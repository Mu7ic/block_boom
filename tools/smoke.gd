extends Node
## Проверка «на дым»: проходит все режимы ходами ИИ и снимает скриншоты экранов.
## Запуск:  Godot --path . res://tools/smoke.tscn -- --test-save [--shots]
## Скриншоты — в user://shots/. Прогресс игрока не трогает (отдельный файл сохранения).

var main: Control
var shots := false
var errors := 0


func _ready() -> void:
	shots = "--shots" in OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(name: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % name)
	print("shot ", name)


func check(cond: bool, what: String) -> void:
	if not cond:
		errors += 1
		push_error("FAIL: " + what)
	else:
		print("ok   ", what)


## Один ход игрока: лучшая из доступных фигур через ИИ
func ai_move(g: GameScreen) -> bool:
	var b := GameScreen.bits(g.board)
	var best := {}
	for i in 3:
		var p = g.pieces[i]
		if p == null:
			continue
		var m := BBAI.best_move(b, p)
		if not m.is_empty() and (best.is_empty() or m.lines * 1000 + m.score > best.v):
			best = {"i": i, "m": m, "v": m.lines * 1000 + m.score}
	if best.is_empty():
		return false
	g.place(best.i, g.pieces[best.i], best.m.r, best.m.c)
	return true


## Ход ИИ; если новая тройка ещё подбирается в фоне — ждём её
func play_one(g: GameScreen) -> bool:
	for k in 120:
		if not g.pieces.all(func(x): return x == null):
			break
		await get_tree().process_frame
	return ai_move(g)


func _run() -> void:
	var g: GameScreen = main.game
	await wait(1.6)
	await shot("01_splash")
	main.show_screen("menu")
	await wait(1.2)
	await shot("02_menu")

	# Скорость ИИ-генерации на заполненном поле
	var t0 := Time.get_ticks_msec()
	var gen := {"since": 5}
	var b := 0
	for i in 40:
		if i % 3 != 0:
			b |= 1 << (i * 7 % 64)
	for k in 5:
		BBAI.smart_set(b, gen)
	print("smart_set avg ms: ", (Time.get_ticks_msec() - t0) / 5.0)

	# Классика: играем ИИ до конца или 120 ходов
	g.start_game("classic")
	await wait(0.6)
	await shot("03_classic_start")
	var moves := 0
	while not g.finished and moves < 120:
		if not await play_one(g):
			break
		moves += 1
		if moves == 6:
			await wait(0.1)
			await shot("04_classic_play")
		await get_tree().process_frame
	print("classic moves=", moves, " score=", g.score, " skin=", g.skin_idx)
	check(g.score > 0, "classic scored")
	check(Save.best == g.score or Save.best >= g.score, "best saved")

	# Перетаскивание: фигура над полем показывает подсветку
	g.start_game("classic")
	await wait(0.5)
	var tr := g.tray.get_global_rect()
	var over := g.board_view.get_global_rect().get_center()
	g._start_drag(0, tr.get_center())
	g._move_drag(over + Vector2(0, g.drag.lift))
	await wait(0.1)
	await shot("05_drag")
	# Настоящая мышь над окном могла сдвинуть фигуру — ставим её снова и проверяем в том же кадре
	g._move_drag(over + Vector2(0, g.drag.lift))
	check(not g.board_view.preview.is_empty(), "drag preview over board")
	g._end_drag()
	await wait(0.4)
	check(g.pieces.count(null) == 1, "drag placed a piece")

	# Все стили на одном поле
	for s in BB.SKINS.size():
		g.apply_skin(s, false)
		for i in 64:
			if g.board[i] == null and (i + s) % 3 != 0:
				g.board[i] = {"c": BB.COLORS[i % 8], "f": ""}
		g.render_board()
		await get_tree().process_frame
		if s % 4 == 0 or s == BB.SKINS.size() - 1:
			await shot("06_skin_%02d_%s" % [s, BB.SKINS[s][0]])

	# Аркада: уровень 12 — цели и камни из генератора, раскладка одинаковая при каждой попытке
	var def12 := BB.level_def(12)
	g.start_game("arcade", 12)
	await wait(0.5)
	check(g.goals.size() == def12.goals.size(), "arcade 12 goals=%d" % g.goals.size())
	var stones := g.board.filter(func(c): return c != null and c.c == BB.STONE).size()
	check(stones == def12.stones, "arcade 12 stones=%d" % stones)
	var layout := GameScreen.bits(g.board)
	g.start_game("arcade", 12)
	await wait(0.3)
	check(GameScreen.bits(g.board) == layout, "arcade: same stones on restart")
	# Уровни без конца: далёкие уровни тоже собираются и не выходят за пределы
	var far_ok := true
	for n in [1, 9, 10, 31, 99, 100, 1000, 54321]:
		var d := BB.level_def(n)
		var tot := 0
		for gl in d.goals:
			tot += gl.need
			far_ok = far_ok and gl.need >= 3 and gl.need <= 30
		far_ok = far_ok and d.stones <= 24 and d.par > 0 and not d.goals.is_empty()
		print("level ", n, ": world ", d.world, " boss ", d.boss, " goals ", d.goals.map(func(x): return "%s%d" % [x.f, x.need]), " stones ", d.stones, " par ", d.par)
	check(far_ok, "endless levels generate sanely")
	await shot("07_arcade")
	moves = 0
	while not g.finished and moves < 150:
		if not await play_one(g):
			break
		moves += 1
		await get_tree().process_frame
	var left := 0
	for gl in g.goals:
		left += gl.left
	print("arcade moves=", moves, " fruits left=", left, " unlocked=", Save.unlocked, " finished=", g.finished)
	await wait(2.0)
	await shot("08_arcade_end")

	# Против бота: бот должен сходить за ~6 с
	g.start_game("duel")
	await wait(0.6)
	for k in 5:
		ai_move(g)
		await wait(0.2)
	await wait(6.0)
	check(g.bot.score > 0, "bot made moves (score %d)" % g.bot.score)
	check(g.duel.time_left < 180, "duel timer runs")
	await shot("09_duel")
	g.duel.time_left = 1
	await wait(1.6)
	check(g.ov_duel.root.visible, "duel result shown")
	await shot("10_duel_end")

	# Онлайн-бой: сообщения сервера в формате веб-версии
	main._on_net({"t": "start", "countdown": 1000, "duration": 4000, "opponent": "Вася"})
	await wait(0.2)
	check(g.mode == "online" and g.finished, "online: countdown blocks moves")
	await wait(1.3)
	check(not g.finished, "online: match started after countdown")
	for k in 3:
		await play_one(g)
	# Своё состояние → JSON → как будто от соперника (проверка совместимости формата)
	var msg: Dictionary = JSON.parse_string(JSON.stringify(g.state_msg({"placed": [0, 1], "cleared": [[8, "#ff5d5d"]], "gained": 120, "n": 1})))
	msg.t = "opp"
	msg.score = 777
	main._on_net(msg)
	check(g.bot.score == 777 and g.opp_score_l.text == "777", "online: opponent score shown")
	check(GameScreen.bits(g.bot.board) == GameScreen.bits(g.board), "online: opponent board mirrored")
	check(g.bot.pieces.filter(func(p): return p != null).size() == g.pieces.filter(func(p): return p != null).size(), "online: opponent tray mirrored")
	# Сообщение из браузера (числа приходят как float, цвета строками)
	main._on_net({"t": "opp", "score": 900.0, "skin": 3.0, "board": range(64).map(func(i): return "#36c3ff" if i < 8 else null),
		"tray": [{"w": 2.0, "h": 1.0, "color": "#ff6fc8", "cells": [[0.0, 0.0], [0.0, 1.0]]}, null, null], "n": 0})
	check(g.bot.score == 900 and g.bot_board.skin == 3, "online: browser message parsed")
	await shot("15_online_match")
	await wait(3.0)
	main._on_net({"t": "end", "you": float(g.score), "them": 900.0})
	await wait(0.6)
	check(g.ov_duel.root.visible, "online: result shown")
	await shot("16_online_end")
	main._on_net({"t": "oppLeft"})
	check(not g.ov_duel.right.visible, "online: rematch hidden after opponent left")

	# Вызов дня: у всех одинаковое стартовое поле и фигуры
	g.start_game("daily")
	await wait(0.4)
	var filled := g.board.filter(func(c): return c != null).size()
	check(filled == 10, "daily: 10 start blocks (%d)" % filled)
	var sig := func() -> String:
		return str(GameScreen.bits(g.board)) + ":" + ",".join(g.pieces.map(func(p): return "%d/%s" % [p.s, p.color.to_html()]))
	var first: String = sig.call()
	g.start_game("daily")
	await wait(0.2)
	check(sig.call() == first, "daily: same board and pieces on restart")
	await shot("17_daily")
	moves = 0
	while not g.finished and moves < 200:
		if not await play_one(g):
			break
		moves += 1
		await get_tree().process_frame
	await wait(2.0)
	print("daily moves=", moves, " score=", g.score)
	check(g.ov_lose.root.visible, "daily: result shown")
	check(Save.daily_best(BB.today()) == g.score or Save.daily_best(BB.today()) > 0, "daily: best saved")
	check(Save.daily_streak == 1, "daily: streak 1 (%d)" % Save.daily_streak)
	await wait(5.5)   # ответ сервера или «нет связи»
	print("daily overlay: ", g.ov_lose.text.text.replace("\n", " | "))
	check(not g.ov_lose.text.text.contains("Загружаем"), "daily: table loaded or offline note")
	await shot("18_daily_end")

	# Задания дня и сундук
	var ml := Missions.list()
	check(ml.size() == 3, "missions: 3 today")
	print("missions: ", ml.map(func(m): return "%s %d/%d" % [m.id, m.prog, m.target]))
	Missions.keys = 3
	var before := Save.got().size() + Save.effects_got().size() + Save.themes_got().size()
	main.open_missions()
	await wait(0.3)
	main.open_chest()
	check(Save.got().size() + Save.effects_got().size() + Save.themes_got().size() == before + 1 and Missions.keys == 0, "missions: chest gives a reward")
	await wait(0.4)
	await shot("19_missions")

	# Эффекты очистки
	for e in BB.EFFECTS:
		Save.add_effect(e[0])
	main.open_collection()
	await wait(0.3)
	var c0 := main.get_global_rect().get_center()
	for k in BB.EFFECTS.size():
		main.fx.burst(c0 + Vector2((k - 2.5) * 110, 0), BB.COLORS[k], 6, 0.0, BB.EFFECTS[k][0])
	await wait(0.35)
	await shot("20_effects")
	Save.effect = "stars"
	main.show_screen("menu")
	await wait(0.6)
	await shot("21_menu_new")

	# Лобби: поиск соперника
	main.open_online()
	await wait(0.2)
	main.lobby_view("search")
	await wait(0.5)
	await shot("22_search")
	main.lobby_view("main")

	# Экраны
	main.open_collection()
	await wait(0.8)
	await shot("11_collection")
	main.open_levels()
	await wait(0.3)
	var nodes: Dictionary = main.level_map._nodes
	check(nodes.size() == 30 and nodes[13].text == "13", "level map: %d nodes, unlocked=%d" % [nodes.size(), Save.unlocked])
	check(Save.level_stars(12) > 0, "level 12 stars saved (%d)" % Save.level_stars(12))
	await shot("12_levels")
	main.open_online()
	await wait(0.3)
	await shot("13_online")
	main.show_screen("menu")
	main.open_tutorial()
	for k in 4:
		await wait(1.2)
		await shot("14_tutorial_%d" % k)
		main.tut_next.pressed.emit()
	main._close_tutorial()

	# Английский язык: подписи переводятся, тексты с числами тоже
	I18N.apply("en")
	main.show_screen("menu")
	await wait(0.6)
	check(tr("Вызов дня 📅") == "Daily Challenge 📅", "en: translation active")
	I18N.apply("ru")
	check(tr("Вызов дня 📅") == "Вызов дня 📅", "ru: stays russian")
	I18N.apply("en")
	check(main.mis_btn.text.begins_with("🎯 Missions"), "en: dynamic text translated (%s)" % main.mis_btn.text)
	await shot("23_en_menu")
	g.start_game("classic")
	await wait(0.4)
	for k in 4:
		await play_one(g)
	await wait(0.4)
	await shot("24_en_game")
	main.open_missions()
	await wait(0.3)
	check(main.renew_l.text.begins_with("New missions"), "en: missions screen")
	await shot("25_en_missions")
	main.open_online()
	await wait(0.3)
	await shot("26_en_online")
	I18N.apply("ru")

	# Фоны: выбор темы
	Save.add_theme("sunset")
	Save.bg_theme = "sunset"
	main.open_collection()
	await wait(0.4)
	var sc: ScrollContainer = main.screens["collection"].get_child(0)
	sc.scroll_vertical = 100000
	await wait(0.3)
	await shot("27_themes")
	Save.bg_theme = "night"
	main.queue_redraw()

	# Лучшие игроки (без сервера — сообщение о связи)
	main.open_top()
	await wait(13.0)   # подключение до 6 с + ответ до 5 с
	check(main.top_me.text != "Загружаем…", "top: loaded or offline note (%s)" % main.top_me.text)
	await shot("28_top")

	print("DONE errors=", errors)
	get_tree().quit(1 if errors else 0)
