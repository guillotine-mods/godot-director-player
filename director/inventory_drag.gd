class_name InventoryDrag
extends RefCounted
## One inventory icon in flight.
##
## reference/lingo/MASTER/External/BehaviorScript 108.ls stores the slot's home
## position in globals objectxx / objectyy on mouseDown and writes them back at
## the end of mouseUp, always. The snap-back is not a failure branch: item
## consumption is a mutation of objectsfield, never a sprite position.

var active: bool = false
var slot_channel: int = -1
var item: String = ""
var home: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO
var icon_size: Vector2 = Vector2.ZERO


func begin(channel: int, item_name: String, home_pos: Vector2, size: Vector2) -> void:
	active = true
	slot_channel = channel
	item = item_name
	home = home_pos
	position = home_pos
	icon_size = size


func move_to(pos: Vector2) -> void:
	if active:
		position = pos


func clear() -> void:
	active = false
	slot_channel = -1
	item = ""
	home = Vector2.ZERO
	position = Vector2.ZERO
	icon_size = Vector2.ZERO


func icon_rect() -> Rect2:
	## Director drags a sprite by its registration point, so the icon stays
	## centred on the cursor. `intersects` is a rect test between two sprites.
	return Rect2(position - icon_size * 0.5, icon_size)
