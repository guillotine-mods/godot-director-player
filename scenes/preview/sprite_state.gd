extends RefCounted
## What a script has puppeted onto a sprite, and how that merges with the score.
##
## The state itself stays on the node, because `tools/` reads `_overrides` by
## name and a field that moved would make those reads return null rather than
## fail. So every function here takes the dictionaries it works on. That is not
## a compromise: `_overrides` is mutated in place by three of them, and GDScript
## dictionaries are reference types, so passing them reads exactly as owning
## them and the node keeps the name the harnesses look for.
##
## **Director has two kinds of puppet and they obey opposite rules**, and holding
## both in one place is what this module is for.
##
## A property write auto-puppets that *one field* (§5.3). The score keeps writing
## everything else every frame, and the auto-puppet itself is released the moment
## the score writes that same property. Handing the whole record over because one
## property was set freezes a sprite against its own animation -- and this game
## walks its characters entirely by member swap, so that would be every character
## in it.
##
## `puppetSprite N, TRUE` claims the *whole sprite* (§5.2). The score is not
## applied to that channel at all, so nothing on it can go stale and nothing on
## it is released -- including the channel's very existence: a puppeted sprite
## stays on frames whose score record for it is empty, which is how a player
## character survives a cut scene the score does not carry it through.
##
## The two were one concept here until `bugs.md` 36, and one concept cannot be
## both: it is either sticky enough for the second rule or loose enough for the
## first. It was sticky, so a talking mouth never stopped; and it had no notion of
## a channel outliving the score, so the player disappeared. One missing
## distinction, two reports that looked unrelated.

const LingoValue := preload("res://lingo/lingo_value.gd")
const Members := preload("res://scenes/preview/members.gd")


## A sprite as it currently stands: the score's record with whatever a script
## has puppeted onto it. `{}` when a script has hidden it.
##
## Every path that asks about a sprite goes through this -- drawing,
## hit-testing, `rollOver`. They diverged before: the screen showed the puppeted
## member while a click was tested against the score's, so a menu button was
## only clickable where its two states happened to overlap, and moving the mouse
## made it flicker in and out of reach.
##
## `overrides` is mutated here, not just read: a puppet the score has moved out
## from under is discarded at the moment that is noticed.
##
## **`ignore_visible` is for the one caller that must not honour the hide**, and
## it is a flag rather than a second merge path because the stale-puppet discard
## below mutates `overrides`: two paths would drift apart in behaviour, not
## merely in code. Director asks two different rect questions and only one of
## them consults visibility -- `channel.cpp:isMouseIn` reads `_visible` and is
## the only thing in that file that does; `c_within` and `c_intersects` read
## `getBbox()`. See `director_preview.lingo_sprite_rect`, which also records why
## that was briefly reverted and why the revert was wrong.
static func effective(
	sprite: Dictionary, overrides: Dictionary, table, ignore_visible: bool = false,
	peek: bool = false
) -> Dictionary:
	var channel := int(sprite["channel"])
	var over: Dictionary = overrides.get(channel, {})
	if over.is_empty():
		return sprite
	# The distinction between per-field and per-sprite matters when the score
	# changes the member underneath: a script that pinned `locV` once should keep
	# that and still follow the score's member swaps.
	#
	# **Unless the channel is a whole-sprite puppet**, which is a different thing
	# from the per-field auto-puppet below and the one Director's own
	# `replaceFrom` short-circuits on (§5.2): with `_puppet` set it copies the
	# script attachment and returns, so *nothing* the score says about this
	# channel is applied and nothing here can be stale. Without the distinction
	# there is only one kind of puppet, and it has to be either too sticky or not
	# sticky enough -- `bugs.md` 36 is both halves of that at once.
	if not bool(over.get("_puppet", false)) \
			and int(over.get("_member", -1)) != int(sprite["cast_id"]):
		# The score moved this channel to a different member, so every auto-puppet
		# on it is released (§5.3: released when the score itself writes that
		# property, and §5.4: a cast-id write releases the size as well).
		# Geometry belongs to the new member, so positional overrides taken
		# against the old one are stale -- **and so is the member a script
		# wrote.** That last clause used to read `and not over.has("membernum")`,
		# which made a script's member swap outlive the score's for the rest of
		# the movie: click Tofi on the veranda and `BehaviorScript 291` puts
		# `btofspk1` -- his *talking* loop -- on channel 18, the clip finishes and
		# returns to `veranda` where the score says `atoflop1`, and the mouth kept
		# moving for ever because the swap was never released. Nine `clicktalk`
		# clips and six `<room>talk` clips do the same thing.
		#
		# `visible` is not geometry and does not go with them. It is channel
		# state, like `the cursor of sprite`: Director does not un-hide a sprite
		# because the score moved that channel to another member, and a port that
		# does gets a very specific bug -- a room hides something during its
		# initialisation and it reappears later, looking like a rendering fault.
		#
		# DAY1 is the case that found this. Its `init all` runs as the frame
		# script on frame 0 and does `sprite(6).visible = 0`, but channel 6 is
		# *empty* on frame 0, so no member was ever recorded against the
		# override. The moment channel 6 acquires a member -- at the beach, 37
		# frames later -- the test below fires and the sprite is un-hidden. The
		# hide was guaranteed to be discarded before it could ever apply.
		var kept: Dictionary = {"_member": int(sprite["cast_id"])}
		if over.has("visible"):
			kept["visible"] = over["visible"]
		# **A look-ahead may not release anything.** `peek` asks the same question
		# about a frame the playhead has not reached, and the release is keyed on
		# "the score has moved this channel" -- which is true of *every* later
		# frame that holds a different member, whether or not the movie ever plays
		# it. Recording it there discards a puppet the current frame is still
		# using: `director_preloader.gd` walks 24 frames ahead every step, so on
		# DAY1 the frame after a talk clip alone was releasing channel 18's
		# override once per step, and the write a script had just made survived
		# exactly one tick. The answer is the same either way; only the record is
		# withheld.
		if not peek:
			if kept.has("visible"):
				overrides[channel] = kept
			else:
				overrides.erase(channel)
		over = kept
		if not ignore_visible and int(LingoValue.to_int(over.get("visible", 1))) == 0:
			return {}
		return sprite
	if not ignore_visible and int(LingoValue.to_int(over.get("visible", 1))) == 0:
		return {}
	var out := sprite.duplicate()
	for key in ["membernum", "castnum"]:
		if over.has(key):
			out["cast_id"] = int(over[key])
	# Director's `setCast` rule: a member swap replaces the sprite's width and
	# height with the new member's natural size, unless the stretch flag says the
	# author deliberately resized this sprite.
	#
	# It matters here because the score's width and height describe whatever
	# member the *score* put on this channel, and a script that swaps the member
	# leaves them describing the wrong artwork. This game walks its characters
	# entirely by member swap -- `member("walkright" & syz & x)`, where `syz` is
	# one of six size tiers and `x` the animation frame -- and never writes a
	# width or a height anywhere. So without this every frame of the cycle is
	# squashed into the previous one's rect, which reads as the character
	# stretching as his arms move, and all six size tiers draw at one size, which
	# reads as perspective scaling that stopped working.
	if int(out["cast_id"]) != int(sprite["cast_id"]) and not bool(sprite["stretch"]):
		var swapped: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(out["cast_id"])
		)
		if int(swapped.get("width", 0)) > 0 and int(swapped.get("height", 0)) > 0:
			out["width"] = int(swapped["width"])
			out["height"] = int(swapped["height"])
	# A script that writes `the width of sprite` resizes it. Deliberately without
	# setting `stretch`: the flag does not mean "is resized", it means "the author
	# resized this deliberately", and all it governs is whether a cast swap is
	# allowed to reset the size back to the member's natural one. Forcing it here
	# changed which branch the drawn size and the texture cache took, for a
	# property that should only have changed a number.
	#
	# Coerced through Lingo's own rules rather than GDScript's. A script can
	# legitimately store VOID here -- `set the locH of sprite 30 to egozh` when
	# `egozh` has never been set does exactly that -- and `int(null)` is not a
	# conversion in GDScript, it is a runtime error that aborts whatever is
	# running. This one aborted `_draw` partway through, every frame, so the
	# sprites after it in channel order simply vanished. VOID is 0 in Director's
	# numeric context, which is what `LingoValue.to_int` answers.
	#
	# `size_from_script` is what carries that distinction to the renderer.
	# `sprite_geometry.drawn_size` draws an unstretched sprite at its member's
	# natural size, because the score's rect is residue; a size a script wrote is
	# not residue and has to survive that. Director gets there by another route --
	# `Sprite::setWidth` sets the width autopuppet, which stops the score writing
	# over it, and `getBbox` then uses whatever the sprite holds. The flag itself
	# still must not be set: it governs whether a later cast swap may reset the
	# size, and in Director a script-set width does not survive one.
	if over.has("width"):
		out["width"] = LingoValue.to_int(over["width"])
		out["size_from_script"] = true
	if over.has("height"):
		out["height"] = LingoValue.to_int(over["height"])
		out["size_from_script"] = true
	if over.has("loch"):
		out["loc_h"] = LingoValue.to_int(over["loch"])
	if over.has("locv"):
		out["loc_v"] = LingoValue.to_int(over["locv"])
	# `the trails of sprite N` is a real Director property and the only way a
	# movie can ask for the accumulation buffer at runtime; the score's own
	# trails bit is the other. Merged here so the two arrive at the renderer as
	# one field and `_draw` has a single thing to test.
	if over.has("trails"):
		out["trails"] = LingoValue.to_int(over["trails"]) != 0
	# `the moveableSprite of sprite N` and the score's own moveable bit are the
	# same property from two sources, exactly as trails is, and they are merged
	# here for the same reason. Before this only the Lingo write existed, so a
	# sprite the author ticked "Moveable" on in the Score window could not be
	# dragged at all and was not even click-eligible -- an authoring-time property
	# that simply did nothing. 744 of Piposh 1's records set it; Piposh 2 sets it
	# on none, which is why nothing missed it until a second title was loaded.
	if over.has("moveable"):
		out["moveable"] = LingoValue.to_int(over["moveable"]) != 0
	# `the editableText of sprite N`, by the same rule and for the same reason.
	# It arrives normalised to `editable` by `sprite_props.gd` -- the seam exists
	# because Director's spelling and the record's key differ, and three separate
	# bugs this session were one half of a property reaching nothing: dragging
	# was dead because `moveablesprite` never became `moveable`, and this one was
	# stored, read back correctly, and consumed by nobody.
	#
	# Editability is `sprite OR member` (§8.4), and this is the sprite half. The
	# member half is `director_cast.gd`'s byte 25 bit 0, which is where every
	# editable field in all three titles actually comes from -- 0 of 3,550,111
	# sprite records set the score's own bit, so nothing in this corpus reaches
	# the line below. It is here because Director has it.
	if over.has("editable"):
		out["editable"] = LingoValue.to_int(over["editable"]) != 0
	# `the flipH of sprite N` and `the flipV of sprite N`, normalised to the score
	# record's own spelling at the seam. `sprite_art.gd` has drawn from `flip_h` /
	# `flip_v` since before the score's own flip bits were decoded, and it mirrors
	# the hit-test sample with them too -- so this is the last link of a chain that
	# was otherwise complete. Without it, 456 sites across Piposh Dream store a flag
	# nothing reads: the fifth instance of one half of a property reaching nothing,
	# after `moveableSprite`, `editableText`, `constraint` and `the member of sprite`.
	if over.has("flip_h"):
		out["flip_h"] = LingoValue.to_int(over["flip_h"]) != 0
	if over.has("flip_v"):
		out["flip_v"] = LingoValue.to_int(over["flip_v"]) != 0
	return out


## The frame's sprites, plus the channels a whole-sprite puppet keeps alive that
## this frame's score does not carry.
##
## **A `puppetSprite N, TRUE` channel is not reconciled from the score at all.**
## Director's `Sprite::replaceFrom` copies the script id and returns when
## `_puppet` is set (§5.2), so the live channel keeps its member, position and
## size through frames whose score record for it is empty — and §5.5: nothing in
## the frame loop clears a whole-sprite puppet implicitly, so it survives frame
## jumps and `go to` and dies only with the movie. A port that draws the score's
## per-frame sprite list instead loses the sprite the moment the score stops
## carrying it.
##
## That is `bugs.md` 36's second symptom and all three of the reports filed
## against it. DAY1 puppets channel 30 — the player — in `init all`, and its
## `lilout1`, `lilclicktalk` and `dnzclicktalk` clips carry **no channel 30 at
## all**, so the player vanished for the length of somebody else's conversation
## and came back when the clip returned to the room. `tofclicktalk` does carry
## one, which is exactly why the same fault was reported as two different bugs.
##
## The record carried is the last one the *score* gave that channel, kept under
## `_score` in the channel's own override entry rather than in a second table on
## the node: it is puppet state, it must be dropped when the puppet is, and it
## rides the save with everything else in `_overrides`.
##
## Returns `sprites` itself when nothing is carried, which is every frame of a
## movie that never puppets a sprite.
static func with_puppets(sprites: Array, overrides: Dictionary) -> Array:
	var carried: Array[Dictionary] = []
	for channel_value in overrides:
		var over: Dictionary = overrides[channel_value]
		if not bool(over.get("_puppet", false)):
			continue
		var channel := int(channel_value)
		var here: Dictionary = {}
		for value in sprites:
			var sprite: Dictionary = value
			if int(sprite["channel"]) == channel:
				here = sprite
				break
		if not here.is_empty():
			over["_score"] = here
			continue
		if over.has("_score"):
			carried.append(over["_score"])
	if carried.is_empty():
		return sprites
	# Channel order is depth order, and every caller relies on it: the hit test
	# descends from the end of this array and the painter walks it forwards.
	var out: Array[Dictionary] = []
	out.assign(sprites)
	out.append_array(carried)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["channel"]) < int(b["channel"]))
	return out


## Notice a member change on a channel, so a film loop arriving there starts at
## its first frame rather than resuming wherever the previous one left off. The
## loop's frame counter is channel state, not member state: two sprites showing
## the same loop animate independently.
##
## This deliberately does *not* adjust the sprite's position. A previous version
## carried a running per-channel correction for the change in registration
## anchor across a swap, on the theory that Director shifts the start point so a
## new offset does not move the sprite. The score changes members on a channel
## constantly -- that is how a walk cycle is authored -- and it supplies its own
## `loc` for each of those members, so the correction was being added on top of a
## position that was already right, and accumulating. `tools/nudge_drift.gd`
## measures it: 451px of drift on one DAY1 channel, 9 of 17 channels displaced.
static func note_member(channel: int, cast_id: int, last_member: Dictionary,
		loop_start: Dictionary, ticks: int) -> void:
	if int(last_member.get(channel, -1)) == cast_id:
		return
	last_member[channel] = cast_id
	loop_start[channel] = ticks
## What a property reads as on a channel that holds no sprite this frame.
##
## Only the ones with a meaningful default are listed; everything else answers 0,
## which is what "nothing here" means for a member number or a position. `visible`
## is the one that matters and the one that was wrong -- see `read_prop`.
const EMPTY_CHANNEL := {
	"visible": 1,
	"ink": 0,
	"blend": 100,
}




## `the <prop> of sprite N`, read back.
##
## Known divergence, preserved by this move rather than introduced by it: this
## consults `overrides` and then the raw score record, where every other reader
## goes through `effective`. A script that reads a property back on a channel
## whose puppet the score has invalidated gets the stale answer here and the
## fresh one everywhere else.
static func read_prop(channel: int, prop: String, overrides: Dictionary,
		sprites: Array) -> Variant:
	var over: Dictionary = overrides.get(channel, {})
	if over.has(prop):
		return over[prop]
	for sprite in sprites:
		if int(sprite["channel"]) != channel:
			continue
		match prop:
			"membernum":
				return int(sprite["cast_id"])
			"castnum":
				# **Not the same answer as `membernum`, and that is the whole
				# point of the two spellings.** A member number is per library, so
				# a bare one is only an address if the library is already known.
				# `the memberNum of sprite` is that bare number and every site
				# that does arithmetic on it wants exactly that -- INVENTOR's
				# `set the memberNum of sprite 4 to the number of member
				# ("money" & y)` would break the moment it carried anything else.
				# `the castNum of sprite` is the reference, and it has to survive
				# being handed straight back to `member()`.
				#
				# These were one arm, and Piposh 1's ship map is what that cost.
				# Every deck movie opens with
				# `set nof to the name of member the castNum of sprite 1` -- the
				# backdrop on channel 1 is named for the deck position, and that
				# line is how the game learns where the player is standing.
				# Channel 1 is `2:1` in DAY1, so a bare `1` came back, resolved in
				# library 1, and `nof` became `"walkright1"` instead of `"dl1"`.
				# The map's `enterFrame` hides the walking Piposh for any `nof` of
				# four characters or more and every one of its `mouseUp` handlers
				# is gated on `the visible of sprite 20 = 1`, so one wrong library
				# removed the figure *and* every destination on the menu.
				return Members.pack_ref(
					int(sprite.get("cast_lib", 1)), int(sprite["cast_id"]))
			"loch":
				return int(sprite["loc_h"])
			"locv":
				return int(sprite["loc_v"])
			"width":
				return int(sprite["width"])
			"height":
				return int(sprite["height"])
			"visible":
				return 1
			"ink":
				return int(sprite["ink"])
			"flip_h":
				return 1 if bool(sprite.get("flip_h", false)) else 0
			"flip_v":
				return 1 if bool(sprite.get("flip_v", false)) else 0
			"castlibnum":
				return int(sprite.get("cast_lib", 0))
			"trails":
				# From the score's own ink byte when no script has written it, so
				# a movie that reads the property back before setting it gets what
				# the author put there rather than a default.
				return 1 if bool(sprite.get("trails", false)) else 0
	# The channel holds no sprite on this frame. **An empty channel is not a
	# zeroed sprite** -- in Director these are properties *of the channel*, and a
	# channel with nothing in it is a visible channel that happens to be empty.
	# Answering 0 for everything conflates "no sprite here" with "a script set
	# this to 0", and the two are different questions.
	#
	# `strtgame.dir`'s Load button is what this cost. Its whole body sits inside
	# `if sprite(30).visible = 1 then` -- a guard copied from the in-game menus,
	# where channel 30 is the walking player and the test means "not mid-cutscene".
	# On the main menu there is no player: channel 30 is occupied in 0 of 1,375
	# frames. The guard passed in 1997 and failed here, so clicking Load did
	# nothing at all and looked like "there is no save to load" (bugs.md 34).
	return EMPTY_CHANNEL.get(prop, 0)


## `puppetSprite N, FALSE` returns the channel to the score, which means
## discarding whatever the scripts wrote to it rather than merely stopping.
##
## `TRUE` records a **flag**, not merely an entry. An entry is what a property
## write makes too, so an entry alone cannot tell a whole-sprite puppet from the
## per-field auto-puppet a `set the memberNum of sprite` leaves behind — and the
## two obey opposite rules about the score (`effective` and `with_puppets`).
static func set_puppet(channel: int, on: bool, overrides: Dictionary) -> void:
	if on:
		if not overrides.has(channel):
			overrides[channel] = {}
		(overrides[channel] as Dictionary)["_puppet"] = true
	else:
		overrides.erase(channel)


## `set the <prop> of sprite N`.
##
## `the cursor of sprite` does not come here -- it is channel state rather than
## a puppeted score field, and the node routes it to the cursor path before
## calling this.
static func write_prop(channel: int, prop: String, value: Variant,
		overrides: Dictionary, sprites: Array) -> void:
	if not overrides.has(channel):
		overrides[channel] = {}
	var over: Dictionary = overrides[channel]
	over[prop] = value
	# Which member the override was taken against, so `effective` can tell a
	# still-valid puppet from one the score has moved out from under.
	for sprite in sprites:
		if int(sprite["channel"]) == channel:
			over["_member"] = int(sprite["cast_id"])
			break
