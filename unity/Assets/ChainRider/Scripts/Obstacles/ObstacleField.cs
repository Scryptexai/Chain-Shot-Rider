// ---------------------------------------------------------------------------
// ObstacleField.cs — Kumpulan obstacle sebagai DATA, bukan collider.
//
// Semua obstacle disimpan sebagai array struct dan di-sweep secara analitik.
// Tidak ada Physics.Raycast, tidak ada Collider, tidak ada Rigidbody.
// GameObject hanya dipakai untuk VISUAL (mesh + VFX), dan posisinya disalin
// dari data — bukan sebaliknya.
// ---------------------------------------------------------------------------

using System.Collections.Generic;
using UnityEngine;
using ChainRider.Core;
using ChainRider.Config;
using ChainRider.BulletSim;

namespace ChainRider.Obstacles
{
    public struct ObstacleEntry
    {
        public ObstacleKind Kind;
        public Vector3 Position;      // posisi saat ini (platform bisa bergerak)
        public Vector3 BasePosition;  // posisi awal, acuan ping-pong
        public float Radius;
        public float HalfWidth;
        public float Travel;
        public float Speed;
        public float Phase;
        public float Force;
        public float Hp;
        public bool Active;
        public int ViewIndex;
    }

    public sealed class ObstacleField : MonoBehaviour, IObstacleQuery
    {
        [Header("Prefab visual (di-pool)")]
        [SerializeField] private GameObject _bumperPrefab;
        [SerializeField] private GameObject _pillarPrefab;
        [SerializeField] private GameObject _barrelPrefab;
        [SerializeField] private GameObject _gravityWellPrefab;
        [SerializeField] private GameObject _movingPlatformPrefab;
        [SerializeField] private GameObject _shieldWallPrefab;
        [SerializeField] private Transform _root;

        [Header("Default")]
        [SerializeField] private float _bumperRestitution = 0.95f;
        [SerializeField] private float _pillarRestitution = 0.98f;
        [SerializeField] private float _barrelExplosionRadius = 3f;
        [SerializeField] private float _barrelExplosionDamage = 50f;
        [SerializeField] private float _chainDelay = 0.08f;
        [SerializeField] private float _gravityMaxCurveDegPerSec = 120f;

        private ObstacleEntry[] _entries = new ObstacleEntry[32];
        private int _count;
        private readonly List<Transform> _views = new(32);
        private ICrowdQuery _crowd;

        // Antrian chain explosion: barrel tidak meledak langsung berantai dalam
        // satu frame (akan terasa seperti satu ledakan besar dan bikin spike).
        // Ia di-stagger 0.08 detik supaya terbaca sebagai RANTAI.
        private readonly List<(int index, float delay, int depth)> _pendingExplosions = new(16);

        public void SetCrowd(ICrowdQuery crowd) => _crowd = crowd;

        // ==================================================================
        // BUILD
        // ==================================================================

        public void BuildVariant(VariantSO variant, ArenaBounds bounds)
        {
            Clear();

            for (int i = 0; i < variant.obstacles.Length; i++)
            {
                ObstaclePlacement p = variant.obstacles[i];
                Vector3 pos = new(p.positionXZ.x, 0f, p.positionXZ.y);

                ObstacleEntry e = new()
                {
                    Kind = p.kind,
                    Position = pos,
                    BasePosition = pos,
                    Radius = p.radius,
                    HalfWidth = p.width * 0.5f,
                    Travel = p.travel,
                    Speed = p.speed,
                    Phase = p.phase,
                    Force = p.force,
                    Hp = p.kind == ObstacleKind.Barrel ? 1f : (p.kind == ObstacleKind.ShieldWall ? 3f : float.MaxValue),
                    Active = true,
                    ViewIndex = i,
                };

                if (_count >= _entries.Length) System.Array.Resize(ref _entries, _count * 2);
                _entries[_count++] = e;

                SpawnView(e, variant);
            }
        }

        private void SpawnView(in ObstacleEntry e, VariantSO variant)
        {
            GameObject prefab = e.Kind switch
            {
                ObstacleKind.Bumper => _bumperPrefab,
                ObstacleKind.Pillar => _pillarPrefab,
                ObstacleKind.Barrel => _barrelPrefab,
                ObstacleKind.GravityWell => _gravityWellPrefab,
                ObstacleKind.MovingPlatform => _movingPlatformPrefab,
                _ => _shieldWallPrefab,
            };
            if (prefab == null) { _views.Add(null); return; }

            GameObject go = Instantiate(prefab, e.Position, Quaternion.identity, _root);  // load-time only
            float s = e.Kind is ObstacleKind.Bumper or ObstacleKind.Pillar ? e.Radius * 2f : 1f;
            if (s > 0f) go.transform.localScale = new Vector3(s, 1f, s);

            // Warna tema lewat MaterialPropertyBlock — tanpa membuat material baru.
            if (go.TryGetComponent(out Renderer r))
            {
                MaterialPropertyBlock mpb = new();
                r.GetPropertyBlock(mpb);
                mpb.SetColor("_BaseColor", variant.bumperColor);
                mpb.SetColor("_EmissionColor", variant.bumperColor * 2f);
                r.SetPropertyBlock(mpb);
            }
            _views.Add(go.transform);
        }

        public void Clear()
        {
            for (int i = 0; i < _views.Count; i++) if (_views[i] != null) Destroy(_views[i].gameObject);
            _views.Clear();
            _count = 0;
            _pendingExplosions.Clear();
        }

        // ==================================================================
        // TICK
        // ==================================================================

        public void Tick(float dt, float simTime)
        {
            // --- Moving platform: ping-pong deterministik ------------------
            // Memakai simTime (kelipatan 1/60), BUKAN Time.time. Ini yang
            // membuat replay menghasilkan posisi platform yang persis sama.
            for (int i = 0; i < _count; i++)
            {
                ref ObstacleEntry e = ref _entries[i];
                if (!e.Active || e.Kind != ObstacleKind.MovingPlatform) continue;

                float t = Mathf.PingPong(simTime * e.Speed + e.Phase * e.Travel * 2f, e.Travel * 2f) - e.Travel;
                e.Position = e.BasePosition + new Vector3(t, 0f, 0f);
                if (e.ViewIndex < _views.Count && _views[e.ViewIndex] != null)
                    _views[e.ViewIndex].position = e.Position;
            }

            // --- Chain explosion terjadwal ---------------------------------
            for (int i = _pendingExplosions.Count - 1; i >= 0; i--)
            {
                var (idx, delay, depth) = _pendingExplosions[i];
                delay -= dt;
                if (delay > 0f) { _pendingExplosions[i] = (idx, delay, depth); continue; }

                _pendingExplosions.RemoveAt(i);
                DetonateBarrel(idx, depth);
            }
        }

        // ==================================================================
        // IObstacleQuery
        // ==================================================================

        public SweepHit SweepObstacles(Vector3 from, Vector3 delta, float radius)
        {
            SweepHit best = SweepHit.None;
            float bestT = float.MaxValue;

            for (int i = 0; i < _count; i++)
            {
                ref ObstacleEntry e = ref _entries[i];
                if (!e.Active) continue;

                SweepHit h = SweepHit.None;

                switch (e.Kind)
                {
                    case ObstacleKind.Bumper:
                        h = RicochetSolver.SweepCircleObstacle(from, delta, radius, e.Position, e.Radius,
                                                               SurfaceKind.Bumper, i, _bumperRestitution);
                        break;

                    case ObstacleKind.Pillar:
                        h = RicochetSolver.SweepCircleObstacle(from, delta, radius, e.Position, e.Radius,
                                                               SurfaceKind.Pillar, i, _pillarRestitution);
                        break;

                    case ObstacleKind.Barrel:
                        h = RicochetSolver.SweepCircleObstacle(from, delta, radius, e.Position, 0.6f,
                                                               SurfaceKind.Bumper, i, 0.5f);
                        break;

                    case ObstacleKind.ShieldWall:
                    {
                        Vector3 a = e.Position + Vector3.left * e.HalfWidth;
                        Vector3 b = e.Position + Vector3.right * e.HalfWidth;
                        h = RicochetSolver.SweepSegment(from, delta, radius, a, b, 0.2f,
                                                        SurfaceKind.ShieldWall, i, 1f);
                        break;
                    }

                    case ObstacleKind.MovingPlatform:
                        // Platform MENGHALANGI MUSUH, tidak memantulkan peluru.
                        // Keputusan desain: kalau ia memantulkan peluru juga,
                        // pemain tidak punya cara menembus barisan tengah.
                        continue;

                    case ObstacleKind.GravityWell:
                        continue;   // non-kontak, ditangani ApplyFields
                }

                if (h.Hit && h.T < bestT) { bestT = h.T; best = h; }
            }

            return best;
        }

        public Vector3 ApplyFields(Vector3 position, Vector3 direction, float dt)
        {
            for (int i = 0; i < _count; i++)
            {
                ref ObstacleEntry e = ref _entries[i];
                if (!e.Active || e.Kind != ObstacleKind.GravityWell) continue;

                direction = RicochetSolver.ApplyGravityWell(
                    position, direction, e.Position, e.Radius, e.Force, dt, _gravityMaxCurveDegPerSec);
            }
            return direction;
        }

        public void DamageObstacle(int obstacleId, float damage, Vector3 hitPoint, Vector3 hitNormal)
        {
            if (obstacleId < 0 || obstacleId >= _count) return;
            ref ObstacleEntry e = ref _entries[obstacleId];
            if (!e.Active) return;

            switch (e.Kind)
            {
                case ObstacleKind.Barrel:
                    e.Hp -= damage;
                    if (e.Hp <= 0f) DetonateBarrel(obstacleId, 0);
                    break;

                case ObstacleKind.ShieldWall:
                {
                    // Hanya rusak kalau dipukul dari BELAKANG.
                    // Normal shield menghadap ke player (-Z). Kalau peluru datang
                    // dari sisi +Z (setelah memantul di belakang), dot > 0 → tembus.
                    bool fromBehind = Vector3.Dot(hitNormal, Vector3.back) < 0f;
                    if (!fromBehind) return;
                    e.Hp -= damage;
                    if (e.Hp <= 0f) Deactivate(obstacleId);
                    break;
                }
            }
        }

        // ==================================================================
        // BARREL
        // ==================================================================

        private void DetonateBarrel(int index, int chainDepth)
        {
            ref ObstacleEntry e = ref _entries[index];
            if (!e.Active) return;

            Vector3 pos = e.Position;
            Deactivate(index);

            _crowd?.ExplodeAt(pos, _barrelExplosionRadius, _barrelExplosionDamage, chainDepth);
            GameEvents.RaiseExplosion(new ExplosionEvt(pos, _barrelExplosionRadius, chainDepth));

            // Cari barrel lain dalam radius → jadwalkan chain.
            if (chainDepth >= 8) return;      // batas kedalaman, cegah kombinasi ekstrem
            for (int i = 0; i < _count; i++)
            {
                if (i == index) continue;
                ref ObstacleEntry o = ref _entries[i];
                if (!o.Active || o.Kind != ObstacleKind.Barrel) continue;
                if ((o.Position - pos).sqrMagnitude > _barrelExplosionRadius * _barrelExplosionRadius) continue;

                _pendingExplosions.Add((i, _chainDelay, chainDepth + 1));
                o.Hp = 0f;   // tandai supaya tidak dijadwalkan dua kali
            }
        }

        private void Deactivate(int index)
        {
            _entries[index].Active = false;
            int vi = _entries[index].ViewIndex;
            if (vi >= 0 && vi < _views.Count && _views[vi] != null)
                _views[vi].gameObject.SetActive(false);
        }
    }
}
