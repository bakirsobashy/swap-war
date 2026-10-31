extends Node2D

## Persistent kill stains (hit-and-kill-feel plan §5). One splat sprite per
## kill, in the victim's team colour at the moment of death, kept for the
## whole match — after a few swaps the arena is a record of who died where.
##
## Lives in ArenaBase as "Stains" at z -1: over the arena Background (-2),
## behind the tiles (0), so a kill on a platform reads as paint on the wall
## behind it. HitFeel adds stains; ArenaManager clears them on Play Again;
## the arena frees them with itself. No per-frame cost: each stain is a
## static Sprite2D after its landing tween.
##
## Art: every PNG under SPLAT_DIR (the Kenney Splat Pack), drawn white-on-
## alpha and tinted through modulate. Until that folder exists, a few
## code-drawn splats stand in.

const SPLAT_DIR := "res://Assets/vfx/PNG/"
## Stain diameter in world px (~1.6x the actor) whatever the art's size.
const BASE_SIZE := 110.0
const STAIN_ALPHA := 0.7
## Pushed toward ink so a stain never reads as a live fighter.
const INK_MIX := 0.15
const LAND_SECONDS := 0.12
const FADE_SECONDS := 1.0
const FALLBACK_VARIANTS := 4
const FALLBACK_SIZE := 64

## Safety cap: past it the oldest stain fades out and frees. A 2-minute
## 4-fighter match leaves ~20-60 stains; this only bounds the long ones.
@export var max_stains: int = 150

static var _textures: Array[Texture2D] = []

var _stains: Array[Sprite2D] = []

func _ready() -> void:
	# Load (or draw) the art at arena load, not on the first kill.
	_get_textures()

func add_stain(pos: Vector2, color: Color, dir: Vector2) -> Sprite2D:
	var textures := _get_textures()
	var tex: Texture2D = textures[randi() % textures.size()]
	var s := Sprite2D.new()
	s.texture = tex
	s.flip_h = randf() < 0.5
	var angle := dir.angle() if not dir.is_zero_approx() else randf() * TAU
	s.rotation = angle + deg_to_rad(randf_range(-20.0, 20.0))
	s.modulate = stain_color(color)
	add_child(s)
	s.global_position = pos
	var size := BASE_SIZE * randf_range(0.8, 1.2)
	var full := Vector2.ONE * size / maxf(tex.get_width(), tex.get_height())
	s.scale = full * 0.3
	s.create_tween().tween_property(s, "scale", full, LAND_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stains.append(s)
	while _stains.size() > max_stains:
		_retire(_stains.pop_front())
	return s

## Team colour -> stain tint (slightly inked, semi-transparent).
func stain_color(color: Color) -> Color:
	var c := color.lerp(TeamPalette.INK, INK_MIX)
	c.a = STAIN_ALPHA
	return c

func get_stains() -> Array:
	return _stains.duplicate()

func clear() -> void:
	for s in get_children():
		s.queue_free()
	_stains.clear()

func _retire(s: Sprite2D) -> void:
	if not is_instance_valid(s):
		return
	var t := s.create_tween()
	t.tween_property(s, "modulate:a", 0.0, FADE_SECONDS)
	t.tween_callback(s.queue_free)

static func _get_textures() -> Array[Texture2D]:
	if _textures.is_empty():
		for path in _list_pngs(SPLAT_DIR):
			# exists(): a .gdignore'd subfolder lists PNGs it never imported.
			if not ResourceLoader.exists(path):
				continue
			var tex := load(path) as Texture2D
			if tex:
				_textures.append(tex)
		if _textures.is_empty():
			for i in FALLBACK_VARIANTS:
				_textures.append(_draw_splat(i))
	return _textures

## Every PNG under `dir_path`, recursively. Exported builds list "x.png.import"
## instead of "x.png", so the suffix is stripped and the result deduped.
static func _list_pngs(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		var file_name := f.trim_suffix(".import")
		if file_name.get_extension().to_lower() == "png" and not out.has(dir_path + file_name):
			out.append(dir_path + file_name)
	for sub in dir.get_directories():
		out.append_array(_list_pngs(dir_path + sub + "/"))
	return out

## Stand-in splat until the Splat Pack is in: a lobed white blob plus a few
## satellite drops, antialiased on the alpha edge.
static func _draw_splat(variant: int) -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var n := FALLBACK_SIZE
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var center := Vector2(n, n) * 0.5
	var base_r := n * 0.26
	var lobes: Array[Vector3] = []   # (frequency, amplitude, phase)
	for k in [3.0, 5.0, 7.0, 11.0]:
		lobes.append(Vector3(float(k), rng.randf_range(0.04, 0.12), rng.randf() * TAU))
	var drops: Array[Vector3] = []   # (x, y, radius)
	for i in rng.randi_range(4, 7):
		var at := center + Vector2.from_angle(rng.randf() * TAU) * base_r * rng.randf_range(1.2, 1.6)
		drops.append(Vector3(at.x, at.y, rng.randf_range(1.5, 3.5)))
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var off := p - center
			var r := base_r
			for l in lobes:
				r += base_r * l.y * sin(l.x * off.angle() + l.z)
			var cover := clampf(r - off.length() + 0.5, 0.0, 1.0)
			for d in drops:
				cover = maxf(cover, clampf(d.z - p.distance_to(Vector2(d.x, d.y)) + 0.5, 0.0, 1.0))
			if cover > 0.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, cover))
	return ImageTexture.create_from_image(img)
