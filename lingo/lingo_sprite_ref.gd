class_name LingoSpriteRef
extends RefCounted
## `sprite(n)` as a value, which is a thing you can hold rather than a number.
##
## Director has a distinct datum type for this — `SPRITEREF` in the reference's
## own list (`lingo/lingo.h`, `DatumType`), sitting alongside `CASTREF` and
## `PICTUREREF` — and this port evaluated it to a plain integer. That reads as
## harmless, because every consumer wanted the channel number anyway, right up
## until a script hands the reference somewhere before using it:
##
##     on hide me
##       me.ItemSprite().visible = 0
##       if me.ItemSprite().locH > 0 then
##         me.ItemSprite().locH = me.ItemSprite().locH - 1000
##       end if
##
## That is Magic Hat's menu-item object, and it is the ordinary way to write a
## button that can hide itself. `ItemSprite()` returns `sprite(prSprite)`; with
## the reference flattened to an integer the assignment arm saw a dot-write onto
## a number, found no sprite in it, and passed the property to `set_window_prop`
## — where a table of window fields accepts any name and drops it. Nothing failed
## and nothing was recorded, and the Yes/No dialog the main menu asks to hide
## stayed on screen over the whole game.
##
## The number is still what everything else gets: `LingoValue.to_num` unwraps
## this to the channel, so comparisons, arithmetic, `sendSprite` and every host
## call that takes a channel see exactly what they saw before. **The only thing
## that changed is that a property access can now tell where the number came
## from**, which is the one question an integer could not answer.
##
## Deliberately not a general handle: it carries a channel and nothing else, and
## it does not pretend to be the sprite. Director's own reference is the same —
## the sprite it names is whatever occupies that channel when the property is
## finally read or written, which is why a reference held across a frame boundary
## addresses the new occupant rather than the old one.

var channel: int


func _init(number: int) -> void:
	channel = number


## True for the value this file makes, false for everything else — including the
## plain integers `the currentSpriteNum` and friends still answer, which must
## keep behaving as numbers.
##
## Deliberately no `LingoValue` here, in either direction of use: `LingoValue`
## unwraps this type in `to_num`, and a `class_name` that reached back would make
## the two files a cycle GDScript refuses to compile.
static func is_ref(value: Variant) -> bool:
	return value is LingoSpriteRef


func _to_string() -> String:
	return "(sprite %d)" % channel
