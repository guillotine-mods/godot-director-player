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
##
## There is a second seam here now, and it is the same failure in another shape:
## not every sprite property the override table can hold *belongs* in it.
## `the constraint of sprite N` does not -- see `write` -- so both functions take
## the dictionary it does live in, as a required argument rather than a
## defaulted one. A caller that forgets it fails to compile, which is the only
## check that would have caught the original bug at the moment it was written.

const SpriteState := preload("res://scenes/preview/sprite_state.gd")

## Director's spelling -> the score record's. `movablesprite` is Director's own
## accepted misspelling, and it is carried because the vocabulary lists it, so a
## script may use it.
##
## `editabletext` is the third entry and the third instance of the same bug.
## `the editableText of sprite N` arrives lower-cased as `editabletext`; the
## record's flag byte is decoded as `editable` (`director_score.gd`, colour-code
## bit 0x40). Unaliased, a *read* of the property cannot see the author's own
## tick in the Score window -- it answers only what a script wrote, through the
## override store, which round-trips perfectly and is why it looks implemented.
## Exactly the shape `moveableSprite` had, and `the constraint of sprite` after
## it. `preview/text_focus.gd:editable` currently reads both spellings off the
## sprite to work around the gap; that is a patch at the consumer, and this is
## the fix at the seam.
## `fliph` / `flipv` are the fifth instance and the largest: **456 sites across
## Piposh Dream**, which both reads and writes them (`if sprite(getAt(ppl, 1))
## .flipH = 1`, `sprite(getAt(ppl, 2)).flipH = 0`). The record's bits are decoded
## as `flip_h` / `flip_v` (`director_score.gd`, thickness byte 0x20 and 0x40) and
## `sprite_art.gd` has drawn from those names since before the bits were decoded
## -- and mirrors the hit-test sample with them, so a flipped sprite is clickable
## where it is drawn. Every link of that chain was already in place; the write
## simply landed under a name at the far end of it.
##
## `member` is the sixth, and the highest-usage one left: **1,453 sites**, all in
## Piposh Dream. `the member of sprite N` is Director's member *reference* where
## `the memberNum of sprite N` is the integer, and they are two properties in
## Director. Here they are one, because this port packs the `(library, slot)` pair
## into a single integer that `member()` accepts either way (§1.6) -- so the alias
## is correct for every site in the corpus and would be wrong only for a title
## that compared a member reference against something that is not an integer.
## Unaliased, the read falls through to `EMPTY_CHANNEL`'s 0 and every one of those
## sites addresses member 0.
const ALIASES := {
	"moveablesprite": "moveable",
	"movablesprite": "moveable",
	"editabletext": "editable",
	"member": "membernum",
	"fliph": "flip_h",
	"flipv": "flip_v",
	# An identity entry, listed rather than omitted. `castLibNum` is its own
	# field under its own name and needs no translation -- but the reason it
	# needs none is exactly the fact this table exists to record, and a name
	# absent from here reads as "nobody has looked at it" rather than as
	# "checked, and the two vocabularies agree". 3 sites.
	#
	# It is live on the **read** only. `sprite_state.read_prop` answers it from
	# the record's `cast_lib`, and `effective` has no arm for it, so a script
	# that *writes* `the castLibNum of sprite N` still moves nothing on screen.
	# Same half-a-property shape as the four above, one seam further along.
	"castlibnum": "castlibnum",
}

## Properties the *score record* carries a value for and `sprite_state.read_prop`
## has no arm for, so a read has to fall back to the record here or answer 0 for
## a flag the author set.
##
## Both are flags rather than values, and both are half of a property whose other
## half is a Lingo write -- which is the whole reason this file exists. Adding a
## key here is not enough on its own to make the property *work*: a Lingo write
## also has to be merged into the effective sprite by `sprite_state.effective`,
## which has an arm for `moveable` and none for `editable`.
const SCORE_FLAGS := ["moveable", "editable"]

## Every canonical key something in this port actually **consumes**.
##
## `sprite_state.write_prop` stores any key at all, and `read_prop` answers a
## stored key back, so *every* sprite write round-trips and every one of them
## looks implemented. Only the keys `read_prop` has an arm for or `effective`
## merges reach the screen. That gap is silent by construction and it has now
## produced five separate bugs -- `moveableSprite`, `editableText`,
## `constraint`, `the member of sprite`, `flipH`/`flipV` -- each found by a
## player noticing something did not move, never by the engine saying so.
##
## `LingoDiagnostics` has had a `SPRITE_PROP` category since it was written and
## **nothing has ever emitted one**, because the check needs a list of what is
## consumed and there was nowhere for the list to live that was not a second
## copy of this table. It lives here, next to the aliases, and
## `director_preview.gd`'s two entry points report against it.
##
## Derived rather than invented, so it can be checked: the keys `read_prop`
## matches on, plus `EMPTY_CHANNEL`'s, plus the keys `effective` merges, plus
## the three the node routes before either is reached (`constraint` in `write`
## below, `cursor` and `loc` in `director_preview.gd`). A name missing from here
## costs one diagnostic row and no behaviour, which is the safe direction for a
## list whose whole purpose is to be noticed when it is wrong.
const CONSUMED := {
	"membernum": true, "castnum": true, "castlibnum": true,
	"loch": true, "locv": true, "loc": true,
	"width": true, "height": true, "visible": true,
	"ink": true, "blend": true, "trails": true,
	"flip_h": true, "flip_v": true,
	"moveable": true, "editable": true,
	"constraint": true, "cursor": true,
}


## Does anything in this port read `prop` after a script writes it?
##
## Takes the **Lingo** spelling and canonicalises, so a caller asks the question
## in the vocabulary it has. False is not "no such property in Director" -- it is
## "this port will store it and nothing will ever look".
static func consumed(prop: String) -> bool:
	return CONSUMED.has(canonical(prop))


## The override-table key for a Lingo property name, already lower-cased by the
## host. Returns the name unchanged when the two vocabularies agree, which is
## every property but one.
static func canonical(prop: String) -> String:
	return str(ALIASES.get(prop, prop))


## `set the <prop> of sprite N`, under the key the merge will look for.
##
## `constraints` is `channel -> the constraint of sprite`, and it is a separate
## dictionary because **`the constraint of sprite` is channel state, not a
## puppeted score field** -- the same class as `the cursor of sprite` in §7.5,
## for the same two reasons.
##
## The 48-byte sprite record has no constraint field, and that is measured, not
## assumed. Bytes 0-35 are all claimed by something `director_score.gd` decodes,
## and bytes 36-47 hold **one distinct value, 0x00, across every one of the
## 816,318 occupied records in Piposh 2 and the 1,886,362 in Piposh 1**
## (`tools/sprite_record_bytes.gd --all`, both roots). So no sprite record in
## either corpus carries a constraint, no score can write one, and there is
## nothing for a per-field merge to merge *with*. In the reference it is
## `Channel::_constraint`, read by `Channel::setPosition` (§7.6).
##
## And putting it in `_overrides` anyway would be a bug with the corpus's own
## shape, not a matter of taste. `sprite_state.effective` discards a channel's
## overrides the moment the score moves that channel to a different member, and
## all five of the corpus's constraint sites -- SHUFFLE's `BehaviorScript 9` and
## `CastScript 169/170/197/198`, ten writes in five scripts, the only ones in
## 3,349 decompiled scripts across 73 movies -- are
##
##     set the moveableSprite of sprite 6 to 1
##     set the constraint of sprite 6 to 2
##     go(marker(1))
##
## : set the constraint, then leave for the segment the drag actually happens in.
## An override-backed constraint is discarded on arrival, every time, and the
## only title that asks for the feature would never once see it applied.
static func write(channel: int, prop: String, value: Variant,
		overrides: Dictionary, sprites: Array, constraints: Dictionary) -> void:
	var key := canonical(prop)
	if key == "constraint":
		constraints[channel] = LingoValue.to_int(value)
		return
	SpriteState.write_prop(channel, key, value, overrides, sprites)


## `the <prop> of sprite N`.
##
## `SCORE_FLAGS` need their own score fallback where the other properties do not.
## `read_prop` answers from the score record for everything a sprite record
## carries, and it has no arm for either of them -- so a sprite the *author*
## ticked Moveable or Editable on in the Score window read back as 0 until a
## script had written the property itself. That is the same half-a-property the
## merge fix closes, seen from the read side: the score's bit and the Lingo write
## are one property from two sources, and both readers have to say so.
##
## `constraint` answers from `constraints` and never reaches `read_prop`, which
## would answer 0 from its fall-through for a property the score record does not
## carry -- indistinguishable from "unconstrained", and so a write that
## round-trips as a lie. `write` has why it lives there.
static func read(channel: int, prop: String, overrides: Dictionary,
		sprites: Array, constraints: Dictionary) -> Variant:
	var key := canonical(prop)
	if key == "constraint":
		return int(constraints.get(channel, 0))
	var value: Variant = SpriteState.read_prop(channel, key, overrides, sprites)
	if not SCORE_FLAGS.has(key) or overrides.get(channel, {}).has(key):
		return value
	for sprite in sprites:
		if int(sprite["channel"]) == channel:
			return 1 if bool(sprite.get(key, false)) else 0
	return value
