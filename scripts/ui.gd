class_name UI
extends RefCounted
## Шрифты и элементы интерфейса (кнопки-«таблетки», подписи). Размеры — в пикселях экрана 720×1280.

static var F_REG: Font
static var F_BOLD: Font
static var F_BLACK: Font


static func init_fonts() -> void:
	if F_BOLD:
		return
	F_REG = _sys(500)
	F_BOLD = _sys(700)
	F_BLACK = _sys(900)


static func _sys(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Noto Sans", "Helvetica Neue", "Arial", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.allow_system_fallback = true
	return f


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = F_BOLD
	th.default_font_size = 30
	th.set_color("font_color", "Label", Color.WHITE)
	# Поле ввода
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0, 0, 0, 0.25)
	le.border_color = Color(1, 1, 1, 0.15)
	le.set_border_width_all(4)
	le.set_corner_radius_all(26)
	le.content_margin_left = 28
	le.content_margin_right = 28
	le.content_margin_top = 18
	le.content_margin_bottom = 18
	var lef := le.duplicate()
	lef.border_color = BB.C_GOLD
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lef)
	th.set_stylebox("read_only", "LineEdit", le)
	th.set_color("font_color", "LineEdit", Color.WHITE)
	th.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.4))
	th.set_color("caret_color", "LineEdit", BB.C_GOLD)
	th.set_font_size("font_size", "LineEdit", 34)
	# Прокрутка
	var empty := StyleBoxEmpty.new()
	th.set_stylebox("panel", "ScrollContainer", empty)
	return th


static func box(bg: Color, radius := 999, pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb


static func style_button(b: Button, bg: Color, fg: Color, size := 32, radius := 999) -> void:
	b.add_theme_stylebox_override("normal", box(bg, radius))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.08), radius))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.12), radius))
	b.add_theme_stylebox_override("disabled", box(Color(bg, bg.a * 0.5), radius))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.5))
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE


## Кнопка-таблетка
static func button(text: String, bg := BB.C_YELLOW, fg := BB.C_INK, size := 32, min_size := Vector2(0, 84)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	style_button(b, bg, fg, size)
	b.pressed.connect(func(): Audio.sfx("click"))
	return b


## Большая кнопка меню: заголовок + мелкая подпись
static func big_button(title: String, sub: String, bg: Color, width := 470.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 118)
	style_button(b, bg, BB.C_INK, 38)
	b.pressed.connect(func(): Audio.sfx("click"))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := label(title, 38, BB.C_INK, F_BOLD)
	var s := label(sub, 23, Color(BB.C_INK, 0.75), F_REG)
	v.add_child(t)
	v.add_child(s)
	return b


static func label(text: String, size := 30, col := Color.WHITE, font: Font = null, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func shadow(l: Control, off := 5, a := 0.3) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, a))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", off)


static func rich(size := 34) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_override("normal_font", F_BOLD)
	r.add_theme_font_override("bold_font", F_BLACK)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Угловая кнопка «← Меню» и т.п.
static func corner(text: String) -> Button:
	var b := button(text, Color(1, 1, 1, 0.12), Color.WHITE, 24, Vector2(0, 60))
	b.add_theme_stylebox_override("normal", box(Color(1, 1, 1, 0.12), 999, Vector4(26, 0, 26, 0)))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.18), 999, Vector4(26, 0, 26, 0)))
	b.add_theme_stylebox_override("pressed", box(Color(1, 1, 1, 0.08), 999, Vector4(26, 0, 26, 0)))
	return b


static func center_box(parent: Control, sep := 22) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


static func hrow(parent: Control, sep := 18) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h


static func centered(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c
