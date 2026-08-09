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

const Ink := preload("res://director/director_ink.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")


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
	# The button arm is an **approximation and unverified**. The reference hilites
	# a `MacButton` *widget*, which is a Mac control drawing itself inverted, not
	# `Ink.invert` over authored artwork; this port draws no button widget, and
	# there is no button member in any of the three corpora to check it against
	# (`interaction.gd:latch_release` measures 0 of 51,350). Inverting the picture
	# is the nearest thing the port has and is what the auto-hilite path below
	# already does.
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
