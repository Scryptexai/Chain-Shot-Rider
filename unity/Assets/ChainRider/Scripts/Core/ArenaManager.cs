// ---------------------------------------------------------------------------
// ArenaManager.cs — Orkestrator run. Wave, win/lose, skor, combo, event.
//
// Ini satu-satunya tempat yang men-drive langkah simulasi. Semua sistem lain
// TIDAK punya Update() yang menyentuh state gameplay. Alasannya determinisme:
// urutan eksekusi harus eksplisit dan tidak bergantung pada Script Execution
// Order milik Unity.
//
// URUTAN SATU TICK SIMULASI (1/60 detik):
//     1. InputRouter.ConsumeTick(tick)   → input untuk tick ini (dari live/replay)
//     2. Obstacles.Tick(dt)              → platform bergerak, well berdenyut
//     3. CrowdManager.Tick(dt)           → gerak musuh + rebuild spatial grid
//     4. BulletSystem.Tick(dt)           → sweep peluru (baca grid yang fresh)
//     5. WaveLogic.Tick(dt)              → timer wave, kondisi menang/kalah
//     6. SimClock.CommitTick()
//
// Di luar tick, pada tiap frame render:
//     SlowMoSystem.RenderUpdate → CrowdManager.RenderCrowd → BulletSystem.SyncViews
//     → CameraRig.RenderUpdate → HUD
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Config;
using ChainRider.Crowd;
using ChainRider.BulletSim;
using ChainRider.Obstacles;
using ChainRider.CameraSys;
using ChainRider.TimeSys;
using ChainRider.InputSys;

namespace ChainRider.Core
{
    public enum RunState : byte { Boot, Ready, Playing, BossFight, Victory, Defeat, Paused }

    public sealed class ArenaManager : MonoBehaviour
    {
        [Header("Config")]
        [SerializeField] private ArenaConfigSO _arenaCfg;
        [SerializeField] private SpawnConfigSO _spawnCfg;
        [SerializeField] private BulletConfigSO _bulletCfg;
        [SerializeField] private SlowMoConfigSO _slowCfg;
        [SerializeField] private VariantSO[] _variants;

        [Header("Systems")]
        [SerializeField] private CrowdManager _crowd;
        [SerializeField] private BulletSystem _bullets;
        [SerializeField] private ObstacleField _obstacleField;
        [SerializeField] private CameraRig _cameraRig;
        [SerializeField] private SlowMoSystem _slowMo;
        [SerializeField] private InputRouter _input;
        [SerializeField] private ChainRider.InputSys.AimController _aim;

        /// <summary>Boss wave 5. Null sampai wave terakhir dimulai.</summary>
        private ChainRider.Boss.BossController _boss;
        public ChainRider.Boss.BossController Boss => _boss;
        [SerializeField] private ArenaBounds _bounds;

        [Header("Run")]
        [SerializeField] private int _seed = 20260929;
        [SerializeField] private int _variantIndex = 0;

        // ---- State --------------------------------------------------------
        private readonly SimClock _clock = new();
        private RunState _state = RunState.Boot;

        /// <summary>
        /// RNG milik run. SATU-SATUNYA sumber keacakan yang boleh memengaruhi
        /// simulasi (spawn, pola boss). Efek kosmetik boleh memakai
        /// UnityEngine.Random karena tidak menyentuh state simulasi.
        /// </summary>
        private DeterministicRng _rng;

        /// <summary>Varian yang sedang dimainkan — dipakai saat memunculkan boss.</summary>
        private VariantSO _variant;

        private int _waveIndex = -1;
        private float _waveTimer;
        private bool _waveActive;

        private int _score;
        private int _combo;
        private int _bestCombo;
        private int _totalKills;
        private int _lives;
        private int _coins;
        private bool _perfectRun = true;
        private float _invulTimer;

        public RunState State => _state;
        public SimClock Clock => _clock;
        public int Score => _score;
        public int Combo => _combo;
        public int Lives => _lives;
        public int WaveNumber => _waveIndex + 1;

        // ==================================================================
        // LIFECYCLE
        // ==================================================================

        private void Awake()
        {
            Application.targetFrameRate = 60;
            QualitySettings.vSyncCount = 0;
        }

        private void OnEnable() => SubscribeEvents();
        private void OnDisable() => UnsubscribeEvents();

        private void Start() => Boot(_seed, _variantIndex);

        /// <summary>Menyiapkan satu run. Seed + variantIndex = reproducible run.</summary>
        public void Boot(int seed, int variantIndex)
        {
            _seed = seed;
            _variantIndex = Mathf.Clamp(variantIndex, 0, _variants.Length - 1);
            VariantSO variant = _variants[_variantIndex];
            _variant = variant;
            _rng = new DeterministicRng(seed);
            _boss = null;

            _clock.Reset();

            // 1. Bangun arena sesuai varian (obstacle, tema warna, layer musik).
            _obstacleField.BuildVariant(variant, _bounds);
            _cameraRig.ApplyTheme(variant);

            // 2. Init sistem. Urutan penting: crowd dulu (menyiapkan grid),
            //    baru bullet (butuh referensi ICrowdQuery).
            _crowd.Init(seed);
            _obstacleField.SetCrowd(_crowd);          // barrel butuh ini untuk ExplodeAt
            IArenaQuery arenaQuery = _bounds != null
                ? (IArenaQuery)_bounds
                : new ArenaQueryAdapter(_arenaCfg);
            _bullets.Init(arenaQuery, _obstacleField, _crowd);
            _slowMo.Init(_slowCfg);
            _input.Init(_bullets);

            // 3. Reset state run.
            _score = 0; _combo = 0; _bestCombo = 0; _totalKills = 0;
            _coins = 0; _perfectRun = true; _invulTimer = 0f;
            _lives = _arenaCfg.playerLives;
            _waveIndex = -1;
            _waveTimer = 1.5f;      // jeda sebelum wave pertama
            _waveActive = false;

            _state = RunState.Playing;
            GameEvents.RaiseScore(0);
        }

        // ==================================================================
        // MAIN LOOP
        // ==================================================================

        private void Update()
        {
            if (_state != RunState.Playing && _state != RunState.BossFight) return;

            // Slow-mo memengaruhi BERAPA BANYAK tick yang jalan, bukan ukurannya.
            float scaled = Time.unscaledDeltaTime * _slowMo.TimeScale;
            int steps = _clock.Advance(scaled);

            for (int i = 0; i < steps; i++)
                SimulateTick(SimClock.FixedDelta);

            // --- Frame render (tidak memengaruhi state simulasi) ----------
            float alpha = _clock.InterpolationAlpha;
            _slowMo.RenderUpdate(Time.unscaledDeltaTime);
            _crowd.RenderCrowd(alpha, _cameraRig.Position);
            _bullets.SyncViews(alpha);
            _cameraRig.RenderUpdate(Time.unscaledDeltaTime, _bullets.RidingBullet);
            if (_aim != null) _aim.RenderIndicator(_bullets.RidingBullet != null);
        }

        private void SimulateTick(float dt)
        {
            _input.ConsumeTick(_clock.Tick);
            if (_aim != null) _aim.Tick(dt);          // sapuan turret, deterministik
            _obstacleField.Tick(dt, _clock.Time);
            _crowd.Tick(dt, _clock.Time);
            if (_boss != null) _boss.Tick(dt, ref _rng);   // boss bergerak sebelum sweep peluru
            _bullets.Tick(dt);
            TickWaveLogic(dt);

            if (_invulTimer > 0f) _invulTimer -= dt;

            _clock.CommitTick();
        }

        // ==================================================================
        // WAVE LOGIC
        // ==================================================================

        private void TickWaveLogic(float dt)
        {
            _waveTimer -= dt;

            // --- Wave selesai: semua musuh mati sebelum timer habis --------
            if (_waveActive && _crowd.IsWaveCleared)
            {
                _waveActive = false;
                GameEvents.RaiseWaveCleared(_waveIndex);

                // Perfect clear: tidak ada satu pun musuh yang lolos garis.
                if (_crowd.LeakedThisWave == 0)
                {
                    _coins += _arenaCfg.perfectClearBonusCoins;
                    GameEvents.RaisePerfectClear();
                }
                else
                {
                    _perfectRun = false;
                }

                // Wave terakhir selesai → menang, TAPI boss harus tumbang juga.
                // Tanpa syarat ini pemain menang hanya dengan membersihkan crowd
                // dan boss jadi dekorasi.
                if (_waveIndex >= _spawnCfg.waveCount - 1)
                {
                    if (_boss == null || _boss.IsDefeated)
                    {
                        EndRun(victory: true);
                        return;
                    }
                    // Crowd habis tapi boss masih hidup: biarkan berlanjut.
                }

                // Jeda pendek sebelum wave berikutnya agar juice sempat bermain.
                _waveTimer = Mathf.Min(_waveTimer, 2.0f);
            }

            // --- Spawn wave berikutnya -------------------------------------
            if (_waveTimer <= 0f && _waveIndex < _spawnCfg.waveCount - 1)
            {
                _waveIndex++;
                _crowd.SpawnWave(_waveIndex);
                _waveActive = true;
                _waveTimer = _spawnCfg.spawnInterval[Mathf.Min(_waveIndex, _spawnCfg.spawnInterval.Length - 1)];

                if (_waveIndex == _spawnCfg.waveCount - 1)
                {
                    _state = RunState.BossFight;      // wave terakhir = boss
                    SpawnBoss();
                }
            }
        }

        // ==================================================================
        // BOSS
        // ==================================================================

        /// <summary>
        /// Membuat boss milik varian yang sedang dimainkan. Pemetaan varian→boss
        /// ada di VariantSO (sumbernya Config/arena_config.json), jadi menambah
        /// varian baru tidak perlu mengubah kelas ini.
        /// </summary>
        private void SpawnBoss()
        {
            _boss = new ChainRider.Boss.BossController();
            _boss.Spawn(_variant.bossId, _variant.bossPattern, _variant.bossHp,
                        _obstacleField, _arenaCfg.defenseLineZ);
            _bullets.SetBoss(_boss);
        }

        // ==================================================================
        // EVENT HANDLERS — skor, combo, HP
        // ==================================================================

        /// <summary>Boss menembus garis pertahanan = kalah langsung, bukan -1 nyawa.</summary>
        private void HandleBossBreached()
        {
            _lives = 0;
            EndRun(victory: false);
        }

        private void SubscribeEvents()
        {
            GameEvents.OnEnemyKilled += HandleEnemyKilled;
            GameEvents.OnBounce += HandleBounce;
            GameEvents.OnBulletExpired += HandleBulletExpired;
            GameEvents.OnEnemyBreached += HandleEnemyBreached;
            GameEvents.OnBossBreached += HandleBossBreached;
        }

        private void UnsubscribeEvents()
        {
            GameEvents.OnEnemyKilled -= HandleEnemyKilled;
            GameEvents.OnBounce -= HandleBounce;
            GameEvents.OnBulletExpired -= HandleBulletExpired;
            GameEvents.OnEnemyBreached -= HandleEnemyBreached;
            GameEvents.OnBossBreached -= HandleBossBreached;
        }

        private void HandleEnemyKilled(EnemyKilledEvt e)
        {
            _totalKills++;
            _combo++;
            if (_combo > _bestCombo) _bestCombo = _combo;

            // Skor = skor dasar musuh × multiplier combo.
            // Multiplier tumbuh pelan (0.15/combo) supaya angka tetap terbaca
            // di layar kecil dan tidak meledak jadi 7 digit di wave 2.
            float mult = 1f + _combo * _arenaCfg.comboMultiplierStep;
            int gained = Mathf.RoundToInt(e.ScoreAwarded * mult);
            _score += gained;

            GameEvents.RaiseScore(_score);

            bool milestone = IsComboMilestone(_combo);
            GameEvents.RaiseCombo(new ComboEvt(_combo, milestone));

            if (IsKillMilestone(_totalKills))
            {
                _score += 500;
                _coins += 10;
                GameEvents.RaiseScore(_score);
            }
        }

        private void HandleBounce(BounceEvt e)
        {
            // Bounce milestone tiap 5 pantulan → flash + pulse slow-mo.
            if (e.BounceIndex % _arenaCfg.bounceMilestoneEvery == 0)
                _cameraRig.Shake(ShakeKind.ComboMilestone);
            else
                _cameraRig.Shake(e.BounceIndex > 8 ? ShakeKind.BounceBig : ShakeKind.BounceSmall);
        }

        private void HandleBulletExpired(int bulletId)
        {
            // Combo reset saat peluru habis TANPA kill baru. Ini yang membuat
            // pemain berpikir sebelum menembak, bukan spam tap.
            _combo = 0;
            GameEvents.RaiseCombo(new ComboEvt(0, false));
        }

        private void HandleEnemyBreached(Vector3 pos)
        {
            if (_invulTimer > 0f) return;

            _lives -= _arenaCfg.damagePerLeakedEnemy;
            _invulTimer = _arenaCfg.invulnerabilityAfterHit;
            _perfectRun = false;

            GameEvents.RaisePlayerDamaged(new PlayerDamagedEvt(_lives, pos));
            _cameraRig.Shake(ShakeKind.Explosion);

            if (_lives <= 0) EndRun(victory: false);
        }

        private bool IsComboMilestone(int combo)
        {
            int[] m = _arenaCfg.comboMilestones;
            for (int i = 0; i < m.Length; i++) if (m[i] == combo) return true;
            return false;
        }

        private bool IsKillMilestone(int kills)
        {
            int[] m = _arenaCfg.killMilestones;
            for (int i = 0; i < m.Length; i++) if (m[i] == kills) return true;
            return false;
        }

        // ==================================================================
        // END RUN
        // ==================================================================

        private void EndRun(bool victory)
        {
            _state = victory ? RunState.Victory : RunState.Defeat;
            _slowMo.ForceTimeScale(victory ? 0.35f : 0.2f, 0.4f);
            if (_perfectRun) _coins += _arenaCfg.perfectClearBonusCoins * 2;

            GameEvents.RaiseRunEnded(new RunEndedEvt(victory, _score, _totalKills, _bestCombo, _coins));
        }

        public void Restart() => Boot(_seed, _variantIndex);
        public void RestartWithNewSeed() => Boot(_seed + 1, _variantIndex);

        private void OnDestroy()
        {
            // Wajib: static event bus akan menahan referensi ke objek mati.
            GameEvents.ClearAll();
        }
    }

    /// <summary>Adapter kalau ArenaBounds tidak dipakai (mis. unit test headless).</summary>
    public sealed class ArenaQueryAdapter : BulletSim.IArenaQuery
    {
        private readonly ArenaConfigSO _cfg;
        public ArenaQueryAdapter(ArenaConfigSO cfg) => _cfg = cfg;
        public float XMin => -_cfg.width * 0.5f;
        public float XMax => _cfg.width * 0.5f;
        public float ZMin => 0f;
        public float ZMax => _cfg.height;
        public float WallRestitution => _cfg.wallRestitution;
        public bool TopAbsorbsBullet => _cfg.topAbsorbsBullet;
    }
}
