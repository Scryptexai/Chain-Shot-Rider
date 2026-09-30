using UnityEditor;
using UnityEngine;

namespace ChainRider.EditorTools
{
    /// <summary>
    /// ProjectSetup — applies the project settings the design documents require.
    ///
    /// These are applied from code rather than shipped as hand-written
    /// ProjectSettings YAML on purpose: a partially hand-authored settings asset
    /// can silently corrupt a project, while this is inspectable, re-runnable, and
    /// fails loudly. Run once after opening the project.
    ///
    /// Run: menu ChainRider -> Apply Project Settings.
    /// </summary>
    public static class ProjectSetup
    {
        /// <summary>
        /// Layer assignment from docs/01. Indices are fixed because collision
        /// filtering and culling masks reference them by number.
        /// </summary>
        private static readonly (int index, string name)[] Layers =
        {
            (8,  "Player"),
            (9,  "Bullet"),
            (10, "Enemy"),
            (11, "Wall"),
            (12, "Bumper"),
            (13, "Obstacle"),
            (14, "Killzone"),
            (15, "FX"),
        };

        [MenuItem("ChainRider/Apply Project Settings", priority = 1)]
        public static void Apply()
        {
            ApplyLayers();
            ApplyOrientation();
            ApplyRendering();
            ApplyPhysics();

            AssetDatabase.SaveAssets();
            Debug.Log("[ChainRider] Project settings applied: layers, portrait lock, linear color, physics off.");
        }

        private static void ApplyLayers()
        {
            SerializedObject tagManager = new(
                AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset")[0]);
            SerializedProperty layers = tagManager.FindProperty("layers");

            foreach ((int index, string name) in Layers)
            {
                if (index >= layers.arraySize)
                {
                    Debug.LogWarning($"[ChainRider] Layer slot {index} unavailable; skipped '{name}'.");
                    continue;
                }
                layers.GetArrayElementAtIndex(index).stringValue = name;
            }
            tagManager.ApplyModifiedProperties();
        }

        private static void ApplyOrientation()
        {
            // Portrait only. The whole layout, camera framing and thumb ergonomics
            // assume 9:16; allowing landscape would silently break the HUD.
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
            PlayerSettings.allowedAutorotateToPortrait = true;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = false;
            PlayerSettings.allowedAutorotateToLandscapeRight = false;

            PlayerSettings.companyName = "ChainRider";
            PlayerSettings.productName = "Chain Rider";
        }

        private static void ApplyRendering()
        {
            PlayerSettings.colorSpace = ColorSpace.Linear;

            // Mobile target: OpenGL ES 3 / Vulkan handled by Unity defaults; we only
            // force the parts the performance budget depends on.
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[]
            {
                UnityEngine.Rendering.GraphicsDeviceType.Vulkan,
                UnityEngine.Rendering.GraphicsDeviceType.OpenGLES3,
            });
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64 | AndroidArchitecture.ARMv7;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;

            // 60 FPS target; vSync off so Application.targetFrameRate is authoritative.
            for (int i = 0; i < QualitySettings.names.Length; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.vSyncCount = 0;
                QualitySettings.shadowDistance = 25f;   // only player + boss cast shadows
            }
        }

        private static void ApplyPhysics()
        {
            // Hard constraint from the brief: ricochet is solved with manual
            // reflection vectors, never a physics engine. Nothing in the game has a
            // Collider or Rigidbody, so stepping the physics world is pure waste.
            Physics.simulationMode = SimulationMode.Script;
            Physics2D.simulationMode = SimulationMode2D.Script;
        }
    }
}
