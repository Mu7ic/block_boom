extends Control
## Корень игры: фон, экраны (заставка, меню, уровни, коллекция, онлайн-лобби, игра),
## обучение, всплывающие подсказки, отсчёт перед онлайн-боем.

var screens := {}
var current := ""
var game: GameScreen
var fx: FxLayer

# меню
var coll_btn: Button
var coll_dot: Control
var tog_sound: Widgets.Toggle
var tog_music: Widgets.Toggle
var tog_vibro: Widgets.Toggle
var menu_logo: Widgets.Logo
# уровни / коллекция
var level_grid: GridContainer
var coll_grid: GridContainer
var coll_bar: ProgressBar
var coll_text: Label
# лобби
var name_in: LineEdit
var server_in: LineEdit
var code_in: LineEdit
var lobby_main: Control
var lobby_wait: Control
var lobby_status: Label
var big_code: Label
var wait_label: Label
var lobby_code := ""
# обучение
var tut_root: Control
var tut_demo: Widgets.TutDemo
var tut_title: Label
var tut_text: Label
var tut_dots: HBoxContainer
var tut_next: Button
var tut_skip: Button
var tut_card: Control
var tut_step := 0
# подсказки и отсчёт
var toast_node: Control
var cd_label: Label

const TUT := [
	["Перетаскивай фигуры", "Бери фигуру снизу и ставь на поле. Хватать можно за любое место вокруг фигуры."],
	["Собирай линии", "Заполни строку или столбец целиком — они исчезнут и дадут очки. Несколько ходов подряд — комбо!"],
	["3 линии сразу = ×5", "Снеси 3 и больше линий одним ходом — очки ×5 и новый стиль блоков. Собери все 20!"],
	["Четыре режима", "Классика — играй на рекорд.\nАркада — 30 уровней, собирай фрукты.\nПротив бота и онлайн — кто больше за 3 минуты."],
]


func _ready() -> void:
	UI.init_fonts()
	Skins.font = UI.F_BOLD
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().set_auto_accept_quit(true)
	get_tree().set_quit_on_go_back(false)
	# Стартовая «Классика» открыта и не считается новинкой
	Save.add_skin(BB.SKINS[Save.skin][0])
	if Save.get_v("seen") == null:
		Save.mark_seen()

	fx = FxLayer.new()
	_build_splash()
	_build_menu()
	_build_levels()
	_build_collection()
	_build_online()
	game = GameScreen.new()
	game.main = self
	game.fx = fx
	add_child(game)
	screens["game"] = game
	_build_tutorial()
	add_child(fx)
	fx.z_index = 30
	Net.message.connect(_on_net)
	show_screen("splash")


func _draw() -> void:
	# Фон: диагональный градиент как в веб-версии
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([BB.C_BG1, BB.C_BG1.lerp(BB.C_BG2, 0.45), BB.C_BG2, BB.C_BG1.lerp(BB.C_BG2, 0.55)]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		_go_back()


func _go_back() -> void:
	if tut_root.visible:
		_close_tutorial()
	elif current == "game":
		game._on_back()
	elif current == "menu":
		get_tree().quit()
	elif current == "online":
		Net.send({"t": "leave"})
		show_screen("menu")
	elif current != "splash":
		show_screen("menu")


# ---------- Экраны ----------
func _screen(id: String) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	screens[id] = c
	return c


func show_screen(id: String) -> void:
	current = id
	for k in screens:
		screens[k].visible = k == id
	game.hide_overlays()
	hide_toast()
	clear_countdown()
	if id != "game":
		game.leave_game()
	if id == "menu":
		update_menu()


func _back_button(parent: Control, cb: Callable) -> Button:
	var b := UI.corner("← Меню")
	b.position = Vector2(22, 22)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ---------- Заставка ----------
func _build_splash() -> void:
	var s := _screen("splash")
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.center_box(s, 60)
	var grid := Widgets.SplashGrid.new()
	v.add_child(UI.centered(grid))
	var logo := Widgets.Logo.new(100, 1.2)
	v.add_child(UI.centered(logo))
	var hint := UI.label("Коснись, чтобы начать", 32, Color.WHITE, UI.F_BOLD)
	v.add_child(hint)
	logo.modulate.a = 0.0
	var tw := logo.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(logo, "modulate:a", 1.0, 0.4)
	var ht := hint.create_tween().set_loops()
	ht.tween_interval(0.8)
	ht.tween_property(hint, "modulate:a", 0.3, 0.8).set_trans(Tween.TRANS_SINE)
	ht.tween_property(hint, "modulate:a", 0.85, 0.8).set_trans(Tween.TRANS_SINE)
	# Средние ряды «взрываются» частицами
	get_tree().create_timer(1.1).timeout.connect(func():
		for n in 8:
			var i := 4 + n
			fx.burst(grid.cell_center_global(i), Widgets.PAL[(i * 5) % 8], 6, (n % 4) * 0.04))
	var done := [false]
	s.gui_input.connect(func(ev: InputEvent):
		if done[0] or not (ev is InputEventMouseButton and ev.pressed):
			return
		done[0] = true
		Audio.sfx("boom")
		Audio.buzz(40)
		show_screen("menu")
		if not Save.get_v("tut", false):
			get_tree().create_timer(0.25).timeout.connect(open_tutorial))


# ---------- Меню ----------
func _build_menu() -> void:
	var s := _screen("menu")
	var v := UI.center_box(s, 22)
	menu_logo = Widgets.Logo.new(72)
	v.add_child(UI.centered(menu_logo))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	var b1 := UI.big_button("Классика", "играй на рекорд", BB.C_YELLOW)
	b1.pressed.connect(func(): game.start_game("classic"))
	v.add_child(UI.centered(b1))
	var b2 := UI.big_button("Аркада", "уровни с фруктами", BB.C_BLUE)
	b2.pressed.connect(open_levels)
	v.add_child(UI.centered(b2))
	var b3 := UI.big_button("Против бота 🤖", "кто больше за 3 минуты", BB.C_PINK)
	b3.pressed.connect(func(): game.start_game("duel"))
	v.add_child(UI.centered(b3))
	var b4 := UI.big_button("Онлайн-бой 🌐", "с другом по коду комнаты", BB.C_GREEN)
	b4.pressed.connect(open_online)
	v.add_child(UI.centered(b4))

	var row := UI.hrow(v, 18)
	coll_btn = UI.button("🎨 Коллекция", Color(1, 1, 1, 0.14), Color.WHITE, 27, Vector2(0, 74))
	_pad(coll_btn, 30)
	coll_btn.pressed.connect(open_collection)
	row.add_child(coll_btn)
	coll_dot = Panel.new()
	coll_dot.add_theme_stylebox_override("panel", UI.box(BB.C_HOT))
	coll_dot.size = Vector2(16, 16)
	coll_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coll_btn.add_child(coll_dot)
	var help := UI.button("❓ Как играть", Color(1, 1, 1, 0.14), Color.WHITE, 27, Vector2(0, 74))
	_pad(help, 30)
	help.pressed.connect(open_tutorial)
	row.add_child(help)

	var row2 := UI.hrow(v, 18)
	tog_sound = Widgets.Toggle.new("🔊")
	tog_sound.pressed.connect(func():
		Audio.set_sound(not Save.sound)
		refresh_toggles())
	row2.add_child(tog_sound)
	tog_music = Widgets.Toggle.new("🎵")
	tog_music.pressed.connect(func():
		Audio.set_music(not Save.music)
		refresh_toggles())
	row2.add_child(tog_music)
	tog_vibro = Widgets.Toggle.new("📳")
	tog_vibro.pressed.connect(func():
		Save.vibro = not Save.vibro
		refresh_toggles()
		Audio.buzz(40))
	tog_vibro.visible = OS.has_feature("mobile")   # на компьютере вибрации нет
	row2.add_child(tog_vibro)
	for t in [tog_sound, tog_music, tog_vibro]:
		t.pressed.connect(func(): Audio.sfx("click"))
	refresh_toggles()


func _pad(b: Button, p: int) -> void:
	for k in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(k).duplicate()
		sb.content_margin_left = p
		sb.content_margin_right = p
		b.add_theme_stylebox_override(k, sb)


func refresh_toggles() -> void:
	tog_sound.set_on(Save.sound)
	tog_music.set_on(Save.music)
	tog_vibro.set_on(Save.vibro)


func update_menu() -> void:
	coll_btn.text = "🎨 Коллекция %d/%d" % [Save.got().size(), BB.SKINS.size()]
	coll_dot.visible = Save.has_new_skins()
	await get_tree().process_frame
	coll_dot.position = Vector2(coll_btn.size.x - 24, 6)
	menu_logo.restart()
	refresh_toggles()


# ---------- Уровни Аркады ----------
func _build_levels() -> void:
	var s := _screen("levels")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 34)
	s.add_child(v)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 100)
	v.add_child(sp)
	v.add_child(UI.label("Выбери уровень", 48, Color.WHITE, UI.F_BLACK))
	level_grid = GridContainer.new()
	level_grid.columns = 5
	level_grid.add_theme_constant_override("h_separation", 20)
	level_grid.add_theme_constant_override("v_separation", 20)
	v.add_child(UI.centered(level_grid))
	_back_button(s, func(): show_screen("menu"))


func open_levels() -> void:
	for ch in level_grid.get_children():
		ch.queue_free()
	var un := Save.unlocked
	for n in range(1, BB.LEVEL_COUNT + 1):
		var locked := n > un
		var done := n < un
		var bg := Color(1, 1, 1, 0.1) if locked else (BB.C_GREEN if done else BB.C_GOLD)
		var b := UI.button("🔒" if locked else str(n), bg, Color(1, 1, 1, 0.35) if locked else BB.C_INK, 36, Vector2(104, 104))
		for k in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(k).duplicate()
			sb.set_corner_radius_all(26)
			b.add_theme_stylebox_override(k, sb)
		if done:
			var ok := UI.label("✓", 22, BB.C_INK)
			ok.position = Vector2(78, 2)
			b.add_child(ok)
		if not locked:
			b.pressed.connect(func(): game.start_game("arcade", n))
		else:
			b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		level_grid.add_child(b)
	show_screen("levels")


# ---------- Коллекция стилей ----------
func _build_collection() -> void:
	var s := _screen("collection")
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 22)
	sc.add_child(v)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 100)
	v.add_child(sp)
	v.add_child(UI.label("Коллекция стилей", 48, Color.WHITE, UI.F_BLACK))
	var prog := UI.hrow(v, 22)
	coll_bar = ProgressBar.new()
	coll_bar.show_percentage = false
	coll_bar.custom_minimum_size = Vector2(290, 18)
	coll_bar.add_theme_stylebox_override("background", UI.box(Color(0, 0, 0, 0.3), 9))
	coll_bar.add_theme_stylebox_override("fill", UI.box(BB.C_HOT.lerp(BB.C_GOLD, 0.5), 9))
	coll_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog.add_child(coll_bar)
	coll_text = UI.label("", 28)
	prog.add_child(coll_text)
	coll_grid = GridContainer.new()
	coll_grid.columns = 4
	coll_grid.add_theme_constant_override("h_separation", 16)
	coll_grid.add_theme_constant_override("v_separation", 16)
	v.add_child(UI.centered(coll_grid))
	var hint := UI.label("Новый стиль открывается, когда сносишь 3+ линии за один ход", 25, Color(1, 1, 1, 0.6), UI.F_REG)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	v.add_child(UI.centered(hint))
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, 50)
	v.add_child(bottom)
	_back_button(s, func(): show_screen("menu"))


func open_collection() -> void:
	for ch in coll_grid.get_children():
		ch.queue_free()
	var got := Save.got()
	var seen := Save.seen()
	for i in BB.SKINS.size():
		var id: String = BB.SKINS[i][0]
		var open := got.has(id)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(150, 0)
		var sb := UI.box(Color(0, 0, 0, 0.22), 26, Vector4(6, 20, 6, 14))
		if i == Save.skin:
			sb.border_color = BB.C_GOLD
			sb.set_border_width_all(4)
		card.add_theme_stylebox_override("panel", sb)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 12)
		card.add_child(cv)
		var prev := Widgets.SkinPreview.new(i, not open, 40)
		cv.add_child(UI.centered(prev))
		if not open:
			var lock := UI.label("🔒", 38)
			lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			prev.add_child(lock)
		var nm := UI.label(BB.SKINS[i][1] if open else "???", 20, Color(1, 1, 1, 0.9 if open else 0.4), UI.F_BOLD)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(138, 52)
		cv.add_child(nm)
		coll_grid.add_child(card)
		if open and not seen.has(id):
			var badge := UI.label("NEW", 18, Color.WHITE, UI.F_BLACK)
			badge.add_theme_stylebox_override("normal", UI.box(BB.C_HOT, 14, Vector4(10, 2, 10, 2)))
			badge.position = Vector2(56, -34)
			prev.add_child(badge)
	coll_text.text = "Собрано %d из %d" % [got.size(), BB.SKINS.size()]
	coll_bar.max_value = BB.SKINS.size()
	coll_bar.value = 0
	coll_bar.create_tween().tween_property(coll_bar, "value", float(got.size()), 0.6)
	Save.mark_seen()
	show_screen("collection")


# ---------- Онлайн-лобби ----------
func _build_online() -> void:
	var s := _screen("online")
	var v := UI.center_box(s, 22)
	var t := UI.label("Онлайн-бой 🌐", 54, Color.WHITE, UI.F_BLACK)
	v.add_child(t)
	v.add_child(UI.label("3 минуты — у кого больше очков", 28, Color(1, 1, 1, 0.65), UI.F_REG))
	name_in = LineEdit.new()
	name_in.placeholder_text = "Твоё имя"
	name_in.max_length = 16
	name_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_in.custom_minimum_size = Vector2(470, 0)
	v.add_child(UI.centered(name_in))

	lobby_main = VBoxContainer.new()
	lobby_main.add_theme_constant_override("separation", 22)
	v.add_child(lobby_main)
	var create := UI.big_button("Создать бой", "получишь код для друга", BB.C_YELLOW)
	create.pressed.connect(create_room)
	lobby_main.add_child(UI.centered(create))
	lobby_main.add_child(UI.label("или", 26, Color(1, 1, 1, 0.5), UI.F_REG))
	var jr := UI.hrow(lobby_main, 16)
	code_in = LineEdit.new()
	code_in.placeholder_text = "Код"
	code_in.max_length = 4
	code_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_in.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	code_in.custom_minimum_size = Vector2(220, 0)
	code_in.add_theme_font_size_override("font_size", 40)
	code_in.text_changed.connect(func(txt: String):
		var digits := ""
		for ch in txt:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != txt:
			code_in.text = digits
			code_in.caret_column = digits.length())
	code_in.text_submitted.connect(func(_t): join_room())
	jr.add_child(code_in)
	var join := UI.button("Войти", BB.C_YELLOW, BB.C_INK, 32, Vector2(180, 84))
	join.pressed.connect(join_room)
	jr.add_child(join)

	lobby_wait = VBoxContainer.new()
	lobby_wait.add_theme_constant_override("separation", 18)
	lobby_wait.visible = false
	v.add_child(lobby_wait)
	lobby_wait.add_child(UI.label("КОД КОМНАТЫ", 25, Color(1, 1, 1, 0.65), UI.F_BOLD))
	big_code = UI.label("----", 115, BB.C_GOLD, UI.F_BLACK)
	UI.shadow(big_code, 9)
	lobby_wait.add_child(big_code)
	wait_label = UI.label("Ждём соперника", 31, Color(1, 1, 1, 0.85), UI.F_BOLD)
	lobby_wait.add_child(wait_label)
	var share := UI.button("📤 Скопировать для друга", Color(1, 1, 1, 0.14), Color.WHITE, 27, Vector2(0, 74))
	_pad(share, 30)
	share.pressed.connect(share_room)
	lobby_wait.add_child(UI.centered(share))
	var cancel := UI.button("Отмена", Color(1, 1, 1, 0.14), Color.WHITE, 30, Vector2(220, 80))
	cancel.pressed.connect(func():
		Net.send({"t": "leave"})
		lobby_view(false)
		set_lobby_status(""))
	lobby_wait.add_child(UI.centered(cancel))

	lobby_status = UI.label("", 27, Color("ffb3d9"), UI.F_BOLD)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_status.custom_minimum_size = Vector2(560, 40)
	v.add_child(UI.centered(lobby_status))

	# Адрес сервера (тот же server.js, что у веб-версии)
	var srow := UI.hrow(v, 12)
	srow.add_child(UI.label("Сервер:", 22, Color(1, 1, 1, 0.45), UI.F_REG))
	server_in = LineEdit.new()
	server_in.custom_minimum_size = Vector2(440, 0)
	server_in.add_theme_font_size_override("font_size", 22)
	server_in.placeholder_text = Save.DEFAULT_SERVER
	server_in.text_changed.connect(func(txt: String): Save.server = txt.strip_edges())
	srow.add_child(server_in)

	_back_button(s, func():
		Net.send({"t": "leave"})
		show_screen("menu"))
	# «Ждём соперника...» — бегущие точки
	var dots := [0]
	var tm := Timer.new()
	tm.wait_time = 0.35
	tm.autostart = true
	tm.timeout.connect(func():
		dots[0] = (dots[0] + 1) % 4
		wait_label.text = "Ждём соперника" + ".".repeat(dots[0]))
	s.add_child(tm)


func open_online() -> void:
	name_in.text = Save.player_name
	server_in.text = Save.server
	code_in.text = ""
	lobby_view(false)
	set_lobby_status("")
	show_screen("online")


func lobby_view(waiting: bool) -> void:
	lobby_main.visible = not waiting
	lobby_wait.visible = waiting
	name_in.visible = not waiting


func set_lobby_status(t: String) -> void:
	lobby_status.text = t


func player_name() -> String:
	var n := name_in.text.strip_edges().substr(0, 16)
	Save.player_name = n
	return n if n != "" else "Игрок"


func ensure_connected() -> bool:
	set_lobby_status("Подключаемся…")
	var err: String = await Net.connect_to(Save.server)
	if err == "":
		set_lobby_status("")
		return true
	set_lobby_status("Укажи адрес сервера внизу" if err == "nourl" else "Сервер недоступен. Попробуй позже или сыграй с ботом 🤖")
	return false


func create_room() -> void:
	if not await ensure_connected():
		return
	Net.send({"t": "create", "name": player_name()})


func join_room() -> void:
	var code := code_in.text.strip_edges()
	if code.length() != 4:
		set_lobby_status("Введи код из 4 цифр")
		return
	if not await ensure_connected():
		return
	Net.send({"t": "join", "code": code, "name": player_name()})


func share_room() -> void:
	DisplayServer.clipboard_set("Го в «%s» онлайн! Код комнаты: %s" % [BB.GAME_NAME, lobby_code])
	set_lobby_status("Скопировано — отправь другу")


func _on_net(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	match t:
		"created":
			lobby_code = str(m.get("code", ""))
			big_code.text = lobby_code
			lobby_view(true)
			set_lobby_status("")
			return
		"error":
			lobby_view(false)
			set_lobby_status(str(m.get("msg", "Ошибка")))
			return
	if game.on_net(m):
		return
	if current == "online":
		if t == "oppLeft":
			lobby_view(false)
			set_lobby_status("Соперник отключился")
		elif t == "closed":
			lobby_view(false)
			set_lobby_status("Связь с сервером потеряна")


# ---------- Отсчёт 3-2-1 ----------
func countdown(n: int, done: Callable, alive: Callable) -> void:
	if not alive.call():
		return
	clear_countdown()
	cd_label = UI.label(str(n) if n > 0 else "Старт!", 200 if n > 0 else 115, BB.C_GOLD, UI.F_BLACK)
	UI.shadow(cd_label, 14)
	cd_label.z_index = 35
	add_child(cd_label)
	cd_label.reset_size()
	var sz := cd_label.size
	cd_label.position = Vector2(size.x * 0.5, size.y * 0.42) - sz * 0.5
	cd_label.pivot_offset = sz * 0.5
	cd_label.scale = Vector2.ONE * 2.2
	cd_label.modulate.a = 0.0
	var l := cd_label
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.22)
	tw.tween_interval(0.5)
	tw.tween_property(l, "scale", Vector2.ONE * 0.85, 0.18)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func():
		if is_instance_valid(l):
			l.queue_free())
	if n > 0:
		Audio.sfx("tick")
		Audio.buzz(15)
		get_tree().create_timer(1.0).timeout.connect(func(): countdown(n - 1, done, alive))
	else:
		Audio.sfx("skin")
		Audio.buzz(40)
		done.call()


func clear_countdown() -> void:
	if cd_label and is_instance_valid(cd_label):
		cd_label.queue_free()
	cd_label = null


# ---------- Подсказка при первом входе в режим ----------
func hint_once(key: String, text: String) -> void:
	if not Save.hint_once(key):
		return
	toast(text)


func hide_toast() -> void:
	if toast_node:
		toast_node.queue_free()
		toast_node = null


func toast(text: String) -> void:
	if toast_node:
		toast_node.queue_free()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.16, 0.93), 30, Vector4(32, 24, 32, 24)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 30
	var l := UI.label(text, 28, Color.WHITE, UI.F_BOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	p.add_child(l)
	add_child(p)
	toast_node = p
	p.reset_size()
	var sz := p.get_combined_minimum_size()
	p.size = sz
	p.position = Vector2((size.x - sz.x) * 0.5, size.y * 0.38)
	p.pivot_offset = sz * 0.5
	p.modulate.a = 0.0
	p.scale = Vector2.ONE * 0.9
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.9)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if toast_node == p:
			toast_node = null
		p.queue_free())


# ---------- Обучение ----------
func _build_tutorial() -> void:
	tut_root = Control.new()
	tut_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tut_root.mouse_filter = Control.MOUSE_FILTER_STOP
	tut_root.visible = false
	tut_root.z_index = 40
	add_child(tut_root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.12, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_root.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.box(Color("252f63"), 40, Vector4(36, 40, 36, 32)))
	card.custom_minimum_size = Vector2(610, 0)
	center.add_child(card)
	tut_card = card
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	tut_demo = Widgets.TutDemo.new()
	v.add_child(UI.centered(tut_demo))
	tut_title = UI.label("", 43, Color.WHITE, UI.F_BLACK)
	v.add_child(tut_title)
	tut_text = UI.label("", 27, Color(1, 1, 1, 0.85), UI.F_REG)
	tut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_text.custom_minimum_size = Vector2(530, 120)
	tut_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(UI.centered(tut_text))
	tut_dots = UI.hrow(v, 11)
	var row := UI.hrow(v, 20)
	tut_skip = UI.button("Пропустить", Color(1, 1, 1, 0.14), Color.WHITE, 30, Vector2(230, 80))
	tut_skip.pressed.connect(_close_tutorial)
	row.add_child(tut_skip)
	tut_next = UI.button("Далее", BB.C_YELLOW, BB.C_INK, 30, Vector2(230, 80))
	tut_next.pressed.connect(func():
		if tut_step < TUT.size() - 1:
			tut_step += 1
			_render_tut()
		else:
			_close_tutorial())
	row.add_child(tut_next)


func open_tutorial() -> void:
	tut_step = 0
	_render_tut()
	tut_root.visible = true


func _render_tut() -> void:
	tut_demo.set_step(tut_step)
	tut_title.text = TUT[tut_step][0]
	tut_text.text = TUT[tut_step][1]
	for ch in tut_dots.get_children():
		ch.queue_free()
	for i in TUT.size():
		var d := Panel.new()
		d.custom_minimum_size = Vector2(36 if i == tut_step else 14, 14)
		d.add_theme_stylebox_override("panel", UI.box(BB.C_GOLD if i == tut_step else Color(1, 1, 1, 0.25), 7))
		tut_dots.add_child(d)
	var last := tut_step == TUT.size() - 1
	tut_next.text = "Играть!" if last else "Далее"
	tut_skip.modulate.a = 0.0 if last else 1.0
	tut_skip.disabled = last
	tut_card.pivot_offset = tut_card.size * 0.5
	tut_card.scale = Vector2.ONE * 0.85
	tut_card.create_tween().tween_property(tut_card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_tutorial() -> void:
	tut_root.visible = false
	Save.set_v("tut", true)
