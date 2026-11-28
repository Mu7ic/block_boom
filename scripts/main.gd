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
var daily_btn: Button
var bg_override: Array = []     ## фон мира Аркады во время уровня
var level_map: LevelMap
var level_scroll: ScrollContainer
var stars_l: Label
var lang_btn: Button
# лучшие игроки
var top_list: VBoxContainer
var top_me: Label
var theme_grid: GridContainer
var mis_btn: Button
var lvl_l: Label
var lvl_bar: ProgressBar
var login_root: Control
var login_grid: GridContainer
var login_btn: Button
var season_l: Label
var upd_btn: Button             ## «Есть обновление» — когда сервер знает сборку новее
var _ev_busy := false
var season := {}                ## {id, left} с сервера: текущий сезон и секунд до конца
var _season_t := 0.0
var mis_dot: Control
# задания
var mis_box: VBoxContainer
var keys_l: Label
var chest_btn: Button
var reward_l: Label
var renew_l: Label
var eff_grid: GridContainer
# уровни / коллекция
var coll_grid: GridContainer
var coll_bar: ProgressBar
var coll_text: Label
# лобби
var name_in: LineEdit
var server_in: LineEdit
var code_in: LineEdit
var lobby_main: Control
var lobby_wait: Control
var lobby_search: Control
var lobby_status: Label
var rating_l: Label
var search_l: Label
var search_time_l: Label
var bot_offer: Button
var search_t0 := 0.0
const BOT_OFFER_AFTER := 15.0   ## через сколько секунд поиска предложить бота
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
	["Собирай линии", "Заполни строку или столбец целиком — они исчезнут и дадут очки. Убирай линии почаще: комбо растёт ×2, ×3, ×4… и не сгорает, пока между линиями не больше двух ходов."],
	["Несколько линий сразу", "Чем больше линий за один ход, тем больше очков. 3 и больше — новый стиль блоков. Собери все 20!"],
	["Четыре режима", "Классика — играй на рекорд.\nАркада — 30 уровней, собирай фрукты.\nПротив бота и онлайн — кто больше за 3 минуты."],
]


func _ready() -> void:
	UI.init_fonts()
	I18N.setup()
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
	_build_missions()
	_build_online()
	_build_top()
	game = GameScreen.new()
	game.main = self
	game.fx = fx
	add_child(game)
	screens["game"] = game
	_build_tutorial()
	add_child(fx)
	fx.z_index = 30
	Net.message.connect(_on_net)
	Missions.done.connect(func(txt: String):
		toast(tr("🎯 Задание выполнено! +🔑") + "\n" + txt)
		Audio.sfx("record"))
	Missions.level_up.connect(func(lvl: int):
		toast(tr("⭐ Уровень %d! +🔑") % lvl)
		Audio.sfx("record"))
	_build_login()
	show_screen("splash")


func _draw() -> void:
	# Фон: диагональный градиент как в веб-версии, цвета — из выбранной темы
	var s := size
	var th := BB.theme_def(Save.bg_theme)
	var c1: Color = th[2]
	var c2: Color = th[3]
	if bg_override.size() == 2:
		c1 = bg_override[1]
		c2 = bg_override[0]
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([c1, c1.lerp(c2, 0.45), c2, c1.lerp(c2, 0.55)]))


func set_bg(cols: Array) -> void:
	if cols != bg_override:
		bg_override = cols
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		_go_back()


var _back_at := -1000


func _go_back() -> void:
	# На Android одно нажатие «Назад» приходит дважды (уведомлением и клавишей) —
	# без этой защиты игра уходила в меню и тут же закрывалась
	var t := Time.get_ticks_msec()
	if t - _back_at < 350:
		return
	_back_at = t
	if login_root.visible:
		login_root.visible = false
	elif tut_root.visible:
		_close_tutorial()
	elif current == "game":
		game._on_back()
	elif current == "menu":
		get_tree().quit()
	elif current == "online":
		if lobby_search.visible or lobby_wait.visible:
			cancel_search()
		else:
			Net.send({"t": "leave"})
			show_screen("menu")
	elif current == "top":
		open_online()
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
		# Награда за вход — раз в день, когда открывается меню (обучение показываем раньше)
		if Missions.login_state().can and Save.get_v("tut", false) and not "--test-save" in OS.get_cmdline_user_args():
			open_login()


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
		track("open")
		# При запуске тихо отправляем результат вызова дня, сыгранного без сети
		if not Save.daily_pending.is_empty():
			get_tree().create_timer(2.0).timeout.connect(flush_daily)
		if not Save.get_v("tut", false):
			get_tree().create_timer(0.25).timeout.connect(open_tutorial))


# ---------- Меню ----------
func _build_menu() -> void:
	var s := _screen("menu")
	# Уровень игрока — сверху по центру
	var lv := UI.hrow(s, 16)
	lv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	lv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lv.position.y = 44
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lvl_l = UI.label("", 30, BB.C_GOLD, UI.F_BLACK)
	lv.add_child(lvl_l)
	lvl_bar = ProgressBar.new()
	lvl_bar.show_percentage = false
	lvl_bar.custom_minimum_size = Vector2(260, 16)
	lvl_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvl_bar.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.16), 8))
	lvl_bar.add_theme_stylebox_override("fill", UI.box(BB.C_GOLD, 8))
	lv.add_child(lvl_bar)
	upd_btn = UI.button("⬆ Есть обновление — скачать", BB.C_GREEN, BB.C_INK, 24, Vector2(0, 56))
	_pad(upd_btn, 26)
	upd_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	upd_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	upd_btn.position.y = 96
	upd_btn.visible = false
	upd_btn.pressed.connect(func(): OS.shell_open(BB.DOWNLOAD_URL))
	s.add_child(upd_btn)
	var v := UI.center_box(s, 22)
	menu_logo = Widgets.Logo.new(72)
	v.add_child(UI.centered(menu_logo))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	var b1 := UI.big_button("Классика", "играй на рекорд", BB.C_YELLOW)
	b1.pressed.connect(func(): game.start_game("classic", 1, true))   # продолжит незаконченную партию
	v.add_child(UI.centered(b1))
	daily_btn = UI.big_button("Вызов дня 📅", "", Color("ffa93b"))
	daily_btn.pressed.connect(func(): game.start_game("daily"))
	v.add_child(UI.centered(daily_btn))
	var b2 := UI.big_button("Аркада", "уровни с фруктами", BB.C_BLUE)
	b2.pressed.connect(open_levels)
	v.add_child(UI.centered(b2))
	var b3 := UI.big_button("Против бота 🤖", "кто больше за 3 минуты", BB.C_PINK)
	b3.pressed.connect(func(): game.start_game("duel"))
	v.add_child(UI.centered(b3))
	var b4 := UI.big_button("Онлайн-бой 🌐", "рейтинг и бои с друзьями", BB.C_GREEN)
	b4.pressed.connect(open_online)
	v.add_child(UI.centered(b4))

	for b in [b1, daily_btn, b2, b3, b4]:
		b.custom_minimum_size.y = 104

	var row := UI.hrow(v, 18)
	coll_btn = UI.button("🎨 Коллекция", Color(1, 1, 1, 0.14), Color.WHITE, 27, Vector2(0, 74))
	_pad(coll_btn, 26)
	coll_btn.pressed.connect(open_collection)
	row.add_child(coll_btn)
	coll_dot = _dot(coll_btn)
	mis_btn = UI.button("🎯 Задания", Color(1, 1, 1, 0.14), Color.WHITE, 27, Vector2(0, 74))
	_pad(mis_btn, 26)
	mis_btn.pressed.connect(open_missions)
	row.add_child(mis_btn)
	mis_dot = _dot(mis_btn)

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
	lang_btn = Widgets.Toggle.new(I18N.current().to_upper())
	lang_btn.add_theme_font_size_override("font_size", 30)
	lang_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lang_btn.pressed.connect(func():
		Audio.sfx("click")
		var langs: Array = I18N.LANGS
		I18N.apply(langs[(langs.find(I18N.current()) + 1) % langs.size()])
		update_menu())
	row2.add_child(lang_btn)
	var help := Widgets.Toggle.new("❓")
	help.pressed.connect(func():
		Audio.sfx("click")
		open_tutorial())
	row2.add_child(help)
	refresh_toggles()


func _dot(parent: Control) -> Control:
	var d := Panel.new()
	d.add_theme_stylebox_override("panel", UI.box(BB.C_HOT))
	d.size = Vector2(16, 16)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)
	return d


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
	coll_btn.text = tr("🎨 Коллекция %d/%d") % [Save.got().size(), BB.SKINS.size()]
	coll_dot.visible = Save.has_new_skins()
	mis_btn.text = tr("🎯 Задания %d/3") % Missions.done_count()
	lang_btn.text = I18N.current().to_upper()
	mis_dot.visible = Missions.chest_ready()
	upd_btn.visible = int(Save.get_v("latest", 0)) > BB.BUILD
	var li := Missions.level_info()
	lvl_l.text = tr("⭐ Ур. %d") % li.level
	lvl_bar.max_value = li.need
	lvl_bar.value = li.cur
	await get_tree().process_frame
	coll_dot.position = Vector2(coll_btn.size.x - 24, 6)
	mis_dot.position = Vector2(mis_btn.size.x - 24, 6)
	menu_logo.restart()
	refresh_toggles()
	var sub: Label = daily_btn.get_child(0).get_child(1)
	var st := Save.daily_streak
	var best := Save.daily_best(BB.today())
	sub.text = (tr("🔥 серия %d дн.") % st if st > 0 else tr("одни фигуры для всех")) + (tr(" · лучший %d") % best if best > 0 else "")


# ---------- Карта Аркады ----------
func _build_levels() -> void:
	var s := _screen("levels")
	level_scroll = ScrollContainer.new()
	level_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	level_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	s.add_child(level_scroll)
	level_map = LevelMap.new()
	level_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_map.play.connect(func(n: int): game.start_game("arcade", n))
	level_scroll.add_child(level_map)
	# Шапка поверх карты
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.16, 0.55), 0, Vector4(0, 0, 0, 0)))
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.custom_minimum_size = Vector2(0, 104)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(head)
	stars_l = UI.label("", 34, BB.C_GOLD, UI.F_BLACK)
	stars_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stars_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stars_l.position = Vector2(-260, 26)
	stars_l.size = Vector2(236, 56)
	s.add_child(stars_l)
	_back_button(s, func(): show_screen("menu"))


func open_levels() -> void:
	show_screen("levels")
	stars_l.text = "★ %d" % Save.total_stars()
	level_map.rebuild()
	# Прокрутка к текущему уровню (после раскладки)
	await get_tree().process_frame
	await get_tree().process_frame
	level_scroll.scroll_vertical = int(level_map.level_pos(Save.unlocked).y - level_scroll.size.y * 0.55)


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
	var hint := UI.label("Стили открываются, когда сносишь 3+ линии за ход, и в сундуке заданий. Нажми на стиль — начнёшь игру с ним.", 25, Color(1, 1, 1, 0.6), UI.F_REG)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	v.add_child(UI.centered(hint))
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 16)
	v.add_child(sp2)
	v.add_child(UI.label("Эффекты очистки", 40, Color.WHITE, UI.F_BLACK))
	eff_grid = GridContainer.new()
	eff_grid.columns = 3
	eff_grid.add_theme_constant_override("h_separation", 16)
	eff_grid.add_theme_constant_override("v_separation", 16)
	v.add_child(UI.centered(eff_grid))
	var hint2 := UI.label("Новые эффекты — в сундуке за задания дня 🎁", 25, Color(1, 1, 1, 0.6), UI.F_REG)
	v.add_child(UI.centered(hint2))
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(0, 16)
	v.add_child(sp3)
	v.add_child(UI.label("Фон", 40, Color.WHITE, UI.F_BLACK))
	theme_grid = GridContainer.new()
	theme_grid.columns = 3
	theme_grid.add_theme_constant_override("h_separation", 16)
	theme_grid.add_theme_constant_override("v_separation", 16)
	v.add_child(UI.centered(theme_grid))
	v.add_child(UI.centered(UI.label("Новые фоны — тоже в сундуке 🎁", 25, Color(1, 1, 1, 0.6), UI.F_REG)))
	var sp4 := Control.new()
	sp4.custom_minimum_size = Vector2(0, 40)
	v.add_child(sp4)
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
		if open:
			_selectable(card, func():
				Save.skin = i
				open_collection())
		if open and not seen.has(id):
			var badge := UI.label("NEW", 18, Color.WHITE, UI.F_BLACK)
			badge.add_theme_stylebox_override("normal", UI.box(BB.C_HOT, 14, Vector4(10, 2, 10, 2)))
			badge.position = Vector2(56, -34)
			prev.add_child(badge)
	_fill_effects()
	_fill_themes()
	coll_text.text = tr("Собрано %d из %d") % [got.size(), BB.SKINS.size()]
	coll_bar.max_value = BB.SKINS.size()
	coll_bar.value = 0
	coll_bar.create_tween().tween_property(coll_bar, "value", float(got.size()), 0.6)
	Save.mark_seen()
	show_screen("collection")


## Карточка-кнопка: нажатие выбирает стиль или эффект
func _selectable(card: Control, cb: Callable) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Audio.sfx("click")
			cb.call())


func _fill_effects() -> void:
	for ch in eff_grid.get_children():
		ch.queue_free()
	var got := Save.effects_got()
	for e in BB.EFFECTS:
		var id: String = e[0]
		var open := got.has(id)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(196, 0)
		var sb := UI.box(Color(0, 0, 0, 0.22), 26, Vector4(6, 16, 6, 14))
		if id == Save.effect:
			sb.border_color = BB.C_GOLD
			sb.set_border_width_all(4)
		card.add_theme_stylebox_override("panel", sb)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		cv.add_child(UI.label(e[2] if open else "🔒", 52))
		cv.add_child(UI.label(e[1] if open else "???", 22, Color(1, 1, 1, 0.9 if open else 0.4), UI.F_BOLD))
		eff_grid.add_child(card)
		if open:
			_selectable(card, func():
				Save.effect = id
				var c := card.get_global_rect().get_center()
				_fill_effects()
				for k in 4:
					fx.burst(c, BB.COLORS[(k * 3) % 8], 5, k * 0.05, id))


func _fill_themes() -> void:
	for ch in theme_grid.get_children():
		ch.queue_free()
	var got := Save.themes_got()
	for th in BB.THEMES:
		var id: String = th[0]
		var open := got.has(id)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(196, 0)
		var sb := UI.box(Color(0, 0, 0, 0.22), 26, Vector4(14, 14, 14, 12))
		if id == Save.bg_theme:
			sb.border_color = BB.C_GOLD
			sb.set_border_width_all(4)
		card.add_theme_stylebox_override("panel", sb)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		var sw := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.gradient = Gradient.new()
		gt.gradient.set_color(0, th[2])
		gt.gradient.set_color(1, th[3])
		gt.fill_to = Vector2(1, 1)
		sw.texture = gt
		sw.custom_minimum_size = Vector2(160, 70)
		sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not open:
			sw.modulate = Color(0.35, 0.35, 0.35)
			var lock := UI.label("🔒", 34)
			lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			sw.add_child(lock)
		cv.add_child(sw)
		cv.add_child(UI.label(th[1] if open else "???", 22, Color(1, 1, 1, 0.9 if open else 0.4), UI.F_BOLD))
		theme_grid.add_child(card)
		if open:
			_selectable(card, func():
				Save.bg_theme = id
				queue_redraw()
				_fill_themes())


# ---------- Лучшие игроки ----------
func _build_top() -> void:
	var s := _screen("top")
	var v := UI.center_box(s, 18)
	v.add_child(UI.label("Лучшие игроки 🏆", 50, Color.WHITE, UI.F_BLACK))
	top_me = UI.label("", 28, BB.C_GOLD, UI.F_BLACK)
	top_me.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_me.custom_minimum_size = Vector2(600, 0)
	v.add_child(UI.centered(top_me))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.22), 30, Vector4(28, 20, 28, 20)))
	panel.custom_minimum_size = Vector2(620, 0)
	v.add_child(UI.centered(panel))
	top_list = VBoxContainer.new()
	top_list.add_theme_constant_override("separation", 6)
	panel.add_child(top_list)
	_back_button(s, open_online)


func open_top() -> void:
	for ch in top_list.get_children():
		ch.queue_free()
	top_me.text = tr("Загружаем…")
	show_screen("top")
	var r: Dictionary = await Net.request(Save.server, {"t": "top", "id": Save.player_id}, "topList", 5.0)
	if current != "top":
		return
	if r.is_empty():
		top_me.text = tr("Нет связи с сервером")
		return
	var top: Array = r.get("top", []) if r.get("top") is Array else []
	if top.is_empty():
		top_me.text = tr("Пока никто не играл рейтинговые бои")
		return
	var rank := int(r.get("rank", 0))
	top_me.text = tr("Твоё место: %d из %d") % [rank, int(r.get("total", 0))] if rank > 0 else tr("Сыграй быстрый бой, чтобы попасть в таблицу")
	for k in mini(top.size(), 15):
		var e = top[k]
		if not (e is Dictionary):
			continue
		var you: bool = e.get("you", false)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		top_list.add_child(row)
		var col := BB.C_GOLD if you else Color.WHITE
		var n := UI.label("%d." % (k + 1), 26, Color(1, 1, 1, 0.55), UI.F_BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		n.custom_minimum_size = Vector2(52, 0)
		row.add_child(n)
		var rt := int(e.get("rating", 0))
		var nm := UI.label("%s %s" % [BB.league(rt)[2], str(e.get("name", "?"))], 28, col, UI.F_BOLD, HORIZONTAL_ALIGNMENT_LEFT)
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)
		row.add_child(UI.label(str(rt), 28, col, UI.F_BLACK, HORIZONTAL_ALIGNMENT_RIGHT))


# ---------- Задания дня ----------
func _build_missions() -> void:
	var s := _screen("missions")
	var v := UI.center_box(s, 22)
	v.add_child(UI.label("Задания дня 🎯", 50, Color.WHITE, UI.F_BLACK))
	renew_l = UI.label("", 25, Color(1, 1, 1, 0.55), UI.F_REG)
	v.add_child(renew_l)
	mis_box = VBoxContainer.new()
	mis_box.add_theme_constant_override("separation", 16)
	v.add_child(UI.centered(mis_box))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	keys_l = UI.label("", 44, BB.C_GOLD, UI.F_BLACK)
	v.add_child(keys_l)
	chest_btn = UI.big_button("🎁 Открыть сундук", "новый стиль, эффект или фон", BB.C_GOLD)
	chest_btn.pressed.connect(open_chest)
	v.add_child(UI.centered(chest_btn))
	reward_l = UI.label("", 32, Color.WHITE, UI.F_BLACK)
	reward_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_l.custom_minimum_size = Vector2(600, 90)
	v.add_child(UI.centered(reward_l))
	_back_button(s, func(): show_screen("menu"))


func open_missions() -> void:
	for ch in mis_box.get_children():
		ch.queue_free()
	for m in Missions.list():
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(600, 0)
		var sb := UI.box(Color(0.31, 0.84, 0.48, 0.3) if m.done else Color(0, 0, 0, 0.22), 26, Vector4(28, 18, 28, 18))
		card.add_theme_stylebox_override("panel", sb)
		mis_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 10)
		card.add_child(cv)
		var h := HBoxContainer.new()
		cv.add_child(h)
		var t := UI.label(Missions.text(m), 28, Color.WHITE, UI.F_BOLD, HORIZONTAL_ALIGNMENT_LEFT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(UI.label("✓ 🔑" if m.done else "%d/%d" % [m.prog, m.target], 28, BB.C_GOLD if m.done else Color(1, 1, 1, 0.7), UI.F_BLACK))
		if not m.done:
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 14)
			bar.add_theme_stylebox_override("background", UI.box(Color(0, 0, 0, 0.3), 7))
			bar.add_theme_stylebox_override("fill", UI.box(BB.C_YELLOW, 7))
			bar.max_value = m.target
			bar.value = m.prog
			cv.add_child(bar)
	reward_l.text = ""
	_update_chest()
	var now_d := Time.get_datetime_dict_from_system()
	var left: int = (23 - now_d.hour) * 60 + (59 - now_d.minute)
	renew_l.text = tr("Новые задания через %d ч %d мин") % [left / 60, left % 60]
	show_screen("missions")


func _update_chest() -> void:
	var k := Missions.keys
	keys_l.text = "🔑 %d / %d" % [mini(k, Missions.KEYS_PER_CHEST), Missions.KEYS_PER_CHEST] + ("  (+%d)" % (k - Missions.KEYS_PER_CHEST) if k > Missions.KEYS_PER_CHEST else "")
	chest_btn.disabled = not Missions.chest_ready()
	chest_btn.modulate.a = 1.0 if Missions.chest_ready() else 0.55


func open_chest() -> void:
	var r := Missions.open_chest()
	if r.is_empty():
		return
	var c := chest_btn.get_global_rect().get_center()
	chest_btn.pivot_offset = chest_btn.size * 0.5
	var tw := chest_btn.create_tween()
	tw.tween_property(chest_btn, "scale", Vector2.ONE * 1.15, 0.12)
	tw.tween_property(chest_btn, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	for k in 8:
		fx.burst(c, BB.COLORS[k], 6, k * 0.04, "confetti")
	Audio.sfx("skin")
	Audio.buzz([30, 40, 80])
	match r.kind:
		"skin":
			reward_l.text = tr("Новый стиль блоков: %s! 🎨") % tr(r.name)
		"effect":
			reward_l.text = tr("Новый эффект: %s! ✨\nВыбери его в коллекции") % tr(r.name)
		"theme":
			reward_l.text = tr("Новый фон: %s! 🖼\nВыбери его в коллекции") % tr(r.name)
		_:
			reward_l.text = tr("Ты уже собрал всё! 🏆")
	_update_chest()


# ---------- Награда за вход ----------
func _build_login() -> void:
	login_root = Control.new()
	login_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	login_root.mouse_filter = Control.MOUSE_FILTER_STOP
	login_root.visible = false
	login_root.z_index = 25
	add_child(login_root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.12, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	login_root.add_child(dim)
	var v := UI.center_box(login_root, 24)
	v.add_child(UI.label("Награда за вход 🎁", 50, Color.WHITE, UI.F_BLACK))
	v.add_child(UI.label("Заходи каждый день — на 7-й день целый сундук", 25, Color(1, 1, 1, 0.6), UI.F_REG))
	login_grid = GridContainer.new()
	login_grid.columns = 4
	login_grid.add_theme_constant_override("h_separation", 14)
	login_grid.add_theme_constant_override("v_separation", 14)
	v.add_child(UI.centered(login_grid))
	login_btn = UI.big_button("Забрать", "", BB.C_GOLD)
	login_btn.pressed.connect(claim_login)
	v.add_child(UI.centered(login_btn))


func open_login() -> void:
	var st := Missions.login_state()
	for ch in login_grid.get_children():
		ch.queue_free()
	for d in Missions.LOGIN_REWARDS.size():
		var today: bool = d == st.n and st.can
		var got: bool = d < st.n or (d == st.n and not st.can)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(146, 146)
		var bg := Color(0.31, 0.84, 0.48, 0.35) if got else (Color(BB.C_GOLD, 0.9) if today else Color(1, 1, 1, 0.1))
		card.add_theme_stylebox_override("panel", UI.box(bg, 26, Vector4(8, 12, 8, 12)))
		login_grid.add_child(card)
		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)
		var ink := BB.C_INK if today else Color.WHITE
		var dl := UI.label(tr("День %d") % (d + 1), 22, Color(ink, 0.75), UI.F_BOLD)
		dl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cv.add_child(dl)
		var last: bool = d == Missions.LOGIN_REWARDS.size() - 1
		var rl := UI.label("✓" if got else ("🎁" if last else "🔑"), 46, ink, UI.F_BLACK)
		rl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cv.add_child(rl)
		var kl := UI.label("×%d" % Missions.LOGIN_REWARDS[d], 24, ink, UI.F_BLACK)
		kl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cv.add_child(kl)
	login_root.visible = true
	login_root.modulate.a = 0.0
	login_root.create_tween().tween_property(login_root, "modulate:a", 1.0, 0.25)


func claim_login() -> void:
	var k := Missions.claim_login()
	login_root.visible = false
	if k <= 0:
		return
	var c := size * Vector2(0.5, 0.45)
	for i in 8:
		fx.burst(c, BB.COLORS[i], 6, i * 0.04, "confetti")
	Audio.sfx("skin")
	Audio.buzz([30, 40, 80])
	toast(tr("Награда за вход: 🔑×%d") % k + ("\n" + tr("Сундук готов — открой его в заданиях!") if Missions.chest_ready() else ""))
	update_menu()


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
	lobby_main.add_theme_constant_override("separation", 20)
	v.add_child(lobby_main)
	rating_l = UI.label("", 30, Color.WHITE, UI.F_BLACK)
	lobby_main.add_child(rating_l)
	season_l = UI.label("", 23, Color(1, 1, 1, 0.6), UI.F_REG)
	season_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lobby_main.add_child(season_l)
	var quick := UI.big_button("⚡ Быстрый бой", "соперник по рейтингу", BB.C_YELLOW)
	quick.pressed.connect(quick_match)
	lobby_main.add_child(UI.centered(quick))
	lobby_main.add_child(UI.label("или с другом — без рейтинга", 25, Color(1, 1, 1, 0.5), UI.F_REG))
	var top_btn := UI.button("🏆 Лучшие", Color(1, 1, 1, 0.12), Color.WHITE, 26, Vector2(0, 62))
	_pad(top_btn, 28)
	top_btn.pressed.connect(open_top)
	lobby_main.add_child(UI.centered(top_btn))
	var create := UI.button("Создать комнату", Color(1, 1, 1, 0.16), Color.WHITE, 30, Vector2(470, 84))
	create.pressed.connect(create_room)
	lobby_main.add_child(UI.centered(create))
	var jr := UI.hrow(lobby_main, 16)
	code_in = LineEdit.new()
	code_in.placeholder_text = "Код"
	code_in.max_length = 4
	code_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_in.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	code_in.custom_minimum_size = Vector2(270, 0)
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
	var join := UI.button("Войти", Color(1, 1, 1, 0.16), Color.WHITE, 30, Vector2(184, 84))
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
	cancel.pressed.connect(cancel_search)
	lobby_wait.add_child(UI.centered(cancel))

	# Быстрый бой: поиск соперника
	lobby_search = VBoxContainer.new()
	lobby_search.add_theme_constant_override("separation", 18)
	lobby_search.visible = false
	v.add_child(lobby_search)
	search_l = UI.label("Ищем соперника", 38, Color.WHITE, UI.F_BLACK)
	lobby_search.add_child(search_l)
	search_time_l = UI.label("0:00", 80, BB.C_GOLD, UI.F_BLACK)
	UI.shadow(search_time_l, 8)
	lobby_search.add_child(search_time_l)
	var hint := UI.label("Подбираем игрока с похожим рейтингом", 25, Color(1, 1, 1, 0.6), UI.F_REG)
	lobby_search.add_child(hint)
	bot_offer = UI.button("🤖 Пока сыграть с ботом", Color(1, 1, 1, 0.14), Color.WHITE, 27, Vector2(0, 74))
	_pad(bot_offer, 30)
	bot_offer.pressed.connect(func():
		cancel_search()
		game.start_game("duel"))
	lobby_search.add_child(UI.centered(bot_offer))
	var cancel2 := UI.button("Отмена", Color(1, 1, 1, 0.14), Color.WHITE, 30, Vector2(220, 80))
	cancel2.pressed.connect(cancel_search)
	lobby_search.add_child(UI.centered(cancel2))

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
		wait_label.text = tr("Ждём соперника") + ".".repeat(dots[0])
		search_l.text = tr("Ищем соперника") + ".".repeat(dots[0])
		if lobby_search.visible:
			var sec := int(now() - search_t0)
			search_time_l.text = "%d:%02d" % [sec / 60, sec % 60]
			bot_offer.visible = sec >= BOT_OFFER_AFTER)
	s.add_child(tm)


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func open_online() -> void:
	name_in.text = Save.player_name
	server_in.text = Save.server
	code_in.text = ""
	lobby_view("main")
	set_lobby_status("")
	update_rating_label()
	show_screen("online")
	refresh_profile()


## Состояние лобби: "main" — кнопки, "wait" — код комнаты, "search" — быстрый поиск
func lobby_view(state: String) -> void:
	lobby_main.visible = state == "main"
	lobby_wait.visible = state == "wait"
	lobby_search.visible = state == "search"
	name_in.visible = state == "main"
	if state == "search":
		search_t0 = now()
		search_time_l.text = "0:00"
		bot_offer.visible = false


func update_rating_label() -> void:
	var g := Save.rated_games
	var l := BB.league(Save.rating)
	rating_l.text = BB.league_text(Save.rating) + ("" if g == 0 else tr("  ·  боёв: %d") % g)
	rating_l.add_theme_color_override("font_color", l[3])
	# Сезон: сколько осталось и награда за текущую лигу
	if season.is_empty():
		season_l.text = ""
	else:
		var left := maxi(0, int(season.left) - int(now() - _season_t))
		season_l.text = tr("Сезон: ещё %d д. %d ч  ·  награда за лигу: 🔑×%d") % [left / 86400, left % 86400 / 3600, BB.season_keys(Save.rating)]


## Отложенный результат вызова дня — отправляем, когда сеть появилась (сервер принимает сегодня и вчера)
func flush_daily() -> void:
	var pend := Save.daily_pending
	if pend.is_empty():
		return
	var day := str(pend.get("day", ""))
	if day != BB.today() and day != BB.today(-86400):
		Save.daily_pending = {}   # слишком старый — таблица того дня уже закрыта
		return
	var nm: String = Save.player_name if Save.player_name != "" else tr("Игрок")
	var r: Dictionary = await Net.request(Save.server, {"t": "daily", "id": Save.player_id, "name": nm, "day": day, "score": int(pend.get("score", 0))}, "dailyTop", 5.0)
	if not r.is_empty() and Save.daily_pending.get("day", "") == day:
		Save.daily_pending = {}


## Рейтинг с сервера (тихо, без сообщений об ошибке)
func refresh_profile() -> void:
	var r: Dictionary = await Net.request(Save.server, {"t": "hello", "id": Save.player_id, "name": Save.player_name}, "profile", 4.0)
	if r.is_empty():
		return
	flush_daily()
	Save.rating = int(r.get("rating", Save.rating))
	Save.rated_games = int(r.get("games", Save.rated_games))
	_season_from(r)
	_latest_from(r)
	if current == "online":
		update_rating_label()


# ---------- Статистика и обновления ----------
## Обезличенное событие (запуск, сыгранная партия). Копится на телефоне и уходит, когда есть сеть.
func track(k: String, d := {}) -> void:
	d.k = k
	d.d = BB.today()
	var q: Array = Save.get_v("ev_q", [])
	q.append(d)
	if q.size() > 60:
		q = q.slice(q.size() - 60)
	Save.set_v("ev_q", q)
	flush_events()


func flush_events() -> void:
	var q: Array = Save.get_v("ev_q", [])
	if _ev_busy or q.is_empty():
		return
	_ev_busy = true
	var n := q.size()
	var r: Dictionary = await Net.request(Save.server, {"t": "ev", "id": Save.player_id, "ver": BB.BUILD,
		"plat": OS.get_name(), "lang": I18N.current(), "list": q}, "evAck", 5.0)
	_ev_busy = false
	if r.is_empty():
		return
	var cur: Array = Save.get_v("ev_q", [])
	Save.set_v("ev_q", cur.slice(n))
	_latest_from(r)


## Сервер знает сборку новее нашей — показываем кнопку обновления в меню
func _latest_from(r: Dictionary) -> void:
	var latest := int(r.get("latest", 0))
	if latest > 0 and latest != int(Save.get_v("latest", 0)):
		Save.set_v("latest", latest)
		if current == "menu":
			upd_btn.visible = latest > BB.BUILD


## Сезон из ответа сервера; если прошлый сезон закончился — награда по лиге
func _season_from(r: Dictionary) -> void:
	if r.get("season") is Dictionary:
		season = r.season
		_season_t = now()
	var rw = r.get("reward")
	if rw is Dictionary and str(rw.get("season", "")) != "":
		Net.send({"t": "rewardAck", "season": rw.season})
		if Save.get_v("season_rewarded", "") != str(rw.season):
			Save.set_v("season_rewarded", str(rw.season))
			var k := clampi(int(rw.get("keys", 0)), 0, 10)
			Missions.keys += k
			toast(tr("🏆 Сезон завершён!\nТвоя лига: %s\nНаграда: 🔑×%d") % [BB.league_text(int(rw.get("rating", 1000))), k])
			Audio.sfx("record")
			update_menu()


func quick_match() -> void:
	if not await ensure_connected():
		return
	Net.send({"t": "quick", "id": Save.player_id, "name": player_name()})


func cancel_search() -> void:
	Net.send({"t": "cancel"})
	lobby_view("main")
	set_lobby_status("")


func set_lobby_status(t: String) -> void:
	lobby_status.text = t


func player_name() -> String:
	var n := name_in.text.strip_edges().substr(0, 16)
	Save.player_name = n
	return n if n != "" else tr("Игрок")


func ensure_connected() -> bool:
	set_lobby_status("Подключаемся…")
	var err: String = await Net.connect_to(Save.server)
	if err == "":
		set_lobby_status("")
		return true
	set_lobby_status("Укажи адрес сервера внизу" if err == "nourl" else "Нет интернета или сервер недоступен.\nБез сети работают Классика, Аркада, вызов дня и бой с ботом 🤖")
	return false


func create_room() -> void:
	if not await ensure_connected():
		return
	Net.send({"t": "create", "name": player_name(), "id": Save.player_id})


func join_room() -> void:
	var code := code_in.text.strip_edges()
	if code.length() != 4:
		set_lobby_status("Введи код из 4 цифр")
		return
	if not await ensure_connected():
		return
	Net.send({"t": "join", "code": code, "name": player_name(), "id": Save.player_id})


func share_room() -> void:
	DisplayServer.clipboard_set(tr("Го в «%s» онлайн! Код комнаты: %s") % [tr(BB.GAME_NAME), lobby_code])
	set_lobby_status("Скопировано — отправь другу")


func _on_net(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	match t:
		"created":
			lobby_code = str(m.get("code", ""))
			big_code.text = lobby_code
			lobby_view("wait")
			set_lobby_status("")
			return
		"queued":
			Save.rating = int(m.get("rating", Save.rating))
			Save.rated_games = int(m.get("games", Save.rated_games))
			_season_from(m)
			update_rating_label()
			lobby_view("search")
			set_lobby_status("")
			return
		"profile", "dailyTop", "topList", "evAck":
			return   # ответы на запросы (Net.request)
		"error":
			if current == "online":
				lobby_view("main")
				set_lobby_status(tr(str(m.get("msg", "Ошибка"))))
			return
	if game.on_net(m):
		return
	if current == "online":
		if t == "oppLeft":
			lobby_view("main")
			set_lobby_status("Соперник отключился")
		elif t == "closed":
			lobby_view("main")
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
	tut_text.text = TUT[tut_step][1]   # Label переводит сам
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
