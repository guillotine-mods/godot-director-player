extends RefCounted
## What the mouse can reach: the hit test, eligibility, drag, and dispatch.
##
## The rule that took the longest to get right, and the one this module exists to
## keep in one piece, is that **eligibility is tested inside the descent, not
## applied to its answer.** A sprite the point is over but which cannot respond
## does not absorb the click -- the search carries on to what is beneath it.
## Filtering afterwards instead is what let a room backdrop swallow every click
## on the stage.
##
## `channel_at` and `draw_hotspots` used to disagree on one detail: the descent
## asked `hits_per_pixel(ink, member_type)` and the overlay asked
## `hits_per_pixel(ink)`, so the overlay painted a matte-inked *shape* as
## artwork-only where the hit test correctly treated it as a whole rect. Both now
## pass the member type. They are the same question and answering it twice is how
## a debugging tool comes to lie about the thing it exists to show.
##
## Everything takes the preview node as `host`: the hit test needs puppet state,
## the artwork cache and the script table, all of which are the node's.

const Ink := preload("res://director/director_ink.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")
## §6.3's queue. Reached from here for two things the click model owns: the
## member latched for the mouse-up's cast element (§15), and tier 1's
## `*Script` runner, which the mouse and the keyboard share.
const EventChain := preload("res://scenes/preview/event_chain.gd")
const Paint := preload("res://director/director_paint.gd")

## How close two presses have to be to make `the doubleClick` true.
##
## Director asks the OS for the system double-click time; there is no such
## setting to ask for here, so this is the Mac default the game was authored
## against. It is a threshold rather than a decoded value, which is why it is
## named once instead of written into the comparison.
const DOUBLE_CLICK_MS := 500

## The file-version word at which the behaviour clause of §4.3 turns on.
##
## `kFileVer600` in the reference's own version table, which is the threshold
## `humanVersion()` maps to 600. Every movie either corpus plays is well past it
## -- Piposh 2's state `0x57E` (D7) and Piposh 1's and Rating's `0x73A` (D8.5),
## measured on all 241 containers by `tools/container_versions.gd` -- so the
## clause is live on everything this port has ever run. The test is here anyway,
## because a D4 title is a title this engine is meant to run and on one the
## clause must be off: the whole point of §4.3's ordering is that the D6+ arm is
## much wider than the handler search below it.
##
## A movie with no config chunk reads 0 and takes the narrower arm. That is the
## conservative direction and it costs nothing measurable: the 87 containers in
## the three corpora without a config chunk are casts, and a cast has no score to
## put a sprite on.
const FILE_VERSION_D6 := 0x4C2


## The topmost sprite whose rect contains a point, or 0. Highest channel first,
## which is Director's stacking order and therefore its hit order.
static func channel_at(host, at: Vector2, sprites: Array, hit_pixels: bool,
		table) -> int:
	# Highest channel first, since channel number is depth -- but a sprite drawn
	# with a keying ink is only hit where it has pixels, and where it does not
	# the search CONTINUES to the sprite behind.
	#
	# Both simpler rules fail on this game's own menu. A pure bounding-box test
	# hands every click to channel 21, a large keyed sprite covering the stage,
	# so the buttons on channels 4-7 are never reached. Treating a transparent
	# pixel as a hole that ends the search is worse still: nothing is ever hit
	# at all. Transparency means "not this sprite", not "stop looking".
	#
	# The paragraph that stood here said `score.cpp` describes a bounding-box
	# test and no per-pixel matte test, and that the pixel test was standing in
	# for an eligibility filter this preview had no notion of. **It has one now**
	# (§4.3, all six clauses), and on the case that motivated the stand-in the
	# filter is enough on its own: measured on `strtgame.dir` frame 850, channel
	# 21 is `1:312`, 640x485 of BackgndTrans over the whole stage, and it carries
	# no behaviour, no member script and no moveable bit -- so it is ineligible
	# and the descent walks past it to the four buttons on channels 4-7 whichever
	# geometry test is on. The pixel test is no longer load-bearing *there*.
	#
	# It is still the honest answer for a Matte sprite, which Director does
	# hit-test per pixel (§2.5), so both remain available and `M` switches
	# between them.
	for i in range(sprites.size() - 1, -1, -1):
		# Puppet state, not the raw score record. The descent used to read the
		# score directly, which meant a sprite a script had hidden still absorbed
		# every click inside its rect, and a sprite a script had moved absorbed
		# them at the position the score last gave it rather than where it is.
		#
		# Both are invisible from the player's chair and read as "something I
		# cannot see is covering what I am trying to click". DAY1's beach frame
		# script alone hides sprites 15, 17 and 33, all of them on channels above
		# the backdrop and two of them above the character.
		#
		# `visible` is the case the reference is most explicit about: false means
		# not drawn *and* not hit-tested, and it is the first thing `isMouseIn`
		# checks. `effective` answers `{}` for it.
		var sprite: Dictionary = host._effective(sprites[i])
		if sprite.is_empty():
			continue
		if not host._sprite_rect(sprite).has_point(at):
			continue
		# Only Matte samples the artwork, and only on a bitmap. Every other ink is
		# a plain rectangle for hit-testing even when it renders per-pixel -- the
		# asymmetry is deliberate in Director and easy to get wrong in both
		# directions. The cast type is the other half of the same rule: a matte is
		# flooded in from the border of the *member's image*, and a shape has no
		# image, so a matte-inked shape hit-tests as its box. Without that, this
		# game's invisible shape hotspots that happen to carry Matte answered no
		# click at all (`director/director_ink.gd:hits_per_pixel`).
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		if hit_pixels \
				and Ink.hits_per_pixel(int(sprite["ink"]), int(member.get("type", 0))) \
				and not host._opaque_at(sprite, at):
			continue
		# Eligibility is tested HERE, inside the descent, not applied to the
		# answer afterwards. A sprite the point is over but which cannot respond
		# does not absorb the click: the search carries on to what is beneath.
		# That is the whole reason a backdrop was taking every click.
		if responds_to_mouse(host, sprite, table):
			return int(sprite["channel"])
	return 0


## Can this sprite answer a mouse message at all?
##
## True when `eligibility_reason` names a clause. The two are one function on
## purpose: this is the predicate the click descent filters on and the reason is
## what `tools/hotspots.gd` and the debug overlay print, and a port where the
## verdict and the explanation are computed separately is a port where the
## debugging tool eventually lies about the thing it exists to show. The overlay
## and the hit test already diverged once over `hits_per_pixel`'s arguments (see
## this module's own header); once was enough.
static func responds_to_mouse(host, sprite: Dictionary, table) -> bool:
	return eligibility_reason(host, sprite, table) != ""


## *Why* this sprite answers a mouse message, or "" for "it does not".
##
## §4.3, clause for clause and **in the reference's order**, which is the whole
## substance of this function. `respondsToMouse` is a chain of early returns, so
## the order is not presentation: an earlier clause that passes means the ones
## below it are never asked, and one of them -- the D6+ behaviour clause -- is so
## much wider than what follows that everything after it is dead code on a D6+
## movie. That is not a detail of this corpus. It is the rule, and this port had
## the rule inverted: it implemented only the clauses that D6 makes unreachable.
##
## The measured cost of the omission was Rating's dialogue. The three options at
## `Egoz1` carry behaviours that declare `exitFrame` and nothing else, so the
## handler search answered "no" for all three and the player's click reached them
## only because `script_for_click` falls back to the frame script. Three sprites
## the movie exists to have you click, and none of them was a click target.
##
## **Widening this widens what absorbs clicks, not just what answers them**
## (§4.2), which is why `tools/click_eligibility.gd` exists and why the change
## that introduced this function shipped with a before/after sweep of all three
## corpora rather than with a screenshot of the dialogue working.
static func eligibility_reason(host, sprite: Dictionary, table) -> String:
	# Clause 1. A moveable sprite is click-eligible on its own, with no script at
	# all -- it has to be, or nothing could start a drag. The sprite handed in
	# here has already been through `effective`, so this is the score's own bit
	# and any `the moveableSprite` write merged, not just the latter.
	if bool(sprite.get("moveable", false)):
		return "moveable"
	var member: Dictionary = table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var type_name := str(member.get("type_name", ""))
	# Clause 2. A button is a click target because it is a button.
	if type_name == "button":
		return "button member"
	# Clause 3. A **movie** member answers the mouse only when its scripts are
	# enabled -- it is an embedded movie, and the clicks are being routed into
	# it. Note the shape: the reference *returns* the flag here rather than
	# falling through on false, so a movie member with scripts off is not a click
	# target however many behaviours the sprite carries. Reproduced as written.
	#
	# **Unverified, and unverifiable on this data.** `director/director_cast.gd`
	# does not decode the flag, and there is no member to decode it from: 0 of
	# the 11,520 + 26,552 + 13,278 members across the three corpora is of type
	# `movie` (or of type `button`, which is why clause 2 has never fired
	# either). Absent decode, the clause reads enabled, which is the answer that
	# leaves the sprite reachable; a wrong guess here can affect no title this
	# engine has been pointed at.
	if type_name == "movie":
		return "movie member with scripts enabled" \
			if bool(member.get("enable_scripts", true)) else ""
	var channel := int(sprite["channel"])
	var behaviours := behaviour_scripts(host, channel, int(host._index))
	# Clause 4, **D6 and later**: a sprite with any behaviour attached is a click
	# target whatever that behaviour declares. An `exitFrame`-only behaviour
	# absorbs clicks, and that is not a bug in the reference -- from D6 the
	# behaviour is an instantiated object with a full event surface, and the
	# engine stops trying to guess from the source which events it wants. This is
	# the clause the port was missing, and on a D6+ movie it is the one that
	# fires: everything below it is the D4/D5 rule and unreachable.
	if not behaviours.is_empty() and is_d6_plus(host):
		return "D6+ behaviour attached"
	# Clause 5, the D4/D5 arm, dead on every movie in either corpus and kept
	# because a D4 title is a title this engine is meant to run. Two traps in it:
	# a non-zero script id is **not** enough -- the handler has to exist, so a
	# behaviour declaring only `mouseEnter` is not a click target -- and a
	# **generic** script counts. The generic one is the D3-style scopeless sprite
	# script: bare statements rather than an `on <event>` block, which the parser
	# keeps in `body` (§8.2 says when it runs -- mouse-down if the sprite is
	# immediate, mouse-up otherwise).
	for script in behaviours:
		if declares_mouse_handler(script, host._interpreter):
			return "behaviour declares mouseDown/mouseUp"
		if not ((script as Dictionary).get("body", []) as Array).is_empty():
			return "generic behaviour, no handler scope"
	# Clause 6, the cast script, resolved in the library the sprite names and not
	# by number alone. Member numbers are per cast, so a number-only search
	# answers with a stranger -- and here that is not silence but a false
	# positive: it makes a sprite clickable because some *other* cast happens to
	# have a script at that number, and the click then runs that stranger.
	#
	# DAY1's beach is the case that found it. Channel 1 is `3:10`, the room
	# backdrop `shore2`, a plain bitmap with no script of its own. A number-only
	# search found a mouse handler anyway, so the backdrop answered clicks across
	# its whole 640x400 rect -- and since the walkable ground is a separate Matte
	# sprite on channel 2 covering only the bottom 154 pixels, clicking the *sea*
	# fell through to the backdrop and walked the character up into it.
	if declares_mouse_handler(host._script_in_lib(
			int(sprite["cast_lib"]), int(sprite["cast_id"])), host._interpreter):
		return "member script declares mouseDown/mouseUp"
	return ""


## Is the movie now playing D6 or later?
##
## Asked of the **movie's own config chunk**, which is the only version this port
## holds. The reference asks a global -- the engine is told once which Director
## it is emulating and every movie is read as that one -- and a per-movie answer
## is the closer of the two available here: a title that mixes formats (Piposh 1
## ships `STRTGAME.dir` with 48-byte sprite records and 94 room movies with
## 24-byte ones) gets each movie read as what it says it is rather than as what
## its neighbour says.
static func is_d6_plus(host) -> bool:
	var config = host._config
	return config != null and int(config.version) >= FILE_VERSION_D6


## Every behaviour attached to a channel on a frame, as the score's own interval
## entries -- **a list, because from D6 a sprite carries a list** (§8.2).
##
## The plural of `preview/scripts.gd:for_sprite`, which answers the first one and
## is the right answer for "which script does this click run" while this port
## still queues a single element per sprite. It lives here rather than there
## because the question it is asked is the eligibility one, and eligibility is
## a test on the list rather than on any script in it.
##
## **The list can be longer than one, and now is.** `director_score.gd` reads a
## span's behaviour entry as a stream in 8-byte strides, as the reference does,
## where it used to take the entry only when it held exactly one element and drop
## a longer one whole. The corpus barely exercises it -- 2 spans of 158,001 in
## Piposh 2 and 5 of 271,872 in Piposh 1 carry two, and Rating carries none --
## and both of Piposh 2's name the same script twice, so what changed there is a
## handler running twice. This function was written against the list before the
## decode could produce one, which is why the fix was a decode change and not a
## second rewrite of the hit test.
static func behaviour_intervals(host, channel: int, frame_index: int) -> Array:
	var out: Array = []
	if host._score == null:
		return out
	for interval in host._score.intervals():
		if str(interval["kind"]) != "sprite" or int(interval["channel"]) != channel:
			continue
		if frame_index < int(interval["start"]) or frame_index > int(interval["end"]):
			continue
		out.append(interval)
	return out


## The same list, resolved, and **the ones that resolve to nothing dropped**.
##
## The reference's clause 4 tests `_behaviors.size()` -- the attachment, not the
## lookup -- and taking it literally here is a false positive of exactly the kind
## §4.2 warns about, because this port's attachment list is not clean.
## `tools/click_eligibility.gd` counts it per corpus: of the sprite intervals
## `director_score.gd` decodes, **279 of 2,680 in Piposh 2, 654 of 6,202 in
## Piposh 1 and 500 of 5,365 in Rating do not resolve**, and by the member type
## the score names, all but 41 of those are a bitmap, a film loop or a shape --
## none of which can be a behaviour.
##
## **They are the record's own attachments, and the decode is not what is wrong
## with them.** This said the opposite for as long as nobody measured it: that
## `_read_interval` paired a span with somebody else's behaviour entry because it
## searched past an empty one. Three measurements say it does not. The search
## took a later entry 0 times in 528,168 spans across the three corpora, because
## the entry after an empty behaviour list is an empty name string and then the
## next span's info record, which is too wide to match. Every interval it
## produced was claimed by the sprite record occupying that channel over those
## frames -- 14,247 spans, 0 orphans -- so matching by channel and frame range is
## exactly the reference's `sprite_list_idx` lookup on this data. And the
## unresolved ones are not a library that failed to map: no consistent offset
## relates the library they name to one holding a script at that number, and for
## 206, 585 and 393 of them respectively **no library in the movie has a script
## there at all**.
##
## So what a bitmap-naming attachment is remains open, and it is a question about
## Director's authored data or about the member-type decode rather than about
## this pairing. Until it is answered the clause below stays narrow, for the
## reason underneath rather than the one that used to be written here.
##
## The cost of taking them was immediate and was exactly the shape the whole
## measurement exists to catch: `AIR1.dir` channel 1 is `2:5`, a 640x400 Copy-ink
## backdrop over the whole stage, and it became a click target on 144 frames on
## the strength of an attachment naming `2:18` -- a bitmap. Across the three
## corpora requiring the lookup drops 118 of the 188 (movie, channel) pairs the
## literal reading made eligible, including four of the five over 640x400.
##
## It is narrower than the reference in one honest place: the 41 intervals that
## name a real **script** member this port fails to resolve or compile -- 29 in
## Rating, 12 in Piposh 1, 0 in Piposh 2 -- lose an eligibility Director would
## give them. That half is in the compiler, not here, and until then this errs
## toward letting the click fall through -- §4.2's own default, and the
## reversible direction.
static func behaviour_scripts(host, channel: int, frame_index: int) -> Array:
	var out: Array = []
	for value in behaviour_intervals(host, channel, frame_index):
		var interval: Dictionary = value
		var script: Dictionary = host._script_in_lib(
			int(interval["script_cast_lib"]), int(interval["script_member"]))
		if not script.is_empty():
			out.append(script)
	return out


static func declares_mouse_handler(script: Dictionary, interpreter) -> bool:
	if script.is_empty() or interpreter == null:
		return false
	for name in ["mousedown", "mouseup"]:
		if interpreter.call("_script_has_handler", script, name):
			return true
	return false


## The channel `the rollOver` is over, or 0. A **pure rect test**, and that is the
## whole difference between this and `channel_at`.
##
## §4.5: `checkSpriteRollOver` applies no matte and no eligibility filter, so a
## backdrop with no handler rolls over and a Matte sprite rolls over its whole
## box. `channel_at` is the opposite on both counts because a *click* has to
## reach the button behind the backdrop. Answering the mouse and being under the
## mouse are two questions, and one function answering both is how the menu
## highlight and the menu click end up disagreeing about which button is live.
##
## Measured against the **score's** geometry, for the reason `lingo_rollover`
## states at length: a menu script swaps a button's art *because* the rollover is
## true, so asking about the swapped member feeds the answer back into the
## question and the highlight oscillates instead of settling. The two functions
## have to read the same rect or `rollOver()` and `rollOver(n)` disagree, which
## is worse than either being wrong.
static func rollover_channel(host, at: Vector2, sprites: Array) -> int:
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = sprites[i]
		if host._sprite_rect(sprite).has_point(at):
			return int(sprite["channel"])
	return 0


## Send a message that exists only on a sprite behaviour, and nowhere else.
##
## §6.5: `mouseEnter`, `mouseLeave`, `mouseWithin` and `mouseUpOutSide` go to
## **sprite behaviours only** -- not to the cast member's script, not to the
## frame, and above all not to a movie script. `preview/scripts.gd:dispatch` is
## the wrong tool for them precisely because it is right for everything else: it
## falls through to `call_handler`'s movie-script search, so one `on mouseWithin`
## in a movie script would receive the message for every sprite on the stage,
## every tick, for the whole title.
##
## Declared-or-nothing for the same reason. `mouseWithin` fires on every tick the
## cursor is inside the sprite, so a dispatch that ran unconditionally would
## tally tens of thousands of sends per room into `_sent` and drown the counters
## the harnesses read. Returns whether a handler actually ran.
static func dispatch_sprite_only(host, handler: String, channel: int) -> bool:
	if channel <= 0 or not host._lingo_on or host._interpreter == null:
		return false
	var script: Dictionary = host._sprite_script(channel, host._index)
	if script.is_empty():
		return false
	if not host._interpreter.call("_script_has_handler", script, handler.to_lower()):
		return false
	host._tally(host._sent, handler)
	host._tally(host._ran, handler)
	host._interpreter.call_handler(handler, [], script, channel)
	return true


## The cursor crossed a sprite boundary: `mouseLeave` to what it left,
## `mouseEnter` to what it entered (§8.1, D5/D6).
##
## Leave before enter, which is the order the two names imply and the only order
## that lets a pair of handlers hand a highlight between them without both
## thinking they own it for an instant.
static func hover_changed(host, was: int, now: int) -> void:
	if was == now:
		return
	dispatch_sprite_only(host, "mouseLeave", was)
	dispatch_sprite_only(host, "mouseEnter", now)


## `mouseWithin`, once per tick while the cursor is inside a sprite (§6.5).
##
## Driven from the frame loop rather than from pointer motion, because "every
## tick the cursor is over the sprite" is true of a *stationary* cursor too --
## firing it on movement would make a script that animates a hover run only
## while the player keeps wiggling the mouse.
static func within(host) -> void:
	dispatch_sprite_only(host, "mouseWithin", int(host._rollover_channel))


## The channel and grab offset for a drag starting at `at`, or `[]`.
##
## Director records the offset from the click to the sprite's position and
## follows the cursor until mouse-up. The offset matters, or the sprite snaps its
## registration point onto the pointer.
static func begin_drag(host, at: Vector2, channel: int, sprites: Array) -> Array:
	for sprite in sprites:
		if int(sprite["channel"]) != channel:
			continue
		# Asked of the effective sprite, which is where the score's own moveable
		# bit and any `the moveableSprite of sprite` write have already been
		# merged into one answer. Reading `_overrides` directly, as this used to,
		# saw only the Lingo half.
		var live: Dictionary = host._effective(sprite)
		if live.is_empty() or not bool(live.get("moveable", false)):
			return []
		return [channel, Vector2(
			float(live.get("loc_h", 0)), float(live.get("loc_v", 0))
		) - at]
	return []


## Is a drag in progress still entitled to move `channel`?
##
## §7.6 gives the drag **two** ends -- "on mouse-up **or when the sprite stops
## being moveable**" -- and the port had only the first, so a script clearing
## `the moveableSprite` mid-gesture left the sprite glued to the cursor until the
## button came up. The reference's motion arm does not merely skip that frame's
## position write: it drops the dragged channel outright the first time the flag
## reads false, so the sprite is handed back to the score there and then and does
## not resume following the pointer if the flag is set again before the release.
##
## A channel that has left the frame ends the drag too. The reference keeps one
## `Channel` per score channel for the life of the movie and an emptied one is
## not moveable, so "the score moved on" and "the script cleared the flag" are
## the same answer; here they are the same answer for the extra reason that there
## is nothing left to write a position onto.
##
## Asked of the *effective* sprite for the reason `begin_drag` gives: the score's
## own moveable bit and any `the moveableSprite of sprite` write are one property
## from two sources, and reading either alone answers half of it.
##
## **Unverified against Director running.** No script in the corpus clears the
## flag -- all 15 `moveableSprite` writes across 7 titles set it to 1, ten of them
## as `set the moveableSprite of sprite i to 1` inside an inventory `init all`
## loop -- so this is built from the reference and this game cannot exercise it.
static func still_moveable(host, channel: int, sprites: Array) -> bool:
	if channel <= 0:
		return false
	for sprite in sprites:
		if int(sprite["channel"]) != channel:
			continue
		var live: Dictionary = host._effective(sprite)
		return not live.is_empty() and bool(live.get("moveable", false))
	return false


## Where a position write on `channel` is allowed to land: `the constraint of
## sprite` (§7.6).
##
## **It clamps the position POINT, not the rect**, and that is the whole of what
## is easy to get wrong here. A sprite is placed from its registration point, so
## a sprite pinned to the right edge of its constraint hangs outside it by
## whatever the registration offset is -- half the artwork's width for a centred
## member. Clamping the rect instead looks more correct on screen and is a
## different behaviour: it stops the registration point short of the edge, so a
## slider knob can never reach the end of its own track and a dragged item can
## never touch the side of the tray it is being dropped into. §7.6 states the
## point rule explicitly and the reference does the same thing --
## `Channel::setPosition` clamps `newPos.x` and `newPos.y` between the constraint
## channel's bbox edges and never looks at the dragged sprite's size at all.
##
## Per axis, and independently, which is what makes it a clamp rather than a
## containment test: a point above and to the left of the box arrives at the
## box's top-left corner rather than being refused.
static func constrain(host, channel: int, to: Vector2) -> Vector2:
	var box: Rect2 = constraint_box(host, channel)
	if box == Rect2():
		return to
	return Vector2(
		clampf(to.x, box.position.x, box.end.x),
		clampf(to.y, box.position.y, box.end.y))


## The box `the constraint of sprite <channel>` names, or an empty rect for "not
## constrained".
##
## **0 means unconstrained** -- Director numbers channels from 1, the property
## defaults to 0, and `Channel::setPosition` tests `_constraint > 0` before it
## reads any bbox. So the overwhelmingly common case costs one dictionary lookup
## and the position write that follows is byte-for-byte what it was before this
## existed.
##
## **A constraint naming a channel with no sprite on it is also unconstrained,
## and that is a deliberate divergence.** Read literally the reference would ask
## an empty channel for its bbox, get an empty rect at the origin, and clamp the
## dragged sprite onto (0, 0) -- a sprite that teleports into the top-left corner
## the instant the player touches it. No author can have meant that, nothing in
## the corpus would exercise it, and the failure it produces looks like a
## rendering fault rather than a constraint.
##
## **A *hidden* constraint channel still constrains**, because `lingo_sprite_rect`
## measures one: `channel.cpp:698` reaches the constraint through
## `getRollOverBbox()`, which is `getBbox()`, and `_visible` is read at exactly
## one site in that file -- `isMouseIn`. An empty channel and a hidden one are
## different things. Only the first has no box.
##
## Measured through `lingo_sprite_rect`, so the constraint follows a constraint
## channel a script has moved or swapped. Deliberately *not* `rollover_channel`'s
## rect, which is the score's: §4.5 reads the score there to stop a menu
## highlight feeding back into its own rollover test, and nothing feeds back
## here. In the reference both are the live channel's box; the rollover path's
## use of the score record is a documented divergence and not a rule to copy.
static func constraint_box(host, channel: int) -> Rect2:
	var onto: int = int(host.lingo_sprite_constraint(channel))
	if onto <= 0:
		return Rect2()
	return host.lingo_sprite_rect(onto)


## The mouse-DOWN half of a click: what was hit, which script answers for it,
## and the `mouseDown` message.
##
## **A click is two messages at two moments, and this port used to send both on
## the press.** `mouseDown` and `mouseUp` went out back to back from the same
## call, and the release then cleared the drag and returned without dispatching
## anything at all. For a plain click that is invisible -- the two handlers run
## in the right order either way, a few milliseconds early. For a *drag* it is
## the whole mechanism, because the only thing that distinguishes a drop from a
## pick-up is **where the sprite is when `mouseUp` arrives**, and on the press it
## is still exactly where it started.
##
## Director's own inventory idiom (`MASTER/External/BehaviorScript 52`, attached
## to the eight slot channels, and eleven near-copies of it across the corpus)
## is written entirely around that gap:
##
##     on mouseDown            -- remember where the item lives
##       objectxx = the locH of sprite the clickOn
##     on mouseUp              -- decide what it was dropped on, then send it home
##       if sprite the clickOn intersects 100 then ...
##       set the locH of sprite the clickOn to objectxx
##
## Sent together on the press, `intersects` is asked while the item is still in
## its slot, so no drop target ever matches; and the snap-back writes the home
## position over the home position, so it does nothing either. Then the drag runs
## and the release throws its message away, and the item is simply abandoned
## wherever the button came up. That is the reported bug -- "I cannot drop the
## item I started dragging" -- and it is a general fault in the click model, not
## an inventory one: every `mouseUp` handler in every title was running before
## the mouse came up.
##
## §7.6: the drag ends on mouse-up, and Director does not suppress the message
## because a drag was in progress.
##
## Director does have a rule shaped like the old behaviour, which is probably how
## it got written: §15's **immediate sprites** run their script on the mouse-down
## and have a mouse-up synthesised straight after. That is one authored sprite
## flag, though, not the click model -- applied to every sprite it makes the
## whole engine immediate, and nothing can be dragged anywhere.
## `right` selects the pair of messages, and **nothing else about the press**
## (§8.1, D5; §15). A right click latches everything a left click latches and
## raises only `rightMouseDown`/`rightMouseUp` -- not the left pair as well.
static func press(host, at: Vector2, right := false) -> void:
	# A window movie has its input processing switched off (`preview/boot.gd`), so
	# the only way it ever learns where the pointer is, is from whoever routed an
	# event into it. Without this, `the mouseH` inside a Movie-In-A-Window answers
	# the stage's coordinates on a touchscreen and nothing at all before the first
	# real mouse move. Harmless and correct on the stage, which has already set
	# the same value from `_input`.
	host.note_pointer(at)
	# Cleared first, so a press the interpreter is not up for cannot leave the
	# *previous* click's script latched for the release to send a message to.
	host._click_script = {}
	# §9.2's other half: the press that ended a wait-for-click dispatches no
	# `mouseDown` and does not move `the clickLoc`, `the lastClick` or `the
	# doubleClick` -- all four are inside the else-arm of `events.cpp:249-297`. See
	# `latch_press`, which carries the argument and the reference lines.
	#
	# After `note_pointer` and the `_click_script` clear, because those two are the
	# port's own bookkeeping rather than Director state: the window still has to
	# learn where the pointer is, and a stale script left latched would answer the
	# release for a click that never resolved one.
	if host._clock != null and host._clock.press_consumed():
		return
	if not host._lingo_on or host._interpreter == null:
		return
	# `the clickLoc`, `the lastClick` and `the doubleClick`, which are three views
	# of the same two facts: where the last press was and when. Recorded before
	# anything is dispatched, so a `mouseDown` handler asking any of them gets
	# *this* click and not the one before it.
	#
	# The interval is measured here rather than taken from Godot's own
	# `InputEventMouseButton.double_click`, because a press can reach this
	# function without an OS event behind it -- `route_click`, every harness, and
	# the container picker all synthesise one -- and a property that answers
	# correctly only when a human is holding the mouse is a property no test can
	# assert.
	var now := Time.get_ticks_msec()
	var since := now - int(host._host.last_click_ms)
	host._host.double_click = int(host._host.last_click_ms) >= 0 and since < DOUBLE_CLICK_MS
	host._host.last_click_ms = now
	host._host.click_loc = at
	# A click always produces a message. What is under the cursor decides which
	# script sees it first; it does not decide whether one is sent.
	#
	# Bailing out on a miss or a hole is why the menu went from unreliable to
	# dead: its backdrop covers the stage, so the hit test answered "hole" and
	# nothing was ever dispatched -- while the handler the menu actually uses
	# lives in the frame script and reads `the clickOn`.
	# Annotated rather than inferred: a call through `host` is untyped, so `:=`
	# has nothing to infer from and the whole module fails to compile.
	#
	# **The channel is the one `latch_press` already answered**, not a fresh
	# descent. `_press_click` runs the latch block before it builds the chain,
	# because §15's block runs "at the very beginning, before the first source
	# type" and because the chain has to be settled before a `mouseDown` handler
	# can move what it would have resolved against.
	var channel := int(host._press_channel)
	var events: Array = click_events(right)
	var chosen: Array = script_for_click(host, channel, host.frame_sprites(), events)
	var script: Dictionary = chosen[0]
	# Says what was clicked, which script is about to answer for it, and whether
	# a handler actually exists. "clicked nothing" and "clicked something with no
	# mouseUp" look identical on screen and are entirely different faults.
	var has_up: bool = host._interpreter.call("_script_has_handler", script, str(events[1])) \
		or host._interpreter.has_handler(str(events[1]))
	# Kept, not just printed: the snapshot key reports the click that went wrong,
	# and by the time anyone presses it the score has moved on several frames.
	#
	# **The message the flag was tested against travels with it.** It is
	# `rightMouseUp` for a right click, and a record that says `mouseUp` about it
	# describes a failure that never happened -- see `snapshot.gd:note_click`.
	host._last_click = Snapshot.note_click(
		at, host._index, channel, str(chosen[1]), script, has_up,
		"rightMouseUp" if right else "mouseUp")
	print(Snapshot.click_line(host._last_click))
	# Held for the release, which uses it only for the *log* and the snapshot now
	# that the chain is queued: `_dispatch` runs the queue and ignores this
	# argument. It is still the press's resolution rather than the release's,
	# because it is the record of what the press decided.
	host._click_script = script
	var event := "rightMouseDown" if right else "mouseDown"
	# §6.3 tier 1. A primary handler runs ahead of every other tier and, unlike
	# every other tier, **passes by default** -- so the sprite/frame/movie
	# dispatch below happens anyway unless the handler called `dontPassEvent`.
	# Inverting that default is the classic Director bug, so the ordering here is
	# "run it, then carry on" rather than "run it and stop if it claimed".
	var pass_on := true
	if host._interpreter.run_primary(event.to_lower()):
		host._tally(host._ran, "when %s" % event)
		pass_on = bool(host._host.pass_event)
	# The flag again, per element (§8.2): two primary elements both default to
	# passing and the second must not inherit the first's `dontPassEvent`. The
	# verdict is carried in `pass_on` and put back below, so resetting here cannot
	# erase what the `when` handler decided -- which is what an unconditional
	# reset does, and it is the shape ENGINE_TODO's second event-chain residue was
	# about.
	#
	# **The left button only.** Director files a primary handler under the event
	# it was installed for, and the language spells only five of them --
	# `the mouseDownScript`, `mouseUpScript`, `keyDownScript`, `keyUpScript` and
	# `timeoutScript`. There is no `rightMouseDownScript`, so the right button's
	# primary slot is one nothing can fill and a right click runs no `*Script`.
	# The `when rightMouseDown then` form above is a different mechanism and does
	# run, which is why the two lines are not one.
	if not right:
		host._host.pass_event = true
		if EventChain.run_primary_script(host, host._interpreter,
				host._host.mouse_down_compiled, "mouseDownScript"):
			pass_on = bool(host._host.pass_event)
	# What the primary tier left, for `EventChain.run` inside `_dispatch` to read.
	host._host.pass_event = pass_on
	host._dispatch(event, script)
	host.queue_redraw()


## §15's mouse-down block: **five things latched together, for either button.**
##
## The reference runs it once per click, at the primary tier, before the first
## script element of the chain resolves -- and it runs it for `rightMouseDown`
## exactly as for `mouseDown` (`lingo-events.cpp:158-190`). This port used to run
## none of it for the right button, which the ENGINE_TODO entry it closes calls
## an all-or-nothing block for a reason worth restating: taking `the clickOn`
## alone would let a right click rename the sprite a left drag is in the middle
## of, with no drag of its own to justify the rename.
##
## The five, in the reference's order:
##
## 1. **The beep**, when the press landed on nothing at all and `the beepOn` is
##    set. The one thing here that happens *because* the click reached no sprite.
## 2. **The hilite channel** -- `_press_channel`, which this port also uses as
##    "the sprite that took the press". The reference splits the two
##    (`_currentHiliteChannelId` is gated on `shouldHilite`), and one field is
##    enough here because `preview/hilite.gd:artwork` asks `should_hilite` again
##    at paint time; a channel latched here that cannot hilite simply does not.
## 3. **"The press was in *a* button"**, which is not about *this* sprite: §15's
##    strange rule is that the mouse-up flips the hilite of whatever button is
##    under it if the press was in any button at all.
## 4. **The drag**, channel and grab offset, for a moveable sprite (§7.6). This
##    was in `route_press` and is here now, which is the whole of the right
##    button's share of it -- the reference sets `_currentDraggedChannel` in this
##    block and clears it in the release block, both for either button, so a
##    right-drag drags. Unexercised: 0 sites.
## 5. **The member the mouse-up will resolve its cast element against**, latched
##    here so that a `mouseDown` handler swapping the member leaves the *old*
##    member answering the release (§15, `_currentMouseDownCastID`).
##
## `the clickOn` is written first and by both buttons, which is the sixth thing
## and the one the reference writes outside the block.
##
## **The else-arm is not optional.** A press on empty stage clears every one of
## the five, and a port that only *sets* them keeps the last click's drag channel
## and last click's member alive across a click that reached nothing.
static func latch_press(host, at: Vector2, channel: int) -> void:
	if host._host == null:
		return
	# **A press that ended a wait-for-click latches none of it** (`bugs.md` 61).
	# `Movie::processEvent` handles the mouse-down in one `if`/`else`
	# (`events.cpp:249-297`): `if (sc->_waitForClick) { _waitForClick = false;
	# renderCursor(pos, true); } else { … }`, and everything below -- the click
	# position and time, `the clickOn`, the hilite, the drag, the latched member,
	# and the `mouseDown` dispatch itself -- is in the else. So on a wait-for-click
	# frame the press does one thing and one thing only: it ends the wait.
	#
	# The port released the wait in `route_press` and then carried straight on
	# into this block and the mouse-down chain, so the click that ended the wait
	# was also a click on whatever sprite was under it. Piposh 2 has 24
	# wait-for-click frames and *Rating* has 214.
	#
	# **The mouse-*up* is a separate question and is deliberately not suppressed.**
	# `EVENT_LBUTTONUP` has no `_waitForClick` arm at all (`events.cpp:300-332`)
	# and `queueEvent` resolves a `mouseUp` from `getMouseSpriteIDFromPos` rather
	# than from anything the press latched (`lingo-events.cpp:579-597`), so the
	# release still reaches the sprite under it in the reference. Suppressing the
	# whole click would be a second bug wearing this one's clothes.
	if host._clock != null and host._clock.press_consumed():
		return
	# `the clickOn`, written by `rightMouseDown` as well as by `mouseDown`.
	host._host.click_sprite = channel
	if channel <= 0:
		# 1. §15: a click on empty stage beeps while `the beepOn` is set. Off by
		# default, which is the reference's default and the original's -- with it
		# on, every click that misses a hotspot beeps, and this game's menu
		# backdrop is ineligible so most of the stage is a miss.
		if bool(host._host.beep_on):
			host.lingo_beep(1)
		host._press_channel = 0
		host._mouse_down_in_button = false
		host._drag_channel = 0
		host._drag_offset = Vector2.ZERO
		host._press_member = {}
		return
	# 2 and 5 in one: the channel the press took, and the member it displayed.
	host._press_channel = channel
	host._press_member = EventChain.member_on(host, channel)
	# 3. *A* button, not this one. See the note above, and `latch_release`.
	host._mouse_down_in_button = _is_button(host, channel)
	# 4. §7.6's drag, which declines by itself when the sprite is not moveable.
	host._begin_drag(at, channel)


## §15's mouse-up block, the mirror of the one above and for either button.
##
## `under` is the channel the release landed on -- the same eligibility-filtered,
## ink-aware descent the press used.
##
## The button flip is the rule ScummVM's own comment calls senseless and
## reproduces anyway: **if the last press was in any button at all, the button
## under the release flips its hilite**, whether or not it is the button that was
## pressed and with nothing flipping on the way down. It is `set the hilite of
## member` state, so it goes where that write goes and outlives the click.
## Unexercised: 0 of the 51,350 members across the three corpora is of type
## `button`, so nothing here can fire on any title this engine has been pointed
## at, and it is built because Director has it.
static func latch_release(host, under: int) -> void:
	# §7.6: the drag ends on mouse-up, for either button.
	host._drag_channel = 0
	if bool(host._mouse_down_in_button) and under > 0 and _is_button(host, under):
		var member: Dictionary = _member_on(host, under)
		if not member.is_empty():
			var key: String = host._field_key(
				int(member["cast_lib"]), int(member["cast_id"]))
			host._member_hilite[key] = not bool(host._member_hilite.get(key, false))
	host._press_channel = 0
	host._mouse_down_in_button = false


## Is the member `channel` displays a **button** cast member (§15)?
static func _is_button(host, channel: int) -> bool:
	if host._table == null:
		return false
	var sprite: Dictionary = _member_on(host, channel)
	if sprite.is_empty():
		return false
	var member: Dictionary = host._table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	return str(member.get("type_name", "")) == "button"


## The effective sprite on `channel`, or `{}`. The *effective* one, so a member a
## script swapped in is the one asked about.
static func _member_on(host, channel: int) -> Dictionary:
	for raw in host.frame_sprites():
		if int(raw["channel"]) != channel:
			continue
		return host._effective(raw)
	return {}


## The mouse-UP half: the drag ends, and the message the press promised goes out.
##
## Reached only through `route_release`, which is reached only after a press this
## movie actually took -- so an empty `_click_script` here means "the press
## resolved to the movie tier", which is a real answer, and not "there was no
## press". That distinction is why the guard lives in the routing and not here.
##
## **Which of the two messages goes out is decided here.** Director (D6, and this
## game is D7) sends the pressed sprite a `mouseUp` only when the button came up
## *inside it*, and `mouseUpOutSide` when it came up anywhere else. Until now
## this port had neither test nor second message and sent `mouseUp`
## unconditionally, so a press-here-release-there click ran the handler for a
## click the player deliberately cancelled -- which is the standard way to back
## out of a mis-aimed press and the reason the message pair exists at all.
##
## **The test is the pressed sprite's own rect, not the topmost sprite under the
## pointer**, and the difference is exactly the case the last fix repaired. A
## drop lands the dragged item on a target: ask "is the pressed channel still the
## topmost hit here" and any target drawn above the item answers no, so the drop
## would get `mouseUpOutSide` and `BehaviorScript 52`'s `on mouseUp` -- the whole
## of the corpus's inventory idiom -- would never run. Ask "is the pointer inside
## the sprite that was pressed" and the dragged item, which follows the cursor by
## construction (§7.6), answers yes however many targets are stacked over it.
##
## A sprite that has left the frame between press and release gets `mouseUp`
## rather than `mouseUpOutSide`. There is no rect to be outside of, the score
## moved rather than the player, and the conservative answer is the one that
## still runs the handler the click was aimed at.
##
## **`the clickOn` and the recipient move together, and they moved.** §15's
## clause -- the clickOn is rewritten on the mouse-up when the release was over a
## sprite -- was implemented once here and reverted the same day, because it was
## taken without its other half: the reference rewrites `_lastClickedSpriteId`
## from `getMouseSpriteIDFromPos(event.mousePos)` **and delivers the mouse-up to
## that same sprite** (`lingo-events.cpp:143-148`, `kSpriteHandler`, D4+). Half of
## it makes one dispatch give two answers to "which sprite is this about", and
## the corpus's inventory idiom is written entirely on the two agreeing:
##
##     on mouseDown   objectxx = the locH of sprite the clickOn
##     on mouseUp     ... set the locH of sprite the clickOn to objectxx
##
## `MASTER/External/BehaviorScript 52` carries that pair on all eight of DAY1's
## inventory slots and eleven near-copies exist across the corpus. Both halves
## are here now, so the pair names one sprite again -- and on every drop the game
## actually asks for it names the *same* sprite the latch used to name, because a
## dragged sprite follows the cursor by construction (§7.6) and every drop target
## in the corpus is a **lower** channel than the slots: `intersects 100` is Pip's
## head, and 17, 9 and 7 are room hotspots. The descent answers the highest
## eligible sprite, so the dragged item answers for itself and the two readings
## agree. They differ only where the release lands on a *higher* eligible channel
## -- dropping a slot's item onto another slot along the bar -- and there
## Director rewrites `the clickOn` and the game sends the wrong sprite home.
## That is the reference's answer to a gesture the game does not ask for, and it
## is not this port's to improve.
##
## **One rule of the three did not move**, and it is now the only divergence
## left: a release *outside* the sprite that was pressed raises `mouseUpOutSide`
## to that sprite and no `mouseUp` at all, where the reference raises the
## `mouseUp` to whatever is under the release and defers `mouseUpOutSide` to the
## **next press** (§8.1). Kept because backing out of a mis-aimed press by
## sliding off before letting go is the gesture the message pair exists for, and
## because it stays coherent under the change above: `the clickOn` is rewritten
## only on the arm that dispatches `mouseUp`, so the sprite receiving
## `mouseUpOutSide` is still the sprite `the clickOn` names while it runs.
static func release(host, at: Vector2, under: int, right := false) -> void:
	# As in `press`: a window movie is told, because it cannot see the event.
	host.note_pointer(at)
	var script: Dictionary = host._click_script
	var pressed := int(host._press_channel)
	host._click_script = {}
	# §15's release block -- the drag ends, the button flip happens, the hilite
	# channel and the "was in a button" flag are cleared. Before the guard below,
	# because a drag must end on the button coming up whether or not there is an
	# interpreter to tell about it.
	latch_release(host, under)
	# §7.5: the cursor is recomputed on the mouse-up, one of the four moments
	# Director recomputes it at all.
	host._resolve_cursor()
	if not host._lingo_on or host._interpreter == null:
		return
	if pressed > 0 and not _release_inside(host, at, pressed):
		# §6.5: sprite behaviours only. There is deliberately no frame or movie
		# fallback -- a cancelled click is the sprite's business and nobody
		# else's, and routing it onward would give every frame script a second
		# copy of every abandoned press. `the clickOn` still names `pressed`
		# here, and that is the point: it is not rewritten on this arm.
		dispatch_sprite_only(host, "mouseUpOutSide", pressed)
		host.queue_redraw()
		return
	# §15: rewritten from the sprite under the release, and **only when that
	# answered something**. "Do not override when clicked on Score" is the
	# reference's own comment: a release over bare stage leaves the property
	# naming what the press latched, so `sprite the clickOn` in a frame script's
	# `on mouseUp` still has a sprite to be about.
	if under > 0:
		host._host.click_sprite = under
	var event := "rightMouseUp" if right else "mouseUp"
	# §6.3 tier 1, and it passes by default. See the note in `press` -- including
	# why the flag is carried in `pass_on` rather than reset in place.
	var pass_on := true
	if host._interpreter.run_primary(event.to_lower()):
		host._tally(host._ran, "when %s" % event)
		pass_on = bool(host._host.pass_event)
	# The left button only, for the reason `press` gives at its own call.
	if not right:
		host._host.pass_event = true
		if EventChain.run_primary_script(host, host._interpreter,
				host._host.mouse_up_compiled, "mouseUpScript"):
			pass_on = bool(host._host.pass_event)
	host._host.pass_event = pass_on
	host._dispatch(event, script)
	host.queue_redraw()


## Did the button come up inside the sprite that took the press?
##
## True when the channel is no longer on the frame at all, which is the "the
## score moved, not the player" case `release` documents. The frame is searched
## directly rather than inferred from a rect, because this is a question about
## the *mouse* and the two rect questions differ: `lingo_sprite_rect` answers for
## a hidden sprite, on purpose, and a sprite a `mouseDown` handler hid is not
## something the pointer can be inside of.
static func _release_inside(host, at: Vector2, channel: int) -> bool:
	for sprite in host.frame_sprites():
		if int(sprite["channel"]) != channel:
			continue
		var live: Dictionary = host._effective(sprite)
		# Hidden by a `mouseDown` handler: not drawn, not hit-tested, and so not
		# something the pointer can be inside of.
		if live.is_empty():
			return false
		return host._sprite_rect(live).has_point(at)
	return true


## The pair of messages a click sends, lowercased, for the button it was made
## with. `script_for_click` resolves against the **pair** and not against the
## single message in flight -- see its own note.
static func click_events(right: bool) -> Array:
	return ["rightmousedown", "rightmouseup"] if right \
		else ["mousedown", "mouseup"]


## Which script answers for a click on `channel`, and at which tier.
##
## Director's order: the sprite's own behaviour, then the script on the cast
## member it displays, then the frame script, then any movie script.
##
## **A tier that cannot answer the message does not take it**, and that rule is
## what makes §4.3's D6+ eligibility clause safe to turn on. From D6 a sprite
## with any behaviour attached is a click target whatever the behaviour declares
## (see `eligibility_reason`), so the descent now stops on sprites carrying an
## `exitFrame`-only behaviour -- 86 (movie, channel) pairs across the three
## corpora, measured by `tools/click_eligibility.gd`. Handing the click to such a
## behaviour and stopping there would be worse than never reaching it: the frame
## script is where this corpus's `the clickOn` idiom lives, and every one of
## those 188 would have become a dead patch of stage. Which is the complaint the
## eligibility work exists to fix, arriving from the other direction.
##
## Director does not have that problem, because it queues the whole chain and an
## element whose script declares no handler simply does not run -- it consumes
## nothing. This port resolves one element, so the equivalent is to skip a tier
## whose script cannot answer, which is what `events` is for. It is **not** the
## queue (§6.3): `pass` and `dontPassEvent` are still unbound, and a behaviour
## that declares `mouseDown` and not `mouseUp` still takes both messages and
## denies the frame script the second. `ENGINE_TODO.md` carries the queue.
##
## `events` is the pair the caller is about to send, lowercased. The pair rather
## than the single message being dispatched, because `press` latches this script
## for `release` to use (see `release`) -- resolving per message would send the
## down to the sprite and the up to the frame the moment a behaviour declared
## only one of them, and split one click between two scripts.
static func script_for_click(host, channel: int, sprites: Array,
		events: Array = ["mousedown", "mouseup"]) -> Array:
	var script: Dictionary = {}
	if channel > 0:
		var behaviour: Dictionary = host._sprite_script(channel, host._index)
		if _answers_any(host, behaviour, events):
			script = behaviour
		if script.is_empty():
			for sprite in sprites:
				if int(sprite["channel"]) == channel:
					# **The member the channel is displaying, not the one the score
					# gave it.** `preview/event_chain.gd:member_on` reads the live
					# channel here and this read the score record, so the two
					# disagreed the moment a script swapped a member -- and the
					# disagreement is invisible except in the report, because
					# `_dispatch` runs the chain and this only decides what the click
					# record *says*. `bugs.md` 101 is the same fault in the other
					# direction and cost four hypotheses; this one cost a session.
					#
					# Measured: `piposh-dream/hex1.dir`'s board is 58 channels the
					# score fills with member 56 and the movie's own init swaps to
					# member 3 (a piece), whose cast script declares `mouseUp`. A
					# click on a piece ran that handler and the record said
					# `movie script none  mouseUp:NO HANDLER`, which reads exactly
					# like a dead hotspot and is the opposite of what happened.
					#
					# Same rule as the eligibility test for *which* library: the
					# member's own, or a click runs a handler belonging to a
					# different cast's member of the same number.
					var live: Dictionary = host._effective(sprite)
					if live.is_empty():
						break
					var member_script: Dictionary = host._script_in_lib(
						int(live["cast_lib"]), int(live["cast_id"])
					)
					if _answers_any(host, member_script, events):
						script = member_script
					break
	if not script.is_empty():
		return [script, "sprite"]
	script = host._frame_script(host._index)
	return [script, "frame" if not script.is_empty() else "movie"]


## Can this script answer any of `events`?
##
## A **generic** script counts, for the same reason §4.3 counts it as a mouse
## handler: a scopeless score script is bare statements with no `on <event>` line
## to name, and §8.2 runs it on the click. So a tier holding one is a tier that
## answers, and skipping it because no handler is named would drop the whole D3
## idiom on the floor.
static func _answers_any(host, script: Dictionary, events: Array) -> bool:
	if script.is_empty():
		return false
	if not (script.get("body", []) as Array).is_empty():
		return true
	for event in events:
		if host._interpreter != null \
				and host._interpreter.call("_script_has_handler", script, str(event)):
			return true
	return false


## Outline every sprite on the frame that a script could actually answer for.
##
## A sprite with a behaviour attached is a hotspot in the ordinary sense; the
## rest are only reachable if a frame script asks `rollOver` or `the clickOn`,
## which is how this game's menu works -- so both are drawn, distinguished
## rather than filtered.
##
## **The per-pixel test asks `channel_at`'s question, with `channel_at`'s
## arguments.** It used to pass only the ink where the hit test passes the ink
## *and* the member type, so a matte-inked shape painted amber, "artwork only",
## while the hit test correctly treated it as a whole rect. That understated
## exactly the invisible shape hotspots this game is full of -- an overlay that
## says a target is smaller than it is sends the reader looking for a hit-test
## bug that is not there.
static func draw_hotspots(host, hover_channel: int, hit_pixels: bool,
		table) -> void:
	var font := ThemeDB.fallback_font
	for raw_sprite in host.frame_sprites():
		# Puppet state, exactly as the hit test sees it. A sprite a script has
		# hidden or moved is not where the score says, and outlining it there
		# would be worse than not outlining it at all.
		var sprite: Dictionary = host._effective(raw_sprite)
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		# Annotated rather than inferred: a call through `host` is untyped, so
		# `:=` has nothing to infer from.
		var rect: Rect2 = host._sprite_rect(sprite)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		# Only what can actually answer a click. This used to outline every
		# sprite and merely tint the ones with a behaviour attached, which made
		# the overlay a picture of the score rather than of what the mouse can
		# reach. On a D6+ movie "has a behaviour" happens to *be* the clause that
		# fires most (§4.3, clause 4), but it is one of six and not the test:
		# `moveable`, a button member and a member script all qualify without
		# one, and on a pre-D6 movie a behaviour that declares no mouse handler
		# does not qualify with one.
		if not responds_to_mouse(host, sprite, table):
			continue
		# Green where the whole rectangle answers, amber where only the artwork
		# does. That distinction is the one that costs people time: a Matte
		# sprite is clickable on its pixels and transparent to the mouse
		# everywhere else, so an outline that implies a solid target is a lie.
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var per_pixel := hit_pixels and Ink.hits_per_pixel(
			int(sprite["ink"]), int(member.get("type", 0)))
		var hovered := channel == hover_channel
		var tint := Color(1.0, 0.75, 0.2) if per_pixel else Color(0.2, 1.0, 0.4)
		if hovered:
			Paint.rect(host, rect, Color(tint.r, tint.g, tint.b, 0.18), true)
		Paint.rect(host, rect, Color(tint.r, tint.g, tint.b, 0.95 if hovered else 0.45),
			false, 2.0 if hovered else 1.0)
		if hovered:
			Paint.text(host, font, rect.position + Vector2(2, -3),
				"ch%d  %d:%d  %s" % [
					channel, int(sprite["cast_lib"]), int(sprite["cast_id"]),
					"artwork only" if per_pixel else "whole rect",
				],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)
