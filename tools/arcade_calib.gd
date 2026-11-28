extends Node
## Подбор числа ходов на три звезды: ИИ проходит уровни Аркады, печатает ходы.
## Запуск: Godot --headless --path . res://tools/arcade_calib.tscn -- --test-save
const LEVELS := [1, 2, 3, 5, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100]
const RUNS := 3


func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	var g: GameScreen = main.game
	for n in LEVELS:
		var res := []
		var d := BB.level_def(n)
		var total := 0
		for gl in d.goals:
			total += gl.need
		for r in RUNS:
			g.start_game("arcade", n)
			var mv := 0
			while not g.finished and mv < 300:
				for k in 200:
					if not g.pieces.all(func(x): return x == null):
						break
					await get_tree().process_frame
				if not _move(g):
					break
				mv += 1
			var won := g.goals.all(func(x): return x.left == 0)
			res.append(mv if won else -mv)
		print("L%d fruits=%d stones=%d par=%d runs=%s" % [n, total, d.stones, d.par, res])
	get_tree().quit()


## Ход ИИ: предпочитает ходы, которые чистят линии с фруктами
func _move(g: GameScreen) -> bool:
	var b := GameScreen.bits(g.board)
	var best := {}
	for i in 3:
		var p = g.pieces[i]
		if p == null:
			continue
		var all := []
		BBAI.best_move(b, p, all)
		for m in all:
			var v: float = m.lines * 1000 + m.score
			if m.lines > 0:
				# Бонус за фрукты в очищаемых линиях — как играл бы человек
				var after: int = b | (int(p.base) << (m.r * 8 + m.c))
				var cl: int = BBAI.full_lines(after)[0]
				for idx in 64:
					if cl & (1 << idx) and g.board[idx] != null and g.board[idx].f != "":
						v += 3000
			if best.is_empty() or v > best.v:
				best = {"i": i, "m": m, "v": v}
	if best.is_empty():
		return false
	g.place(best.i, g.pieces[best.i], best.m.r, best.m.c)
	return true
