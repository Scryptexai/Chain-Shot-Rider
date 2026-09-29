// ---------------------------------------------------------------------------
// BulletView.cs — Representasi visual peluru. Tidak punya logika gameplay.
// Posisinya ditulis oleh BulletSystem.SyncViews() dari hasil simulasi.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Pooling;

namespace ChainRider.BulletSim
{
    public sealed class BulletView : MonoBehaviour, IPoolable
    {
        [SerializeField] private TrailRenderer _trail;
        [SerializeField] private ParticleSystem _deathFx;
        [SerializeField] private Light _light;

        public int BulletId { get; private set; }

        public void Bind(int id) => BulletId = id;

        /// <summary>
        /// Trail WAJIB di-clear saat peluru dipakai ulang dari pool, kalau tidak
        /// akan muncul garis panjang dari posisi peluru sebelumnya ke posisi baru.
        /// Bug klasik pooling.
        /// </summary>
        public void ResetTrail()
        {
            if (_trail == null) return;
            _trail.Clear();
            _trail.emitting = true;
        }

        public void PlayDeathFx(BulletEndReason reason)
        {
            if (_trail != null) _trail.emitting = false;
            if (_deathFx != null) _deathFx.Play();
        }

        public void OnSpawned()
        {
            if (_light != null) _light.enabled = true;
        }

        public void OnDespawned()
        {
            if (_trail != null) { _trail.emitting = false; _trail.Clear(); }
            if (_light != null) _light.enabled = false;
        }
    }
}
