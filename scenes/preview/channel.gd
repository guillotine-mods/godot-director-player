extends RefCounted
## One score channel, which is the thing this port did not have.
##
## Director keeps a persistent `Channel` per score channel, each owning a live
## `Sprite`, and every question about that channel is asked of that one object:
## what is on it, whether it is visible, whether the score may write it, and what
## each of its properties currently says. The frame's delta drives
## `releaseAutoPuppet` and then `setClean` against it, and nothing else in the
## engine touches the fields those two govern.
##
## This port had **a dictionary of override keys beside the score** and five
## functions that had to agree about what the keys meant. They did not, and the
## eight bugs that came out of that disagreement are one bug counted eight times:
## a property whose write landed in the bag and whose read came back correctly
## while nothing on the way to the screen ever looked at it. `moveableSprite`,
## `editableText`, `constraint`, `the member of sprite`, `flipH`/`flipV` were
## found one at a time by players noticing a sprite had not moved; `ink`,
## `blend`, `foreColor` and `backColor` were still in that state when this file
## was written, three of them with a *release* rule for a merge that did not
## exist.
##
## So the shape of the fix is not another arm in the merge. It is that **there is
## one description of a sprite property and everything is derived from it**:
## `FIELDS` below says, per property, which record field it writes, how the two
## spellings convert, and which score writes hand it back. `merged`, `read`,
## `release` and `sprite_props.CONSUMED` are all that table read from different
## sides, so a property cannot be half-implemented — adding a row implements it in
## every direction at once, and omitting one implements it in none.
##
## ## What a channel is made of
##
## The storage is the node's `_overrides[channel]` dictionary, unchanged, because
## `tools/` reads it by name and by shape (`scenes/preview/README.md`). This class
## is the rules that dictionary obeys, not a second copy of it: `entry` *is* the
## node's dictionary, GDScript dictionaries are reference types, and a write here
## is a write there.
##
## Its keys are two different things and that distinction is the whole model:
##
## - **Channel state** — `CHANNEL_KEYS`. `Channel::_visible` in the reference, and
##   the puppet bookkeeping this port needs because it draws from the score's
##   per-frame list rather than from a live sprite. No score write, no
##   `setClean`, and no `puppetSprite N, FALSE` may touch these, because in
##   Director they are not in the `Sprite` object any of those three replace.
## - **Sprite fields** — everything else, each one a `FIELDS` key. These are what
##   the score owns and a script borrows.
##
## The three operations that hand a channel back to the score — the auto-puppet
## release, `puppetSprite N, FALSE`, and dropping a spent entry — are all defined
## as "over the sprite fields", which is `entry` minus `CHANNEL_KEYS`. That is one
## rule in one place. It used to be three hand-written agreements, and the one
## time they disagreed, four dwarves and Renati walked back into shot.
##
## ## Auto-puppet is the presence of the key, and that is not a shortcut
##
## The reference keeps a value and a bit: `_width` and `kAPWidth`. Here the key's
## presence is the bit and the key's value is the value, which is the same model
## because the two die together — `releaseAutoPuppet` clears the bit and the very
## next `replaceFrom` overwrites the value from the score, so a value with no bit
## is never observable. For the properties with **no** release row (blend,
## editable, the flips, the rect) the bit never clears, so the key simply stays.
## Either way the port has one thing to store where the reference has two.
##
## The one place that is not true is `visible`, which is why it is channel state:
## it has a value and no bit at all, so keeping it in the same bag as the sprite
## fields meant every operation over those fields had to remember to step around
## it.

const LingoValue := preload("res://lingo/lingo_value.gd")
const Members := preload("res://scenes/preview/members.gd")

## `puppetSprite N, TRUE`. A **flag**, not merely an entry: an entry is what a
## property write makes too, and the two obey opposite rules about the score
## (§5.2 against §5.3), so an entry alone cannot tell them apart.
const PUPPET_KEY := "_puppet"

## The last record the *score* gave a whole-sprite puppeted channel, so the
## channel can outlive the score's per-frame list. Kept in the channel's own
## entry rather than in a second table on the node: it is puppet state, it must
## be dropped when the puppet is, and it rides the save with everything else.
const SCORE_KEY := "_score"

## `the visible of sprite N`. `Channel::_visible` in the reference, and reading
## every use of that field settles what it is: set true once when the channel is
## constructed, copied when a channel is copied, read by the painter, by the
## mouse test and by the property, and **written by exactly one thing, its own
## setter**. `replaceFrom` does not touch it, `setClean` does not touch it, and
## `puppetSprite N, FALSE` does not touch it.
##
## DAY1 is what makes that concrete: `init all` runs `sprite(6).visible = 0` on
## frame 0 where channel 6 is empty, and the hide has to survive until the beach
## 37 frames later gives that channel a member.
const VISIBLE_KEY := "visible"

## Everything in a channel entry that is **not** a sprite field.
##
## `_member` is listed because it *was* bookkeeping: states saved before the
## auto-puppet release became an event carry it, nothing reads it now, and a
## restored session would otherwise keep an entry alive for ever on the strength
## of a key that no longer means anything. It is not channel state — it is dead
## state — but for every operation here the two behave the same way, and naming
## it is what stops a stale save resurrecting a puppet.
const CHANNEL_KEYS := [VISIBLE_KEY, PUPPET_KEY, SCORE_KEY, "_member"]

## Entry keys a spent channel may hold and still be spent. `_score` is here and
## `visible` is not: a carried score record means nothing once the puppet that
## carried it is gone, while a hide is the one thing on a channel that only a
## script may lift.
const SPENT_KEYS := [SCORE_KEY, "_member"]

## Every sprite property a script can puppet, described once.
##
## Read four ways and written by hand nowhere else. Per row:
##
## - `field` — the score record's own name for it. The two vocabularies differ
##   more often than not (`moveablesprite`/`moveable`, `loch`/`loc_h`), and
##   `sprite_props.ALIASES` is the other half of that seam: it maps Director's
##   spelling onto the keys here.
## - `kind` — how one becomes the other. Lingo has integers where the record has
##   booleans, a member *reference* where the record has a library and a slot,
##   and a 0-100 blend where the record has an inverted byte.
## - `released_by` — the score-record fields whose **write** hands this property
##   back (§5.3). Transcribed from `Sprite::releaseAutoPuppet`, in this port's two
##   vocabularies; the only rewriting is where one spelling splits a field the
##   other keeps whole, so the reference's single `startPoint` is `loc_h` and
##   `loc_v` here and its `moveable` bit is inside `color_code`.
##
## **An empty `released_by` is a statement, not an omission.** The reference
## auto-puppets blend, editability, thickness (which carries the flips) and the
## rect on a write and releases none of them, so a script that sets `the blend of
## sprite` holds it against the score until something un-puppets the channel.
## That asymmetry is Director's; inventing the missing rows would be inventing
## Director.
##
## §5.4 is the entry worth reading twice: a **cast-id** write releases the width
## and the height as well, because in Director a member swap is what re-derives a
## sprite's size, so a size taken against the old member cannot survive one.
const FIELDS := {
	# The member, in Director's two spellings, which are two properties and not
	# one. `the memberNum of sprite` is a bare per-library slot number and every
	# site that does arithmetic on it wants exactly that; `the castNum of sprite`
	# is a *reference*, and it has to survive being handed straight back to
	# `member()`. This port packs the (library, slot) pair into one integer that
	# `member()` accepts either way (§1.6), so both write here and only the read
	# differs.
	#
	# Merged as a bare member number, a packed reference addressed slot 131,073 of
	# library 1 and drew nothing at all -- which is what `set the castNum of
	# sprite 4 to the castNum of sprite 9` did.
	"membernum": {
		"field": "cast_id", "kind": "member", "group": "cast",
		"released_by": ["cast_lib", "cast_id"],
	},
	"castnum": {
		"field": "cast_id", "kind": "member_ref", "group": "cast",
		"released_by": ["cast_lib", "cast_id"],
	},
	# `the castLibNum of sprite N` -- the library half of `the member of sprite`.
	# In the reference a write here is a `setCast` with the member number kept and
	# the library replaced, which is why it belongs with the two above rather than
	# after them: everything below reads the merged library, and the artwork, the
	# drawn size, the texture-cache key and the hit-test sample all key on it.
	# Piposh Dream's Fritz duel is the corpus site -- `the castLibNum of sprite
	# getAt(ppl, 1) = 2` asks which library a fighter's current frame came from.
	"castlibnum": {
		"field": "cast_lib", "kind": "int", "group": "cast",
		"released_by": ["cast_lib", "cast_id"],
	},
	# A script that writes `the width of sprite` resizes it, and `size_from_script`
	# is what carries that to the renderer: `sprite_geometry.drawn_size` draws an
	# unstretched sprite at its member's natural size because the score's rect is
	# residue, and a size a script wrote is not residue. Director gets there by
	# another route -- `Sprite::setWidth` sets the width auto-puppet, which stops
	# the score writing over it, and `getBbox` uses whatever the sprite holds.
	#
	# The stretch flag itself must **not** be set: it does not mean "is resized",
	# it means "the author resized this deliberately", and all it governs is
	# whether a cast swap may reset the size back to the member's natural one. In
	# Director a script-set width does not survive one.
	"width": {
		"field": "width", "kind": "size",
		"released_by": ["cast_lib", "cast_id", "width"],
	},
	"height": {
		"field": "height", "kind": "size",
		"released_by": ["cast_lib", "cast_id", "height"],
	},
	"loch": {
		"field": "loc_h", "kind": "int", "released_by": ["loc_h", "loc_v"],
	},
	"locv": {
		"field": "loc_v", "kind": "int", "released_by": ["loc_h", "loc_v"],
	},
	# `the ink of sprite N`. Stored and merged by nothing until this table existed,
	# while `releaseAutoPuppet`'s row for it was already transcribed -- a release
	# rule for a merge that was not there, which is the clearest possible statement
	# that the two sides had stopped being one description.
	"ink": {"field": "ink", "kind": "int", "released_by": ["ink"]},
	# `the trails of sprite N` is a real Director property and the only way a movie
	# can ask for the accumulation buffer at runtime; the score's own trails bit is
	# the other. Merged here so the two arrive at the renderer as one field and
	# `_draw` has a single thing to test. It rides the ink byte, which is why the
	# score's *ink* write is what releases it.
	"trails": {"field": "trails", "kind": "bool", "released_by": ["ink"]},
	# `the blend of sprite N` is 0-100 and the record's byte is
	# `(100 - blend) * 255 / 100`, so 0 is opaque and 255 is invisible. Both
	# directions of that conversion are `kind`, because a property with a
	# conversion on only one side reads back a different number than was written.
	# No release row: the reference auto-puppets it and never takes it back.
	"blend": {"field": "blend_amount", "kind": "blend", "released_by": []},
	"forecolor": {
		"field": "fore_color", "kind": "int", "released_by": ["fore_color"],
	},
	"backcolor": {
		"field": "back_color", "kind": "int", "released_by": ["back_color"],
	},
	# `the moveableSprite of sprite N` and the score's own moveable bit are one
	# property from two sources. Before the merge existed a sprite the author
	# ticked "Moveable" on in the Score window could not be dragged at all and was
	# not even click-eligible; 744 of Piposh 1's records set it, and Piposh 2 sets
	# it on none, which is why nothing missed it until a second title was loaded.
	"moveable": {
		"field": "moveable", "kind": "bool", "released_by": ["color_code"],
	},
	# Editability is `sprite OR member` (§8.4), and this is the sprite half. The
	# member half is `director_cast.gd`'s byte 25 bit 0, which is where every
	# editable field in all three titles actually comes from -- 0 of 3,550,111
	# sprite records set the score's own bit. It is here because Director has it.
	# The reference releases it on nothing, and preserves it across a member swap
	# by hand (§5.4).
	"editable": {"field": "editable", "kind": "bool", "released_by": []},
	# `the flipH of sprite N` and `the flipV of sprite N`. `sprite_art.gd` has
	# drawn from these names since before the score's own flip bits were decoded,
	# and it mirrors the hit-test sample with them too, so the whole chain was in
	# place and the write landed at the far end of it. 456 sites across Piposh
	# Dream, which both reads and writes them. They ride the thickness byte, which
	# the reference auto-puppets and never releases.
	"flip_h": {"field": "flip_h", "kind": "bool", "released_by": []},
	"flip_v": {"field": "flip_v", "kind": "bool", "released_by": []},
}

## What a property reads as on a channel that holds no sprite this frame.
##
## **An empty channel is not a zeroed sprite.** In Director these are properties
## *of the channel*, and a channel with nothing in it is a visible channel that
## happens to be empty. Answering 0 for everything conflates "no sprite here"
## with "a script set this to 0", and the two are different questions.
##
## `strtgame.dir`'s Load button is what that cost. Its whole body sits inside
## `if sprite(30).visible = 1 then` -- a guard copied from the in-game menus,
## where channel 30 is the walking player and the test means "not mid-cutscene".
## On the main menu there is no player: channel 30 is occupied in 0 of 1,375
## frames. The guard passed in 1997 and failed here, so clicking Load did nothing
## at all and looked like "there is no save to load" (bugs.md 34).
##
## Only the ones with a meaningful default are listed; everything else answers 0,
## which is what "nothing here" means for a member number or a position.
const EMPTY_CHANNEL := {
	VISIBLE_KEY: 1,
	"ink": 0,
	"blend": 100,
}

## The channel number. Carried so that a `Channel` answers for itself rather than
## needing the caller to remember which one it asked for.
var number: int

## The channel's own entry in the node's `_overrides`. The same dictionary, not a
## copy -- see the header.
var entry: Dictionary


func _init(channel: int, channel_entry: Dictionary) -> void:
	number = channel
	entry = channel_entry


## This script, so the two factories below can live beside the model they build
## rather than in the module that calls them. A GDScript static function has no
## `new()` of its own to reach for and this file carries no `class_name` -- the
## global class cache is generated by the editor and a headless run on a fresh
## checkout has none (`AGENTS.md`), so a new one is a name that resolves on the
## machine it was written on and nowhere else.
const Self := preload("res://scenes/preview/channel.gd")

## The channel `number`, for reading. Never inserts: a channel nothing has
## touched gets an entry of its own that is not in the table, so a read cannot
## make `hilite.gd` believe a script is composing something here.
static func at(channel: int, overrides: Dictionary):
	return Self.new(channel, overrides.get(channel, {}))


## The channel `number`, for writing. Inserts the entry if this is the first
## thing to claim it.
static func claim(channel: int, overrides: Dictionary):
	if not overrides.has(channel):
		overrides[channel] = {}
	return Self.new(channel, overrides[channel])


# ---------------------------------------------------------------- channel state


func is_puppet() -> bool:
	return bool(entry.get(PUPPET_KEY, false))


func is_visible() -> bool:
	return LingoValue.to_int(entry.get(VISIBLE_KEY, 1)) != 0


## Is anything left on this channel that a script put there?
##
## An entry holding nothing but spent bookkeeping is not a puppet, and leaving it
## behind would make the merge duplicate the record for no merge and make
## `hilite.gd` believe a script is composing a picture here.
func is_spent() -> bool:
	for key in entry:
		if not SPENT_KEYS.has(key):
			return false
	return true


# --------------------------------------------------------------- sprite fields


## Every sprite field this channel currently holds, which is every auto-puppeted
## property plus whatever a whole-sprite puppet is carrying.
##
## The one definition of "sprite field", used by the merge, by the release and by
## both ways of handing the channel back. Everything that is not channel state is
## one, including a key `FIELDS` has no row for: `write` stores any key at all, so
## a property this port does not yet describe still has to be handed back with the
## rest rather than left behind for ever.
func sprite_fields() -> Array:
	var out: Array = []
	for key in entry:
		if not CHANNEL_KEYS.has(key):
			out.append(key)
	return out


## `Sprite::replaceFrom`, from the other end: the score's record for this frame
## with every field a script holds against it merged in.
##
## **Visibility is not consulted here**, and that is the model rather than an
## oversight. `Channel::_visible` gates the *painter* and the mouse test; it is
## not a field of the sprite the score writes, so a hidden channel still has a
## member, a position and a size, and `the memberNum of sprite` still answers
## them. `effective` in `sprite_state.gd` is where the two are combined, for the
## callers that draw.
func merged(sprite: Dictionary, table) -> Dictionary:
	if entry.is_empty():
		return sprite
	var out := sprite.duplicate()
	# The cast group first, and then the size the swap implies, and then
	# everything else -- which is the order Director does it in. `Channel::setCast`
	# calls `Sprite::setCast` with `replaceDims = !stretch`, and only afterwards
	# does a `setWidth` from a script override the result. Merging width before
	# the swap would let the swap overwrite a size a script had just asked for.
	for key in FIELDS:
		if str(FIELDS[key].get("group", "")) == "cast" and entry.has(key):
			_merge_one(key, out)
	_resize_for_swap(sprite, out, table)
	for key in FIELDS:
		if str(FIELDS[key].get("group", "")) != "cast" and entry.has(key):
			_merge_one(key, out)
	return out


## Director's `setCast` rule: a member swap replaces the sprite's width and height
## with the new member's natural size, unless the stretch flag says the author
## deliberately resized this sprite.
##
## It matters because the score's width and height describe whatever member the
## *score* put on this channel, and a script that swaps the member leaves them
## describing the wrong artwork. This game walks its characters entirely by member
## swap -- `member("walkright" & syz & x)`, where `syz` is one of six size tiers
## and `x` the animation frame -- and never writes a width or a height anywhere.
## Without this every frame of the cycle is squashed into the previous one's rect,
## which reads as the character stretching as his arms move, and all six size tiers
## draw at one size, which reads as perspective scaling that stopped working.
##
## **The library the new size is looked up in is the merged one**, not the score's.
## A swap that changes only the library still changes the artwork, so reading the
## natural size out of the library the script just left would answer for a member
## on the other side of the swap.
func _resize_for_swap(sprite: Dictionary, out: Dictionary, table) -> void:
	if table == null or bool(sprite.get("stretch", false)):
		return
	if int(out["cast_id"]) == int(sprite["cast_id"]) \
			and int(out["cast_lib"]) == int(sprite["cast_lib"]):
		return
	var swapped: Dictionary = table.get_member(
		int(out["cast_lib"]), int(out["cast_id"]))
	if int(swapped.get("width", 0)) > 0 and int(swapped.get("height", 0)) > 0:
		out["width"] = int(swapped["width"])
		out["height"] = int(swapped["height"])


## One property, from the value a script wrote into the field the record names.
##
## Coerced through Lingo's own rules rather than GDScript's. A script can
## legitimately store VOID -- `set the locH of sprite 30 to egozh` when `egozh`
## has never been set does exactly that -- and `int(null)` is not a conversion in
## GDScript, it is a runtime error that aborts whatever is running. This one
## aborted `_draw` partway through, every frame, so the sprites after it in
## channel order simply vanished. VOID is 0 in Director's numeric context, which
## is what `LingoValue.to_int` answers.
func _merge_one(key: String, out: Dictionary) -> void:
	var row: Dictionary = FIELDS[key]
	var value: Variant = entry[key]
	var raw := LingoValue.to_int(value)
	match str(row["kind"]):
		"member", "member_ref":
			# A member reference carries its library and a member number does not,
			# and this is where the two spellings stop being interchangeable. A
			# packed value unpacks into both halves; a bare one addresses the
			# library the sprite is already in.
			if raw >= Members.LIB_STRIDE:
				out["cast_lib"] = raw / Members.LIB_STRIDE + 1
				out["cast_id"] = raw % Members.LIB_STRIDE
			else:
				out["cast_id"] = raw
		"bool":
			out[str(row["field"])] = raw != 0
		"size":
			out[str(row["field"])] = raw
			out["size_from_script"] = true
		"blend":
			out[str(row["field"])] = clampi((100 - clampi(raw, 0, 100)) * 255 / 100, 0, 255)
		_:
			out[str(row["field"])] = raw


# ------------------------------------------------------------- the score writes


## `Sprite::releaseAutoPuppet`: the score has written `written` (record-field
## names) on this channel, so every property those writes own goes back to it.
##
## **This is an event, not a comparison.** A per-field auto-puppet is released
## when the score *writes* that property (§5.3), which the reference implements by
## handing `releaseAutoPuppet` the set of fields the frame's own delta touched. A
## score that rewrites a channel with the member it already had has still written
## it. Inferring the release from "the member under the override is not the one it
## was taken against" is the same answer on every frame where the two differ and
## silence on every frame where they do not -- and `bugs.md` 47 is the second case
## in the field: click the dwarf at `exitforest3` and `BehaviorScript 281` writes
## his talking loop onto channel 18, but the score puts `adnzlop1` on channel 18
## both in the room and inside `dnzclicktalk`, so the write was never released and
## the mouth kept moving for the rest of the movie.
##
## A **whole-sprite** puppet is skipped entirely, and not as an optimisation: the
## reference's `setAutoPuppet` returns without doing anything while `_puppet` is
## set, so such a channel cannot be released by the score any more than it can be
## written by it (§5.2).
func release(written: Dictionary) -> void:
	if entry.is_empty() or is_puppet():
		return
	for key in sprite_fields():
		var row: Dictionary = FIELDS.get(key, {})
		for field in (row.get("released_by", []) as Array):
			if written.has(field):
				entry.erase(key)
				break


## `puppetSprite N, FALSE` -- and `TRUE`.
##
## **It returns the *sprite* to the score and leaves the channel alone**, and the
## difference is a bug report with three saves behind it. The reference puts the
## whole of the release in one line -- `chan->setClean(the score's record for this
## channel)` -- and `setClean` replaces the `Sprite` object's fields. A channel's
## own state is not in that object and is not restored with it.
##
## This used to erase the channel's whole entry, so a script that had hidden a
## sprite and later un-puppeted the channel un-hid it as a side effect. In DAY1
## that is four of the dwarves and Renati: the walk-away path runs
## `puppetSprite(i, 0)` over a range of channels that `init all` had hidden with
## `sprite(i).visible = 0`, and they all came back mid-walk. The player-visible
## symptom is characters appearing out of nowhere while somebody walks off, which
## is why it read as an animation fault rather than as a puppet one.
##
## It cannot come back, because the release is stated over `sprite_fields()` and
## the hide is not one. That is the same sentence `release` above is written from.
func set_puppet(on: bool) -> void:
	if on:
		entry[PUPPET_KEY] = true
		return
	for key in sprite_fields():
		entry.erase(key)
	entry.erase(PUPPET_KEY)
	for key in SPENT_KEYS:
		entry.erase(key)


## The record the score has for this channel on the frame the playhead is on,
## remembered so a whole-sprite puppet can outlive the score's own list.
##
## Director does not need this: its channel *is* the live sprite, so there is
## nothing to carry. A port that draws the score's per-frame sprite list has to
## keep the last record the score gave, or the channel has nothing to be when the
## list stops carrying it.
func note_score(sprite: Dictionary) -> void:
	entry[SCORE_KEY] = sprite


## What this channel keeps on the frame when the score has let go, or `{}` when
## there is nothing to carry.
##
## **A script that gives a channel a member makes it live**, whether or not
## anyone said `puppetSprite`. That is the reference's rule and it is not a
## special case there: `_channels` holds one `Channel` for every channel however
## few the frame carries, `Sprite::setCast` raises the `kAPCast` auto-puppet
## (`sprite.h:41`, `channel.cpp:649`), and `setClean` then refuses to replace the
## sprite from the score (`channel.cpp:534`). The channel simply keeps being what
## the script made it.
##
## This port draws the score's per-frame sprite list instead, so "keeps being"
## has to be spelled out -- and it used to be spelled `is_puppet()` alone, which
## is only the explicit half. Itamar Park's arcade is the whole cost of that
## missing half: `MovieScript 6 - play handlers1` moves eighteen object channels
## with `sprite(n).member = "AntFood9"` and never puppets one, so all eighteen
## were alive in `_overrides` and scrolling correctly while `frame_sprites()`
## never returned them. The player walked an empty ice sheet and the food bar
## drained with nothing to eat, and the level ended by starvation -- which is the
## *game's* correct response to a level with no food in it.
##
## **A member is what makes it live, not any write at all.** The reference draws
## a channel whose sprite has a cast member; a script that writes only a position
## to an empty channel has said nothing about what to draw there, and inventing
## something would put a sprite on the stage no title asked for. So the test is
## the cast group of `FIELDS` -- the same three rows the merge treats as the cast
## swap -- and nothing else.
func carried() -> Dictionary:
	if is_puppet():
		return entry.get(SCORE_KEY, {})
	if not _holds_a_member():
		return {}
	return entry.get(SCORE_KEY, _bare_sprite())


## Has a script put a member on this channel?
func _holds_a_member() -> bool:
	for key in FIELDS:
		if str(FIELDS[key].get("group", "")) == "cast" and entry.has(key):
			return true
	return false


## A sprite record for a channel the score has never carried, for the merge to
## write the script's own fields onto.
##
## Not an invention: it is `Sprite`'s own constructed state in the reference --
## no cast, ink 0, the default colours, and a zero size that `setCast` replaces
## with the member's natural one because `stretch` is false. `merged` runs the
## cast group first and then `_resize_for_swap`, so the size arrives there by the
## same path a score-carried swap uses rather than by a second rule here.
##
## `carried()` prefers a remembered score record over this whenever there is one,
## so a channel the score used to carry keeps that record's ink and flags -- as
## the reference's channel keeps the sprite it last had.
func _bare_sprite() -> Dictionary:
	return {
		"channel": number,
		"cast_lib": 1,
		"cast_id": 0,
		"loc_h": 0,
		"loc_v": 0,
		"width": 0,
		"height": 0,
		"ink": 0,
		"stretch": false,
		"trails": false,
		"sprite_type": 0,
		"fore_color": 255,
		"back_color": 0,
		"thickness": 1,
		"has_blend": false,
		"flip_h": false,
		"flip_v": false,
	}


# -------------------------------------------------------- the property surface


## `the <prop> of sprite N`, read back.
##
## Two layers, in the order the reference has them: what a script holds, then what
## the score says, then what an empty channel says. A stale first layer is not
## possible any more -- `release` takes the key out of the entry on the frame
## change, so there is no invalidated value left for this and the merge to
## disagree about, which they did until the release became an event.
##
## Any key at all answers from the first layer, including one `FIELDS` has no row
## for. `write` stores anything, so a property this port does not describe still
## round-trips; what it does not do is reach the screen, and
## `sprite_props.CONSUMED` is the list that says which those are.
func read(prop: String, sprite: Dictionary) -> Variant:
	if entry.has(prop):
		# **A script's own write still has to be read back through the row's kind.**
		# This returned the stored value raw, so the `member`/`member_ref` split
		# below held only while the score owned the channel and collapsed the
		# moment a script wrote one -- and `member()` evaluates to a *packed*
		# reference, so `set the member of sprite 15 to member(3, 2)` stored
		# 131,075 and `the memberNum of sprite 15` answered 131,075 instead of 3.
		#
		# `preview/members.gd:pack_ref` predicted exactly this and nobody
		# re-measured it: "reusing it anywhere the integer might be *stored* would
		# need that claim re-measured." The override entry is where it is stored.
		#
		# The cost is every script that does arithmetic on a member number after
		# writing one, which in this corpus is the games that animate a character
		# by walking their member along. `hatuli.cst`'s `hatulidown`/`hatuliup`
		# gate every movement branch on `the memberNum of sprite 15` against 2, 18,
		# 29 and 40; at 131,075 `< 29` is false and `> 18` is true, so the branches
		# fail in *both* directions and the player cannot move at all. Piposh
		# Dream's Fritz duel reads the same property against 18 and 46.
		#
		# Answered through `_merge_one` rather than by unpacking here, because the
		# split is already written once and a second copy is the shape this file's
		# own comments keep warning about -- two places agreeing by both saying the
		# same thing, until one of them gains a case.
		var kind := str((FIELDS.get(prop, {}) as Dictionary).get("kind", ""))
		if kind == "member" or kind == "member_ref":
			var split: Dictionary = {
				"cast_lib": int(sprite.get("cast_lib", 1)) if not sprite.is_empty() else 1,
				"cast_id": 0,
			}
			# A `castLibNum` the same script wrote wins over the score's library,
			# for the same reason the merge lets it: it is the later statement.
			if entry.has("castlibnum"):
				_merge_one("castlibnum", split)
			_merge_one(prop, split)
			if kind == "member":
				return int(split["cast_id"])
			return Members.pack_ref(int(split.get("cast_lib", 1)), int(split["cast_id"]))
		return entry[prop]
	if sprite.is_empty():
		return EMPTY_CHANNEL.get(prop, 0)
	if prop == VISIBLE_KEY:
		return 1
	var row: Dictionary = FIELDS.get(prop, {})
	if row.is_empty():
		return EMPTY_CHANNEL.get(prop, 0)
	var field := str(row["field"])
	match str(row["kind"]):
		"member":
			return int(sprite["cast_id"])
		"member_ref":
			# **Not the same answer as `membernum`, and that is the whole point of
			# the two spellings.** These were one arm, and Piposh 1's ship map is
			# what that cost. Every deck movie opens with `set nof to the name of
			# member the castNum of sprite 1` -- the backdrop on channel 1 is named
			# for the deck position, and that line is how the game learns where the
			# player is standing. Channel 1 is `2:1` in DAY1, so a bare `1` came
			# back, resolved in library 1, and `nof` became `"walkright1"` instead
			# of `"dl1"`. The map's `enterFrame` hides the walking Piposh for any
			# `nof` of four characters or more and every one of its `mouseUp`
			# handlers is gated on `the visible of sprite 20 = 1`, so one wrong
			# library removed the figure *and* every destination on the menu.
			return Members.pack_ref(
				int(sprite.get("cast_lib", 1)), int(sprite["cast_id"]))
		"bool":
			# From the score's own byte when no script has written it, so a movie
			# that reads a property back before setting it gets what the author put
			# there rather than a default.
			return 1 if bool(sprite.get(field, false)) else 0
		"blend":
			return (255 - clampi(int(sprite.get(field, 0)), 0, 255)) * 100 / 255
		_:
			return int(sprite.get(field, EMPTY_CHANNEL.get(prop, 0)))


## `set the <prop> of sprite N`.
##
## The write *is* the auto-puppet: Director puppets the one property on the write
## and releases it when the score writes that property back (§5.3), which is
## `release`. There is nothing to record about the member the write was taken
## against -- that was this port's proxy for the release event, and it answered
## the wrong question whenever a clip and the room it was entered from put the
## same member on a channel (`bugs.md` 47).
func write(prop: String, value: Variant) -> void:
	entry[prop] = value
