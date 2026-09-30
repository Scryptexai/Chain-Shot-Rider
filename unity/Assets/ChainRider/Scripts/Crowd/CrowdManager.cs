// ---------------------------------------------------------------------------
// CrowdManager.cs — INTI CROWD. Spawn, formasi, gerak, separation, damage.
//
// ARSITEKTUR SINGKAT
//   - Musuh disimpan di array struct (_enemies), BUKAN GameObject.
//   - Broadphase memakai uniform spatial grid (cell 1.0 unit) yang dibangun
//     ulang tiap tick. Grid ini dipakai oleh dua konsumen:
//         a) BulletSystem  → query tabrakan peluru vs crowd
//         b) BoidSeparation → tetangga untuk separation
//     Membangun sekali, memakai dua kali → hemat.
//   - Rendering memakai Graphics.DrawMeshInstanced: 1 draw call per 1023 musuh
//     per tipe. Tidak ada Transform yang di-update sama sekali.
//
// KENAPA TIDAK ECS PENUH?
//   Skeleton ini sengaja ditulis dengan array biasa + struct supaya bisa jalan
//   di proyek URP standar. Semua tipe data sudah blittable, jadi migrasi ke
//   NativeArray + IJobParallelFor + Burst adalah perubahan mekanis, bukan
//   rewrite. Lihat catatan "// DOTS:" di bawah untuk titik migrasi.
// ---------------------------------------------------------------------------

using System.Collections.Generic;
using UnityEngine;
using ChainRider.Core;
using ChainRider.Config;
using ChainRider.BulletSim;

namespace ChainRider.Crowd
{
    public sealed class CrowdManager : MonoBehaviour, ICrowdQuery
    {
        [Header("Config")]
        [SerializeField] private SpawnConfigSO _spawnCfg;
        [SerializeField] private ArenaConfigSO _arenaCfg;
        [SerializeField] private EnemyStats[] _stats = new EnemyStats[7];

        [Header("Rendering (GPU Instancing)")]
        [SerializeField] private Mesh[] _meshByType = new Mesh[7];
        [SerializeField] private Mesh _billboardMesh;             // LOD jauh
        [SerializeField] private Material[] _materialByType = new Material[7];
        [SerializeField] private float _lodDistance = 26f;

        // ---- Penyimpanan musuh (SoA-ready) -------------------------------
        private EnemyData[] _enemies;
        private int _capacity;
        private int _aliveCount;
        private readonly Stack<int> _freeSlots = new(512);

        // ---- Spatial grid ------------------------------------------------
        private const float CellSize = 1.0f;
        private int _gridW, _gridH;
        private int[] _cellStart;     // index awal tiap cell di _cellItems
        private int[] _cellCount;
        private int[] _cellItems;     // indeks musuh, terurut per cell

        // ---- Buffer instancing (dialokasi sekali, dipakai selamanya) ------
        private Matrix4x4[][] _matrixBatches;   // [type][1023]
        private int[] _batchCounts;
        private MaterialPropertyBlock _mpb;

        // ---- Wave state ---------------------------------------------------
        private DeterministicRng _rng;
        private Vector3[] _formationBuffer;
        private int _nextEnemyId = 1;
        private int _totalSpawnedThisWave;
        private int _leakedThisWave;

        public int AliveCount => _aliveCount;
        public int LeakedThisWave => _leakedThisWave;
        public bool IsWaveCleared => _aliveCount == 0;

        // ==================================================================
        // INIT
        // ==================================================================

        public void Init(int seed)
        {
            _rng = new DeterministicRng(seed);
            _capacity = _spawnCfg.poolSize;                     // 500
            _enemies = new EnemyData[_capacity];
            _formationBuffer = new Vector3[_spawnCfg.maxActiveEnemies];

            _freeSlots.Clear();
            for (int i = _capacity - 1; i >= 0; i--) _freeSlots.Push(i);

            // Grid menutupi seluruh arena.
            _gridW = Mathf.CeilToInt(_arenaCfg.width / CellSize) + 2;
            _gridH = Mathf.CeilToInt(_arenaCfg.height / CellSize) + 2;
            int cells = _gridW * _gridH;
            _cellStart = new int[cells];
            _cellCount = new int[cells];
            _cellItems = new int[_capacity];

            // Pra-alokasi buffer instancing: 7 tipe × 1023 matriks.
            _matrixBatches = new Matrix4x4[7][];
            for (int t = 0; t < 7; t++) _matrixBatches[t] = new Matrix4x4[1023];
            _batchCounts = new int[7];
            _mpb = new MaterialPropertyBlock();

            _aliveCount = 0;
        }

        // ==================================================================
        // SPAWN
        // ==================================================================

        /// <summary>
        /// Memunculkan satu wave di spawn zone (Z = 30..40).
        /// Formasi dibangun di ruang lokal lalu digeser ke atas arena.
        /// </summary>
        public void SpawnWave(int waveIndex)
        {
            int count = _spawnCfg.enemiesPerWave[Mathf.Min(waveIndex, _spawnCfg.enemiesPerWave.Length - 1)];
            FormationKind formation = _spawnCfg.formation[Mathf.Min(waveIndex, _spawnCfg.formation.Length - 1)];

            count = Mathf.Min(count, _spawnCfg.maxActiveEnemies - _aliveCount);
            if (count <= 0) return;

            int columns = _rng.Range(_spawnCfg.columnsMin, _spawnCfg.columnsMax + 1);
            float halfUsable = _arenaCfg.width * 0.5f - 1.2f;   // sisakan margin dari dinding

            int n = FormationBuilder.Build(formation, count, columns, _spawnCfg.spacing,
                                           halfUsable, _formationBuffer);
            FormationBuilder.ApplyJitter(_formationBuffer, n, _spawnCfg.spacing * 0.12f, ref _rng);

            // Origin formasi: tepat di atas gerbang spawn, sehingga musuh
            // "mengalir masuk" alih-alih muncul tiba-tiba di layar.
            float baseZ = _arenaCfg.height + 1f;

            for (int i = 0; i < n; i++)
            {
                EnemyType type = PickTypeForWave(waveIndex, i);
                Vector3 pos = _formationBuffer[i];
                Spawn(type, new Vector3(pos.x, 0f, baseZ + pos.z), i);
            }

            _totalSpawnedThisWave = n;
            _leakedThisWave = 0;
            GameEvents.RaiseWaveStarted(new WaveEvt(waveIndex, n, formation));
        }

        /// <summary>Komposisi tipe musuh per wave. Deterministik via _rng.</summary>
        private EnemyType PickTypeForWave(int waveIndex, int slot)
        {
            // Baris depan sengaja diisi grunt agar pemain selalu punya target
            // "empuk" untuk memicu bullet riding di kontak pertama.
            if (slot < 6) return EnemyType.Grunt;

            System.Span<float> w = stackalloc float[6];
            switch (waveIndex)
            {
                case 0: w[0] = 1.0f; w[1] = 0.0f; w[2] = 0f; w[3] = 0f; w[4] = 0f; w[5] = 0f; break;
                case 1: w[0] = 0.7f; w[1] = 0.3f; w[2] = 0f; w[3] = 0f; w[4] = 0f; w[5] = 0f; break;
                case 2: w[0] = 0.5f; w[1] = 0.2f; w[2] = 0.1f; w[3] = 0.1f; w[4] = 0.1f; w[5] = 0f; break;
                case 3: w[0] = 0.4f; w[1] = 0.2f; w[2] = 0.12f; w[3] = 0.12f; w[4] = 0.08f; w[5] = 0.08f; break;
                default: w[0] = 0.35f; w[1] = 0.2f; w[2] = 0.15f; w[3] = 0.1f; w[4] = 0.1f; w[5] = 0.1f; break;
            }
            return (EnemyType)_rng.WeightedIndex(w);
        }

        public int Spawn(EnemyType type, Vector3 position, int formationIndex)
        {
            if (_freeSlots.Count == 0) return -1;               // pool habis: tolak, jangan Instantiate

            int slot = _freeSlots.Pop();
            ref EnemyStats st = ref _stats[(int)type];

            EnemyFlags flags = EnemyFlags.Alive;
            if (st.armored) flags |= EnemyFlags.Armored;
            if (st.explodeOnDeath) flags |= EnemyFlags.ExplodeOnDeath;
            if (st.splitOnDeath) flags |= EnemyFlags.SplitOnDeath;

            _enemies[slot] = new EnemyData
            {
                Id = _nextEnemyId++,
                Type = type,
                Flags = flags,
                Position = position,
                PrevPosition = position,
                Velocity = Vector3.zero,
                Hp = st.hp,
                MaxHp = st.hp,
                Speed = st.speed * _rng.Range(0.9f, 1.1f),      // variasi kecil, deterministik
                Radius = st.radius,
                SwayPhase = _rng.Range(0f, Mathf.PI * 2f),
                FormationIndex = formationIndex,
            };

            _aliveCount++;
            return slot;
        }

        // ==================================================================
        // TICK — gerak + separation + grid + cek garis pertahanan
        // ==================================================================

        public void Tick(float dt, float simTime)
        {
            // DOTS: tiga loop di bawah adalah kandidat langsung IJobParallelFor.
            BuildSpatialGrid();
            MoveEnemies(dt, simTime);
            CheckDefenseLine();
        }

        private void MoveEnemies(float dt, float simTime)
        {
            float defenseZ = _arenaCfg.defenseLineZ;
            float halfW = _arenaCfg.width * 0.5f;

            for (int i = 0; i < _capacity; i++)
            {
                ref EnemyData e = ref _enemies[i];
                if (!e.IsAlive) continue;

                e.PrevPosition = e.Position;

                // --- 1. Turun ke arah player ------------------------------
                Vector3 v = new Vector3(0f, 0f, -e.Speed);

                // --- 2. Sway horizontal (bukan random per-frame!) ---------
                // Memakai simTime + phase per musuh → mulus, deterministik,
                // dan tiap musuh bergerak sedikit berbeda tanpa terlihat kacau.
                float sway = Mathf.Sin(simTime * _spawnCfg.swayFrequency * Mathf.PI * 2f + e.SwayPhase);
                v.x += sway * _spawnCfg.swayAmplitude;

                // --- 3. Soft separation (boids ringan) --------------------
                // Musuh tidak saling menabrak tapi juga tidak ber-collider.
                // Cukup dorongan lembut dari tetangga terdekat.
                v += ComputeSeparation(i, in e) * _spawnCfg.separationWeight;

                e.Velocity = v;
                e.Position += v * dt;

                // --- 4. Clamp ke dalam dinding ----------------------------
                // Dinding memantulkan PELURU, bukan musuh. Musuh cuma ditahan.
                if (e.Position.x < -halfW + e.Radius) e.Position.x = -halfW + e.Radius;
                else if (e.Position.x > halfW - e.Radius) e.Position.x = halfW - e.Radius;

                // --- 5. Near miss: heartbeat SFX --------------------------
                if ((e.Flags & EnemyFlags.NearMissFired) == 0 &&
                    e.Position.z <= defenseZ + _arenaCfg.nearMissBandZ)
                {
                    e.Flags |= EnemyFlags.NearMissFired;
                    GameEvents.RaiseEnemyNearMiss(e.Position);
                }
            }
        }

        /// <summary>
        /// Separation berbasis grid: hanya memeriksa 9 cell di sekitar musuh,
        /// bukan seluruh crowd. Kompleksitas O(n·k) dengan k kecil (~6),
        /// bukan O(n²) yang akan membunuh performa di 200 musuh.
        /// </summary>
        private Vector3 ComputeSeparation(int selfIndex, in EnemyData self)
        {
            Vector3 push = Vector3.zero;
            float r = _spawnCfg.separationRadius;
            float r2 = r * r;
            int neighbours = 0;
            Vector3 avgVel = Vector3.zero;

            (int cx, int cz) = WorldToCell(self.Position);

            for (int dz = -1; dz <= 1; dz++)
            for (int dx = -1; dx <= 1; dx++)
            {
                int gx = cx + dx, gz = cz + dz;
                if (gx < 0 || gz < 0 || gx >= _gridW || gz >= _gridH) continue;

                int cell = gz * _gridW + gx;
                int start = _cellStart[cell];
                int count = _cellCount[cell];

                for (int k = 0; k < count; k++)
                {
                    int other = _cellItems[start + k];
                    if (other == selfIndex) continue;

                    ref EnemyData o = ref _enemies[other];
                    Vector3 d = self.Position - o.Position;
                    d.y = 0f;
                    float sq = d.sqrMagnitude;
                    if (sq > r2 || sq < 1e-6f) continue;

                    // Dorongan berbanding terbalik dengan jarak.
                    float dist = Mathf.Sqrt(sq);
                    push += (d / dist) * (1f - dist / r);
                    avgVel += o.Velocity;
                    neighbours++;
                }
            }

            if (neighbours == 0) return Vector3.zero;

            // Alignment ringan: musuh ikut arah rata-rata tetangga sedikit saja,
            // supaya crowd terasa "satu kesatuan" tanpa jadi kaku.
            avgVel /= neighbours;
            return push + (avgVel - self.Velocity) * _spawnCfg.alignmentWeight * 0.1f;
        }

        private void CheckDefenseLine()
        {
            float defenseZ = _arenaCfg.defenseLineZ;
            for (int i = 0; i < _capacity; i++)
            {
                ref EnemyData e = ref _enemies[i];
                if (!e.IsAlive) continue;
                if (e.Position.z > defenseZ) continue;

                // Musuh menembus garis: player kehilangan HP, musuh dihapus
                // (tidak menumpuk di player zone).
                GameEvents.RaiseEnemyBreached(e.Position);
                _leakedThisWave++;
                Despawn(i, killed: false);
            }
        }

        // ==================================================================
        // SPATIAL GRID
        // ==================================================================

        private (int, int) WorldToCell(Vector3 p)
        {
            int cx = Mathf.Clamp(Mathf.FloorToInt((p.x + _arenaCfg.width * 0.5f) / CellSize), 0, _gridW - 1);
            int cz = Mathf.Clamp(Mathf.FloorToInt(p.z / CellSize), 0, _gridH - 1);
            return (cx, cz);
        }

        /// <summary>
        /// Counting sort dua-lintasan. Tanpa alokasi, tanpa List, tanpa Dictionary.
        /// Ini salah satu alasan utama game bisa 200 musuh di Snapdragon 660.
        /// </summary>
        private void BuildSpatialGrid()
        {
            System.Array.Clear(_cellCount, 0, _cellCount.Length);

            // Lintasan 1: hitung isi tiap cell.
            for (int i = 0; i < _capacity; i++)
            {
                if (!_enemies[i].IsAlive) continue;
                (int cx, int cz) = WorldToCell(_enemies[i].Position);
                _cellCount[cz * _gridW + cx]++;
            }

            // Prefix sum → offset awal tiap cell.
            int running = 0;
            for (int c = 0; c < _cellStart.Length; c++)
            {
                _cellStart[c] = running;
                running += _cellCount[c];
                _cellCount[c] = 0;                 // dipakai lagi sebagai cursor
            }

            // Lintasan 2: isi item.
            for (int i = 0; i < _capacity; i++)
            {
                if (!_enemies[i].IsAlive) continue;
                (int cx, int cz) = WorldToCell(_enemies[i].Position);
                int cell = cz * _gridW + cx;
                _cellItems[_cellStart[cell] + _cellCount[cell]] = i;
                _cellCount[cell]++;
            }
        }

        // ==================================================================
        // ICrowdQuery — dipanggil BulletController
        // ==================================================================

        /// <summary>
        /// Sapu segmen gerak peluru terhadap crowd.
        /// Musuh biasa DITEMBUS (kena damage, peluru jalan terus);
        /// musuh berarmor MEMANTULKAN peluru (lihat catatan desain di BulletController).
        /// </summary>
        public int SweepDamage(Vector3 from, Vector3 delta, float radius, float damage,
                               out bool touchedAnyEnemy, out SweepHit reflectiveHit)
        {
            touchedAnyEnemy = false;
            reflectiveHit = SweepHit.None;
            int kills = 0;
            float bestT = float.MaxValue;

            // Broadphase: hanya cell yang dilewati AABB segmen.
            Vector3 to = from + delta;
            float minX = Mathf.Min(from.x, to.x) - radius;
            float maxX = Mathf.Max(from.x, to.x) + radius;
            float minZ = Mathf.Min(from.z, to.z) - radius;
            float maxZ = Mathf.Max(from.z, to.z) + radius;

            (int x0, int z0) = WorldToCell(new Vector3(minX, 0f, minZ));
            (int x1, int z1) = WorldToCell(new Vector3(maxX, 0f, maxZ));

            for (int gz = z0; gz <= z1; gz++)
            for (int gx = x0; gx <= x1; gx++)
            {
                int cell = gz * _gridW + gx;
                int start = _cellStart[cell];
                int count = _cellCount[cell];

                for (int k = 0; k < count; k++)
                {
                    int idx = _cellItems[start + k];
                    ref EnemyData e = ref _enemies[idx];
                    if (!e.IsAlive) continue;

                    if (!RicochetSolver.SweepCircle(from, delta, radius, e.Position, e.Radius,
                                                    out float t, out Vector3 point, out Vector3 normal))
                        continue;

                    touchedAnyEnemy = true;

                    // Musuh berarmor: peluru memantul di sini, dan musuh di
                    // BELAKANG titik ini tidak boleh kena damage pada substep ini.
                    if (e.IsArmored && t < bestT)
                    {
                        // Shielder hanya kebal dari DEPAN (arah datang berlawanan
                        // dengan hadapnya). Dari samping/belakang ia tembus biasa.
                        bool frontal = Vector3.Dot(delta.normalized, Vector3.back) > 0.3f;
                        if (e.Type == EnemyType.Brute || (e.Type == EnemyType.Shielder && frontal))
                        {
                            bestT = t;
                            reflectiveHit = new SweepHit(t, point, normal, SurfaceKind.Enemy, idx, 1f);
                            ApplyDamage(idx, damage * 0.5f);     // armor menyerap separuh
                            continue;
                        }
                    }

                    // Musuh biasa: kena damage penuh, peluru menembus.
                    if (t <= bestT && ApplyDamage(idx, damage))
                        kills++;
                }
            }

            return kills;
        }

        public int ExplodeAt(Vector3 center, float radius, float damage, int chainDepth)
        {
            int kills = 0;
            float r2 = radius * radius;

            (int x0, int z0) = WorldToCell(new Vector3(center.x - radius, 0f, center.z - radius));
            (int x1, int z1) = WorldToCell(new Vector3(center.x + radius, 0f, center.z + radius));

            for (int gz = z0; gz <= z1; gz++)
            for (int gx = x0; gx <= x1; gx++)
            {
                int cell = gz * _gridW + gx;
                int start = _cellStart[cell];
                int count = _cellCount[cell];

                for (int k = 0; k < count; k++)
                {
                    int idx = _cellItems[start + k];
                    ref EnemyData e = ref _enemies[idx];
                    if (!e.IsAlive) continue;

                    Vector3 d = e.Position - center; d.y = 0f;
                    float sq = d.sqrMagnitude;
                    if (sq > r2) continue;

                    // Falloff linear dari pusat ke tepi.
                    float falloff = 1f - Mathf.Sqrt(sq) / radius;
                    if (ApplyDamage(idx, damage * falloff)) kills++;
                }
            }

            GameEvents.RaiseExplosion(new ExplosionEvt(center, radius, chainDepth));
            return kills;
        }

        /// <returns>true kalau musuh mati akibat damage ini.</returns>
        private bool ApplyDamage(int index, float damage)
        {
            ref EnemyData e = ref _enemies[index];
            if (!e.IsAlive) return false;

            e.Hp -= damage;
            if (e.Hp > 0f) return false;

            Vector3 pos = e.Position;
            EnemyType type = e.Type;
            EnemyFlags flags = e.Flags;
            int score = _stats[(int)type].score;

            Despawn(index, killed: true);

            // Efek kematian khusus. Dilakukan SETELAH despawn supaya slot bebas
            // bisa langsung dipakai oleh splitter.
            if ((flags & EnemyFlags.SplitOnDeath) != 0)
            {
                for (int s = 0; s < 3; s++)
                {
                    float a = s * Mathf.PI * 2f / 3f;
                    Spawn(EnemyType.Grunt, pos + new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a)) * 0.6f, s);
                }
            }
            if ((flags & EnemyFlags.ExplodeOnDeath) != 0)
            {
                ref EnemyStats st = ref _stats[(int)type];
                ExplodeAt(pos, st.explosionRadius, st.explosionDamage, 1);
            }

            GameEvents.RaiseEnemyKilled(new EnemyKilledEvt(e.Id, (byte)type, pos, score, 0));
            return true;
        }

        private void Despawn(int index, bool killed)
        {
            ref EnemyData e = ref _enemies[index];
            if (!e.IsAlive) return;
            e.Flags &= ~EnemyFlags.Alive;
            _aliveCount--;
            _freeSlots.Push(index);
        }

        public void ClearAll()
        {
            for (int i = 0; i < _capacity; i++)
                if (_enemies[i].IsAlive) Despawn(i, false);
            _aliveCount = 0;
        }

        // ==================================================================
        // RENDER — GPU Instancing, nol Transform
        // ==================================================================

        /// <summary>
        /// Dipanggil tiap frame render (bukan tiap tick). Membangun matriks dari
        /// posisi ter-interpolasi lalu mengirim satu DrawMeshInstanced per tipe.
        /// </summary>
        public void RenderCrowd(float alpha, Vector3 cameraPos)
        {
            for (int t = 0; t < _batchCounts.Length; t++) _batchCounts[t] = 0;

            float lodSq = _lodDistance * _lodDistance;

            for (int i = 0; i < _capacity; i++)
            {
                ref EnemyData e = ref _enemies[i];
                if (!e.IsAlive) continue;

                Vector3 p = Vector3.LerpUnclamped(e.PrevPosition, e.Position, alpha);
                int t = (int)e.Type;

                // Batch penuh (1023 = batas DrawMeshInstanced) → flush dulu.
                if (_batchCounts[t] >= 1023) FlushBatch(t, (p - cameraPos).sqrMagnitude > lodSq);

                // Sedikit rotasi mengikuti arah gerak agar crowd terasa hidup.
                Quaternion rot = Quaternion.LookRotation(
                    e.Velocity.sqrMagnitude > 1e-4f ? -e.Velocity.normalized : Vector3.back, Vector3.up);

                _matrixBatches[t][_batchCounts[t]++] = Matrix4x4.TRS(p, rot, Vector3.one);
            }

            for (int t = 0; t < _batchCounts.Length; t++)
                if (_batchCounts[t] > 0) FlushBatch(t, false);
        }

        private void FlushBatch(int type, bool useBillboard)
        {
            Mesh mesh = useBillboard && _billboardMesh != null ? _billboardMesh : _meshByType[type];
            if (mesh == null || _materialByType[type] == null) { _batchCounts[type] = 0; return; }

            _mpb.SetColor("_BaseColor", _stats[type].color);

            Graphics.DrawMeshInstanced(
                mesh, 0, _materialByType[type],
                _matrixBatches[type], _batchCounts[type], _mpb,
                UnityEngine.Rendering.ShadowCastingMode.Off,   // crowd tidak cast shadow
                receiveShadows: false);

            _batchCounts[type] = 0;
        }

        // ==================================================================
        // DEBUG
        // ==================================================================

        public int DebugSpawnedThisWave => _totalSpawnedThisWave;
    }
}
