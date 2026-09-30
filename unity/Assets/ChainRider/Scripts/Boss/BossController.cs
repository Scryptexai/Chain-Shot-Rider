using UnityEngine;
using ChainRider.Core;
using ChainRider.Obstacles;

namespace ChainRider.Boss
{
    /// <summary>Pola serang boss. Satu pola per varian arena (docs/10).</summary>
    public enum BossPattern
    {
        SlowDescendSlam,     // Colossus      — Classic Pit
        MirrorPairSidestep,  // Twin Warden   — Twin Towers
        OrbitPullPulse,      // Singularity   — Gravity Chamber
        BarrelDropCharge,    // Pyro Baron    — Explosive Yard
        TeleportLaneSwap,    // Shifter       — Moving Maze
    }

    /// <summary>
    /// Satu bagian boss. Twin Warden punya dua bagian, sisanya satu.
    /// Struct-like class supaya bisa dirujuk hasil sweep tanpa menyalin.
    /// </summary>
    public sealed class BossPart
    {
        public float X, Z;
        public float Hp, MaxHp;
        public float Radius;
        public float ShieldAngle;    // radian, arah perisai menghadap
        public float HitFlash;       // detik tersisa untuk kedip putih
        public bool Alive = true;
        public float DeadAt = -1f;   // waktu boss-lokal saat mati (untuk revive)
    }

    /// <summary>
    /// BossController — boss wave 5, satu per varian arena.
    ///
    /// ATURAN DESAIN
    /// 1. TANPA PHYSICS. Posisi digerakkan aritmetika murni; tabrakan peluru
    ///    diselesaikan lewat RicochetSolver.SweepCircle seperti rintangan lain.
    /// 2. Boss SELALU memantulkan peluru — secara mekanis ia adalah bumper
    ///    raksasa. Yang dikendalikan perisai adalah apakah damage MASUK, bukan
    ///    apakah peluru memantul. Ini menjaga chain tetap hidup saat boss fight:
    ///    kalau boss menyerap peluru, setiap tembakan ke boss akan mematikan
    ///    chain dan terasa seperti hukuman.
    /// 3. Deterministik: semua keacakan lewat DeterministicRng milik run,
    ///    tidak pernah UnityEngine.Random.
    /// 4. Boss menembus garis pertahanan = kalah langsung. Boss tidak "bocor"
    ///    satu nyawa seperti musuh biasa; ia adalah kondisi gagal.
    ///
    /// Terverifikasi di harness: boss tercapai pada 30/30 run, durasi rata-rata
    /// 105 detik, determinisme tetap identik di 5 varian (tools/sim_test.js).
    /// </summary>
    public sealed class BossController
    {
        // ------------------------------------------------------------------
        // STATE
        // ------------------------------------------------------------------

        public BossPattern Pattern { get; private set; }
        public string BossId { get; private set; }
        public BossPart[] Parts { get; private set; }

        /// <summary>HP total awal — dipakai untuk mengisi bar boss di HUD.</summary>
        public float TotalMaxHp { get; private set; }

        /// <summary>HP total saat ini.</summary>
        public float TotalHp
        {
            get
            {
                float sum = 0f;
                for (int i = 0; i < Parts.Length; i++) sum += Mathf.Max(0f, Parts[i].Hp);
                return sum;
            }
        }

        public bool IsDefeated
        {
            get
            {
                for (int i = 0; i < Parts.Length; i++) if (Parts[i].Alive) return false;
                return true;
            }
        }

        /// <summary>True kalau boss sedang membuka perisai (dipakai VFX + audio).</summary>
        public bool Vulnerable { get; private set; } = true;

        private float _t;              // umur boss fight, detik simulasi
        private float _nextAction = 2f;
        private float _phase;          // timer serbaguna per pola

        private ObstacleField _obstacles;
        private float _defenseLineZ;

        // ==================================================================
        // SETUP
        // ==================================================================

        public void Spawn(string bossId, BossPattern pattern, float hp,
                          ObstacleField obstacles, float defenseLineZ)
        {
            BossId = bossId;
            Pattern = pattern;
            _obstacles = obstacles;
            _defenseLineZ = defenseLineZ;
            _t = 0f;
            _nextAction = 2f;
            _phase = 0f;
            Vulnerable = true;

            if (pattern == BossPattern.MirrorPairSidestep)
            {
                Parts = new[]
                {
                    new BossPart { X = -4f, Z = 34f, Hp = hp, MaxHp = hp, Radius = 1.8f, ShieldAngle = Mathf.PI },
                    new BossPart { X =  4f, Z = 34f, Hp = hp, MaxHp = hp, Radius = 1.8f, ShieldAngle = Mathf.PI },
                };
            }
            else
            {
                Parts = new[]
                {
                    new BossPart { X = 0f, Z = 34f, Hp = hp, MaxHp = hp, Radius = 2.4f, ShieldAngle = Mathf.PI },
                };
            }

            TotalMaxHp = 0f;
            for (int i = 0; i < Parts.Length; i++) TotalMaxHp += Parts[i].MaxHp;

            GameEvents.RaiseBossSpawned(BossId, TotalMaxHp);
        }

        // ==================================================================
        // TICK SIMULASI
        // ==================================================================

        /// <summary>
        /// Dipanggil dari ArenaManager.SimulateTick, SEBELUM BulletSystem.Tick
        /// (urutan sama seperti crowd: pemindahan target dulu, baru sweep peluru,
        /// supaya peluru tidak pernah menabrak posisi boss yang basi).
        /// </summary>
        public void Tick(float dt, ref DeterministicRng rng)
        {
            if (Parts == null || IsDefeated) return;

            _t += dt;
            for (int i = 0; i < Parts.Length; i++)
                if (Parts[i].HitFlash > 0f) Parts[i].HitFlash -= dt;

            switch (Pattern)
            {
                case BossPattern.SlowDescendSlam:    TickColossus(dt);        break;
                case BossPattern.MirrorPairSidestep: TickTwinWarden(dt);      break;
                case BossPattern.OrbitPullPulse:     TickSingularity(dt);     break;
                case BossPattern.BarrelDropCharge:   TickPyroBaron(dt);       break;
                case BossPattern.TeleportLaneSwap:   TickShifter(dt, ref rng); break;
            }

            // Boss menembus garis pertahanan = kalah langsung.
            for (int i = 0; i < Parts.Length; i++)
            {
                if (Parts[i].Alive && Parts[i].Z <= _defenseLineZ + 1f)
                {
                    GameEvents.RaiseBossBreached();
                    return;
                }
            }
        }

        // --- COLOSSUS: turun lambat, slam berkala, perisai terbuka setelah slam ---
        private void TickColossus(float dt)
        {
            BossPart p = Parts[0];
            p.Z -= 0.22f * dt;

            _nextAction -= dt;
            if (_nextAction <= 0f)
            {
                _nextAction = 4.0f;
                _phase = 1.5f;                       // jendela rentan 1.5 detik
                GameEvents.RaiseExplosion(new ExplosionEvt
                {
                    Position = new Vector3(p.X, 0f, p.Z - 2f),
                    Radius = 4.5f,
                    Damage = 0f,                     // slam hanya telegraf + shake
                });
            }

            _phase -= dt;
            Vulnerable = _phase > 0f;
        }

        // --- TWIN WARDEN: gerak cermin; yang mati bangkit kalau pasangannya hidup 3 detik ---
        private void TickTwinWarden(float dt)
        {
            for (int i = 0; i < Parts.Length; i++)
            {
                BossPart p = Parts[i];
                if (!p.Alive) continue;
                float dir = i == 0 ? -1f : 1f;
                p.X = dir * 4f + dir * Mathf.Sin(_t * 1.1f) * 3.2f;
                p.Z = 33f - Mathf.Sin(_t * 0.5f) * 1.5f;
            }

            bool anyAlive = false;
            for (int i = 0; i < Parts.Length; i++) if (Parts[i].Alive) anyAlive = true;
            if (!anyAlive) return;

            for (int i = 0; i < Parts.Length; i++)
            {
                BossPart p = Parts[i];
                if (p.Alive || p.DeadAt < 0f) continue;
                if (_t - p.DeadAt > 3f)
                {
                    // Hukuman karena tidak membunuh keduanya dalam 3 detik.
                    p.Alive = true;
                    p.Hp = p.MaxHp * 0.3f;
                    p.DeadAt = -1f;
                    GameEvents.RaiseBossRevived(BossId);
                }
            }
            Vulnerable = true;
        }

        // --- SINGULARITY: mengorbit, perisai berputar; rentan dari sisi berlawanan ---
        private void TickSingularity(float dt)
        {
            BossPart p = Parts[0];
            p.X = Mathf.Sin(_t * 0.7f) * 5.5f;
            p.Z = 28f + Mathf.Cos(_t * 0.7f) * 3f;
            p.ShieldAngle = Mathf.Repeat(_t * 1.3f, Mathf.PI * 2f);
            Vulnerable = true;   // keputusan sebenarnya per-arah di ApplyDamage
        }

        // --- PYRO BARON: menjatuhkan barrel lalu charge ---
        private void TickPyroBaron(float dt)
        {
            BossPart p = Parts[0];

            _nextAction -= dt;
            if (_nextAction <= 0f)
            {
                _nextAction = 3.5f;
                _obstacles.SpawnBarrel(new Vector3(p.X, 0f, p.Z - 3f));
                _phase = 1.2f;
            }

            if (_phase > 0f) { _phase -= dt; p.Z -= 3.2f * dt; }   // charge
            else if (p.Z < 33f) p.Z += 1.4f * dt;                  // mundur

            p.X = Mathf.Clamp(p.X + Mathf.Sin(_t * 0.9f) * 2.4f * dt, -7f, 7f);
            Vulnerable = true;
        }

        // --- SHIFTER: teleport antar lajur; hanya rentan dari belakang ---
        private void TickShifter(float dt, ref DeterministicRng rng)
        {
            BossPart p = Parts[0];

            _nextAction -= dt;
            if (_nextAction <= 0f)
            {
                _nextAction = 2.5f;
                // RNG run — bukan UnityEngine.Random — supaya replay identik.
                float[] lanes = { -6f, 0f, 6f };
                p.X = lanes[rng.Range(0, 3)];
                GameEvents.RaiseBossTeleported(new Vector3(p.X, 0f, p.Z));
            }

            p.Z = 32f + Mathf.Sin(_t * 0.8f) * 1.2f;
            Vulnerable = true;   // keputusan sebenarnya per-arah di ApplyDamage
        }

        // ==================================================================
        // DAMAGE
        // ==================================================================

        /// <summary>
        /// Menerapkan damage dengan aturan perisai per pola.
        /// Dipanggil BulletSystem setelah sweep mengenai boss. Peluru TETAP
        /// memantul walau damage ditolak — lihat aturan desain 2 di ringkasan kelas.
        /// </summary>
        /// <param name="incomingDir">Arah gerak peluru saat menumbuk.</param>
        /// <returns>True kalau damage masuk (untuk memilih SFX/VFX).</returns>
        public bool ApplyDamage(BossPart part, float damage, Vector3 incomingDir)
        {
            if (part == null || !part.Alive) return false;

            bool allowed = Vulnerable;

            if (Pattern == BossPattern.OrbitPullPulse)
            {
                // Rentan kalau peluru datang dari sisi berlawanan arah perisai.
                float inc = Mathf.Atan2(-incomingDir.z, -incomingDir.x);
                float d = Mathf.Abs(Mathf.DeltaAngle(inc * Mathf.Rad2Deg,
                                                     part.ShieldAngle * Mathf.Rad2Deg));
                allowed = d > 90f;
            }
            else if (Pattern == BossPattern.TeleportLaneSwap)
            {
                // Hanya dari BELAKANG: peluru harus sedang bergerak turun.
                allowed = incomingDir.z < -0.15f;
            }

            if (!allowed)
            {
                part.HitFlash = 0.1f;
                GameEvents.RaiseBossShieldBlocked(new Vector3(part.X, 0f, part.Z));
                return false;
            }

            part.Hp -= damage;
            part.HitFlash = 0.15f;

            if (part.Hp <= 0f)
            {
                part.Alive = false;
                part.DeadAt = _t;
                GameEvents.RaiseExplosion(new ExplosionEvt
                {
                    Position = new Vector3(part.X, 0f, part.Z),
                    Radius = 6f,
                    Damage = 60f,
                });
                GameEvents.RaiseBossPartKilled(BossId, IsDefeated);
            }

            GameEvents.RaiseBossHealthChanged(TotalHp / TotalMaxHp);
            return true;
        }
    }
}
