// ---------------------------------------------------------------------------
// ComboPopup.cs — Popup besar di tengah layar saat combo milestone (x10/x20/x50).
// Satu instance, di-reuse. Animasi via kurva, bukan Animator (lebih murah).
// ---------------------------------------------------------------------------

using UnityEngine;
using TMPro;

namespace ChainRider.UI
{
    public sealed class ComboPopup : MonoBehaviour
    {
        [SerializeField] private TMP_Text _text;
        [SerializeField] private CanvasGroup _group;
        [SerializeField] private float _duration = 0.9f;
        [SerializeField] private AnimationCurve _scale = new(
            new Keyframe(0f, 0.4f), new Keyframe(0.18f, 1.25f), new Keyframe(0.35f, 1f), new Keyframe(1f, 1.05f));
        [SerializeField] private AnimationCurve _alpha = new(
            new Keyframe(0f, 0f), new Keyframe(0.12f, 1f), new Keyframe(0.75f, 1f), new Keyframe(1f, 0f));

        private float _t = -1f;

        public void Play(int combo)
        {
            _text.SetText("x{0}", combo);
            _t = 0f;
            _group.alpha = 0f;
            gameObject.SetActive(true);
        }

        private void Update()
        {
            if (_t < 0f) return;

            // unscaledDeltaTime: popup harus tetap cepat walau game slow-mo.
            _t += Time.unscaledDeltaTime / _duration;
            if (_t >= 1f) { _t = -1f; _group.alpha = 0f; gameObject.SetActive(false); return; }

            transform.localScale = Vector3.one * _scale.Evaluate(_t);
            _group.alpha = _alpha.Evaluate(_t);
        }
    }
}
