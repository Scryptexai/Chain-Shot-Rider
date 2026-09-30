// ---------------------------------------------------------------------------
// EnemyData.cs — Data musuh dalam bentuk struct (SoA-friendly).
//
// 200+ musuh aktif × MonoBehaviour per musuh = mimpi buruk performa:
// 200 Update() call, 200 Transform write, cache miss di mana-mana.
// Karena itu musuh di game ini BUKAN GameObject. Mereka adalah entri di dalam
// array struct; renderingnya memakai GPU instancing (satu draw call per tipe).
//
// Struktur ini blittable → siap dipindah ke NativeArray + Burst tanpa rewrite.
// ---------------------------------------------------------------------------

using UnityEngine;

namespace ChainRider.Crowd
{
    public enum EnemyType : byte
    {
        Grunt = 0,
        Runner = 1,
        Brute = 2,
        Shielder = 3,
        Splitter = 4,
        Bomber = 5,
        Boss = 6,
    }

    [System.Flags]
    public enum EnemyFlags : byte
    {
        None = 0,
        Alive = 1 << 0,
        Armored = 1 << 1,   // memantulkan peluru, bukan ditembus
        ExplodeOnDeath = 1 << 2,
        SplitOnDeath = 1 << 3,
        NearMissFired = 1 << 4,   // sudah memicu SFX heartbeat, jangan ulangi
    }

    public struct EnemyData
    {
        public int Id;
        public EnemyType Type;
        public EnemyFlags Flags;

        public Vector3 Position;
        public Vector3 PrevPosition;
        public Vector3 Velocity;        // hasil descend + sway + separation

        public float Hp;
        public float MaxHp;
        public float Speed;
        public float Radius;

        public float SwayPhase;         // offset fase sway, diacak deterministik
        public int FormationIndex;      // untuk formasi & efek gelombang

        public readonly bool IsAlive => (Flags & EnemyFlags.Alive) != 0;
        public readonly bool IsArmored => (Flags & EnemyFlags.Armored) != 0;
    }

    /// <summary>Statistik per tipe musuh. Dimuat dari arena_config.json.</summary>
    [System.Serializable]
    public struct EnemyStats
    {
        public EnemyType type;
        public float hp;
        public float speed;
        public float radius;
        public int score;
        public Color color;
        public bool armored;
        public bool explodeOnDeath;
        public bool splitOnDeath;
        public float explosionRadius;
        public float explosionDamage;
    }
}
