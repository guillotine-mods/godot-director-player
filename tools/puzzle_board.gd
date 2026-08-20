extends SceneTree
## A member a script assigned survives the movie's own backward `go`.
##
##   godot --script tools/puzzle_board.gd -- --root piposh-dream
##
##   --root R      the corpus (default the config's)
##   --moves N     legal moves to play, each derived from the board (default 8)
##   --settle N    process frames after each step (default 8)
##   --ticks N     process frames to watch after the last move (default 600)
##
## Runs headless, which `gate.sh` requires. Nothing here needs a window: the board
## is read from the override table through `lingo_sprite_prop` and from
## `lingo_field`, and neither goes near the painter. `scene_probe` refuses headless
## because it photographs, and that is the only reason this is not that tool.
##
## ## What it guards, and why a comment could not
##
## `docs/bugs-closed.md` 120. `director_score.gd:writes_between` **deliberately
## diverges from the reference** on one case: a rewind releases the auto-puppets
## the target frame's own delta writes, where `Score::loadFrame` (`score.cpp:2211`)
## sets the copy-back mask to all-ones for the whole rebuild and says so in a
## comment — *"starting from rewind, copy back everything"*.
##
## That divergence is the kind a later session undoes on purpose, reading the
## reference, citing it, and calling it a fidelity repair. `AGENTS.md` says the
## reference documents are the specification, so the reasoning would be sound and
## the result would silently break every movie that holds a member across its own
## idle loop. The reason lives in a comment at the site; a comment is not a check.
##
## ## The movie, and why it is the right one to assert on
##
## `piposh-dream/puzzle.dir` is a 4x4 sliding-tile puzzle. Three properties make it
## a test rather than a demo:
##
## - **It keeps its whole state in `field "pazel"`** — four lines of four items,
##   `"x"` for the hole — so the field and the sixteen channels are two independent
##   readings of one truth and can be made to disagree. That is how 120 was found.
## - **It never calls `puppetSprite`.** Every member it assigns is an auto-puppet,
##   which is exactly the state the release rule governs.
## - **Its idle loop runs backwards.** `1:3` on f9 is `go("start")` to f6, for ever,
##   so a rewind happens every four frames without anything having to arrange one.
##
## ## Why the backward-jump count is a checked assertion and not a print
##
## Under the pre-120 rule the board reverted on every wrap. A run that never wrapped
## would therefore agree with the field for a reason that has nothing to do with the
## fix, and would go green with the bug fully present. So "the playhead moved
## backwards at least once" is a **check**, not a diagnostic: without it this file
## passes vacuously, which is the failure mode `film_loop_restart.gd` guards with
## its own "at least one lane took a second drop".
##
## The same argument applies to the clicks. If no click reaches a tile the board is
## the one `1:2` shuffled on entry and it will agree with the field for ever, so the
## field having *changed* under the clicks is a check too.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Where the board is dealt and the sixteen tiles are made visible. `1:2`'s frame,
## resolved by name rather than by number so a re-authored score does not silently
## move the landing.
const LANDING := "restart"

## The tiles occupy channels 1..16 in reading order, which is the same order
## `refreshpaz` walks (`gsnum` incrementing over `line y` then `item x`).
const TILES := 16


func _init() -> void:
	var args := Args.parse()
	var settle := Args.number(args, "settle", 8)
	var h := Harness.new()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", "puzzle.dir", null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return

	var landing := _marker(preview, LANDING)
	if landing < 0:
		print("no marker '%s' in %s" % [LANDING, str(preview.call("movie_name"))])
		quit(1)
		return
	# Entered, not merely indexed: `1:2` is an `exitFrame`, and a frame nobody
	# stood on has dealt no board. Landing on `start` f6 instead leaves `ifmove`
	# unset and every tile handler falls through its own gate, which reads as a
	# dead game rather than as a skipped init.
	preview.set("_index", landing)
	# **The board is dealt when the playhead *leaves* f5, not when it arrives.**
	# `1:2` is an `exitFrame` handler, so a fixed settle can read the control while
	# `field "pazel"` still holds the member's authored text and the channels still
	# hold the score's own `paz<index>`. Those two disagree, and the harness reports
	# a red for its own impatience — measured, not hypothetical: this file did
	# exactly that, with every click landing on frame 5.
	var waited := 0
	while int(preview.call("current_frame")) == landing and waited < 240:
		await process_frame
		waited += 1
	for i in settle:
		await process_frame

	var dealt := str(preview.call("lingo_field", "pazel", ""))
	var before: Array[String] = []
	var control_ok := _agrees(preview, dealt, before)

	var wraps := 0
	var last := int(preview.call("current_frame"))
	var clicks := 0
	# **Each click is derived from the board, not counted off from ch1.** A tile
	# only moves when it is next to the hole, and `1:2` shuffles on entry, so a
	# fixed channel list moves the board on some shuffles and not others — this
	# file first asserted `ch1..ch8` and drew a red on a run whose hole came up in
	# the bottom row, which is a flake of exactly the kind entry 119 documents.
	# Clicking the hole's own neighbour is a legal move on every shuffle.
	# `avoid` is the cell the hole just vacated. Without it the first neighbour is
	# always the tile that moved last, so each click undoes the one before it and
	# an even number of moves returns the board to where it started — which reads
	# as "the clicks never arrived". Measured: eight moves, field byte-identical.
	var avoid := -1
	var moved := 0
	for move in Args.number(args, "moves", 8):
		var was := str(preview.call("lingo_field", "pazel", ""))
		var channel := _neighbour_of_hole(was, avoid)
		if channel < 0:
			break
		var at: Variant = _centre(preview, channel)
		if at == null:
			break
		avoid = _hole_cell(was)
		preview.call("route_press", at)
		preview.call("route_release", at)
		clicks += 1
		for i in settle:
			await process_frame
			var here := int(preview.call("current_frame"))
			if here < last:
				wraps += 1
			last = here
		# Per click, not start-against-end: a sequence of legal moves can return
		# the board to its opening position, and the question here is only whether
		# each click reached a tile handler.
		if str(preview.call("lingo_field", "pazel", "")) != was:
			moved += 1

	# Long enough that the movie's own loop is certain to have wrapped: the clock
	# reads 8 fps here and the span is four frames, so a handful of process frames
	# buys nothing. The wrap is the whole mechanism under test.
	for i in Args.number(args, "ticks", 600):
		await process_frame
		var here := int(preview.call("current_frame"))
		if here < last:
			wraps += 1
		last = here

	var played := str(preview.call("lingo_field", "pazel", ""))
	var disagreed: Array[String] = []
	var agrees := _agrees(preview, played, disagreed)

	h.begin("a script's member survives the movie's own backward go")
	h.check("the board was dealt into `field \"pazel\"`",
		_grid(dealt).size() == 4, "%d line(s)" % _grid(dealt).size())
	h.check("the stage matched the field before any click", control_ok,
		"" if control_ok else "%d of %d channel(s) disagree before any input"
			% [before.size(), TILES])
	for line in before.slice(0, 8):
		print("     %s" % line)
	h.check("every click reached a tile and moved the board", clicks > 0 and moved == clicks,
		"%d of %d click(s) changed the field" % [moved, clicks])
	# The load-bearing one. Without a wrap the run says nothing about the release.
	h.check("the playhead ran its backward idle loop", wraps > 0,
		"%d backward jump(s)" % wraps)
	h.check("every tile still matches the field after the wraps", agrees,
		"" if agrees else "%d of %d channel(s) disagree" % [disagreed.size(), TILES])
	for line in disagreed.slice(0, 8):
		print("     %s" % line)
	h.complete("a script's member survives the movie's own backward go")

	print("")
	print("landing    : %s f%d" % [LANDING, landing])
	print("field      : %s" % played.replace("\n", " / "))
	print("clicks     : %d, %d moved the board, backward jumps: %d" % [clicks, moved, wraps])
	quit(h.finish("an auto-puppet outlives a rewind the movie itself drives"))


## `field "pazel"` as four lines of four items.
func _grid(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n", false):
		var items := str(line).split(",", false)
		if items.size() == 4:
			out.append(items)
	return out


## Does every channel hold the member the field says it should?
##
## The hole is part of the assertion rather than an exemption. `visible` is channel
## state and no release path touches it, so it went on being correct all through
## 120 — a check that skipped the hole would have been the same shape as the bug's
## own half-and-half and would have looked healthy while fifteen tiles were wrong.
##
## **Asked as "is it drawn", not as `the visible of sprite`.** A hidden tile leaves
## `frame_sprites()`/`_effective` altogether — the runs behind 120 report the hole
## channel as *absent* from the table rather than as present-and-invisible — and a
## `lingo_sprite_prop(ch, "visible")` on a channel the frame does not offer is the
## unrouted read that same file has a comment about, falling through to
## `EMPTY_CHANNEL`'s default instead of to the override. So the drawn set is both
## what was measured and the reading that cannot answer from a default.
func _agrees(preview: Node, text: String, out: Array[String]) -> bool:
	var grid := _grid(text)
	if grid.size() != 4:
		return false
	var table = preview.get("_table")
	var drawn := _drawn_members(preview)
	var right := true
	var channel := 0
	for y in 4:
		for x in 4:
			channel += 1
			var item := str((grid[y] as PackedStringArray)[x]).strip_edges()
			if item == "x":
				if drawn.has(channel):
					out.append("ch%d is the hole and is still drawn (member %d)" % [
						channel, int(drawn[channel])])
					right = false
				continue
			if not drawn.has(channel):
				out.append("ch%d is not drawn, field says paz%s" % [channel, item])
				right = false
				continue
			var member := int(drawn[channel])
			var name := str((table.get_member(1, member) as Dictionary).get("name", ""))
			if name.to_lower() != ("paz%s" % item).to_lower():
				out.append("ch%d holds %s (member %d), field says paz%s" % [
					channel, name if not name.is_empty() else "<unnamed>", member, item])
				right = false
	return right


## The channel of a tile sitting next to the hole, so the click is a legal move on
## any shuffle. `-1` when the field will not parse.
##
## Channel numbering is the grid in reading order — `refreshpaz` walks `gsnum` over
## `line y` then `item x` — so the channel at a cell adjacent to the `"x"` cell is
## displaying the tile whose own handler will find a neighbouring hole and swap.
## `avoid` is a channel not to pick — the cell the hole came from. A hole has two
## neighbours at worst, so skipping one always leaves a legal move.
func _neighbour_of_hole(text: String, avoid: int = -1) -> int:
	var cell := _hole_cell(text)
	if cell < 0:
		return -1
	var x := (cell - 1) % 4
	var y := (cell - 1) / 4
	var steps: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var fallback := -1
	for step in steps:
		var nx: int = x + step.x
		var ny: int = y + step.y
		if nx < 0 or nx > 3 or ny < 0 or ny > 3:
			continue
		var channel := ny * 4 + nx + 1
		if channel != avoid:
			return channel
		fallback = channel
	return fallback


## Which channel's cell holds the `"x"`, 1-based in reading order. `-1` if unparsed.
func _hole_cell(text: String) -> int:
	var grid := _grid(text)
	if grid.size() != 4:
		return -1
	for y in 4:
		for x in 4:
			if str((grid[y] as PackedStringArray)[x]).strip_edges() == "x":
				return y * 4 + x + 1
	return -1


## Channel -> the member it is actually drawing, for the channels the frame offers.
func _drawn_members(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		var live: Dictionary = preview.call("_effective", sprite)
		if live.is_empty():
			continue
		out[int(sprite["channel"])] = int(live.get("cast_id", sprite.get("cast_id", 0)))
	return out


## The centre of what a channel is drawing now, the same derivation
## `scene_probe.gd:_point` uses for `chN`.
func _centre(preview: Node, channel: int) -> Variant:
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		if int(sprite["channel"]) != channel:
			continue
		if (preview.call("_effective", sprite) as Dictionary).is_empty():
			continue
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		return rect.position + rect.size * 0.5
	return null


func _marker(preview: Node, name: String) -> int:
	var labels = preview.get("_labels")
	if labels == null:
		return -1
	for m in labels.markers:
		if str((m as Dictionary)["name"]).to_lower() == name.to_lower():
			return int((m as Dictionary)["frame"])
	return -1
