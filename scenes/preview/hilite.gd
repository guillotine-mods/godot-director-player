extends RefCounted
## Hilite on click: the sprite you are pressing inverts while you hold it.
##
## `DIRECTOR_ENGINE.md` §4.6, and the reference is
## `sprite.cpp:Sprite::shouldHilite`, `events.cpp:Movie::processSysEvent` and
## `window.cpp:Window::invertChannel`.
##
## **Why this is worth more than its size.** It is the only *feedback* mechanism
## in the engine. Without it a dead hotspot and a live one look identical at the
## moment of the click, so every "I clicked and nothing happened" report starts
## from zero. With it, the picture on screen answers the first question -- did
## the press reach a sprite that can respond -- before anybody opens a log.
##
## Three separate questions, and mixing them up is how ports get this wrong:
##
##   *which sprite*    the one the mouse-down landed on, held for the press
##   *when*            while the button is down **and** the pointer is inside it
##   *what it does*    invert the silhouette, not the box
##
## ### Which sprite
##
## The channel the press latched (`interaction.gd:press` -> `_press_channel`),
## not whatever is under the pointer now. ScummVM re-resolves the topmost
## responding sprite on every motion while the button is held, which means
## pressing button A and sliding onto button B hilites B -- a control that
## hilites without having been pressed. Mac control tracking, which auto-hilite
## exists to emulate, tracks the control the press went to and no other, and this
## port already draws that line for `mouseUp` versus `mouseUpOutSide`
## (`interaction.gd:release`). Divergence from the reference, taken deliberately,
## and the one place it shows is press-A-drag-onto-B.
##
## ### When
##
## On at mouse-down, off at mouse-up -- and off again the moment the pointer
## leaves the sprite while the button is still held, back on when it re-enters.
## That last part is the reference's, not an invention: `events.cpp` drops the
## hilite on `EVENT_MOUSEMOVE` when `isMouseIn(pos) != kCollisionYes`, and
## re-arms it on a later move while the button is down. So "leaves" is measured
## by the **ink-aware** test -- an irregular Matte sprite un-hilites when the
## pointer crosses onto one of its transparent pixels, not when it crosses its
## bounding box.
##
## One gap, named rather than papered over: the repaint that shows the change is
## `input_router.mouse_motion`'s, and it asks for one when the *hovered* channel
## changes. Those agree except when the pointer slides off the pressed sprite
## while staying over the same higher sprite -- then the answer here changes and
## nothing asks for a paint. A running movie repaints on its own frame cadence
## and never shows it; a paused preview holds the stale inversion until the next
## paint. The fix is one line in `mouse_motion` -- request a paint whenever a
## press is live -- and it is in a file this change does not own.
##
## ### What it does
##
## `Ink.invert` has the pixel rule and the one divergence. Here it is enough that
## the inverted image carries the same alpha, so drawing it *instead of* the
## normal artwork is the masked XOR rather than a rectangle painted over the top.
## A box-shaped flash is the wrong answer and looks obviously wrong on irregular
## buttons -- it is the same failure EXODUS's selection highlight had when a
## blended bar drew opaque (`stage_paint.gd`).
##
## Nothing here knows what game is loaded.
##
## ## The second trigger: `hint` (`bugs.md` 130)
##
## Everything above is feedback for a click the player has already made. The
## bottom half of this file is the same mechanism reached from the other end --
## the player asks "what *can* I click here", and the engine answers by marking
## one thing the click router would actually reach.
##
## **It lives here rather than in a third overlay for the reason the header
## above gives**: this is already the file that answers "which sprite is marked,
## when, and what the mark looks like", and a second file answering the same
## three questions is how `channel_at` and `draw_hotspots` came to disagree about
## `hits_per_pixel`'s arguments. One mark, one place.
##
## **Three properties, and the second is the one worth the code.**
##
##   *title-agnostic*  the question is asked of the **frame**: which of the
##                     sprites the score placed can answer a mouse message. No
##                     room, no channel number and no title appears below, and
##                     nothing here reads a marker -- which is the whole
##                     difference between this and the `skip_minigame` action
##                     `bugs.md` 129 deleted. Skip had to know which markers are
##                     scenes and a `VWLB` does not say; this needs to know what
##                     is clickable, and the score does say.
##
##   *it cannot lie*   a hint that points somewhere a click would not reach is
##                     worse than no hint, because the player acts on it. So a
##                     candidate is not merely "eligible": `reachable_point` runs
##                     `interaction.gd:channel_at` -- the click router's **own**
##                     descent, not a re-implementation of it -- at sample points
##                     inside the sprite and keeps the first point the descent
##                     resolves back to that same channel. A sprite that is
##                     eligible but wholly covered by a higher eligible one is
##                     skipped, because clicking it is not possible.
##                     `tools/hint.gd` asserts both halves against the router.
##
##   *player-facing*   `debug_keys.gd:enabled()` gates what exists for **us**; an
##                     accessibility affordance the player asked for is not that,
##                     so the mark is drawn on the player side of the switch and
##                     a shipped build still has it. Two consequences are
##                     deliberate. `hint` is **not** a `DebugKeys` command -- it
##                     is an `InputMap` action in `project.godot`, so nothing is
##                     added to the map `tools/debug_bindings.gd` asserts is empty
##                     when the layer is off. And the mark carries **no text**:
##                     these titles are Hebrew and Russian, and an English word
##                     painted over a 1997 stage is chrome, not help. The words go
##                     in the debug toast, which is already behind the switch, and
##                     the shape goes on the stage.
##
## ## Why the mark is drawn from `artwork`
##
## `artwork` is the only hook this change owns that runs on the player side of
## every paint: `sprite_art.draw` calls it for every drawn sprite of every frame,
## and `stage_paint.gd` reaches that unconditionally. `director_preview.gd:_paint`
## has a second, tidier place to put an overlay and it is **below**
## `DebugKeys.enabled()`, which is the wrong side of the switch for this.
##
## So the momentary hint is drawn from the **stored rect**, not from the sprite
## being drawn, and it is drawn on *every* call rather than on the hinted
## sprite's. Both follow from the hook:
##
##   - drawing from the stored rect means the hint works for a member type that
##     never reaches `artwork` at all -- a field, a film loop, a digital video --
##     each of which `stage_paint.gd` consumes before `_texture_for` is asked.
##     Keying the draw on "is this the hinted sprite" would have silently made
##     those three unhintable, which is a hole shaped exactly like the ones
##     `AGENTS.md` warns about: from the chair it would look like the hint had
##     chosen nothing.
##   - drawing on every call puts the last copy immediately under the topmost
##     sprite, so the outline reads as being *over* the stage rather than buried
##     under whatever is painted after it. The stroke is opaque, so N copies of it
##     are indistinguishable from one; the cost is two `Paint.rect` commands per
##     sprite for the two and a half seconds a hint is up.
##
## The persistent form -- `qol/hotspot_hints`, `bugs.md` 130's secondary half --
## is the exception and is drawn per sprite, because "outline everything
## clickable" over the stored-rect route would be one rect list redrawn once per
## sprite, which is quadratic. That narrows it to the sprites `artwork` sees, so
## a clickable *field* is not outlined by the persistent toggle while it is by
## the momentary hint. Recorded rather than smoothed over: it is the cost of the
## hook, and it goes away the day the stage grows a player-side overlay pass.

const Ink := preload("res://director/director_ink.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
## Read, never written. The whole point of the hint is that it answers with the
## click router's own eligibility and the click router's own descent rather than
## with a second opinion about either -- `interaction.gd` is not this change's to
## edit and does not need to be.
const Interaction := preload("res://scenes/preview/interaction.gd")
const Paint := preload("res://director/director_paint.gd")

## The hint's whole state, as metadata on the preview node.
##
## **Metadata rather than a field on the node**, which is the one place this
## departs from `preview/README.md`'s "state stays on the node". The node is
## `scenes/director_preview.gd` and adding a `var` to it was not available to
## this change; `set_meta` puts the state on the same object, where `tools/` can
## read it by name exactly as it reads a field, and where a harness that reads
## the wrong key gets `{}` and fails its assertion rather than reading a silent
## zero. `hint_state` is the only reader and the only writer.
##
## Not a `static var`, and that is a measurement rather than a preference:
## `director_preview.gd:_paint` records that Godot clears a script's statics
## during engine teardown while `_draw` is still firing, which cost
## `key_affordance.gd` 1,556 error lines in one gate log. A node's metadata is the
## node's and outlives nothing.
const HINT_META := "director_hint"

## How long one press stays up. The toast's own `SECONDS`, deliberately: the two
## are the same event seen twice -- the shape on the stage and the words in the
## debug log -- and a mark that outlived its explanation would be the pair
## disagreeing.
const HINT_MS := 2500

## The mark blinks rather than fading. A fade needs alpha, and alpha compounds
## when the same stroke is drawn once per sprite (see the header); a blink is
## expressible with an opaque stroke, and it is the louder of the two, which is
## what an accessibility affordance wants.
const HINT_BLINK_MS := 320

## Outside the sprite's own rect, so the sprite's artwork -- drawn immediately
## after this in `sprite_art.draw` -- cannot cover its own outline.
const HINT_GROW := 2.0
const HINT_WIDTH := 2.0

## Amber. `interaction.gd:draw_hotspots` uses amber for "artwork only" and green
## for "whole rect"; this is neither of those questions and it is not that
## overlay -- it is one target rather than a survey, and it is on the player's
## side of the debug switch where that overlay is not.
const HINT_COLOUR := Color(1.0, 0.78, 0.12, 1.0)

## How finely a candidate is probed for a point the click router agrees is its.
##
## The rect's centre is tried first and answers for almost everything; the grid is
## what finds a foothold on a sprite whose middle is covered by a higher eligible
## sprite, or on a Matte sprite whose middle is a transparent hole. 5x5 is 25
## descents in the worst case for a candidate that has no reachable point at all,
## and the whole search runs once per keypress.
const HINT_SAMPLES := 5


## The artwork this sprite should draw with: the inverted copy while it is
## hilited, and the texture it was handed otherwise.
##
## Called from `sprite_art.draw` for every sprite of every frame, so the common
## path is one integer comparison: `_press_channel` is 0 unless a button is
## physically down, and even then only the pressed channel goes any further.
##
## `canvas` is the preview node -- `sprite_art.draw` receives it as the thing it
## paints on, and it is also the host that owns the caches and the puppet state.
## Held untyped for that reason: a `CanvasItem`-typed variable cannot be asked
## for `_press_channel` without failing to compile.
static func artwork(canvas: CanvasItem, texture: Texture2D,
		sprite: Dictionary) -> Texture2D:
	var host = canvas
	# **Ahead of the null guard and ahead of everything else**, because it is the
	# player's half of this file and the rest is the movie's. It draws nothing at
	# all unless a hint is up or `qol/hotspot_hints` is on, and the whole of the
	# common path is one `has_meta` (see `mark`).
	mark(host, sprite)
	if texture == null:
		return texture
	# **`set the hilite of member` is the other hilite, and it comes first.**
	#
	# Everything below this is *auto*-hilite: the movie asks for none of it, the
	# press decides, and it lasts as long as the button is held. This is the other
	# mechanism: a flag a script sets and the movie leaves set (§4.6).
	#
	# **It reaches the screen for a button member and for nothing else.** The
	# reference stores the flag on the cast member base class for every type --
	# `castmember.cpp:CastMember::setField(kTheHilite)` accepts it and never
	# refuses -- and reads it back in exactly one place: `text.cpp:355`, under
	# `case kCastButton:`, where it becomes `MacButton::setHilite`. `bitmap.cpp`
	# and `shape.cpp` never mention `_hilite` at all. So a script may set it on a
	# bitmap, and Director stores the value, answers `the hilite of member` with
	# it, and draws nothing differently.
	#
	# Without that test this inverted Rating's artwork wherever the movie made the
	# write, which it does at **39 sites across 21 containers** -- naming hotspot
	# rectangles, bitmaps and film loops. Every one of them must draw nothing,
	# because *Rating* has **0 button members in all 19,074 of them**. The visible
	# one was Zehava at the pool: `HOTEL.cst`'s `on exitFrame` sets the hilite of
	# members 196, 197 and 198 of castLib 1, `NAVIGATE.dir`'s three 77x84 frames of
	# her, and she swam in reverse video (`docs/bugs-closed.md` 66). Piposh 1, 2 and
	# Dream have 0 sites, which is why this survived: the corpus the port was built
	# against never writes it.
	#
	# The button arm is **unreachable, not merely unverified**, and the difference
	# matters to whoever reads this next. `preview/sprite_art.gd:texture_for`
	# decodes bitmaps and shapes and returns null for every other type, a button
	# is type 7, `stage_paint.gd` skips a sprite with no texture, and this
	# function returns on its own first line when handed one. So no button member
	# reaches this line, and the true branch below has never run and cannot.
	#
	# It is written anyway because the gate is on the *false* branch: without the
	# test this inverted every type, which is the bug. Keeping the arm says what
	# the rule is rather than leaving a bare "draw nothing" that reads like the
	# flag has no consumer at all.
	#
	# What has to happen before it means anything: a button member has to be
	# drawable, which is a button *widget* -- the reference hilites a `MacButton`,
	# a Mac control that draws itself inverted, not `Ink.invert` over authored
	# artwork. Inverting the picture is the nearest thing this port has and is
	# what the auto-hilite path below already does, and it is a guess until there
	# is something to compare it against. `tools/hilite.gd` asserts the
	# unreachability rather than faking a button, so the day the widget lands the
	# check fails and points here.
	#
	# One clause narrower than the reference, and unreachable for the same reason:
	# `castmember/text.cpp:320-322` reassigns `type = kCastButton` when a **text**
	# member sits on sprite type 8, 9 or 10 (`util.cpp:1361` -- button, checkbox,
	# radio), so Director's `setHilite` reaches a field on a button sprite too.
	# This port draws a field as glyphs and never through `texture_for`, so that
	# path is as dead as this one; `director_score.gd` already decodes
	# `sprite_type` for whoever revives both.
	#
	# There is no button member in any of the three corpora to check any of it
	# against (`interaction.gd:latch_release` measures 0 of 51,350).
	#
	# Substituted here rather than painted as a second pass, for the reason the
	# block below this function gives: the inverted copy carries the same alpha,
	# so flip, blend and the clip apply to it exactly as they do to the plain
	# picture and there is no second copy of any of them.
	if sprite.has("cast_lib") and not host._member_hilite.is_empty():
		var key: String = host._field_key(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		if bool(host._member_hilite.get(key, false)) and is_button(host, sprite):
			var set_by_script := _inverted(host, sprite)
			if set_by_script != null:
				return set_by_script
	var pressed := int(host._press_channel)
	if pressed <= 0:
		return texture
	# A film loop's children arrive here carrying their *own* mini-score channel
	# numbers, which collide with the stage's: a loop with an internal channel 3
	# would invert whenever stage channel 3 was pressed. They are distinguishable
	# because a child names its cast by name and has no `cast_lib`
	# (`director/director_film_loop.gd`), and they should not hilite in any case --
	# the member the *sprite* displays is a film loop, and §4.6 admits only
	# bitmaps.
	if not sprite.has("cast_lib") or int(sprite.get("channel", 0)) != pressed:
		return texture
	if not should_hilite(host, sprite):
		return texture
	if not mouse_in(host, sprite, host.stage_mouse()):
		return texture
	var inverted := _inverted(host, sprite)
	return inverted if inverted != null else texture


## Does this sprite display a **button** cast member?
##
## The whole of `set the hilite of member`'s reach on the screen, and the reason
## `artwork` asks: the reference's only consumer of the flag is the `kCastButton`
## arm of `text.cpp:createWidget`. Every other type stores the flag and draws
## itself unchanged.
##
## Public because the gate harness asserts the same rule from the outside, and a
## check that re-derives the type test rather than calling it would keep passing
## if this one drifted.
##
## A sprite with no member, or a host with no cast table, is not a button. False
## is the answer that draws the authored picture, which is the safe half: a
## missed button is a control that does not flash, a false positive is artwork in
## reverse video, and the second is what this function exists to stop.
static func is_button(host, sprite: Dictionary) -> bool:
	if host == null or host._table == null or not sprite.has("cast_lib"):
		return false
	var member: Dictionary = host._table.get_member(
		int(sprite["cast_lib"]), int(sprite.get("cast_id", 0)))
	return str(member.get("type_name", "")) == "button"


## §4.6's predicate, clause for clause against `sprite.cpp:Sprite::shouldHilite`.
##
## `isActive()` first, then **not** moveable and **not** puppet. The first clause
## of `isActive` is "moveable", which the second test then rejects, so a moveable
## sprite can never hilite -- that is not redundancy in the reference, it is the
## reason a draggable inventory icon does not flash when you pick it up.
static func should_hilite(host, sprite: Dictionary) -> bool:
	if not is_active(host, sprite):
		return false
	# The sprite handed in has already been through `sprite_state.effective`, so
	# this is the score's own moveable bit and any `the moveableSprite of sprite`
	# write merged into one answer.
	if bool(sprite.get("moveable", false)):
		return false
	# A puppeted channel belongs to the scripts, and Director will not paint over
	# a picture a script is composing. `_overrides` has an entry for exactly the
	# channels `puppetSprite` or a property write has claimed
	# (`preview/sprite_state.gd:set_puppet`).
	if host._overrides.has(int(sprite.get("channel", 0))):
		return false
	var m: Dictionary = host._table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	if m.is_empty():
		# No cast member at all is the reference's QuickDraw-shape arm: a sprite
		# whose *type* is a rectangle or an oval, with no member behind it, still
		# hilites when its ink is Matte. This port has no cast-less sprite -- the
		# score drops a record with no member (`director_score.gd:230`) -- so the
		# arm is written for the model rather than for anything reachable here.
		return (int(sprite.get("ink", 0)) & Ink.INK_MASK) == Ink.MATTE
	# Bitmaps only, and this is the clause that surprises people: a **shape cast
	# member** does not hilite even with Matte ink, because the reference tests
	# the member type before it ever looks at the ink. The shapes that do hilite
	# are the cast-less QuickDraw ones above. This corpus's invisible hotspots are
	# matte-inked shape members, so without this clause every door in the game
	# would flash a black rectangle on every click.
	if int(m.get("type", 0)) != Ink.TYPE_BITMAP:
		return false
	# D3 introduced the Auto Hilite tick box, and from D4 on every member carries
	# an info block to hold it. Where there is no info block -- a D3 member the
	# author never named or scripted -- the older rule stands in: Matte ink means
	# a button. D2, which had neither the flag nor a version of this file that
	# could read it, used the Matte rule unconditionally; it collapses into the
	# same fallback here and there is no D2 container this port can open anyway.
	if bool(m.get("has_cast_info", false)):
		return bool(m.get("auto_hilite", false))
	return (int(sprite.get("ink", 0)) & Ink.INK_MASK) == Ink.MATTE


## `isActive()`: the looser D3 rule. Moveable, or a button, or a score script
## *exists*, or a cast script *exists* -- **presence only**.
##
## Deliberately not `interaction.responds_to_mouse`, which is the D4+ rule and
## inspects the compiled script for a `mouseDown`/`mouseUp` handler. The two
## answer different questions and §4.3 keeps them apart: a sprite whose behaviour
## declares only `mouseEnter` is not a click target but *is* active, so it
## hilites under the press even though no handler will run. That is Director's
## behaviour and it is also the more useful one to have -- it says "this sprite
## has something attached", which is exactly what a player wondering why nothing
## happened needs to see.
static func is_active(host, sprite: Dictionary) -> bool:
	if bool(sprite.get("moveable", false)):
		return true
	var m: Dictionary = host._table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	if str(m.get("type_name", "")) == "button":
		return true
	if not host._sprite_script(int(sprite.get("channel", 0)), host._index).is_empty():
		return true
	# In the library the sprite names, for the reason `responds_to_mouse` gives at
	# length: member numbers are per cast, so a number-only search makes a sprite
	# active because some other cast has a script at that number.
	return not host._script_in_lib(
		int(sprite["cast_lib"]), int(sprite["cast_id"])).is_empty()


## `isMouseIn`: is the point over this sprite, by the same rule the hit test uses?
##
## Rect first, then the artwork for Matte-inked bitmaps and nothing else -- §4.4
## and `director/director_ink.gd:hits_per_pixel`. Asked of this one sprite rather
## than by descending the channels, because "did the pointer leave the button I
## am pressing" is not the same question as "what is on top here": a drop target
## drawn above the pressed sprite would answer the second and must not cancel the
## hilite. `interaction.release` draws the same distinction for `mouseUpOutSide`.
static func mouse_in(host, sprite: Dictionary, at: Vector2) -> bool:
	var rect: Rect2 = host._sprite_rect(sprite)
	if not rect.has_point(at):
		return false
	var m: Dictionary = host._table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	if not Ink.hits_per_pixel(int(sprite.get("ink", 0)), int(m.get("type", 0))):
		return true
	return bool(host._opaque_at(sprite, at))


## The inverted artwork for a sprite, derived once and kept.
##
## Rebuilding it per paint would be a full per-pixel pass over the member for
## every frame the button is held, which for a backdrop-sized sprite is the whole
## stage at the frame rate. So it is cached on the node beside `_textures` and
## `_hit_images` and under the same key.
##
## **The entry is validated against the Image it was derived from, not against
## whoever remembers to clear it.** The obvious design is to empty this wherever
## those two are emptied -- a palette change and a movie change -- and it is the
## design that rots: the two clear sites are in different files, one of them is
## somebody else's, and a third will appear. Since `_hit_images` hands out a new
## `Image` object every time it is repopulated, holding the source alongside the
## texture and comparing by identity makes a stale entry impossible to return.
## Nothing outside this function has to know the cache exists.
##
## A miss is cached as readily as a hit: `_hit_images` has no entry for a member
## that decoded to nothing, and re-asking every paint would cost what not caching
## costs.
static func _inverted(host, sprite: Dictionary) -> Texture2D:
	var m: Dictionary = host._table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var key := Geometry.texture_key(sprite, Geometry.drawn_size(sprite, m))
	var source: Image = host._hit_images.get(key)
	var cache: Dictionary = host._hilite_textures
	var held: Dictionary = cache.get(key, {})
	if held.get("source", null) == source:
		return held.get("texture", null)
	if source == null or source.get_width() <= 0 or source.get_height() <= 0:
		cache[key] = {"source": source, "texture": null}
		return null
	var texture := ImageTexture.create_from_image(Ink.invert(source))
	cache[key] = {"source": source, "texture": texture}
	return texture


# ---------------------------------------------------------------------------
# `hint`: the mark the player asks for. `bugs.md` 130, and the header above for
# why it is in this file rather than in a third overlay.
# ---------------------------------------------------------------------------


## The hint's state on `host`, as a dictionary that is safe to mutate in place.
##
## Always answers the same shape, so no caller has to test for a missing key --
## `channel` 0 means "nothing is marked", and it survives the deadline on purpose
## because it is also the cursor `request` cycles from.
##
##   channel  the channel the momentary hint named, 0 for none
##   until    `Time.get_ticks_msec()` deadline for that mark
##   rect     the marked sprite's stage rect **as it was when the hint was taken**
##   point    the stage point a click has to land on to reach it
##   reason   `interaction.gd:eligibility_reason`'s clause, for the debug toast
##   all      `qol/hotspot_hints`: outline everything eligible, with no deadline
static func hint_state(host) -> Dictionary:
	if host == null:
		return {"channel": 0, "until": 0, "rect": Rect2(), "point": Vector2.ZERO,
			"reason": "", "all": false}
	if host.has_meta(HINT_META):
		return host.get_meta(HINT_META)
	var fresh := {"channel": 0, "until": 0, "rect": Rect2(),
		"point": Vector2.ZERO, "reason": "", "all": false}
	host.set_meta(HINT_META, fresh)
	return fresh


## Is a momentary hint still up?
static func hint_live(host) -> bool:
	var state := hint_state(host)
	return int(state["channel"]) > 0 and int(state["until"]) > Time.get_ticks_msec()


## Turn the persistent form on or off. `qol/hotspot_hints`' only reader, reached
## from `autoload/input_router.gd` -- which is where this engine's knowledge of
## `AppSettings` lives, so that a preview module does not grow a second one.
static func set_persistent(host, on: bool) -> void:
	var state := hint_state(host)
	if bool(state["all"]) == on:
		return
	state["all"] = on
	host.set_meta(HINT_META, state)
	host.queue_redraw()


## Answer one press of `hint`: choose a target, store it, and ask for a paint.
##
## Returns the answer -- `{}` when the frame offers nothing -- so the caller can
## say so in the debug toast without asking a second question and risking a
## different answer.
##
## **Repeated presses cycle**, and that is a decision rather than a fallback. The
## retired implementation (`b04e5596:director/director_runtime.gd:725`) named the
## first clickable sprite and only ever that one; a frame with five doors then
## answers one question once, and the player who presses again -- which is what a
## player who has already seen the answer does -- is asking "what *else*". Cycling
## costs the one integer that is already stored, and it is stable across a frame
## change without storing an index into a list that may no longer exist: the
## cursor is the previously named **channel**, and a channel that is no longer a
## candidate simply falls back to the top of the list.
static func request(host, table, hit_pixels: bool) -> Dictionary:
	var state := hint_state(host)
	var answer := aim(host, table, hit_pixels, int(state["channel"]))
	if answer.is_empty():
		# **The channel is cleared as well as the deadline.** Leaving it would make
		# the next press on a frame that *does* offer something cycle from a
		# channel nobody was shown.
		state["channel"] = 0
		state["until"] = 0
		state["reason"] = ""
		host.set_meta(HINT_META, state)
		host.queue_redraw()
		return answer
	state["channel"] = int(answer["channel"])
	state["until"] = Time.get_ticks_msec() + HINT_MS
	state["rect"] = answer["rect"]
	state["point"] = answer["point"]
	state["reason"] = str(answer["reason"])
	host.set_meta(HINT_META, state)
	host.queue_redraw()
	return answer


## Every sprite on this frame a click can actually reach, topmost first.
##
## The order is `interaction.gd:channel_at`'s -- highest channel first, which is
## Director's stacking order and therefore its hit order -- so "the first one" is
## the thing nearest the player rather than the lowest-numbered channel.
##
## Two filters, and they are different questions:
##
##   1. `eligibility_reason` != "" -- §4.3, the router's own six clauses. Asked
##      through `interaction.gd` rather than restated here; a second copy is the
##      failure that file's own header is about.
##   2. `reachable_point` finds a point the router's descent resolves back to
##      this channel. Without it the list would include a sprite that is eligible
##      and wholly covered, which is a hint the player cannot act on.
##
## `_effective` first, so a sprite a script has hidden or moved is judged where it
## is rather than where the score last put it -- the same rule and the same reason
## `channel_at` gives.
static func candidates(host, table, hit_pixels: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if host == null or table == null:
		return out
	var sprites: Array = host.frame_sprites()
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = host._effective(sprites[i])
		if sprite.is_empty():
			continue
		var reason: String = Interaction.eligibility_reason(host, sprite, table)
		if reason == "":
			continue
		var rect: Rect2 = host._sprite_rect(sprite)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var at := reachable_point(host, sprite, sprites, hit_pixels, table)
		if at.x < 0.0:
			continue
		out.append({
			"channel": int(sprite["channel"]),
			"cast_lib": int(sprite["cast_lib"]),
			"cast_id": int(sprite["cast_id"]),
			"rect": rect,
			"point": at,
			"reason": reason,
		})
	return out


## The candidate after `after_channel`, or the first one. `{}` when the frame
## offers none at all.
##
## **A frame with no clickable sprite is ordinary, not a failure.** MAP's frame 0
## holds a backdrop, a panel and one off-stage sprite and none of them has a
## behaviour, because the map's regions arrive a few frames later
## (`tools/hotspots.gd` records the same case and refuses to assert against it).
## So the honest player-side answer is that the stage does not change: there is
## nothing to point at, and painting a "nothing here" badge over a movie would be
## inventing the third overlay this file exists to avoid. The words are the debug
## toast's, where they are already behind the switch and already in English --
## see `autoload/input_router.gd:answer`.
static func aim(host, table, hit_pixels: bool, after_channel: int) -> Dictionary:
	var found := candidates(host, table, hit_pixels)
	if found.is_empty():
		return {}
	var index := 0
	for i in found.size():
		if int(found[i]["channel"]) == after_channel:
			index = (i + 1) % found.size()
			break
	return found[index]


## A point inside `sprite` that the **click router's own descent** answers with
## this sprite's channel, or `(-1, -1)` when there is none.
##
## This is the whole of "the hint cannot lie". `channel_at` is the function the
## player's click goes through, called with the arguments
## `director_preview.gd:_channel_at` calls it with, so a point that passes here is
## a point that reaches this sprite -- not a point that would reach it if six
## other rules agreed, and not a point a re-derived copy of those rules thinks
## reaches it.
##
## The centre first, because it answers for almost every sprite in one descent.
## The grid after it, because two ordinary cases have no reachable centre: a
## sprite whose middle is covered by a higher eligible sprite, and a Matte-inked
## bitmap whose middle is transparent -- for which the descent correctly walks
## past to whatever is behind.
static func reachable_point(host, sprite: Dictionary, sprites: Array,
		hit_pixels: bool, table) -> Vector2:
	var channel := int(sprite["channel"])
	var rect: Rect2 = host._sprite_rect(sprite)
	if Interaction.channel_at(host, rect.get_center(), sprites, hit_pixels,
			table) == channel:
		return rect.get_center()
	for row in HINT_SAMPLES:
		for column in HINT_SAMPLES:
			var at := rect.position + Vector2(
				rect.size.x * (float(column) + 0.5) / float(HINT_SAMPLES),
				rect.size.y * (float(row) + 0.5) / float(HINT_SAMPLES))
			if Interaction.channel_at(host, at, sprites, hit_pixels, table) == channel:
				return at
	return Vector2(-1, -1)


## Draw whatever mark this sprite's turn owes, if any.
##
## Called from `artwork` for every drawn sprite of every frame, so the first line
## is the whole of the common path: no metadata means no hint has ever been asked
## for on this node and `qol/hotspot_hints` is off, which is every frame of every
## run that does not use either.
##
## `sprite` is the sprite being drawn and is used **only** by the persistent arm.
## The momentary hint draws from the stored rect and would draw the same thing on
## any call -- see the header for why that is the point rather than an accident.
static func mark(host, sprite: Dictionary) -> void:
	if host == null or not host.has_meta(HINT_META):
		return
	var state: Dictionary = host.get_meta(HINT_META)
	if bool(state["all"]):
		mark_persistent(host, sprite)
	if int(state["channel"]) <= 0:
		return
	if int(state["until"]) <= Time.get_ticks_msec():
		return
	# The blink. Integer division of the elapsed time by the half-period, so the
	# stroke is on for `HINT_BLINK_MS` and off for `HINT_BLINK_MS`, from
	# `Time.get_ticks_msec()` -- the only clock in this engine that always moves
	# (`toast.gd` says why the score's does not).
	var left := int(state["until"]) - Time.get_ticks_msec()
	if int(float(left) / float(HINT_BLINK_MS)) % 2 == 1:
		return
	outline(host, state["rect"])


## The persistent form: outline this sprite if the click router says a click can
## reach it. `qol/hotspot_hints`, and the check is `interaction.gd`'s own, so the
## toggle marks exactly the set the mouse can answer for and cannot drift from it.
##
static func mark_persistent(host, sprite: Dictionary) -> void:
	if not marks_persistently(host, sprite):
		return
	outline(host, host._sprite_rect(sprite))


## Would the persistent form outline this sprite?
##
## Split out from the draw for the reason `interaction.gd` splits
## `responds_to_mouse` from `eligibility_reason`: the harness has to be able to
## ask the question the drawing asks, and a harness that re-derived it would keep
## passing after this drifted. `tools/hint.gd` compares this answer against
## `Interaction.responds_to_mouse` sprite by sprite over a real frame, which is
## how the toggle is held to "exactly what the mouse can reach".
##
## A film loop's children arrive at `artwork` carrying their own mini-score
## channel numbers, which collide with the stage's; they are distinguishable
## because a child names its cast by name and has no `cast_lib`
## (`director/director_film_loop.gd`), and asking `responds_to_mouse` about one
## would be asking about the stage channel that happens to share its number.
static func marks_persistently(host, sprite: Dictionary) -> bool:
	if host == null or not sprite.has("cast_lib") or host._table == null:
		return false
	return Interaction.responds_to_mouse(host, sprite, host._table)


## The mark itself: an opaque stroke just outside the rect, with a dark one
## outside that.
##
## Two strokes because one is invisible on about half the artwork in this corpus.
## A single amber line disappears over sand, over a lit interior and over any
## bright title screen, and "the hint did nothing" is exactly the report this
## feature exists to stop; a dark outer stroke gives the amber one an edge to sit
## against whatever is behind it. Both are opaque, which is what makes drawing
## this once per sprite indistinguishable from drawing it once (see the header).
static func outline(host, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	Paint.rect(host, rect.grow(HINT_GROW + HINT_WIDTH), Color(0, 0, 0, 1),
		false, HINT_WIDTH)
	Paint.rect(host, rect.grow(HINT_GROW), HINT_COLOUR, false, HINT_WIDTH)
