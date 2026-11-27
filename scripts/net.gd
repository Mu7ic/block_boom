extends Node
## Autoload "Net": WebSocket-клиент онлайн-боя. Протокол тот же, что у веб-версии (server/server.js),
## поэтому игрок из Godot может играть с игроком из браузера.
## Сообщения сервера приходят сигналом message(m); при обрыве — {t: "closed"}.

signal message(m: Dictionary)

const TIMEOUT := 6.0

var _ws: WebSocketPeer
var _open := false


func is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Подключиться; возвращает "" при успехе или текст ошибки ("nourl" / "timeout" / "error")
func connect_to(url: String) -> String:
	if url.strip_edges() == "":
		return "nourl"
	if is_open():
		return ""
	close()
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(url.strip_edges()) != OK:
		return "error"
	_ws = ws
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		if _ws != ws:
			return "error"
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			_open = true
			return ""
		if st == WebSocketPeer.STATE_CLOSED:
			_ws = null
			return "error"
		if Time.get_ticks_msec() - t0 > TIMEOUT * 1000.0:
			ws.close()
			_ws = null
			return "timeout"
	return "error"


## Отправить и дождаться ответа нужного типа (или ошибки). {} — нет связи или не дождались.
func request(url: String, m: Dictionary, want: String, timeout := 6.0) -> Dictionary:
	if await connect_to(url) != "":
		return {}
	var box := {"r": {}}
	var on := func(r: Dictionary) -> void:
		var t := str(r.get("t", ""))
		if box.r.is_empty() and (t == want or t == "error" or t == "closed"):
			box.r = r
	message.connect(on)
	send(m)
	var t0 := Time.get_ticks_msec()
	while box.r.is_empty() and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame
	message.disconnect(on)
	var r: Dictionary = box.r
	return r if str(r.get("t", "")) == want else {}


func close() -> void:
	if _ws:
		var ws := _ws
		_ws = null
		_open = false
		ws.close()


func send(m: Dictionary) -> void:
	if is_open():
		_ws.send_text(JSON.stringify(m))


func _process(_dt: float) -> void:
	if _ws == null or not _open:
		return
	_ws.poll()
	while _ws and _ws.get_available_packet_count() > 0:
		var txt := _ws.get_packet().get_string_from_utf8()
		var m = JSON.parse_string(txt)
		if m is Dictionary:
			message.emit(m)
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_open = false
		message.emit({"t": "closed"})
