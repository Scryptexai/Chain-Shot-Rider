// ---------------------------------------------------------------------------
// InputRouter.cs — Satu jempol: tap + swipe horizontal. Itu saja.
//
// Constraint: portrait, 1 jempol, tidak ada tombol gerak/lompat/dash/reload.
//   TAP   → tembak (atau "rem" kalau sedang bullet riding)
//   SWIPE → belokkan peluru (hanya saat bullet riding)
//
// DETERMINISME: input tidak dibaca langsung oleh gameplay. Ia di-SAMPLE tiap
// frame render, lalu di-COMMIT ke tick simulasi. ReplayRecorder merekam
// InputFrame per tick; memutar ulang seed + stream ini menghasilkan run
// yang identik bit-per-bit.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.BulletSim;

namespace ChainRider.InputSys
{
    /// <summary>Input satu tick. 8 byte — murah untuk direkam ribuan kali.</summary>
    public struct InputFrame
    {
        public bool Tap;
        public float SteerAxis;    // -1..1, normalized against screen width
        public float AimAxis;      // horizontal drag as a fraction of screen width
        public bool Release;       // pointer lifted: fires in manual aim mode
    }

    public sealed class InputRouter : MonoBehaviour
    {
        [Header("Tuning")]
        [Tooltip("Jarak minimum (fraksi lebar layar) agar gerakan dihitung sebagai swipe, bukan tap.")]
        [SerializeField] private float _swipeDeadZone = 0.015f;
        [Tooltip("Jarak (fraksi lebar layar) yang setara dengan satu swipe penuh (15 derajat).")]
        [SerializeField] private float _fullSwipeDistance = 0.18f;
        [SerializeField] private float _tapMaxDuration = 0.25f;

        private BulletSystem _bullets;
        private AimController _aim;

        // Sampling state (frame render)
        private bool _pointerDown;
        private float _pointerDownTime;
        private Vector2 _pointerStart;
        private Vector2 _pointerLast;
        private InputFrame _pending;

        public InputFrame LastFrame { get; private set; }

        public void Init(BulletSystem bullets, AimController aim)
        {
            _bullets = bullets;
            _aim = aim;
        }

        /// <summary>True while a bullet is being ridden: drag steers instead of aiming.</summary>
        private bool IsRiding => _bullets != null && _bullets.RidingBullet != null;

        private void Update() => SampleInput();

        private void SampleInput()
        {
            // Satu jalur kode untuk touch & mouse (editor).
            bool down = false, up = false;
            Vector2 pos = default;

#if UNITY_EDITOR || UNITY_STANDALONE
            if (UnityEngine.Input.GetMouseButtonDown(0)) down = true;
            if (UnityEngine.Input.GetMouseButtonUp(0)) up = true;
            pos = UnityEngine.Input.mousePosition;
            bool held = UnityEngine.Input.GetMouseButton(0);
#else
            bool held = false;
            if (UnityEngine.Input.touchCount > 0)
            {
                Touch t = UnityEngine.Input.GetTouch(0);
                pos = t.position;
                down = t.phase == TouchPhase.Began;
                up = t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled;
                held = t.phase is TouchPhase.Moved or TouchPhase.Stationary or TouchPhase.Began;
            }
#endif
            float invW = 1f / Mathf.Max(1, Screen.width);

            if (down)
            {
                _pointerDown = true;
                _pointerDownTime = Time.unscaledTime;
                _pointerStart = _pointerLast = pos;
            }
            else if (held && _pointerDown)
            {
                // Steering kontinu: delta SEJAK FRAME TERAKHIR, bukan sejak titik
                // awal. Dengan begitu pemain bisa menggeser bolak-balik untuk
                // koreksi halus, dan meter tidak "terkunci" ke posisi absolut.
                float dx = (pos.x - _pointerLast.x) * invW;
                if (Mathf.Abs(dx) > _swipeDeadZone * 0.2f)
                {
                    // The same drag means different things depending on state, which
                    // is what keeps the scheme to one thumb and two gestures:
                    //   riding  -> steer the bullet
                    //   idle    -> aim the turret (manual mode only)
                    if (IsRiding || _aim == null || _aim.Mode != AimMode.Manual)
                        _pending.SteerAxis += dx / _fullSwipeDistance;
                    else
                        _pending.AimAxis += dx;

                    _pointerLast = pos;
                }
            }
            else if (up && _pointerDown)
            {
                _pointerDown = false;
                float dur = Time.unscaledTime - _pointerDownTime;
                float totalDx = Mathf.Abs(pos.x - _pointerStart.x) * invW;

                if (!IsRiding && _aim != null && _aim.Mode == AimMode.Manual)
                {
                    // Manual aim: releasing always fires, whether the player dragged
                    // to aim first or just tapped. One gesture, no separate button.
                    _pending.Release = true;
                }
                else if (dur <= _tapMaxDuration && totalDx < _swipeDeadZone)
                {
                    // Tap = quick and nearly motionless. Fires, or brakes while riding.
                    _pending.Tap = true;
                }
            }
        }

        /// <summary>
        /// Dipanggil ArenaManager di awal tiap tick simulasi.
        /// Input yang terkumpul selama frame render dikonsumsi di sini,
        /// tepat sekali, pada tick yang tercatat.
        /// </summary>
        public void ConsumeTick(int tick)
        {
            InputFrame frame = _pending;
            frame.SteerAxis = Mathf.Clamp(frame.SteerAxis, -1f, 1f);
            _pending = default;
            LastFrame = frame;

            ApplyFrame(frame);

            // ReplayRecorder.Record(tick, frame);
        }

        /// <summary>Replay playback: inject input instead of reading touches.</summary>
        public void InjectFrame(InputFrame frame)
        {
            ApplyFrame(frame);
            LastFrame = frame;
        }

        /// <summary>
        /// Single place where an InputFrame becomes game actions. Live input and
        /// replay MUST go through here, otherwise the two paths can drift apart and
        /// replays stop matching.
        ///
        /// Order matters: aim is applied before firing so a drag-then-release in the
        /// same tick fires along the angle the player actually aimed at.
        /// </summary>
        private void ApplyFrame(in InputFrame frame)
        {
            if (_aim != null && Mathf.Abs(frame.AimAxis) > 0.0001f) _aim.QueueDrag(frame.AimAxis);
            if (Mathf.Abs(frame.SteerAxis) > 0.001f) _bullets.SteerRidingBullet(frame.SteerAxis);
            if (frame.Tap || frame.Release) _bullets.OnTap();
        }
    }
}
