extends RefCounted
## Lingo's sprite-property names, translated to the keys the override table uses.
##
## There are two vocabularies here and nothing used to sit between them. The
## interpreter hands `lingo_set_sprite_prop` the name the *script* wrote, lower-
## cased and otherwise untouched -- `moveablesprite`, because that is what
## Director calls the property. `preview/sprite_state.gd` merges the override
## table into the score record under the key the *score* uses -- `moveable`,
## because that is what the sprite record's flag byte is called. So the write
## landed, read back perfectly through `read_prop`, and was never once seen by
## anything that consumes it.
##
## That is the failure this file exists to make impossible to repeat, and it is
## worth being precise about why it is so hard to spot: a property with a name
## mismatch is not a missing property. It round-trips. `the moveableSprite of
## sprite 103` answered 1 immediately after being set to 1, so every test that
## asks the obvious question passes, and the only thing that fails is a consumer
## three modules away deciding the sprite is not moveable.
##
## Symptom it produced: in DAY1 you cannot drag anything out of the inventory.
## `init all` and `displayobject` both run `set the moveableSprite of sprite i to
## 1` over channels 103-110 for every occupied slot, and that write is the only
## thing that makes those sprites moveable -- Piposh 2's score sets the authored
## moveable bit on no record at all. With the write invisible, `Interaction`
## found the slots ineligible for the mouse entirely, so the click fell through
## to the inventory bar behind them and the drag never started.
##
## Everything else the two vocabularies share already agrees, and the aliases
## below are the whole translation. New entries belong here rather than in
## either module: this is the seam, and a second copy of it is how one rule
## becomes two that disagree.

const SpriteState := preload("res://scenes/preview/sprite_state.gd")

## Director's spelling -> the score record's. `movablesprite` is Director's own
## accepted misspelling, and it is carried for the same reason `lingo_host.gd`
## carries it: the vocabulary lists it, so a script may use it.
const ALIASES := {
	"moveablesprite": "moveable",
	"movablesprite": "moveable",
}


## The override-table key for a Lingo property name, already lower-cased by the
## host. Returns the name unchanged when the two vocabularies agree, which is
## every property but one.
static func canonical(prop: String) -> String:
	return str(ALIASES.get(prop, prop))


## `set the <prop> of sprite N`, under the key the merge will look for.
static func write(channel: int, prop: String, value: Variant,
		overrides: Dictionary, sprites: Array) -> void:
	SpriteState.write_prop(channel, canonical(prop), value, overrides, sprites)


## `the <prop> of sprite N`.
##
## `moveable` needs its own score fallback where the other properties do not.
## `read_prop` answers from the score record for everything a sprite record
## carries, and it has no arm for this one -- so a sprite the *author* ticked
## Moveable on in the Score window read back as 0 until a script had written the
## property itself. That is the same half-a-property the merge fix closes, seen
## from the read side: the score's bit and the Lingo write are one property from
## two sources, and both readers have to say so.
static func read(channel: int, prop: String, overrides: Dictionary,
		sprites: Array) -> Variant:
	var key := canonical(prop)
	var value: Variant = SpriteState.read_prop(channel, key, overrides, sprites)
	if key != "moveable" or overrides.get(channel, {}).has(key):
		return value
	for sprite in sprites:
		if int(sprite["channel"]) == channel:
			return 1 if bool(sprite.get("moveable", false)) else 0
	return value
