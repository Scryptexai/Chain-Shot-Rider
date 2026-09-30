// ---------------------------------------------------------------------------
// ReplayRecorder.cs — Bukti bahwa game ini benar-benar deterministik.
//
// Yang direkam hanya DUA hal:
//   1. seed (int)
//   2. stream InputFrame per tick
//
// Tidak ada posisi, tidak ada state musuh. Kalau replay menghasilkan skor akhir
// dan checksum posisi yang sama dengan run aslinya, berarti simulasi memang
// deterministik. Kalau berbeda, ada sumber non-determinisme yang bocor
// (UnityEngine.Random, Time.deltaTime, urutan Dictionary, dsb).
//
// Ukuran file: 5 byte/tick x 60 tick/detik x 180 detik = ~54 KB per run.
// ---------------------------------------------------------------------------

using System.Collections.Generic;
using System.IO;
using UnityEngine;
using ChainRider.InputSys;

namespace ChainRider.DebugTools
{
    public sealed class ReplayRecorder : MonoBehaviour
    {
        public const ushort FormatVersion = 1;

        private readonly List<InputFrame> _frames = new(60 * 180);
        private int _seed;
        private int _variantIndex;
        private bool _recording;

        public int FrameCount => _frames.Count;
        public bool IsRecording => _recording;

        public void BeginRecording(int seed, int variantIndex)
        {
            _seed = seed;
            _variantIndex = variantIndex;
            _frames.Clear();
            _recording = true;
        }

        public void Record(int tick, in InputFrame frame)
        {
            if (!_recording) return;
            // tick dipakai sebagai assert: harus selalu == _frames.Count.
            Debug.Assert(tick == _frames.Count, $"Replay desync: tick {tick} != {_frames.Count}");
            _frames.Add(frame);
        }

        public void Save(string path)
        {
            using var w = new BinaryWriter(File.Create(path));
            w.Write(FormatVersion);
            w.Write(_seed);
            w.Write(_variantIndex);
            w.Write(_frames.Count);
            for (int i = 0; i < _frames.Count; i++)
            {
                w.Write(_frames[i].Tap);
                // Kuantisasi steer ke sbyte: presisi 1/127 sudah jauh di bawah
                // ambang persepsi, dan menjaga file tetap kecil + deterministik
                // (float di file bisa berbeda pembulatan antar platform).
                w.Write((sbyte)Mathf.RoundToInt(Mathf.Clamp(_frames[i].SteerAxis, -1f, 1f) * 127f));
            }
        }

        public (int seed, int variant, InputFrame[] frames) Load(string path)
        {
            using var r = new BinaryReader(File.OpenRead(path));
            ushort version = r.ReadUInt16();
            if (version != FormatVersion) throw new IOException($"Replay version {version} tidak didukung.");

            int seed = r.ReadInt32();
            int variant = r.ReadInt32();
            int count = r.ReadInt32();
            var frames = new InputFrame[count];
            for (int i = 0; i < count; i++)
                frames[i] = new InputFrame { Tap = r.ReadBoolean(), SteerAxis = r.ReadSByte() / 127f };

            return (seed, variant, frames);
        }

        /// <summary>
        /// Checksum state simulasi. Dipanggil tiap 60 tick saat mode verifikasi.
        /// Dua run dengan seed+input sama WAJIB menghasilkan urutan checksum sama.
        /// </summary>
        public static uint Checksum(Vector3 bulletPos, int aliveEnemies, int score)
        {
            unchecked
            {
                uint h = 2166136261u;
                h = (h ^ (uint)Mathf.RoundToInt(bulletPos.x * 1000f)) * 16777619u;
                h = (h ^ (uint)Mathf.RoundToInt(bulletPos.z * 1000f)) * 16777619u;
                h = (h ^ (uint)aliveEnemies) * 16777619u;
                h = (h ^ (uint)score) * 16777619u;
                return h;
            }
        }
    }
}
