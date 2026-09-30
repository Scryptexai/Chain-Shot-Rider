// ---------------------------------------------------------------------------
// DeterministicRng.cs — xorshift128 RNG.
//
// UnityEngine.Random TIDAK boleh dipakai di jalur simulasi: state-nya global,
// bisa diubah oleh sistem lain (partikel, animasi), dan tidak bisa di-serialize
// untuk replay. RNG ini adalah struct kecil, murah, dan state-nya 16 byte
// sehingga bisa ditulis ke file replay / save.
//
// ATURAN PROYEK:
//   - Semua keputusan yang memengaruhi hasil run (formasi, sway, tipe musuh,
//     drop) WAJIB memakai instance ini.
//   - Efek kosmetik (arah percikan partikel, pitch SFX) BOLEH memakai
//     UnityEngine.Random karena tidak memengaruhi state simulasi.
// ---------------------------------------------------------------------------

using System;

namespace ChainRider.Core
{
    [Serializable]
    public struct DeterministicRng
    {
        private uint _x, _y, _z, _w;

        public DeterministicRng(int seed)
        {
            // SplitMix-style seeding supaya seed kecil (mis. 1) tetap menghasilkan
            // state awal yang "kaya" dan tidak berkorelasi antar run.
            unchecked
            {
                uint s = (uint)seed;
                _x = Mix(ref s);
                _y = Mix(ref s);
                _z = Mix(ref s);
                _w = Mix(ref s);
                if ((_x | _y | _z | _w) == 0u) _x = 0x9E3779B9u; // state nol dilarang
            }
        }

        private static uint Mix(ref uint s)
        {
            unchecked
            {
                s += 0x9E3779B9u;
                uint z = s;
                z = (z ^ (z >> 16)) * 0x85EBCA6Bu;
                z = (z ^ (z >> 13)) * 0xC2B2AE35u;
                return z ^ (z >> 16);
            }
        }

        /// <summary>uint acak penuh. Basis dari semua fungsi lain.</summary>
        public uint NextUInt()
        {
            unchecked
            {
                uint t = _x ^ (_x << 11);
                _x = _y; _y = _z; _z = _w;
                _w = _w ^ (_w >> 19) ^ t ^ (t >> 8);
                return _w;
            }
        }

        /// <summary>Float [0,1).</summary>
        public float NextFloat() => (NextUInt() >> 8) * (1f / 16777216f);

        /// <summary>Float [min,max).</summary>
        public float Range(float min, float max) => min + (max - min) * NextFloat();

        /// <summary>Int [min,max) — inklusif min, eksklusif max.</summary>
        public int Range(int min, int max)
        {
            if (max <= min) return min;
            return min + (int)(NextUInt() % (uint)(max - min));
        }

        /// <summary>True dengan probabilitas p.</summary>
        public bool Chance(float p) => NextFloat() < p;

        /// <summary>Pilih indeks berbobot. Dipakai untuk komposisi tipe musuh per wave.</summary>
        public int WeightedIndex(ReadOnlySpan<float> weights)
        {
            float total = 0f;
            for (int i = 0; i < weights.Length; i++) total += weights[i];
            float r = NextFloat() * total;
            for (int i = 0; i < weights.Length; i++)
            {
                r -= weights[i];
                if (r <= 0f) return i;
            }
            return weights.Length - 1;
        }

        /// <summary>Snapshot state untuk replay / save.</summary>
        public (uint, uint, uint, uint) GetState() => (_x, _y, _z, _w);

        public void SetState(uint x, uint y, uint z, uint w)
        {
            _x = x; _y = y; _z = z; _w = w;
        }
    }
}
