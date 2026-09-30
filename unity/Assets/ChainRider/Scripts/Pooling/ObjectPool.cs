// ---------------------------------------------------------------------------
// ObjectPool.cs — Pool generik tanpa alokasi runtime.
//
// ATURAN PROYEK: tidak ada Instantiate/Destroy setelah loading selesai.
// Instantiate memicu alokasi + inisialisasi komponen (0.1-0.5 ms per objek);
// Destroy memicu GC. Dua-duanya adalah penyebab utama frame spike di mobile.
// ---------------------------------------------------------------------------

using System.Collections.Generic;
using UnityEngine;

namespace ChainRider.Pooling
{
    /// <summary>Komponen yang bisa di-pool wajib mengimplementasikan ini.</summary>
    public interface IPoolable
    {
        void OnSpawned();
        void OnDespawned();
    }

    public sealed class ObjectPool<T> where T : Component
    {
        private readonly GameObject _prefab;
        private readonly Transform _root;
        private readonly Stack<T> _free;
        private readonly List<T> _all;

        /// <summary>Jumlah maksimum yang pernah aktif bersamaan. Dipakai untuk
        /// men-tune ukuran pre-warm — kalau angka ini menyentuh kapasitas,
        /// pool kekecilan dan akan terjadi Instantiate saat runtime.</summary>
        public int HighWaterMark { get; private set; }
        public int ActiveCount => _all.Count - _free.Count;
        public int Capacity => _all.Count;

        public ObjectPool(GameObject prefab, Transform root, int prewarm)
        {
            _prefab = prefab;
            _root = root;
            _free = new Stack<T>(prewarm);
            _all = new List<T>(prewarm);
            for (int i = 0; i < prewarm; i++) _free.Push(CreateNew());
        }

        private T CreateNew()
        {
            GameObject go = Object.Instantiate(_prefab, _root);
            go.SetActive(false);
            T c = go.GetComponent<T>();
            _all.Add(c);
            return c;
        }

        public T Get()
        {
            T item = _free.Count > 0 ? _free.Pop() : CreateNew();
            item.gameObject.SetActive(true);
            if (item is IPoolable p) p.OnSpawned();

            int active = ActiveCount;
            if (active > HighWaterMark) HighWaterMark = active;
            return item;
        }

        public void Release(T item)
        {
            if (item == null) return;
            if (item is IPoolable p) p.OnDespawned();
            item.gameObject.SetActive(false);
            item.transform.SetParent(_root, false);
            _free.Push(item);
        }

        public void ReleaseAll()
        {
            for (int i = 0; i < _all.Count; i++)
                if (_all[i] != null && _all[i].gameObject.activeSelf) Release(_all[i]);
        }
    }

    /// <summary>Registry seluruh pool — dipakai PerfHud untuk laporan high-water mark.</summary>
    public static class PoolRegistry
    {
        private static readonly Dictionary<string, System.Func<(int active, int cap, int hwm)>> _reporters = new();

        public static void Register(string name, System.Func<(int, int, int)> reporter) => _reporters[name] = reporter;
        public static void Clear() => _reporters.Clear();

        public static void AppendReport(System.Text.StringBuilder sb)
        {
            foreach (var kv in _reporters)
            {
                var (a, c, h) = kv.Value();
                sb.Append(kv.Key).Append(": ").Append(a).Append('/').Append(c)
                  .Append(" (hwm ").Append(h).Append(")\n");
            }
        }
    }
}
