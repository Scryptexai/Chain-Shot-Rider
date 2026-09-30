// ---------------------------------------------------------------------------
// FloatingTextSpawner.cs — "+100" melayang di lokasi kill.
//
// Pool 32 item. Kalau 200 musuh mati bersamaan, kita TIDAK menampilkan 200 teks:
// itu tidak terbaca dan membunuh performa. Ketika pool habis, teks digabung
// menjadi satu popup agregat di tengah — lebih terbaca DAN lebih murah.
// ---------------------------------------------------------------------------

using UnityEngine;
using TMPro;
using ChainRider.Pooling;

namespace ChainRider.UI
{
    public sealed class FloatingTextSpawner : MonoBehaviour
    {
        [SerializeField] private GameObject _prefab;
        [SerializeField] private Transform _root;
        [SerializeField] private Camera _worldCamera;
        [SerializeField] private int _poolSize = 32;
        [SerializeField] private float _lifetime = 0.8f;
        [SerializeField] private float _riseSpeed = 90f;
        [SerializeField] private AnimationCurve _scaleCurve = AnimationCurve.EaseInOut(0, 1.4f, 1, 0.9f);

        private struct Item { public RectTransform Rt; public TMP_Text Text; public float T; public Vector2 Pos; }

        private Item[] _items;
        private int _cursor;
        private int _aggregatedScore;
        private float _aggregateTimer;

        private void Awake()
        {
            _items = new Item[_poolSize];
            for (int i = 0; i < _poolSize; i++)
            {
                GameObject go = Instantiate(_prefab, _root);
                go.SetActive(false);
                _items[i] = new Item
                {
                    Rt = go.GetComponent<RectTransform>(),
                    Text = go.GetComponent<TMP_Text>(),
                    T = 0f,
                };
            }
        }

        public void Spawn(Vector3 worldPos, int score)
        {
            // Cari slot bebas mulai dari cursor (round-robin, O(1) amortized).
            for (int n = 0; n < _poolSize; n++)
            {
                int i = (_cursor + n) % _poolSize;
                if (_items[i].T > 0f) continue;

                _cursor = (i + 1) % _poolSize;
                Vector2 screen = _worldCamera.WorldToScreenPoint(worldPos);

                _items[i].T = _lifetime;
                _items[i].Pos = screen;
                _items[i].Rt.position = screen;
                _items[i].Text.SetText("+{0}", score);
                _items[i].Rt.gameObject.SetActive(true);
                return;
            }

            // Pool habis → agregasi.
            _aggregatedScore += score;
            _aggregateTimer = 0.25f;
        }

        private void Update()
        {
            float dt = Time.unscaledDeltaTime;

            for (int i = 0; i < _poolSize; i++)
            {
                if (_items[i].T <= 0f) continue;

                _items[i].T -= dt;
                if (_items[i].T <= 0f) { _items[i].Rt.gameObject.SetActive(false); continue; }

                float k = 1f - _items[i].T / _lifetime;
                _items[i].Pos.y += _riseSpeed * dt;
                _items[i].Rt.position = _items[i].Pos;
                _items[i].Rt.localScale = Vector3.one * _scaleCurve.Evaluate(k);

                Color c = _items[i].Text.color;
                c.a = 1f - k * k;
                _items[i].Text.color = c;
            }

            if (_aggregateTimer > 0f)
            {
                _aggregateTimer -= dt;
                if (_aggregateTimer <= 0f && _aggregatedScore > 0)
                {
                    Spawn(_worldCamera.transform.position + _worldCamera.transform.forward * 20f, _aggregatedScore);
                    _aggregatedScore = 0;
                }
            }
        }
    }
}
