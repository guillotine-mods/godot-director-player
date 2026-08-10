extends Node
## Which devices the mouse events reaching the tree came from.
##
## One thing only, and it exists because it is the one fact about an input event
## the engine now *depends* on and nothing else in the tree would notice
## changing: Godot stamps `InputEvent.DEVICE_ID_EMULATION` on the mouse events it
## synthesises from a finger, and `director_preview.gd:_input` reads that to
## decide whether the OS cursor followed the pointer. A harness that asserted the
## engine's own conclusion instead would keep passing if Godot stopped marking
## them, because the engine would simply be wrong in both arms at once.
##
## Added to the tree by whoever wants it and freed afterwards. `seen` is cleared
## by the caller between gestures rather than by a method here, because the
## interesting question is always "what arrived since I last looked".

var seen: Array = []


func _ready() -> void:
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		seen.append(int(event.device))
