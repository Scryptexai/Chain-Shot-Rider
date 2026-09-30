class_name UiTheme
extends RefCounted
## Neon arcade skin, built in code from the active arena palette.
##
## Every colour here comes from the variant's theme block in
## Config/arena_config.json — the same block that tints the arena, the crowd
## and the bumpers. That is the whole point: when the player switches from
## Classic Pit to Gravity Chamber, the HUD has to move with the world. A UI
## that stays cyan while the arena turns toxic green reads as a different
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
const DANGER := Color("#FF1744")
const GOLD := Color("#FFD54F")
const SHADOW := Color(0, 0, 0, 0.75)


## Reads a variant theme block into a palette dictionary with safe fallbacks.
static func palette(theme: Dictionary) -> Dictionary:
	return {
		"primary": _color(theme, "primary", "#00E5FF"),
		"enemy": _color(theme, "enemy", "#FF4D3D"),
		"bumper": _color(theme, "bumper", "#B14DFF"),
		"bg_top": _color(theme, "bgTop", "#0A1030"),
		"bg_bottom": _color(theme, "bgBottom", "#03060F"),
		"grid": _color(theme, "grid", "#1FD3E8"),
	}


## Translucent panel with a neon edge — the base of every HUD chip.
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
