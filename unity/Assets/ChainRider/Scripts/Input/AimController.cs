using UnityEngine;
using ChainRider.Bullet;
using ChainRider.Core;

namespace ChainRider.Input
{
    /// <summary>
    /// AimController — turret menyapu kiri-kanan terus-menerus; tap menembak
    /// pada sudut saat itu.
    ///
    /// KENAPA ADA (deviasi spec yang disengaja, berbasis pengukuran):
    /// Spec awal menembakkan peluru lurus ke depan (dz = 1, dx = 0). Instrumentasi
    /// pada prototipe menunjukkan konsekuensinya fatal:
    ///   - rata-rata bounce per peluru = 0.10 (peluru tidak pernah kena dinding samping)
    ///   - hanya 7 dari 63 peluru pernah menyentuh crowd
    ///   - peluru hanya menyapu 1 kolom: 3 dari 30 musuh yang punya |x| < 0.56
    /// Artinya fantasi inti game (ricochet + bullet riding) mekanis mustahil terjadi.
    ///
    /// Sapuan otomatis memperbaiki itu TANPA menambah kontrol: pemain tetap
    /// memakai satu jempol dan satu gestur ("tap = tembak"). Tidak ada joystick,
    /// tidak ada drag-to-aim, konsisten dengan batasan portrait 1 jempol.
    ///
    /// Determinisme: sudut hanya bergerak di dalam tick simulasi ber-delta tetap,
    /// jadi seed + urutan InputFrame yang sama selalu menghasilkan sudut yang sama.
    /// Jangan pernah memajukan sudut ini dari Update()/render.
    /// </summary>
    public sealed class AimController : MonoBehaviour
    {
        // ------------------------------------------------------------------
        // KONFIGURASI (sumber: Config/arena_config.json -> blok "aim")
        // ------------------------------------------------------------------

        [Tooltip("Kecepatan sapuan turret, derajat per detik simulasi.")]
        [SerializeField] private float _sweepSpeedDegPerSec = 75f;

        [Tooltip("Sudut maksimum dari sumbu Z, kiri dan kanan.")]
        [SerializeField] private float _maxAngleDeg = 58f;

        [Tooltip("Berapa pantulan yang digambar garis bidik.")]
        [SerializeField] private int _indicatorBounces = 2;

        [SerializeField] private Transform _muzzle;
        [SerializeField] private LineRenderer _indicator;

        // ------------------------------------------------------------------
        // STATE SIMULASI
        // ------------------------------------------------------------------

        /// <summary>Sudut turret saat ini, derajat. 0 = lurus ke +Z.</summary>
        public float AngleDeg { get; private set; }

        /// <summary>Arah sapuan: +1 ke kanan, -1 ke kiri.</summary>
        private int _sweepDir = 1;

        /// <summary>Arah tembak ternormalisasi pada sudut saat ini.</summary>
        public Vector3 Direction
        {
            get
            {
                float r = AngleDeg * Mathf.Deg2Rad;
                return new Vector3(Mathf.Sin(r), 0f, Mathf.Cos(r));
            }
        }

        // Buffer garis bidik — dialokasikan sekali, nol GC per frame.
        private Vector3[] _pathBuffer;
        private ArenaBounds _bounds;
        private float _bulletRadius;
        private bool _topAbsorbs;

        // ==================================================================
        // LIFECYCLE
        // ==================================================================

        public void Init(ArenaBounds bounds, float bulletRadius, bool topAbsorbs,
                         float sweepSpeedDegPerSec, float maxAngleDeg, int indicatorBounces)
        {
            _bounds = bounds;
            _bulletRadius = bulletRadius;
            _topAbsorbs = topAbsorbs;
            _sweepSpeedDegPerSec = sweepSpeedDegPerSec;
            _maxAngleDeg = maxAngleDeg;
            _indicatorBounces = indicatorBounces;

            // +2: titik muzzle + satu titik ujung setelah pantulan terakhir.
            _pathBuffer = new Vector3[_indicatorBounces + 2];
            AngleDeg = 0f;
            _sweepDir = 1;
        }

        /// <summary>Reset di awal run supaya replay selalu mulai dari sudut yang sama.</summary>
        public void ResetAim()
        {
            AngleDeg = 0f;
            _sweepDir = 1;
        }

        // ==================================================================
        // TICK SIMULASI — dipanggil dari ArenaManager.SimulateTick
        // ==================================================================

        /// <summary>
        /// Memajukan sapuan turret. Ping-pong di batas: sudut di-clamp lalu arah
        /// dibalik, sehingga tidak pernah melewati _maxAngleDeg walau dt besar.
        /// </summary>
        public void Tick(float dt)
        {
            AngleDeg += _sweepDir * _sweepSpeedDegPerSec * dt;

            if (AngleDeg > _maxAngleDeg) { AngleDeg = _maxAngleDeg; _sweepDir = -1; }
            else if (AngleDeg < -_maxAngleDeg) { AngleDeg = -_maxAngleDeg; _sweepDir = 1; }
        }

        // ==================================================================
        // RENDER — garis bidik (tidak memengaruhi state simulasi)
        // ==================================================================

        /// <summary>
        /// Menggambar prediksi lintasan. Disembunyikan saat sedang riding karena
        /// pada saat itu tap berarti "rem", bukan "tembak" — indicator yang tetap
        /// tampil akan membohongi pemain soal apa yang dilakukan tap berikutnya.
        /// </summary>
        public void RenderIndicator(bool isRiding)
        {
            if (_indicator == null) return;

            if (isRiding)
            {
                _indicator.enabled = false;
                return;
            }

            _indicator.enabled = true;
            int n = RicochetSolver.PredictWallPath(
                _muzzle.position, Direction, _bulletRadius,
                _bounds.XMin, _bounds.XMax, _bounds.ZMax,
                _indicatorBounces, _pathBuffer, _topAbsorbs);

            _indicator.positionCount = n;
            for (int i = 0; i < n; i++) _indicator.SetPosition(i, _pathBuffer[i]);
        }
    }
}
