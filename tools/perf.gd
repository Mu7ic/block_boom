extends SceneTree
## Время генерации тройки фигур на реальных позициях (ИИ играет сам с собой).
## Запуск: Godot --headless --path . -s res://tools/perf.gd
func _init():
	var b := 0
	var gen := {"since": 0}
	var times := []
	for set_i in 60:
		var t0 := Time.get_ticks_usec()
		var ids := BBAI.smart_set(b, gen)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		if ids.is_empty():
			b = 0
			continue
		for s in ids:
			var m := BBAI.best_move(b, BB.SHAPES[s])
			if m.is_empty():
				break
			if m.lines >= 3:
				gen.since = 0
			b = m.board
	times.sort()
	print("sets=", times.size(), " median=", times[times.size() / 2], " p90=", times[int(times.size() * 0.9)], " max=", times[-1])
	quit()
