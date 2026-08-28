class_name StateMachine
extends RefCounted

## The AIController that owns this machine and acts as a blackboard.
var owner = null

## The active state. Null until the first transition.
var current_state = null

## Map of state name String to State instance.
var states: Dictionary = {}


func _init(ai_controller) -> void:
	owner = ai_controller


## Register a state under a name. The state receives back-references to this machine and its owner.
func register(name: String, state) -> void:
	states[name] = state
	state.machine = self
	state.owner = owner


## Transition to a registered state. Calls exit() on the old state and enter() on the new one.
func transition_to(name: String) -> void:
	if not states.has(name):
		push_error("StateMachine: unknown state '%s'" % name)
		return

	if current_state == states[name]:
		return

	if current_state:
		current_state.exit()

	current_state = states[name]
	current_state.enter()


## Run the active state's _process logic.
func update(delta: float) -> void:
	if not current_state:
		return
	var next: String = current_state.update(delta)
	if next:
		transition_to(next)


## Run the active state's _physics_process logic.
func physics_update(delta: float) -> void:
	if not current_state:
		return
	var next: String = current_state.physics_update(delta)
	if next:
		transition_to(next)
