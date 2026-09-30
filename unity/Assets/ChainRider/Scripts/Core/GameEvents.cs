// ---------------------------------------------------------------------------
// GameEvents.cs — Event bus statis, zero-allocation.
//
// Alasan desain:
//   - UI, audio, dan VFX TIDAK boleh melakukan polling state gameplay tiap frame
//     (boros + bikin coupling). Mereka subscribe ke event ini.
//   - Payload memakai STRUCT readonly, bukan class, supaya tidak ada alokasi heap
//     (target: no GC spike selama run, lihat testing checklist).
//   - Semua listener WAJIB unsubscribe di OnDisable. Ada guard di editor.
// ---------------------------------------------------------------------------

using System;
using UnityEngine;

namespace ChainRider.Core
{
    #region Payloads (struct — tidak mengalokasikan heap)

    public readonly struct BulletFiredEvt
    {
        public readonly int BulletId;
        public readonly Vector3 Origin;
        public readonly Vector3 Direction;
        public BulletFiredEvt(int id, Vector3 origin, Vector3 dir)
        { BulletId = id; Origin = origin; Direction = dir; }
    }

    public readonly struct BounceEvt
    {
        public readonly int BulletId;
        public readonly Vector3 Point;
        public readonly Vector3 Normal;
        public readonly int BounceIndex;      // pantulan ke-berapa (1-based)
        public readonly int BouncesRemaining;
        public readonly float DamageMultiplier;
        public readonly SurfaceKind Surface;
        public BounceEvt(int id, Vector3 p, Vector3 n, int idx, int remaining, float dmgMul, SurfaceKind surface)
        { BulletId = id; Point = p; Normal = n; BounceIndex = idx; BouncesRemaining = remaining; DamageMultiplier = dmgMul; Surface = surface; }
    }

    public readonly struct EnemyKilledEvt
    {
        public readonly int EnemyId;
        public readonly byte TypeId;
        public readonly Vector3 Position;
        public readonly int ScoreAwarded;
        public readonly int ComboAtKill;
        public EnemyKilledEvt(int id, byte type, Vector3 pos, int score, int combo)
        { EnemyId = id; TypeId = type; Position = pos; ScoreAwarded = score; ComboAtKill = combo; }
    }

    public readonly struct ComboEvt
    {
        public readonly int Combo;
        public readonly bool IsMilestone;
        public ComboEvt(int combo, bool milestone) { Combo = combo; IsMilestone = milestone; }
    }

    public readonly struct WaveEvt
    {
        public readonly int WaveIndex;        // 0-based
        public readonly int EnemyCount;
        public readonly FormationKind Formation;
        public WaveEvt(int idx, int count, FormationKind formation)
        { WaveIndex = idx; EnemyCount = count; Formation = formation; }
    }

    public readonly struct ExplosionEvt
    {
        public readonly Vector3 Position;
        public readonly float Radius;
        public readonly int ChainDepth;       // 0 = ledakan pertama; >0 = chain
        public ExplosionEvt(Vector3 pos, float radius, int depth)
        { Position = pos; Radius = radius; ChainDepth = depth; }
    }

    public readonly struct SlowMoEvt
    {
        public readonly float TargetTimeScale;
        public readonly SlowMoReason Reason;
        public SlowMoEvt(float target, SlowMoReason reason)
        { TargetTimeScale = target; Reason = reason; }
    }

    public readonly struct PlayerDamagedEvt
    {
        public readonly int LivesRemaining;
        public readonly Vector3 BreachPosition;
        public PlayerDamagedEvt(int lives, Vector3 pos) { LivesRemaining = lives; BreachPosition = pos; }
    }

    public readonly struct RunEndedEvt
    {
        public readonly bool Victory;
        public readonly int Score;
        public readonly int TotalKills;
        public readonly int BestCombo;
        public readonly int Coins;
        public RunEndedEvt(bool victory, int score, int kills, int bestCombo, int coins)
        { Victory = victory; Score = score; TotalKills = kills; BestCombo = bestCombo; Coins = coins; }
    }

    public enum SurfaceKind : byte { Wall = 0, Bumper = 1, Pillar = 2, Enemy = 3, ShieldWall = 4, Platform = 5, Boss = 6 }
    public enum SlowMoReason : byte { None = 0, CrowdEntry = 1, FinalBounces = 2, LastBullet = 3, BossKill = 4 }
    public enum FormationKind : byte { Rect = 0, VShape = 1, Diamond = 2, Line = 3, Circle = 4 }

    #endregion

    public static class GameEvents
    {
        // --- Bullet ---
        public static event Action<BulletFiredEvt> OnBulletFired;
        public static event Action<BounceEvt> OnBounce;
        public static event Action<int> OnBulletExpired;          // payload: bulletId
        public static event Action<int> OnBulletRidingStarted;    // payload: bulletId
        public static event Action<float> OnSteerMeterChanged;    // payload: 0..1

        // --- Crowd ---
        public static event Action<EnemyKilledEvt> OnEnemyKilled;
        public static event Action<Vector3> OnEnemyNearMiss;      // musuh 0.5u dari garis
        public static event Action<Vector3> OnEnemyBreached;      // musuh lewat garis

        // --- Meta ---
        public static event Action<ComboEvt> OnCombo;
        public static event Action<int> OnScoreChanged;
        public static event Action<WaveEvt> OnWaveStarted;
        public static event Action<int> OnWaveCleared;
        public static event Action<ExplosionEvt> OnExplosion;
        public static event Action<SlowMoEvt> OnSlowMoChanged;
        public static event Action<PlayerDamagedEvt> OnPlayerDamaged;
        public static event Action OnPerfectClear;
        public static event Action<RunEndedEvt> OnRunEnded;

        // --- Boss (wave 5) ---
        public static event Action<string, float> OnBossSpawned;      // bossId, maxHp
        public static event Action<float> OnBossHealthChanged;        // 0..1
        public static event Action<Vector3> OnBossShieldBlocked;      // perisai menahan damage
        public static event Action<Vector3> OnBossTeleported;
        public static event Action<string> OnBossRevived;
        public static event Action<string, bool> OnBossPartKilled;    // bossId, seluruhnya tumbang
        public static event Action OnBossBreached;                    // boss lewat garis = kalah

        // --- Raise helpers (null-safe, inline) ---
        public static void RaiseBulletFired(in BulletFiredEvt e) => OnBulletFired?.Invoke(e);
        public static void RaiseBounce(in BounceEvt e) => OnBounce?.Invoke(e);
        public static void RaiseBulletExpired(int id) => OnBulletExpired?.Invoke(id);
        public static void RaiseBulletRidingStarted(int id) => OnBulletRidingStarted?.Invoke(id);
        public static void RaiseSteerMeter(float n01) => OnSteerMeterChanged?.Invoke(n01);
        public static void RaiseEnemyKilled(in EnemyKilledEvt e) => OnEnemyKilled?.Invoke(e);
        public static void RaiseEnemyNearMiss(Vector3 p) => OnEnemyNearMiss?.Invoke(p);
        public static void RaiseEnemyBreached(Vector3 p) => OnEnemyBreached?.Invoke(p);

        public static void RaiseBossSpawned(string id, float maxHp) => OnBossSpawned?.Invoke(id, maxHp);
        public static void RaiseBossHealthChanged(float n01) => OnBossHealthChanged?.Invoke(n01);
        public static void RaiseBossShieldBlocked(Vector3 p) => OnBossShieldBlocked?.Invoke(p);
        public static void RaiseBossTeleported(Vector3 p) => OnBossTeleported?.Invoke(p);
        public static void RaiseBossRevived(string id) => OnBossRevived?.Invoke(id);
        public static void RaiseBossPartKilled(string id, bool all) => OnBossPartKilled?.Invoke(id, all);
        public static void RaiseBossBreached() => OnBossBreached?.Invoke();
        public static void RaiseCombo(in ComboEvt e) => OnCombo?.Invoke(e);
        public static void RaiseScore(int score) => OnScoreChanged?.Invoke(score);
        public static void RaiseWaveStarted(in WaveEvt e) => OnWaveStarted?.Invoke(e);
        public static void RaiseWaveCleared(int idx) => OnWaveCleared?.Invoke(idx);
        public static void RaiseExplosion(in ExplosionEvt e) => OnExplosion?.Invoke(e);
        public static void RaiseSlowMo(in SlowMoEvt e) => OnSlowMoChanged?.Invoke(e);
        public static void RaisePlayerDamaged(in PlayerDamagedEvt e) => OnPlayerDamaged?.Invoke(e);
        public static void RaisePerfectClear() => OnPerfectClear?.Invoke();
        public static void RaiseRunEnded(in RunEndedEvt e) => OnRunEnded?.Invoke(e);

        /// <summary>
        /// Wajib dipanggil saat keluar dari scene arena. Static event bertahan
        /// antar scene reload di Unity dan akan memegang referensi ke objek mati
        /// (memory leak + NullReference saat domain reload dimatikan).
        /// </summary>
        public static void ClearAll()
        {
            OnBulletFired = null; OnBounce = null; OnBulletExpired = null;
            OnBulletRidingStarted = null; OnSteerMeterChanged = null;
            OnEnemyKilled = null; OnEnemyNearMiss = null; OnEnemyBreached = null;
            OnCombo = null; OnScoreChanged = null; OnWaveStarted = null;
            OnWaveCleared = null; OnExplosion = null; OnSlowMoChanged = null;
            OnPlayerDamaged = null; OnPerfectClear = null; OnRunEnded = null;
        }
    }
}
