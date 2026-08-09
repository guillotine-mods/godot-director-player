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
	# Identity entries, listed rather than omitted. Each is its own field under
	# its own name and needs no translation -- but the reason it needs none is
	# exactly the fact this table exists to record, and a name absent from here
	# reads as "nobody has looked at it" rather than as "checked, and the two
	# vocabularies agree".
	#
	# `castlibnum` is 3 sites, and was live on the **read** only until the channel
	# model landed: the read answered it from the record's `cast_lib` and the merge
	# had no arm for it, so a script that *wrote* `the castLibNum of sprite N`
	# moved nothing on screen. Same half-a-property shape as the five above, one
	# seam further along.
	#
	# `ink`, `blend`, `forecolor` and `backcolor` are **0 sites in this corpus**,
	# and are here because Director has them (`AGENTS.md`: build Director, not this
	# game). They were in the same half-implemented state and worse: the release
	# table already carried rows for `ink`, `forecolor` and `backcolor`, handing
	# back auto-puppets for a merge that did not exist. Nothing here can exercise
	# them, so the merge is transcribed from `lingo-the.cpp` and unverified against
	# play -- `blend`'s conversion in particular, which is the only one of the four
	# that is not a straight copy.
	"castlibnum": "castlibnum",
	"ink": "ink",
	"blend": "blend",
	"forecolor": "forecolor",
	"backcolor": "backcolor",
}

## Canonical keys that reach the screen without being a channel field the model
## merges: the three the node routes before `sprite_state.gd` is ever reached.
##
## `constraint` is in `write` below, `cursor` and `loc` in `director_preview.gd`,
## and `visible` is the channel's own (`channel.gd:VISIBLE_KEY`) -- honoured by
## the painter and by the mouse test rather than merged into a sprite record.
##
## `puppet` is the fifth and it is the seventh instance of this file's whole
## subject, found by `tools/property_surface.gd` driving Director's own name list
## through the engine. `the puppet of sprite N` is `Sprite::_puppet` in the
## reference (`lingo-the.cpp:1746` reads it, `:2074` writes it) -- the same flag
## `puppetSprite N, TRUE` sets -- and this port keeps that flag under
## `channel.gd:PUPPET_KEY`, which is the string `"_puppet"`. So an unrouted
## `puppet` landed in the override entry under `"puppet"`, one underscore away
## from the thing it means:
##
##     puppetSprite 5, TRUE               is_puppet() true, the puppet of sprite 5 -> 0
##     set the puppet of sprite 6 to 1    is_puppet() false, the puppet of sprite 6 -> 1
##
## Both halves wrong and both round-tripping, at 12 corpus sites. Routed on the
## node rather than translated by an alias, because `puppetSprite N, TRUE` is not
## a field write: it takes a **copy of the channel as it stands**
## (`director_preview.gd:lingo_puppet_sprite`), and an alias onto `_puppet` would
## set the flag with no record behind it -- a channel frozen holding nothing.
## One mechanism, reached by its two spellings.
const ROUTED := ["constraint", "cursor", "loc", "puppet", "visible"]


## Does anything in this port read `prop` after a script writes it?
##
## Takes the **Lingo** spelling and canonicalises, so a caller asks the question
## in the vocabulary it has. False is not "no such property in Director" -- it is
## "this port will store it and nothing will ever look".
##
## **Derived from the channel model rather than listed beside it.** This was a
## hand-written table of eighteen keys, which is a second copy of `channel.gd`'s
## `FIELDS` and therefore a second thing to forget: the copy claimed `ink` and
## `blend` were consumed for as long as the merge had no arm for either, so the
## one diagnostic that exists to catch a half-implemented property was reporting
## that the two worst instances of it were fine. A property is consumed when it
## has a `FIELDS` row, because the row *is* the merge, and there is now no way to
## say otherwise here.
##
## `LingoDiagnostics` has had a `SPRITE_PROP` category since it was written and
## nothing had ever emitted one, because the check needs this list and there was
## nowhere for it to live that was not that second copy.
static func consumed(prop: String) -> bool:
	var key := canonical(prop)
	return SpriteState.FIELDS.has(key) or ROUTED.has(key)


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
## `constraint` answers from `constraints` and never reaches the channel table,
## which would answer 0 from its fall-through for a property the score record does
## not carry -- indistinguishable from "unconstrained", and so a write that
## round-trips as a lie. `write` has why it lives there.
##
## Everything else goes straight through. There used to be a second fallback here
## for `moveable` and `editable`, because the channel read had no arm for either
## and a sprite the *author* ticked Moveable or Editable on in the Score window
## read back as 0 until a script had written the property itself. That is the same
## half-a-property this file exists to prevent, seen from the read side -- and it
## is gone because the model reads a flag out of the score record for every
## `FIELDS` row of that kind, so the two sources of one property are one answer
## without a special case naming which two properties they are.
static func read(channel: int, prop: String, overrides: Dictionary,
		sprites: Array, constraints: Dictionary) -> Variant:
	var key := canonical(prop)
	if key == "constraint":
		return int(constraints.get(channel, 0))
	return SpriteState.read_prop(channel, key, overrides, sprites)
