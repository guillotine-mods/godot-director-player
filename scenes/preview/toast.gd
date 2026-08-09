extends RefCounted
## A line of text that says something happened, and then goes away.
##
## Drawn through the stage's paint rather than as a `Control`, for the reason
## `stage_paint.gd:draw_overlays` gives about the SKIP button and the HUD: these
## are the *preview's* affordances, not any movie's, so they are drawn once by
## the stage instead of by every movie on it. A Control node would also have to
## be positioned in the letterbox transform that the stage already applies to
## everything it draws, and would sit outside the clip the stage arms each paint.
##
## Self-dismissing by deadline rather than by a `Timer` or a tween. The score's
## clock is not Godot's -- it pauses, it steps, it holds on transitions -- and a
## toast that lived on the score's time would freeze on screen for as long as the
## player left the preview paused. `Time.get_ticks_msec` is the only clock here
## that always moves.

## How long a message stays up. Long enough to read a filename, short enough that
## it is gone before it covers anything the player is looking at.
const SECONDS := 2.5
const Paint := preload("res://director/director_paint.gd")

## Where it sits: bottom-left, one line above the HUD, so the two do not overlap
## at any stage size.
const MARGIN := Vector2(8, 26)


## Show `text` until `SECONDS` from now. Returns the deadline for the node to
## hold -- the state stays on the node, per `preview/README.md`, because that is
## where `tools/` can see it.
static func show(text: String) -> Array:
	return [text, Time.get_ticks_msec() + int(SECONDS * 1000.0)]


static func showing(until: int) -> bool:
	return until > Time.get_ticks_msec()


## Paint it, if it is still due. Returns true while it is, which the caller uses
## to ask for the next frame: a paused preview does not repaint on its own, and a
## toast that needs a repaint to disappear would stay up for ever.
static func draw(host, text: String, until: int, stage: Vector2i) -> bool:
	if text == "" or not showing(until):
		return false
	var font := ThemeDB.fallback_font
	var size := 12
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	# Fades out over its last half-second rather than vanishing, so a toast that
	# is on its way out is not mistaken for one that never appeared.
	var left := float(until - Time.get_ticks_msec()) / 1000.0
	var alpha := clampf(left / 0.5, 0.0, 1.0)
	var at := Vector2(MARGIN.x, float(stage.y) - MARGIN.y)
	var box := Rect2(at - Vector2(5, 13), Vector2(width + 10, 18))
	Paint.rect(host, box, Color(0, 0, 0, 0.7 * alpha), true)
	Paint.rect(host, box, Color(1, 1, 1, 0.5 * alpha), false, 1.0)
	Paint.text(host, font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(1, 1, 1, 0.95 * alpha))
	return true
