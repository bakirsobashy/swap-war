class_name State
extends RefCounted

## The owning AI controller (blackboard). States read inputs from and write outputs to this.
var owner = null

## The owning state machine. States can use this to request transitions.
var machine = null


## Called once when this state becomes active.
func enter() -> void:
	pass


## Called once when this state is deactivated.
func exit() -> void:
	pass


## Mirrors _process. Return a state name string to transition, or "" to stay.
func update(_delta: float) -> String:
	return ""


## Mirrors _physics_process. Return a state name string to transition, or "" to stay.
func physics_update(_delta: float) -> String:
	return ""


## Returns a human-readable name for debugging and the plan documentation.
func get_name() -> String:
	return "State"
