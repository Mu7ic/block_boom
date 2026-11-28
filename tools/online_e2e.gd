extends Node
## Настоящий быстрый бой против локального сервера: ИИ делает ходы, в конце печатаем свой счёт.
## Запускается из tools/online_e2e.js, который поднимает сервер и соперника и сверяет счёт
## игры со счётом, который принял сервер (защита от накруток не должна резать честные ходы).

var main: Control


func _ready() -> void:
	var port := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("port="):
			port = int(a.substr(5))
	Save.set_v("server", "ws://127.0.0.1:%d/ws" % port)
	Save.set_v("tut", true)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	var g: GameScreen = main.game
	await get_tree().create_timer(1.0).timeout
	main.show_screen("menu")
	main.open_online()
	await get_tree().create_timer(1.0).timeout
	main.quick_match()
	for k in 600:
		if g.mode == "online" and not g.duel.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
	if g.duel.is_empty():
		print("E2E no match")
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.4).timeout   # отсчёт
	var moves := 0
	while not g.finished and not g.duel.is_empty():
		for k in 120:
			if not g.pieces.all(func(x): return x == null):
				break
			await get_tree().process_frame
		var b := GameScreen.bits(g.board)
		var best := {}
		for i in 3:
			var p = g.pieces[i]
			if p == null:
				continue
			var m := BBAI.best_move(b, p)
			if not m.is_empty() and (best.is_empty() or m.lines * 1000 + m.score > best.v):
				best = {"i": i, "m": m, "v": m.lines * 1000 + m.score}
		if not best.is_empty() and not g.finished and not g.duel.is_empty():
			g.place(best.i, g.pieces[best.i], best.m.r, best.m.c)
			moves += 1
		await get_tree().create_timer(0.3).timeout
	for k in 80:   # ждём итог от сервера
		if g.last_result != [0, 0]:
			break
		await get_tree().create_timer(0.1).timeout
	print("E2E score=%d moves=%d result=%s ranked=%s" % [g.score, moves, str(g.last_result), str(g.ranked)])
	get_tree().quit()
