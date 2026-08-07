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
## `channel_at` and `draw_hotspots` currently disagree on one detail and the
## disagreement is preserved here rather than quietly fixed: the descent asks
## `hits_per_pixel(ink, member_type)` and the overlay asks `hits_per_pixel(ink)`.
## The overlay therefore paints a matte-inked *shape* as artwork-only when the
## hit test treats it as a whole rect. See `draw_hotspots`.
##
## Everything takes the preview node as `host`: the hit test needs puppet state,
## the artwork cache and the script table, all of which are the node's.

const Ink := preload("res://director/director_ink.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")

## How close two presses have to be to make `the doubleClick` true.
##
## Director asks the OS for the system double-click time; there is no such
## setting to ask for here, so this is the Mac default the game was authored
## against. It is a threshold rather than a decoded value, which is why it is
## named once instead of written into the comparison.
const DOUBLE_CLICK_MS := 500


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
	# Which of the two is right is an open question. `score.cpp` describes a
	# bounding-box test and no per-pixel matte test -- but Director also skips
	# sprites that do not respond to the mouse, which this preview has no notion
	# of, and without that filter a pure rect test hands every click to the
	# backdrop on channel 21. The pixel test is standing in for the filter I
	# cannot model yet, so both are available and `M` switches between them.
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
## Director asks whether a script attached to the sprite or to its cast member
## actually declares a mouse handler -- the presence of a script id is not enough
## -- or whether the sprite is moveable or a button. A backdrop with no handler
## is visible, hit-testable for other purposes, and simply not clickable.
static func responds_to_mouse(host, sprite: Dictionary, table) -> bool:
	var channel := int(sprite["channel"])
	if declares_mouse_handler(host._sprite_script(channel, host._index), host._interpreter):
		return true
	# In the library the sprite names, not by number alone. Member numbers are
	# per cast, so a number-only search answers with a stranger -- and here that
	# is not silence but a false positive: it makes a sprite clickable because
	# some *other* cast happens to have a script at that number, and the click
	# then runs that stranger.
	#
	# DAY1's beach is the case that found it. Channel 1 is `3:10`, the room
	# backdrop `shore2`, a plain bitmap with no script of its own. A number-only
	# search found a mouse handler anyway, so the backdrop answered clicks across
	# its whole 640x400 rect -- and since the walkable ground is a separate Matte
	# sprite on channel 2 covering only the bottom 154 pixels, clicking the *sea*
	# fell through to the backdrop and walked the character up into it.
	if declares_mouse_handler(host._script_in_lib(
			int(sprite["cast_lib"]), int(sprite["cast_id"])), host._interpreter):
		return true
	# A moveable sprite is click-eligible on its own, with no script at all --
	# it has to be, or nothing could start a drag. The sprite handed in here has
	# already been through `effective`, so this is the score's bit and the Lingo
	# write merged, not just the latter.
	if bool(sprite.get("moveable", false)):
		return true
	var m: Dictionary = table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	return str(m.get("type_name", "")) == "button"


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
	host._interpreter.call_handler(handler, [], script)
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
## rendering fault rather than a constraint. The same answer covers a hidden
## constraint channel, since `lingo_sprite_rect` treats `visible` as "not drawn
## and not measured" throughout the port.
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
static func press(host, at: Vector2) -> void:
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
	host._press_channel = 0
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
	var channel: int = host._channel_at(at)
	# `the clickOn` is latched by the mouse-DOWN and holds until the next one, so
	# it still names the dragged channel when the release arrives. Recomputing it
	# under the pointer at mouse-up would usually answer the same thing -- the
	# dragged sprite is under the cursor by construction -- and would be wrong the
	# moment a handler moves or hides it, which `BehaviorScript 52` does on its
	# own last two lines.
	host._host.click_sprite = channel
	var chosen: Array = script_for_click(
		host, channel, host._score.frame(host._index).get("sprites", []))
	var script: Dictionary = chosen[0]
	# Says what was clicked, which script is about to answer for it, and whether
	# a handler actually exists. "clicked nothing" and "clicked something with no
	# mouseUp" look identical on screen and are entirely different faults.
	var has_up: bool = host._interpreter.call("_script_has_handler", script, "mouseup") \
		or host._interpreter.has_handler("mouseup")
	# Kept, not just printed: the snapshot key reports the click that went wrong,
	# and by the time anyone presses it the score has moved on several frames.
	host._last_click = Snapshot.note_click(
		at, host._index, channel, str(chosen[1]), script, has_up)
	print(Snapshot.click_line(host._last_click))
	# Held for the release. Director sends `mouseUp` to the sprite that took the
	# `mouseDown`, not to whatever is under the pointer when the button comes up,
	# and resolving it again at release would ask a different question of a score
	# that may have advanced frames in between.
	host._click_script = script
	# The channel as well as the script, because the release has to answer a
	# question the script cannot: was the button let go *inside the sprite that
	# was pressed*. `release` below is where that is decided.
	host._press_channel = channel
	# §6.3 tier 1. A primary handler runs ahead of every other tier and, unlike
	# every other tier, **passes by default** -- so the sprite/frame/movie
	# dispatch below happens anyway unless the handler called `dontPassEvent`.
	# Inverting that default is the classic Director bug, so the ordering here is
	# "run it, then carry on" rather than "run it and stop if it claimed".
	if host._interpreter.run_primary("mousedown"):
		host._tally(host._ran, "when mouseDown")
	_run_primary_script(host, str(host._host.mouse_down_script), "mouseDownScript")
	host._dispatch("mouseDown", script)
	host.queue_redraw()


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
static func release(host, at: Vector2) -> void:
	# As in `press`: a window movie is told, because it cannot see the event.
	host.note_pointer(at)
	# §7.6: the drag ends on mouse-up. §7.5: the cursor is recomputed there too --
	# one of the four moments Director recomputes it at all.
	host._drag_channel = 0
	host._resolve_cursor()
	var script: Dictionary = host._click_script
	var pressed := int(host._press_channel)
	host._click_script = {}
	host._press_channel = 0
	if not host._lingo_on or host._interpreter == null:
		return
	# §15: `the clickOn` updates on mouse-down always, and on mouse-up **only when
	# the release was over a sprite**. Updated before the dispatch, so a handler
	# reading it sees the click it is answering -- and left alone on a release
	# over bare stage, which is what keeps `sprite the clickOn` naming something
	# real after a drag that ended off every hotspot.
	var under: int = host._channel_at(at)
	if under > 0:
		host._host.click_sprite = under
	if pressed > 0 and not _release_inside(host, at, pressed):
		# §6.5: sprite behaviours only. There is deliberately no frame or movie
		# fallback -- a cancelled click is the sprite's business and nobody
		# else's, and routing it onward would give every frame script a second
		# copy of every abandoned press.
		dispatch_sprite_only(host, "mouseUpOutSide", pressed)
		host.queue_redraw()
		return
	# §6.3 tier 1, and it passes by default. See the note in `press`.
	if host._interpreter.run_primary("mouseup"):
		host._tally(host._ran, "when mouseUp")
	_run_primary_script(host, str(host._host.mouse_up_script), "mouseUpScript")
	host._dispatch("mouseUp", script)
	host.queue_redraw()


## `the mouseDownScript` / `the mouseUpScript`, the other half of §6.3 tier 1.
##
## Run alongside the `when <event> then` handler rather than instead of it: both
## are tier 1, and both pass by default, so the sprite/frame/movie tiers run
## afterwards either way. Same shape as `_dispatch_key`'s `keyDownScript` arm,
## and the same divergence -- the value is treated as a handler name, because
## this port cannot compile a source string at run time.
static func _run_primary_script(host, name: String, tally: String) -> void:
	var handler := name.strip_edges().to_lower()
	if handler == "" or not host._interpreter.has_handler(handler):
		return
	host._tally(host._sent, tally)
	host._tally(host._ran, tally)
	host._interpreter.call_handler(handler)


## Did the button come up inside the sprite that took the press?
##
## True when the channel is no longer on the frame at all, which is the "the
## score moved, not the player" case `release` documents: `lingo_sprite_rect`
## cannot tell an absent channel from a hidden one, so the frame is searched
## directly rather than inferred from an empty rect.
static func _release_inside(host, at: Vector2, channel: int) -> bool:
	for sprite in host._score.frame(host._index).get("sprites", []):
		if int(sprite["channel"]) != channel:
			continue
		var live: Dictionary = host._effective(sprite)
		# Hidden by a `mouseDown` handler: not drawn, not hit-tested, and so not
		# something the pointer can be inside of.
		if live.is_empty():
			return false
		return host._sprite_rect(live).has_point(at)
	return true


## The right button, which this port ignored entirely until now (§8.1, D5).
##
## Routed through the same tier resolution as the left, because `rightMouseDown`
## and `rightMouseUp` sit in the same list in §6.3 and reach the same five tiers.
## What it deliberately does *not* do is touch the drag, `the clickOn` or a
## wait-for-click: §7.6's drag and §9.2's wait are both the left button's, and a
## right-click that cancelled a drag or advanced a held frame would be this port
## inventing behaviour rather than porting it.
static func right_button(host, at: Vector2, pressed: bool) -> void:
	if not host._lingo_on or host._interpreter == null:
		return
	var event := "rightMouseDown" if pressed else "rightMouseUp"
	if host._interpreter.run_primary(event.to_lower()):
		host._tally(host._ran, "when %s" % event)
	var chosen: Array = script_for_click(
		host, host._channel_at(at), host._score.frame(host._index).get("sprites", []))
	host._dispatch(event, chosen[0])
	host.queue_redraw()


## Which script answers for a click on `channel`, and at which tier.
##
## Director's order: the sprite's own behaviour, then the script on the cast
## member it displays, then the frame script, then any movie script.
static func script_for_click(host, channel: int, sprites: Array) -> Array:
	var script: Dictionary = {}
	if channel > 0:
		script = host._sprite_script(channel, host._index)
		if script.is_empty():
			for sprite in sprites:
				if int(sprite["channel"]) == channel:
					# Same rule as the eligibility test: the member's own library
					# decides, or a click runs a handler belonging to a different
					# cast's member of the same number.
					script = host._script_in_lib(
						int(sprite["cast_lib"]), int(sprite["cast_id"])
					)
					break
	if not script.is_empty():
		return [script, "sprite"]
	script = host._frame_script(host._index)
	return [script, "frame" if not script.is_empty() else "movie"]


## Outline every sprite on the frame that a script could actually answer for.
##
## A sprite with a behaviour attached is a hotspot in the ordinary sense; the
## rest are only reachable if a frame script asks `rollOver` or `the clickOn`,
## which is how this game's menu works -- so both are drawn, distinguished
## rather than filtered.
##
## **Known divergence from `channel_at`, preserved by this move rather than
## introduced by it.** The per-pixel test here passes only the ink; the hit test
## passes the ink *and* the member type. A matte-inked shape therefore paints
## amber, "artwork only", while the hit test correctly treats it as a whole
## rect -- so the overlay understates exactly the invisible shape hotspots this
## game is full of. Fixing it means passing the member type here too.
static func draw_hotspots(host, frame: Dictionary, hover_channel: int,
		hit_pixels: bool, table) -> void:
	var font := ThemeDB.fallback_font
	for raw_sprite in frame.get("sprites", []):
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
		# reach -- and eligibility is not "has a behaviour": a member script, a
		# button or `moveable` all qualify, and a behaviour that declares no
		# mouse handler does not.
		if not responds_to_mouse(host, sprite, table):
			continue
		# Green where the whole rectangle answers, amber where only the artwork
		# does. That distinction is the one that costs people time: a Matte
		# sprite is clickable on its pixels and transparent to the mouse
		# everywhere else, so an outline that implies a solid target is a lie.
		var per_pixel := hit_pixels and Ink.hits_per_pixel(int(sprite["ink"]))
		var hovered := channel == hover_channel
		var tint := Color(1.0, 0.75, 0.2) if per_pixel else Color(0.2, 1.0, 0.4)
		if hovered:
			host.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.18), true)
		host.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.95 if hovered else 0.45),
			false, 2.0 if hovered else 1.0)
		if hovered:
			host.draw_string(font, rect.position + Vector2(2, -3),
				"ch%d  %d:%d  %s" % [
					channel, int(sprite["cast_lib"]), int(sprite["cast_id"]),
					"artwork only" if per_pixel else "whole rect",
				],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)
