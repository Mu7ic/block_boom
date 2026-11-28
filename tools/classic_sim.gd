extends Node
## Симуляция «Классики»: ИИ-игроки играют партии с генератором фигур из игры,
## считаем ходы до проигрыша и очки по формуле игры (Scoring).
## Запуск:  Godot --headless --path . res://tools/classic_sim.tscn -- [games=60]

const MAX_MOVES := 600


func _ready() -> void:
	var games := 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("games="):
			games = int(a.substr(6))
	for ease in [false, true]:
		BBAI.ease = ease
		print("--- помощь при забитом поле: ", ease)
		for player in ["weak", "mid"]:
			var mv := []
			var sc := []
			var ol := []
			var lines := 0
			var max_combo := 0
			for g in games:
				seed(1000 + g)
				var r := play(player)
				mv.append(r.moves)
				sc.append(r.score)
				ol.append(r.old)
				lines += r.lines
				max_combo = maxi(max_combo, r.max_combo)
			mv.sort()
			sc.sort()
			ol.sort()
			print("%-6s  старые очки: медиана %6d  (90%% %6d)" % [player, ol[games / 2], ol[games * 9 / 10]])
			print("%-6s  ходов: медиана %4d  (10%% %4d, 90%% %4d)   очки: медиана %8d  (10%% %7d, 90%% %8d, макс %8d)   линий/ход %.2f  макс.комбо %d" % [
				player, mv[games / 2], mv[games / 10], mv[games * 9 / 10],
				sc[games / 2], sc[games / 10], sc[games * 9 / 10], sc[games - 1],
				float(lines) / maxi(1, mv.reduce(func(x, y): return x + y, 0)), max_combo])
	get_tree().quit()


## Ход игрока: weak — случайный из 6 лучших мест, mid — из 2 лучших, strong — лучший
func choose(b: int, piece: Dictionary, player: String) -> Dictionary:
	if player == "strong":
		return BBAI.best_move(b, piece)
	var all := []
	BBAI.best_move(b, piece, all)
	if all.is_empty():
		return {}
	all.sort_custom(func(x, y): return x.score > y.score)
	var k := 6 if player == "weak" else 2
	return all[randi() % mini(k, all.size())]


func play(player: String) -> Dictionary:
	var b := 0
	var gen := {"since": 0}
	var st := Scoring.new()
	var old := 0
	var oc := 0
	var moves := 0
	var lines := 0
	while moves < MAX_MOVES:
		var ids := BBAI.smart_set(b, gen)
		var set := []
		if ids.is_empty():
			for t in 30:
				set = [randi() % BB.SHAPES.size(), randi() % BB.SHAPES.size(), randi() % BB.SHAPES.size()]
				if set.any(func(s): return BBAI.fits_anywhere(b, BB.SHAPES[s])):
					break
		else:
			set = ids
		# Игрок ставит по одной: каждый раз выбирает фигуру, для которой ход лучше
		var left := set.duplicate()
		while not left.is_empty():
			var best := {}
			var bi := -1
			for k in left.size():
				var m := choose(b, BB.SHAPES[left[k]], player)
				if not m.is_empty() and (best.is_empty() or m.score > best.score):
					best = m
					bi = k
			if bi < 0:
				return {"moves": moves, "score": st.score, "old": old, "lines": lines, "max_combo": st.max_combo}
			var cells: int = BB.SHAPES[left[bi]].cells.size()
			left.remove_at(bi)
			b = best.board
			moves += 1
			lines += int(best.lines)
			st.add(cells, int(best.lines), best.lines > 0 and b == 0)
			# Прежняя формула — для сравнения
			old += cells
			if best.lines > 0:
				oc += 1
				old += int(best.lines * best.lines * 10 * oc * (5 if best.lines >= 3 else 1)) + (300 if b == 0 else 0)
			else:
				oc = 0
			if best.lines >= 3:
				gen.since = 0
	return {"moves": moves, "score": st.score, "old": old, "lines": lines, "max_combo": st.max_combo}
