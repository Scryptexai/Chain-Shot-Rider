// ---------------------------------------------------------------------------
// BulletController.cs — INTI GAME. Ricochet + bullet riding + trigger slow-mo.
//
// Ini adalah kelas simulasi murni (POCO, bukan MonoBehaviour). Ia dijalankan
// oleh BulletSystem pada langkah tetap 1/60 detik. Tidak ada Rigidbody, tidak
// ada Collider, tidak ada FixedUpdate Unity — sesuai constraint:
//   "Tidak boleh pakai physics engine untuk ricochet" + "harus deterministik".
//
// ===========================================================================
// KEPUTUSAN DESAIN PENTING (baca sebelum mengubah apa pun)
// ===========================================================================
//
// 1. MUSUH BIASA DITEMBUS, MUSUH BERARMOR MEMANTULKAN.
//    Spec menyebut "peluru memantul dari dinding, bumper, dan musuh". Kalau
//    SEMUA musuh memantulkan, peluru akan terpental tiap 0.8 unit di tengah
//    crowd rapat; pemain kehilangan kendali dan bounce budget habis dalam
//    0.2 detik. Maka:
//       - grunt/runner/splitter/bomber  → DITEMBUS (damage, tanpa konsumsi bounce)
//       - brute & shielder (dari depan) → MEMANTULKAN (konsumsi bounce, +combo)
//    Hasilnya: menembus crowd terasa seperti membelah kerumunan, dan musuh
//    berarmor menjadi "bumper hidup" yang dicari pemain untuk menyambung combo.
//
// 2. SPEED-UP TIDAK MENGUBAH JUMLAH SUBSTEP.
//    Substep dihitung dari jarak tempuh per tick supaya peluru cepat tetap
//    tidak tunneling, tapi jumlahnya di-clamp agar frame budget aman.
//
// 3. STEERING MEMUTAR ARAH, BUKAN MENAMBAH VELOCITY.
//    Menjaga kecepatan tetap dalam budget (max 150%) dan membuat kontrol
//    terasa presisi, bukan "licin".
//
// 4. SLOW-MO DIPICU DARI SINI, TAPI DIEKSEKUSI DI SlowMoSystem.
//    BulletController hanya mengirim intent lewat GameEvents. Dengan begitu
//    tidak ada dua sistem yang berebut menulis Time.timeScale.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Core;
using ChainRider.Config;

namespace ChainRider.BulletSim
{
    public sealed class BulletController
    {
        // ---- Data & dependency -------------------------------------------
        public BulletData Data;

        private readonly BulletConfigSO _cfg;
        private readonly SlowMoConfigSO _slowCfg;
        private readonly IArenaQuery _arena;
        private readonly IObstacleQuery _obstacles;
        private readonly ICrowdQuery _crowd;

        /// <summary>Antrian sudut steer dari input (derajat). Diakumulasi antar tick
        /// lalu dikonsumsi dengan rate limit supaya swipe cepat tidak melompat.</summary>
        private float _pendingSteerDeg;

        /// <summary>Guard anti-infinite-loop: maksimum resolve tabrakan per substep.</summary>
        private const int MaxResolvesPerSubstep = 4;

        /// <summary>Umur maksimum peluru (detik simulasi). Jaring pengaman kalau
        /// peluru terjebak pola pantul sempurna yang tak pernah selesai.</summary>
        private const float MaxLifeTime = 12f;

        public bool IsAlive => Data.IsAlive;
        public int Id => Data.Id;

        public BulletController(BulletConfigSO cfg, SlowMoConfigSO slowCfg,
                                IArenaQuery arena, IObstacleQuery obstacles, ICrowdQuery crowd)
        {
            _cfg = cfg;
            _slowCfg = slowCfg;
            _arena = arena;
            _obstacles = obstacles;
            _crowd = crowd;
        }

        // ==================================================================
        // FIRE
        // ==================================================================

        /// <summary>
        /// Mengaktifkan peluru dari pool. Semua field di-reset eksplisit —
        /// jangan pernah mengandalkan nilai default dari pool.
        /// </summary>
        /// <param name="bounceUpgrade">Bonus bounce dari upgrade meta (0..35).</param>
        /// <param name="steerUpgrade">Bonus durasi steer dari upgrade meta (detik).</param>
        public void Fire(int id, Vector3 origin, Vector3 direction, int bounceUpgrade = 0, float steerUpgrade = 0f)
        {
            direction.y = 0f;
            direction.Normalize();

            Data = new BulletData
            {
                Id = id,
                State = BulletState.Flying,
                Position = origin,
                PrevPosition = origin,
                Direction = direction,
                BaseSpeed = _cfg.baseSpeed,
                SpeedMultiplier = 1f,
                DamageBase = _cfg.damageBase,
                DamageMultiplier = 1f,
                BouncesRemaining = Mathf.Min(_cfg.maxBounce + bounceUpgrade, _cfg.maxBounceUpgraded),
                BounceCount = 0,
                SteerRemaining = 0f,                              // steer baru aktif saat Riding
                SteerMeterMax = _cfg.steerMeterDuration + steerUpgrade,
                KillsThisBullet = 0,
                LifeTime = 0f,
            };

            _pendingSteerDeg = 0f;
            GameEvents.RaiseBulletFired(new BulletFiredEvt(id, origin, direction));
        }

        // ==================================================================
        // INPUT
        // ==================================================================

        /// <summary>
        /// Dipanggil InputRouter saat pemain swipe horizontal.
        /// Satu swipe = maksimum <c>steerAnglePerSwipe</c> (15°). Nilai di-akumulasi;
        /// konsumsi aktualnya dibatasi rate di ApplySteering().
        /// </summary>
        public void QueueSteer(float normalizedSwipe)
        {
            if (Data.State != BulletState.Riding || Data.SteerRemaining <= 0f) return;
            float deg = Mathf.Clamp(normalizedSwipe, -1f, 1f) * _cfg.steerAnglePerSwipe;
            _pendingSteerDeg = Mathf.Clamp(_pendingSteerDeg + deg,
                                           -_cfg.steerAnglePerSwipe * 3f,
                                            _cfg.steerAnglePerSwipe * 3f);
        }

        /// <summary>Pemain tap tombol "rem" → peluru berhenti, sisa bounce hangus.</summary>
        public void Brake()
        {
            if (!Data.IsAlive) return;
            Kill(BulletEndReason.PlayerBrake);
        }

        // ==================================================================
        // TICK — dipanggil BulletSystem sekali per langkah simulasi (1/60 s)
        // ==================================================================

        public void Tick(float dt)
        {
            if (!Data.IsAlive) return;

            Data.PrevPosition = Data.Position;
            Data.LifeTime += dt;

            if (Data.LifeTime > MaxLifeTime)
            {
                Kill(BulletEndReason.TimeOut);
                return;
            }

            // --- 1. Steering (hanya saat Riding) ---------------------------
            UpdateSteerMeter(dt);
            ApplySteering(dt);

            // --- 2. Medan non-kontak (gravity well) ------------------------
            Data.Direction = _obstacles.ApplyFields(Data.Position, Data.Direction, dt);

            // --- 3. Tentukan jumlah substep dari jarak tempuh --------------
            // Aturan: satu substep tidak boleh menempuh lebih dari 1 diameter peluru
            // relatif terhadap obstacle terkecil, supaya sweep tidak melewatkan
            // dua tabrakan berurutan yang sangat dekat.
            float travel = Data.Speed * dt;
            int substeps = Mathf.Clamp(Mathf.CeilToInt(travel / 0.5f), 1, _cfg.simulationSubsteps);
            float sdt = dt / substeps;

            for (int s = 0; s < substeps && Data.IsAlive; s++)
                SimulateSubstep(sdt);
        }

        // ------------------------------------------------------------------
        // SUBSTEP
        // ------------------------------------------------------------------

        private void SimulateSubstep(float dt)
        {
            // Sisa gerakan yang belum "terbayar" pada substep ini.
            // Setelah memantul, sisa jarak dilanjutkan pada arah baru — inilah
            // yang membuat pantulan di sudut arena terasa tajam dan benar.
            float remaining = Data.Speed * dt;

            for (int resolve = 0; resolve < MaxResolvesPerSubstep && remaining > 1e-5f; resolve++)
            {
                Vector3 delta = Data.Direction * remaining;

                // ---- a. Sweep terhadap tiga kategori dunia ----------------
                SweepHit wallHit = RicochetSolver.SweepSideWalls(
                    Data.Position, delta, _cfg.radius, _arena.XMin, _arena.XMax, _arena.WallRestitution);

                SweepHit obsHit = _obstacles.SweepObstacles(Data.Position, delta, _cfg.radius);

                // Crowd: memberi damage sepanjang lintasan, mengembalikan hit
                // yang MEMANTULKAN (kalau ada musuh berarmor).
                int kills = _crowd.SweepDamage(Data.Position, delta, _cfg.radius, Data.CurrentDamage,
                                               out bool touchedEnemy, out SweepHit enemyHit);

                if (kills > 0) Data.KillsThisBullet += kills;

                // Kontak pertama dengan musuh mana pun → masuk mode Riding.
                if (touchedEnemy && Data.State == BulletState.Flying)
                    EnterRidingMode();

                // ---- b. Pilih hit paling awal -----------------------------
                SweepHit hit = SweepHit.None;
                float bestT = float.MaxValue;
                if (wallHit.Hit && wallHit.T < bestT) { bestT = wallHit.T; hit = wallHit; }
                if (obsHit.Hit && obsHit.T < bestT) { bestT = obsHit.T; hit = obsHit; }
                if (enemyHit.Hit && enemyHit.T < bestT) { bestT = enemyHit.T; hit = enemyHit; }

                // ---- c. Tidak ada tabrakan: jalan lurus, selesai ----------
                if (!hit.Hit)
                {
                    Data.Position += delta;
                    remaining = 0f;

                    // Keluar lewat atas/bawah arena → peluru mati (bukan pantul).
                    if (Data.Position.z + _cfg.radius < _arena.ZMin ||
                        Data.Position.z - _cfg.radius > _arena.ZMax)
                    {
                        Kill(BulletEndReason.LeftArena);
                    }
                    return;
                }

                // ---- d. Pindah ke titik kontak ----------------------------
                float travelled = remaining * hit.T;
                Data.Position += Data.Direction * travelled;
                remaining -= travelled;

                // Dorong keluar permukaan supaya tidak terjebak di dalam geometri.
                Data.Position += hit.Normal * RicochetSolver.SkinWidth;

                // ---- e. Barrel / shield wall menerima damage --------------
                if (hit.Surface == SurfaceKind.ShieldWall || hit.TargetId >= 0)
                    _obstacles.DamageObstacle(hit.TargetId, Data.CurrentDamage, hit.Point, hit.Normal);

                // ---- f. Resolusi pantulan ---------------------------------
                if (!ResolveBounce(in hit)) return;   // peluru mati di dalam ResolveBounce
            }
        }

        // ------------------------------------------------------------------
        // BOUNCE
        // ------------------------------------------------------------------

        /// <returns>false kalau peluru mati akibat pantulan ini.</returns>
        private bool ResolveBounce(in SweepHit hit)
        {
            // Boss shield menyerap peluru sepenuhnya — aturan eksplisit di GDD.
            if (hit.Surface == SurfaceKind.ShieldWall && Vector3.Dot(Data.Direction, hit.Normal) < 0f)
            {
                // Shield wall hanya bisa dihancurkan dari belakang. Kalau peluru
                // datang dari depan, ia memantul dan TIDAK memberi damage.
                // (DamageObstacle di atas sudah memfilter arah di sisi obstacle.)
            }

            // 1. Konsumsi jatah bounce.
            Data.BouncesRemaining--;
            Data.BounceCount++;

            if (Data.BouncesRemaining < 0)
            {
                Kill(BulletEndReason.BouncesExhausted);
                return false;
            }

            // 2. Hitung arah pantul. ReflectSafe mencegah sudut serempet yang
            //    membuat peluru "menempel" di dinding.
            Data.Direction = RicochetSolver.ReflectSafe(Data.Direction, hit.Normal);

            // 3. Stacking reward.
            //    Damage  +15% per bounce (multiplikatif → mendorong combo panjang).
            //    Speed   +2% per bounce, di-cap 150% agar tetap bisa dikendalikan.
            Data.DamageMultiplier *= _cfg.damagePerBounce;
            Data.SpeedMultiplier = Mathf.Min(Data.SpeedMultiplier * _cfg.speedPerBounce,
                                             _cfg.speedMultiplierCap);

            // Bumper memberi bonus damage kecil sebagai insentif menargetkannya.
            if (hit.Surface == SurfaceKind.Bumper)
                Data.DamageMultiplier *= 1f + _cfg.bumperBonusDamage;

            // 4. Broadcast — VFX, SFX (pitch ladder), camera shake, combo counter
            //    semuanya berlangganan event ini. BulletController tidak tahu
            //    apa pun tentang mereka.
            GameEvents.RaiseBounce(new BounceEvt(
                Data.Id, Data.Position, hit.Normal, Data.BounceCount,
                Data.BouncesRemaining, Data.DamageMultiplier, hit.Surface));

            // 5. Slow-mo pada 3 pantulan terakhir → momen sinematik penutup.
            if (Data.BouncesRemaining <= _slowCfg.finalBounceThreshold && Data.BouncesRemaining > 0)
                RequestSlowMo(_slowCfg.finalBounceTimeScale, SlowMoReason.FinalBounces);

            return true;
        }

        // ------------------------------------------------------------------
        // BULLET RIDING & STEER METER
        // ------------------------------------------------------------------

        /// <summary>
        /// Dipicu saat peluru menyentuh musuh PERTAMA kalinya.
        /// Membuka kontrol steer + meminta bullet time + zoom kamera.
        /// </summary>
        private void EnterRidingMode()
        {
            Data.State = BulletState.Riding;
            Data.SteerRemaining = Data.SteerMeterMax;

            GameEvents.RaiseBulletRidingStarted(Data.Id);
            RequestSlowMo(_slowCfg.crowdTimeScale, SlowMoReason.CrowdEntry);
            GameEvents.RaiseSteerMeter(1f);
        }

        private void UpdateSteerMeter(float dt)
        {
            if (Data.State != BulletState.Riding) return;
            if (Data.SteerRemaining <= 0f) return;

            // CATATAN: dt di sini adalah waktu SIMULASI (1/60), bukan waktu nyata.
            // Artinya slow-mo secara otomatis membuat steer meter terasa lebih
            // lama bagi pemain — ini disengaja, itulah gunanya bullet time.
            Data.SteerRemaining -= dt;

            if (Data.SteerRemaining <= 0f)
            {
                // Steer habis → peluru kembali auto-pantul, bullet time dilepas.
                Data.SteerRemaining = 0f;
                _pendingSteerDeg = 0f;
                GameEvents.RaiseSteerMeter(0f);
                RequestSlowMo(1f, SlowMoReason.None);
            }
            else
            {
                GameEvents.RaiseSteerMeter(Data.SteerRemaining / Data.SteerMeterMax);
            }
        }

        private void ApplySteering(float dt)
        {
            if (Mathf.Abs(_pendingSteerDeg) < 1e-4f) return;
            if (Data.State != BulletState.Riding || Data.SteerRemaining <= 0f)
            {
                _pendingSteerDeg = 0f;
                return;
            }

            // Rate limit: berapa pun cepatnya pemain menggesek, peluru hanya bisa
            // berbelok maksimum steerMaxAnglePerSecond. Ini menjaga lintasan tetap
            // terbaca dan mencegah 180° instan yang merusak feel.
            float maxStep = _cfg.steerMaxAnglePerSecond * dt;
            float step = Mathf.Clamp(_pendingSteerDeg, -maxStep, maxStep);
            _pendingSteerDeg -= step;

            Data.Direction = RicochetSolver.RotateXZ(Data.Direction, step);
        }

        // ------------------------------------------------------------------
        // SLOW-MO REQUEST
        // ------------------------------------------------------------------

        private void RequestSlowMo(float targetScale, SlowMoReason reason)
        {
            // Hanya kirim intent. SlowMoSystem yang memutuskan prioritas kalau ada
            // beberapa permintaan bersamaan (mis. ledakan + bounce terakhir).
            GameEvents.RaiseSlowMo(new SlowMoEvt(targetScale, reason));
        }

        // ------------------------------------------------------------------
        // DEATH
        // ------------------------------------------------------------------

        public void Kill(BulletEndReason reason)
        {
            if (Data.State == BulletState.Inactive || Data.State == BulletState.Expiring) return;

            Data.State = BulletState.Expiring;
            _pendingSteerDeg = 0f;

            // Kembalikan waktu ke normal — kalau peluru ini yang memegang bullet time.
            RequestSlowMo(1f, SlowMoReason.None);
            GameEvents.RaiseSteerMeter(0f);
            GameEvents.RaiseBulletExpired(Data.Id);

            LastEndReason = reason;
        }

        public BulletEndReason LastEndReason { get; private set; }

        /// <summary>Dipanggil BulletSystem setelah VFX kematian selesai.</summary>
        public void Recycle()
        {
            Data.State = BulletState.Inactive;
        }

        // ------------------------------------------------------------------
        // RENDER HELPER
        // ------------------------------------------------------------------

        /// <summary>
        /// Posisi untuk render pada frame ini. Simulasi berjalan 60 Hz; layar bisa
        /// 90/120 Hz. Interpolasi mencegah stutter tanpa mengorbankan determinisme.
        /// </summary>
        public Vector3 GetRenderPosition(float alpha) =>
            Vector3.LerpUnclamped(Data.PrevPosition, Data.Position, alpha);
    }
}
