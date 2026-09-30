using UnityEngine;
using ChainRider.BulletSim;
using ChainRider.Core;

namespace ChainRider.InputSys
{
    /// <summary>Aiming scheme. Selected from Config/arena_config.json -> aim.mode.</summary>
    public enum AimMode
    {
        /// <summary>Player holds and drags horizontally to aim, releases to fire. MVP default.</summary>
        Manual = 0,

        /// <summary>Turret sweeps automatically; tap fires at the current angle. Accessibility option.</summary>
        Sweep = 1,
    }

    /// <summary>
    /// AimController — owns the turret angle and the aim indicator.
    ///
    /// WHY THIS EXISTS
    /// The original spec fired bullets straight ahead (dz = 1, dx = 0). Measured on
    /// the prototype, that produced 0.10 bounces per bullet and only 7 of 63 bullets
    /// ever touched the crowd: a vector with zero x-component can never reach the
    /// side walls at x = +/-10, so ricochet and bullet-riding were mechanically
    /// impossible. Aim direction therefore has to be a real, controllable quantity.
    ///
    /// WHY MANUAL AND NOT AUTO-SWEEP
    /// Both were implemented and measured (30 runs per configuration, see
    /// docs/12-aim-mode-comparison.md). In sweep mode the player controls only WHEN
    /// to fire, so playing more selectively cuts shot throughput with no way to
    /// compensate: win rate went from 10% (naive play) to 0% (skilled play). In
    /// manual mode angle and fire rate reinforce each other: 3% -> 33%. A control
    /// scheme that punishes learning is a design defect, so manual won.
    ///
    /// DETERMINISM
    /// The angle advances only inside the fixed-step simulation tick, never from
    /// Update() or render code. Player input is queued and consumed on the tick, the
    /// same way steering is, so a replay of (seed + InputFrame stream) is identical.
    /// </summary>
    public sealed class AimController : MonoBehaviour
    {
        // ------------------------------------------------------------------
        // CONFIGURATION (source: Config/arena_config.json -> "aim")
        // ------------------------------------------------------------------

        [SerializeField] private AimMode _mode = AimMode.Manual;

        [Tooltip("Maximum angle from the +Z axis, left and right.")]
        [SerializeField] private float _maxAngleDeg = 58f;

        [Tooltip("Degrees covered by dragging across the full screen width (manual mode).")]
        [SerializeField] private float _dragFullWidthDeg = 116f;

        [Tooltip("Turret sweep speed in degrees per simulated second (sweep mode).")]
        [SerializeField] private float _sweepSpeedDegPerSec = 75f;

        [Tooltip("How many bounces the aim indicator predicts.")]
        [SerializeField] private int _indicatorBounces = 2;

        [SerializeField] private Transform _muzzle;
        [SerializeField] private LineRenderer _indicator;

        // ------------------------------------------------------------------
        // SIMULATION STATE
        // ------------------------------------------------------------------

        /// <summary>Current turret angle in degrees. 0 points straight down +Z.</summary>
        public float AngleDeg { get; private set; }

        public AimMode Mode => _mode;

        /// <summary>Sweep direction: +1 right, -1 left. Unused in manual mode.</summary>
        private int _sweepDir = 1;

        /// <summary>
        /// Aim delta queued by input this tick, in degrees. Consumed by Tick so that
        /// input applies at a deterministic point in the frame.
        /// </summary>
        private float _queuedAimDeg;

        /// <summary>Normalized firing direction at the current angle.</summary>
        public Vector3 Direction
        {
            get
            {
                float r = AngleDeg * Mathf.Deg2Rad;
                return new Vector3(Mathf.Sin(r), 0f, Mathf.Cos(r));
            }
        }

        // Preallocated so the indicator costs zero GC per frame.
        private Vector3[] _pathBuffer;
        private IArenaQuery _bounds;
        private float _bulletRadius;
        private bool _topAbsorbs;

        // ==================================================================
        // SETUP
        // ==================================================================

        public void Init(IArenaQuery bounds, float bulletRadius, bool topAbsorbs,
                         AimMode mode, float maxAngleDeg, float dragFullWidthDeg,
                         float sweepSpeedDegPerSec, int indicatorBounces)
        {
            _bounds = bounds;
            _bulletRadius = bulletRadius;
            _topAbsorbs = topAbsorbs;
            _mode = mode;
            _maxAngleDeg = maxAngleDeg;
            _dragFullWidthDeg = dragFullWidthDeg;
            _sweepSpeedDegPerSec = sweepSpeedDegPerSec;
            _indicatorBounces = indicatorBounces;

            // +2: the muzzle point plus the endpoint after the last bounce.
            _pathBuffer = new Vector3[_indicatorBounces + 2];
            ResetAim();
        }

        /// <summary>Reset at run start so replays always begin from the same angle.</summary>
        public void ResetAim()
        {
            AngleDeg = 0f;
            _sweepDir = 1;
            _queuedAimDeg = 0f;
        }

        // ==================================================================
        // INPUT (called by InputRouter, never applied immediately)
        // ==================================================================

        /// <summary>
        /// Queue an aim change from a horizontal drag.
        /// </summary>
        /// <param name="normalizedDx">
        /// Horizontal drag distance as a fraction of screen width. Dragging the full
        /// width sweeps <see cref="_dragFullWidthDeg"/> degrees.
        /// </param>
        public void QueueDrag(float normalizedDx)
        {
            if (_mode != AimMode.Manual) return;
            _queuedAimDeg += normalizedDx * _dragFullWidthDeg;
        }

        /// <summary>Queue an absolute angle delta. Used by replay playback and tests.</summary>
        public void QueueAimDelta(float degrees)
        {
            if (_mode != AimMode.Manual) return;
            _queuedAimDeg += degrees;
        }

        // ==================================================================
        // SIMULATION TICK — called from ArenaManager.SimulateTick
        // ==================================================================

        public void Tick(float dt)
        {
            if (_mode == AimMode.Manual)
            {
                // Player owns the angle; apply whatever input was queued this tick.
                AngleDeg += _queuedAimDeg;
                _queuedAimDeg = 0f;
            }
            else
            {
                // Ping-pong sweep. Clamp before flipping so a large dt can never
                // carry the angle past the limit.
                AngleDeg += _sweepDir * _sweepSpeedDegPerSec * dt;
                if (AngleDeg > _maxAngleDeg) { AngleDeg = _maxAngleDeg; _sweepDir = -1; }
                else if (AngleDeg < -_maxAngleDeg) { AngleDeg = -_maxAngleDeg; _sweepDir = 1; }
            }

            AngleDeg = Mathf.Clamp(AngleDeg, -_maxAngleDeg, _maxAngleDeg);
        }

        // ==================================================================
        // RENDER — aim indicator (never touches simulation state)
        // ==================================================================

        /// <summary>
        /// Draw the predicted path. Hidden while riding, because a tap then means
        /// "brake" rather than "fire" — leaving the indicator up would mislead the
        /// player about what the next tap does.
        ///
        /// In manual mode this indicator is not decoration: it is the only feedback
        /// the player gets before committing a shot.
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
