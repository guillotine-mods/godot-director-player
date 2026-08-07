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
