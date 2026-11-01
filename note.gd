extends Node2D

# Falling note: Body + Core + a NinePatchRect hold tail with a glow layer.
# The tail texture is generated in code: rounded caps and a vertical alpha ramp.

@export var note_texture: Texture2D
@export var tail_texture: Texture2D
@export var core_color: Color = Color(1, 1, 1, 0.85)

var lane_color := Color("#4f8cff")
var hold_seconds := 0.0
var mirror := false

var _body: Sprite2D
var _core: Sprite2D
var _tail: NinePatchRect
var _glow: NinePatchRect
var _diameter := 80.0
var _fading := false

static var _cached_disc: ImageTexture
static var _cached_tail: ImageTexture


func _ready() -> void:
	_body = $Body
	_core = $Core
	_tail = $Tail
	_build_tail_nodes()
	_build_fallback_textures()
	_body.flip_h = mirror
	_apply_look()
	_apply_size()
	_hide_tail_now()


func setup(color: Color, hold: float) -> void:
	lane_color = color
	hold_seconds = hold
	if is_node_ready():
		_apply_look()


func set_note_texture(tex: Texture2D) -> void:
	note_texture = tex
	if _body == null:
		return
	_body.texture = tex if tex != null else _cached_disc
	_apply_look()
	_apply_size()


func set_mirror(on: bool) -> void:
	mirror = on
	if _body != null:
		_body.flip_h = on


func set_note_diameter(px: float) -> void:
	_diameter = maxf(8.0, px)
	if is_node_ready():
		_apply_size()


# top_local / bottom_local are in this note's local space.
func set_tail_geometry(top_local: Vector2, bottom_local: Vector2, width: float) -> void:
	if _tail == null:
		return
	_fading = false
	var mid := (top_local + bottom_local) * 0.5
	var dir := bottom_local - top_local
	var length := maxf(dir.length(), 1.0)
	var angle := dir.angle() + PI * 0.5
	var w := maxf(width, 4.0)

	_tail.size = Vector2(w, length)
	_tail.pivot_offset = _tail.size * 0.5
	_tail.position = mid - _tail.size * 0.5
	_tail.rotation = angle
	_tail.modulate = Color(lane_color.r, lane_color.g, lane_color.b, 1.0)
	_tail.visible = true

	if _glow != null:
		var gw := w + 12.0
		_glow.size = Vector2(gw, length + 8.0)
		_glow.pivot_offset = _glow.size * 0.5
		_glow.position = mid - _glow.size * 0.5
		_glow.rotation = angle
		_glow.modulate = Color(1.0, 1.0, 1.0, 0.2)
		_glow.visible = true


# Kept for compatibility. The tail is driven by set_tail_geometry().
func set_tail_length(_px: float) -> void:
	if _tail == null:
		return
	_tail.visible = false
	if _glow != null:
		_glow.visible = false


func fade_tail() -> void:
	if _tail == null or not _tail.visible or _fading:
		return
	_fading = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_tail, "modulate:a", 0.0, 0.1)
	if _glow != null:
		tw.tween_property(_glow, "modulate:a", 0.0, 0.1)
	tw.chain().tween_callback(_hide_tail_now)


func hide_tail_immediate() -> void:
	_fading = false
	_hide_tail_now()


func set_hold_glow(on: bool) -> void:
	if _body == null:
		return
	if note_texture != null:
		_body.modulate = Color(1.35, 1.35, 1.35) if on else Color.WHITE
	else:
		_body.modulate = lane_color.lightened(0.25) if on else lane_color


func _hide_tail_now() -> void:
	_fading = false
	if _tail != null:
		_tail.visible = false
		_tail.modulate.a = 1.0
	if _glow != null:
		_glow.visible = false
		_glow.modulate.a = 1.0


func _apply_look() -> void:
	if _body == null:
		return
	if note_texture != null:
		_body.modulate = Color.WHITE
		_core.visible = false
	else:
		_body.modulate = lane_color
		_core.visible = true
	_core.modulate = core_color


func _apply_size() -> void:
	if _body == null or _body.texture == null:
		return
	var tex_size: float = float(_body.texture.get_width())
	if tex_size <= 0.0:
		return
	var s := _diameter / tex_size
	_body.scale = Vector2(s, s)
	_core.scale = Vector2(s, s)


func _build_tail_nodes() -> void:
	if _tail == null:
		_tail = NinePatchRect.new()
		_tail.name = "Tail"
		add_child(_tail)
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.z_index = 0

	_glow = NinePatchRect.new()
	_glow.name = "TailGlow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.z_index = 0
	add_child(_glow)
	move_child(_glow, 0)
	move_child(_tail, 1)


func _build_fallback_textures() -> void:
	if _cached_disc == null:
		_cached_disc = _make_disc_texture(128)
	if _cached_tail == null:
		_cached_tail = _make_tail_texture()

	if note_texture == null:
		_body.texture = _cached_disc
	else:
		_body.texture = note_texture

	var tex: Texture2D = tail_texture if tail_texture != null else _cached_tail
	_tail.texture = tex
	_glow.texture = tex
	for rect in [_tail, _glow]:
		rect.patch_margin_left = 0
		rect.patch_margin_right = 0
		rect.patch_margin_top = 16
		rect.patch_margin_bottom = 16
	_core.texture = _cached_disc


# 32x64 capsule: radius 16 caps, vertical alpha ramp in the middle.
func _make_tail_texture() -> ImageTexture:
	var w := 32
	var h := 64
	var radius := 16.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var cx := clampf(px, radius, float(w) - radius)
			var cy := clampf(py, radius, float(h) - radius)
			var dx := px - cx
			var dy := py - cy
			var dist := sqrt(dx * dx + dy * dy)
			var shape := 1.0 - smoothstep(radius - 1.0, radius + 0.5, dist)
			var gradient := lerpf(0.12, 0.95, py / float(h))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(shape * gradient, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_disc_texture(size_px: int) -> ImageTexture:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var r := float(size_px) * 0.5
	for y in size_px:
		for x in size_px:
			var dx := float(x) + 0.5 - r
			var dy := float(y) + 0.5 - r
			var dist := sqrt(dx * dx + dy * dy) / r
			var a := 0.0
			if dist <= 1.0:
				a = 1.0 - smoothstep(0.86, 1.0, dist)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
