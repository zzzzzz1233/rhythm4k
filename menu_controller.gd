extends Control

# Login -> Song Select -> Difficulty Select -> Game.
# Song list and difficulty list use two-column GridContainers.

const GAME_SCENE := "res://Game.tscn"
const DIFF_CARD := "res://DiffCard.tscn"
const DIAGONAL_BG := "res://diagonal_bg.gd"

const BG := Color("#0a0d13")
const TEXT := Color("#e8eefc")
const MUTED := Color("#8a97ad")

var _login_ui: Control
var _song_ui: Control
var _diff_ui: Control
var _game = null

var _manifest: Array = []
var _current_song: Dictionary = {}
var _ui_font: SystemFont


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_font = SystemFont.new()
	_ui_font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Yu Gothic UI",
		"Meiryo",
		"Noto Sans CJK SC",
		"Noto Sans",
		"sans-serif",
	])
	_manifest = GameConfig.load_manifest()
	_build_login()
	_build_song_select()
	_build_diff_select()
	_show_only(_login_ui)


func _style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _ui_font)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(460, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _style(Color("#1b2230"), 14))
	b.add_theme_stylebox_override("hover", _style(Color("#2a3550"), 14))
	b.add_theme_stylebox_override("pressed", _style(Color("#111826"), 14))
	b.add_theme_color_override("font_color", TEXT)
	return b


func _make_root(node_name: String) -> Control:
	var root := Control.new()
	root.name = node_name
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root


func _add_diagonal_bg(root: Control) -> void:
	var script = load(DIAGONAL_BG)
	if script == null:
		return
	var bg = script.new()
	bg.name = "DiagonalBG"
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_login() -> void:
	_login_ui = _make_root("LoginUI")
	var center := CenterContainer.new()
	_login_ui.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	col.add_child(_label("RHYTHM 4K", 58, TEXT))
	col.add_child(_label("Enter a name to begin", 18, MUTED))

	var name_edit := LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "Nickname"
	name_edit.text = GameConfig.player_name
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(460, 60)
	name_edit.add_theme_font_override("font", _ui_font)
	name_edit.add_theme_font_size_override("font_size", 22)
	col.add_child(name_edit)

	var enter := _button("ENTER", 24)
	enter.pressed.connect(_on_login_enter.bind(name_edit))
	col.add_child(enter)
	name_edit.text_submitted.connect(_on_login_submitted.bind(name_edit))


func _on_login_submitted(_text_value: String, edit: LineEdit) -> void:
	_on_login_enter(edit)


func _on_login_enter(edit: LineEdit) -> void:
	var nick := edit.text.strip_edges()
	GameConfig.player_name = nick if not nick.is_empty() else "Player"
	_show_song_select()


func _build_song_select() -> void:
	_song_ui = _make_root("SongSelectUI")
	_add_diagonal_bg(_song_ui)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	_song_ui.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := _label("SELECT SONG", 38, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var hello := _label("", 18, MUTED)
	hello.name = "HelloLabel"
	hello.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(hello)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(grid)


func _refresh_song_list() -> void:
	var grid := _song_ui.find_child("Grid", true, false) as GridContainer
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	if _manifest.is_empty():
		grid.columns = 1
		grid.add_child(_label("No songs found in manifest.json", 20, Color("#ff6b81")))
		return
	grid.columns = 2
	for song in _manifest:
		if not song is Dictionary:
			continue
		var song_title := str(song.get("title", "?"))
		var artist := str(song.get("artist", "?"))
		var diffs: Array = song.get("difficulties", [])
		var b := _button("%s\n%s    (%d diffs)" % [song_title, artist, diffs.size()], 20)
		b.custom_minimum_size = Vector2(0, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_song_pressed.bind(song))
		grid.add_child(b)


func _build_diff_select() -> void:
	_diff_ui = _make_root("DiffSelectUI")
	_add_diagonal_bg(_diff_ui)

	var center := CenterContainer.new()
	_diff_ui.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := _label("", 36, TEXT)
	title.name = "Title"
	col.add_child(title)

	var sub := _label("", 18, MUTED)
	sub.name = "Sub"
	col.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(grid)

	var back := _button("BACK", 20)
	back.custom_minimum_size = Vector2(460, 56)
	back.pressed.connect(_show_song_select)
	col.add_child(back)


func _on_song_pressed(song: Dictionary) -> void:
	_current_song = song
	_build_diff_buttons()
	_show_only(_diff_ui)


func _build_diff_buttons() -> void:
	var title := _diff_ui.find_child("Title", true, false) as Label
	if title != null:
		title.text = str(_current_song.get("title", ""))
	var sub := _diff_ui.find_child("Sub", true, false) as Label
	if sub != null:
		sub.text = str(_current_song.get("artist", ""))
	var grid := _diff_ui.find_child("Grid", true, false) as GridContainer
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	var folder := str(_current_song.get("folder", ""))
	var diffs: Array = _current_song.get("difficulties", [])
	var packed: PackedScene = load(DIFF_CARD)
	if packed == null:
		push_error("Missing " + DIFF_CARD)
		return
	for d in diffs:
		var entry: Dictionary
		if d is Dictionary:
			entry = d
		else:
			entry = {"name": str(d), "stars": 1, "notes_count": 0}
		var card = packed.instantiate()
		card.setup(entry)
		card.custom_minimum_size = Vector2(300, 140)
		card.card_pressed.connect(_on_card_pressed.bind(folder))
		grid.add_child(card)


func _on_card_pressed(diff_name: String, folder: String) -> void:
	_start_game(folder, diff_name)


func _start_game(folder: String, diff: String) -> void:
	var packed: PackedScene = load(GAME_SCENE)
	if packed == null:
		push_error("Cannot load " + GAME_SCENE)
		return
	_show_only(null)
	GameConfig.last_song_folder = folder
	GameConfig.last_difficulty = diff
	_game = packed.instantiate()
	_game.name = "Game"
	add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.exit_requested.connect(_on_game_exit)
	_game.start_chart(folder, diff)


func _on_game_exit(target: String) -> void:
	if _game != null:
		_game.queue_free()
		_game = null
	if target == "diff":
		_show_only(_diff_ui)
	else:
		_show_song_select()


func _show_song_select() -> void:
	_refresh_song_list()
	var hello := _song_ui.find_child("HelloLabel", true, false) as Label
	if hello != null:
		hello.text = "Player: " + GameConfig.player_name
	_show_only(_song_ui)


func _show_only(node: Control) -> void:
	_login_ui.visible = node == _login_ui
	_song_ui.visible = node == _song_ui
	_diff_ui.visible = node == _diff_ui
