extends Button

signal card_pressed(card_name: String)

@export var stars: int = 1

var _diff_name := ""
var _notes_count := 0
var _ui_font: SystemFont


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(300, 140)
	_ui_font = SystemFont.new()
	_ui_font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Segoe UI Symbol",
		"Noto Sans CJK SC",
		"Noto Sans",
		"sans-serif",
	])
	_apply_style()
	pressed.connect(_on_pressed)
	_apply()


func setup(diff: Dictionary) -> void:
	_diff_name = str(diff.get("name", "Unknown"))
	stars = clampi(int(diff.get("stars", 1)), 1, 5)
	_notes_count = int(diff.get("notes_count", 0))
	if is_node_ready():
		_apply()


func _apply_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(1)
	normal.border_color = Color(1, 1, 1, 0.10)
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.11)
	hover.border_color = Color(1, 1, 1, 0.22)
	var pressed_box := normal.duplicate()
	pressed_box.bg_color = Color(1, 1, 1, 0.16)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_box)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _apply() -> void:
	if not is_node_ready():
		return
	var name_label := get_node_or_null("Margin/VBox/NameLabel") as Label
	var stars_label := get_node_or_null("Margin/VBox/StarsLabel") as Label
	var notes_label := get_node_or_null("Margin/VBox/NotesLabel") as Label
	if name_label == null or stars_label == null or notes_label == null:
		return
	name_label.text = _diff_name
	stars_label.text = _stars_text(stars)
	notes_label.text = "%d notes" % _notes_count
	for l in [name_label, stars_label, notes_label]:
		l.add_theme_font_override("font", _ui_font)


func _stars_text(count: int) -> String:
	var out := ""
	for i in 5:
		out += "★" if i < count else "☆"
	return out


func _on_pressed() -> void:
	card_pressed.emit(_diff_name)
