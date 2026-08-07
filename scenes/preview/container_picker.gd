extends RefCounted
## Type a few letters, press Enter, and that movie is playing.
##
## A Director title is a few hundred containers and the only way into most of
## them is to play the game until it goes there. Piposh 2 ships 124; getting to
## the one with the bug in it meant editing `director_game.cfg`, or adding a
## `--movie` argument to a harness, or walking the game. All three are slower
## than the fix usually is.
##
## The list is `DirectorPaths.containers()`, which is the same index resolution
## itself reads, so what is offered is exactly what can be opened -- and the
## entries are root-relative rather than bare filenames, which is what tells this
## game's two `MASTER.CST` apart. Enter hands the entry straight back to
## `lingo_go_movie`, the engine's own `go to movie`, so a movie reached this way
## is entered the way the game would enter it: `prepareMovie`, `startMovie`, the
## first frame's `prepareFrame` and `enterFrame`. Nothing about the jump is a
## debug path, which is the point -- a bug that only reproduces on the real
## entry path is the kind worth reaching quickly.
##
## **While it is closed it takes no keys at all.** That is the constraint the
## whole design answers to: the preview shares a keyboard with the movie, and a
## picker that filtered on letters would be eating every letter the game wants
## for the sake of a window that is not open. So exactly one key opens it, from
## the same F-key band as every other preview binding, and the moment it is open
## it takes *everything* -- letters, the arrows, Enter, Escape -- because it is
## then the thing in front of the player. `input_router.gd` routes it before the
## movie is offered anything.

const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")

## How many matches are on screen at once. Enough to see that a filter is working
## without covering the movie it is being chosen from.
const ROWS := 12
const ROW_HEIGHT := 15.0
const PANEL := Rect2(40, 40, 560, 260)


## Open it, with the list read fresh. Fresh because a title's tree is only
## indexed once per run and this is the cheap moment to notice it is empty --
## an unconfigured game shows "no containers" rather than an empty box that
## looks like the key did nothing.
static func open(host) -> Dictionary:
	var all: Array[String] = []
	if host._paths != null:
		all = host._paths.containers()
	return {"open": true, "query": "", "index": 0, "all": all,
		"shown": all.duplicate()}


static func closed() -> Dictionary:
	return {"open": false, "query": "", "index": 0, "all": [], "shown": []}


## Every key while the picker is open, and it claims all of them. Returns the new
## state, plus `go` when the player has chosen something.
##
## Claiming everything is deliberate. A picker that let unrecognised keys through
## to the movie would have the game skipping speech and walking its character
## around behind a list the player is reading.
static func key(state: Dictionary, event: InputEventKey) -> Dictionary:
	var next := state.duplicate()
	# Any key clears the last complaint. A note that outlived the keypress it
	# answered would be read as applying to the entry now selected.
	next.erase("note")
	match event.keycode:
		KEY_ESCAPE:
			return closed()
		KEY_ENTER, KEY_KP_ENTER:
			var shown: Array = state["shown"]
			if shown.is_empty():
				return next
			var chosen := str(shown[int(state["index"])])
			# A cast is a container and belongs in the list -- half of what a
			# title ships is casts and "where does this member live" is a real
			# question -- but it has no score, so `go to movie` on one would
			# quietly do nothing and read as the picker being broken. Said, and
			# the picker stays open so the next guess costs one keypress.
			if ContainerName.CAST.has(chosen.get_extension()):
				next["note"] = "%s is a cast — no score to play" % chosen.get_file()
				return next
			next = closed()
			next["go"] = chosen
			return next
		KEY_UP:
			next["index"] = maxi(int(state["index"]) - 1, 0)
			return next
		KEY_DOWN:
			next["index"] = mini(int(state["index"]) + 1,
				maxi((state["shown"] as Array).size() - 1, 0))
			return next
		KEY_BACKSPACE:
			next["query"] = str(state["query"]).substr(0, maxi(
				str(state["query"]).length() - 1, 0))
			return _refilter(next)
	# `unicode` rather than `keycode`, so the filter reads what the player typed
	# on their own layout rather than what the key is called on a US one.
	if event.unicode >= 32 and event.unicode != 127:
		next["query"] = str(state["query"]) + String.chr(event.unicode)
		return _refilter(next)
	return next


## Substring, case-insensitively, against the **filename** -- unless the term
## carries a `/`, and then against the whole relative path.
##
## Matching the whole path always is the obvious rule and it is useless here:
## every one of this title's 124 movies lives under `PIP2DATA`, so typing "da"
## matched 83 of them on the *directory* rather than on `day1`, `dagi` and
## `dtcday2`. The directory is in the list because it is what tells this game's
## two `MASTER.CST` apart; it is not what anyone is typing at.
##
## Spaces split into terms that must all match, so "day 1" finds `day1.dir` and
## `pip2data/ day` narrows by both. The alternative, one substring, makes the
## player remember the order the directory happens to put things in.
static func _refilter(state: Dictionary) -> Dictionary:
	var terms := str(state["query"]).to_lower().split(" ", false)
	var shown: Array = []
	for entry in state["all"]:
		var text := str(entry)
		var file := text.get_file()
		var all_match := true
		for raw in terms:
			var term := str(raw)
			if not (text if term.contains("/") else file).contains(term):
				all_match = false
				break
		if all_match:
			shown.append(text)
	state["shown"] = shown
	# Back to the top on every edit. Keeping the position would leave the
	# highlight on whatever row happens to be there now, which is not the entry
	# the player was looking at and is the one Enter would open.
	state["index"] = 0
	return state


## Draw it, if it is open. Through the stage's paint for the reason
## `stage_paint.gd:draw_overlays` gives: this is the preview's own affordance and
## belongs to the stage rather than to every movie on it.
static func draw(host, state: Dictionary) -> void:
	if not bool(state.get("open", false)):
		return
	var font := ThemeDB.fallback_font
	host.draw_rect(PANEL, Color(0, 0, 0, 0.85), true)
	host.draw_rect(PANEL, Color(1, 1, 1, 0.6), false, 1.0)
	var at := PANEL.position + Vector2(10, 18)
	var shown: Array = state.get("shown", [])
	host.draw_string(font, at, "go to movie:  %s_" % str(state.get("query", "")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.6, 0.95))
	host.draw_string(font, at + Vector2(PANEL.size.x - 90, 0),
		"%d/%d" % [shown.size(), (state.get("all", []) as Array).size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
	at.y += 20
	if shown.is_empty():
		host.draw_string(font, at,
			"no containers match" if not (state["all"] as Array).is_empty()
			else "no game configured",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.6, 0.6, 0.9))
		return
	# Scrolled so the selection is always on screen: a filter that matches 90
	# entries and a selection on the 40th must not draw the first twelve.
	var index := int(state.get("index", 0))
	var first := clampi(index - ROWS / 2, 0, maxi(shown.size() - ROWS, 0))
	for row in mini(ROWS, shown.size() - first):
		var entry := str(shown[first + row])
		var line := at + Vector2(0, row * ROW_HEIGHT)
		if first + row == index:
			host.draw_rect(Rect2(line - Vector2(6, 11),
				Vector2(PANEL.size.x - 20, ROW_HEIGHT)), Color(0.2, 0.5, 1.0, 0.5), true)
		# Casts are listed and dimmed rather than hidden: they are containers, and
		# "which cast is that member in" is a real question -- but they have no
		# score, so a row that looks identical to a movie is a promise the Enter
		# key cannot keep.
		var playable := not ContainerName.CAST.has(entry.get_extension())
		var shade := 0.95 if first + row == index else 0.7
		host.draw_string(font, line, entry, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1, 1, 1, shade) if playable else Color(0.75, 0.7, 0.6, shade * 0.8))
	var footer := PANEL.position + Vector2(10, PANEL.size.y - 8)
	var note := str(state.get("note", ""))
	if note != "":
		host.draw_string(font, footer - Vector2(0, 14), note,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.7, 0.5, 0.95))
	host.draw_string(font, footer,
		"type to filter    up/down select    enter play    esc close    (%s)"
			% DebugKeys.key_name("containers"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
