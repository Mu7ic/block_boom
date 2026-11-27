extends Node
## Autoload "Audio": все звуки и музыка синтезируются кодом (как Web Audio в веб-версии), файлов нет.
## Audio.sfx("place"), Audio.clear(n, combo), Audio.buzz(30).

const RATE := 22050
const VOICES := 14
const SFX_GAIN := 1.7
const MUSIC_GAIN := 0.85
## Пентатоника — любые ноты из неё звучат приятно вместе
const PENTA := [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25, 783.99, 880.0,
	1046.5, 1174.66, 1318.51, 1567.98, 1760.0]

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _mutex := Mutex.new()
var _music: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _task := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = 0.0
	add_child(_music)
	# Синтез заранее в фоне, чтобы не было подтормаживаний при первом звуке
	_task = WorkerThreadPool.add_task(_prewarm)


func _exit_tree() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_music.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_music.stream_paused = false


# ---------- Включение/выключение ----------
func set_sound(on: bool) -> void:
	Save.sound = on


func set_music(on: bool) -> void:
	Save.music = on
	if on:
		start_music()
	else:
		_music.stop()


func start_music() -> void:
	if not Save.music or _music.playing:
		return
	if _music_stream == null:
		return   # ещё синтезируется — включится само
	_music.stream = _music_stream
	_music.play()


# ---------- Вибрация ----------
func buzz(p) -> void:
	if not Save.vibro or not OS.has_feature("mobile"):
		return
	var ms := 0
	if p is Array:
		for i in range(0, p.size(), 2):
			ms += int(p[i])
	else:
		ms = int(p)
	Input.vibrate_handheld(ms)


# ---------- Эффекты ----------
func sfx(name: String) -> void:
	if not Save.sound:
		return
	_play(name, func(): return _events(name))


## Чем больше комбо — тем выше арпеджио
func clear(n: int, combo: int) -> void:
	if not Save.sound:
		return
	var nn := mini(n, 6)
	var base := mini(combo - 1, 7)
	_play("clear_%d_%d" % [nn, base], func(): return _clear_events(nn, base))


func _play(key: String, make: Callable) -> void:
	_mutex.lock()
	var st: AudioStreamWAV = _cache.get(key)
	_mutex.unlock()
	if st == null:
		st = _render(make.call(), false)
		_mutex.lock()
		_cache[key] = st
		_mutex.unlock()
	var pl := _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = st
	pl.play()


# Событие: [тип, частота/длительность, ...] — словари как опции в веб-версии
func _t(freq: float, dur: float, o := {}) -> Dictionary:
	var d := {"k": "tone", "f": freq, "dur": dur}
	d.merge(o)
	return d


func _n(dur: float, o := {}) -> Dictionary:
	var d := {"k": "noise", "dur": dur}
	d.merge(o)
	return d


func _clear_events(n: int, base: int) -> Array:
	var ev := []
	for k in n + 2:
		ev.append(_t(PENTA[mini(base + k + 3, PENTA.size() - 1)], 0.24, {"type": "triangle", "vol": 0.2, "delay": k * 0.06}))
	ev.append(_n(0.35, {"type": "highpass", "freq": 2600.0, "vol": 0.07}))
	return ev


func _events(name: String) -> Array:
	var ev := []
	match name:
		"click":
			ev.append(_t(880, 0.05, {"type": "triangle", "vol": 0.1}))
		"pick":
			ev.append(_t(520, 0.07, {"type": "triangle", "vol": 0.16, "to": 720.0}))
		"place":
			ev.append(_t(210, 0.13, {"vol": 0.45, "to": 110.0}))
			ev.append(_n(0.05, {"freq": 900.0, "vol": 0.1}))
		"bad":
			ev.append(_t(250, 0.15, {"type": "square", "vol": 0.05, "to": 160.0}))
		"mega":
			var fs := [523.25, 659.25, 783.99, 1046.5]
			for k in fs.size():
				ev.append(_t(fs[k], 0.55, {"type": "sawtooth", "vol": 0.06, "delay": 0.12 + k * 0.05}))
				ev.append(_t(fs[k] * 2.0, 0.4, {"vol": 0.07, "delay": 0.12 + k * 0.05}))
		"skin":
			for k in 9:
				ev.append(_t(PENTA[k + 5], 0.2, {"vol": 0.11, "delay": k * 0.04}))
		"perfect":
			var fs := [523.25, 659.25, 783.99, 1046.5, 1318.51]
			for k in fs.size():
				ev.append(_t(fs[k], 0.6, {"type": "triangle", "vol": 0.12, "delay": k * 0.08}))
		"fruit":
			ev.append(_t(1318.51, 0.1, {"vol": 0.14, "to": 1760.0}))
		"refill":
			ev.append(_n(0.16, {"type": "bandpass", "freq": 1800.0, "vol": 0.05}))
		"tick":
			ev.append(_t(1100, 0.04, {"type": "square", "vol": 0.045}))
		"record":
			var fs := [659.25, 783.99, 1046.5, 1318.51]
			for k in fs.size():
				ev.append(_t(fs[k], 0.3, {"type": "triangle", "vol": 0.14, "delay": k * 0.1}))
		"win":
			var fs := [523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5]
			for k in fs.size():
				ev.append(_t(fs[k], 0.8 if k == 5 else 0.18, {"type": "triangle", "vol": 0.2, "delay": k * 0.13}))
		"lose":
			var fs := [392.0, 349.23, 311.13, 261.63]
			for k in fs.size():
				ev.append(_t(fs[k], 0.38, {"type": "triangle", "vol": 0.16, "delay": k * 0.22}))
		"stuck":
			ev.append(_t(320, 0.45, {"vol": 0.2, "to": 120.0}))
		"botClear":
			ev.append(_t(700, 0.08, {"vol": 0.04}))
		"boom":
			ev.append(_t(120, 0.5, {"vol": 0.5, "to": 45.0}))
			ev.append(_n(0.5, {"freq": 700.0, "vol": 0.25}))
	return ev


# ---------- Синтез ----------
func _render(events: Array, loop: bool, length := 0.0) -> AudioStreamWAV:
	var total := length
	if not loop:
		for e in events:
			total = maxf(total, float(e.get("delay", 0.0)) + float(e.dur) + 0.04)
	var count := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for e in events:
		if e.k == "tone":
			_add_tone(buf, e, loop)
		else:
			_add_noise(buf, e)
	var gain := MUSIC_GAIN if loop else SFX_GAIN
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var v := buf[i] * gain
		v = v / (1.0 + absf(v) * 0.6)   # мягкое ограничение вместо компрессора
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = count
	return st


func _add_tone(buf: PackedFloat32Array, e: Dictionary, wrap: bool) -> void:
	var start := int(float(e.get("delay", 0.0)) * RATE)
	var dur: float = e.dur
	var f0: float = e.f
	var to: float = e.get("to", 0.0)
	var vol: float = e.get("vol", 0.3)
	var att: float = e.get("attack", 0.006)
	var typ: String = e.get("type", "sine")
	var n := int((dur + 0.03) * RATE)
	var size := buf.size()
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0
		if to > 0.0:
			f = f0 * pow(to / f0, minf(t / dur, 1.0))
		phase += f / RATE
		phase -= floorf(phase)
		var s: float
		match typ:
			"triangle":
				s = 1.0 - 4.0 * absf(phase - 0.5)
			"square":
				s = 1.0 if phase < 0.5 else -1.0
			"sawtooth":
				s = 2.0 * phase - 1.0
			_:
				s = sin(TAU * phase)
		var env: float
		if t < att:
			env = 0.0001 * pow(vol / 0.0001, t / att)
		elif t < dur:
			env = vol * pow(0.0001 / vol, (t - att) / (dur - att))
		else:
			env = 0.0
		var idx := start + i
		if idx >= size:
			if not wrap:
				break
			idx %= size
		buf[idx] += s * env


func _add_noise(buf: PackedFloat32Array, e: Dictionary) -> void:
	var start := int(float(e.get("delay", 0.0)) * RATE)
	var n := int(float(e.dur) * RATE)
	var vol: float = e.get("vol", 0.2)
	var freq: float = minf(e.get("freq", 1200.0), RATE * 0.45)
	var typ: String = e.get("type", "lowpass")
	# Биквад-фильтр (формулы RBJ), Q ≈ 1 как у Web Audio по умолчанию
	var w0 := TAU * freq / RATE
	var alpha := sin(w0) / (2.0 * 1.0)
	var cw := cos(w0)
	var b0: float; var b1: float; var b2: float
	match typ:
		"highpass":
			b0 = (1.0 + cw) / 2.0; b1 = -(1.0 + cw); b2 = b0
		"bandpass":
			b0 = alpha; b1 = 0.0; b2 = -alpha
		_:
			b0 = (1.0 - cw) / 2.0; b1 = 1.0 - cw; b2 = b0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw
	var a2 := 1.0 - alpha
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var x := (randf() * 2.0 - 1.0) * (1.0 - float(i) / n)
		var y := (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1; x1 = x; y2 = y1; y1 = y
		buf[idx] += y * vol


# ---------- Музыка: спокойная петля C–G–Am–F ----------
func _music_events() -> Array:
	var chords := [[130.81, [261.63, 329.63, 392.0]], [98.0, [246.94, 293.66, 392.0]],
		[110.0, [261.63, 329.63, 440.0]], [87.31, [261.63, 349.23, 440.0]]]
	var order := [0, 1, 2, 1, 0, 2, 1, 2]
	var beat := 60.0 / 92.0 / 2.0
	var ev := []
	for step in 32:
		var bar := step / 8
		var s := step % 8
		var bass: float = chords[bar][0]
		var arp: Array = chords[bar][1]
		var d := step * beat
		if s == 0 or s == 4:
			ev.append(_t(bass, beat * 3.6, {"vol": 0.5, "delay": d}))
		var note: float = arp[order[s]] * (2.0 if s >= 4 else 1.0)
		ev.append(_t(note, beat * 1.7, {"type": "triangle", "vol": 0.16, "delay": d}))
	return ev


func _prewarm() -> void:
	var ms := _render(_music_events(), true, 32 * 60.0 / 92.0 / 2.0)
	call_deferred("_music_ready", ms)
	var local := {}
	for name in ["click", "pick", "place", "bad", "refill", "fruit", "tick", "botClear", "boom", "mega", "skin"]:
		local[name] = _render(_events(name), false)
	for n in range(1, 5):
		for base in 8:
			local["clear_%d_%d" % [n, base]] = _render(_clear_events(n, base), false)
	for name in ["perfect", "record", "win", "lose", "stuck"]:
		local[name] = _render(_events(name), false)
	_mutex.lock()
	for k in local:
		if not _cache.has(k):
			_cache[k] = local[k]
	_mutex.unlock()


func _music_ready(ms: AudioStreamWAV) -> void:
	_music_stream = ms
	start_music()
