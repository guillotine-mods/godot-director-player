extends RefCounted
## The outside of the channel model: what the rest of the port asks a channel.
##
## The rules are in `preview/channel.gd` — one `Channel` per score channel,
## carrying its own visibility, its whole-sprite puppet flag and the sprite fields
## a script holds against the score, exactly as Director's `Channel`/`Sprite` pair
## does. This file is the six questions the player node asks of that model, and
## nothing else.
##
## It used to be the model as well as the questions, and the two are not the same
## thing: `effective`, `with_puppets`, `release_auto_puppets`, `read_prop`,
## `write_prop` and `set_puppet` were **five rules that had to agree with each
## other** about what a key in the override table meant. Every time they did not,
## a property arrived somewhere as half of itself — stored and never merged,
## merged and never released, released and never read — and the report came back
## as "a sprite did not move" from someone playing the game. Eight of those, and
## four more found while writing `channel.gd:FIELDS` because the table made them
## visible: `ink`, `blend`, `foreColor` and `backColor` were stored by `write_prop`
## and merged by nothing, three of them with a *release* rule already transcribed
## for a merge that did not exist.
##
## The state itself stays on the node, because `tools/` reads `_overrides` by name
## and a field that moved would make those reads return null rather than fail. So
## every function here takes the dictionary it works on. That is not a compromise:
## the dictionary is the channel table's storage and GDScript dictionaries are
## reference types, so passing it reads exactly as owning it and the node keeps the
## name the harnesses look for.
##
## **Director has two kinds of puppet and they obey opposite rules.** A property
## write auto-puppets that *one field* (§5.3); the score keeps writing everything
## else every frame, and the auto-puppet is released the moment the score writes
## that same property. `puppetSprite N, TRUE` claims the *whole sprite* (§5.2): the
## score is not applied to that channel at all, so nothing on it goes stale and
## nothing on it is released — including the channel's very existence. The two were
## one concept here until `bugs.md` 36, and one concept cannot be both: it is
## either sticky enough for the second rule or loose enough for the first. It was
## sticky, so a talking mouth never stopped; and it had no notion of a channel
## outliving the score, so the player disappeared.

const Channel := preload("res://scenes/preview/channel.gd")

## Kept as this module's own name for the pair of tables `channel.gd` owns, so a
## caller that wants "what does an empty channel answer" does not have to know
## which file the model lives in. Both are the model's, and both are read-only
## here.
const EMPTY_CHANNEL := Channel.EMPTY_CHANNEL
const FIELDS := Channel.FIELDS


## A sprite as it currently stands: the score's record with whatever a script has
## puppeted onto it. `{}` when a script has hidden it.
##
## Every path that asks about a sprite goes through this — drawing, hit-testing,
## `rollOver`. They diverged before: the screen showed the puppeted member while a
## click was tested against the score's, so a menu button was only clickable where
## its two states happened to overlap, and moving the mouse made it flicker in and
## out of reach.
##
## **A pure read.** Releasing an auto-puppet is `release_auto_puppets` below, on
## the one event that can cause it — the playhead moving to another frame — and not
## a side effect of somebody asking what a sprite looks like. It was the side
## effect, and a read that mutates cannot be asked speculatively: the preloader
## walks 24 frames ahead every step, so every look-ahead discarded a puppet the
## *current* frame was still using and a script's member swap survived exactly one
## tick. That needed a `peek` flag to suppress, which is a second code path through
## the same rule, which is the shape the model exists to avoid.
##
## **This is the one place the channel's visibility and its sprite are combined**,
## and that is why `ignore_visible` is a parameter here and nowhere in the model.
## Director asks two different rect questions and only one of them consults
## visibility — `channel.cpp:isMouseIn` reads `_visible` and is the only thing in
## that file that does; `c_within` and `c_intersects` read `getBbox()`. See
## `director_preview.lingo_sprite_rect`, which also records why that was briefly
## reverted and why the revert was wrong.
static func effective(
	sprite: Dictionary, overrides: Dictionary, table, ignore_visible: bool = false
) -> Dictionary:
	var channel: Channel = Channel.at(int(sprite["channel"]), overrides)
	if not ignore_visible and not channel.is_visible():
		return {}
	return channel.merged(sprite, table)


## The playhead has moved to another frame, and the score wrote `writes`
## (`{channel: {field: true}}`, from `director_score.writes_between`). Hand every
## auto-puppet the score wrote over back to it.
##
## `writes_between` answers the same question Director's copy-back mask does, out
## of the same delta byte ranges, for the walk between two frames — so this is the
## reference's `for each channel: releaseAutoPuppet(mask)` with the port's own
## source for the mask. `preview/frame_loop.gd:sync_frame_entry` calls it once per
## frame change, before the new frame's scripts run.
static func release_auto_puppets(writes: Dictionary, overrides: Dictionary) -> void:
	for number in writes:
		var channel: Channel = Channel.at(int(number), overrides)
		if channel.entry.is_empty():
			continue
		channel.release(writes[number])
		# An entry holding nothing but spent bookkeeping is not a puppet, and
		# leaving it behind would make `effective` duplicate the record for no
		# merge and `hilite.gd` believe a script is composing something here.
		if channel.is_spent():
			overrides.erase(number)


## The frame's sprites, plus the channels a whole-sprite puppet keeps alive that
## this frame's score does not carry.
##
## **A `puppetSprite N, TRUE` channel is not reconciled from the score at all.**
## Director's `Sprite::replaceFrom` copies the script id and returns when `_puppet`
## is set (§5.2), so the live channel keeps its member, position and size through
## frames whose score record for it is empty — and §5.5: nothing in the frame loop
## clears a whole-sprite puppet implicitly, so it survives frame jumps and `go to`
## and dies only with the movie. A port that draws the score's per-frame sprite
## list instead loses the sprite the moment the score stops carrying it.
##
## That is `bugs.md` 36's second symptom and all three of the reports filed against
## it. DAY1 puppets channel 30 — the player — in `init all`, and its `lilout1`,
## `lilclicktalk` and `dnzclicktalk` clips carry **no channel 30 at all**, so the
## player vanished for the length of somebody else's conversation and came back
## when the clip returned to the room. `tofclicktalk` does carry one, which is
## exactly why the same fault was reported as two different bugs.
##
## **The score record is dropped even when there is one.** That is the half this
## function used to be missing, and the half nothing caught: it took the score's
## record on any frame that carried one and only carried the channel forward
## across frames where the record was empty. A puppet was therefore frozen
## exactly on the frames the score was going to leave alone anyway, which is
## indistinguishable from working until a movie puppets a channel the score is
## still writing.
##
## CHESS's name wheel is that movie. It spins the same seven members on channel 8
## twice; the click puppets the channel to freeze whoever it landed on and plays
## that name's clip. The first spin's `go(marker(1))` lands on a frame with no
## channel 8 in the score, so the freeze held and all seven landings were right.
## The second lands on a frame where the score *does* carry channel 8 — always
## `jos` — so the stage snapped back to `jos` on 6 of 7 landings while the sound
## played the name the player actually stopped on. Reported as "the second spin
## plays the wrong sound"; the sound was right every time and the picture was
## wrong.
##
## Returns `sprites` itself when nothing is puppeted, which is every frame of a
## movie that never puppets a sprite.
static func with_puppets(sprites: Array, overrides: Dictionary) -> Array:
	var frozen: Dictionary = {}
	for number in overrides:
		var channel: Channel = Channel.at(int(number), overrides)
		if channel.is_puppet():
			# A whole-sprite puppet is carried even when its carry is empty --
			# see the paragraph above about a channel puppeted while the score
			# had nothing for it.
			frozen[channel.number] = channel.carried()
			continue
		# **And a channel a script has given a member is carried too**, which is
		# the auto-puppet half of the same rule. `channel.gd:carried` has the
		# reference for it and the cost of having only the explicit half: Itamar
		# Park's eighteen arcade object channels are moved by
		# `sprite(n).member = …` and never puppeted, so the whole level's food,
		# animals and enemies existed in `_overrides` and reached no frame.
		var auto: Dictionary = channel.carried()
		if not auto.is_empty():
			frozen[channel.number] = auto
	if frozen.is_empty():
		return sprites
	# Channel order is depth order, and every caller relies on it: the hit test
	# descends from the end of this array and the painter walks it forwards.
	var out: Array[Dictionary] = []
	for value in sprites:
		var sprite: Dictionary = value
		if not frozen.has(int(sprite["channel"])):
			out.append(sprite)
	# An empty carry is a channel puppeted while its score record was empty. It
	# stays empty for the puppet's life rather than being refilled by a later
	# frame, which is the same rule seen from the other side.
	for number in frozen:
		var kept: Dictionary = frozen[number]
		if not kept.is_empty():
			out.append(kept)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["channel"]) < int(b["channel"]))
	return out


## Notice a member change on a channel, so a film loop arriving there starts at
## its first frame rather than resuming wherever the previous one left off. The
## loop's frame counter is channel state, not member state: two sprites showing
## the same loop animate independently.
##
## This deliberately does *not* adjust the sprite's position. A previous version
## carried a running per-channel correction for the change in registration anchor
## across a swap, on the theory that Director shifts the start point so a new
## offset does not move the sprite. The score changes members on a channel
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


## `the <prop> of sprite N`, read back.
##
## The same two-layer lookup `effective` does, minus the merges that only the
## screen cares about — which is one lookup asked twice rather than two lookups
## that can disagree, and they did: a script could read back a puppet the score had
## invalidated and get the stale answer here and the fresh one everywhere else.
## That stopped being possible when the release became an event, because there is
## no invalidated entry left for either reader to find.
static func read_prop(channel: int, prop: String, overrides: Dictionary,
		sprites: Array) -> Variant:
	var here: Dictionary = {}
	for value in sprites:
		var sprite: Dictionary = value
		if int(sprite["channel"]) == channel:
			here = sprite
			break
	return Channel.at(channel, overrides).read(prop, here)


## `set the <prop> of sprite N`. The write *is* the auto-puppet (§5.3).
##
## `sprites` stays in the signature because `sprite_props.gd` passes it through one
## seam for both directions and a read genuinely needs it.
##
## `the cursor of sprite` does not come here -- it is channel state rather than a
## puppeted score field, and the node routes it to the cursor path before calling
## this.
static func write_prop(channel: int, prop: String, value: Variant,
		overrides: Dictionary, _sprites: Array) -> void:
	Channel.claim(channel, overrides).write(prop, value)


## `puppetSprite N, FALSE` returns the *sprite* to the score and leaves the
## *channel* alone; `TRUE` claims the whole sprite. Both are `channel.gd:set_puppet`
## — the difference between the two objects is the model's, and stating it here as
## well is how it stopped being stated the same way twice.
static func set_puppet(channel: int, on: bool, overrides: Dictionary) -> void:
	if not on and not overrides.has(channel):
		return
	var live: Channel = Channel.claim(channel, overrides)
	live.set_puppet(on)
	if live.is_spent():
		overrides.erase(channel)
