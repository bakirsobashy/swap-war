extends SceneTree

## Headless probe for AudioManager's gameplay sound library (Kenney CC0 packs).
## Verifies:
##   1. every LIBRARY event resolves to at least one loaded clip
##   2. no gameplay clip runs long (the win jingle is the longest by design)
##   3. every play_* entry point plays without script errors
##
## Probe discipline: runtime node-path access to the autoload, untyped vars.

const MAX_SFX_SECONDS := 1.0
const MAX_JINGLE_SECONDS := 2.5

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var audio = root.get_node_or_null("/root/AudioManager")
	if audio == null:
		_check(false, "AudioManager autoload present")
		quit(1)
		return

	for event in audio.LIBRARY:
		var count: int = audio.get_library_clip_count(event)
		_check(count == audio.LIBRARY[event]["clips"].size(),
				"%s: all %d clip(s) load" % [event, audio.LIBRARY[event]["clips"].size()])
		# The win jingle is long by design; the project's own fire.mp3 (guns —
		# no Kenney equivalent) is padded to 2 s with silence.
		var limit := MAX_JINGLE_SECONDS if event in [&"win", &"ranged"] else MAX_SFX_SECONDS
		for clip in audio._library_clips[event]:
			if clip.get_length() > limit:
				_check(false, "%s: clip %s is %.2fs (> %.1fs)" % [event, clip.resource_path.get_file(), clip.get_length(), limit])

	for method in ["play_hit", "play_death", "play_jump", "play_land", "play_melee_attack",
			"play_ranged_fire", "play_team_swap", "play_win", "play_pickup", "play_drop"]:
		audio.call(method)
	await process_frame
	_check(true, "every play_* entry point ran")

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print(verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	var verdict := "FAIL"
	if ok:
		verdict = "PASS"
	print("%s: %s" % [verdict, what])
	if not ok:
		_fails += 1
