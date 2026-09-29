// ---------------------------------------------------------------------------
// AudioDirector.cs — Voice pool, pitch ladder, ducking, prioritas.
//
// MASALAH YANG DISELESAIKAN:
//   Saat 200 musuh mati dalam 0.5 detik, memutar 200 AudioSource akan:
//     - menghabiskan voice budget OS (biasanya 32)
//     - menghasilkan clipping dan "suara pasir"
//     - memakan CPU audio thread
//   Solusi: voice pool 8 + cooldown per cue + prioritas.
//
// PITCH LADDER BOUNCE:
//   SFX "ting" naik semitone tiap bounce. Ini satu-satunya feedback paling
//   penting di game ini — pemain mendengar combo-nya tumbuh tanpa melihat UI.
// ---------------------------------------------------------------------------

using UnityEngine;
using UnityEngine.Audio;
using ChainRider.Core;

namespace ChainRider.AudioSys
{
    public enum CueId : byte
    {
        Shot = 0, Bounce = 1, Kill = 2, ComboMilestone = 3, Explosion = 4,
        SlowMoEnter = 5, SlowMoExit = 6, Heartbeat = 7, Breach = 8,
        PerfectClear = 9, KillMilestone = 10, BulletExpire = 11,
    }

    [System.Serializable]
    public struct SfxCue
    {
        public CueId id;
        public AudioClip[] clips;        // variasi, dipilih round-robin (bukan random)
        [Range(0f, 1f)] public float volume;
        public float basePitch;
        [Tooltip("Jeda minimum antar pemutaran cue yang sama, detik.")]
        public float cooldown;
        [Tooltip("0 = tertinggi. Cue prioritas rendah dibuang saat voice penuh.")]
        public int priority;
    }

    public sealed class AudioDirector : MonoBehaviour
    {
        [Header("Mixer")]
        [SerializeField] private AudioMixerGroup _sfxGroup;
        [SerializeField] private AudioMixerGroup _musicGroup;

        [Header("Voices")]
        [SerializeField] private int _voiceCount = 8;

        [Header("Cues")]
        [SerializeField] private SfxCue[] _cues;

        [Header("Music")]
        [SerializeField] private AudioSource _musicSource;
        [SerializeField] private AudioClip _musicBase;      // loop 60 detik, 120 BPM
        [SerializeField] private AudioClip[] _musicLayers;  // 1 layer per varian arena

        private AudioSource[] _voices;
        private float[] _voiceFreeAt;
        private int[] _voicePriority;
        private float[] _cueCooldownUntil;
        private int[] _clipCursor;

        private int _bounceLadder;      // 0..11, semitone
        private const float SemitoneRatio = 1.05946f;

        private void Awake()
        {
            _voices = new AudioSource[_voiceCount];
            _voiceFreeAt = new float[_voiceCount];
            _voicePriority = new int[_voiceCount];

            for (int i = 0; i < _voiceCount; i++)
            {
                var go = new GameObject($"Voice_{i}");
                go.transform.SetParent(transform, false);
                AudioSource s = go.AddComponent<AudioSource>();
                s.playOnAwake = false;
                s.outputAudioMixerGroup = _sfxGroup;
                s.spatialBlend = 0f;          // 2D: arena kecil, panning tidak membantu
                _voices[i] = s;
            }

            _cueCooldownUntil = new float[System.Enum.GetValues(typeof(CueId)).Length];
            _clipCursor = new int[_cueCooldownUntil.Length];
        }

        private void OnEnable()
        {
            GameEvents.OnBulletFired += _ => Play(CueId.Shot);
            GameEvents.OnBounce += HandleBounce;
            GameEvents.OnEnemyKilled += _ => Play(CueId.Kill);
            GameEvents.OnCombo += HandleCombo;
            GameEvents.OnExplosion += _ => Play(CueId.Explosion);
            GameEvents.OnEnemyNearMiss += _ => Play(CueId.Heartbeat);
            GameEvents.OnEnemyBreached += _ => Play(CueId.Breach);
            GameEvents.OnPerfectClear += () => Play(CueId.PerfectClear);
            GameEvents.OnSlowMoChanged += HandleSlowMo;
            GameEvents.OnBulletExpired += _ => { _bounceLadder = 0; Play(CueId.BulletExpire); };
        }

        // CATATAN: lambda di atas ditulis ringkas untuk skeleton. Di produksi,
        // gunakan method bernama agar bisa di-unsubscribe di OnDisable.

        private void HandleBounce(BounceEvt e)
        {
            // Pitch naik 1 semitone per bounce, reset saat peluru mati.
            _bounceLadder = Mathf.Min(_bounceLadder + 1, 14);
            float pitch = Mathf.Pow(SemitoneRatio, _bounceLadder);
            Play(CueId.Bounce, pitchOverride: pitch);
        }

        private void HandleCombo(ComboEvt e)
        {
            if (e.IsMilestone) Play(CueId.ComboMilestone);
        }

        private void HandleSlowMo(SlowMoEvt e)
        {
            Play(e.TargetTimeScale < 0.95f ? CueId.SlowMoEnter : CueId.SlowMoExit);

            // Musik ikut melambat sedikit — 0.85x, bukan 0.3x (0.3x terdengar rusak).
            if (_musicSource != null)
                _musicSource.pitch = Mathf.Lerp(0.85f, 1f, Mathf.InverseLerp(0.3f, 1f, e.TargetTimeScale));
        }

        // ==================================================================
        // PLAY
        // ==================================================================

        public void Play(CueId id, float pitchOverride = -1f)
        {
            int idx = (int)id;
            if (idx >= _cues.Length) return;
            ref SfxCue cue = ref _cues[idx];
            if (cue.clips == null || cue.clips.Length == 0) return;

            // Cooldown: mencegah 200 "pop" kill dalam satu frame.
            float now = Time.unscaledTime;
            if (now < _cueCooldownUntil[idx]) return;
            _cueCooldownUntil[idx] = now + cue.cooldown;

            AudioSource voice = AcquireVoice(cue.priority, now);
            if (voice == null) return;                 // semua voice dipakai cue prioritas lebih tinggi

            // Round-robin, bukan random: variasi terdengar merata dan deterministik.
            AudioClip clip = cue.clips[_clipCursor[idx]];
            _clipCursor[idx] = (_clipCursor[idx] + 1) % cue.clips.Length;

            voice.clip = clip;
            voice.volume = cue.volume;
            voice.pitch = pitchOverride > 0f ? pitchOverride : cue.basePitch;
            voice.Play();
        }

        private AudioSource AcquireVoice(int priority, float now)
        {
            // 1. Voice yang sudah selesai.
            for (int i = 0; i < _voiceCount; i++)
                if (now >= _voiceFreeAt[i]) { _voicePriority[i] = priority; _voiceFreeAt[i] = now + 2f; return _voices[i]; }

            // 2. Curi voice yang prioritasnya lebih rendah (angka lebih besar).
            int worst = -1, worstPriority = priority;
            for (int i = 0; i < _voiceCount; i++)
                if (_voicePriority[i] > worstPriority) { worstPriority = _voicePriority[i]; worst = i; }

            if (worst >= 0) { _voicePriority[worst] = priority; return _voices[worst]; }
            return null;
        }

        // ==================================================================
        // MUSIC
        // ==================================================================

        public void PlayMusic(int variantIndex)
        {
            if (_musicSource == null) return;
            _musicSource.clip = _musicBase;
            _musicSource.loop = true;
            _musicSource.outputAudioMixerGroup = _musicGroup;
            _musicSource.Play();
            // Layer varian di-crossfade oleh AudioMixer snapshot (tidak di-skeleton-kan).
        }
    }
}
