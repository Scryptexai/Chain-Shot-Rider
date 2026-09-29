// ---------------------------------------------------------------------------
// BulletSystem.cs — Pemilik pool peluru + jembatan simulasi ↔ render.
//
// Simulasi peluru ada di BulletController (POCO). File ini hanya mengurus:
//   - pool BulletController + GameObject view-nya (no runtime Instantiate)
//   - meneruskan tick dari ArenaManager
//   - menyalin posisi hasil simulasi ke Transform (dengan interpolasi)
//   - amunisi & auto-reload
// ---------------------------------------------------------------------------

using System.Collections.Generic;
using UnityEngine;
using ChainRider.Core;
using ChainRider.Config;
using ChainRider.Pooling;

namespace ChainRider.BulletSim
{
    public sealed class BulletSystem : MonoBehaviour
    {
        [Header("Config")]
        [SerializeField] private BulletConfigSO _cfg;
        [SerializeField] private SlowMoConfigSO _slowCfg;

        [Header("Refs")]
        [SerializeField] private Transform _muzzle;
        [SerializeField] private GameObject _bulletViewPrefab;
        [SerializeField] private Transform _poolRoot;
        [SerializeField] private int _prewarm = 16;

        private readonly List<BulletController> _active = new(16);
        private readonly Stack<BulletController> _free = new(16);
        private readonly Dictionary<int, BulletView> _views = new(16);

        private IArenaQuery _arena;
        private IObstacleQuery _obstacles;
        private ICrowdQuery _crowd;

        private ObjectPool<BulletView> _viewPool;
        private int _nextId;

        // Amunisi: tidak ada reload manual (constraint). Magazine terisi otomatis.
        private int _ammo;
        private float _reloadTimer;
        public int Ammo => _ammo;

        /// <summary>Peluru yang sedang "dikendarai" pemain; null kalau tidak ada.
        /// Kamera & input steering mengacu ke sini.</summary>
        public BulletController RidingBullet { get; private set; }

        public void Init(IArenaQuery arena, IObstacleQuery obstacles, ICrowdQuery crowd)
        {
            _arena = arena; _obstacles = obstacles; _crowd = crowd;

            _viewPool = new ObjectPool<BulletView>(_bulletViewPrefab, _poolRoot, _prewarm);
            for (int i = 0; i < _prewarm; i++)
                _free.Push(new BulletController(_cfg, _slowCfg, _arena, _obstacles, _crowd));

            _ammo = _cfg.magazine;
            _nextId = 1;
        }

        // ==================================================================
        // FIRE
        // ==================================================================

        /// <summary>Tap layar = tembak (kalau tidak sedang riding) atau rem (kalau riding).</summary>
        /// <summary>Turret penyapu; boleh null pada test headless.</summary>
        private ChainRider.Input.AimController _aim;

        public void SetAim(ChainRider.Input.AimController aim) => _aim = aim;

        /// <summary>
        /// Boss aktif (null di luar wave 5). Diteruskan ke tiap BulletController
        /// supaya sweep peluru ikut memperhitungkan badan boss.
        /// </summary>
        public void SetBoss(ChainRider.Boss.BossController boss)
        {
            _boss = boss;
            for (int i = 0; i < _active.Count; i++) _active[i].SetBoss(boss);
        }

        private ChainRider.Boss.BossController _boss;

        public void OnTap()
        {
            if (RidingBullet != null && RidingBullet.IsAlive)
            {
                RidingBullet.Brake();
                return;
            }
            // Arah datang dari turret yang menyapu, bukan lurus ke depan.
            // Lurus ke depan terukur membuat peluru hampir tidak pernah memantul
            // (0.10 bounce/peluru) — lihat AimController untuk datanya.
            TryFire(_aim != null ? _aim.Direction : Vector3.forward);
        }

        public bool TryFire(Vector3 direction)
        {
            if (_ammo <= 0) return false;

            BulletController b = _free.Count > 0
                ? _free.Pop()
                : new BulletController(_cfg, _slowCfg, _arena, _obstacles, _crowd);  // fallback, jarang

            b.SetBoss(_boss);
            b.Fire(_nextId++, _muzzle.position, direction,
                   MetaUpgrades.BounceBonus, MetaUpgrades.SteerBonus);

            _active.Add(b);

            BulletView view = _viewPool.Get();
            view.Bind(b.Id);
            view.transform.SetPositionAndRotation(b.Data.Position, Quaternion.LookRotation(b.Data.Direction));
            view.ResetTrail();
            _views[b.Id] = view;

            _ammo--;
            _reloadTimer = _cfg.autoReloadDelay;
            return true;
        }

        public void SteerRidingBullet(float normalizedSwipe)
            => RidingBullet?.QueueSteer(normalizedSwipe);

        // ==================================================================
        // SIMULASI — dipanggil ArenaManager pada fixed step
        // ==================================================================

        public void Tick(float dt)
        {
            // Auto-reload (tanpa tombol, sesuai constraint "tidak ada reload manual").
            if (_ammo < _cfg.magazine)
            {
                _reloadTimer -= dt;
                if (_reloadTimer <= 0f)
                {
                    _ammo++;
                    _reloadTimer = _cfg.autoReloadDelay;
                }
            }

            RidingBullet = null;

            // Iterasi mundur supaya aman saat menghapus elemen.
            for (int i = _active.Count - 1; i >= 0; i--)
            {
                BulletController b = _active[i];
                b.Tick(dt);

                if (b.Data.State == BulletState.Riding)
                    RidingBullet = b;

                if (!b.IsAlive)
                {
                    ReleaseBullet(i, b);
                }
            }
        }

        private void ReleaseBullet(int index, BulletController b)
        {
            if (_views.TryGetValue(b.Id, out BulletView view))
            {
                view.PlayDeathFx(b.LastEndReason);
                _viewPool.Release(view);          // view menunda disable sampai trail habis
                _views.Remove(b.Id);
            }
            b.Recycle();
            _active.RemoveAt(index);
            _free.Push(b);
        }

        // ==================================================================
        // RENDER — interpolasi antar tick
        // ==================================================================

        public void SyncViews(float alpha)
        {
            for (int i = 0; i < _active.Count; i++)
            {
                BulletController b = _active[i];
                if (!_views.TryGetValue(b.Id, out BulletView view)) continue;

                view.transform.SetPositionAndRotation(
                    b.GetRenderPosition(alpha),
                    Quaternion.LookRotation(b.Data.Direction, Vector3.up));
            }
        }

        public void ClearAll()
        {
            for (int i = _active.Count - 1; i >= 0; i--)
                ReleaseBullet(i, _active[i]);
            _active.Clear();
            RidingBullet = null;
            _ammo = _cfg.magazine;
        }
    }

    /// <summary>Nilai upgrade meta-progression. Disederhanakan untuk skeleton.</summary>
    public static class MetaUpgrades
    {
        public static int BounceBonus;    // 0..35 → total maksimum 50 bounce
        public static float SteerBonus;   // 0..2 detik tambahan
    }
}
