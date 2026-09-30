// ---------------------------------------------------------------------------
// ConfigSO.cs — Semua ScriptableObject konfigurasi.
//
// Sumber kebenaran tetap Config/arena_config.json. ConfigImporter (editor tool)
// membaca JSON itu dan menulis nilainya ke aset-aset di bawah ini. Tujuannya:
//   - designer bisa tweak lewat Inspector
//   - build tetap punya satu file data yang bisa di-diff di Git
//   - server/analytics bisa membaca JSON yang sama
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Core;

namespace ChainRider.Config
{
    [CreateAssetMenu(menuName = "ChainRider/Arena Config", fileName = "ArenaConfig")]
    public sealed class ArenaConfigSO : ScriptableObject
    {
        [Header("Dimensi (unit dunia)")]
        public float width = 20f;
        public float height = 40f;
        public float playerZone = 5f;
        public float combatZone = 25f;
        public float spawnZone = 10f;
        public float defenseLineZ = 5f;
        public float nearMissBandZ = 0.5f;
        public float wallRestitution = 0.95f;

        [Tooltip("false = dinding atas (spawn gate) MEMANTULKAN peluru; musuh tetap masuk lewat sana.")]
        public bool topAbsorbsBullet = false;

        [Header("Player")]
        public int playerLives = 3;
        public int damagePerLeakedEnemy = 1;
        public float invulnerabilityAfterHit = 1f;

        [Header("Scoring")]
        public float comboMultiplierStep = 0.15f;
        public int[] comboMilestones = { 10, 20, 50, 100 };
        public int[] killMilestones = { 50, 100, 200 };
        public int bounceMilestoneEvery = 5;
        public int perfectClearBonusCoins = 50;
    }

    [CreateAssetMenu(menuName = "ChainRider/Bullet Config", fileName = "BulletConfig")]
    public sealed class BulletConfigSO : ScriptableObject
    {
        [Header("Gerak")]
        public float baseSpeed = 25f;
        public float radius = 0.18f;
        [Tooltip("Substep maksimum per tick. Lebih tinggi = lebih presisi, lebih mahal.")]
        public int simulationSubsteps = 4;

        [Header("Bounce")]
        public int maxBounce = 15;
        public int maxBounceUpgraded = 50;
        public float damagePerBounce = 1.15f;
        public float speedPerBounce = 1.02f;
        public float speedMultiplierCap = 1.5f;
        public float bumperBonusDamage = 0.05f;

        [Header("Damage")]
        public float damageBase = 10f;

        [Header("Steering")]
        public float steerAnglePerSwipe = 15f;
        public float steerMaxAnglePerSecond = 90f;
        public float steerMeterDuration = 3f;

        [Header("Amunisi (tidak ada reload manual)")]
        public int magazine = 5;
        public float autoReloadDelay = 0.35f;
    }

    [CreateAssetMenu(menuName = "ChainRider/Spawn Config", fileName = "SpawnConfig")]
    public sealed class SpawnConfigSO : ScriptableObject
    {
        [Header("Wave")]
        public int waveCount = 5;
        public int[] enemiesPerWave = { 30, 50, 80, 120, 200 };
        public float[] spawnInterval = { 10f, 12f, 15f, 18f, 20f };
        public FormationKind[] formation =
        {
            FormationKind.Rect, FormationKind.VShape, FormationKind.Diamond,
            FormationKind.Rect, FormationKind.Circle
        };

        [Header("Formasi")]
        public int columnsMin = 5;
        public int columnsMax = 12;
        public float spacing = 0.8f;

        [Header("Gerak crowd")]
        public float swayAmplitude = 0.35f;
        public float swayFrequency = 0.6f;
        public float separationRadius = 0.7f;
        public float separationWeight = 1f;
        public float alignmentWeight = 0.25f;
        public float cohesionWeight = 0.1f;

        [Header("Budget")]
        public int maxActiveEnemies = 260;
        public int poolSize = 500;
    }

    [CreateAssetMenu(menuName = "ChainRider/SlowMo Config", fileName = "SlowMoConfig")]
    public sealed class SlowMoConfigSO : ScriptableObject
    {
        public float crowdTimeScale = 0.3f;
        public float finalBounceTimeScale = 0.15f;
        public int finalBounceThreshold = 3;
        public float transitionDuration = 0.2f;
        [Tooltip("Batas bawah keras. Di bawah ini game terasa hang, bukan sinematik.")]
        public float minFixedDeltaScale = 0.15f;
        public float audioDuckDb = -6f;
    }

    [System.Serializable]
    public struct ShakeProfile
    {
        public float amplitude;
        public float frequency;
        public float duration;
    }

    [CreateAssetMenu(menuName = "ChainRider/Camera Config", fileName = "CameraConfig")]
    public sealed class CameraConfigSO : ScriptableObject
    {
        [Header("Rig")]
        public float pitchDegrees = 40f;
        public float yawDegrees = 0f;
        public float distance = 18f;
        public float heightOffset = 12f;
        public float lookAheadZ = 6f;

        [Header("Follow")]
        public float followLerp = 8f;
        public float bulletFollowLerp = 14f;
        [Range(0f, 1f)] public float horizontalFollowWeight = 0.35f;
        [Range(0f, 1f)] public float bulletFocusWeight = 0.6f;

        [Header("FOV")]
        public float fovNormal = 60f;
        public float fovBulletTime = 40f;
        public float fovTransitionDuration = 0.2f;

        [Header("Shake")]
        public ShakeProfile bounceSmall = new() { amplitude = 0.08f, frequency = 22f, duration = 0.10f };
        public ShakeProfile bounceBig = new() { amplitude = 0.22f, frequency = 18f, duration = 0.18f };
        public ShakeProfile explosion = new() { amplitude = 0.35f, frequency = 14f, duration = 0.28f };
        public ShakeProfile comboMilestone = new() { amplitude = 0.18f, frequency = 20f, duration = 0.22f };
    }

    [System.Serializable]
    /// <summary>
    /// Aiming configuration. Source: Config/arena_config.json -> "aim".
    /// Mode was chosen by measurement, see docs/12-aim-mode-comparison.md.
    /// </summary>
    [CreateAssetMenu(menuName = "ChainRider/Aim Config", fileName = "AimConfig")]
    public sealed class AimConfigSO : ScriptableObject
    {
        public InputSys.AimMode mode = InputSys.AimMode.Manual;

        [Header("Limits")]
        public float maxAngleDeg = 58f;
        public int indicatorBounces = 2;

        [Header("Manual mode")]
        [Tooltip("Degrees covered by dragging across the full screen width.")]
        public float dragFullWidthDeg = 116f;

        [Header("Sweep mode (accessibility option)")]
        public float sweepSpeedDegPerSec = 75f;
    }

    public struct ObstaclePlacement
    {
        public ObstacleKind kind;
        public Vector2 positionXZ;     // x = X dunia, y = Z dunia
        public float radius;
        public float width;
        public float travel;
        public float speed;
        public float phase;
        public float force;
    }

    public enum ObstacleKind : byte
    {
        Bumper = 0, Pillar = 1, Barrel = 2, GravityWell = 3, MovingPlatform = 4, ShieldWall = 5
    }

    [CreateAssetMenu(menuName = "ChainRider/Arena Variant", fileName = "SO_Variant")]
    public sealed class VariantSO : ScriptableObject
    {
        public string variantId = "classic_pit";
        public string displayName = "Classic Pit";
        [TextArea] public string description;

        [Header("Tema")]
        public Color primary = new(0f, 0.898f, 1f);
        public Color enemyColor = new(1f, 0.302f, 0.239f);
        public Color bumperColor = new(0.694f, 0.302f, 1f);
        public Color bgTop = new(0.039f, 0.063f, 0.188f);
        public Color bgBottom = new(0.012f, 0.024f, 0.059f);
        public Color gridColor = new(0.122f, 0.827f, 0.910f);

        [Header("Konten")]
        public string musicLayer = "base_synth";
        public Crowd.EnemyType specialEnemy = Crowd.EnemyType.Runner;
        public string bossId = "colossus";
        public Boss.BossPattern bossPattern = Boss.BossPattern.SlowDescendSlam;
        public float bossHp = 1200f;

        [Header("Layout")]
        public ObstaclePlacement[] obstacles;
    }
}
