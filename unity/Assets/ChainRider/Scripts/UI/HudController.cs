// ---------------------------------------------------------------------------
// HudController.cs — Binding event bus → UI portrait.
//
// ATURAN ANTI-GC DI UI (penyebab #1 frame spike di game mobile):
//   1. Jangan pernah int.ToString() tiap frame → gunakan tabel string pre-cache
//      untuk angka kecil, dan hanya update saat nilainya BERUBAH.
//   2. Jangan pernah string concatenation di Update.
//   3. Gunakan SetText(char[]/StringBuilder) TextMeshPro, bukan .text = "...".
//   4. Update UI hanya saat event, bukan tiap frame.
// ---------------------------------------------------------------------------

using System.Text;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using ChainRider.Core;

namespace ChainRider.UI
{
    public sealed class HudController : MonoBehaviour
    {
        [Header("Top bar")]
        [SerializeField] private TMP_Text _scoreText;
        [SerializeField] private TMP_Text _comboText;
        [SerializeField] private TMP_Text _waveText;

        [Header("Bottom bar")]
        [SerializeField] private Image _steerMeterFill;
        [SerializeField] private CanvasGroup _steerMeterGroup;
        [SerializeField] private Image[] _ammoIcons;
        [SerializeField] private Image[] _hearts;

        [Header("Overlay")]
        [SerializeField] private ComboPopup _comboPopup;
        [SerializeField] private FloatingTextSpawner _floatingText;
        [SerializeField] private Image _damageFlash;
        [SerializeField] private CanvasGroup _perfectClearBanner;

        private readonly StringBuilder _sb = new(16);
        private static readonly string[] SmallNumbers = BuildSmallNumbers(256);

        private int _lastScore = -1;
        private int _lastCombo = -1;
        private float _steerTarget;
        private float _flashAlpha;

        private static string[] BuildSmallNumbers(int n)
        {
            var arr = new string[n];
            for (int i = 0; i < n; i++) arr[i] = i.ToString();
            return arr;
        }

        private void OnEnable()
        {
            GameEvents.OnScoreChanged += HandleScore;
            GameEvents.OnCombo += HandleCombo;
            GameEvents.OnWaveStarted += HandleWave;
            GameEvents.OnSteerMeterChanged += HandleSteer;
            GameEvents.OnEnemyKilled += HandleKill;
            GameEvents.OnPlayerDamaged += HandleDamaged;
            GameEvents.OnPerfectClear += HandlePerfectClear;
        }

        private void OnDisable()
        {
            GameEvents.OnScoreChanged -= HandleScore;
            GameEvents.OnCombo -= HandleCombo;
            GameEvents.OnWaveStarted -= HandleWave;
            GameEvents.OnSteerMeterChanged -= HandleSteer;
            GameEvents.OnEnemyKilled -= HandleKill;
            GameEvents.OnPlayerDamaged -= HandleDamaged;
            GameEvents.OnPerfectClear -= HandlePerfectClear;
        }

        private void Update()
        {
            // Hanya interpolasi visual — tidak ada logika, tidak ada alokasi.
            if (_steerMeterFill != null)
            {
                float k = 1f - Mathf.Exp(-14f * Time.unscaledDeltaTime);
                _steerMeterFill.fillAmount = Mathf.Lerp(_steerMeterFill.fillAmount, _steerTarget, k);
                if (_steerMeterGroup != null)
                    _steerMeterGroup.alpha = Mathf.Lerp(_steerMeterGroup.alpha, _steerTarget > 0.01f ? 1f : 0.25f, k);
            }

            if (_flashAlpha > 0f && _damageFlash != null)
            {
                _flashAlpha = Mathf.Max(0f, _flashAlpha - Time.unscaledDeltaTime * 2.5f);
                Color c = _damageFlash.color; c.a = _flashAlpha;
                _damageFlash.color = c;
            }
        }

        // ---- Handlers -----------------------------------------------------

        private void HandleScore(int score)
        {
            if (score == _lastScore) return;
            _lastScore = score;
            _sb.Clear();
            _sb.Append(score);
            _scoreText.SetText(_sb);
        }

        private void HandleCombo(ComboEvt e)
        {
            if (e.Combo == _lastCombo) return;
            _lastCombo = e.Combo;

            if (e.Combo <= 1) { _comboText.SetText(string.Empty); }
            else
            {
                _sb.Clear();
                _sb.Append('x').Append(e.Combo);
                _comboText.SetText(_sb);
            }

            if (e.IsMilestone) _comboPopup.Play(e.Combo);
        }

        private void HandleWave(WaveEvt e)
        {
            _sb.Clear();
            _sb.Append("WAVE ").Append(e.WaveIndex + 1);
            _waveText.SetText(_sb);
        }

        private void HandleSteer(float normalized) => _steerTarget = normalized;

        private void HandleKill(EnemyKilledEvt e)
        {
            // "+100" melayang di lokasi kill. Di-pool; kalau pool habis, kill
            // berikutnya tidak menampilkan teks (lebih baik hilang daripada spike).
            _floatingText.Spawn(e.Position, e.ScoreAwarded);
        }

        private void HandleDamaged(PlayerDamagedEvt e)
        {
            _flashAlpha = 0.6f;
            for (int i = 0; i < _hearts.Length; i++)
                _hearts[i].enabled = i < e.LivesRemaining;
        }

        private void HandlePerfectClear()
        {
            if (_perfectClearBanner != null) _perfectClearBanner.alpha = 1f;
        }

        public void SetAmmo(int ammo)
        {
            for (int i = 0; i < _ammoIcons.Length; i++)
                _ammoIcons[i].enabled = i < ammo;
        }
    }
}
