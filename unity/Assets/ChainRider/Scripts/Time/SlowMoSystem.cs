// ---------------------------------------------------------------------------
// SlowMoSystem.cs — Satu-satunya pemilik "kecepatan waktu".
//
// KENAPA TIDAK PAKAI Time.timeScale SECARA LANGSUNG?
// Karena kita punya simulasi fixed-step sendiri. Kalau Time.timeScale diubah:
//   - FixedUpdate Unity ikut berubah (kita tidak memakainya, tapi plugin lain bisa)
//   - Partikel & animasi melambat (INI YANG KITA MAU)
//   - Simulasi kita TIDAK boleh ikut melambat ukurannya, hanya frekuensinya
//
// Maka polanya:
//   - Time.timeScale diset untuk keperluan VISUAL (partikel, Animator, tween)
//   - ArenaManager memakai TimeScale property untuk mengatur berapa tick
//     simulasi yang dijalankan per detik nyata
//   - Semua transisi memakai UNSCALED time, kalau tidak transisi ke slow-mo
//     akan ikut melambat dan terasa seperti hang
//
// PRIORITAS: kalau beberapa sistem meminta slow-mo bersamaan, yang PALING
// LAMBAT menang, dan permintaan "kembali normal" hanya diterima dari sumber
// yang levelnya sama atau lebih tinggi. Ini mencegah ledakan barrel mematikan
// bullet time yang sedang berjalan.
// ---------------------------------------------------------------------------

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using ChainRider.Core;
using ChainRider.Config;

namespace ChainRider.TimeSys
{
    public sealed class SlowMoSystem : MonoBehaviour
    {
        [Header("Post-processing")]
        [SerializeField] private Volume _normalVolume;
        [SerializeField] private Volume _bulletTimeVolume;

        [Header("Audio")]
        [SerializeField] private UnityEngine.Audio.AudioMixer _mixer;
        [SerializeField] private string _musicVolumeParam = "MusicVolume";
        [SerializeField] private string _lowPassParam = "MusicLowPass";

        private SlowMoConfigSO _cfg;

        // ---- State --------------------------------------------------------
        private float _currentScale = 1f;
        private float _targetScale = 1f;
        private SlowMoReason _activeReason = SlowMoReason.None;
        private float _blend;               // 0 = normal, 1 = bullet time penuh
        private float _holdTimer;           // slow-mo paksa (ForceTimeScale)

        /// <summary>Skala waktu efektif. ArenaManager mengalikan ini dengan
        /// unscaledDeltaTime untuk menentukan jumlah tick simulasi.</summary>
        public float TimeScale => _currentScale;

        public bool IsSlowMotion => _currentScale < 0.95f;

        public void Init(SlowMoConfigSO cfg)
        {
            _cfg = cfg;
            _currentScale = _targetScale = 1f;
            _blend = 0f;
            _activeReason = SlowMoReason.None;
            ApplyVisuals(0f);
        }

        private void OnEnable() => GameEvents.OnSlowMoChanged += HandleRequest;
        private void OnDisable()
        {
            GameEvents.OnSlowMoChanged -= HandleRequest;
            Time.timeScale = 1f;               // jangan tinggalkan game dalam slow-mo
        }

        // ==================================================================
        // REQUEST HANDLING
        // ==================================================================

        private void HandleRequest(SlowMoEvt e)
        {
            if (_holdTimer > 0f) return;       // sedang di-force, abaikan request

            // Permintaan melambat: selalu diterima kalau lebih lambat dari saat ini.
            if (e.TargetTimeScale < _targetScale - 0.001f)
            {
                _targetScale = Mathf.Max(e.TargetTimeScale, _cfg.minFixedDeltaScale);
                _activeReason = e.Reason;
                return;
            }

            // Permintaan kembali normal: hanya diterima dari pemilik state saat ini
            // (atau saat request-nya eksplisit "None" = peluru mati).
            if (e.Reason == SlowMoReason.None || e.Reason == _activeReason)
            {
                _targetScale = Mathf.Clamp01(e.TargetTimeScale);
                if (_targetScale >= 0.999f) _activeReason = SlowMoReason.None;
            }
        }

        /// <summary>
        /// Memaksa slow-mo untuk durasi tertentu, mengabaikan request lain.
        /// Dipakai untuk momen sinematik: last bullet, boss kill, akhir run.
        /// </summary>
        public void ForceTimeScale(float scale, float duration)
        {
            _targetScale = Mathf.Clamp(scale, _cfg.minFixedDeltaScale, 1f);
            _holdTimer = duration;
            _activeReason = SlowMoReason.LastBullet;
        }

        /// <summary>
        /// Pulse singkat: melambat lalu langsung kembali. Dipakai untuk
        /// bounce milestone tiap 5 pantulan — terasa "ketuk" tanpa mengganggu ritme.
        /// </summary>
        public void Pulse(float scale, float duration) => ForceTimeScale(scale, duration);

        // ==================================================================
        // UPDATE (unscaled — wajib)
        // ==================================================================

        public void RenderUpdate(float unscaledDt)
        {
            if (_holdTimer > 0f)
            {
                _holdTimer -= unscaledDt;
                if (_holdTimer <= 0f) _targetScale = 1f;
            }

            // Transisi eksponensial: frame-rate independent, tanpa overshoot.
            float k = 1f - Mathf.Exp(-(3f / Mathf.Max(0.01f, _cfg.transitionDuration)) * unscaledDt);
            _currentScale = Mathf.Lerp(_currentScale, _targetScale, k);
            if (Mathf.Abs(_currentScale - _targetScale) < 0.002f) _currentScale = _targetScale;

            // timeScale Unity hanya untuk VISUAL (partikel, Animator, tween).
            // Simulasi gameplay tidak membacanya sama sekali.
            Time.timeScale = _currentScale;
            Time.fixedDeltaTime = 0.02f * _currentScale;   // jaga-jaga untuk sistem pihak ketiga

            // Blend 0..1 dipetakan dari rentang [crowdTimeScale .. 1].
            _blend = Mathf.InverseLerp(1f, _cfg.crowdTimeScale, _currentScale);
            ApplyVisuals(_blend);
            ApplyAudio(_blend);
        }

        // ==================================================================
        // VISUAL & AUDIO
        // ==================================================================

        /// <summary>
        /// Blend dua Volume Profile lewat weight — JAUH lebih murah daripada
        /// mengubah parameter override satu per satu tiap frame (yang memicu
        /// rebuild stack post-processing dan mengalokasikan memori).
        /// </summary>
        private void ApplyVisuals(float blend)
        {
            if (_normalVolume != null) _normalVolume.weight = 1f - blend;
            if (_bulletTimeVolume != null) _bulletTimeVolume.weight = blend;
        }

        /// <summary>
        /// Ducking: musik turun dan di-low-pass saat slow-mo, supaya SFX bounce
        /// dan heartbeat menonjol. Ini setengah dari "rasa" slow-mo — sisanya visual.
        /// </summary>
        private void ApplyAudio(float blend)
        {
            if (_mixer == null) return;

            float duckDb = Mathf.Lerp(0f, _cfg.audioDuckDb, blend);
            _mixer.SetFloat(_musicVolumeParam, duckDb);

            // Low-pass: 22000 Hz (terbuka) → 1200 Hz (teredam, "di dalam air").
            float cutoff = Mathf.Lerp(22000f, 1200f, blend);
            _mixer.SetFloat(_lowPassParam, cutoff);

            // Pitch musik ikut melambat sedikit — jangan penuh 0.3× karena akan
            // terdengar rusak. 0.85× sudah cukup memberi kesan waktu melar.
            AudioListener.pause = false;
        }

        private void OnApplicationPause(bool paused)
        {
            if (paused) Time.timeScale = 0f;
            else Time.timeScale = _currentScale;
        }
    }
}
