// ---------------------------------------------------------------------------
// SimClock.cs — Fixed-step simulation clock (deterministic).
//
// KENAPA ADA FILE INI:
// Constraint proyek: "Harus deterministik (bisa direplay)". Itu mustahil kalau
// gameplay di-update dengan Time.deltaTime yang berbeda tiap frame/tiap device.
// Solusi: SELURUH simulasi (peluru, crowd, obstacle) berjalan pada langkah tetap
// 1/60 detik. Rendering/UI boleh berjalan pada frame rate berapa pun dan
// meng-interpolasi antar tick.
//
// Slow-motion TIDAK mengubah ukuran langkah simulasi. Slow-mo hanya mengurangi
// BERAPA BANYAK tick yang dijalankan per detik nyata. Dengan begitu urutan tick
// dan hasil simulasi tetap identik untuk seed + input stream yang sama.
// ---------------------------------------------------------------------------

using UnityEngine;

namespace ChainRider.Core
{
    /// <summary>
    /// Akumulator fixed-step. Bukan MonoBehaviour: dimiliki dan di-drive oleh
    /// <see cref="ArenaManager"/> supaya urutan eksekusi eksplisit dan tidak
    /// bergantung pada Script Execution Order Unity.
    /// </summary>
    public sealed class SimClock
    {
        /// <summary>Ukuran langkah simulasi, detik. 60 Hz. Konstan seumur run.</summary>
        public const float FixedDelta = 1f / 60f;

        /// <summary>Batas substep per frame render. Mencegah spiral of death saat
        /// frame drop (lebih baik simulasi melambat daripada freeze total).</summary>
        public const int MaxStepsPerFrame = 4;

        /// <summary>Jumlah tick yang sudah dijalankan sejak run dimulai.
        /// Ini adalah "waktu resmi" game — dipakai untuk replay, moving platform,
        /// dan semua animasi yang harus deterministik.</summary>
        public int Tick { get; private set; }

        /// <summary>Waktu simulasi dalam detik = Tick * FixedDelta.</summary>
        public float Time => Tick * FixedDelta;

        /// <summary>Sisa waktu yang belum cukup untuk satu tick penuh. Dipakai
        /// untuk interpolasi visual: alpha = Accumulator / FixedDelta.</summary>
        public float Accumulator { get; private set; }

        /// <summary>Alpha interpolasi 0..1 untuk render antar dua tick.</summary>
        public float InterpolationAlpha => Mathf.Clamp01(Accumulator / FixedDelta);

        /// <summary>True saat frame render ini sudah menjalankan minimal satu tick.</summary>
        public bool SteppedThisFrame { get; private set; }

        public void Reset()
        {
            Tick = 0;
            Accumulator = 0f;
            SteppedThisFrame = false;
        }

        /// <summary>
        /// Menambahkan waktu nyata (sudah dikali timeScale slow-mo) dan mengembalikan
        /// berapa tick yang harus dijalankan frame ini.
        /// </summary>
        /// <param name="scaledDeltaTime">
        /// Delta time REAL (Time.unscaledDeltaTime) dikali <c>SlowMoSystem.TimeScale</c>.
        /// Sengaja tidak memakai Time.deltaTime supaya kita mengendalikan penuh
        /// bagaimana slow-mo memengaruhi laju simulasi.
        /// </param>
        public int Advance(float scaledDeltaTime)
        {
            // Clamp delta: hindari lonjakan besar saat app resume / loading hitch.
            if (scaledDeltaTime > 0.25f) scaledDeltaTime = 0.25f;

            Accumulator += scaledDeltaTime;

            int steps = 0;
            while (Accumulator >= FixedDelta && steps < MaxStepsPerFrame)
            {
                Accumulator -= FixedDelta;
                steps++;
            }

            // Kalau masih ada sisa besar (device terlalu lambat), buang sisanya.
            // Lebih baik simulasi "slow" tapi stabil daripada menumpuk utang.
            if (Accumulator > FixedDelta * MaxStepsPerFrame)
                Accumulator = 0f;

            SteppedThisFrame = steps > 0;
            return steps;
        }

        /// <summary>Dipanggil oleh driver SETELAH satu tick simulasi selesai.</summary>
        public void CommitTick() => Tick++;
    }
}
