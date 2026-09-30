// ---------------------------------------------------------------------------
// PerfHud.cs — Overlay metrik untuk sesi profiling di device.
// Menampilkan: FPS, ms/frame, GC alloc per detik, jumlah musuh & peluru aktif,
// high-water mark tiap pool. Wajib nyala saat menjalankan testing checklist.
// ---------------------------------------------------------------------------

using System.Text;
using UnityEngine;
using UnityEngine.Profiling;
using ChainRider.Crowd;
using ChainRider.Pooling;

namespace ChainRider.DebugTools
{
    public sealed class PerfHud : MonoBehaviour
    {
        [SerializeField] private CrowdManager _crowd;
        [SerializeField] private bool _enabled = true;
        [SerializeField] private float _refreshInterval = 0.25f;

        private readonly StringBuilder _sb = new(256);
        private GUIStyle _style;
        private float _timer;
        private float _fps, _worstMs;
        private long _lastGcBytes;
        private long _gcPerSec;
        private string _cached = string.Empty;

        private void Update()
        {
            if (!_enabled) return;

            float ms = Time.unscaledDeltaTime * 1000f;
            if (ms > _worstMs) _worstMs = ms;

            _timer -= Time.unscaledDeltaTime;
            if (_timer > 0f) return;
            _timer = _refreshInterval;

            _fps = 1f / Mathf.Max(0.0001f, Time.unscaledDeltaTime);

            long gc = Profiler.GetMonoUsedSizeLong();
            _gcPerSec = (long)((gc - _lastGcBytes) / _refreshInterval);
            _lastGcBytes = gc;

            _sb.Clear();
            _sb.Append("FPS ").Append(Mathf.RoundToInt(_fps))
               .Append("  |  ").Append(ms.ToString("F1")).Append(" ms")
               .Append("  |  worst ").Append(_worstMs.ToString("F1")).Append(" ms\n");
            _sb.Append("Enemies alive: ").Append(_crowd != null ? _crowd.AliveCount : 0).Append('\n');
            _sb.Append("Mono heap: ").Append(gc / 1048576).Append(" MB  (delta ")
               .Append(_gcPerSec / 1024).Append(" KB/s)\n");
            PoolRegistry.AppendReport(_sb);
            _cached = _sb.ToString();

            // Reset worst tiap 4 detik supaya spike lama tidak menutupi kondisi kini.
            if (Time.frameCount % 240 == 0) _worstMs = 0f;
        }

        private void OnGUI()
        {
            if (!_enabled) return;
            _style ??= new GUIStyle(GUI.skin.label)
            {
                fontSize = Mathf.RoundToInt(Screen.height * 0.018f),
                normal = { textColor = Color.green },
            };
            GUI.Label(new Rect(16, Screen.height * 0.08f, Screen.width - 32, 300), _cached, _style);
        }
    }
}
