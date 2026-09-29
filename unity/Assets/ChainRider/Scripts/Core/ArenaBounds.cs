// ---------------------------------------------------------------------------
// ArenaBounds.cs — Representasi analitik batas arena.
//
// CONSTRAINT PROYEK: "Tidak boleh pakai physics engine untuk ricochet".
// Karena arena adalah kotak sederhana, kita tidak butuh collider sama sekali.
// Dinding direpresentasikan sebagai 4 bidang (plane) dan pantulan dihitung
// analitik. Ini lebih cepat, deterministik lintas platform, dan bebas dari
// ketidakpastian floating point milik PhysX.
// ---------------------------------------------------------------------------

using UnityEngine;
using ChainRider.BulletSim;

namespace ChainRider.Core
{
    /// <summary>
    /// Implementasi <see cref="IArenaQuery"/> berbasis komponen scene, supaya
    /// level designer bisa melihat batas arena lewat Gizmos sambil sistem peluru
    /// tetap hanya bergantung pada interface (bisa di-unit-test tanpa scene).
    /// </summary>
    public sealed class ArenaBounds : MonoBehaviour, IArenaQuery
    {
        [Header("Dimensi dunia (unit)")]
        [SerializeField] private float _width = 20f;
        [SerializeField] private float _height = 40f;

        [Header("Zona")]
        [SerializeField] private float _playerZoneSize = 5f;   // Z: 0..5
        [SerializeField] private float _spawnZoneSize = 10f;   // Z: 30..40
        [SerializeField] private float _defenseLineZ = 5f;
        [SerializeField] private float _nearMissBand = 0.5f;

        [Header("Fisika dinding")]
        [SerializeField] private float _wallRestitution = 0.95f;

        // --- IArenaQuery ---
        public float XMin => -_width * 0.5f;
        public float XMax => _width * 0.5f;
        public float ZMin => 0f;
        public float ZMax => _height;
        public float WallRestitution => _wallRestitution;
        public float DefenseLineZ => _defenseLineZ;
        public float NearMissZ => _defenseLineZ + _nearMissBand;
        public float SpawnZoneMinZ => _height - _spawnZoneSize;
        public float CombatZoneMinZ => _playerZoneSize;
        public float CombatZoneMaxZ => _height - _spawnZoneSize;

        /// <summary>Lebar efektif yang bisa ditempati crowd tanpa menyentuh dinding.</summary>
        public float UsableWidth(float unitRadius) => _width - unitRadius * 2f;

        public bool ContainsXZ(Vector3 p) =>
            p.x >= XMin && p.x <= XMax && p.z >= ZMin && p.z <= ZMax;

        /// <summary>
        /// Apakah titik berada di luar dinding SAMPING (yang memantulkan)?
        /// Dipakai sebagai pengecekan cepat sebelum sweep presisi.
        /// </summary>
        public bool OutsideSideWalls(Vector3 p, float radius) =>
            p.x - radius < XMin || p.x + radius > XMax;

        /// <summary>
        /// Apakah peluru sudah keluar lewat atas/bawah? Di sana peluru MATI,
        /// bukan memantul (spawn gate & garis pertahanan bukan bumper).
        /// </summary>
        public bool ExitedLengthwise(Vector3 p, float radius) =>
            p.z + radius < ZMin || p.z - radius > ZMax;

        /// <summary>Clamp posisi ke dalam arena — pengaman anti-tunneling.</summary>
        public Vector3 Clamp(Vector3 p, float radius)
        {
            p.x = Mathf.Clamp(p.x, XMin + radius, XMax - radius);
            p.z = Mathf.Clamp(p.z, ZMin, ZMax);
            return p;
        }

#if UNITY_EDITOR
        private void OnDrawGizmos()
        {
            // Visualisasi zona di Scene view — membantu level design.
            Gizmos.color = new Color(0.7f, 0.3f, 1f, 1f);          // dinding bumper
            Gizmos.DrawLine(new Vector3(XMin, 0, ZMin), new Vector3(XMin, 0, ZMax));
            Gizmos.DrawLine(new Vector3(XMax, 0, ZMin), new Vector3(XMax, 0, ZMax));

            Gizmos.color = new Color(0f, 0.9f, 1f, 1f);            // garis pertahanan
            Gizmos.DrawLine(new Vector3(XMin, 0, _defenseLineZ), new Vector3(XMax, 0, _defenseLineZ));

            Gizmos.color = new Color(1f, 0.3f, 0.2f, 0.5f);        // batas spawn zone
            Gizmos.DrawLine(new Vector3(XMin, 0, SpawnZoneMinZ), new Vector3(XMax, 0, SpawnZoneMinZ));
        }
#endif
    }
}
