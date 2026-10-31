extends RefCounted

## One-shot hit/kill effects (hit-and-kill-feel plan §4), spawned by HitFeel.
## Everything lands in the arena's Effects node, so Play Again's leftover
## sweep clears it. Nothing here keeps a reference to the actor: Health.die()
## hides it the same frame, and it can be freed during the respawn wait.

## Death pop: the white silhouette swells to POP_SCALE, then fades.
const POP_SECONDS := 0.06
const POP_FADE_SECONDS := 0.1
const POP_SCALE := 1.25
## Droplet sprite size in px (scaled per particle).
const DROP_TEXTURE_SIZE := 16

static var _white_material: ShaderMaterial = null
static var _drop_texture: Texture2D = null

## A white silhouette of the victim's body at the death spot: holds through
## the kill's hit-stop (tweens run on scaled time), then swells and fades.
static func death_pop(effects: Node, actor: Node2D) -> void:
	var src := actor.get_node_or_null("VisualBody/Sprite2D") as Sprite2D
	if src == null or src.texture == null:
		return
	var pop := Sprite2D.new()
	pop.texture = src.texture
	pop.centered = src.centered
	pop.offset = src.offset
	pop.flip_h = src.flip_h
	pop.material = _white()
	pop.z_index = 5   # over tiles and actors, under weapons (10)
	effects.add_child(pop)
	pop.global_transform = src.global_transform
	var base := pop.scale
	var t := pop.create_tween().set_parallel(true)
	t.tween_property(pop, "scale", base * POP_SCALE, POP_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(pop, "modulate:a", 0.0, POP_FADE_SECONDS).set_delay(POP_SECONDS)
	t.chain().tween_callback(pop.queue_free)

## Team-colour droplets sprayed along the killing blow, falling under gravity.
static func kill_burst(effects: Node, pos: Vector2, dir: Vector2, color: Color) -> void:
	var p := _droplets(color)
	p.amount = 26
	p.lifetime = 0.55
	p.direction = dir
	p.spread = 80.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 320.0
	_emit(effects, p, pos)

## Off-map death: a fountain of droplets at the edge of the view.
static func edge_splash(effects: Node, pos: Vector2, color: Color) -> void:
	var p := _droplets(color)
	p.amount = 20
	p.lifetime = 0.6
	p.direction = Vector2.UP
	p.spread = 35.0
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 380.0
	_emit(effects, p, pos)

static func _droplets(color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.texture = _drop()
	p.gravity = Vector2(0.0, 700.0)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.75
	p.color = color
	# Fade out over the lifetime (the ramp multiplies `color`).
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	p.color_ramp = ramp
	return p

static func _emit(effects: Node, p: CPUParticles2D, pos: Vector2) -> void:
	effects.add_child(p)
	p.global_position = pos
	p.emitting = true
	# Weak capture: Effects (and the arena) can be freed before this fires —
	# same pattern as Health's flash timer.
	var p_ref: WeakRef = weakref(p)
	effects.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func() -> void:
		var node := p_ref.get_ref() as CPUParticles2D
		if node:
			node.queue_free()
	)

## Flat white with the texture's alpha (times modulate alpha, for the fade).
static func _white() -> ShaderMaterial:
	if _white_material == null:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = vec4(1.0, 1.0, 1.0, COLOR.a);\n}\n"
		_white_material = ShaderMaterial.new()
		_white_material.shader = shader
	return _white_material

## Soft-edged white disc, tinted per burst through the particle colour.
static func _drop() -> Texture2D:
	if _drop_texture == null:
		var n := DROP_TEXTURE_SIZE
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 1.0, 1.0, 0.0))
		var c := Vector2(n, n) * 0.5
		var r := n * 0.5 - 1.0
		for y in n:
			for x in n:
				var a := clampf(r - Vector2(x + 0.5, y + 0.5).distance_to(c) + 0.5, 0.0, 1.0)
				if a > 0.0:
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		_drop_texture = ImageTexture.create_from_image(img)
	return _drop_texture
