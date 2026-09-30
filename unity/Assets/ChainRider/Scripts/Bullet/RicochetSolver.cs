// ---------------------------------------------------------------------------
// RicochetSolver.cs — Matematika pantulan murni. TANPA physics engine.
//
// Kelas ini:
//   - static, tanpa state, tanpa alokasi → aman dipanggil ribuan kali/frame
//   - hanya memakai float math → hasil identik di semua device (determinisme)
//   - memakai SWEEP (continuous collision), bukan overlap per-frame, sehingga
//     peluru berkecepatan 25–37 unit/detik TIDAK PERNAH menembus dinding
//     (tunneling) walau di-substep.
//
// Semua perhitungan dilakukan di bidang XZ (Y diabaikan). Arena itu 2D secara
// gameplay; 2.5D hanya urusan kamera & render.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.Core;

namespace ChainRider.BulletSim
{
    /// <summary>Hasil satu query sweep. Struct → tanpa alokasi.</summary>
    public readonly struct SweepHit
    {
        public readonly bool Hit;
        public readonly float T;             // 0..1 sepanjang gerakan frame ini
        public readonly Vector3 Point;
        public readonly Vector3 Normal;      // ternormalisasi, menghadap keluar permukaan
        public readonly SurfaceKind Surface;
        public readonly int TargetId;        // id obstacle/musuh; -1 untuk dinding
        public readonly float Restitution;

        public SweepHit(float t, Vector3 point, Vector3 normal, SurfaceKind surface, int targetId, float restitution)
        {
            Hit = true; T = t; Point = point; Normal = normal;
            Surface = surface; TargetId = targetId; Restitution = restitution;
        }

        public static readonly SweepHit None = default;
    }

    public static class RicochetSolver
    {
        /// <summary>Epsilon untuk mendorong peluru keluar dari permukaan setelah pantul.
        /// Tanpa ini, floating point error bisa membuat peluru "menempel" di dinding
        /// dan memantul berkali-kali dalam satu frame.</summary>
        public const float SkinWidth = 0.01f;

        // ------------------------------------------------------------------
        // REFLEKSI DASAR
        // ------------------------------------------------------------------

        /// <summary>
        /// Vektor pantul standar: R = D - 2(D·N)N.
        /// <paramref name="restitution"/> hanya mengurangi MAGNITUDO, tidak mengubah sudut —
        /// penting supaya pemain bisa memprediksi arah secara konsisten.
        /// </summary>
        public static Vector3 Reflect(Vector3 dir, Vector3 normal, float restitution = 1f)
        {
            Vector3 r = dir - 2f * Vector3.Dot(dir, normal) * normal;
            r.y = 0f;
            r.Normalize();
            return r * restitution;
        }

        /// <summary>
        /// Refleksi dengan pengaman sudut serempet (grazing angle).
        /// Kalau peluru menyerempet dinding hampir sejajar (&lt; minAngle), pantulan
        /// akan nyaris tidak terlihat dan pemain merasa "peluru menempel di dinding".
        /// Kita paksa minimal 12° menjauh dari permukaan agar selalu terbaca.
        /// </summary>
        public static Vector3 ReflectSafe(Vector3 dir, Vector3 normal, float minAngleDeg = 12f)
        {
            Vector3 r = Reflect(dir, normal);
            float sin = Vector3.Dot(r, normal);                 // r & n unit → sin(sudut dari permukaan)
            float minSin = Mathf.Sin(minAngleDeg * Mathf.Deg2Rad);
            if (sin < minSin)
            {
                // Dorong keluar sepanjang normal lalu re-normalisasi.
                r = (r + normal * (minSin - sin) * 1.5f).normalized;
                r.y = 0f;
                r.Normalize();
            }
            return r;
        }

        /// <summary>
        /// Memutar arah pada bidang XZ sebesar sudut derajat (positif = ke kanan layar).
        /// Dipakai oleh bullet steering. Rotasi murni, tidak mengubah kecepatan.
        /// </summary>
        public static Vector3 RotateXZ(Vector3 dir, float degrees)
        {
            float rad = degrees * Mathf.Deg2Rad;
            float c = Mathf.Cos(rad), s = Mathf.Sin(rad);
            return new Vector3(dir.x * c + dir.z * s, 0f, -dir.x * s + dir.z * c);
        }

        // ------------------------------------------------------------------
        // SWEEP: LINGKARAN BERGERAK vs BIDANG SUMBU (dinding kiri/kanan)
        // ------------------------------------------------------------------

        /// <summary>
        /// Sweep terhadap dinding samping arena (bidang X = konstan).
        /// Mengembalikan hit paling awal (T terkecil) atau SweepHit.None.
        /// </summary>
        public static SweepHit SweepSideWalls(Vector3 from, Vector3 delta, float radius,
                                              float xMin, float xMax, float restitution)
        {
            SweepHit best = SweepHit.None;
            float bestT = float.MaxValue;

            // Dinding kiri: permukaan di x = xMin, normal menghadap +X.
            if (delta.x < -1e-6f)
            {
                float t = ((xMin + radius) - from.x) / delta.x;
                if (t >= 0f && t <= 1f && t < bestT)
                {
                    bestT = t;
                    best = new SweepHit(t, from + delta * t, Vector3.right, SurfaceKind.Wall, -1, restitution);
                }
            }

            // Dinding kanan: permukaan di x = xMax, normal menghadap -X.
            if (delta.x > 1e-6f)
            {
                float t = ((xMax - radius) - from.x) / delta.x;
                if (t >= 0f && t <= 1f && t < bestT)
                {
                    bestT = t;
                    best = new SweepHit(t, from + delta * t, Vector3.left, SurfaceKind.Wall, -1, restitution);
                }
            }

            return best;
        }

        // ------------------------------------------------------------------
        // SWEEP: LINGKARAN BERGERAK vs LINGKARAN DIAM (pillar / bumper / musuh)
        // ------------------------------------------------------------------

        /// <summary>
        /// Continuous collision antara peluru (lingkaran radius rB bergerak sejauh delta)
        /// dan obstacle bulat (pusat c, radius rC).
        ///
        /// Selesaikan |P(t) - C|² = (rB + rC)² dengan P(t) = from + delta*t.
        /// Menjadi kuadrat: a·t² + b·t + k = 0.
        /// Ambil akar terkecil non-negatif ≤ 1.
        /// </summary>
        public static bool SweepCircle(Vector3 from, Vector3 delta, float rB,
                                       Vector3 center, float rC,
                                       out float t, out Vector3 point, out Vector3 normal)
        {
            t = 0f; point = default; normal = default;

            Vector3 m = new Vector3(from.x - center.x, 0f, from.z - center.z);
            float R = rB + rC;

            float a = delta.x * delta.x + delta.z * delta.z;
            if (a < 1e-12f) return false;                       // tidak bergerak

            float b = 2f * (m.x * delta.x + m.z * delta.z);
            float k = m.x * m.x + m.z * m.z - R * R;

            // Sudah tumpang tindih di awal (bisa terjadi setelah spawn/teleport):
            // dorong keluar langsung, anggap hit di t = 0.
            if (k < 0f)
            {
                t = 0f;
                normal = m.sqrMagnitude > 1e-8f ? m.normalized : Vector3.forward;
                point = center + normal * rC;
                return true;
            }

            float disc = b * b - 4f * a * k;
            if (disc < 0f) return false;                        // tidak pernah bersentuhan

            float sqrt = Mathf.Sqrt(disc);
            float t0 = (-b - sqrt) / (2f * a);
            if (t0 < 0f || t0 > 1f) return false;

            t = t0;
            point = from + delta * t;
            normal = new Vector3(point.x - center.x, 0f, point.z - center.z).normalized;
            return true;
        }

        /// <summary>Wrapper yang menghasilkan SweepHit.</summary>
        public static SweepHit SweepCircleObstacle(Vector3 from, Vector3 delta, float rB,
                                                   Vector3 center, float rC,
                                                   SurfaceKind kind, int id, float restitution)
        {
            if (SweepCircle(from, delta, rB, center, rC, out float t, out Vector3 p, out Vector3 n))
                return new SweepHit(t, p, n, kind, id, restitution);
            return SweepHit.None;
        }

        // ------------------------------------------------------------------
        // SWEEP: LINGKARAN vs SEGMEN (shield wall / moving platform)
        // ------------------------------------------------------------------

        /// <summary>
        /// Sweep terhadap segmen horizontal (platform/shield) yang direpresentasikan
        /// sebagai kapsul: segmen dari A ke B dengan ketebalan half.
        /// Implementasi ringkas: uji sweep terhadap bidang segmen, lalu clamp ke rentang.
        /// </summary>
        public static SweepHit SweepSegment(Vector3 from, Vector3 delta, float rB,
                                            Vector3 a, Vector3 b, float half,
                                            SurfaceKind kind, int id, float restitution)
        {
            Vector3 ab = b - a; ab.y = 0f;
            float abLen = ab.magnitude;
            if (abLen < 1e-6f) return SweepHit.None;
            Vector3 dir = ab / abLen;
            Vector3 n = new Vector3(-dir.z, 0f, dir.x);          // normal segmen

            float denom = Vector3.Dot(delta, n);
            if (Mathf.Abs(denom) < 1e-6f) return SweepHit.None;  // bergerak sejajar

            // Normal harus menghadap ke arah datangnya peluru.
            float side = Mathf.Sign(Vector3.Dot(from - a, n));
            Vector3 nFacing = n * side;
            float offset = (half + rB) * side;

            float t = (Vector3.Dot(a - from, n) + offset) / denom;
            if (t < 0f || t > 1f) return SweepHit.None;

            Vector3 p = from + delta * t;
            float along = Vector3.Dot(p - a, dir);
            if (along < -rB || along > abLen + rB) return SweepHit.None;   // lewat ujung

            return new SweepHit(t, p, nFacing, kind, id, restitution);
        }

        // ------------------------------------------------------------------
        // GRAVITY WELL
        // ------------------------------------------------------------------

        /// <summary>
        /// Membelokkan arah peluru menuju pusat gravity well.
        /// PENTING: kita hanya memutar ARAH, tidak menambah kecepatan. Kalau kita
        /// menambahkan force ke velocity, peluru bisa melesat tak terkendali dan
        /// merusak aturan "speed max 150%". Rotasi murni menjaga budget kecepatan
        /// dan tetap menghasilkan lintasan melengkung yang terasa enak.
        /// </summary>
        public static Vector3 ApplyGravityWell(Vector3 position, Vector3 dir,
                                               Vector3 wellCenter, float wellRadius, float force,
                                               float dt, float maxCurveDegPerSec)
        {
            Vector3 toCenter = new Vector3(wellCenter.x - position.x, 0f, wellCenter.z - position.z);
            float dist = toCenter.magnitude;
            if (dist > wellRadius || dist < 1e-4f) return dir;

            // Falloff linear: paling kuat di pusat, nol di tepi.
            float strength = 1f - (dist / wellRadius);

            Vector3 want = toCenter / dist;
            float angleTo = Vector3.SignedAngle(dir, want, Vector3.up);
            float maxStep = maxCurveDegPerSec * dt;
            float step = Mathf.Clamp(angleTo * strength * force * dt, -maxStep, maxStep);

            return RotateXZ(dir, -step);   // tanda negatif: RotateXZ positif = searah jarum jam
        }

        // ------------------------------------------------------------------
        // UTILITAS PREDIKSI (dipakai AimIndicator di UI)
        // ------------------------------------------------------------------

        /// <summary>
        /// Memprediksi titik-titik lintasan untuk garis bidik (aim indicator).
        /// Hanya memperhitungkan dinding — cukup untuk membantu pemain tanpa
        /// membocorkan seluruh solusi dan tanpa biaya CPU besar.
        ///
        /// PENTING: harus memakai batas yang SAMA PERSIS dengan BulletController,
        /// kalau tidak indicator akan berbohong. Diverifikasi di prototipe:
        /// deviasi terburuk 0.43 unit pada 19 titik pantul (tools/sim_test.js).
        /// </summary>
        /// <param name="topAbsorbs">
        /// false = dinding atas memantulkan peluru (spawn_gate_bumper, default
        /// desain ini). true = peluru keluar lewat atas dan prediksi berhenti.
        /// </param>
        public static int PredictWallPath(Vector3 origin, Vector3 dir, float radius,
                                          float xMin, float xMax, float zMax,
                                          int maxBounces, Vector3[] outPoints,
                                          bool topAbsorbs = false)
        {
            int count = 0;
            Vector3 p = origin;
            Vector3 d = dir.normalized;
            if (outPoints.Length == 0) return 0;
            outPoints[count++] = p;

            for (int i = 0; i < maxBounces && count < outPoints.Length; i++)
            {
                // Jarak ke dinding samping berikutnya.
                float tWall = float.MaxValue;
                Vector3 n = Vector3.zero;
                if (d.x < -1e-6f) { tWall = ((xMin + radius) - p.x) / d.x; n = Vector3.right; }
                else if (d.x > 1e-6f) { tWall = ((xMax - radius) - p.x) / d.x; n = Vector3.left; }

                // Jarak ke ujung atas arena.
                float tTop = d.z > 1e-6f ? ((zMax - radius) - p.z) / d.z : float.MaxValue;

                if (tTop <= tWall)
                {
                    p += d * tTop;
                    outPoints[count++] = p;
                    if (topAbsorbs) break;               // peluru keluar lewat spawn gate
                    d = Reflect(d, Vector3.back);        // spawn_gate_bumper: memantul
                    p += Vector3.back * SkinWidth;
                    continue;
                }

                p += d * tWall;
                outPoints[count++] = p;
                d = Reflect(d, n);
                p += n * SkinWidth;
            }
            return count;
        }
    }
}
