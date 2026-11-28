class_name GameScreen
extends Control
## Экран игры: Классика, Аркада, Против бота, Онлайн-бой. Порт игровой части index.html.

const N := 8
const DUEL_TIME := 180                 ## секунд
const BOT_THINK := Vector2(1.7, 3.2)   ## пауза бота между ходами, с
const BOT_MISTAKE := 0.15              ## шанс, что бот сходит не лучшим образом
const EMOJI := ["👍", "😂", "😮", "😎", "😭"]   ## реакции в онлайн-бою (на сервер уходит номер)

var main: Node   ## Main (экраны, подсказки, отсчёт)
var fx: FxLayer

# ---------- Состояние ----------
var mode := "classic"
var level := 1
var board: Array = []
var pieces: Array = [null, null, null]
var score := 0
var combo := 0
var scoring := Scoring.new()          ## очки и серия комбо (scripts/scoring.gd)
var goals: Array = []
var finished := false
var skin_idx := 0
var gen := {"since": 0}               ## счётчик «джекпота» игрока
var shown_score := 0
var best_at_start := 0
var record_shown := false
var drag := {}
var duel := {}
var bot := {}
var opp_name := "Соперник"
var ranked := false                   ## онлайн-бой из быстрого поиска (меняет рейтинг)
var daily_day := ""                   ## вызов дня: дата (UTC) и генератор с общим для всех зерном
var daily_rng := RandomNumberGenerator.new()
var moves := 0                        ## ходов в уровне Аркады (для звёзд)
var level_par := 0                    ## ходов на три звезды
var moves_l: Label
var daily_rank: Array = []           ## [место, всего] из таблицы дня — для «Поделиться»
var last_result: Array = [0, 0]       ## счёт последнего боя
var _t_start := 0.0                   ## когда началась партия — для статистики
var revive_used := false              ## «второй шанс» — один раз за партию
var combo_pill: ComboPill
var emoji_row: HBoxContainer          ## смайлики сопернику в онлайн-бою
var _emoji_t := 0.0
var rec_bar: ProgressBar              ## полоска «до рекорда» под рекордом
var _tok := 0
var _bot_tok := 0
var _score_tw: Tween

# ---------- Узлы ----------
var col: VBoxContainer
var hud: HBoxContainer
var board_view: BoardView
var tray: TrayView
var bot_panel: PanelContainer
var bot_board: BoardView
var bot_tray: TrayView
var bot_head: Label
var bot_score_l: Label
var bot_status: Label
var btn_restart: Button
var btn_mute: Button
var corner_r: HBoxContainer
var score_l: Label
var best_l: Label
var timer_l: Label
var opp_score_l: Label
var goal_nodes: Array = []
var ov_lose: Dictionary
var ov_win: Dictionary
var ov_duel: Dictionary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.resize(N * N)
	skin_idx = Save.skin

	col = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 18)
	add_child(col)

	hud = HBoxContainer.new()
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	hud.add_theme_constant_override("separation", 50)
	hud.custom_minimum_size = Vector2(0, 100)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hud)

	_build_bot_panel()

	board_view = BoardView.new()
	col.add_child(UI.centered(board_view))

	tray = TrayView.new()
	tray.grab.connect(_start_drag)
	col.add_child(UI.centered(tray))

	var back := UI.corner("← Назад")
	back.position = Vector2(22, 22)
	back.pressed.connect(_on_back)
	add_child(back)
	var right := UI.hrow(self, 14)
	corner_r = right
	btn_mute = UI.corner("🔊")
	btn_mute.pressed.connect(_toggle_mute)
	right.add_child(btn_mute)
	btn_restart = UI.corner("Заново")
	btn_restart.pressed.connect(func(): start_game(mode, level))
	right.add_child(btn_restart)

	ov_lose = _overlay("Нет ходов", "Выйти", "Ещё раз")
	ov_lose.left.pressed.connect(_on_back)
	ov_lose.right.pressed.connect(func(): start_game(mode, level))
	var rv := UI.button("💖 Второй шанс", BB.C_GREEN, BB.C_INK, 34, Vector2(480, 96))
	rv.pressed.connect(revive)
	ov_lose.revive = UI.centered(rv)
	ov_lose.box.add_child(ov_lose.revive)
	ov_lose.box.move_child(ov_lose.revive, ov_lose.row.get_index())
	combo_pill = ComboPill.new()
	add_child(combo_pill)
	emoji_row = HBoxContainer.new()
	emoji_row.add_theme_constant_override("separation", 14)
	emoji_row.visible = false
	add_child(emoji_row)
	for k in EMOJI.size():
		var eb := UI.button(EMOJI[k], Color(1, 1, 1, 0.12), Color.WHITE, 38, Vector2(84, 84))
		eb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		eb.pressed.connect(send_emoji.bind(k))
		emoji_row.add_child(eb)
	ov_win = _overlay("Уровень пройден! 🎉", "К уровням", "Следующий →")
	ov_win.left.pressed.connect(func(): main.open_levels())
	ov_win.right.pressed.connect(func(): start_game("arcade", level + 1))
	ov_duel = _overlay("", "Меню", "Реванш")
	ov_duel.left.pressed.connect(func():
		if mode == "online":
			Net.send({"t": "leave"})
		main.show_screen("menu"))
	ov_duel.right.pressed.connect(_on_rematch)

	resized.connect(_layout)


func _build_bot_panel() -> void:
	bot_panel = PanelContainer.new()
	bot_panel.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.22), 26, Vector4(26, 12, 26, 12)))
	bot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(UI.centered(bot_panel))
	var h := UI.hrow(bot_panel, 26)
	bot_board = BoardView.new()
	bot_board.radius = 0.2
	bot_board.corner = 12
	bot_board.show_fruits = false
	bot_board.set_metrics(16, 2, 5)
	h.add_child(bot_board)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	bot_head = UI.label("🤖 Бот", 22, Color(1, 1, 1, 0.75), UI.F_BOLD, HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(bot_head)
	bot_score_l = UI.label("0", 40, Color.WHITE, UI.F_BLACK, HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(bot_score_l)
	bot_tray = TrayView.new()
	bot_tray.interactive = false
	bot_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_tray.mini = 9
	bot_tray.gap = 2
	bot_tray.custom_minimum_size = Vector2(170, 50)
	v.add_child(bot_tray)
	bot_status = UI.label("думает…", 20, Color(1, 1, 1, 0.55), UI.F_REG, HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(bot_status)


func _overlay(title: String, left: String, right: String) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	root.z_index = 20
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.12, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var v := UI.center_box(root, 22)
	var t := UI.label(title, 56, Color.WHITE, UI.F_BLACK)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(640, 0)
	v.add_child(UI.centered(t))
	var txt := UI.rich(34)
	txt.custom_minimum_size = Vector2(620, 0)
	v.add_child(UI.centered(txt))
	var row := UI.hrow(v, 22)
	var l := UI.button(left, Color(1, 1, 1, 0.14), Color.WHITE, 32, Vector2(220, 84))
	var r := UI.button(right, BB.C_YELLOW, BB.C_INK, 32, Vector2(240, 84))
	row.add_child(l)
	row.add_child(r)
	var sh := UI.button("📤 Поделиться", Color(1, 1, 1, 0.1), Color.WHITE, 26, Vector2(0, 66))
	sh.add_theme_stylebox_override("normal", UI.box(Color(1, 1, 1, 0.1), 999, Vector4(30, 0, 30, 0)))
	sh.pressed.connect(share_result)
	v.add_child(UI.centered(sh))
	return {"root": root, "title": t, "text": txt, "left": l, "right": r, "share": sh, "box": v, "row": row}


## Текст результата в буфер обмена — вставить в любой мессенджер
func share_result() -> void:
	var g := tr(BB.GAME_NAME)
	var txt := ""
	match mode:
		"daily":
			var place := (tr(", место %d из %d") % daily_rank) if daily_rank.size() == 2 and daily_rank[0] > 0 else ""
			txt = tr("«%s», вызов дня %s: %d очков%s. Сможешь больше?") % [g, daily_day, score, place]
		"arcade":
			txt = tr("«%s»: прошёл уровень %d Аркады!") % [g, level]
		"online":
			txt = tr("«%s»: онлайн-бой %d : %d %s") % [g, last_result[0], last_result[1], opp_name]
		"duel":
			txt = tr("«%s»: бой с ботом %d : %d") % [g, score, bot.get("score", 0)]
		_:
			txt = tr("«%s»: мой счёт %d в классике! Побьёшь?") % [g, score]
	DisplayServer.clipboard_set(txt)
	main.toast(tr("Скопировано — отправь друзьям") + "\n\n" + txt)


func _show_overlay(o: Dictionary) -> void:
	main.hide_toast()
	o.root.visible = true
	o.root.modulate.a = 0.0
	o.root.create_tween().tween_property(o.root, "modulate:a", 1.0, 0.3)


func hide_overlays() -> void:
	for o in [ov_lose, ov_win, ov_duel]:
		o.root.visible = false


func _set_text(o: Dictionary, bb: String) -> void:
	var r: RichTextLabel = o.text
	r.text = "[center]" + bb + "[/center]"


func _append_text(o: Dictionary, bb: String) -> void:
	var r: RichTextLabel = o.text
	r.text = r.text.trim_suffix("[/center]") + bb + "[/center]"


# ---------- Утилиты ----------
func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func later(sec: float, cb: Callable) -> void:
	var t := _tok
	get_tree().create_timer(sec).timeout.connect(func():
		if t == _tok:
			cb.call())


func _bot_later(sec: float, cb: Callable) -> void:
	var t := _bot_tok
	get_tree().create_timer(sec).timeout.connect(func():
		if t == _bot_tok and not duel.is_empty():
			cb.call())


static func bits(b: Array) -> int:
	var m := 0
	for i in b.size():
		if b[i] != null:
			m |= 1 << i
	return m


static func mask_indices(m: int) -> Array[int]:
	var out: Array[int] = []
	for i in 64:
		if m & (1 << i):
			out.append(i)
	return out


func board_center_global() -> Vector2:
	return board_view.get_global_transform() * (board_view.size * Vector2(0.5, 0.45))


func float_text(main_t: String, sub: String, sz := 1, gold := false) -> void:
	fx.float_text(board_center_global(), main_t, sub, sz, gold)


# ---------- Фигуры ----------
## Фрукт для новой фигуры — из тех, что ещё нужно собрать (с весом по остатку)
func pick_fruit(rng: RandomNumberGenerator = null) -> String:
	var need := goals.filter(func(g): return g.left > 0)
	if need.is_empty():
		return ""
	var total := 0
	for g in need:
		total += g.left
	var x := (rng.randf() if rng else randf()) * total
	for g in need:
		x -= g.left
		if x < 0:
			return g.f
	return need[0].f


func new_piece(s := -1, rng: RandomNumberGenerator = null) -> Dictionary:
	if s < 0:
		s = (rng.randi() if rng else randi()) % BB.SHAPES.size()
	var sh: Dictionary = BB.SHAPES[s]
	var fruits: Array[String] = []
	fruits.resize(sh.cells.size())
	fruits.fill("")
	var p := {"s": s, "cells": sh.cells, "fruits": fruits, "h": sh.h, "w": sh.w, "base": sh.base,
		"color": BB.COLORS[(rng.randi() if rng else randi()) % BB.COLORS.size()]}
	if mode == "arcade":
		var n := 1 if randf() < 0.55 else 0
		if n and sh.cells.size() >= 4 and randf() < 0.3:
			n = 2
		var idx := range(sh.cells.size())
		idx.shuffle()
		for k in n:
			fruits[idx[k]] = pick_fruit()
	return p


func smart_set(b: Array, g: Dictionary) -> Array:
	var ids := BBAI.smart_set(bits(b), g)
	if ids.is_empty():
		return []
	return ids.map(func(s): return new_piece(s))


func refill() -> void:
	if mode == "daily":
		# Вызов дня: тройки идут из общего генератора и не зависят от поля — у всех одинаковые
		pieces = [new_piece(-1, daily_rng), new_piece(-1, daily_rng), new_piece(-1, daily_rng)]
		return
	var smart := smart_set(board, gen)
	if not smart.is_empty():
		pieces = smart
		return
	refill_random()


## Подбор тройки в фоновом потоке; after вызывается, когда фигуры уже в лотке
func refill_async(after: Callable) -> void:
	tray.set_pieces([null, null, null], [false, false, false])
	var b := bits(board)
	var since: int = gen.since
	var tok := _tok
	_bg(func():
		var g := {"since": since}
		var ids := BBAI.smart_set(b, g)
		_refill_done.call_deferred(ids, g.since, tok, after))


func _refill_done(ids: Array, since: int, tok: int, after: Callable) -> void:
	if tok != _tok:
		return
	gen.since = since
	if ids.is_empty():
		refill_random()
	else:
		pieces = ids.map(func(s): return new_piece(s))
	Audio.sfx("refill")
	render_tray(true)
	after.call()


func refill_random() -> void:
	var b := bits(board)
	var set := []
	for t in 30:
		set = [new_piece(), new_piece(), new_piece()]
		if set.any(func(p): return BBAI.fits_anywhere(b, p)):
			break
	pieces = set


var _tasks: Array[int] = []


func _bg(job: Callable) -> void:
	_tasks = _tasks.filter(func(t): return not WorkerThreadPool.is_task_completed(t))
	_tasks.append(WorkerThreadPool.add_task(job))


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)


## Камни с фруктами на старте уровня (без готовых линий); раскладка зависит только от уровня
func seed_stones(count: int, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var placed := 0
	var tries := 0
	while placed < count and tries < 500:
		tries += 1
		var i := rng.randi() % (N * N)
		if board[i] != null:
			continue
		board[i] = {"c": BB.STONE, "f": pick_fruit(rng) if rng.randf() < 0.5 else ""}
		if BBAI.full_lines(bits(board))[1] > 0:
			board[i] = null
			continue
		placed += 1


## Стартовое поле вызова дня: несколько блоков из того же генератора
func seed_daily() -> void:
	daily_rng.seed = hash("blockboom-daily-" + daily_day)
	var placed := 0
	var tries := 0
	while placed < 10 and tries < 200:
		tries += 1
		var i := daily_rng.randi() % (N * N)
		var c: Color = BB.COLORS[daily_rng.randi() % BB.COLORS.size()]
		if board[i] != null:
			continue
		board[i] = {"c": c, "f": ""}
		if BBAI.full_lines(bits(board))[1] > 0:
			board[i] = null
			continue
		placed += 1


# ---------- Отрисовка ----------
func render_board() -> void:
	board_view.cells = board


func render_tray(animate := false) -> void:
	var b := bits(board)
	var nf := pieces.map(func(p): return p != null and not BBAI.fits_anywhere(b, p))
	tray.set_pieces(pieces, nf, animate)
	tray.hidden_slot = -1


func _stat(title: String, value: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hud.add_child(v)
	v.add_child(UI.label(tr(title).to_upper(), 21, Color(1, 1, 1, 0.65), UI.F_BOLD))
	var b := UI.label(value, 56, Color.WHITE, UI.F_BLACK)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(b)
	return b


func render_hud() -> void:
	for ch in hud.get_children():
		hud.remove_child(ch)
		ch.queue_free()
	score_l = null
	best_l = null
	rec_bar = null
	timer_l = null
	opp_score_l = null
	goal_nodes.clear()
	hud.add_theme_constant_override("separation", 50)
	hud.custom_minimum_size.y = 100 + _combo_room()   # под счётом — место для плашки комбо
	if mode == "classic":
		score_l = _stat("Счёт", str(score))
		best_l = _stat("Рекорд", str(Save.best))
		if best_at_start > 0:
			# Полоска «до рекорда»: заполняется по мере приближения к лучшему счёту
			rec_bar = ProgressBar.new()
			rec_bar.show_percentage = false
			rec_bar.max_value = 1.0
			rec_bar.value = minf(1.0, score / float(best_at_start))
			rec_bar.custom_minimum_size = Vector2(150, 10)
			rec_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rec_bar.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.16), 5))
			rec_bar.add_theme_stylebox_override("fill", UI.box(BB.C_GOLD, 5))
			best_l.get_parent().add_child(rec_bar)
	elif mode == "daily":
		score_l = _stat("Вызов дня", str(score))
		best_l = _stat("Лучший сегодня", str(Save.daily_best(daily_day)))
	elif mode == "duel" or mode == "online":
		score_l = _stat("Ты", str(score))
		timer_l = _stat("Время", "3:00")
		opp_score_l = _stat("Соперник" if mode == "online" else "Бот 🤖", "0")
	else:
		hud.add_theme_constant_override("separation", 22)
		moves_l = _stat("Ходы", "0/%d" % level_par)
		var row := UI.hrow(hud, 10)
		for k in goals.size():
			var g: Dictionary = goals[k]
			var pill := PanelContainer.new()
			pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pill)
			var h := UI.hrow(pill, 10)
			var f := UI.label(g.f, 40)
			h.add_child(f)
			var n := UI.label("", 34, Color.WHITE, UI.F_BLACK)
			h.add_child(n)
			goal_nodes.append({"pill": pill, "f": f, "n": n})
			_paint_goal(k)


func _paint_goal(k: int) -> void:
	var g: Dictionary = goals[k]
	var gn: Dictionary = goal_nodes[k]
	var ok: bool = g.left == 0
	gn.pill.add_theme_stylebox_override("panel", UI.box(Color(0.31, 0.84, 0.48, 0.35) if ok else Color(0, 0, 0, 0.25), 999, Vector4(12, 4, 20, 4)))
	gn.n.text = str(g.left) + (" ✓" if ok else "")


func _pulse(l: Label) -> void:
	l.pivot_offset = l.size * 0.5
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.25, 0.17)
	tw.parallel().tween_property(l, "modulate", BB.C_YELLOW, 0.17)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18)
	tw.parallel().tween_property(l, "modulate", Color.WHITE, 0.18)


## Счёт плавно «докручивается» до нового значения
func update_score() -> void:
	if mode == "arcade" or score_l == null:
		return
	if mode == "classic":
		if score > Save.best:
			Save.best = score
		best_l.text = str(Save.best)
	elif mode == "daily":
		if score > Save.daily_best(daily_day):
			Save.set_daily_best(daily_day, score)
		best_l.text = str(Save.daily_best(daily_day))
	var from := shown_score
	var to := score
	if _score_tw:
		_score_tw.kill()
	_score_tw = create_tween()
	var step := func(k: float) -> void:
		shown_score = roundi(from + (to - from) * (1.0 - pow(1.0 - k, 3)))
		if score_l:
			score_l.text = str(shown_score)
		if is_instance_valid(rec_bar):
			rec_bar.value = minf(1.0, shown_score / float(maxi(1, best_at_start)))
	_score_tw.tween_method(step, 0.0, 1.0, 0.45)
	if to - from >= 10:
		_pulse(score_l)
	if mode == "classic" and not record_shown and best_at_start > 0 and score > best_at_start:
		record_shown = true
		later(0.7, func():
			Audio.sfx("record")
			float_text(tr("Новый рекорд!"), "🏆", 3, true))


# ---------- Раскладка ----------
func _layout() -> void:
	if fx == null:
		return
	var W := size.x
	var H := size.y
	var dueling := mode == "duel" or mode == "online"
	var cell := minf(74.0, minf((W - 56.0) / 8.0 - 6.0, (H - ((567.0 + (70.0 if mode == "online" else 0.0)) if dueling else 342.0 + _combo_room())) / 11.4))
	cell = floorf(cell)
	board_view.set_metrics(cell, 5, 14)
	tray.custom_minimum_size = Vector2(cell * 8 + 54, cell * 3.4)
	tray.mini = floorf(cell * 0.5)
	tray.gap = 4
	bot_panel.visible = dueling
	col.add_theme_constant_override("separation", 12 if dueling else 18)
	col.position = Vector2(0, 92 if not dueling else 86)
	col.size.x = W
	fx.ghost_cell = cell
	fx.ghost_gap = 5
	corner_r.reset_size()
	corner_r.position = Vector2(W - corner_r.size.x - 22, 22)
	emoji_row.visible = mode == "online"
	emoji_row.reset_size()
	emoji_row.position = Vector2((W - emoji_row.size.x) * 0.5, H - emoji_row.size.y - 36)


# ---------- Начало игры ----------
## resume — продолжить незаконченную партию «Классики», если она сохранена
func start_game(m: String, n := 1, resume := false) -> void:
	stop_duel()
	_tok += 1
	mode = m
	level = n
	hide_overlays()
	btn_restart.visible = mode != "online"
	bot_head.text = "🤖 Бот"
	board = []
	board.resize(N * N)
	score = 0
	combo = 0
	scoring = Scoring.new()
	finished = false
	shown_score = 0
	best_at_start = Save.best
	record_shown = false
	gen = {"since": 0}
	goals = []
	drag = {}
	fx.ghost = null
	board_view.reset_fx()
	moves = 0
	moves_l = null
	revive_used = false
	_t_start = now()
	main.set_bg([])
	var resumed := false
	if mode == "classic":
		if resume:
			resumed = _load_run(Save.run)
		if not resumed:
			Save.clear_run()
	if mode == "arcade":
		var def := BB.level_def(level)
		goals = def.goals
		level_par = def.par
		seed_stones(def.stones, def.seed)
		var wd := BB.world_def(def.world)
		main.set_bg([wd[2], wd[3]])
	if mode == "daily":
		daily_day = BB.today()
		seed_daily()
	if not resumed:
		refill()
	main.show_screen("game")
	apply_skin(Save.skin, false)
	_refresh_mute()
	_layout()
	render_hud()
	render_board()
	render_tray(true)
	_update_combo.call_deferred()
	if resumed:
		later(0.35, func(): float_text(tr("Продолжаем!"), tr("твоя партия сохранена"), 2, true))
	if mode == "duel":
		start_duel()
	if mode == "arcade":
		var wd := BB.world_def(BB.world_of(level))
		later(0.35, func(): float_text(tr("Уровень %d") % level, "%s %s" % [wd[1], tr(wd[0])], 2, true))
	if mode == "arcade":
		main.hint_once("arcade", "🍓 Фрукты спрятаны в блоках.\nОчищай линии с ними, чтобы выполнить задание сверху!")
	if mode == "duel":
		main.hint_once("duel", "⏱ У вас 3 минуты!\nНабери больше очков, чем бот 🤖")
	if mode == "daily":
		main.hint_once("daily", "📅 Сегодня у всех одинаковые фигуры.\nНабери больше всех — и попади в таблицу дня!")


func apply_skin(i: int, remember := true) -> void:
	skin_idx = i
	board_view.skin = i
	tray.skin = i
	fx.ghost_skin = i
	if remember:
		Save.skin = i
		Save.add_skin(BB.SKINS[i][0])


func leave_game() -> void:
	combo_pill.set_state(0, 0)
	main.set_bg([])
	stop_duel()
	_tok += 1
	finished = true
	drag = {}
	fx.ghost = null


func _on_back() -> void:
	leave_game()
	if mode == "online":
		Net.send({"t": "leave"})
		main.show_screen("menu")
	elif mode == "arcade":
		main.open_levels()
	else:
		main.show_screen("menu")


func _toggle_mute() -> void:
	var on := not (Save.sound or Save.music)
	Audio.set_sound(on)
	Audio.set_music(on)
	_refresh_mute()


func _refresh_mute() -> void:
	btn_mute.text = "🔊" if (Save.sound or Save.music) else "🔇"


# ---------- Перетаскивание ----------
func _start_drag(i: int, gpos: Vector2) -> void:
	if finished or pieces[i] == null:
		return
	Audio.sfx("pick")
	Audio.buzz(8)
	var p: Dictionary = pieces[i]
	drag = {"i": i, "p": p, "pos": null, "lift": 126.0 if DisplayServer.is_touchscreen_available() else 0.0}
	fx.ghost = p
	fx.ghost_scale = 1.0
	tray.hidden_slot = i
	_move_drag(gpos)


func _input(ev: InputEvent) -> void:
	if drag.is_empty():
		return
	if ev is InputEventMouseMotion:
		_move_drag(ev.position)
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_end_drag()


func _move_drag(gpos: Vector2) -> void:
	if drag.is_empty():
		return
	var gs := fx.ghost_size()
	var tl := Vector2(gpos.x - gs.x / 2.0, gpos.y - gs.y / 2.0 - drag.lift)
	fx.ghost_pos = tl
	var rc := board_view.cell_at_global(tl)
	drag.pos = rc if BBAI.can_place(bits(board), drag.p, rc.x, rc.y) else null
	_show_preview()


func _show_preview() -> void:
	board_view.preview.clear()
	board_view.willclear.clear()
	if drag.is_empty() or drag.pos == null:
		return
	var p: Dictionary = drag.p
	var rc: Vector2i = drag.pos
	var b := bits(board)
	for k in p.cells.size():
		var v: Vector2i = p.cells[k]
		var idx := (rc.x + v.x) * N + rc.y + v.y
		board_view.preview[idx] = {"c": p.color, "f": p.fruits[k]}
		b |= 1 << idx
	for idx in mask_indices(BBAI.full_lines(b)[0]):
		board_view.willclear[idx] = p.color


func _end_drag() -> void:
	if drag.is_empty():
		return
	var d := drag
	drag = {}
	if d.pos != null and not finished:
		fx.ghost = null
		place(d.i, d.p, d.pos.x, d.pos.y)
		return
	# Нельзя поставить — фигура уезжает обратно в слот
	Audio.sfx("bad")
	_show_preview()
	var target := tray.piece_origin_global(d.i)
	var tw := fx.create_tween().set_parallel(true)
	tw.tween_property(fx, "ghost_pos", target, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_property(fx, "ghost_scale", (tray.mini + tray.gap) / (board_view.cell + board_view.gap), 0.2)
	tw.chain().tween_callback(func():
		if drag.is_empty():
			fx.ghost = null
			if tray.hidden_slot == d.i:
				tray.hidden_slot = -1)


# ---------- Ход ----------
func place(i: int, p: Dictionary, r: int, c: int) -> void:
	tray.hidden_slot = -1
	var placed: Array[int] = []
	for k in p.cells.size():
		var v: Vector2i = p.cells[k]
		var idx := (r + v.x) * N + c + v.y
		board[idx] = {"c": p.color, "f": p.fruits[k]}
		placed.append(idx)
	var fl := BBAI.full_lines(bits(board))
	var cleared := mask_indices(fl[0])
	var n: int = fl[1]
	var old := {}
	for idx in cleared:
		old[idx] = board[idx]
		board[idx] = null
	var perfect := n > 0 and bits(board) == 0
	var res := scoring.add(p.cells.size(), n, perfect and mode != "arcade")
	var gained: int = res.gained
	combo = res.combo
	_update_combo()

	moves += 1
	if moves_l:
		moves_l.text = "%d/%d" % [moves, level_par]
		moves_l.add_theme_color_override("font_color", Color.WHITE if moves <= level_par else Color(1, 1, 1, 0.6))

	Missions.add_xp(Missions.XP_PIECE + n * Missions.XP_LINE)

	# Задания дня
	Missions.add("pieces")
	if n > 0:
		Missions.add("lines", n)
		Missions.reach("combo", combo)
		if n >= 3:
			Missions.add("triple")
		if perfect:
			Missions.add("perfect")

	Audio.sfx("place")
	if n > 0:
		Audio.clear(n, combo)
		Audio.buzz([30, 40, 80] if n >= 3 else 25)
		if n >= 3:
			Audio.sfx("mega")
		var bonus: int = res.bonus - (Scoring.PERFECT if perfect and mode != "arcade" else 0)
		var praise := tr("Невероятно!") if n >= 4 else (tr("Отлично!") if n == 3 else (tr("Хорошо!") if n == 2 else ""))
		var sub: Array[String] = []
		if mode != "arcade" and praise != "":
			sub.append(praise)
		if combo > 1:
			sub.append(tr("Комбо ×%d") % combo)
		var main_t := ""
		if mode != "arcade":
			main_t = "+%d" % bonus
		elif praise != "":
			main_t = praise
		elif not sub.is_empty():
			main_t = sub.pop_front()
		if main_t != "":
			float_text(main_t, " · ".join(sub), n, mode == "arcade")
		if perfect:
			later(0.5, func():
				Audio.sfx("perfect")
				float_text(tr("Чистое поле!"), "+%d" % Scoring.PERFECT if mode != "arcade" else "✨", 4, true))
		if n >= 2 or perfect:
			board_view.shake((2 + n * 2) * 1.8)
		# 3 и больше линий за один ход — новый стиль блоков
		if n >= 3:
			gen.since = 0
			var nxt := (skin_idx + 1) % BB.SKINS.size()   # стили идут по порядку
			later(0.65, func():
				apply_skin(nxt)
				board_view.flash()
				Audio.sfx("skin")
				float_text(tr("Новый стиль!"), "%s · %d/%d" % [tr(BB.SKINS[nxt][1]), Save.got().size(), BB.SKINS.size()], 3, true))
	else:
		Audio.buzz(10)
	score += gained
	if mode != "arcade":
		Missions.reach("score", score)

	# Приземление фигуры
	render_board()
	board_view.preview.clear()
	board_view.willclear.clear()
	for idx in placed:
		if not old.has(idx):
			board_view.anim_land(idx)
	# Очки за саму фигуру: «+10» над каждой её клеткой, по очереди
	if mode != "arcade":
		var cs := floori(board_view.cell * 0.42)
		for k in placed.size():
			fx.pop(board_view.cell_center_global(placed[k]), "+%d" % Scoring.PER_CELL, k * 0.05, cs)

	# Очистка волной от места установки + частицы + сбор фруктов
	var cr: float = r + (p.h - 1) / 2.0
	var cc: float = c + (p.w - 1) / 2.0
	var max_delay := 0.0
	for idx in cleared:
		var delay := roundf(Vector2(idx / N - cr, idx % N - cc).length() * 40.0) / 1000.0
		max_delay = maxf(max_delay, delay)
		board_view.anim_clear(idx, old[idx], delay)
		fx.burst(board_view.cell_center_global(idx), old[idx].c, 5, delay)
		var f: String = old[idx].f
		if mode == "arcade" and f != "":
			for k in goals.size():
				if goals[k].f == f and goals[k].left > 0:
					goals[k].left -= 1
					Missions.add("fruit")
					var from := board_view.cell_center_global(idx)
					later(delay, func(): _fly_fruit(from, f, k))
					break

	pieces[i] = null
	update_score()
	var cl := []
	for idx in cleared:
		cl.append([idx, BB.color_hex(old[idx].c)])
	var ev := {"placed": placed, "cleared": cl, "gained": gained if n > 0 else 0, "n": n}

	if mode == "arcade" and goals.all(func(g): return g.left == 0):
		finished = true
		_track_game(true)
		Missions.add("arcade")
		Missions.add_xp(Missions.XP_WIN)
		if Save.unlocked <= level:
			Save.unlocked = level + 1
		var st := BB.level_stars(moves, level_par)
		Save.set_level_stars(level, st)
		later(1.1 + max_delay, func():
			var stars := "[font_size=96][color=#ffd84d]%s[/color][color=#ffffff33]%s[/color][/font_size]" % ["★".repeat(st), "★".repeat(3 - st)]
			var hint := tr("Ходов: %d") % moves
			if st < 3:
				hint += "  ·  " + tr("на ★★★ — не больше %d") % level_par
			_set_text(ov_win, stars + "\n" + tr("Уровень %d — все фрукты собраны") % level + "\n[font_size=28]" + hint + "[/font_size]")
			ov_win.right.visible = true
			_show_overlay(ov_win)
			Audio.sfx("win")
			Audio.buzz([40, 60, 40, 60, 120]))
		return

	# Новая тройка подбирается в фоне — без подтормаживания на телефоне
	if pieces.all(func(x): return x == null) and mode == "daily":
		refill()
		Audio.sfx("refill")
		render_tray(true)
		_after_move(max_delay, ev)
	elif pieces.all(func(x): return x == null):
		refill_async(func(): _after_move(max_delay, ev))
	else:
		render_tray(false)
		_after_move(max_delay, ev)


func _after_move(max_delay: float, ev: Dictionary) -> void:
	# Онлайн: отправляем сопернику своё поле после каждого хода
	send_state(ev)
	_save_run()
	var b := bits(board)
	if not pieces.any(func(x): return x != null and BBAI.fits_anywhere(b, x)):
		# В дуэли не проигрываем — поле очищается, время идёт дальше
		if mode == "duel" or mode == "online":
			later(max_delay + 0.5, func(): stuck_reset(false))
			return
		finished = true
		_track_game(false)
		if mode == "classic":
			Save.clear_run()
		later(max_delay + 0.4, func():
			board_view.anim_dead()
			tray.nofit = [true, true, true])
		if mode == "daily":
			Save.daily_played(daily_day)
			Missions.add("daily")
		later(max_delay + 1.4, func():
			if mode == "daily":
				_set_text(ov_lose, (tr("Счёт: [b]%d[/b]   ·   лучший сегодня: [b]%d[/b]") % [score, Save.daily_best(daily_day)]) + "\n[font_size=28]" + tr("🔥 Серия: %d дн.") % Save.daily_streak + "[/font_size]")
				_daily_table(score)
			elif mode == "classic":
				_set_text(ov_lose, tr("Счёт: [b]%d[/b]") % score)
			else:
				var parts := []
				for g in goals:
					if g.left > 0:
						parts.append("%s %d" % [g.f, g.left])
				_set_text(ov_lose, tr("Осталось собрать: ") + "  ".join(parts))
			ov_lose.revive.visible = mode == "classic" and not revive_used
			_show_overlay(ov_lose)
			Audio.sfx("lose")
			Audio.buzz(200))


## Отправить результат дня и показать таблицу под счётом
func _daily_table(sc: int) -> void:
	var tok := _tok
	daily_rank = []
	_append_text(ov_lose, "\n[font_size=24][color=#ffffff88]" + tr("Загружаем таблицу дня…") + "[/color][/font_size]")
	var nm: String = Save.player_name if Save.player_name != "" else tr("Игрок")
	var r: Dictionary = await Net.request(Save.server, {"t": "daily", "id": Save.player_id, "name": nm, "day": daily_day, "score": sc}, "dailyTop", 5.0)
	if tok != _tok or not ov_lose.root.visible:
		return
	var txt: String = ov_lose.text.text
	ov_lose.text.text = txt.substr(0, txt.find("\n[font_size=24][color=#ffffff88]")) + "[/center]"
	if r.is_empty():
		# Нет сети: запоминаем лучший результат дня и отправим его позже
		var pend := Save.daily_pending
		if pend.get("day", "") != daily_day or int(pend.get("score", 0)) < sc:
			Save.daily_pending = {"day": daily_day, "score": sc}
		_append_text(ov_lose, "\n[font_size=24][color=#ffffff99]" + tr("Нет интернета — результат сохранён.\nОн попадёт в таблицу дня, когда появится сеть") + "[/color][/font_size]")
		return
	if Save.daily_pending.get("day", "") == daily_day:
		Save.daily_pending = {}
	daily_rank = [int(r.get("rank", 0)), int(r.get("total", 0))]
	var lines := "\n[font_size=30][color=#ffd84d]" + tr("Место %d из %d") % daily_rank + "[/color][/font_size]"
	var top: Array = r.get("top", []) if r.get("top") is Array else []
	for k in mini(top.size(), 5):
		var e = top[k]
		if not (e is Dictionary):
			continue
		var row := "%d. %s — %d" % [k + 1, _esc(str(e.get("name", "?"))), int(e.get("score", 0))]
		lines += "\n[font_size=26]" + ("[color=#ffd84d]%s[/color]" % row if e.get("you", false) else row) + "[/font_size]"
	_append_text(ov_lose, lines)


func _fly_fruit(from: Vector2, f: String, k: int) -> void:
	if k >= goal_nodes.size():
		return
	var gn: Dictionary = goal_nodes[k]
	var target: Label = gn.f
	var to := target.get_global_rect().get_center()
	fx.fly(f, from, to, int(board_view.cell * 0.6), func():
		if not is_instance_valid(target) or not target.is_inside_tree():
			return   # уровень уже перезапущен
		_paint_goal(k)
		var pill: Control = gn.pill
		pill.pivot_offset = pill.size * 0.5
		var tw := pill.create_tween()
		tw.tween_property(pill, "scale", Vector2.ONE * 1.2, 0.08)
		tw.tween_property(pill, "scale", Vector2.ONE, 0.12)
		Audio.sfx("fruit"))


# ---------- Против бота ----------
func refill_bot() -> void:
	var s := smart_set(bot.board, bot.gen)
	bot.pieces = s if not s.is_empty() else [new_piece(), new_piece(), new_piece()]


## Тройка для бота — в фоне, пока он «думает»
func refill_bot_async(after := Callable()) -> void:
	bot.refilling = true
	var b := bits(bot.board)
	var since: int = bot.gen.since
	var tok := _bot_tok
	var bt := bot
	_bg(func():
		var g := {"since": since}
		var ids := BBAI.smart_set(b, g)
		_bot_refill_done.call_deferred(ids, g.since, tok, bt, after))


func _bot_refill_done(ids: Array, since: int, tok: int, bt: Dictionary, after: Callable) -> void:
	if bt != bot or bot.is_empty():
		return
	bot.refilling = false
	bot.gen.since = since
	bot.pieces = ids.map(func(s): return new_piece(s)) if not ids.is_empty() else [new_piece(), new_piece(), new_piece()]
	render_bot()
	if after.is_valid():
		after.call()


func render_bot(hi := -1) -> void:
	bot_board.cells = bot.board
	bot_tray.set_pieces(bot.pieces, [false, false, false])
	if hi >= 0:
		bot_tray.set_thinking(hi)
	bot_score_l.text = str(bot.score)
	if opp_score_l:
		opp_score_l.text = str(bot.score)


func bot_float(text: String) -> void:
	fx.float_text(bot_board.get_global_rect().get_center(), text, "", -3, false)


func schedule_bot() -> void:
	if duel.is_empty():
		return
	bot_status.text = tr("думает…")
	_bot_later(randf_range(BOT_THINK.x, BOT_THINK.y), bot_turn)


func bot_turn() -> void:
	if duel.is_empty() or finished:
		return
	if bot.get("refilling", false):
		_bot_later(0.3, bot_turn)
		return
	var b := bits(bot.board)
	var opts := []
	for i in bot.pieces.size():
		var p = bot.pieces[i]
		if p == null:
			continue
		var all := []
		BBAI.best_move(b, p, all)
		for m in all:
			m.i = i
			m.p = p
			m.v = m.lines * 1000 + m.score
			opts.append(m)
	if opts.is_empty():
		stuck_reset(true)
		_bot_later(0.9, schedule_bot)
		return
	opts.sort_custom(func(x, y): return x.v > y.v)
	var move: Dictionary = opts[randi() % opts.size()] if randf() < BOT_MISTAKE else opts[0]
	# Показываем, какую фигуру бот берёт, и через мгновение ставим
	render_bot(move.i)
	bot_status.text = tr("ставит…")
	_bot_later(0.45, func():
		if finished:
			return
		apply_bot_move(move)
		schedule_bot())


func apply_bot_move(mv: Dictionary) -> void:
	var p: Dictionary = mv.p
	var placed := []
	for v in p.cells:
		var idx: int = (mv.r + v.x) * N + mv.c + v.y
		bot.board[idx] = {"c": p.color, "f": ""}
		placed.append(idx)
	var fl := BBAI.full_lines(bits(bot.board))
	var cleared := mask_indices(fl[0])
	var n: int = fl[1]
	var old := {}
	for idx in cleared:
		old[idx] = bot.board[idx]
		bot.board[idx] = null
	var gained: int = bot.sc.add(p.cells.size(), n, n > 0 and bits(bot.board) == 0).gained
	if n > 0:
		if n >= 3:
			bot.gen.since = 0
			# У бота свой стиль — меняется только от его собственных 3+ линий
			bot.skin = (bot.skin + 1) % BB.SKINS.size()
			later(0.5, func():
				if not bot.is_empty():
					_set_bot_skin(bot.skin)
					bot_float(tr("новый стиль")))
	bot.score += gained

	bot.pieces[mv.i] = null
	if bot.pieces.all(func(x): return x == null):
		refill_bot_async(_bot_check_stuck)
	render_bot()
	for idx in placed:
		if not old.has(idx):
			bot_board.anim_land(idx)
	for idx in cleared:
		bot_board.anim_clear(idx, old[idx], 0.0)
	if n > 0:
		bot_float("+%d" % gained)
		Audio.sfx("botClear")
	if not bot.get("refilling", false):
		_bot_check_stuck()


func _bot_check_stuck() -> void:
	var b := bits(bot.board)
	if not bot.pieces.any(func(x): return x != null and BBAI.fits_anywhere(b, x)):
		_bot_tok += 1
		later(0.6, func(): stuck_reset(true))
		_bot_later(1.5, schedule_bot)


func _set_bot_skin(i: int) -> void:
	bot_board.skin = i
	bot_tray.skin = i


## Нет ходов в дуэли — поле очищается, игра продолжается
func stuck_reset(is_bot: bool) -> void:
	if duel.is_empty() or finished:
		return
	var bv := bot_board if is_bot else board_view
	var b: Array = bot.board if is_bot else board
	for i in N * N:
		if b[i] != null:
			bv.anim_clear(i, b[i], (i / N) * 0.04)
	if is_bot:
		bot_float(tr("новое поле"))
	else:
		float_text(tr("Нет ходов"), tr("новое поле"), 2, true)
		Audio.sfx("stuck")
		Audio.buzz(120)
	# Клетки уже анимируются как исчезающие — убираем их с поля сразу
	var empty := []
	empty.resize(N * N)
	if is_bot:
		bot.board = empty
		bot_board.cells = empty
	else:
		board = empty
		render_board()
	later(0.7, func():
		if duel.is_empty():
			return
		if is_bot:
			bot.sc = Scoring.new()
			refill_bot_async()
		else:
			combo = 0
			scoring.combo = 0
			_update_combo()
			render_board()
			refill_async(func(): send_state({"reset": true})))


func update_timer() -> void:
	var t: int = maxi(0, duel.time_left)
	timer_l.text = "%d:%02d" % [t / 60, t % 60]
	timer_l.add_theme_color_override("font_color", BB.C_GOLD if t <= 10 else Color.WHITE)
	if t <= 10 and t > 0:
		Audio.sfx("tick")


func _new_bot(with_gen: bool) -> void:
	var empty := []
	empty.resize(N * N)
	bot = {"board": empty, "pieces": [null, null, null], "score": 0, "sc": Scoring.new(), "gen": {"since": 0}, "skin": 0}
	if not with_gen:
		bot.erase("gen")
	_set_bot_skin(0)


func start_duel() -> void:
	_new_bot(true)
	refill_bot()
	render_bot()
	duel = {"time_left": DUEL_TIME, "next_tick": now() + 1.0}
	update_timer()
	schedule_bot()


func stop_duel() -> void:
	duel = {}
	_bot_tok += 1


func _process(_dt: float) -> void:
	if duel.is_empty():
		return
	if duel.get("online", false):
		if not duel.has("end_at"):
			return
		var t := maxi(0, ceili((duel.end_at - now())))
		if t != duel.time_left:
			duel.time_left = t
			update_timer()
		if t <= 0 and not finished:
			finished = true
			bot_status.text = tr("подсчёт…")
			# Итог объявляет сервер; если он не ответит — считаем по своим данным
			var tok := _bot_tok
			later(4.5, func():
				if tok == _bot_tok:
					end_online(score, bot.get("score", 0), ""))
	elif now() >= duel.next_tick:
		duel.next_tick += 1.0
		duel.time_left -= 1
		update_timer()
		if duel.time_left <= 0:
			end_duel()


func end_duel() -> void:
	stop_duel()
	ov_duel.right.disabled = false
	ov_duel.right.visible = true
	finished = true
	_track_game(score > int(bot.get("score", 0)))
	bot_status.text = tr("время вышло")
	var you := score
	var them: int = bot.score
	ov_duel.title.text = tr("Ты победил! 🏆") if you > them else (tr("Бот победил 🤖") if you < them else tr("Ничья 🤝"))
	if you > them:
		Missions.add("win")
		Missions.add_xp(Missions.XP_WIN)
	_set_text(ov_duel, tr("Ты [b]%d[/b] : [b]%d[/b] Бот") % [you, them])
	later(0.5, func():
		_show_overlay(ov_duel)
		_result_sound(you, them, false))


func _result_sound(you: int, them: int, forced_win: bool) -> void:
	if forced_win or you > them:
		Audio.sfx("win")
		Audio.buzz([40, 60, 40, 60, 120])
	elif you < them:
		Audio.sfx("lose")
		Audio.buzz(200)
	else:
		Audio.sfx("record")


func _on_rematch() -> void:
	if mode != "online":
		start_game("duel")
		return
	Net.send({"t": "rematch"})
	ov_duel.right.disabled = true
	_append_text(ov_duel, "\n[font_size=26]" + tr("Ждём соперника…") + "[/font_size]")


# ---------- Онлайн-бой ----------
## Реакция сопернику: не чаще раза в секунду
func send_emoji(k: int) -> void:
	if mode != "online" or now() - _emoji_t < 1.0:
		return
	_emoji_t = now()
	Net.send({"t": "emoji", "e": k})
	fx.pop(emoji_row.get_child(k).get_global_rect().get_center() - Vector2(0, 60), EMOJI[k], 0.0, 80)
	Audio.sfx("click")


func send_state(ev := {}) -> void:
	if mode != "online" or duel.is_empty():
		return
	Net.send(state_msg(ev))


## Сообщение о своём поле — в том же формате, что у веб-версии
func state_msg(ev := {}) -> Dictionary:
	var m := {"t": "state", "score": score, "skin": skin_idx}
	var bd := []
	for c in board:
		bd.append(BB.color_hex(c.c) if c != null else null)
	m.board = bd
	var tr := []
	for p in pieces:
		if p == null:
			tr.append(null)
			continue
		var cells := []
		for v in p.cells:
			cells.append([v.x, v.y])
		tr.append({"w": p.w, "h": p.h, "color": BB.color_hex(p.color), "cells": cells})
	m.tray = tr
	m.merge(ev)
	return m


## Ход соперника → на мини-поле
func apply_opp(m: Dictionary) -> void:
	if mode != "online" or bot.is_empty() or not (m.get("board") is Array) or m.board.size() != N * N:
		return
	bot.board = m.board.map(func(c): return {"c": Color(c), "f": ""} if BB.is_color_str(c) else null)
	var tr: Array = m.get("tray", []) if m.get("tray") is Array else []
	var ps := []
	for k in 3:
		var p = tr[k] if k < tr.size() else null
		if p is Dictionary and BB.is_color_str(p.get("color")) and p.get("cells") is Array:
			var cells: Array[Vector2i] = []
			for v in p.cells.slice(0, 25):
				if v is Array and v.size() >= 2:
					cells.append(Vector2i(clampi(int(v[0]), 0, 4), clampi(int(v[1]), 0, 4)))
			ps.append({"w": mini(5, int(p.get("w", 1))), "h": mini(5, int(p.get("h", 1))), "color": Color(p.color),
				"cells": cells, "base": BBAI.cells_mask(cells)})
		else:
			ps.append(null)
	bot.pieces = ps
	bot.score = maxi(0, int(m.get("score", 0)))
	var sk = m.get("skin")
	if (sk is float or sk is int) and int(sk) >= 0 and int(sk) < BB.SKINS.size() and int(sk) != bot.skin:
		bot.skin = int(sk)
		_set_bot_skin(bot.skin)
	render_bot()
	var cl: Array = m.get("cleared", []) if m.get("cleared") is Array else []
	var cl_set := {}
	for x in cl:
		if x is Array and x.size() >= 2:
			cl_set[int(x[0])] = true
	for i in (m.get("placed", []) if m.get("placed") is Array else []):
		var ii := int(i)
		if not cl_set.has(ii) and ii >= 0 and ii < N * N:
			bot_board.anim_land(ii)
	for x in cl:
		if x is Array and x.size() >= 2 and BB.is_color_str(x[1]):
			var ii := int(x[0])
			if ii >= 0 and ii < N * N:
				bot_board.anim_clear(ii, {"c": Color(x[1]), "f": ""}, 0.0)
	var n := int(m.get("n", 0))
	if n > 0:
		bot_float("+%d" % int(m.get("gained", 0)))
		Audio.sfx("botClear")
	if m.get("reset", false):
		bot_float(tr("новое поле"))
	bot_status.text = tr("играет")


func start_online_match(m: Dictionary) -> void:
	opp_name = str(m.get("opponent", tr("Соперник"))).substr(0, 16)
	ranked = bool(m.get("ranked", false))
	start_game("online")
	# Быстрый бой может идти без рейтинга — сервер сообщает почему
	var why := str(m.get("why", ""))
	if why == "sameNet":
		later(4.0, func(): main.toast(tr("Вы с соперником в одной сети — этот бой без рейтинга")))
	elif why == "pairLimit":
		later(4.0, func(): main.toast(tr("С этим соперником рейтинг сегодня уже разыгран — бой без рейтинга")))
	_new_bot(false)
	render_bot()
	bot_head.text = ("⚡ " if ranked else "🧑 ") + opp_name
	bot_status.text = tr("готовится…")
	ov_duel.right.disabled = false
	ov_duel.right.visible = true
	var dur: float = float(m.get("duration", 180000)) / 1000.0
	duel = {"online": true, "time_left": roundi(dur)}
	update_timer()
	finished = true   # пока идёт отсчёт, ходить нельзя
	var token := _bot_tok
	var go := func() -> void:
		if token != _bot_tok or duel.is_empty():
			return
		finished = false
		duel.end_at = now() + dur
		bot_status.text = tr("играет")
		send_state()
	var alive := func() -> bool: return token == _bot_tok
	main.countdown(roundi(float(m.get("countdown", 3000)) / 1000.0), go, alive)


func end_online(you: int, them: int, note: String, rm := {}) -> void:
	if mode != "online":
		return
	stop_duel()
	finished = true
	_track_game(note != "" or you > them)
	main.clear_countdown()
	bot_status.text = tr("бой окончен")
	last_result = [you, them]
	if note != "":
		ov_duel.title.text = note
	else:
		ov_duel.title.text = tr("Ты победил! 🏆") if you > them else (tr("%s победил") % opp_name if you < them else tr("Ничья 🤝"))
	_set_text(ov_duel, tr("Ты [b]%d[/b] : [b]%d[/b] %s") % [you, them, _esc(opp_name)])
	_rating_result(rm)
	if note != "" or you > them:
		Missions.add("win")
		Missions.add_xp(Missions.XP_WIN)
	ov_duel.right.disabled = note != ""
	ov_duel.right.visible = note == ""
	later(0.4, func():
		_show_overlay(ov_duel)
		_result_sound(you, them, note != ""))


## Новый рейтинг от сервера: запоминаем и показываем под счётом
func _rating_result(rm: Dictionary) -> void:
	if not rm.has("rating"):
		return
	var old_l := BB.league(Save.rating)
	var r := int(rm.rating)
	var d := int(rm.get("delta", 0))
	Save.rating = r
	Save.rated_games += 1
	var l := BB.league(r)
	var col := "#7dffa0" if d >= 0 else "#ff9db5"
	_append_text(ov_duel, "\n[font_size=28]%s  [color=%s]%s%d[/color][/font_size]" % [BB.league_text(r), col, "+" if d >= 0 else "", d])
	if l[0] > old_l[0]:
		_append_text(ov_duel, "\n[font_size=28][color=#ffd84d]" + tr("Новая лига: %s %s!") % [l[2], tr(l[1])] + "[/color][/font_size]")
	elif l[0] < old_l[0]:
		_append_text(ov_duel, "\n[font_size=24]" + tr("Лига: %s %s") % [l[2], tr(l[1])] + "[/font_size]")


func _esc(s: String) -> String:
	return s.replace("[", "(").replace("]", ")")


## Сообщения сервера, относящиеся к бою. Возвращает true, если обработано.
func on_net(m: Dictionary) -> bool:
	match str(m.get("t", "")):
		"start":
			hide_overlays()
			start_online_match(m)
			return true
		"opp":
			apply_opp(m)
			return true
		"emoji":
			var k := int(m.get("e", -1))
			if mode == "online" and k >= 0 and k < EMOJI.size():
				fx.pop(bot_panel.get_global_rect().get_center(), EMOJI[k], 0.0, 110)
				Audio.sfx("click")
			return true
		"oppRematch":
			if ov_duel.root.visible:
				_append_text(ov_duel, "\n[font_size=26]" + tr("%s хочет реванш!") % _esc(opp_name) + "[/font_size]")
			return true
		"end":
			end_online(int(m.get("you", 0)), int(m.get("them", 0)), "", m)
			return true
		"oppLeft":
			if mode == "online" and not duel.is_empty():
				end_online(score, bot.get("score", 0), tr("Соперник вышел — победа! 🏆"), m)
				return true
			if mode == "online" and ov_duel.root.visible:
				ov_duel.right.visible = false
				_append_text(ov_duel, "\n[font_size=26]" + tr("Соперник ушёл") + "[/font_size]")
				return true
		"closed":
			if mode == "online" and not duel.is_empty():
				stop_duel()
				finished = true
				ov_duel.title.text = tr("Связь потеряна 📡")
				_set_text(ov_duel, tr("Ты [b]%d[/b] : [b]%d[/b] %s") % [score, bot.get("score", 0), _esc(opp_name)])
				ov_duel.right.visible = false
				_show_overlay(ov_duel)
				return true
	return false


## Сыгранная партия — в обезличенную статистику (режим, счёт, ходы, длительность)
func _track_game(win: bool) -> void:
	main.track("game", {"m": mode, "s": score, "n": moves, "t": int(now() - _t_start), "w": win, "lv": level if mode == "arcade" else 0})


# ---------- Серия комбо на экране ----------
## Свободная полоса между счётом и полем в «Классике» и вызове дня
func _combo_room() -> float:
	return 36.0 if mode == "classic" or mode == "daily" else 0.0


func _update_combo() -> void:
	if mode == "arcade":
		combo_pill.set_state(0, 0)
		return
	combo_pill.position = board_view.global_position - global_position + Vector2(board_view.size.x * 0.5, -8 - _combo_room() * 0.6)
	combo_pill.set_state(scoring.combo, scoring.moves_left())


## Плашка над полем: «Комбо ×N» и три точки — сколько ходов осталось, чтобы продлить серию
class ComboPill extends Control:
	var combo := 0
	var left := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 5
		visible = false

	func set_state(c: int, l: int) -> void:
		var grew := c > combo
		var changed := c != combo or l != left
		combo = c
		left = l
		visible = c > 0
		if not changed:
			return
		queue_redraw()
		if grew:
			scale = Vector2.ONE * 1.35
			create_tween().tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		if combo <= 0:
			return
		var f: Font = UI.F_BLACK
		var fs := 26
		var txt := tr("Комбо ×%d") % combo
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w := tw + 3 * 22 + 46
		var r := Rect2(-w / 2, -22, w, 44)
		var hot := left <= 1   # последний ход, чтобы продлить серию
		Skins.rrect(self, r, Color(0.05, 0.06, 0.16, 0.92), 22)
		draw_string(f, Vector2(r.position.x + 18, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BB.C_GOLD)
		for k in 3:
			var c := Color(1, 1, 1, 0.22)
			if k < left:
				c = Color("ff6b5e") if hot else BB.C_GREEN
			draw_circle(Vector2(r.position.x + 18 + tw + 22 + k * 22, 0), 7, c)


# ---------- Продолжение партии «Классики» ----------
func _save_run() -> void:
	if mode != "classic" or finished:
		return
	var b := []
	for c in board:
		b.append(null if c == null else c.c.to_html())
	var ps := []
	for p in pieces:
		ps.append(null if p == null else [p.s, p.color.to_html()])
	Save.run = {"board": b, "pieces": ps, "score": score, "combo": scoring.combo, "miss": scoring.miss,
		"since": gen.since, "revive": revive_used, "best0": best_at_start, "rec": record_shown}


func _load_run(r: Dictionary) -> bool:
	var b: Array = r.get("board", [])
	var ps: Array = r.get("pieces", [])
	if b.size() != N * N or ps.size() != 3:
		return false
	var loaded := []
	for i in N * N:
		loaded.append(null if b[i] == null else {"c": Color.html(str(b[i])), "f": ""})
	var set := [null, null, null]
	for i in 3:
		if ps[i] != null and int(ps[i][0]) < BB.SHAPES.size():
			set[i] = new_piece(int(ps[i][0]))
			set[i].color = Color.html(str(ps[i][1]))
	var bb := bits(loaded)
	if not set.any(func(x): return x != null and BBAI.fits_anywhere(bb, x)):
		return false
	board = loaded
	pieces = set
	score = int(r.get("score", 0))
	shown_score = score
	scoring.score = score
	scoring.combo = int(r.get("combo", 0))
	scoring.miss = int(r.get("miss", 0))
	combo = scoring.combo
	gen.since = int(r.get("since", 0))
	revive_used = bool(r.get("revive", false))
	best_at_start = int(r.get("best0", Save.best))
	record_shown = bool(r.get("rec", false))
	return true


# ---------- Второй шанс ----------
## Раз за партию: убираем три самых заполненных ряда и три столбца, даём новые фигуры
func revive() -> void:
	if not finished or mode != "classic" or revive_used:
		return
	revive_used = true
	finished = false
	hide_overlays()
	board_view.reset_fx()
	var b := bits(board)
	var rows := []
	var cols := []
	for i in N:
		rows.append([BBAI.popcount(b & BBAI.ROW[i]), BBAI.ROW[i]])
		cols.append([BBAI.popcount(b & BBAI.COL[i]), BBAI.COL[i]])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	cols.sort_custom(func(x, y): return x[0] > y[0])
	var mask := 0
	for k in 3:
		mask |= int(rows[k][1]) | int(cols[k][1])
	for idx in mask_indices(mask & b):
		var delay := (idx / N) * 0.04
		board_view.anim_clear(idx, board[idx], delay)
		fx.burst(board_view.cell_center_global(idx), board[idx].c, 5, delay)
		board[idx] = null
	render_board()
	Audio.sfx("perfect")
	Audio.buzz([30, 40, 80])
	float_text(tr("Второй шанс!"), tr("поле расчищено"), 3, true)
	_update_combo()
	refill_async(_save_run)
