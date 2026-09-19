class_name State
extends RefCounted

## The owning AI controller (blackboard). States read inputs from and write
## outputs to this.
##
## Deliberately NO back-reference to the owning StateMachine: State(RC) ->
## machine(RC) -> states dictionary is a reference cycle, and RefCounted
## cycles are never collected — every state leaked at exit (audit bug).
## Transitions are returned as strings from physics_update instead; the
## machine is a one-way owner -> state -> owner(Node) chain.

var owner = null


## Called once when this state becomes active.
func enter() -> void:
	pass


## Called once when this state is deactivated.
func exit() -> void:
	pass


## Mirrors _physics_process. Return a state name string to transition, or "" to stay.
## All decision logic is physics-ticked — there is no _process mirror anymore.
func physics_update(_delta: float) -> String:
	return ""


## Returns a human-readable name for debugging and the plan documentation.
func get_name() -> String:
	return "State"