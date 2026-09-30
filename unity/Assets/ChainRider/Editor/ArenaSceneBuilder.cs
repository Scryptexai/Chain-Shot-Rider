using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using ChainRider.AudioSys;
using ChainRider.BulletSim;
using ChainRider.CameraSys;
using ChainRider.Config;
using ChainRider.Core;
using ChainRider.Crowd;
using ChainRider.InputSys;
using ChainRider.Obstacles;
using ChainRider.TimeSys;

namespace ChainRider.EditorTools
{
    /// <summary>
    /// ArenaSceneBuilder — generates 02_Arena.unity and its placeholder prefabs.
    ///
    /// WHY GENERATED INSTEAD OF HAND-AUTHORED YAML
    /// A .unity scene is a graph of GUID references. Writing that by hand outside
    /// the editor produces a file that looks plausible and then fails to open, or
    /// worse, opens with silently broken references. Building it through the real
    /// editor API guarantees the references are valid, and re-running after a
    /// refactor is one click instead of a merge conflict.
    ///
    /// Placeholder art: primitives and unlit colors, sized to the spec in
    /// docs/05-prefab-spec.md. They exist so the scene is playable on day one;
    /// swapping in real meshes later only changes the prefab contents.
    ///
    /// Run: menu ChainRider -> Build Arena Scene.
    /// </summary>
    public static class ArenaSceneBuilder
    {
        private const string SceneDir = "Assets/ChainRider/Scenes";
        private const string ScenePath = SceneDir + "/02_Arena.unity";
        private const string PrefabDir = "Assets/ChainRider/Prefabs";
        private const string MaterialDir = "Assets/ChainRider/Art/Materials";
        private const string ConfigDir = "Assets/ChainRider/Config";

        [MenuItem("ChainRider/Build Arena Scene", priority = 2)]
        public static void Build()
        {
            // Config assets are the scene's inputs; without them the wiring below
            // would produce a scene full of null references that only fails at play.
            var arenaCfg = Load<ArenaConfigSO>($"{ConfigDir}/ArenaConfig.asset");
            if (arenaCfg == null)
            {
                if (!EditorUtility.DisplayDialog("ChainRider",
                        "Config assets not found. Run 'ChainRider -> Import Config From JSON' first.\n\n" +
                        "Import now?", "Import", "Cancel"))
                    return;
                ConfigImporter.Import();
                arenaCfg = Load<ArenaConfigSO>($"{ConfigDir}/ArenaConfig.asset");
                if (arenaCfg == null) return;
            }

            var bulletCfg = Load<BulletConfigSO>($"{ConfigDir}/BulletConfig.asset");
            var spawnCfg = Load<SpawnConfigSO>($"{ConfigDir}/SpawnConfig.asset");
            var slowCfg = Load<SlowMoConfigSO>($"{ConfigDir}/SlowMoConfig.asset");
            var camCfg = Load<CameraConfigSO>($"{ConfigDir}/CameraConfig.asset");
            var aimCfg = Load<AimConfigSO>($"{ConfigDir}/AimConfig.asset");
            VariantSO[] variants = LoadAll<VariantSO>($"{ConfigDir}/Variants");

            EnsureFolder(SceneDir);
            EnsureFolder(PrefabDir);
            EnsureFolder(MaterialDir);

            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // ---------- placeholder art ----------
            Material matPlayer = MakeMaterial("M_Player", new Color(0f, 0.898f, 1f));
            Material matBullet = MakeMaterial("M_Bullet", Color.white);
            Material matEnemy = MakeMaterial("M_Enemy", new Color(1f, 0.302f, 0.239f));
            Material matBumper = MakeMaterial("M_Bumper", new Color(0.694f, 0.302f, 1f));
            Material matPillar = MakeMaterial("M_Pillar", new Color(0.35f, 0.42f, 0.55f));
            Material matBarrel = MakeMaterial("M_Barrel", new Color(1f, 0.55f, 0.15f));
            Material matWell = MakeMaterial("M_GravityWell", new Color(0.45f, 0.25f, 0.9f));
            Material matPlatform = MakeMaterial("M_Platform", new Color(0.25f, 0.65f, 0.7f));
            Material matShield = MakeMaterial("M_ShieldWall", new Color(0.9f, 0.8f, 0.3f));
            Material matFloor = MakeMaterial("M_Floor", new Color(0.047f, 0.071f, 0.16f));

            GameObject bulletPrefab = MakePrefab("P_BulletView", PrimitiveType.Sphere,
                Vector3.one * (bulletCfg != null ? bulletCfg.radius * 2f : 0.5f), matBullet);
            GameObject bumperPrefab = MakePrefab("P_Bumper", PrimitiveType.Cylinder,
                new Vector3(1f, 0.4f, 1f), matBumper);
            GameObject pillarPrefab = MakePrefab("P_Pillar", PrimitiveType.Cylinder,
                new Vector3(1f, 1.2f, 1f), matPillar);
            GameObject barrelPrefab = MakePrefab("P_Barrel", PrimitiveType.Cylinder,
                new Vector3(1.2f, 0.7f, 1.2f), matBarrel);
            GameObject wellPrefab = MakePrefab("P_GravityWell", PrimitiveType.Sphere,
                Vector3.one * 1.5f, matWell);
            GameObject platformPrefab = MakePrefab("P_MovingPlatform", PrimitiveType.Cube,
                new Vector3(5f, 0.3f, 1f), matPlatform);
            GameObject shieldPrefab = MakePrefab("P_ShieldWall", PrimitiveType.Cube,
                new Vector3(4f, 1.2f, 0.4f), matShield);

            // ---------- SYSTEMS ----------
            GameObject systems = new("── SYSTEMS ──");

            GameObject gameRoot = Child(systems, "GameRoot");
            var arenaManager = gameRoot.AddComponent<ArenaManager>();
            gameRoot.AddComponent<SimClock>();

            GameObject timeSystem = Child(systems, "TimeSystem");
            var slowMo = timeSystem.AddComponent<SlowMoSystem>();

            GameObject bulletSystemGo = Child(systems, "BulletSystem");
            var bulletSystem = bulletSystemGo.AddComponent<BulletSystem>();

            GameObject crowdSystemGo = Child(systems, "CrowdSystem");
            var crowd = crowdSystemGo.AddComponent<CrowdManager>();

            GameObject obstacleGo = Child(systems, "ObstacleField");
            var obstacles = obstacleGo.AddComponent<ObstacleField>();
            GameObject obstacleRoot = Child(obstacleGo, "Obstacles");

            GameObject inputGo = Child(systems, "InputRouter");
            var input = inputGo.AddComponent<InputRouter>();
            var aim = inputGo.AddComponent<AimController>();

            GameObject audioGo = Child(systems, "AudioDirector");
            audioGo.AddComponent<AudioDirector>();

            // ---------- ARENA ----------
            GameObject arena = new("── ARENA ──");
            GameObject arenaRoot = Child(arena, "ArenaRoot");
            var bounds = arenaRoot.AddComponent<ArenaBounds>();

            float w = arenaCfg.width, h = arenaCfg.height;
            GameObject floor = Child(arena, "Floor");
            var floorMesh = GameObject.CreatePrimitive(PrimitiveType.Cube);
            floorMesh.name = "FloorMesh";
            Object.DestroyImmediate(floorMesh.GetComponent<Collider>());   // zero colliders in this project
            floorMesh.transform.SetParent(floor.transform, false);
            floorMesh.transform.localScale = new Vector3(w, 0.1f, h);
            floorMesh.transform.localPosition = new Vector3(0f, -0.05f, h * 0.5f);
            floorMesh.GetComponent<MeshRenderer>().sharedMaterial = matFloor;

            GameObject walls = Child(arena, "Walls");
            MakeWall(walls, "Wall_Left", new Vector3(-w * 0.5f, 0.5f, h * 0.5f), new Vector3(0.2f, 1f, h), matPillar);
            MakeWall(walls, "Wall_Right", new Vector3(w * 0.5f, 0.5f, h * 0.5f), new Vector3(0.2f, 1f, h), matPillar);
            MakeWall(walls, "Wall_Top_SpawnGate", new Vector3(0f, 0.5f, h), new Vector3(w, 1f, 0.2f), matBumper);
            MakeWall(walls, "DefenseLine", new Vector3(0f, 0.02f, arenaCfg.defenseLineZ), new Vector3(w, 0.04f, 0.15f), matPlayer);

            // ---------- ACTORS ----------
            GameObject actors = new("── ACTORS ──");
            GameObject player = Child(actors, "Player");
            player.transform.position = new Vector3(0f, 0f, 2f);
            player.layer = LayerMask.NameToLayer("Player");
            var playerMesh = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            playerMesh.name = "PlayerMesh";
            Object.DestroyImmediate(playerMesh.GetComponent<Collider>());
            playerMesh.transform.SetParent(player.transform, false);
            playerMesh.transform.localScale = new Vector3(0.8f, 0.5f, 0.8f);
            playerMesh.GetComponent<MeshRenderer>().sharedMaterial = matPlayer;

            GameObject muzzle = Child(player, "Muzzle");
            muzzle.transform.localPosition = new Vector3(0f, 0.6f, 0.8f);

            // Aim indicator: in manual mode this is the only feedback before firing,
            // so it is part of the core loop rather than decoration.
            GameObject indicatorGo = Child(player, "AimIndicator");
            var indicator = indicatorGo.AddComponent<LineRenderer>();
            indicator.useWorldSpace = true;
            indicator.widthMultiplier = 0.09f;
            indicator.numCapVertices = 4;
            indicator.sharedMaterial = MakeMaterial("M_AimIndicator", new Color(0.47f, 1f, 0.88f, 0.75f));
            indicator.positionCount = 0;

            GameObject bulletPool = Child(actors, "BulletPool");
            GameObject crowdRoot = Child(actors, "CrowdRoot");

            // ---------- CAMERA ----------
            GameObject camGo = new("Main Camera");
            camGo.tag = "MainCamera";
            var cam = camGo.AddComponent<Camera>();
            cam.fieldOfView = camCfg != null ? camCfg.fovNormal : 60f;
            cam.nearClipPlane = 0.3f;
            cam.farClipPlane = 120f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.012f, 0.024f, 0.059f);
            var camRig = camGo.AddComponent<CameraRig>();

            GameObject light = new("Directional Light");
            var lt = light.AddComponent<Light>();
            lt.type = LightType.Directional;
            lt.intensity = 1.1f;
            lt.shadows = LightShadows.Soft;      // only player + boss are shadow casters
            light.transform.rotation = Quaternion.Euler(50f, -30f, 0f);

            // ---------- WIRING ----------
            // Done through SerializedObject because the fields are [SerializeField]
            // private: that keeps runtime encapsulation while still letting the
            // builder assemble the scene.
            Wire(arenaManager, new()
            {
                { "_arenaCfg", arenaCfg }, { "_spawnCfg", spawnCfg }, { "_bulletCfg", bulletCfg },
                { "_slowCfg", slowCfg }, { "_crowd", crowd }, { "_bullets", bulletSystem },
                { "_obstacleField", obstacles }, { "_cameraRig", camRig }, { "_slowMo", slowMo },
                { "_input", input }, { "_aim", aim }, { "_bounds", bounds },
            });
            WireArray(arenaManager, "_variants", variants);

            Wire(bulletSystem, new()
            {
                { "_cfg", bulletCfg }, { "_slowCfg", slowCfg },
                { "_muzzle", muzzle.transform }, { "_bulletViewPrefab", bulletPrefab },
                { "_poolRoot", bulletPool.transform },
            });

            Wire(crowd, new() { { "_spawnCfg", spawnCfg }, { "_arenaCfg", arenaCfg } });

            Wire(camRig, new()
            {
                { "_camera", cam }, { "_player", player.transform }, { "_cfg", camCfg },
            });
            WireFloat(camRig, "_defenseLineZ", arenaCfg.defenseLineZ);

            Wire(obstacles, new()
            {
                { "_bumperPrefab", bumperPrefab }, { "_pillarPrefab", pillarPrefab },
                { "_barrelPrefab", barrelPrefab }, { "_gravityWellPrefab", wellPrefab },
                { "_movingPlatformPrefab", platformPrefab }, { "_shieldWallPrefab", shieldPrefab },
                { "_root", obstacleRoot.transform },
            });

            Wire(aim, new() { { "_muzzle", muzzle.transform }, { "_indicator", indicator } });
            if (aimCfg != null)
            {
                WireEnum(aim, "_mode", (int)aimCfg.mode);
                WireFloat(aim, "_maxAngleDeg", aimCfg.maxAngleDeg);
                WireFloat(aim, "_dragFullWidthDeg", aimCfg.dragFullWidthDeg);
                WireFloat(aim, "_sweepSpeedDegPerSec", aimCfg.sweepSpeedDegPerSec);
                WireInt(aim, "_indicatorBounces", aimCfg.indicatorBounces);
            }

            WireFloat(bounds, "_width", arenaCfg.width);
            WireFloat(bounds, "_height", arenaCfg.height);
            WireFloat(bounds, "_defenseLineZ", arenaCfg.defenseLineZ);
            WireFloat(bounds, "_wallRestitution", arenaCfg.wallRestitution);
            WireBool(bounds, "_topAbsorbsBullet", arenaCfg.topAbsorbsBullet);

            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene, ScenePath);
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();

            Debug.Log($"[ChainRider] Scene built: {ScenePath}\n" +
                      $"Variants wired: {variants.Length}. Aim mode: {(aimCfg != null ? aimCfg.mode.ToString() : "n/a")}.\n" +
                      "Placeholder art is primitives — replace prefab contents in Assets/ChainRider/Prefabs.");
        }

        // ==================================================================
        // HELPERS
        // ==================================================================

        private static GameObject Child(GameObject parent, string name)
        {
            GameObject go = new(name);
            go.transform.SetParent(parent.transform, false);
            return go;
        }

        private static void MakeWall(GameObject parent, string name, Vector3 pos, Vector3 scale, Material mat)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name;
            Object.DestroyImmediate(go.GetComponent<Collider>());
            go.transform.SetParent(parent.transform, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            go.GetComponent<MeshRenderer>().sharedMaterial = mat;
            go.layer = LayerMask.NameToLayer("Wall");
        }

        private static Material MakeMaterial(string name, Color color)
        {
            string path = $"{MaterialDir}/{name}.mat";
            Material existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null) return existing;

            Shader shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            Material mat = new(shader) { name = name };
            // URP/Lit exposes _BaseColor; Material.color targets _Color and would
            // silently do nothing, leaving every placeholder white.
            if (mat.HasProperty("_BaseColor")) mat.SetColor("_BaseColor", color);
            if (mat.HasProperty("_Color")) mat.SetColor("_Color", color);
            AssetDatabase.CreateAsset(mat, path);
            return mat;
        }

        private static GameObject MakePrefab(string name, PrimitiveType type, Vector3 scale, Material mat)
        {
            string path = $"{PrefabDir}/{name}.prefab";
            GameObject existing = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (existing != null) return existing;

            GameObject temp = GameObject.CreatePrimitive(type);
            temp.name = name;
            // Zero colliders anywhere: all collision is analytic sweeping.
            Object.DestroyImmediate(temp.GetComponent<Collider>());
            temp.transform.localScale = scale;
            temp.GetComponent<MeshRenderer>().sharedMaterial = mat;

            GameObject prefab = PrefabUtility.SaveAsPrefabAsset(temp, path);
            Object.DestroyImmediate(temp);
            return prefab;
        }

        private static void Wire(Object target, System.Collections.Generic.Dictionary<string, Object> fields)
        {
            SerializedObject so = new(target);
            foreach (var kv in fields)
            {
                SerializedProperty prop = so.FindProperty(kv.Key);
                if (prop == null)
                {
                    Debug.LogWarning($"[ChainRider] {target.GetType().Name}.{kv.Key} not found — wire it by hand.");
                    continue;
                }
                prop.objectReferenceValue = kv.Value;
            }
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        private static void WireArray(Object target, string field, Object[] values)
        {
            SerializedObject so = new(target);
            SerializedProperty prop = so.FindProperty(field);
            if (prop == null)
            {
                Debug.LogWarning($"[ChainRider] {target.GetType().Name}.{field} not found.");
                return;
            }
            prop.arraySize = values.Length;
            for (int i = 0; i < values.Length; i++)
                prop.GetArrayElementAtIndex(i).objectReferenceValue = values[i];
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        private static void WireFloat(Object target, string field, float value) =>
            SetProp(target, field, p => p.floatValue = value);

        private static void WireInt(Object target, string field, int value) =>
            SetProp(target, field, p => p.intValue = value);

        private static void WireBool(Object target, string field, bool value) =>
            SetProp(target, field, p => p.boolValue = value);

        private static void WireEnum(Object target, string field, int value) =>
            SetProp(target, field, p => p.enumValueIndex = value);

        private static void SetProp(Object target, string field, System.Action<SerializedProperty> set)
        {
            SerializedObject so = new(target);
            SerializedProperty prop = so.FindProperty(field);
            if (prop == null)
            {
                Debug.LogWarning($"[ChainRider] {target.GetType().Name}.{field} not found.");
                return;
            }
            set(prop);
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        private static T Load<T>(string path) where T : Object => AssetDatabase.LoadAssetAtPath<T>(path);

        private static T[] LoadAll<T>(string folder) where T : Object
        {
            string[] guids = AssetDatabase.FindAssets($"t:{typeof(T).Name}", new[] { folder });
            var result = new T[guids.Length];
            for (int i = 0; i < guids.Length; i++)
                result[i] = AssetDatabase.LoadAssetAtPath<T>(AssetDatabase.GUIDToAssetPath(guids[i]));
            return result;
        }

        private static void EnsureFolder(string path)
        {
            if (AssetDatabase.IsValidFolder(path)) return;
            string parent = Path.GetDirectoryName(path).Replace('\\', '/');
            string leaf = Path.GetFileName(path);
            EnsureFolder(parent);
            AssetDatabase.CreateFolder(parent, leaf);
        }
    }
}
