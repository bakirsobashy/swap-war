extends Node

## Hit & kill feel (docs/godot-prompter/plans/hit-and-kill-feel.md).
##
## Health calls on_hit for every landed hit and on_kill for every death; this
## fans out to hit-stop (a global Engine.time_scale freeze), the arena
## camera's shake, the death pop + droplet burst (ImpactFX) and the
## persistent kill stain (the arena's Stains layer). TUNING is the single
## table of feel numbers.
##
## Hit-stop and shake are for the PLAYER's fights only: 3-7 AIs hit each
## other constantly, and a freeze the player didn't cause reads as lag (and
## slows the swap clock). AI-vs-AI kills still pop, splat and stain.

const ImpactFX := preload("res://Scripts/FX/ImpactFX.gd")

const TUNING: Dictionary = {
	# Hit-stop: REAL milliseconds spent at hitstop_scale.
	"hitstop_scale": 0.05,
	"hitstop_player_hit_ms": 45,       # the player lands a hit
	"hitstop_player_hurt_ms": 60,      # the player gets hit
	"hitstop_crit_bonus_ms": 25,
	"hitstop_player_kill_ms": 120,     # the player kills or dies
	# Camera shake trauma (0..1) added per event; the camera shakes by trauma².
	"shake_player_hit": 0.2,
	"shake_player_hurt": 0.35,
	"shake_crit_bonus": 0.15,
	"shake_kill": 0.15,                # an AI kill on screen
	"shake_player_kill": 0.55,
	# Stain lands this far along the blow, so the paint sits where it sprays.
	"stain_offset": 12.0,
	# Off-map deaths splash this far inside the camera's visible edge.
	"edge_splash_margin": 24.0,
}

## Master switch for everything here (pops, stains, shake, hit-stop).
var enabled: bool = true
## Hit-stop alone. Defaults OFF under the headless display server: the probes
## count physics ticks (hit pacing, swing cadence, live matches), and a
## player-involved freeze would shift them. hit_feel_probe turns it back on.
var hitstop_enabled: bool = true

## Real-clock end of the current freeze (Time.get_ticks_msec); 0 = none.
var _hitstop_until_msec: int = 0

func _ready() -> void:
	# ALWAYS: the restore below must run while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		hitstop_enabled = false
	get_tree().scene_changed.connect(end_hitstop)

func _process(_delta: float) -> void:
	if _hitstop_until_msec == 0:
		return
	# Real clock, checked every frame: a pause or the post-round screen during
	# a freeze must never leave the game crawling — time_scale slows the
	# menus' tweens too.
	if get_tree().paused or Time.get_ticks_msec() >= _hitstop_until_msec:
		end_hitstop()

func on_hit(victim: Node, attacker, _amount: float, _dir: Vector2, is_critical: bool) -> void:
	if not enabled:
		return
	var player_hurt := _is_player(victim)
	if not player_hurt and not _is_player(attacker):
		return
	var ms: int = TUNING["hitstop_player_hurt_ms"] if player_hurt else TUNING["hitstop_player_hit_ms"]
	var trauma: float = TUNING["shake_player_hurt"] if player_hurt else TUNING["shake_player_hit"]
	if is_critical:
		ms += int(TUNING["hitstop_crit_bonus_ms"])
		trauma += float(TUNING["shake_crit_bonus"])
	hitstop(ms)
	shake(trauma)

## off_map: the KillZone death plane — no pop and no stain, just a splash at
## the edge of the camera's view so the kill still lands.
func on_kill(victim: Node2D, killer, dir: Vector2, color: Color, off_map: bool) -> void:
	if not enabled or not victim.is_inside_tree():
		return
	var scene := victim.get_tree().current_scene
	if scene == null:
		return
	if _is_player(victim) or _is_player(killer):
		hitstop(TUNING["hitstop_player_kill_ms"])
		shake(TUNING["shake_player_kill"])
	else:
		shake(TUNING["shake_kill"])

	var effects := scene.get_node_or_null("Effects")
	if off_map:
		if effects:
			ImpactFX.edge_splash(effects, _point_in_view(scene, victim.global_position), color)
		return
	var spray := dir.normalized() if not dir.is_zero_approx() else Vector2.UP
	if effects:
		ImpactFX.death_pop(effects, victim)
		ImpactFX.kill_burst(effects, victim.global_position, spray, color)
	var stains := scene.get_node_or_null("Stains")
	if stains and stains.has_method("add_stain"):
		stains.add_stain(victim.global_position + spray * float(TUNING["stain_offset"]), color, spray)

## Freeze the game for `ms` real milliseconds. Overlapping freezes extend to
## the latest end, never add up.
func hitstop(ms: int) -> void:
	if not enabled or not hitstop_enabled or ms <= 0 or get_tree().paused:
		return
	_hitstop_until_msec = maxi(_hitstop_until_msec, Time.get_ticks_msec() + ms)
	Engine.time_scale = TUNING["hitstop_scale"]

func end_hitstop() -> void:
	_hitstop_until_msec = 0
	Engine.time_scale = 1.0

func is_hitstopped() -> bool:
	return _hitstop_until_msec != 0

func shake(trauma: float) -> void:
	if not enabled or trauma <= 0.0:
		return
	var cam := get_tree().get_first_node_in_group("arena_camera")
	if cam and cam.has_method("add_trauma"):
		cam.add_trauma(trauma)

## Untyped: a killer can be a freed actor (Play Again mid-attribution window).
func _is_player(node) -> bool:
	return is_instance_valid(node) and "is_player" in node and bool(node.is_player)

## `pos` clamped inside the active camera's visible rect (inset by a margin).
func _point_in_view(scene: Node, pos: Vector2) -> Vector2:
	var cam := scene.get_viewport().get_camera_2d()
	if cam == null:
		return pos
	var half: Vector2 = cam.get_viewport_rect().size / cam.zoom * 0.5
	var center := cam.get_screen_center_position()
	var m: float = TUNING["edge_splash_margin"]
	return Vector2(
			clampf(pos.x, center.x - half.x + m, center.x + half.x - m),
			clampf(pos.y, center.y - half.y + m, center.y + half.y - m))
