class_name JuiceSuite
extends Node

## Penjaga untuk lapisan "rasa": musik dinamis, milestone, dan reaksi
## tampilan atasnya (denyut slow motion, zoom sinematik, confetti, cue audio).
##
## Semua yang diuji di sini gampang lulus diam-diam. Sebuah event milestone
## bisa dikirim simulasi tanpa seorang pun mendengarkannya; sebuah confetti
## bisa dibangun tapi tak pernah meletus; sebuah zoom bisa menyala dan tak
## pernah padam. Jadi setiap perilaku diperiksa dalam DUA keadaan yang
## berlawanan — sebelum dan sesudah, dengan dan tanpa — bukan sekadar
## "ada reaksinya".
##
## Dipisah dari smoke.gd karena berkas itu sudah mentok batas seribu baris.

signal failed(message: String)

const TICKS_PER_SECOND := 60.0
const FRAME := 1.0 / 60.0


func run(packed: PackedScene) -> void:
	_run_music_states(packed)
	_run_sim_milestones()
	_run_feel_and_audio(packed)
	await _run_hud_confetti(packed)


## Musik dinamis docs/07 7.3: dua keadaan yang mengubah arti lagu.
##
## Keduanya nyaris mustahil tertangkap oleh smoke biasa — slow motion hanya
## bertahan sepersekian detik, dan nyawa terakhir butuh bot yang kebetulan
## hampir kalah. Jadi keadaannya dipasang langsung, lalu yang diperiksa adalah
## reaksi mixer-nya: filter yang bergerak dan denyut yang benar-benar berbunyi.
func _run_music_states(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	root.call("_on_stage_chosen", 0)
	var music: Object = root.get("_music")
	var sim: Object = root.get("_sim")
	var feel: Object = root.get("_feel")
	if music == null or sim == null or feel == null:
		failed.emit("musik: run tidak terbentuk")
		root.queue_free()
		return

	# 1. Slow motion: low-pass menutup ke 1200 Hz dan bus Music turun -6 dB.
	# Ducking-nya milik AudioDirector, filternya milik MusicDirector, jadi
	# keduanya harus ikut berjalan supaya baris spec ini benar-benar teruji.
	var audio: Object = root.get("_audio")
	feel.set("time_scale", 0.3)
	for i in range(240):
		music.call("update", sim, feel, FRAME)
		if audio != null:
			audio.call("update", sim, feel, FRAME)
	var lpf := _music_filter("AudioEffectLowPassFilter")
	if lpf == null:
		failed.emit("musik: low-pass tidak terpasang di bus Music")
	elif lpf.cutoff_hz > 2000.0:
		failed.emit("musik: slow-mo tidak menutup filter (%.0f Hz)" % lpf.cutoff_hz)
	var music_bus := AudioServer.get_bus_index("Music")
	var ducked := AudioServer.get_bus_volume_db(music_bus) if music_bus >= 0 else 0.0
	if ducked > -3.0:
		failed.emit("musik: slow-mo tidak menurunkan bus Music (%.1f dB)" % ducked)

	# 2. Nyawa terakhir: high-pass menyapu naik dan sub pulse berdetak.
	feel.set("time_scale", 1.0)
	sim.set("lives", 1)
	var before := int(music.get("sub_pulses"))
	for i in range(240):
		music.call("update", sim, feel, FRAME)
	var hpf := _music_filter("AudioEffectHighPassFilter")
	if hpf == null:
		failed.emit("musik: high-pass tidak terpasang di bus Music")
	elif hpf.cutoff_hz < 300.0:
		failed.emit("musik: nyawa terakhir tidak menyapu high-pass (%.0f Hz)" % hpf.cutoff_hz)
	var pulses := int(music.get("sub_pulses")) - before
	# 240 frame = 4 detik wall-clock = 8 beat pada 120 BPM.
	if pulses < 6:
		failed.emit("musik: hanya %d sub pulse dalam 4 detik, diharapkan ~8" % pulses)
	print("  musik: slow-mo menutup filter, nyawa terakhir berdenyut %d kali" % pulses)
	root.queue_free()


## Efek di bus Music menurut nama kelasnya.
func _music_filter(class_wanted: String) -> Object:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return null
	for i in range(AudioServer.get_bus_effect_count(bus)):
		var effect := AudioServer.get_bus_effect(bus, i)
		if effect.get_class() == class_wanted:
			return effect
	return null


## Milestone di sisi simulasi, diperiksa pada keadaan yang dipasang tangan.
##
## Sebuah run bot bisa kebetulan tidak pernah mencapai 50 kill atau tidak
## pernah menutup gelombang dengan peluru yang masih terbang, dan uji yang
## hanya menghitung kejadian akan ikut diam. Di sini keadaannya dibuat.
func _run_sim_milestones() -> void:
	var cfg := GameConfig.dict("")
	var every := int(GameConfig.num("scoring.bounceMilestoneEvery"))

	# 1. Tangga pantulan: kelipatan kelima berbunyi, yang keempat tidak.
	var sim := SimWorld.new(cfg, 1234, 0, {})
	sim.chain_active = true
	for i in range(every - 1):
		sim._bounce_chain(Vector2.UP)
	if _count(sim.events, "bounce_milestone") != 0:
		failed.emit("juice: pantulan ke-%d sudah dirayakan" % (every - 1))
	sim._bounce_chain(Vector2.UP)
	if _count(sim.events, "bounce_milestone") != 1:
		failed.emit("juice: pantulan ke-%d tidak memicu milestone" % every)

	# 2. Near miss: sekali per musuh, bukan sekali per tick.
	var band := GameConfig.num("arena.nearMissBandZ")
	var line := GameConfig.num("arena.defenseLineZ")
	sim = SimWorld.new(cfg, 1234, 0, {})
	sim.enemy_count = 1
	sim.enemy_x[0] = 0.0
	sim.enemy_near[0] = 0
	sim.enemy_z[0] = line + band + 2.0
	sim.events.clear()
	sim._tick_crowd()
	if _count(sim.events, "near_miss") != 0:
		failed.emit("juice: near miss berbunyi padahal musuh masih jauh")
	sim.enemy_z[0] = line + band * 0.5
	var fired := 0
	for i in range(8):
		sim.events.clear()
		sim.enemy_z[0] = line + band * 0.5
		sim._tick_crowd()
		fired += _count(sim.events, "near_miss")
	if fired != 1:
		failed.emit("juice: near miss berbunyi %d kali untuk satu musuh" % fired)

	# 3. Peluru terakhir: hanya kalau chain shot yang menutup gelombang.
	var without := _last_bullet_case(cfg, false)
	var with_bullet := _last_bullet_case(cfg, true)
	if without != 0:
		failed.emit("juice: last_bullet terkirim tanpa peluru di udara")
	if with_bullet != 1:
		failed.emit("juice: peluru penutup gelombang tidak memicu last_bullet")

	# 4. Perfect clear dan ambang kill, diukur pada satu run bot penuh.
	var tally := _bot_run(cfg)
	if int(tally["bounce_milestone"]) != int(tally["bounces"]) / every:
		(
			failed
			. emit(
				(
					"juice: %d milestone untuk %d pantulan"
					% [int(tally["bounce_milestone"]), int(tally["bounces"])]
				)
			)
		)
	if int(tally["dirty_clear"]) > 0:
		failed.emit("juice: perfect clear diberikan pada gelombang yang kebobolan")
	if int(tally["coins"]) != int(tally["perfect_clear"]) * int(GameConfig.num(
		"scoring.perfectClearBonusCoins"
	)):
		failed.emit("juice: koin perfect clear tidak cocok dengan jumlah event")
	if int(tally["near_miss"]) < int(tally["leaks"]):
		failed.emit("juice: ada musuh bocor tanpa pernah terhitung near miss")
	print(
		(
			"  juice: %d pantulan -> %d milestone, %d near miss, %d perfect clear (+%d koin)"
			% [
				int(tally["bounces"]),
				int(tally["bounce_milestone"]),
				int(tally["near_miss"]),
				int(tally["perfect_clear"]),
				int(tally["coins"]),
			]
		)
	)


## Membunuh musuh terakhir sebuah gelombang, dengan atau tanpa chain shot
## yang masih terbang. Mengembalikan jumlah event "last_bullet".
func _last_bullet_case(cfg: Dictionary, chain_in_air: bool) -> int:
	var sim := SimWorld.new(cfg, 99, 0, {})
	sim.enemy_count = 1
	sim.enemy_x[0] = 0.0
	sim.enemy_z[0] = 20.0
	sim.enemy_hp[0] = 1.0
	sim._wave_remaining = 0
	sim.chain_active = chain_in_air
	sim.events.clear()
	sim._damage_enemy(0, 999.0, "chain")
	return _count(sim.events, "last_bullet")


## Satu run bot pendek, menghitung event yang jarang muncul di uji satuan.
func _bot_run(cfg: Dictionary) -> Dictionary:
	var sim := SimWorld.new(cfg, 4242, 0, {})
	var tally := {
		"bounces": 0,
		"bounce_milestone": 0,
		"kill_milestone": 0,
		"near_miss": 0,
		"perfect_clear": 0,
		"dirty_clear": 0,
		"leaks": 0,
		"coins": 0,
	}
	var leaks_this_wave := 0
	var ticks := 0
	while ticks < int(90.0 * TICKS_PER_SECOND) and sim.state == SimWorld.State.PLAYING:
		var target := sim.enemy_x[0] if sim.enemy_count > 0 else 0.0
		var tap: bool = not sim.chain_riding and sim.chain_charges > 0 and sim.enemy_count > 0
		sim.set_input(target, true, tap, 0.0)
		sim.tick()
		ticks += 1
		for event in sim.events:
			match String(event.get("type", "")):
				"bounce":
					tally["bounces"] = int(tally["bounces"]) + 1
				"bounce_milestone":
					tally["bounce_milestone"] = int(tally["bounce_milestone"]) + 1
				"kill_milestone":
					tally["kill_milestone"] = int(tally["kill_milestone"]) + 1
				"near_miss":
					tally["near_miss"] = int(tally["near_miss"]) + 1
				"leak":
					tally["leaks"] = int(tally["leaks"]) + 1
					leaks_this_wave += 1
				"perfect_clear":
					tally["perfect_clear"] = int(tally["perfect_clear"]) + 1
					if leaks_this_wave > 0:
						tally["dirty_clear"] = int(tally["dirty_clear"]) + 1
					leaks_this_wave = 0
				"wave_start":
					leaks_this_wave = 0
	tally["coins"] = sim.coins
	return tally


## Reaksi tampilan: denyut, zoom sinematik, dan cue audio yang menyala lalu
## benar-benar padam lagi.
func _run_feel_and_audio(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	root.call("_on_stage_chosen", 0)
	var feel: Object = root.get("_feel")
	var audio: Object = root.get("_audio")
	if feel == null or audio == null:
		failed.emit("juice: run tidak terbentuk")
		root.queue_free()
		return

	# Zoom sinematik peluru terakhir: menyala tanpa bantuan keadaan sim, lalu
	# padam sendiri setelah durasi config habis.
	var normal_fov := GameConfig.num("slowMo.fovNormal")
	feel.call("react_to", {"type": "last_bullet"})
	# Satu detik: transisi slow motion adalah easing eksponensial 0,2 s, jadi
	# nilainya butuh beberapa tetapan waktu sebelum benar-benar mendarat —
	# dan satu detik masih di dalam durasi sinematik 1,2 s.
	for i in range(60):
		feel.call("update", null, FRAME)
	var zoom_scale: float = feel.get("time_scale")
	var zoom_fov: float = feel.get("fov")
	if zoom_scale > GameConfig.num("slowMo.finalBounceTimeScale") + 0.02:
		failed.emit("juice: peluru terakhir tidak memperdalam slow motion (%.2f)" % zoom_scale)
	if zoom_fov > GameConfig.num("slowMo.fovLastBullet") + 1.0:
		failed.emit("juice: peluru terakhir tidak menarik kamera masuk (%.0f)" % zoom_fov)
	for i in range(150):
		feel.call("update", null, FRAME)
	if absf(float(feel.get("fov")) - normal_fov) > 1.0:
		failed.emit("juice: zoom sinematik tidak pernah dilepas (%.0f)" % feel.get("fov"))

	# Denyut pantulan: menekan time scale sebentar, lalu hilang.
	feel.call("react_to", {"type": "bounce_milestone", "count": 5})
	for i in range(10):
		feel.call("update", null, FRAME)
	var pulse_scale: float = feel.get("time_scale")
	if pulse_scale > 0.9:
		failed.emit("juice: milestone pantulan tidak memberi denyut (%.2f)" % pulse_scale)
	for i in range(60):
		feel.call("update", null, FRAME)
	if float(feel.get("time_scale")) < 0.98:
		failed.emit("juice: denyut pantulan tidak kembali ke kecepatan normal")

	_check_cues(audio)
	root.queue_free()


## Setiap event juice harus punya suaranya sendiri — dan hanya suaranya.
func _check_cues(audio: Object) -> void:
	var pairs := {
		"near_miss": "heartbeat",
		"kill_milestone": "kill_milestone",
		"perfect_clear": "perfect_clear",
		"bounce_milestone": "chain_spark",
	}
	for event_type in pairs:
		var cue: String = pairs[event_type]
		var counts: Dictionary = audio.get("play_counts")
		var before := int(counts.get(cue, 0))
		audio.call("react_to", {"type": event_type})
		counts = audio.get("play_counts")
		if int(counts.get(cue, 0)) <= before:
			failed.emit("juice: event %s tidak membunyikan cue %s" % [event_type, cue])
	var counts_after: Dictionary = audio.get("play_counts")
	var heartbeats := int(counts_after.get("heartbeat", 0))
	audio.call("react_to", {"type": "gate_bullet", "op": "add"})
	counts_after = audio.get("play_counts")
	if int(counts_after.get("heartbeat", 0)) != heartbeats:
		failed.emit("juice: cue heartbeat ikut berbunyi untuk event yang salah")


## HUD: ambang kill harus meletuskan confetti, dan confetti itu harus habis.
func _run_hud_confetti(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	root.call("_on_stage_chosen", 0)
	await get_tree().process_frame
	# Simulasi dibekukan supaya event yang dipasang tangan tidak tertimpa
	# oleh tick berikutnya sebelum HUD sempat membacanya.
	root.set_physics_process(false)
	var hud: Object = root.get_node_or_null("HUD")
	var sim: Object = root.get("_sim")
	if hud == null or sim == null:
		failed.emit("juice: HUD tidak terbentuk")
		root.queue_free()
		return

	var confetti: Object = hud.get("_confetti")
	if confetti == null:
		failed.emit("juice: lapisan confetti tidak ada di HUD")
		root.queue_free()
		return
	if bool(confetti.call("is_falling")):
		failed.emit("juice: confetti sudah jatuh sebelum ada ambang kill")

	sim.events.clear()
	sim.events.append({"type": "kill_milestone", "kills": 50, "bonus": 500})
	hud.call("render_frame")
	if not bool(confetti.call("is_falling")):
		failed.emit("juice: ambang 50 kill tidak meletuskan confetti")
	var popup: Object = hud.get("_popup")
	if popup != null and String(popup.get("text")) != "50 KILLS":
		failed.emit("juice: popup ambang kill berbunyi \"%s\"" % popup.get("text"))

	for i in range(140):
		confetti.call("advance", FRAME)
	if bool(confetti.call("is_falling")):
		failed.emit("juice: confetti tidak pernah berhenti jatuh")
	print("  juice: 50 kill -> confetti meletus lalu habis, popup \"50 KILLS\"")
	root.queue_free()


func _count(events: Array, kind: String) -> int:
	var total := 0
	for event in events:
		if String(event.get("type", "")) == kind:
			total += 1
	return total
