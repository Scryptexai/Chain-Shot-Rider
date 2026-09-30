// ---------------------------------------------------------------------------
// CameraRig.cs — Follow, zoom (bullet time), shake, framing clamp.
//
// Kamera adalah alat BACA, bukan alat pamer. Tiga aturan keras:
//   1. Player dan garis pertahanan HARUS selalu terlihat. Kalau kamera mau
//      mengejar peluru sampai melanggar ini, ia di-clamp.
//   2. Kamera tidak pernah mengikuti peluru 1:1. Ia melakukan dolly parsial
//      (LOOK_WEIGHT) supaya pemain tetap punya konteks arena saat bullet riding.
//   3. Semua gerakan kamera berjalan di waktu NYATA (unscaled), bukan waktu
//      simulasi. Kalau tidak, zoom bullet time akan ikut melambat 0.3× dan
//      terasa seperti lag, bukan sinematik.
//
// Skeleton ini memakai kamera manual. Kalau memakai Cinemachine, petakan:
//   _targetFov          → CinemachineVirtualCamera.m_Lens.FieldOfView
//   ComputeDesiredPos   → CinemachineTransposer offset
//   Shake()             → CinemachineImpulseSource.GenerateImpulse()
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Core;
using ChainRider.Config;
using ChainRider.BulletSim;

namespace ChainRider.CameraSys
{
    public enum ShakeKind : byte { BounceSmall, BounceBig, Explosion, ComboMilestone }

    public sealed class CameraRig : MonoBehaviour
    {
        [Header("Refs")]
        [SerializeField] private Camera _camera;
        [SerializeField] private Transform _player;
        [SerializeField] private CameraConfigSO _cfg;

        [Header("Framing guard")]
        [SerializeField] private float _defenseLineZ = 5f;
        [SerializeField] private float _minVisibleMarginZ = 2f;

        // ---- State --------------------------------------------------------
        private Vector3 _basePosition;      // posisi tanpa shake
        private Quaternion _baseRotation;
        private float _currentFov;
        private float _targetFov;
        private float _bulletWeight;        // 0 = fokus player, 1 = fokus peluru
        private float _targetBulletWeight;

        // ---- Shake ---------------------------------------------------------
        private float _shakeAmp, _shakeFreq, _shakeTimeLeft, _shakeDuration;
        private float _shakeSeed;

        public Vector3 Position => _basePosition;

        private void Awake()
        {
            if (_camera == null) _camera = GetComponent<Camera>();
            _currentFov = _targetFov = _cfg.fovNormal;
            _camera.fieldOfView = _currentFov;
            _shakeSeed = Random.value * 100f;   // kosmetik → boleh Random biasa
            _baseRotation = Quaternion.Euler(_cfg.pitchDegrees, _cfg.yawDegrees, 0f);
            transform.rotation = _baseRotation;
        }

        private void OnEnable()
        {
            GameEvents.OnSlowMoChanged += HandleSlowMo;
            GameEvents.OnBulletRidingStarted += HandleRidingStarted;
            GameEvents.OnBulletExpired += HandleBulletExpired;
            GameEvents.OnExplosion += HandleExplosion;
        }

        private void OnDisable()
        {
            GameEvents.OnSlowMoChanged -= HandleSlowMo;
            GameEvents.OnBulletRidingStarted -= HandleRidingStarted;
            GameEvents.OnBulletExpired -= HandleBulletExpired;
            GameEvents.OnExplosion -= HandleExplosion;
        }

        // ==================================================================
        // UPDATE (dipanggil ArenaManager, memakai waktu NYATA)
        // ==================================================================

        public void RenderUpdate(float unscaledDt, BulletController ridingBullet)
        {
            // --- 1. Tentukan titik fokus -------------------------------------
            Vector3 focus = _player.position + Vector3.forward * _cfg.lookAheadZ;

            if (ridingBullet != null && ridingBullet.IsAlive)
            {
                // Dolly parsial: kamera bergerak sebagian menuju peluru.
                Vector3 bulletPos = ridingBullet.Data.Position;
                focus = Vector3.Lerp(focus, bulletPos, _bulletWeight * _cfg.bulletFocusWeight);
            }

            // --- 2. Posisi ideal berdasarkan pitch & jarak --------------------
            Vector3 desired = ComputeDesiredPos(focus);

            // --- 3. Clamp framing: garis pertahanan wajib terlihat ------------
            desired = ClampFraming(desired);

            // --- 4. Smoothing -------------------------------------------------
            float lerp = ridingBullet != null ? _cfg.bulletFollowLerp : _cfg.followLerp;
            _basePosition = Vector3.Lerp(_basePosition, desired, 1f - Mathf.Exp(-lerp * unscaledDt));

            // --- 5. FOV: 60 normal → 40 saat bullet time ----------------------
            // Exponential smoothing = frame-rate independent, tidak seperti
            // Lerp(a, b, 0.1f) yang berbeda hasilnya di 30 vs 120 FPS.
            float fovLerp = 1f - Mathf.Exp(-(1f / Mathf.Max(0.01f, _cfg.fovTransitionDuration)) * 3f * unscaledDt);
            _currentFov = Mathf.Lerp(_currentFov, _targetFov, fovLerp);
            _camera.fieldOfView = _currentFov;

            _bulletWeight = Mathf.Lerp(_bulletWeight, _targetBulletWeight, fovLerp);

            // --- 6. Shake (aditif, tidak mengubah _basePosition) --------------
            Vector3 shakeOffset = EvaluateShake(unscaledDt);
            transform.SetPositionAndRotation(_basePosition + shakeOffset, _baseRotation);
        }

        private Vector3 ComputeDesiredPos(Vector3 focus)
        {
            // Kamera berada di belakang & di atas titik fokus, miring ke bawah.
            float pitchRad = _cfg.pitchDegrees * Mathf.Deg2Rad;
            float back = Mathf.Cos(pitchRad) * _cfg.distance;
            float up = Mathf.Sin(pitchRad) * _cfg.distance;

            return new Vector3(
                focus.x * _cfg.horizontalFollowWeight,   // 0.35 → kamera tidak geser penuh
                up + _cfg.heightOffset * 0f,
                focus.z - back);
        }

        /// <summary>
        /// Menjamin garis pertahanan tetap di dalam frustum. Kalau kamera terlalu
        /// jauh ke depan mengejar peluru, tarik mundur.
        /// </summary>
        private Vector3 ClampFraming(Vector3 desired)
        {
            float halfFovRad = _currentFov * 0.5f * Mathf.Deg2Rad;
            float pitchRad = _cfg.pitchDegrees * Mathf.Deg2Rad;

            // Perkiraan konservatif batas bawah frustum pada bidang lantai.
            float groundNear = desired.z + desired.y / Mathf.Tan(pitchRad + halfFovRad);
            float maxZ = _defenseLineZ - _minVisibleMarginZ - (groundNear - desired.z);

            if (desired.z > maxZ) desired.z = maxZ;
            return desired;
        }

        // ==================================================================
        // SHAKE
        // ==================================================================

        /// <summary>
        /// Shake berbasis Perlin noise, bukan Random. Perlin menghasilkan gerakan
        /// kontinu (tidak "berkedip") dan bisa di-decay dengan mulus.
        /// </summary>
        public void Shake(ShakeKind kind)
        {
            ShakeProfile p = kind switch
            {
                ShakeKind.BounceSmall => _cfg.bounceSmall,
                ShakeKind.BounceBig => _cfg.bounceBig,
                ShakeKind.Explosion => _cfg.explosion,
                _ => _cfg.comboMilestone,
            };

            // Shake tidak menumpuk tak terbatas — ambil yang paling kuat.
            if (p.amplitude < _shakeAmp * (_shakeTimeLeft / Mathf.Max(0.001f, _shakeDuration)))
                return;

            _shakeAmp = p.amplitude;
            _shakeFreq = p.frequency;
            _shakeDuration = p.duration;
            _shakeTimeLeft = p.duration;
        }

        private Vector3 EvaluateShake(float unscaledDt)
        {
            if (_shakeTimeLeft <= 0f) return Vector3.zero;

            _shakeTimeLeft -= unscaledDt;
            float t = Mathf.Clamp01(_shakeTimeLeft / _shakeDuration);
            float decay = t * t;                       // quadratic ease-out
            float time = Time.unscaledTime * _shakeFreq;

            return new Vector3(
                (Mathf.PerlinNoise(_shakeSeed, time) - 0.5f) * 2f,
                (Mathf.PerlinNoise(_shakeSeed + 13.7f, time) - 0.5f) * 2f,
                0f) * (_shakeAmp * decay);
        }

        // ==================================================================
        // EVENT HANDLERS
        // ==================================================================

        private void HandleSlowMo(SlowMoEvt e)
        {
            // FOV mengikuti state waktu: makin lambat waktu, makin sempit FOV.
            bool inBulletTime = e.TargetTimeScale < 0.95f;
            _targetFov = inBulletTime ? _cfg.fovBulletTime : _cfg.fovNormal;

            if (e.Reason == SlowMoReason.LastBullet)
                _targetFov = _cfg.fovBulletTime - 6f;    // zoom ekstra sinematik
        }

        private void HandleRidingStarted(int bulletId) => _targetBulletWeight = 1f;

        private void HandleBulletExpired(int bulletId)
        {
            _targetBulletWeight = 0f;
            _targetFov = _cfg.fovNormal;
        }

        private void HandleExplosion(ExplosionEvt e) => Shake(ShakeKind.Explosion);

        // ==================================================================
        // THEME
        // ==================================================================

        public void ApplyTheme(VariantSO variant)
        {
            _camera.backgroundColor = variant.bgBottom;
            RenderSettings.ambientSkyColor = variant.bgTop;
        }
    }
}
