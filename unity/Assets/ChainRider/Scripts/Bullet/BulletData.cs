// ---------------------------------------------------------------------------
// BulletData.cs — State peluru + kontrak dunia yang di-query peluru.
//
// BulletData sengaja dibuat STRUCT blittable (hanya field nilai, tanpa referensi)
// supaya:
//   1. Tidak ada alokasi heap saat menembak (no GC spike).
//   2. Bisa dipindah ke NativeArray<BulletData> + IJobParallelFor tanpa rewrite
//      kalau nanti jumlah peluru aktif naik (multi-shot upgrade).
//   3. Bisa di-snapshot untuk replay/rewind.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Core;

namespace ChainRider.BulletSim
{
    public enum BulletState : byte
    {
        Inactive = 0,
        Flying = 1,     // sudah ditembak, belum menyentuh musuh
        Riding = 2,     // sudah kena musuh pertama → bullet time + steer aktif
        Expiring = 3,   // sedang memainkan efek kematian, tidak lagi disimulasi
    }

    public struct BulletData
    {
        public int Id;
        public BulletState State;

        public Vector3 Position;
        public Vector3 Direction;      // selalu ternormalisasi, y = 0
        public Vector3 PrevPosition;   // untuk interpolasi render & trail

        public float BaseSpeed;        // dari config (25)
        public float SpeedMultiplier;  // 1.00 → max 1.50
        public float DamageBase;       // dari config (10)
        public float DamageMultiplier; // 1.00, ×1.15 tiap bounce

        public int BouncesRemaining;
        public int BounceCount;        // total bounce yang sudah terjadi
        public float SteerRemaining;   // detik, hanya berkurang saat Riding
        public float SteerMeterMax;

        public int KillsThisBullet;
        public float LifeTime;         // detik simulasi sejak ditembak

        public readonly float Speed => BaseSpeed * SpeedMultiplier;
        public readonly Vector3 Velocity => Direction * Speed;
        public readonly float CurrentDamage => DamageBase * DamageMultiplier;
        public readonly bool IsAlive => State == BulletState.Flying || State == BulletState.Riding;
    }

    /// <summary>Alasan peluru berhenti — dipakai untuk memilih SFX/VFX & analytics.</summary>
    public enum BulletEndReason : byte
    {
        BouncesExhausted = 0,
        LeftArena = 1,
        BossShield = 2,
        PlayerBrake = 3,
        TimeOut = 4,
    }

    // -----------------------------------------------------------------------
    // KONTRAK DUNIA
    // Peluru tidak boleh tahu tentang MonoBehaviour, collider, atau scene.
    // Ia hanya bertanya ke tiga interface ini. Ini membuat BulletController
    // bisa di-unit-test tanpa Unity (penting untuk verifikasi determinisme).
    // -----------------------------------------------------------------------

    /// <summary>Dinding & zona arena.</summary>
    public interface IArenaQuery
    {
        float XMin { get; }
        float XMax { get; }
        float ZMin { get; }
        float ZMax { get; }
        float WallRestitution { get; }

        /// <summary>
        /// false = dinding atas memantulkan peluru (spawn_gate_bumper).
        /// Musuh tetap masuk lewat gerbang itu; hanya peluru yang memantul.
        /// </summary>
        bool TopAbsorbsBullet { get; }
    }

    /// <summary>Obstacle statis & dinamis (bumper, pillar, barrel, platform, shield, well).</summary>
    public interface IObstacleQuery
    {
        /// <summary>Sweep semua obstacle, kembalikan hit paling awal.</summary>
        SweepHit SweepObstacles(Vector3 from, Vector3 delta, float radius);

        /// <summary>Terapkan medan non-kontak (gravity well) ke arah peluru.</summary>
        Vector3 ApplyFields(Vector3 position, Vector3 direction, float dt);

        /// <summary>Beri damage ke obstacle yang bisa hancur (barrel, shield wall).</summary>
        void DamageObstacle(int obstacleId, float damage, Vector3 hitPoint, Vector3 hitNormal);
    }

    /// <summary>Kerumunan musuh. Implementasi ada di CrowdManager (spatial grid).</summary>
    public interface ICrowdQuery
    {
        /// <summary>
        /// Sapu segmen gerak peluru terhadap crowd.
        /// Memberi damage ke SEMUA musuh yang tersentuh (peluru menembus crowd biasa),
        /// dan mengembalikan hit pertama yang bersifat MEMANTULKAN (musuh berarmor:
        /// brute / shielder dari depan). Lihat catatan desain di BulletController.
        /// </summary>
        /// <returns>Jumlah musuh yang terbunuh oleh sapuan ini.</returns>
        int SweepDamage(Vector3 from, Vector3 delta, float radius, float damage,
                        out bool touchedAnyEnemy, out SweepHit reflectiveHit);

        /// <summary>Damage area (ledakan barrel/bomber).</summary>
        int ExplodeAt(Vector3 center, float radius, float damage, int chainDepth);
    }
}
