using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
using ChainRider.Config;
using ChainRider.Core;
using ChainRider.Crowd;
using ChainRider.InputSys;

namespace ChainRider.EditorTools
{
    /// <summary>
    /// ConfigImporter — turns Config/arena_config.json into ScriptableObject assets.
    ///
    /// The JSON file stays the single source of truth: it is what the web prototype
    /// runs on and what tools/sim_test.js measures. Unity reads the same numbers
    /// rather than keeping a second copy, so a balance change cannot silently apply
    /// to one and not the other.
    ///
    /// Run: menu ChainRider -> Import Config From JSON.
    /// </summary>
    public static class ConfigImporter
    {
        private const string ConfigAssetDir = "Assets/ChainRider/Config";
        private const string VariantAssetDir = ConfigAssetDir + "/Variants";

        /// <summary>Repo-root path of the JSON, resolved from Application.dataPath.</summary>
        public static string JsonPath
        {
            get
            {
                // dataPath = <repo>/unity/Assets  ->  repo root is two levels up.
                string repoRoot = Path.GetFullPath(Path.Combine(Application.dataPath, "..", ".."));
                return Path.Combine(repoRoot, "Config", "arena_config.json");
            }
        }

        [MenuItem("ChainRider/Import Config From JSON", priority = 0)]
        public static void Import()
        {
            if (!File.Exists(JsonPath))
            {
                EditorUtility.DisplayDialog("ChainRider",
                    $"Config not found:\n{JsonPath}\n\nExpected repo layout: <repo>/Config/arena_config.json " +
                    "with the Unity project at <repo>/unity.", "OK");
                return;
            }

            JsonNode root;
            try
            {
                root = new JsonNode(MiniJson.Parse(File.ReadAllText(JsonPath)));
            }
            catch (System.Exception e)
            {
                Debug.LogError($"[ChainRider] Failed to parse {JsonPath}: {e.Message}");
                return;
            }

            EnsureFolder(ConfigAssetDir);
            EnsureFolder(VariantAssetDir);

            try
            {
                AssetDatabase.StartAssetEditing();
                ImportArena(root);
                ImportBullet(root);
                ImportSpawn(root);
                ImportSlowMo(root);
                ImportCamera(root);
                ImportAim(root);
                ImportVariants(root);
            }
            finally
            {
                AssetDatabase.StopAssetEditing();
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();
            }

            Debug.Log($"[ChainRider] Config imported from {JsonPath}");
        }

        // ==================================================================
        // SECTIONS
        // ==================================================================

        private static void ImportArena(JsonNode root)
        {
            var a = root["arena"];
            var p = root["player"];
            var sc = root["scoring"];
            var so = GetOrCreate<ArenaConfigSO>($"{ConfigAssetDir}/ArenaConfig.asset");

            so.width = a["width"].AsFloat();
            so.height = a["height"].AsFloat();
            so.playerZone = a["playerZone"].AsFloat(5f);
            so.combatZone = a["combatZone"].AsFloat(25f);
            so.spawnZone = a["spawnZone"].AsFloat(10f);
            so.defenseLineZ = a["defenseLineZ"].AsFloat();
            so.nearMissBandZ = a["nearMissBandZ"].AsFloat(0.5f);
            so.wallRestitution = a["walls"]["left"].Opt("restitution").AsFloat(0.95f);

            // Top wall doubles as the spawn gate: enemies pass through, bullets bounce.
            // Measured: an absorbing gate produced only 0.10 bounces per bullet.
            so.topAbsorbsBullet = a["walls"]["top"].Opt("absorbsBullet").AsBool(false);

            so.playerLives = p["lives"].AsInt(3);
            so.damagePerLeakedEnemy = p["damagePerLeakedEnemy"].AsInt(1);
            so.invulnerabilityAfterHit = p["invulnerabilityAfterHit"].AsFloat(1f);

            so.comboMultiplierStep = sc.Opt("comboMultiplierStep").AsFloat(0.15f);
            so.perfectClearBonusCoins = sc.Opt("perfectClearBonusCoins").AsInt(50);

            EditorUtility.SetDirty(so);
        }

        private static void ImportBullet(JsonNode root)
        {
            var b = root["bullet"];
            var so = GetOrCreate<BulletConfigSO>($"{ConfigAssetDir}/BulletConfig.asset");

            so.baseSpeed = b["baseSpeed"].AsFloat();
            so.radius = b["radius"].AsFloat();
            so.simulationSubsteps = b["simulationSubsteps"].AsInt(4);
            so.maxBounce = b["maxBounce"].AsInt();
            so.maxBounceUpgraded = b["maxBounceUpgraded"].AsInt(50);
            so.damagePerBounce = b["damagePerBounce"].AsFloat();
            so.speedPerBounce = b["speedPerBounce"].AsFloat();
            so.speedMultiplierCap = b["speedMultiplierCap"].AsFloat();
            so.damageBase = b["damageBase"].AsFloat();
            so.steerAnglePerSwipe = b["steerAnglePerSwipe"].AsFloat();
            so.steerMaxAnglePerSecond = b["steerMaxAnglePerSecond"].AsFloat();
            so.steerMeterDuration = b["steerMeterDuration"].AsFloat();
            so.magazine = b.Opt("magazine").AsInt(5);
            so.autoReloadDelay = b.Opt("autoReloadDelay").AsFloat(0.35f);

            EditorUtility.SetDirty(so);
        }

        private static void ImportSpawn(JsonNode root)
        {
            var s = root["spawn"];
            var so = GetOrCreate<SpawnConfigSO>($"{ConfigAssetDir}/SpawnConfig.asset");

            so.waveCount = s["waveCount"].AsInt();
            so.enemiesPerWave = s["enemiesPerWave"].AsIntArray();
            so.spawnInterval = s["spawnInterval"].AsFloatArray();

            string[] formations = s["formation"].AsStringArray();
            so.formation = new FormationKind[formations.Length];
            for (int i = 0; i < formations.Length; i++) so.formation[i] = ParseFormation(formations[i]);

            float[] cols = s["columnsRange"].AsFloatArray();
            so.columnsMin = Mathf.RoundToInt(cols[0]);
            so.columnsMax = Mathf.RoundToInt(cols[1]);
            so.spacing = s["spacing"].AsFloat();
            so.swayAmplitude = s["swayAmplitude"].AsFloat();
            so.swayFrequency = s["swayFrequency"].AsFloat();
            so.separationRadius = s["separationRadius"].AsFloat();
            so.separationWeight = s["separationWeight"].AsFloat();
            so.alignmentWeight = s["alignmentWeight"].AsFloat();
            so.cohesionWeight = s["cohesionWeight"].AsFloat();
            so.maxActiveEnemies = s["maxActiveEnemies"].AsInt();

            EditorUtility.SetDirty(so);
        }

        private static void ImportSlowMo(JsonNode root)
        {
            var m = root["slowMo"];
            var so = GetOrCreate<SlowMoConfigSO>($"{ConfigAssetDir}/SlowMoConfig.asset");

            so.crowdTimeScale = m["crowdTimeScale"].AsFloat();
            so.finalBounceTimeScale = m["finalBounceTimeScale"].AsFloat();
            so.finalBounceThreshold = m["finalBounceThreshold"].AsInt();
            so.transitionDuration = m["transitionDuration"].AsFloat();
            so.minFixedDeltaScale = m["minFixedDeltaScale"].AsFloat(0.15f);
            so.audioDuckDb = m["audioDuckDb"].AsFloat(-6f);

            EditorUtility.SetDirty(so);
        }

        private static void ImportCamera(JsonNode root)
        {
            var c = root["camera"];
            var m = root["slowMo"];
            var so = GetOrCreate<CameraConfigSO>($"{ConfigAssetDir}/CameraConfig.asset");

            so.pitchDegrees = c["pitchDegrees"].AsFloat();
            so.yawDegrees = c["yawDegrees"].AsFloat();
            so.distance = c["distance"].AsFloat();
            so.heightOffset = c["heightOffset"].AsFloat();
            so.lookAheadZ = c["lookAheadZ"].AsFloat();
            so.followLerp = c["followLerp"].AsFloat();
            so.bulletFollowLerp = c["bulletFollowLerp"].AsFloat();

            so.fovNormal = m["fovNormal"].AsFloat(60f);
            so.fovBulletTime = m["fovBulletTime"].AsFloat(40f);
            so.fovTransitionDuration = m["transitionDuration"].AsFloat(0.2f);

            var shake = c["shake"];
            so.bounceSmall = ReadShake(shake["bounceSmall"]);
            so.bounceBig = ReadShake(shake["bounceBig"]);
            so.explosion = ReadShake(shake["explosion"]);
            so.comboMilestone = ReadShake(shake["comboMilestone"]);

            EditorUtility.SetDirty(so);
        }

        private static void ImportAim(JsonNode root)
        {
            var a = root["aim"];
            var so = GetOrCreate<AimConfigSO>($"{ConfigAssetDir}/AimConfig.asset");

            so.mode = a.Opt("mode").AsString("manual") == "sweep" ? AimMode.Sweep : AimMode.Manual;
            so.maxAngleDeg = a["maxAngleDeg"].AsFloat();
            so.indicatorBounces = a["indicatorBounces"].AsInt();
            so.sweepSpeedDegPerSec = a["sweepSpeedDegPerSec"].AsFloat();
            so.dragFullWidthDeg = a.Opt("manual").Exists
                ? a["manual"].Opt("dragFullWidthDeg").AsFloat(116f)
                : 116f;

            EditorUtility.SetDirty(so);
        }

        private static void ImportVariants(JsonNode root)
        {
            var variants = root["variants"];
            var bosses = root["bosses"];

            for (int i = 0; i < variants.Count; i++)
            {
                var v = variants[i];
                string id = v["id"].AsString();
                var so = GetOrCreate<VariantSO>($"{VariantAssetDir}/SO_Variant_{ToPascal(id)}.asset");

                so.variantId = id;
                so.displayName = v["name"].AsString();
                so.description = v.Opt("description").AsString("");
                so.musicLayer = v.Opt("musicLayer").AsString("base_synth");
                so.specialEnemy = ParseEnemy(v.Opt("specialEnemy").AsString("runner"));

                var theme = v["theme"];
                so.primary = ParseColor(theme["primary"].AsString());
                so.enemyColor = ParseColor(theme["enemy"].AsString());
                so.bumperColor = ParseColor(theme["bumper"].AsString());
                so.bgTop = ParseColor(theme["bgTop"].AsString());
                so.bgBottom = ParseColor(theme["bgBottom"].AsString());
                so.gridColor = ParseColor(theme["grid"].AsString());

                // Boss definition lives in a separate array, matched by id.
                so.bossId = v.Opt("boss").AsString("colossus");
                for (int b = 0; b < bosses.Count; b++)
                {
                    if (bosses[b]["id"].AsString() != so.bossId) continue;
                    so.bossHp = bosses[b]["hp"].AsFloat();
                    so.bossPattern = ParseBossPattern(bosses[b]["pattern"].AsString());
                    break;
                }

                var obstacles = v["obstacles"];
                var list = new List<ObstaclePlacement>(obstacles.Count);
                for (int o = 0; o < obstacles.Count; o++)
                {
                    var node = obstacles[o];
                    list.Add(new ObstaclePlacement
                    {
                        kind = ParseObstacle(node["type"].AsString()),
                        positionXZ = new Vector2(node["x"].AsFloat(), node["z"].AsFloat()),
                        radius = node.Opt("radius").AsFloat(0.9f),
                        width = node.Opt("width").AsFloat(1f),
                        travel = node.Opt("travel").AsFloat(0f),
                        speed = node.Opt("speed").AsFloat(0f),
                        phase = node.Opt("phase").AsFloat(0f),
                        force = node.Opt("force").AsFloat(0f),
                    });
                }
                so.obstacles = list.ToArray();

                EditorUtility.SetDirty(so);
            }
        }

        // ==================================================================
        // HELPERS
        // ==================================================================

        private static ShakeProfile ReadShake(JsonNode n) => new()
        {
            amplitude = n["amplitude"].AsFloat(),
            frequency = n["frequency"].AsFloat(),
            duration = n["duration"].AsFloat(),
        };

        private static FormationKind ParseFormation(string s) => s switch
        {
            "rect" => FormationKind.Rect,
            "vshape" => FormationKind.VShape,
            "diamond" => FormationKind.Diamond,
            "line" => FormationKind.Line,
            "circle" => FormationKind.Circle,
            _ => FormationKind.Rect,
        };

        private static ObstacleKind ParseObstacle(string s) => s switch
        {
            "bumper" => ObstacleKind.Bumper,
            "pillar" => ObstacleKind.Pillar,
            "barrel" => ObstacleKind.Barrel,
            "gravityWell" => ObstacleKind.GravityWell,
            "movingPlatform" => ObstacleKind.MovingPlatform,
            "shieldWall" => ObstacleKind.ShieldWall,
            _ => ObstacleKind.Bumper,
        };

        private static EnemyType ParseEnemy(string s) => s switch
        {
            "grunt" => EnemyType.Grunt,
            "runner" => EnemyType.Runner,
            "brute" => EnemyType.Brute,
            "shielder" => EnemyType.Shielder,
            "splitter" => EnemyType.Splitter,
            "bomber" => EnemyType.Bomber,
            _ => EnemyType.Grunt,
        };

        private static Boss.BossPattern ParseBossPattern(string s) => s switch
        {
            "slow_descend_slam" => Boss.BossPattern.SlowDescendSlam,
            "mirror_pair_sidestep" => Boss.BossPattern.MirrorPairSidestep,
            "orbit_pull_pulse" => Boss.BossPattern.OrbitPullPulse,
            "barrel_drop_charge" => Boss.BossPattern.BarrelDropCharge,
            "teleport_lane_swap" => Boss.BossPattern.TeleportLaneSwap,
            _ => Boss.BossPattern.SlowDescendSlam,
        };

        private static Color ParseColor(string hex)
        {
            if (ColorUtility.TryParseHtmlString(hex, out Color c)) return c;
            Debug.LogWarning($"[ChainRider] Unparseable color '{hex}', falling back to magenta");
            return Color.magenta;
        }

        private static string ToPascal(string snake)
        {
            string[] parts = snake.Split('_');
            var sb = new System.Text.StringBuilder();
            foreach (string part in parts)
            {
                if (part.Length == 0) continue;
                sb.Append(char.ToUpperInvariant(part[0]));
                if (part.Length > 1) sb.Append(part.Substring(1));
            }
            return sb.ToString();
        }

        private static T GetOrCreate<T>(string path) where T : ScriptableObject
        {
            T asset = AssetDatabase.LoadAssetAtPath<T>(path);
            if (asset != null) return asset;
            asset = ScriptableObject.CreateInstance<T>();
            AssetDatabase.CreateAsset(asset, path);
            return asset;
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
