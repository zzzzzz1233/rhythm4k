extends Control

# Four-lane falling rhythm game.
# Notes: tap or hold. A hold can be cleared by keeping the finger down
# OR by pressing and flicking upward in the same lane.

const LANES := 4
const LANE_COLORS := [Color("#ff5d7a"), Color("#ffc24b"), Color("#4fd1c5"), Color("#7aa2ff")]
const KEY_CODES := [KEY_D, KEY_F, KEY_J, KEY_K]
const TRAVEL_TIME := 1.10
const HIT_WINDOW := 0.17
const FLICK_DISTANCE := 64.0
const LEAD_IN := 2.0
const BASE_W := 1280.0
const BASE_H := 720.0

var _song_time := -LEAD_IN
var _notes: Array = []
var _last_time := 0.0
var _held := [false, false, false, false]
var _flash := [0.0, 0.0, 0.0, 0.0]
var _drag_y := [0.0, 0.0, 0.0, 0.0]
var _touch_lane := {}
var _score := 0
var _combo := 0
var _max_combo := 0
var _hits := 0
var _misses := 0
var _perfects := 0
var _auto := false
var _paused := false
var _finished := false
var _popup_text := ""
var _popup_lane := 0
var _popup_left := 0.0
var _popup_color := Color.WHITE

var _score_label: Label
var _combo_label: Label
var _acc_label: Label
var _time_label: Label
var _hint_label: Label
var _auto_btn: Button
var _pause_btn: Button
var _menu: Control
var _menu_title: Label
var _menu_info: Label
var _btn_resume: Button
var _btn_restart: Button
var _btn_end: Button
var _btn_exit: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_chart()
	_build_hud()
	_build_menu()
	_restart()
	resized.connect(_apply_layout)
	call_deferred("_apply_layout")
	if "--auto" in OS.get_cmdline_user_args():
		_auto = true
		_auto_btn.text = "AUTO ON"
	if "--capture" in OS.get_cmdline_user_args():
		_auto = true
		_auto_btn.text = "AUTO ON"
		_capture_shot()


func _px(value: float) -> float:
	var s := clampf(size.y / BASE_H, 0.72, 1.60)
	return value * s


func _build_chart() -> void:
	var beat := 60.0 / 132.0
	var patterns := [
		[0, 2, 1, 3, 2, 0, 3, 1],
		[1, 1, 3, 2, 0, 0, 2, 3],
		[0, 3, 1, 2, 0, 2, 3, 1],
	]
	var t := LEAD_IN
	var i := 0
	while t < 116.0:
		var section := int(i / 32) % patterns.size()
		var pattern: Array = patterns[section]
		var lane: int = pattern[i % pattern.size()]
		var hold := 0.0
		if i % 8 == 5:
			hold = beat * 2.0
		_notes.append({"t": t, "lane": lane, "hold": hold, "state": 0, "dt": 0.0})
		if i % 16 == 10 or (section == 2 and i % 8 == 3):
			_notes.append({"t": t, "lane": (lane + 2) % LANES, "hold": 0.0, "state": 0, "dt": 0.0})
		t += beat
		if hold > 0.0:
			t += beat
		i += 1
	_last_time = t


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.add_theme_color_override("font_color", Color("#e8eefc"))
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score_label)

	_time_label = Label.new()
	_time_label.add_theme_color_override("font_color", Color("#9fb0c9"))
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_label)

	_combo_label = Label.new()
	_combo_label.anchor_right = 1.0
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_color_override("font_color", Color("#ffffff"))
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combo_label)

	_acc_label = Label.new()
	_acc_label.anchor_left = 1.0
	_acc_label.anchor_right = 1.0
	_acc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_acc_label.add_theme_color_override("font_color", Color("#8a97ad"))
	_acc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_acc_label)

	_auto_btn = Button.new()
	_auto_btn.text = "AUTO"
	_auto_btn.focus_mode = Control.FOCUS_NONE
	_auto_btn.pressed.connect(_toggle_auto)
	add_child(_auto_btn)

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(_pause_game)
	add_child(_pause_btn)

	_hint_label = Label.new()
	_hint_label.text = "D F J K   /   HOLD OR FLICK UP"
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.add_theme_color_override("font_color", Color("#4d5a70"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)


func _build_menu() -> void:
	_menu = Control.new()
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	_menu_title = Label.new()
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_title.add_theme_color_override("font_color", Color("#ffffff"))
	col.add_child(_menu_title)

	_menu_info = Label.new()
	_menu_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_info.add_theme_color_override("font_color", Color("#9fb0c9"))
	col.add_child(_menu_info)

	_btn_resume = _make_menu_button("CONTINUE")
	_btn_resume.pressed.connect(_resume_game)
	col.add_child(_btn_resume)

	_btn_restart = _make_menu_button("RESTART")
	_btn_restart.pressed.connect(_restart_game)
	col.add_child(_btn_restart)

	_btn_end = _make_menu_button("END SESSION")
	_btn_end.pressed.connect(_end_session)
	col.add_child(_btn_end)

	_btn_exit = _make_menu_button("EXIT APP")
	_btn_exit.pressed.connect(_exit_game)
	col.add_child(_btn_exit)


func _make_menu_button(text_value: String) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(300, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	return b


func _apply_layout() -> void:
	_score_label.position = Vector2(_px(26), _px(10))
	_score_label.add_theme_font_size_override("font_size", int(_px(30)))
	_time_label.position = Vector2(_px(26), _px(44))
	_time_label.add_theme_font_size_override("font_size", int(_px(20)))
	_combo_label.offset_top = _px(10)
	_combo_label.offset_bottom = _px(10) + _px(44)
	_combo_label.add_theme_font_size_override("font_size", int(_px(32)))
	var btn_w := _px(118)
	var btn_h := _px(44)
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.offset_left = -_px(20) - btn_w * 0.55
	_pause_btn.offset_right = -_px(20)
	_pause_btn.offset_top = _px(12)
	_pause_btn.offset_bottom = _px(12) + btn_h
	_auto_btn.anchor_left = 1.0
	_auto_btn.anchor_right = 1.0
	_auto_btn.offset_left = -_px(34) - btn_w * 1.55
	_auto_btn.offset_right = -_px(28) - btn_w * 0.62
	_auto_btn.offset_top = _px(12)
	_auto_btn.offset_bottom = _px(12) + btn_h
	_acc_label.offset_left = -_px(170) - btn_w * 1.55
	_acc_label.offset_right = -_px(40) - btn_w * 1.48
	_acc_label.offset_top = _px(16)
	_acc_label.offset_bottom = _px(16) + btn_h
	_acc_label.add_theme_font_size_override("font_size", int(_px(22)))
	_auto_btn.add_theme_font_size_override("font_size", int(_px(17)))
	_pause_btn.add_theme_font_size_override("font_size", int(_px(18)))
	_hint_label.offset_left = _px(26)
	_hint_label.offset_top = -_px(32)
	_hint_label.offset_bottom = -_px(6)
	_hint_label.add_theme_font_size_override("font_size", int(_px(15)))
	_menu_title.add_theme_font_size_override("font_size", int(_px(46)))
	_menu_info.add_theme_font_size_override("font_size", int(_px(22)))
	for b in [_btn_resume, _btn_restart, _btn_end, _btn_exit]:
		b.custom_minimum_size = Vector2(_px(300), _px(62))
		b.add_theme_font_size_override("font_size", int(_px(22)))


func _toggle_auto() -> void:
	_auto = not _auto
	_auto_btn.text = "AUTO ON" if _auto else "AUTO"


func _process(delta: float) -> void:
	if _paused or _finished:
		queue_redraw()
		return
	_song_time += delta
	for i in range(LANES):
		_flash[i] = maxf(0.0, _flash[i] - delta * 6.0)
	_popup_left = maxf(0.0, _popup_left - delta)
	_update_notes()
	if _auto:
		_auto_play()
	if _song_time > _last_time + 2.2:
		_finish_song()
	_update_hud()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _menu.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var lane := _lane_at(event.position.x)
			_touch_lane[event.index] = lane
			_drag_y[lane] = 0.0
			_press_lane(lane)
		else:
			if _touch_lane.has(event.index):
				var lane: int = _touch_lane[event.index]
				_touch_lane.erase(event.index)
				_drag_y[lane] = 0.0
				_held[lane] = false
		accept_event()
	elif event is InputEventScreenDrag:
		if _touch_lane.has(event.index):
			var lane: int = _touch_lane[event.index]
			_track_drag(lane, event.relative.y)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var lane := _lane_at(event.position.x)
		_drag_y[lane] = 0.0
		if event.pressed:
			_press_lane(lane)
		else:
			_held[lane] = false
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var lane := _lane_at(event.position.x)
		_track_drag(lane, event.relative.y)
		accept_event()


func _track_drag(lane: int, dy: float) -> void:
	if dy >= 0.0:
		return
	_drag_y[lane] += dy
	if _drag_y[lane] <= -_px(FLICK_DISTANCE):
		_drag_y[lane] = 0.0
		_flick_lane(lane)


func _flick_lane(lane: int) -> void:
	_flash[lane] = 1.0
	var best = null
	var best_dt := HIT_WINDOW + 1.0
	for n in _notes:
		if n.lane != lane or n.state == 2:
			continue
		if n.state == 1 and n.hold > 0.0:
			best = n
			break
		if n.state == 0 and n.hold > 0.0:
			var dt: float = absf(_song_time - n.t)
			if dt <= HIT_WINDOW and dt < best_dt:
				best_dt = dt
				best = n
	if best == null:
		return
	if best.state == 0:
		best.dt = _song_time - best.t
	best.state = 2
	_grade(best, absf(best.dt))


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	if key.pressed and key.keycode == KEY_ESCAPE:
		if _paused:
			_resume_game()
		elif not _finished:
			_pause_game()
		return
	if key.pressed and key.keycode == KEY_R:
		_restart_game()
		return
	for i in range(LANES):
		if key.keycode == KEY_CODES[i]:
			if key.pressed:
				_press_lane(i)
			else:
				_held[i] = false


func _lane_at(x: float) -> int:
	return clampi(int(x / _lane_width()), 0, LANES - 1)


func _lane_width() -> float:
	return size.x / float(LANES)


func _lane_center(lane: int) -> float:
	return _lane_width() * (float(lane) + 0.5)


func _hit_y() -> float:
	return size.y - _px(100.0)


func _note_speed() -> float:
	return (_hit_y() + _px(100.0)) / TRAVEL_TIME


func _update_notes() -> void:
	for n in _notes:
		if n.state == 0:
			if _song_time > n.t + HIT_WINDOW:
				_register_miss(n, "MISS")
		elif n.state == 1:
			var end_time: float = n.t + n.hold
			if _song_time >= end_time:
				n.state = 2
				_grade(n, absf(n.dt))
			elif not _auto and not _held[n.lane]:
				_register_miss(n, "BREAK")


func _auto_play() -> void:
	for n in _notes:
		if n.state == 0 and _song_time >= n.t:
			n.dt = 0.0
			_flash[n.lane] = 1.0
			if n.hold > 0.0:
				n.state = 1
			else:
				n.state = 2
				_grade(n, 0.0)


func _press_lane(lane: int) -> void:
	_held[lane] = true
	_flash[lane] = 1.0
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
	else:
		best.state = 2
		_grade(best, best_dt)


func _grade(n, adt: float) -> void:
	_hits += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	var pts := 40
	var text := "GOOD"
	if adt <= 0.05:
		pts = 100
		text = "PERFECT"
		_perfects += 1
	elif adt <= 0.10:
		pts = 70
		text = "GREAT"
	_score += pts + mini(_combo, 50)
	_show_popup(text, n.lane, Color("#8ef7c6"))


func _register_miss(n, text: String) -> void:
	n.state = 2
	_misses += 1
	_combo = 0
	_show_popup(text, n.lane, Color("#ff6b81"))


func _show_popup(text: String, lane: int, color: Color) -> void:
	_popup_text = text
	_popup_lane = lane
	_popup_color = color
	_popup_left = 0.55


func _update_hud() -> void:
	_score_label.text = "%07d" % _score
	var remain: float = maxf(0.0, (_last_time + 2.2) - _song_time)
	_time_label.text = "%d:%02d" % [int(remain) / 60, int(remain) % 60]
	if _combo >= 2:
		_combo_label.text = "%d COMBO" % _combo
	else:
		_combo_label.text = ""
	var total := _hits + _misses
	var acc := 100.0
	if total > 0:
		acc = 100.0 * float(_hits) / float(total)
	_acc_label.text = "%.1f%%" % acc


func _pause_game() -> void:
	if _paused or _finished:
		return
	_paused = true
	for i in range(LANES):
		_held[i] = false
		_drag_y[i] = 0.0
	_show_menu("PAUSED", "", "pause")


func _resume_game() -> void:
	if not _paused:
		return
	_paused = false
	_menu.visible = false


func _restart_game() -> void:
	_menu.visible = false
	_restart()


func _end_session() -> void:
	_menu.visible = false
	_finish_song()


func _exit_game() -> void:
	get_tree().quit()


func _show_menu(title: String, info: String, mode: String) -> void:
	_menu_title.text = title
	_menu_info.text = info
	_menu_info.visible = info != ""
	var is_pause := mode == "pause"
	_btn_resume.visible = is_pause
	_btn_end.visible = is_pause
	_btn_exit.visible = not is_pause
	_btn_restart.text = "RESTART" if is_pause else "REPLAY"
	_menu.visible = true


func _finish_song() -> void:
	_paused = false
	_finished = true
	for i in range(LANES):
		_held[i] = false
	var total := _hits + _misses
	var acc := 0.0
	if total > 0:
		acc = 100.0 * float(_hits) / float(total)
	var info := "SCORE  %d
MAX COMBO  %d
ACCURACY  %.1f%%
PERFECT  %d" % [_score, _max_combo, acc, _perfects]
	_show_menu("RESULT", info, "result")


func _restart() -> void:
	for n in _notes:
		n.state = 0
		n.dt = 0.0
	_song_time = -LEAD_IN
	_score = 0
	_combo = 0
	_max_combo = 0
	_hits = 0
	_misses = 0
	_perfects = 0
	_popup_left = 0.0
	_finished = false
	_paused = false
	_touch_lane.clear()
	for i in range(LANES):
		_held[i] = false
		_flash[i] = 0.0
		_drag_y[i] = 0.0
	_update_hud()
	queue_redraw()


func _capture_shot() -> void:
	await get_tree().create_timer(4.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shot.png")
	get_tree().quit()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var lw := _lane_width()
	var hy := _hit_y()
	var speed := _note_speed()
	var pad_r := _px(58.0)
	var note_r := _px(40.0)

	draw_rect(Rect2(0, 0, w, h), Color("#070a10"))

	for i in range(LANES):
		var c: Color = LANE_COLORS[i]
		draw_rect(Rect2(i * lw, 0, lw, h), Color(c.r, c.g, c.b, 0.045))
		if i > 0:
			draw_line(Vector2(i * lw, 0), Vector2(i * lw, h), Color(1, 1, 1, 0.06), 2.0)

	draw_line(Vector2(0, hy), Vector2(w, hy), Color(1, 1, 1, 0.10), 3.0)

	for i in range(LANES):
		var c: Color = LANE_COLORS[i]
		var pad := Vector2(_lane_center(i), hy)
		var fl: float = _flash[i]
		draw_circle(pad, pad_r + _px(9.0), Color(c.r, c.g, c.b, 0.08 + 0.30 * fl))
		draw_circle(pad, pad_r, Color(c.r, c.g, c.b, 0.16 + 0.50 * fl))
		draw_arc(pad, pad_r, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.80), 5.0, true)
		if fl > 0.02:
			draw_circle(pad, pad_r * 0.58, Color(1, 1, 1, 0.30 * fl))

	for n in _notes:
		if n.state == 2:
			continue
		var c: Color = LANE_COLORS[n.lane]
		var x := _lane_center(n.lane)
		if n.state == 1:
			var remain: float = maxf(0.0, (n.t + n.hold) - _song_time)
			var tail_h: float = remain * speed
			draw_rect(Rect2(x - note_r * 0.44, hy - tail_h, note_r * 0.88, tail_h), Color(c.r, c.g, c.b, 0.40))
			draw_circle(Vector2(x, hy - tail_h), note_r * 0.44, Color(c.r, c.g, c.b, 0.55))
			draw_circle(Vector2(x, hy), note_r, c)
			draw_circle(Vector2(x, hy), note_r * 0.52, Color(1, 1, 1, 0.85))
			continue
		var y: float = hy - (n.t - _song_time) * speed
		if y < -160.0 or y > h + 80.0:
			continue
		if n.hold > 0.0:
			var tail_len: float = n.hold * speed
			var top := y - tail_len
			draw_rect(Rect2(x - note_r * 0.44, top, note_r * 0.88, tail_len), Color(c.r, c.g, c.b, 0.32))
			draw_circle(Vector2(x, top), note_r * 0.44, Color(c.r, c.g, c.b, 0.50))
		draw_circle(Vector2(x, y), note_r + _px(8.0), Color(c.r, c.g, c.b, 0.16))
		draw_circle(Vector2(x, y), note_r, c)
		draw_circle(Vector2(x, y), note_r * 0.52, Color(1, 1, 1, 0.82))

	if _popup_left > 0.0:
		var alpha: float = clampf(_popup_left / 0.55, 0.0, 1.0)
		var font := ThemeDB.fallback_font
		var pw := _px(260.0)
		draw_string(font, Vector2(_lane_center(_popup_lane) - pw * 0.5, hy - _px(96.0)), _popup_text, HORIZONTAL_ALIGNMENT_CENTER, pw, int(_px(32.0)), Color(_popup_color.r, _popup_color.g, _popup_color.b, alpha))
