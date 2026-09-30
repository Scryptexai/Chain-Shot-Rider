// ---------------------------------------------------------------------------
// FormationBuilder.cs — Menghasilkan posisi offset untuk sebuah wave.
//
// Semua formasi dibangun dalam RUANG LOKAL (origin = tengah formasi, +Z = maju
// ke arah player). CrowdManager yang memindahkannya ke spawn zone.
//
// Fungsi di sini murni & deterministik: input sama → output sama persis.
// Tidak ada UnityEngine.Random.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Core;

namespace ChainRider.Crowd
{
    public static class FormationBuilder
    {
        /// <summary>
        /// Mengisi <paramref name="outPositions"/> dengan offset lokal.
        /// </summary>
        /// <param name="count">Jumlah musuh pada wave ini.</param>
        /// <param name="columns">Lebar formasi dalam jumlah kolom (5..12).</param>
        /// <param name="spacing">Jarak antar musuh (0.8 unit).</param>
        /// <param name="maxHalfWidth">Setengah lebar arena yang boleh dipakai — mencegah
        /// formasi menembus dinding.</param>
        /// <returns>Jumlah posisi yang benar-benar diisi.</returns>
        public static int Build(FormationKind kind, int count, int columns, float spacing,
                                float maxHalfWidth, Vector3[] outPositions)
        {
            count = Mathf.Min(count, outPositions.Length);
            columns = Mathf.Max(1, columns);

            // Clamp kolom agar formasi tidak melebihi lebar yang diizinkan.
            int maxCols = Mathf.Max(1, Mathf.FloorToInt((maxHalfWidth * 2f) / spacing));
            columns = Mathf.Min(columns, maxCols);

            return kind switch
            {
                FormationKind.Rect => BuildRect(count, columns, spacing, outPositions),
                FormationKind.VShape => BuildVShape(count, columns, spacing, maxHalfWidth, outPositions),
                FormationKind.Diamond => BuildDiamond(count, spacing, maxHalfWidth, outPositions),
                FormationKind.Line => BuildLine(count, spacing, outPositions),
                FormationKind.Circle => BuildCircle(count, spacing, maxHalfWidth, outPositions),
                _ => BuildRect(count, columns, spacing, outPositions),
            };
        }

        // --- RECT: grid rapat. Formasi default, paling "memuaskan" ditembus. ---
        private static int BuildRect(int count, int columns, float spacing, Vector3[] o)
        {
            float halfW = (columns - 1) * spacing * 0.5f;
            for (int i = 0; i < count; i++)
            {
                int col = i % columns;
                int row = i / columns;
                o[i] = new Vector3(col * spacing - halfW, 0f, row * spacing);
            }
            return count;
        }

        // --- V-SHAPE: ujung V menghadap player. Memancing tembakan tengah
        //     yang lalu memantul keluar ke dua sayap. ---
        private static int BuildVShape(int count, int columns, float spacing, float maxHalfWidth, Vector3[] o)
        {
            int written = 0;
            int row = 0;
            while (written < count)
            {
                int perRow = Mathf.Min(2, count - written);
                float x = Mathf.Min(row * spacing * 0.6f, maxHalfWidth);
                float z = row * spacing * 0.8f;

                o[written++] = new Vector3(-x, 0f, z);
                if (perRow > 1 && x > 0.01f && written < count)
                    o[written++] = new Vector3(x, 0f, z);

                row++;
                if (row > 400) break;   // guard
            }
            return written;
        }

        // --- DIAMOND: melebar lalu menyempit. Bagus untuk chain-explosion. ---
        private static int BuildDiamond(int count, float spacing, float maxHalfWidth, Vector3[] o)
        {
            int written = 0;
            int row = 0;
            int maxRowWidth = Mathf.FloorToInt(Mathf.Sqrt(count));
            int totalRows = maxRowWidth * 2;

            while (written < count && row < totalRows)
            {
                int inRow = row <= maxRowWidth ? row + 1 : totalRows - row + 1;
                inRow = Mathf.Max(1, inRow);
                float halfW = Mathf.Min((inRow - 1) * spacing * 0.5f, maxHalfWidth);

                for (int c = 0; c < inRow && written < count; c++)
                {
                    float x = inRow == 1 ? 0f : Mathf.Lerp(-halfW, halfW, c / (float)(inRow - 1));
                    o[written++] = new Vector3(x, 0f, row * spacing * 0.9f);
                }
                row++;
            }

            // Sisa musuh (kalau count tidak pas) ditumpuk di baris belakang.
            while (written < count)
            {
                int c = written % 6;
                o[written] = new Vector3((c - 2.5f) * spacing, 0f, row * spacing * 0.9f);
                written++;
                if (c == 5) row++;
            }
            return written;
        }

        // --- LINE: satu kolom vertikal. Ujian presisi tembakan lurus. ---
        private static int BuildLine(int count, float spacing, Vector3[] o)
        {
            for (int i = 0; i < count; i++)
                o[i] = new Vector3(0f, 0f, i * spacing * 0.7f);
            return count;
        }

        // --- CIRCLE: cincin konsentris. Peluru yang masuk ke tengah dan
        //     memantul di dalamnya = pembantaian maksimal. ---
        private static int BuildCircle(int count, float spacing, float maxHalfWidth, Vector3[] o)
        {
            int written = 0;
            int ring = 1;
            while (written < count)
            {
                float radius = Mathf.Min(ring * spacing * 1.1f, maxHalfWidth);
                int perRing = Mathf.Max(6, Mathf.FloorToInt(Mathf.PI * 2f * radius / spacing));
                for (int i = 0; i < perRing && written < count; i++)
                {
                    float a = (i / (float)perRing) * Mathf.PI * 2f;
                    o[written++] = new Vector3(Mathf.Cos(a) * radius, 0f,
                                               Mathf.Sin(a) * radius + radius);
                }
                ring++;
                if (ring > 60) break;   // guard
            }
            return written;
        }

        /// <summary>
        /// Jitter kecil deterministik agar formasi tidak terlihat seperti
        /// spreadsheet. Memakai DeterministicRng, bukan UnityEngine.Random.
        /// </summary>
        public static void ApplyJitter(Vector3[] positions, int count, float amount, ref DeterministicRng rng)
        {
            for (int i = 0; i < count; i++)
            {
                positions[i].x += rng.Range(-amount, amount);
                positions[i].z += rng.Range(-amount, amount);
            }
        }
    }
}
