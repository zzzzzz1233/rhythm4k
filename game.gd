extends Control

signal exit_requested(target: String)

# Node-based rhythm game.
# Visuals live in Game.tscn / Note.tscn so textures can be swapped in the editor.
# Drop a texture into any exported slot to replace the generated placeholder art.

const LANES := 4
const KEY_CODES := [KEY_D, KEY_F, KEY_J, KEY_K]
const BASE_H := 720.0
const HIT_OFFSET := 100.0
const LEAD_IN := 3.0
const PPS_PER_SV := 120.0
const FLICK_DISTANCE := 64.0
const TOP_TAPER := 0.24
const NOTE_SCENE := "res://Note.tscn"

const NOTE_TEX_DIR := "res://assets/notes/"
const NOTE_TEX_FILES := ["note_blue.png", "note_green.png", "note_orange.png", "note_purple.png", "note_red.png"]
const NOTE_TEX_YELLOW := "res://assets/notes/note_yellow.png"
const PAD_TEX_IDLE := "res://assets/pads/pad_idle.png"
const PAD_TEX_PRESS := "res://assets/pads/pad_press.png"
const COMBO_YELLOW_THRESHOLD := 40
const PAD_SIZE_RATIO := 1.05
const LANE_STRIPES := 3
const LANE_STRIPE_SPAN := 0.25
const LANE_STRIPE_COLORS := [
	Color(0.0, 0.0, 0.0, 0.85),
	Color(1.0, 1.0, 1.0, 0.72),
	Color(0.0, 0.0, 0.0, 0.85),
]
const GAME_BG_TEX := "res://assets/backgrounds/game_bg.jpg"
const GAME_BG_ALPHA := 0.4

const HIT_WINDOW := 0.20
const W_PERFECT := 0.06
const W_GREAT := 0.12
const W_GOOD := 0.20

@export var background_texture: Texture2D
@export var note_texture: Texture2D
@export var tail_texture: Texture2D
@export var pad_texture: Texture2D
@export var hit_texture: Texture2D
@export var lane_colors: Array[Color] = [
	Color("#ff5d7a"),
	Color("#ffc24b"),
	Color("#4fd1c5"),
	Color("#7aa2ff"),
]

@onready var _bg: TextureRect = $Background
@onready var _lane_layer: Node2D = $LaneLayer
@onready var _note_layer: Node2D = $NoteLayer
@onready var _effect_layer: Node2D = $EffectLayer
@onready var _hud: Control = $HUD

var scroll_speed_multiplier := 5.0
var track_width_ratio := 0.6
var audio_offset := 0.0
var _current_speed := 5.0

var _notes: Array = []
var _song_time := -LEAD_IN
var _last_note_end := 0.0
var _started := false
var _paused := false
var _finished := false
var _audio_ready := false

var _player: AudioStreamPlayer
var _hit_players: Array = []
var _hit_stream: AudioStreamWAV
var _hit_index := 0

var _held := [false, false, false, false]
var _flash := [0.0, 0.0, 0.0, 0.0]
var _hold_active := [false, false, false, false]
var _drag_y := [0.0, 0.0, 0.0, 0.0]
var _touch_lane := {}
var _miss_flash := 0.0

var _lane_stripes: Array = []
var _lane_top_points: Array = []
var _lane_bottom_points: Array = []
var _pads: Array = []
var _note_pool: Array = []
var _lane_tails: Array = []
var _last_press_msec := [-1000, -1000, -1000, -1000]
var _fx: Array = []
var _fx_life: Array = []
var _fx_color: Array = []
var _hit_flash := 0.0
var _hit_flash_color := Color.WHITE
var _lead_start_usec := 0
var _hit_line: ColorRect
var _miss_edges: Array = []
var _note_scene: PackedScene
var _note_textures: Array = []
var _note_yellow: Texture2D
var _yellow_mode := false
var _pad_idle: Texture2D
var _pad_press: Texture2D
var _disc_tex: ImageTexture

var _score := 0
var _combo := 0
var _max_combo := 0
var _counts := {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0}
var _accuracy := 100.0

var _song_title := ""
var _difficulty := ""

var _score_label: Label
var _time_label: Label
var _combo_label: Label
var _acc_label: Label
var _title_label: Label
var _hint_label: Label
var _pause_btn: Button

var _pause_panel: Control
var _slider: HSlider
var _speed_value: Label
var _result_panel: Control
var _result_info: Label

var _popup_text := ""
var _popup_lane := 0
var _popup_left := 0.0
var _popup_color := Color.WHITE
var _popup_label: Label


func _ready() -> void:
	Engine.max_fps = 0
	Input.set_emulate_mouse_from_touch(true)
	scroll_speed_multiplier = GameConfig.scroll_speed_multiplier
	track_width_ratio = GameConfig.track_width_ratio
	audio_offset = GameConfig.audio_offset
	_current_speed = scroll_speed_multiplier
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_note_scene = load(NOTE_SCENE)
	_load_note_textures()
	_load_pad_textures()
	_prewarm_notes(128)
	_disc_tex = _make_disc_texture(128)
	var bg_tex: Texture2D = background_texture
	if bg_tex == null:
		bg_tex = load(GAME_BG_TEX)
	if bg_tex != null:
		_bg.texture = bg_tex
		_bg.modulate = Color(1.0, 1.0, 1.0, GAME_BG_ALPHA)
	_build_lanes()
	_build_effect_pool()
	_build_hud()
	_build_audio()
	resized.connect(_apply_layout)
	call_deferred("_apply_layout")


func start_chart(folder: String, diff: String) -> void:
	print("=== start_chart ===")
	print("  folder: ", folder)
	print("  diff:   ", diff)
	var chart_path := GameConfig.chart_path(folder, diff)
	var audio_path := GameConfig.audio_path(folder)
	print("  chart_path: ", chart_path)
	print("  audio_path: ", audio_path)
	_difficulty = diff
	_load_chart(chart_path)
	print("  notes: ", _notes.size(), "  last_note_end: ", _last_note_end)
	_load_audio(audio_path)
	print("  audio_ready: ", _audio_ready)
	if _notes.is_empty() or _last_note_end <= 0.0:
		push_error("Aborting: chart has no notes (" + chart_path + ")")
		exit_requested.emit("diff")
		return
	if not _audio_ready:
		push_error("Aborting: audio failed to load (" + audio_path + ")")
		exit_requested.emit("diff")
		return
	_restart_state()
	if _title_label != null:
		_title_label.text = "%s   [%s]" % [_song_title, _difficulty]

func _load_chart(path: String) -> void:
	_notes.clear()
	_last_note_end = 0.0
	print("Chart load: ", path, " exists=", FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		push_error("Chart not found: " + path)
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Chart is empty: " + path)
		return
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Chart is not a JSON object: " + path)
		return
	var meta: Dictionary = data.get("metadata", {})
	_song_title = str(meta.get("title_unicode", meta.get("title", "")))
	if meta.has("offset"):
		audio_offset = clampf(float(meta.get("offset", 0.0)), -0.2, 0.2)
		GameConfig.audio_offset = audio_offset
		GameConfig.save_settings()
	var arr: Array = data.get("notes", [])
	for item in arr:
		if not item is Dictionary:
			continue
		var t := float(item.get("time", 0.0))
		var lane := clampi(int(item.get("lane", 0)), 0, LANES - 1)
		var typ := str(item.get("type", "tap"))
		var end_t := float(item.get("end_time", t))
		var hold := 0.0
		if typ == "hold" and end_t > t:
			hold = end_t - t
		_notes.append({"t": t, "lane": lane, "hold": hold, "state": 0, "dt": 0.0, "node": null, "hold_active": false, "flicked": false, "tail_line": null, "tex": randi() % NOTE_TEX_FILES.size()})
		_last_note_end = maxf(_last_note_end, t + hold)
	print("Chart loaded: %s  notes=%d  last=%.2fs" % [path, _notes.size(), _last_note_end])


func _load_audio(path: String) -> void:
	if _player != null:
		_player.queue_free()
		_player = null
	_audio_ready = false
	var stream: AudioStream = null
	print("Audio load: ", path, " exists=", FileAccess.file_exists(path))
	if path.begins_with("res://"):
		stream = load(path) as AudioStream
	else:
		if not FileAccess.file_exists(path):
			push_error("Audio not found: " + path)
			return
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			push_error("Audio file is empty: " + path)
			return
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	print("Audio stream: ", stream)
	if stream == null:
		push_error("Failed to load audio: " + path)
		return
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.bus = "Master"
	add_child(_player)
	_player.stream = stream
	_audio_ready = true
	print("Audio loaded: %s  length=%.2fs" % [path, stream.get_length()])


func _load_note_textures() -> void:
	_note_textures.clear()
	for file_name in NOTE_TEX_FILES:
		var tex: Texture2D = load(NOTE_TEX_DIR + file_name)
		if tex != null:
			_note_textures.append(tex)
	_note_yellow = load(NOTE_TEX_YELLOW)


func _load_pad_textures() -> void:
	_pad_idle = load(PAD_TEX_IDLE)
	_pad_press = load(PAD_TEX_PRESS)


func _texture_for(n) -> Texture2D:
	if _yellow_mode:
		return _note_yellow
	if _note_textures.is_empty():
		return null
	return _note_textures[int(n.tex) % _note_textures.size()]


func _update_note_textures() -> void:
	var want_yellow := _combo >= COMBO_YELLOW_THRESHOLD
	if want_yellow == _yellow_mode:
		return
	_yellow_mode = want_yellow
	for n in _notes:
		if n.node != null:
			n.node.set_note_texture(_texture_for(n))


func _prewarm_notes(count: int) -> void:
	if _note_scene == null:
		return
	for i in count:
		var node: Node2D = _note_scene.instantiate()
		node.visible = false
		_note_layer.add_child(node)
		_note_pool.append(node)


func _build_lanes() -> void:
	for i in range(LANES):
		for s in range(LANE_STRIPES):
			var stripe := Polygon2D.new()
			stripe.name = "Lane%dStripe%d" % [i, s]
			stripe.color = LANE_STRIPE_COLORS[s]
			stripe.antialiased = true
			stripe.z_index = -100
			_lane_layer.add_child(stripe)
			_lane_stripes.append(stripe)

	for i in range(LANES):
		var pad := Sprite2D.new()
		pad.name = "Pad%d" % i
		pad.texture = pad_texture if pad_texture != null else _pad_idle
		pad.modulate = lane_colors[i]
		_lane_layer.add_child(pad)
		_pads.append(pad)

	_hit_line = ColorRect.new()
	_hit_line.name = "HitLine"
	_hit_line.color = Color(1, 1, 1, 0.16)
	_hit_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lane_layer.add_child(_hit_line)

	_lane_tails.clear()
	for i in range(LANES):
		var tail := Line2D.new()
		tail.name = "LaneTail%d" % i
		tail.width = _px(20.0)
		tail.default_color = Color(lane_colors[i].r, lane_colors[i].g, lane_colors[i].b, 0.65)
		tail.antialiased = true
		tail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		tail.end_cap_mode = Line2D.LINE_CAP_ROUND
		tail.z_index = 0
		tail.visible = false
		_lane_layer.add_child(tail)
		_lane_tails.append(tail)

func _build_hud() -> void:
	_build_miss_overlay()
	_score_label = Label.new()
	_score_label.add_theme_color_override("font_color", Color("#e8eefc"))
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_score_label)

	_time_label = Label.new()
	_time_label.add_theme_color_override("font_color", Color("#9fb0c9"))
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_time_label)

	_combo_label = Label.new()
	_combo_label.anchor_right = 1.0
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_color_override("font_color", Color("#ffffff"))
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_combo_label)

	_acc_label = Label.new()
	_acc_label.anchor_left = 1.0
	_acc_label.anchor_right = 1.0
	_acc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_acc_label.add_theme_color_override("font_color", Color("#8a97ad"))
	_acc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_acc_label)

	_popup_label = Label.new()
	_popup_label.anchor_left = 0.0
	_popup_label.anchor_right = 1.0
	_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_label.add_theme_color_override("font_color", Color("#8ef7c6"))
	_popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_label.visible = false
	_hud.add_child(_popup_label)

	_title_label = Label.new()
	_title_label.anchor_top = 1.0
	_title_label.anchor_bottom = 1.0
	_title_label.add_theme_color_override("font_color", Color("#5b6a80"))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.text = "D F J K   /   HOLD OR FLICK UP   /   ESC PAUSE"
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.add_theme_color_override("font_color", Color("#3d4a5e"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint_label)

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(_pause)
	_hud.add_child(_pause_btn)

	_build_pause_panel()
	_build_result_panel()


func _build_audio() -> void:
	_hit_stream = _make_click()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.name = "Hit%d" % i
		p.bus = "Master"
		p.stream = _hit_stream
		add_child(p)
		_hit_players.append(p)


func _make_click() -> AudioStreamWAV:
	var rate := 44100
	var frames := int(rate * 0.05)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 90.0)
		var s := sin(TAU * 1700.0 * t) * 0.65 + sin(TAU * 3400.0 * t) * 0.25
		var v := int(clampf(s * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _play_hit() -> void:
	if _hit_players.is_empty():
		return
	var p: AudioStreamPlayer = _hit_players[_hit_index % _hit_players.size()]
	_hit_index += 1
	p.play()


func _physics_process(delta: float) -> void:
	if _paused or _finished:
		return

	if not _started:
		_song_time = -LEAD_IN + float(Time.get_ticks_usec() - _lead_start_usec) / 1000000.0
		if _song_time >= 0.0:
			_song_time = 0.0
			_started = true
			if _player != null and _audio_ready:
				_player.play()
	else:
		if _player != null and _audio_ready and _player.playing:
			_song_time += delta
			var raw := _audio_time()
			var drift := raw - _song_time
			if absf(drift) > 2.0:
				_song_time = raw
			else:
				_song_time += drift * 0.08
		else:
			_song_time += delta

	_current_speed = lerpf(_current_speed, scroll_speed_multiplier, clampf(delta * 6.0, 0.0, 1.0))

	for i in range(LANES):
		_flash[i] = maxf(0.0, _flash[i] - delta * 6.0)
	_miss_flash = maxf(0.0, _miss_flash - delta * 2.5)
	_popup_left = maxf(0.0, _popup_left - delta)

	_update_note_textures()
	_update_notes()
	_update_note_nodes()
	_update_pads()
	_update_effects(delta)
	_update_hit_line(delta)
	_update_popup()
	_update_miss_flash()

	if _started and _should_finish():
		_finish()

	_update_hud()

func _should_finish() -> bool:
	if not _started:
		return false
	if _notes.is_empty() or _last_note_end <= 0.0:
		return false
	if _song_time > _last_note_end + 15.0:
		push_warning("Song finish safety net triggered at %.2fs" % _song_time)
		return true
	if _player != null and _player.playing:
		return false
	for n in _notes:
		if n.state != 2:
			return false
	return true

func _audio_time() -> float:
	var t := _player.get_playback_position()
	t += AudioServer.get_time_since_last_mix()
	t -= AudioServer.get_output_latency()
	t += audio_offset
	return maxf(-1.0, t)


func _gui_input(event: InputEvent) -> void:
	if _paused or _finished:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			var lane := _lane_at_position(event.position)
			_touch_lane[event.index] = lane
			_drag_y[lane] = 0.0
			_press_lane(lane)
		else:
			if _touch_lane.has(event.index):
				var lane: int = _touch_lane[event.index]
				_touch_lane.erase(event.index)
				_release_lane(lane)
		accept_event()
	elif event is InputEventScreenDrag:
		if _touch_lane.has(event.index):
			var lane: int = _touch_lane[event.index]
			_track_drag(lane, event.relative.y)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var lane := _lane_at_position(event.position)
		_drag_y[lane] = 0.0
		if event.pressed:
			_press_lane(lane)
		else:
			_release_lane(lane)
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var lane := _lane_at_position(event.position)
		_track_drag(lane, event.relative.y)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	if key.pressed and key.keycode == KEY_ESCAPE:
		if _paused:
			_resume()
		elif not _finished:
			_pause()
		return
	if key.pressed and key.keycode == KEY_R:
		_restart()
		return
	for i in range(LANES):
		if key.keycode == KEY_CODES[i]:
			if key.pressed:
				_press_lane(i)
			else:
				_release_lane(i)


func _track_drag(lane: int, dy: float) -> void:
	if dy >= 0.0:
		return
	_drag_y[lane] += dy
	if _drag_y[lane] <= -_px(FLICK_DISTANCE):
		_drag_y[lane] = 0.0
		_flick_lane(lane)


func _flick_lane(lane: int) -> void:
	_flash[lane] = 1.0
	_pulse_hit_line(lane)
	var best = null
	for n in _notes:
		if n.lane == lane and n.state == 1:
			best = n
			break
	if best == null:
		for n in _notes:
			if n.lane == lane and n.state == 0 and n.hold > 0.0 and absf(_song_time - n.t) <= HIT_WINDOW:
				n.dt = _song_time - n.t
				best = n
				break
	if best == null:
		return
	if best.state == 0:
		best.state = 1
		best.hold_active = true
		_judge_hold_head(best, absf(best.dt))
	_flick_hold(best)

func _press_lane(lane: int) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_press_msec[lane]) < 25:
		return
	_last_press_msec[lane] = now
	_held[lane] = true
	_flash[lane] = 1.0
	_pulse_hit_line(lane)
	if _paused or _finished:
		return
	var best = null
	var best_dt := HIT_WINDOW + 1.0
	for n in _notes:
		if n.lane != lane or n.state != 0:
			continue
		var dt: float = absf(_song_time - n.t)
		if dt <= HIT_WINDOW and dt < best_dt:
			best_dt = dt
			best = n
	if best == null:
		return
	best.dt = _song_time - best.t
	if best.hold > 0.0:
		best.state = 1
		best.hold_active = true
		_hold_active[lane] = true
		_judge_hold_head(best, best_dt)
	else:
		best.state = 2
		_grade(best, best_dt)

func _release_lane(lane: int) -> void:
	_held[lane] = false
	_drag_y[lane] = 0.0


func _update_notes() -> void:
	for n in _notes:
		if n.state == 0:
			if _song_time > n.t + HIT_WINDOW:
				_miss(n)
		elif n.state == 1:
			if _song_time >= n.t + n.hold:
				_finish_hold(n)
			elif not _held[n.lane]:
				_release_hold_visual(n)
		elif n.state == 3:
			if _song_time >= n.t + n.hold:
				n.state = 2
				if n.node != null:
					n.node.visible = false

func _update_note_nodes() -> void:
	var speed := _note_speed()
	var hy := _hit_y()
	for t in _lane_tails:
		t.visible = false
	for n in _notes:
		if n.state == 2:
			if n.node != null:
				n.node.hide_tail_immediate()
				_release_note(n.node)
				n.node = null
			continue
		if n.state == 1:
			if n.node != null:
				n.node.visible = false
			var remain: float = maxf(0.0, (n.t + n.hold) - _song_time)
			_update_hold_tail(n, hy, remain * speed)
			continue
		var y: float = hy - (n.t - _song_time) * speed
		if y < -2000.0:
			continue
		if y > size.y + 2000.0:
			if n.node != null:
				n.node.visible = false
			continue
		if n.node == null:
			n.node = _spawn_note(n)
		n.node.position = _lane_point(y, n.lane)
		n.node.set_note_diameter((_track_width_at(y) / 4.0) * 0.9)
		n.node.set_tail_length(0.0)
		n.node.hide_tail_immediate()
		if n.state == 3:
			n.node.visible = false
			var tail_len: float = maxf(0.0, (n.t + n.hold) - _song_time) * speed
			var top_y := y - tail_len
			var bottom_y := minf(y, hy)
			if top_y < hy:
				_update_hold_tail(n, bottom_y, bottom_y - top_y)
		else:
			n.node.visible = true
			n.node.set_hold_glow(false)
			if n.hold > 0.0:
				_update_hold_tail(n, y, n.hold * speed)

func _update_hold_tail(n, head_y: float, tail_len: float) -> void:
	if tail_len <= 2.0:
		return
	var line: Line2D = _lane_tails[n.lane]
	var top_y := head_y - tail_len
	line.points = PackedVector2Array([
		_lane_point(top_y, n.lane),
		_lane_point(head_y, n.lane),
	])
	line.width = _px(20.0)
	line.visible = true

func _hide_tail(_n) -> void:
	pass

func _hide_tail_now(_n) -> void:
	pass

func _spawn_note(n) -> Node2D:
	var node: Node2D = null
	if not _note_pool.is_empty():
		node = _note_pool.pop_back()
	else:
		if _note_scene == null:
			return null
		node = _note_scene.instantiate()
		_note_layer.add_child(node)
	if node.has_method("set_note_texture"):
		node.set_note_texture(_texture_for(n))
	if node.has_method("set_mirror"):
		node.set_mirror(n.lane >= LANES / 2)
	if tail_texture != null and "tail_texture" in node:
		node.tail_texture = tail_texture
	node.setup(lane_colors[n.lane], n.hold)
	node.set_note_diameter(48.0)
	node.set_tail_length(0.0)
	node.set_hold_glow(false)
	node.visible = true
	if node.has_method("reset_physics_interpolation"):
		node.reset_physics_interpolation()
	return node


func _release_note(node: Node2D) -> void:
	if node == null:
		return
	node.visible = false
	if node.has_method("set_tail_length"):
		node.set_tail_length(0.0)
	if not _note_pool.has(node):
		_note_pool.append(node)


func _update_pads() -> void:
	var pad_diameter := (_track_width_at(_hit_y()) / float(LANES)) * PAD_SIZE_RATIO
	for i in range(LANES):
		if _pads[i].texture == null:
			continue
		var fl: float = _flash[i]
		var active: bool = _held[i] or _hold_active[i] or fl > 0.05
		var want: Texture2D = _pad_idle
		if active and _pad_press != null:
			want = _pad_press
		if want != null and _pads[i].texture != want:
			_pads[i].texture = want
		var tex_w := float(_pads[i].texture.get_width())
		if tex_w <= 0.0:
			continue
		var base := pad_diameter / tex_w
		_pads[i].modulate = Color(1.0, 1.0, 1.0, 1.0)
		_pads[i].scale = Vector2.ONE * base * (1.0 + 0.08 * fl)

func _update_popup() -> void:
	if _popup_label == null:
		return
	if _popup_left <= 0.0:
		_popup_label.visible = false
		return
	_popup_label.visible = true
	_popup_label.modulate = Color(1, 1, 1, clampf(_popup_left / 0.55, 0.0, 1.0))


func _pulse_hit_line(lane: int) -> void:
	if _hit_line == null:
		return
	_hit_flash = 1.0
	_hit_flash_color = lane_colors[lane]
	_hit_line.modulate = _hit_flash_color
	_hit_line.scale = Vector2(1.0, 2.6)

func _build_effect_pool() -> void:
	_fx.clear()
	_fx_life.clear()
	_fx_color.clear()
	for i in 24:
		var s := Sprite2D.new()
		s.name = "Fx%d" % i
		s.texture = hit_texture
		s.visible = false
		s.z_index = 4
		_effect_layer.add_child(s)
		_fx.append(s)
		_fx_life.append(0.0)
		_fx_color.append(Color.WHITE)


func _spawn_hit_effect(lane: int, color: Color) -> void:
	for i in _fx.size():
		if _fx_life[i] <= 0.0:
			var s: Sprite2D = _fx[i]
			s.position = _lane_point(_hit_y(), lane)
			s.scale = Vector2(0.35, 0.35)
			s.modulate = Color(color.r, color.g, color.b, 0.95)
			s.visible = true
			_fx_life[i] = 0.28
			_fx_color[i] = color
			return


func _update_effects(delta: float) -> void:
	for i in _fx.size():
		if _fx_life[i] <= 0.0:
			continue
		_fx_life[i] -= delta
		var s: Sprite2D = _fx[i]
		if _fx_life[i] <= 0.0:
			s.visible = false
			continue
		var t: float = 1.0 - (float(_fx_life[i]) / 0.28)
		s.scale = Vector2.ONE * lerpf(0.35, 2.4, t)
		var c: Color = _fx_color[i]
		s.modulate = Color(c.r, c.g, c.b, 0.95 * (1.0 - t))


func _update_hit_line(delta: float) -> void:
	if _hit_line == null:
		return
	if _hit_flash <= 0.0:
		_hit_line.modulate = Color(1, 1, 1, 0.16)
		_hit_line.scale = Vector2.ONE
		return
	_hit_flash = maxf(0.0, _hit_flash - delta / 0.28)
	var t := 1.0 - _hit_flash
	_hit_line.scale = Vector2(1.0, lerpf(2.6, 1.0, t))
	_hit_line.modulate = Color(_hit_flash_color.r, _hit_flash_color.g, _hit_flash_color.b, lerpf(1.0, 0.16, t))

func _judge_hold_head(n, adt: float) -> void:
	var g := "GOOD"
	var pts := 40
	if adt <= W_PERFECT:
		g = "PERFECT"
		pts = 100
	elif adt <= W_GREAT:
		g = "GREAT"
		pts = 70
	_counts[g] = int(_counts[g]) + 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_score += pts + mini(_combo, 100) * 2
	_play_hit()
	_spawn_hit_effect(n.lane, _grade_color(g))
	_pulse_hit_line(n.lane)
	_show_popup(g, n.lane, _grade_color(g))
	_update_accuracy()


func _flick_hold(n) -> void:
	n.hold_active = false
	n.flicked = true
	n.state = 3
	_hold_active[n.lane] = false
	_held[n.lane] = false
	_drag_y[n.lane] = 0.0
	_score += 120
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_play_hit()
	_spawn_hit_effect(n.lane, Color("#8ef7c6"))
	_show_popup("PERFECT", n.lane, Color("#8ef7c6"))


func _release_hold_visual(n) -> void:
	n.hold_active = false
	n.state = 3
	_hold_active[n.lane] = false
	_held[n.lane] = false


func _finish_hold(n) -> void:
	n.hold_active = false
	n.state = 2
	_hide_tail(n)
	_hold_active[n.lane] = false
	if n.node != null:
		n.node.set_tail_length(0.0)
		n.node.visible = false

func _grade(n, adt: float) -> void:
	var g := "GOOD"
	var pts := 40
	if adt <= W_PERFECT:
		g = "PERFECT"
		pts = 100
	elif adt <= W_GREAT:
		g = "GREAT"
		pts = 70
	_counts[g] = int(_counts[g]) + 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_score += pts + mini(_combo, 100) * 2
	_play_hit()
	_spawn_hit_effect(n.lane, _grade_color(g))
	_pulse_hit_line(n.lane)
	_show_popup(g, n.lane, _grade_color(g))
	_update_accuracy()


func _grade_color(g: String) -> Color:
	if g == "PERFECT":
		return Color("#8ef7c6")
	if g == "GREAT":
		return Color("#7ac8ff")
	return Color("#ffd166")


func _miss(n) -> void:
	n.state = 2
	_hold_active[n.lane] = false
	_counts["MISS"] = int(_counts["MISS"]) + 1
	_combo = 0
	_miss_flash = 1.0
	_show_popup("MISS", n.lane, Color("#ff5d7a"))
	_update_accuracy()


func _update_accuracy() -> void:
	var total := 0
	for k in _counts:
		total += int(_counts[k])
	if total <= 0:
		_accuracy = 100.0
		return
	var weighted: float = float(_counts["PERFECT"]) * 1.0
	weighted += float(_counts["GREAT"]) * 0.7
	weighted += float(_counts["GOOD"]) * 0.4
	_accuracy = weighted / float(total) * 100.0


func _show_popup(text: String, lane: int, color: Color) -> void:
	if _popup_label == null:
		return
	_popup_text = text
	_popup_lane = lane
	_popup_color = color
	_popup_left = 0.55
	_popup_label.text = text
	_popup_label.add_theme_color_override("font_color", color)
	_popup_label.visible = true


func _update_hud() -> void:
	if _score_label == null:
		return
	_score_label.text = "%07d" % _score
	var shown := maxf(0.0, _song_time)
	_time_label.text = "%d:%02d" % [int(shown) / 60, int(shown) % 60]
	if _combo >= 2:
		_combo_label.text = "%d COMBO" % _combo
	else:
		_combo_label.text = ""
	_acc_label.text = "%.1f%%" % _accuracy


func _panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	return s


func _make_button(text_value: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(330, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _panel_style(Color("#1b2230"), 12))
	b.add_theme_stylebox_override("hover", _panel_style(Color("#2a3550"), 12))
	b.add_theme_stylebox_override("pressed", _panel_style(Color("#111826"), 12))
	b.add_theme_color_override("font_color", Color("#e8eefc"))
	return b


func _build_miss_overlay() -> void:
	_miss_edges.clear()
	for i in 4:
		var r := ColorRect.new()
		r.name = "MissEdge%d" % i
		r.color = Color(1, 0.1, 0.2, 0.0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(r)
		_miss_edges.append(r)


func _update_miss_flash() -> void:
	var a: float = _miss_flash * 0.35
	for r in _miss_edges:
		r.color = Color(1, 0.1, 0.2, a)


func _build_pause_panel() -> void:
	_pause_panel = Control.new()
	_pause_panel.visible = false
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pause_panel)
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	_pause_panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var center := CenterContainer.new()
	margin.add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	col.add_child(title)

	_speed_value = Label.new()
	_speed_value.text = "SCROLL SPEED  %.1f" % scroll_speed_multiplier
	_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_value.add_theme_font_size_override("font_size", 20)
	_speed_value.add_theme_color_override("font_color", Color("#9fb0c9"))
	col.add_child(_speed_value)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 28.0
	_slider.step = 0.1
	_slider.custom_minimum_size = Vector2(520, 56)
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.set_value_no_signal(scroll_speed_multiplier)
	_slider.value_changed.connect(_on_speed_changed)
	col.add_child(_slider)

	var width_label := Label.new()
	width_label.name = "WidthLabel"
	width_label.text = "TRACK WIDTH  %.2f" % track_width_ratio
	width_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	width_label.add_theme_font_size_override("font_size", 20)
	width_label.add_theme_color_override("font_color", Color("#9fb0c9"))
	col.add_child(width_label)

	var width_slider := HSlider.new()
	width_slider.min_value = 0.4
	width_slider.max_value = 1.0
	width_slider.step = 0.02
	width_slider.custom_minimum_size = Vector2(520, 56)
	width_slider.focus_mode = Control.FOCUS_NONE
	width_slider.set_value_no_signal(track_width_ratio)
	width_slider.value_changed.connect(_on_track_width_changed)
	col.add_child(width_slider)


	var offset_label := Label.new()
	offset_label.name = "OffsetLabel"
	offset_label.text = "AUDIO OFFSET  %+.2fs" % audio_offset
	offset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offset_label.add_theme_font_size_override("font_size", 20)
	offset_label.add_theme_color_override("font_color", Color("#9fb0c9"))
	col.add_child(offset_label)

	var offset_slider := HSlider.new()
	offset_slider.name = "OffsetSlider"
	offset_slider.min_value = -0.2
	offset_slider.max_value = 0.2
	offset_slider.step = 0.01
	offset_slider.custom_minimum_size = Vector2(520, 56)
	offset_slider.focus_mode = Control.FOCUS_NONE
	offset_slider.set_value_no_signal(audio_offset)
	offset_slider.value_changed.connect(_on_audio_offset_changed)
	col.add_child(offset_slider)

	var resume := _make_button("CONTINUE", 22)
	resume.pressed.connect(_resume)
	col.add_child(resume)

	var restart := _make_button("RESTART", 22)
	restart.pressed.connect(_restart)
	col.add_child(restart)

	var back := _make_button("EXIT TO SONG SELECT", 22)
	back.pressed.connect(_exit_to_menu.bind("songs"))
	col.add_child(back)


func _build_result_panel() -> void:
	_result_panel = Control.new()
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_result_panel)
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.90)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_panel.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_result_panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)

	var title := Label.new()
	title.text = "RESULT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	col.add_child(title)

	_result_info = Label.new()
	_result_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_info.add_theme_font_size_override("font_size", 24)
	_result_info.add_theme_color_override("font_color", Color("#c9d6ea"))
	col.add_child(_result_info)

	var restart := _make_button("RESTART", 22)
	restart.pressed.connect(_restart)
	col.add_child(restart)

	var back := _make_button("BACK TO DIFFICULTY", 22)
	back.pressed.connect(_exit_to_menu.bind("diff"))
	col.add_child(back)


func _on_speed_changed(value: float) -> void:
	if not _paused:
		return
	scroll_speed_multiplier = value
	GameConfig.scroll_speed_multiplier = value
	GameConfig.save_settings()
	_speed_value.text = "SCROLL SPEED  %.1f" % value



func _on_track_width_changed(value: float) -> void:
	if not _paused:
		return
	track_width_ratio = clampf(value, 0.4, 1.0)
	GameConfig.track_width_ratio = track_width_ratio
	GameConfig.save_settings()
	var label := _pause_panel.find_child("WidthLabel", true, false) as Label
	if label != null:
		label.text = "TRACK WIDTH  %.2f" % track_width_ratio
	_update_track_geometry()


func _on_audio_offset_changed(value: float) -> void:
	if not _paused:
		return
	var delta_offset := value - audio_offset
	audio_offset = clampf(value, -0.2, 0.2)
	_song_time += delta_offset
	GameConfig.audio_offset = audio_offset
	GameConfig.save_settings()
	var label := _pause_panel.find_child("OffsetLabel", true, false) as Label
	if label != null:
		label.text = "AUDIO OFFSET  %+.2fs" % audio_offset


func _pause() -> void:
	if _paused or _finished:
		return
	_paused = true
	if _player != null:
		_player.stream_paused = true
	for i in range(LANES):
		_held[i] = false
		_hold_active[i] = false
		_drag_y[i] = 0.0
	_slider.set_value_no_signal(scroll_speed_multiplier)
	_speed_value.text = "SCROLL SPEED  %.1f" % scroll_speed_multiplier
	var offset_slider := _pause_panel.find_child("OffsetSlider", true, false) as HSlider
	if offset_slider != null:
		offset_slider.set_value_no_signal(audio_offset)
	var offset_label := _pause_panel.find_child("OffsetLabel", true, false) as Label
	if offset_label != null:
		offset_label.text = "AUDIO OFFSET  %+.2fs" % audio_offset
	_pause_panel.visible = true


func _resume() -> void:
	if not _paused:
		return
	_paused = false
	if _player != null:
		_player.stream_paused = false
	_pause_panel.visible = false


func _restart() -> void:
	_restart_state()
	if _title_label != null:
		_title_label.text = "%s   [%s]" % [_song_title, _difficulty]


func _exit_to_menu(target: String) -> void:
	if _player != null:
		_player.stop()
	exit_requested.emit(target)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _player != null:
		_player.stop()
	_pause_panel.visible = false
	var rating := "C"
	if _accuracy >= 95.0:
		rating = "S"
	elif _accuracy >= 90.0:
		rating = "A"
	elif _accuracy >= 80.0:
		rating = "B"
	_result_info.text = "RATING       %s\nSCORE        %d\nMAX COMBO    %d\nACCURACY     %.1f%%\n\nPERFECT  %d    GREAT  %d\nGOOD  %d    MISS  %d" % [
		rating,
		_score,
		_max_combo,
		_accuracy,
		int(_counts["PERFECT"]),
		int(_counts["GREAT"]),
		int(_counts["GOOD"]),
		int(_counts["MISS"]),
	]
	_result_panel.visible = true

func _restart_state() -> void:
	for n in _notes:
		_hide_tail_now(n)
		if n.node != null:
			_release_note(n.node)
			n.node = null
		n.state = 0
		n.dt = 0.0
		n.hold_active = false
		n.flicked = false
	_song_time = -LEAD_IN
	_lead_start_usec = Time.get_ticks_usec()
	_started = false
	_paused = false
	_finished = false
	_score = 0
	_combo = 0
	_max_combo = 0
	_counts = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0}
	_accuracy = 100.0
	_popup_left = 0.0
	_miss_flash = 0.0
	_current_speed = scroll_speed_multiplier
	_touch_lane.clear()
	for i in range(LANES):
		_held[i] = false
		_flash[i] = 0.0
		_hold_active[i] = false
		_drag_y[i] = 0.0
	if _player != null:
		_player.stop()
		_player.stream_paused = false
	if _pause_panel != null:
		_pause_panel.visible = false
	if _result_panel != null:
		_result_panel.visible = false
	if _popup_label != null:
		_popup_label.visible = false
	_update_hud()


func _apply_layout() -> void:
	_update_track_geometry()
	for i in range(mini(_lane_tails.size(), LANES)):
		_lane_tails[i].width = _px(20.0)

	_score_label.position = Vector2(_px(26), _px(8))
	_score_label.add_theme_font_size_override("font_size", int(_px(30)))
	_time_label.position = Vector2(_px(26), _px(44))
	_time_label.add_theme_font_size_override("font_size", int(_px(20)))
	_combo_label.offset_top = _px(8)
	_combo_label.offset_bottom = _px(8) + _px(46)
	_combo_label.add_theme_font_size_override("font_size", int(_px(32)))
	_acc_label.offset_left = -_px(330)
	_acc_label.offset_right = -_px(140)
	_acc_label.offset_top = _px(16)
	_acc_label.offset_bottom = _px(16) + _px(40)
	_acc_label.add_theme_font_size_override("font_size", int(_px(22)))
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.offset_left = -_px(132)
	_pause_btn.offset_right = -_px(18)
	_pause_btn.offset_top = _px(12)
	_pause_btn.offset_bottom = _px(12) + _px(72)
	_pause_btn.add_theme_font_size_override("font_size", int(_px(20)))
	_popup_label.offset_top = _hit_y() - _px(150)
	_popup_label.offset_bottom = _hit_y() - _px(90)
	_popup_label.add_theme_font_size_override("font_size", int(_px(34)))
	_hint_label.offset_left = _px(26)
	_hint_label.offset_top = -_px(34)
	_hint_label.offset_bottom = -_px(6)
	_hint_label.add_theme_font_size_override("font_size", int(_px(14)))
	_title_label.offset_left = _px(26)
	_title_label.offset_top = -_px(62)
	_title_label.offset_bottom = -_px(34)
	_title_label.add_theme_font_size_override("font_size", int(_px(16)))

	var e := _px(28.0)
	_miss_edges[0].position = Vector2(0, 0)
	_miss_edges[0].size = Vector2(size.x, e)
	_miss_edges[1].position = Vector2(0, size.y - e)
	_miss_edges[1].size = Vector2(size.x, e)
	_miss_edges[2].position = Vector2(0, 0)
	_miss_edges[2].size = Vector2(e, size.y)
	_miss_edges[3].position = Vector2(size.x - e, 0)
	_miss_edges[3].size = Vector2(e, size.y)

func _update_track_geometry() -> void:
	if _lane_stripes.is_empty():
		return
	var h := size.y
	var bottom := _track_width_at(h)
	var top := _track_width_at(0.0)
	var bleft := size.x * 0.5 - bottom * 0.5
	var tleft := size.x * 0.5 - top * 0.5
	var hy := _hit_y()
	_lane_top_points.clear()
	_lane_bottom_points.clear()
	for i in range(LANES):
		var lt := (float(i) + 0.5) / float(LANES)
		_lane_top_points.append(Vector2(tleft + top * lt, 0.0))
		_lane_bottom_points.append(Vector2(bleft + bottom * lt, h))
	for i in range(LANES):
		var lane_t0 := float(i) / float(LANES)
		var lane_t1 := float(i + 1) / float(LANES)
		var center_t := (lane_t0 + lane_t1) * 0.5
		var half_t := (lane_t1 - lane_t0) * LANE_STRIPE_SPAN * 0.5
		var step_t := half_t * 2.0 / float(LANE_STRIPES)
		for s in range(LANE_STRIPES):
			var a := center_t - half_t + step_t * float(s)
			var b := a + step_t
			var poly: Polygon2D = _lane_stripes[i * LANE_STRIPES + s]
			poly.polygon = PackedVector2Array([
				Vector2(tleft + top * a, 0.0),
				Vector2(tleft + top * b, 0.0),
				Vector2(bleft + bottom * b, h),
				Vector2(bleft + bottom * a, h),
			])
	for i in range(LANES):
		_pads[i].position = _lane_point(hy, i)
	_hit_line.position = Vector2(0.0, hy - _px(2.0))
	_hit_line.size = Vector2(size.x, _px(4.0))
	_hit_line.pivot_offset = _hit_line.size * 0.5


func _track_width_at(y: float) -> float:
	var t := clampf(y / maxf(size.y, 1.0), 0.0, 1.0)
	var bottom := size.x * track_width_ratio
	var top := bottom * TOP_TAPER
	return lerpf(top, bottom, t)


func _lane_point(y: float, lane: int) -> Vector2:
	if _lane_top_points.size() < LANES:
		return Vector2(size.x * 0.5, y)
	var t := y / maxf(size.y, 1.0)
	var top_p: Vector2 = _lane_top_points[lane]
	var bottom_p: Vector2 = _lane_bottom_points[lane]
	return top_p.lerp(bottom_p, t)


func _lane_x_at(y: float, lane: int) -> float:
	var w := _track_width_at(y)
	var left := size.x * 0.5 - w * 0.5
	var lw := w / float(LANES)
	return left + lw * (float(lane) + 0.5)


func _lane_at_position(pos: Vector2) -> int:
	var w := _track_width_at(pos.y)
	var left := size.x * 0.5 - w * 0.5
	var lw := w / float(LANES)
	return clampi(int((pos.x - left) / lw), 0, LANES - 1)


func _hit_y() -> float:
	return size.y - _px(HIT_OFFSET)


func _note_speed() -> float:
	return PPS_PER_SV * _current_speed


func _px(value: float) -> float:
	var s := clampf(size.y / BASE_H, 0.72, 1.60)
	return value * s


func _make_disc_texture(size_px: int) -> ImageTexture:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var r := float(size_px) * 0.5
	for y in size_px:
		for x in size_px:
			var dx := float(x) + 0.5 - r
			var dy := float(y) + 0.5 - r
			var d := sqrt(dx * dx + dy * dy) / r
			var a := 0.0
			if d <= 1.0:
				a = (1.0 - smoothstep(0.78, 1.0, d)) * (0.65 + 0.35 * (1.0 - d))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
