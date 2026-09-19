class_name AIDifficulty
extends RefCounted

## Tuning table for the AI decision layer. Locked decision: ONE shipped
## profile ("normal") — every tunable the states and sensors read lives here
## so a future Easy/Hard is one dict addition, not code changes.
##
## Deliberately NO sight/seek radii in this table (locked decision #11:
## full-map awareness — distance appears only inside scores, never as a
## knowledge filter).

const PROFILES: Dictionary = {
	&"normal": {
		"reaction_time": 0.25,             # sensor refresh cadence
		"swap_reaction_time": 0.35,        # team-swap enemy re-acquire window
		"target_switch_cooldown": 0.5,     # sticky-enemy switch pacing
		"aim_error_deg": 10.0,             # ranged aim scatter, re-rolled per refresh
		"ranged_preference_bonus": 150.0,  # weapon score bonus for ranged picks
		"retreat_health_ratio": 0.3,        # low-health retreat trigger
		"jump_risk_weight": 1.0,           # A* jump-cost multiplier (caution)
		"patrol_hop_interval": 2.5,         # seconds between patrol hops
	},
}


## Write a profile's keys onto the controller's exported vars. AIController
## applies this in _ready, before any state runs; editor-set values lose to
## the table by design (the table is the single source of tuning truth).
static func apply(controller: Node, profile_name: StringName = &"normal") -> void:
	if not PROFILES.has(profile_name):
		push_warning("AIDifficulty: unknown profile '%s', falling back to normal" % profile_name)
		profile_name = &"normal"
	var values: Dictionary = PROFILES[profile_name]
	for key in values:
		controller.set(key, values[key])