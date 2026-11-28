extends Node
## Настоящий перенос прогресса через локальный сервер: получить код, «сменить телефон», вернуть по коду.
## Запускается из tools/backup_e2e.js.

var main: Control
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


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
	await get_tree().create_timer(1.0).timeout
	main.show_screen("menu")
	# «Старый телефон»: есть прогресс
	var old_id: String = Save.player_id
	Save.best = 4242
	Save.set_v("xp", 777)
	Save.add_skin("gold")
	Save.set_level_stars(3, 2)
	main.open_backup()
	await main.do_backup(true)
	var code := str(Save.get_v("backup_code", ""))
	check(code.length() == 14 and main.bk_code_l.text == code, "код получен и показан (%s)" % ("XXXX-XXXX-XXXX" if code.length() == 14 else code))
	# «Новый телефон»: чистое сохранение с другим игроком
	Save.import_all({"pid": "f".repeat(32), "tut": true})
	check(Save.best == 0 and Save.player_id != old_id, "новый телефон: прогресса нет")
	main.open_backup()
	main.bk_in.text = "ZZZZ-ZZZZ-ZZZZ"
	main.do_restore()
	await main.do_restore()
	check(Save.best == 0 and main.bk_status.text != "", "чужой код не подходит: %s" % main.bk_status.text)
	main.bk_in.text = code.to_lower().replace("-", " ")
	main.do_restore()
	check(Save.best == 0, "первое нажатие только спрашивает подтверждение")
	await main.do_restore()
	check(Save.best == 4242 and int(Save.get_v("xp", 0)) == 777, "рекорд и опыт вернулись")
	check(Save.player_id == old_id, "вернулся тот же игрок (рейтинг переезжает вместе с ним)")
	check(Save.got().has("gold") and Save.level_stars(3) == 2, "коллекция и звёзды Аркады на месте")
	check(str(Save.get_v("backup_code", "")) == code, "код остался тем же")
	print("E2E fails=%d" % fails)
	get_tree().quit(fails)
