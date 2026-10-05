class_name UiTheme
extends RefCounted
## NEON skin, built in code from the active arena palette.
##
## Every colour here comes from the variant's theme block in
## Config/arena_config.json — the same block that tints the arena, the crowd
## and the bumpers. That is the whole point: when the player switches from
## Lembah Batu to Kuil Melayang, the HUD has to move with the world. A UI
## that stays torch-gold while the arena turns jade reads as a different
## app bolted on top of the game.
##
## Built in code rather than as a .theme resource because the palette is only
## known at runtime, and because a generated theme cannot drift out of sync
## with the JSON the way a hand-edited binary resource silently can.
##
## Nothing here touches autoloads: callers pass the palette in. That keeps the
## whole file testable and usable from a static context.

## Neutral ink used on top of every palette. Deliberately not pure white:
## #FFFFFF against a near-black arcade background buzzes on OLED panels.
const INK := Color("#F5F9FF")
const INK_DIM := Color("#8A9BB8")
const DANGER := Color("#FF2A2A")
## Combo chrome from the key art. Named GOLD for the call sites that predate
## the NEON rebuild; the colour itself is no longer gold anywhere.
const GOLD := Color("#9BF2FF")
const COMBO_CHROME := Color("#9BF2FF")
const COMBO_OUTLINE := Color("#0A2A33")
const SHADOW := Color(0, 0, 0, 0.75)
## Hijau "go". Tombol aksi utama di game mobile hampir selalu hijau; memakai
## warna aksen arena untuk PLAY membuatnya hilang di antara chip lain.
const GO := Color("#5BE34B")
const GO_DARK := Color("#1E7A2B")
const GO_LIT := Color("#B6FF8A")
const INK_DEEP := Color("#06240E")


## Reads a variant theme block into a palette dictionary with safe fallbacks.
##
## The fallbacks are the NEON core colours from config.artDirection, written
## out here as literals so a palette is still correct when this is called from
## a test with a bare dictionary. Six keys were enough for the fantasy skin;
## the key art needs the player, the tracer rain, the chain arcs and the wall
## panels to be themeable too, because those are the four things the eye
## actually tracks.
static func palette(theme: Dictionary) -> Dictionary:
	var pal := {
		"primary": _color(theme, "primary", "#2BE8FF"),
		"enemy": _color(theme, "enemy", "#E03A2F"),
		"bumper": _color(theme, "bumper", "#FF2BD6"),
		"bg_top": _color(theme, "bgTop", "#131B38"),
		"bg_bottom": _color(theme, "bgBottom", "#070A14"),
		"grid": _color(theme, "grid", "#1E8FA8"),
		"player": _color(theme, "player", "#DCE6F2"),
		"tracer": _color(theme, "tracer", "#FF2A2A"),
		"chain": _color(theme, "chain", "#A64BFF"),
		"bumper_glow": _color(theme, "bumperGlow", "#FF9BEE"),
		"wall_panel": _color(theme, "wallPanel", "#2A1B3D"),
		"fog": _color(theme, "fog", "#2A1340"),
		"vortex": _color(theme, "vortex", "#6B2FA8"),
	}
	# Derived, never authored: these two are always the hot core of the
	# explosion and the brass of the chain round, in every room.
	pal["blast"] = Color("#FF9A2E")
	pal["blast_core"] = Color("#FFE3A0")
	pal["brass"] = Color("#D9A441")
	return pal


## Translucent panel with a lit edge — the base of every HUD chip.
static func panel(accent: Color, radius: int = 18, fill_alpha: float = 0.10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, fill_alpha)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


## Solid slab for menus and dialogs, darker so text stays readable over play.
static func slab(pal: Dictionary, radius: int = 28) -> StyleBoxFlat:
	var bottom: Color = pal["bg_bottom"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bottom.r, bottom.g, bottom.b, 0.94)
	style.border_color = Color(pal["primary"].r, pal["primary"].g, pal["primary"].b, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 24
	return style


## Progress bar fill with a lit edge.
static func bar_fill(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(8)
	return style


## Progress bar track: the palette's background, not a generic grey.
static func bar_track(pal: Dictionary) -> StyleBoxFlat:
	var top: Color = pal["bg_top"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(top.r, top.g, top.b, 0.85)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


## Full Theme for buttons and labels on the non-gameplay screens.
##
## Buttons get a visible pressed and hover state on purpose. Touch has no
## cursor, so the press state is the only feedback that a tap registered; a
## button that looks identical when held feels broken even when it works.
static func build(pal: Dictionary) -> Theme:
	var theme := Theme.new()
	var accent: Color = pal["primary"]

	theme.set_type_variation("NeonButton", "Button")
	theme.set_font_size("font_size", "Button", 44)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", accent)
	theme.set_color("font_pressed_color", "Button", pal["bg_bottom"])
	theme.set_color("font_disabled_color", "Button", INK_DIM)
	theme.set_constant("outline_size", "Button", 0)

	var normal := panel(accent, 22, 0.12)
	normal.content_margin_top = 26.0
	normal.content_margin_bottom = 26.0
	theme.set_stylebox("normal", "Button", normal)

	var hover := panel(accent, 22, 0.24)
	hover.content_margin_top = 26.0
	hover.content_margin_bottom = 26.0
	hover.border_color = accent
	theme.set_stylebox("hover", "Button", hover)

	var pressed := panel(accent, 22, 1.0)
	pressed.content_margin_top = 26.0
	pressed.content_margin_bottom = 26.0
	pressed.bg_color = accent
	pressed.border_color = accent
	theme.set_stylebox("pressed", "Button", pressed)

	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_outline_color", "Label", SHADOW)
	theme.set_constant("outline_size", "Label", 8)
	return theme


## Applies the house label style. Outline, not drop shadow: an outline stays
## readable over both the dark floor and a bright explosion.
static func style_label(label: Label, size: int, tint: Color, outline: int = 8) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", SHADOW)
	label.add_theme_constant_override("outline_size", outline)


static func _color(theme: Dictionary, key: String, fallback: String) -> Color:
	var raw := String(theme.get(key, fallback))
	if raw.is_empty() or not raw.begins_with("#"):
		raw = fallback
	return Color.from_string(raw, Color.from_string(fallback, Color.MAGENTA))


## Tombol tebal bergaya game: bevel atas, "kaki" gelap di bawah, bayangan jatuh.
##
## Dibuat dari StyleBoxFlat biasa — border bawah tebal berwarna lebih gelap
## sudah cukup membaca sebagai tombol tiga dimensi, dan tetap satu resource
## tanpa tekstur. `sunken` adalah keadaan ditekan: kakinya memendek dan isi
## tombol turun, sehingga tap terasa menekan sesuatu.
static func chunky(
	face: Color, foot: Color, radius: int = 34, sunken: bool = false
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = face
	style.set_corner_radius_all(radius)
	style.border_color = foot
	style.border_width_bottom = 6 if sunken else 16
	style.border_width_top = 0
	style.border_width_left = 0
	style.border_width_right = 0
	style.shadow_color = Color(0, 0, 0, 0.0 if sunken else 0.45)
	style.shadow_size = 0 if sunken else 20
	style.shadow_offset = Vector2(0, 0 if sunken else 10)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 34.0 if sunken else 26.0
	style.content_margin_bottom = 26.0 if sunken else 34.0
	return style


## Pod HUD: kaca gelap dengan garis aksen. Dipakai untuk skor, chip stage,
## jumlah pasukan — semua yang dibaca sekilas di atas arena.
static func pod(accent: Color, radius: int = 28, fill: float = 0.82) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.14, fill)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 8)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 14.0
	return style


## Kotak padat satu warna — hati, titik wave, kartu pratinjau.
static func blob(fill: Color, radius: int = 18, foot: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	if foot.a > 0.0:
		style.border_color = foot
		style.border_width_bottom = 6
	return style


## Deretan pip sebagai pengganti bintang.
##
## Font bawaan Godot (Open Sans) TIDAK punya ★ ☆ ✦ ▲ ◎ — karakter itu keluar
## sebagai kotak tofu, dan itu baru terlihat pada build web pertama karena
## sandbox tanpa GPU tidak pernah menggambar satu huruf pun. Daripada
## menyeret berkas font sejuta glyph ke dalam build hanya demi tiga bintang,
## bentuknya digambar: pip bulat yang menyala atau redup.
static func pips(filled: int, total: int, on: Color, off: Color, size: int = 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(size * 0.45))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(total):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(size, size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", blob(on if i < filled else off, int(size * 0.5)))
		row.add_child(pip)
	return row


## Belah ketupat: penanda satuan di pod pasukan. Panel persegi yang diputar
## 45 derajat, karena StyleBoxFlat tidak bisa menggambar segitiga.
static func diamond(fill: Color, size: int = 22) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size * 1.45, size * 1.45)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pip := Panel.new()
	pip.size = Vector2(size, size)
	pip.pivot_offset = Vector2(size, size) * 0.5
	pip.position = Vector2(size * 0.22, size * 0.22)
	pip.rotation = PI * 0.25
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.add_theme_stylebox_override("panel", blob(fill, int(size * 0.25)))
	holder.add_child(pip)
	return holder


## Cincin: lingkaran berongga untuk inti tombol chain shot.
static func ring(tint: Color, diameter: int = 56, thickness: int = 6) -> Panel:
	var node := Panel.new()
	node.custom_minimum_size = Vector2(diameter, diameter)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.0)
	style.set_corner_radius_all(int(diameter * 0.5))
	style.border_color = tint
	style.set_border_width_all(thickness)
	node.add_theme_stylebox_override("panel", style)
	return node


## Memasang tiga keadaan tombol tebal sekaligus.
static func apply_chunky(button: Button, face: Color, foot: Color, radius: int = 34) -> void:
	button.add_theme_stylebox_override("normal", chunky(face, foot, radius))
	button.add_theme_stylebox_override("hover", chunky(face.lightened(0.08), foot, radius))
	button.add_theme_stylebox_override("pressed", chunky(face.darkened(0.05), foot, radius, true))
	button.add_theme_stylebox_override("focus", chunky(face, foot, radius))
	var off := chunky(Color(0.16, 0.2, 0.3), Color(0.08, 0.1, 0.16), radius)
	button.add_theme_stylebox_override("disabled", off)
	var ink: Color = INK_DEEP if face.get_luminance() > 0.45 else INK
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_disabled_color", INK_DIM)
