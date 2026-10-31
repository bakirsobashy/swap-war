extends Camera2D

## Arena camera with trauma-based screen shake (hit-and-kill-feel plan §2).
## HitFeel adds trauma; the camera shakes by trauma², decaying on REAL time
## so the shake keeps moving through a hit-stop (that is what sells it).
## Offset only, no rotation: the whole arena is framed, and rotating shows the
## void past the walls. Writes nothing but `offset`, so a later follow camera
## (driving position) composes with it.

## Peak shake in SCREEN pixels, divided by zoom so every arena shakes alike.
@export var max_offset_px: float = 28.0
## Trauma lost per real second.
@export var trauma_decay: float = 1.6
## Noise samples per real second (how fast the shake jitters).
@export var noise_speed: float = 25.0

var trauma: float = 0.0

var _noise := FastNoiseLite.new()
var _t: float = 0.0

func _ready() -> void:
	add_to_group("arena_camera")
	_noise.seed = randi()
	_noise.frequency = 1.0

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	trauma = maxf(trauma - trauma_decay * real_delta, 0.0)
	_t += real_delta * noise_speed
	var amp := max_offset_px / maxf(zoom.x, 0.01) * trauma * trauma
	offset = Vector2(_noise.get_noise_2d(_t, 0.0), _noise.get_noise_2d(0.0, _t)) * amp
