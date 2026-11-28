class_name Skins
extends RefCounted
## Рисование блоков в 20 стилях (порт CSS-стилей веб-версии на _draw).
## Skins.block(ci, pos, s, color, skin, t, i) — блок размера s в точке pos (левый верхний угол).
## t — время (с), i — номер клетки для «волны» анимаций по полю.

const W := 0.11   ## шаг «волны» по полю, с (animation-delay: -110ms * i)

static var font: Font
## Фильтры для всего, что рисуется: прозрачность, яркость, обесцвечивание
static var ALPHA := 1.0
static var BRIGHT := 1.0
static var GRAY := 0.0

static var _sb := StyleBoxFlat.new()
static var _ci: CanvasItem
static var _c := Vector2.ZERO   ## центр блока в координатах ci
static var _k := 1.0            ## внешний масштаб блока


static func reset_filters() -> void:
	ALPHA = 1.0
	BRIGHT = 1.0
	GRAY = 0.0


static func fc(c: Color) -> Color:
	if GRAY > 0.0:
		var l := c.get_luminance()
		c = c.lerp(Color(l, l, l, c.a), GRAY)
	if BRIGHT != 1.0:
		c = Color(minf(c.r * BRIGHT, 1.0), minf(c.g * BRIGHT, 1.0), minf(c.b * BRIGHT, 1.0), c.a)
	c.a *= ALPHA
	return c


static func mix(a: Color, b: Color, pa: float) -> Color:
	## color-mix(a pa%, b)
	return b.lerp(a, pa)


static func rrect(ci: CanvasItem, r: Rect2, col: Color, rad: float) -> void:
	_sb.bg_color = fc(col)
	_sb.set_corner_radius_all(int(maxf(rad, 0.0)))
	_sb.anti_aliasing = true
	_sb.corner_detail = 5
	ci.draw_style_box(_sb, r)


static func bevel(ci: CanvasItem, r: Rect2, col: Color, rad: float, s: float) -> void:
	## Фон блока: цвет + тень снизу + блик сверху
	rrect(ci, r, col.darkened(0.25), rad)
	rrect(ci, Rect2(r.position, Vector2(r.size.x, r.size.y - s * 0.083)), col.lerp(Color.WHITE, 0.35), rad)
	rrect(ci, Rect2(r.position + Vector2(0, s * 0.0625), Vector2(r.size.x, r.size.y - s * 0.146)), col, rad * 0.8)


static func _tf(off: Vector2, rot := 0.0, sc := Vector2.ONE) -> void:
	_ci.draw_set_transform(_c + off * _k, rot, sc * _k)


static func ph(t: float, period: float, delay := 0.0) -> float:
	return fposmod(t + delay, period) / period


static func wave(p: float) -> float:
	## 0 → 1 → 0, плавно (ease-in-out «туда-обратно»)
	return (1.0 - cos(TAU * p)) * 0.5


static func keys(p: float, frames: Array) -> float:
	## Ключевые кадры [[доля, значение], ...] с плавной интерполяцией
	for k in range(1, frames.size()):
		if p <= frames[k][0]:
			var a: Array = frames[k - 1]
			var b: Array = frames[k]
			var u: float = (p - a[0]) / maxf(b[0] - a[0], 0.0001)
			return lerpf(a[1], b[1], smoothstep(0.0, 1.0, u))
	return frames[frames.size() - 1][1]


static func vgrad(ci: CanvasItem, r: Rect2, stops: Array) -> void:
	## Вертикальный градиент: stops = [[доля, цвет], ...]
	for k in range(1, stops.size()):
		var y0: float = r.position.y + r.size.y * stops[k - 1][0]
		var y1: float = r.position.y + r.size.y * stops[k][0]
		if y1 <= y0:
			continue
		var c0 := fc(stops[k - 1][1])
		var c1 := fc(stops[k][1])
		ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)]),
			PackedColorArray([c0, c0, c1, c1]))


static func hgrad(ci: CanvasItem, r: Rect2, x0: float, width: float, stops: Array) -> void:
	## Горизонтальный градиент от x0 шириной width, обрезанный по r
	for k in range(1, stops.size()):
		var a: float = x0 + width * stops[k - 1][0]
		var b: float = x0 + width * stops[k][0]
		var ca: Color = stops[k - 1][1]
		var cb: Color = stops[k][1]
		var a2 := maxf(a, r.position.x)
		var b2 := minf(b, r.end.x)
		if b2 <= a2:
			continue
		var c0 := fc(ca.lerp(cb, (a2 - a) / (b - a)))
		var c1 := fc(ca.lerp(cb, (b2 - a) / (b - a)))
		ci.draw_polygon(PackedVector2Array([Vector2(a2, r.position.y), Vector2(b2, r.position.y), Vector2(b2, r.end.y), Vector2(a2, r.end.y)]),
			PackedColorArray([c0, c1, c1, c0]))


static func circ(ci: CanvasItem, p: Vector2, rad: float, col: Color) -> void:
	if rad > 0.2:
		ci.draw_circle(p, rad, fc(col), true, -1.0, true)


static func ellipse(ci: CanvasItem, p: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 18:
		var a := TAU * k / 18.0
		pts.append(p + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, fc(col))


static func radial(ci: CanvasItem, p: Vector2, rad: float, c0: Color, c1: Color, steps := 7) -> void:
	## Радиальный градиент кругами (от края к центру)
	for k in steps:
		var u := 1.0 - float(k) / steps
		circ(ci, p, rad * u, c0.lerp(c1, u))


static func clip_poly(ci: CanvasItem, poly: PackedVector2Array, r: Rect2, col: Color) -> void:
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for part in Geometry2D.intersect_polygons(poly, box):
		if part.size() >= 3:
			ci.draw_colored_polygon(part, fc(col))


static func heart_poly(p: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 28:
		var t := TAU * k / 28.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(p + Vector2(x, y + 2.0) * size / 34.0)
	return pts


## Блок в стиле skin. stone — камень Аркады (без стиля). fruit — эмодзи поверх.
static func block(ci: CanvasItem, pos: Vector2, s: float, col: Color, skin: int, t: float, i: int,
		fruit := "", stone := false, scale := 1.0, radius := 0.125) -> void:
	if s * scale < 1.0:
		return   # блок в начале/конце анимации — многоугольники такого размера не рисуются
	_ci = ci
	_k = scale
	_c = pos + Vector2(s, s) * 0.5
	var h := s * 0.5
	var R := Rect2(-h, -h, s, s)
	var rad := s * radius
	_tf(Vector2.ZERO)
	if stone or skin <= 0:
		bevel(ci, R, col, rad, s)
	else:
		_skin(ci, R, s, rad, col, skin, t, i)
	if fruit != "" and font:
		_tf(Vector2.ZERO)
		var fs := int(s * 0.58)
		var asc := font.get_ascent(fs)
		var desc := font.get_descent(fs)
		ci.draw_string(font, Vector2(-h, (asc - desc) * 0.5), fruit, HORIZONTAL_ALIGNMENT_CENTER, s, fs, fc(Color.WHITE))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _skin(ci: CanvasItem, R: Rect2, s: float, rad: float, col: Color, skin: int, t: float, i: int) -> void:
	var h := s * 0.5
	var P := func(x: float, y: float) -> Vector2: return Vector2(-h + x * s, -h + y * s)
	var wd := i * W
	match BB.SKINS[skin][0]:
		"disco":
			bevel(ci, R, col, rad, s)
			var tile := s * 0.833
			var off := ph(t, 1.1) * tile
			var stops := [[0.0, Color("7f8aa0")], [0.25, Color.WHITE], [0.5, mix(col, Color.WHITE, 0.65)], [0.75, Color.WHITE], [1.0, Color("7f8aa0")]]
			var x := -h - tile + off
			while x < h:
				hgrad(ci, R, x, tile, stops)
				x += tile
			var line := Color(0, 0, 0, 0.28)
			for k in range(1, 4):
				ci.draw_rect(Rect2(-h + s * 0.25 * k, -h, maxf(1.0, s / 48.0), s), fc(line))
				ci.draw_rect(Rect2(-h, -h + s * 0.25 * k, s, maxf(1.0, s / 48.0)), fc(line))
			circ(ci, P.call(0.28, 0.28), s * 0.09, Color(1, 1, 1, 0.5))
			circ(ci, P.call(0.28, 0.28), s * 0.05, Color.WHITE)
			var tw := wave(ph(t, 0.8, wd))
			var sc := 1.0 - 0.5 * tw
			circ(ci, P.call(0.73, 0.27), s * 0.14 * sc, Color(1, 1, 1, 0.35 * (1.0 - 0.8 * tw)))
			circ(ci, P.call(0.73, 0.27), s * 0.05 * sc, Color(1, 1, 1, 1.0 - 0.8 * tw))
		"melon":
			bevel(ci, R, col, rad, s)
			var k := wave(ph(t, 1.8, wd))
			_tf(Vector2.ZERO, deg_to_rad(-4.0) * k, Vector2.ONE * (1.0 - 0.07 * k))
			vgrad(ci, R, [[0.0, Color("ff4d6d")], [0.7, Color("ff4d6d")], [0.7, Color("fdeaea")], [0.78, Color("fdeaea")],
				[0.78, Color("74d86b")], [0.87, Color("74d86b")], [0.87, Color("2f8f3a")], [1.0, Color("2f8f3a")]])
			for p in [Vector2(0.30, 0.38), Vector2(0.56, 0.26), Vector2(0.74, 0.46), Vector2(0.46, 0.56)]:
				ellipse(ci, P.call(p.x, p.y), s * 0.06, s * 0.095, Color("222222"))
		"egg":
			rrect(ci, R, mix(col, Color("2b2b33"), 0.3), rad)
			rrect(ci, Rect2(R.position + Vector2(0, s - s * 0.0625), Vector2(s, s * 0.0625)), Color(0, 0, 0, 0.35), 0)
			var white := Color("fffdf3")
			circ(ci, P.call(0.36, 0.62), s * 0.30, white)
			circ(ci, P.call(0.64, 0.40), s * 0.30, white)
			circ(ci, P.call(0.5, 0.5), s * 0.27, white)
			var p := wrapf(ph(t, 1.3, wd), 0.0, 1.0)
			var sx := keys(p, [[0.0, 1.0], [0.3, 1.12], [0.6, 0.94], [1.0, 1.0]])
			var sy := keys(p, [[0.0, 1.0], [0.3, 0.9], [0.6, 1.06], [1.0, 1.0]])
			var yc: Vector2 = P.call(0.51, 0.49)
			_tf(yc, 0.0, Vector2(sx, sy))
			circ(ci, Vector2(0, s * 0.02), s * 0.2, Color(0, 0, 0, 0.18))
			radial(ci, Vector2.ZERO, s * 0.2, Color("ffc107"), Color("ff9100"), 5)
			circ(ci, Vector2(-s * 0.06, -s * 0.07), s * 0.05, Color(1, 1, 1, 0.6))
		"neon":
			var k := wave(ph(t, 1.4, wd))
			var c2 := col.lerp(Color.WHITE, 0.25 * k)
			for g in 3:
				var e := s * (0.03 + 0.05 * k) * (g + 1) / 3.0
				rrect(ci, R.grow(e), Color(c2, 0.18 * (1.0 - g / 3.0)), rad + e)
			rrect(ci, R, c2, rad)
			var bw := s * 0.042
			rrect(ci, R.grow(-bw), Color("0c0e22"), rad - bw)
			rrect(ci, R.grow(-bw), Color(c2, 0.25 + 0.2 * k), rad - bw)
			rrect(ci, R.grow(-bw - s * (0.08 + 0.06 * k)), Color("0c0e22"), rad)
		"candy":
			rrect(ci, R, Color.WHITE, rad)
			var period := s * 12.0 / 48.0 / 0.7071
			var off := ph(t, 0.8) * period
			var u := -2.0 * s + off
			while u < 2.0 * s:
				var poly := PackedVector2Array([Vector2(u - h, -h), Vector2(u + period * 0.5 - h, -h),
					Vector2(u + period * 0.5 + h, h), Vector2(u + h, h)])
				clip_poly(ci, poly, R, col)
				u += period
			ci.draw_rect(Rect2(-h, -h, s, s * 0.0625), fc(Color(1, 1, 1, 0.55)))
			ci.draw_rect(Rect2(-h, h - s * 0.083, s, s * 0.083), fc(Color(0, 0, 0, 0.2)))
		"jelly":
			var r2 := s * 0.32
			rrect(ci, R, mix(col, Color.WHITE, 0.8).darkened(0.18), r2)
			rrect(ci, Rect2(R.position, Vector2(s, s * 0.9)), mix(col, Color.WHITE, 0.8), r2)
			var a := TAU * ph(t, 3.2, wd)
			var c: Vector2 = Vector2(cos(a), sin(a)) * s * 0.21
			circ(ci, c, s * 0.15, Color(1, 1, 1, 0.3))
			circ(ci, c, s * 0.08, Color(1, 1, 1, 0.9))
		"eyes":
			bevel(ci, R, col, rad, s)
			var p := ph(t, 4.0, wd)
			var dx := keys(p, [[0.0, -0.06], [0.4, 0.06], [0.48, 0.06], [0.7, 0.0], [1.0, -0.06]])
			var dy := keys(p, [[0.0, 0.0], [0.48, 0.0], [0.7, -0.05], [1.0, 0.0]])
			var sy := keys(p, [[0.0, 1.0], [0.4, 1.0], [0.44, 0.1], [0.48, 1.0], [1.0, 1.0]])
			for ex in [0.32, 0.68]:
				circ(ci, P.call(ex, 0.45), s * 0.15, Color.WHITE)
				var py := 0.5 + (0.45 - 0.5) * sy + dy
				ellipse(ci, P.call(ex + dx, py), s * 0.062, s * 0.062 * sy, Color("1a1a2e"))
		"ice":
			vgrad(ci, R, [[0.0, Color("e6f9ff")], [0.6, Color("8fd6ff")], [1.0, mix(col, Color("5fbfff"), 0.35)]])
			var p := ph(t, 2.6, wd)
			if p < 0.6:
				var x := lerpf(1.1, -1.1, p / 0.6) * s
				var sk := s * 0.36
				var band := PackedVector2Array([Vector2(x - s * 0.1 + sk, -h), Vector2(x + s * 0.1 + sk, -h),
					Vector2(x + s * 0.1 - sk, h), Vector2(x - s * 0.1 - sk, h)])
				clip_poly(ci, band, R, Color(1, 1, 1, 0.45))
				var core := PackedVector2Array([Vector2(x - s * 0.04 + sk, -h), Vector2(x + s * 0.04 + sk, -h),
					Vector2(x + s * 0.04 - sk, h), Vector2(x - s * 0.04 - sk, h)])
				clip_poly(ci, core, R, Color(1, 1, 1, 0.6))
			ci.draw_rect(R, fc(Color(1, 1, 1, 0.8)), false, maxf(1.0, s / 48.0))
		"gold":
			var p := ph(t, 4.0, i * 0.25)
			var fx := 1.0
			if p > 0.75:
				fx = cos(TAU * smoothstep(0.0, 1.0, (p - 0.75) / 0.25))
			_tf(Vector2.ZERO, 0.0, Vector2(fx, 1.0))
			vgrad(ci, R, [[0.0, Color("fff3b0")], [0.35, Color("f5c518")], [0.72, Color("b8860b")], [1.0, Color("ffe680")]])
			ci.draw_arc(Vector2.ZERO, s * 0.22, 0, TAU, 28, fc(Color(0.47, 0.31, 0, 0.35)), maxf(s * 0.03, 1.0), s >= 40.0)
			ci.draw_rect(Rect2(-h, -h, s, s * 0.042), fc(Color(1, 1, 1, 0.7)))
			ci.draw_rect(Rect2(-h, h - s * 0.0625, s, s * 0.0625), fc(Color(0.47, 0.31, 0, 0.5)))
		"pixel":
			ci.draw_rect(R, fc(col))
			var q := s * 0.25
			var lite := Color(1, 1, 1, 0.2)
			for ty in 2:
				for tx in 2:
					var o := Vector2(-h + tx * 2 * q, -h + ty * 2 * q)
					ci.draw_rect(Rect2(o + Vector2(q, 0), Vector2(q, q)), fc(lite))
					ci.draw_rect(Rect2(o + Vector2(0, q), Vector2(q, q)), fc(lite))
			var e := s * 0.083
			ci.draw_rect(Rect2(-h, h - e, s, e), fc(Color(0, 0, 0, 0.35)))
			ci.draw_rect(Rect2(h - e, -h, e, s), fc(Color(0, 0, 0, 0.35)))
			ci.draw_rect(Rect2(-h, -h, s, e), fc(Color(1, 1, 1, 0.4)))
			ci.draw_rect(Rect2(-h, -h, e, s), fc(Color(1, 1, 1, 0.4)))
		"water":
			vgrad(ci, R, [[0.0, Color("d9f3ff")], [1.0, Color("a8defa")]])
			var a := TAU * ph(t, 6.0, wd)
			var pts := PackedVector2Array()
			for k in 13:
				var x := k / 12.0
				var y := 0.47 + 0.07 * sin(a) + 0.16 * (x - 0.5) * cos(a) + 0.025 * sin(TAU * x * 1.5 + a * 2.0)
				pts.append(P.call(x, clampf(y, 0.0, 1.0)))
			pts.append(P.call(1, 1))
			pts.append(P.call(0, 1))
			ci.draw_colored_polygon(pts, fc(mix(col, Color("1e88e5"), 0.3)))
		"donut":
			bevel(ci, R, col, rad, s)
			var a := TAU * ph(t, 5.0)
			_tf(Vector2.ZERO, a)
			circ(ci, Vector2.ZERO, s * 0.48, Color("d9a066"))
			circ(ci, Vector2.ZERO, s * 0.37, Color("f48fb1"))
			circ(ci, Vector2.ZERO, s * 0.125, col)
			for d in [[0.32, 0.30, "4fc3f7"], [0.66, 0.28, "ffeb3b"], [0.72, 0.64, "81c784"], [0.30, 0.68, "ffffff"]]:
				circ(ci, P.call(d[0], d[1]), s * 0.035, Color(d[2]))
		"cookie":
			bevel(ci, R, col, rad, s)
			var k := wave(ph(t, 1.5, wd))
			_tf(Vector2(0, -0.09 * s * k), 0.0, Vector2.ONE * (1.0 + 0.04 * k))
			circ(ci, Vector2.ZERO, s * 0.475, Color("b5733a"))
			circ(ci, Vector2.ZERO, s * 0.43, Color("e2a65c"))
			for d in [[0.32, 0.30, 0.078], [0.66, 0.36, 0.068], [0.44, 0.68, 0.08], [0.72, 0.72, 0.05]]:
				circ(ci, P.call(d[0], d[1]), s * d[2], Color("3e2210"))
		"wood":
			hgrad(ci, R, -h, s, [[0.0, Color("a0652c")], [0.5, Color("c98b4c")], [1.0, Color("8b5524")]])
			var step := s * 7.0 / 48.0
			var x := -h
			while x < h:
				ci.draw_rect(Rect2(x, -h, minf(s * 2.0 / 48.0, h - x), s), fc(Color(0, 0, 0, 0.12)))
				x += step
			ci.draw_rect(R.grow(-s / 48.0), fc(Color(0.24, 0.12, 0.04, 0.5)), false, s * 2.0 / 48.0)
			ci.draw_rect(Rect2(-h, -h, s, s * 0.0625), fc(Color(1, 1, 1, 0.2)))
		"galaxy":
			rrect(ci, R, Color("110934"), rad)
			radial(ci, Vector2.ZERO, s * 0.5, mix(col, Color("6a00ff"), 0.6), Color("1a0c45"), 8)
			var p := ph(t, 6.0)
			_star_tiles(ci, R, s * 18.0 / 48.0, Vector2(0.3, 0.4), p * Vector2(1, 1), s * 1.3 / 48.0, Color.WHITE)
			_star_tiles(ci, R, s * 26.0 / 48.0, Vector2(0.7, 0.2), p * Vector2(-1, 1), s * 1.1 / 48.0, Color("cfe8ff"))
		"bubble":
			rrect(ci, R, mix(col, Color("141a3a"), 0.25), rad)
			var p := ph(t, 3.0, i * 0.37)
			var e := p * p   # ease-in
			var ty := keys(e, [[0.0, 0.3], [0.85, -0.12], [1.0, -0.18]])
			var sc := keys(e, [[0.0, 0.5], [0.85, 1.0], [1.0, 1.35]])
			var op := keys(e, [[0.0, 0.0], [0.2, 1.0], [0.85, 1.0], [1.0, 0.0]])
			_tf(Vector2(0, ty * s), 0.0, Vector2.ONE * sc)
			var a0 := ALPHA
			ALPHA *= op
			circ(ci, Vector2.ZERO, s * 0.38, col)
			circ(ci, Vector2.ZERO, s * 0.3, mix(col, Color("141a3a"), 0.45))
			circ(ci, Vector2(-s * 0.07, -s * 0.09), s * 0.06, Color.WHITE)
			ALPHA = a0
		"heart":
			rrect(ci, R, Color("ff4f8b").darkened(0.2), rad)
			vgrad(ci, Rect2(R.position, Vector2(s, s * 0.92)), [[0.0, Color("ff9abb")], [1.0, Color("ff4f8b")]])
			var p := ph(t, 1.0, wd)
			var sc := keys(p, [[0.0, 0.85], [0.15, 1.15], [0.3, 0.9], [0.45, 1.05], [1.0, 0.85]])
			_tf(Vector2(0, s * 0.03), 0.0, Vector2.ONE * sc)
			ci.draw_colored_polygon(heart_poly(Vector2(0, s * 0.04), s * 0.5), fc(Color(0.59, 0, 0.24, 0.35)))
			ci.draw_colored_polygon(heart_poly(Vector2.ZERO, s * 0.5), fc(Color.WHITE))
		"matrix":
			vgrad(ci, R, [[0.0, Color("001a0a")], [1.0, Color("003b17")]])
			var step := s * 6.0 / 48.0
			var x := -h + s * 5.0 / 48.0
			while x < h:
				ci.draw_rect(Rect2(x, -h, maxf(1.0, s / 48.0), s), fc(Color(0, 1, 0.47, 0.12)))
				x += step
			var p := ph(t, 2.2, i * 0.33)
			var bh := s * 0.45
			var top := lerpf(-1.1, 2.4, p) * bh - h
			var y0 := maxf(top, -h)
			var y1 := minf(top + bh, h)
			if y1 > y0:
				var g := Color(0, 1, 0.53, 0.85)
				var c0 := Color(g, g.a * (y0 - top) / bh)
				var c1 := Color(g, g.a * (y1 - top) / bh)
				ci.draw_polygon(PackedVector2Array([Vector2(-h, y0), Vector2(h, y0), Vector2(h, y1), Vector2(-h, y1)]),
					PackedColorArray([fc(c0), fc(c0), fc(c1), fc(c1)]))
			ci.draw_rect(R, fc(Color("00ff88")), false, maxf(1.0, s / 48.0))
		"pizza":
			vgrad(ci, R, [[0.0, Color("ffd54f")], [1.0, Color("ffb300")]])
			for d in [[0.30, 0.34], [0.70, 0.62]]:
				circ(ci, P.call(d[0], d[1]), s * 0.125, Color("c62828"))
			for d in [[0.34, 0.76], [0.72, 0.24]]:
				circ(ci, P.call(d[0], d[1]), s * 0.048, Color("2e7d32"))
			ci.draw_rect(R.grow(-s * 1.5 / 48.0), fc(Color("d9822b")), false, s * 3.0 / 48.0)
		_:
			bevel(ci, R, col, rad, s)
	_tf(Vector2.ZERO)


static func _star_tiles(ci: CanvasItem, R: Rect2, tile: float, at: Vector2, shift: Vector2, rad: float, col: Color) -> void:
	var o := Vector2(fposmod(shift.x * tile, tile), fposmod(shift.y * tile, tile))
	var y := R.position.y - tile + o.y
	while y < R.end.y:
		var x := R.position.x - tile + o.x
		while x < R.end.x:
			var p := Vector2(x, y) + at * tile
			if R.grow(-rad).has_point(p):
				circ(ci, p, rad, col)
			x += tile
		y += tile
