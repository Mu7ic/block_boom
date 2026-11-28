class_name LevelMap
extends Control
## Карта Аркады: извилистая дорожка снизу вверх, у пройденных уровней звёзды,
## каждые 10 уровней — новый мир со своим фоном. Уровней бесконечно много:
## карта всегда показывает текущий мир и следующий за ним.

signal play(n: int)

const STEP := 168.0          ## шаг между уровнями по вертикали
const TOP_PAD := 300.0       ## место над последним показанным уровнем
const BOTTOM_PAD := 230.0
const WORLD_GAP := 130.0     ## промежуток между мирами — там подпись мира
const NODE := 112.0
const BOSS := 136.0

var count := 20
var _nodes := {}             ## n → Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


## Сколько уровней показать: текущий мир целиком и весь следующий
func _visible_count() -> int:
	var w := BB.world_of(Save.unlocked)
	return (w + 2) * BB.LEVELS_PER_WORLD


func rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	_nodes.clear()
	count = _visible_count()
	custom_minimum_size.y = BOTTOM_PAD + (count - 1) * STEP + (count / BB.LEVELS_PER_WORLD - 1) * WORLD_GAP + TOP_PAD
	var un := Save.unlocked
	for n in range(1, count + 1):
		_nodes[n] = _make_node(n, un)
	_place()
	queue_redraw()


func level_pos(n: int) -> Vector2:
	var y := custom_minimum_size.y - BOTTOM_PAD - (n - 1) * STEP - BB.world_of(n) * WORLD_GAP
	var x := size.x * 0.5 + sin((n - 1) * 0.85) * minf(size.x * 0.27, 200.0)
	return Vector2(x, y)


func _make_node(n: int, un: int) -> Control:
	var boss := (n - 1) % BB.LEVELS_PER_WORLD == BB.LEVELS_PER_WORLD - 1
	var d := BOSS if boss else NODE
	var locked := n > un
	var current := n == un
	var st := Save.level_stars(n)
	var bg: Color
	if locked:
		bg = Color(0.1, 0.11, 0.25, 0.85)
	elif current:
		bg = BB.C_GOLD
	else:
		bg = BB.C_GREEN if st >= 3 else Color("7fd8a0") if st > 0 else BB.C_GREEN
	var b := UI.button(str(n), bg, Color(1, 1, 1, 0.35) if locked else BB.C_INK, 40 if boss else 36, Vector2(d, d))
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # чтобы карту можно было листать пальцем по кнопкам
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(k).duplicate()
		sb.set_corner_radius_all(int(d / 2))
		sb.border_color = Color(1, 1, 1, 0.9) if current else Color(0, 0, 0, 0.25)
		sb.set_border_width_all(6 if current else 4)
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 5)
		b.add_theme_stylebox_override(k, sb)
	b.size = Vector2(d, d)
	add_child(b)
	if locked:
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		b.pressed.connect(func(): Audio.sfx("bad"))
	else:
		b.pressed.connect(func(): play.emit(n))
	if boss:
		var crown := UI.label("👑", 40)
		crown.position = Vector2(d / 2 - 26, -44)
		crown.size = Vector2(52, 50)
		b.add_child(crown)
	if st > 0:
		var stars := Label.new()
		stars.text = "★".repeat(st) + "☆".repeat(3 - st)
		stars.add_theme_font_size_override("font_size", 30)
		stars.add_theme_color_override("font_color", BB.C_GOLD)
		stars.add_theme_constant_override("outline_size", 8)
		stars.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars.position = Vector2(d / 2 - 60, d - 6)
		stars.size = Vector2(120, 36)
		b.add_child(stars)
	if current:
		# Текущий уровень «дышит», над ним стрелка
		b.pivot_offset = Vector2(d, d) / 2
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2.ONE * 1.1, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
		var arrow := UI.label("▼", 34, Color.WHITE, UI.F_BLACK)
		arrow.position = Vector2(d / 2 - 20, -54 if not boss else -96)
		arrow.size = Vector2(40, 44)
		b.add_child(arrow)
	return b


func _place() -> void:
	for n in _nodes:
		var b: Control = _nodes[n]
		b.position = level_pos(n) - b.size / 2


# ---------- Рисование: миры, дорожка, подписи ----------
func _draw() -> void:
	if _nodes.is_empty():
		return
	var f: Font = UI.F_BLACK
	var worlds := count / BB.LEVELS_PER_WORLD
	# Полосы миров
	for w in worlds:
		var wd := BB.world_def(w)
		var first := w * BB.LEVELS_PER_WORLD + 1
		var last := first + BB.LEVELS_PER_WORLD - 1
		var y0 := size.y if w == 0 else level_pos(first).y + (STEP + WORLD_GAP) / 2   # низ полосы
		var y1 := 0.0 if w == worlds - 1 else level_pos(last).y - (STEP + WORLD_GAP) / 2
		var cb: Color = wd[2]
		var ct: Color = wd[3]
		draw_polygon(PackedVector2Array([Vector2(0, y1), Vector2(size.x, y1), Vector2(size.x, y0), Vector2(0, y0)]),
			PackedColorArray([Color(ct, 0.75), Color(ct, 0.75), Color(cb, 0.75), Color(cb, 0.75)]))
	# Дорожка: точки по плавной кривой; пройденная часть золотая
	var un := Save.unlocked
	for n in range(1, count):
		var a := level_pos(n)
		var b := level_pos(n + 1)
		var steps := 9
		for k in range(1, steps):
			var t := float(k) / steps
			# Плавный изгиб: середина сдвигается к средней линии
			var p := a.lerp(b, t)
			p.x += sin(t * PI) * (size.x * 0.5 - (a.x + b.x) * 0.5) * 0.35
			var done := n < un
			draw_circle(p + Vector2(0, 4), 9.0, Color(0, 0, 0, 0.18))
			draw_circle(p, 8.0, Color(BB.C_GOLD, 0.95) if done else Color(1, 1, 1, 0.28))
	# Подписи миров: у начала каждого мира
	for w in worlds:
		var wd := BB.world_def(w)
		var first := w * BB.LEVELS_PER_WORLD + 1
		var y := level_pos(first).y + (135.0 if w == 0 else (STEP + WORLD_GAP) * 0.5)
		var title := "%s %s" % [wd[1], tr(wd[0])]
		var sub := tr("Мир %d") % (w + 1)
		var fs := 34
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pw := maxf(tw + 120, 300)
		var r := Rect2(size.x / 2 - pw / 2, y - 40, pw, 80)
		Skins.rrect(self, r, Color(0.05, 0.06, 0.16, 0.72), 40)
		draw_string(f, Vector2(r.position.x, y - 6), sub.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, pw, 18, Color(1, 1, 1, 0.6))
		draw_string(f, Vector2(r.position.x, y + 26), title, HORIZONTAL_ALIGNMENT_CENTER, pw, fs, Color.WHITE)
	# Сверху — туман и обещание продолжения
	var top := level_pos(count).y - STEP * 0.6
	draw_string(f, Vector2(0, top - 40), tr("Дальше — новые миры ✨"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Color(1, 1, 1, 0.65))
