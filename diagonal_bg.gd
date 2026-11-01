extends Control

# Slow moving diagonal lines used behind the menus.

@export var line_color: Color = Color(1, 1, 1, 0.07)
@export var spacing: float = 130.0
@export var speed: float = 16.0
@export var thickness: float = 2.0

var _offset := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_offset = fmod(_offset + speed * delta, spacing)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var x := -h - spacing + _offset
	while x < w + h:
		draw_line(Vector2(x, 0.0), Vector2(x + h, h), line_color, thickness, true)
		x += spacing
