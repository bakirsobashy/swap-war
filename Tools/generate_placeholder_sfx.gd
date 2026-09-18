extends SceneTree

## One-shot tool: synthesizes placeholder SFX WAVs into Assets/audio/generated/.
## Run with:
##   D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --headless --path . --script res://Tools/generate_placeholder_sfx.gd
## These are temporary stand-ins until final audio assets arrive.

const SAMPLE_RATE: int = 44100

## Accumulated phase for time-varying frequencies (integrating frequency keeps
## a sweep continuous; a naive sin(t * freq * TAU) warbles instead).
var _phase: float = 0.0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://Assets/audio/generated")
	_write_wav("res://Assets/audio/generated/hit.wav", _synth_hit())
	_write_wav("res://Assets/audio/generated/death.wav", _synth_death())
	_write_wav("res://Assets/audio/generated/drop.wav", _synth_drop())
	print("Placeholder SFX generated.")
	quit()


## Short noise burst + low thump. Weapon-on-actor impact.
func _synth_hit() -> PackedFloat32Array:
	var duration := 0.12
	return _render(duration, func(t: float) -> float:
		var noise := (randf() * 2.0 - 1.0) * exp(-t * 35.0) * 0.5
		var thump := sin(t * TAU * 90.0) * exp(-t * 22.0) * 0.6
		return clamp(noise + thump, -1.0, 1.0)
	)


## Descending square tone, like a character keeling over.
func _synth_death() -> PackedFloat32Array:
	var duration := 0.45
	_phase = 0.0
	return _render(duration, func(t: float) -> float:
		var k: float = t / duration
		var freq: float = lerpf(380.0, 70.0, k)
		var sample: float = sign(sin(TAU * _phase_accum(freq))) * exp(-t * 5.0) * 0.35
		return clamp(sample, -1.0, 1.0)
	)


## Two quick noise ticks, like a weapon clattering on the ground.
func _synth_drop() -> PackedFloat32Array:
	var duration := 0.22
	return _render(duration, func(t: float) -> float:
		var tick1 := (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.6
		var tick2: float = (randf() * 2.0 - 1.0) * exp(-(t - 0.08) * 45.0) * 0.5 if t > 0.08 else 0.0
		return clamp(tick1 + tick2, -1.0, 1.0)
	)


func _phase_accum(freq: float) -> float:
	_phase += freq / SAMPLE_RATE
	return _phase


func _render(duration: float, sampler: Callable) -> PackedFloat32Array:
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = sampler.call(float(i) / SAMPLE_RATE)
	return samples


func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32767.0))

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("RIFF")
	f.store_32(36 + data.size())
	f.store_string("WAVE")
	f.store_string("fmt ")
	f.store_32(16)
	f.store_16(1)            # PCM
	f.store_16(1)            # mono
	f.store_32(SAMPLE_RATE)
	f.store_32(SAMPLE_RATE * 2)  # byte rate
	f.store_16(2)            # block align
	f.store_16(16)           # bits per sample
	f.store_string("data")
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()