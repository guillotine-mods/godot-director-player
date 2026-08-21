extends SceneTree
## A hex board's own state field and the members its channels draw say the same
## thing, before input, after a select, and after a move.
##
##   godot --headless --script tools/hex_board.gd -- --root piposh-dream
##
##   --settle N    process frames after each step (default 12)
##   --wraps N     ceiling on the wait for the movie's backward jump (default 900)
##   --ticks N     process frames to watch after the move (default 120)
##
## Runs headless. Nothing here paints: one reading comes from the movie's own
## `valueOf` handler through the interpreter and the other from the override
## table through `frame_sprites`/`_effective`, and neither goes near the painter.
##
## ## What it guards
##
## `docs/bugs-closed.md` 120 was found by reading a movie's own state field
## against the members its channels were drawing — two readings of one truth,
## made to disagree. The minigame sweep of 2026-08-14 could not have found it:
## its four criteria are about *presence* (the init runs, elements reach the
## painter, input changes something, an outcome is reachable) and 120's puzzle
## satisfied three of them while being unplayable on screen.
##
## Five of that sweep's `YES` rows carried the same exposure unchecked.
## `piposh-dream/hex2.dir` is the one of the five whose pair is the same shape as
## 120's, so it is the one that can be gated at 120's strength:
##
## - **The board is a field.** `field "Field"` holds nine lines of comma items,
##   `0` empty, `1` the player's piece, `2` the opponent's, and the movie's own
##   `valueOf <channel>` handler is the authored channel-to-cell map. Reading it
##   through the interpreter rather than transcribing sixty-one `case` arms means
##   a re-authored board cannot silently desynchronise the harness — and the map
##   is not the identity: `valueOf(44)` is `item 8 of line 3`, not line 6, which
##   is the author's own off-by-one and would be invisible to a transcription
##   that assumed a rectangle.
## - **The channels are the other reading.** `clearScreen` re-dresses every cell
##   *from the field* — `1` to member 3, `0` to 56, `2` to 2 — so the field and
##   the drawn members are two stores that a release, a revert or a lost override
##   can pull apart. That is exactly what 120 was.
## - **The board is dealt deterministically.** Six literal `put`s in the init
##   (`1:99`, an `enterFrame` at f209) seed cells 2, 36, 58 for the player and 6,
##   28, 62 for the opponent over an all-zero board. There is no shuffle, so the
##   flake that made `puzzle_board` red on its first version — a fixed click list
##   against a random board — cannot happen here, and the click list can be
##   derived once and trusted.
##
## **This is not 120's mechanism a second time.** `1:99` calls `puppetSprite(i, 1)`
## on every cell, so these are explicit puppets and the auto-puppet release rule
## 120 fixed never governed them. What is shared is the *reading pair*, over a
## different path to the same picture: the strongest available answer to "is the
## board on screen the board the movie thinks it has".
##
## ## Why the wrap, the light and the move are checks and not prints
##
## Three ways this file could pass while asserting nothing, all of them measured
## rather than imagined:
##
## - **Without a backward jump** the run says nothing about anything that
##   survives one. The board loop is f213..f228 with `1:61` jumping back to
##   `marker(0)` — f213, because f228's covering marker is `hhh` and not `start`
##   — so a wrap arrives by itself and its absence means the movie never entered
##   its loop.
## - **Without a lit cell** the first click never reached `CastScript 3`, and the
##   two readings would go on agreeing because nothing asked them to change. The
##   light is also the only observation of `the currentSpriteNum` resolving for a
##   *cast* script, which is what the whole game is steered by.
## - **Without the field changing** the second click never reached
##   `CastScript 103`, and an unchanged board agrees with an unchanged field for
##   a reason that has nothing to do with the port.
##
## **The wrap is before the clicks and not after, and that is a real limit.** The
## move ends in `go("ishspk")`, so the playhead leaves the board loop forwards and
## does not come back inside this run. So what is asserted is that the *dealt*
## board survives a rewind and that the *moved* board agrees at the instant the
## move was made -- not that a member a click assigned survives one, which is the
## ordering `puzzle_board` has and the reason that file and this one are both in
## `ALL`.
##
## ## The cells are the ones the movie draws, not 2..62
##
## Five of the sixty-one channels `valueOf` maps are not drawn at the landing, and
## the reason is the container: **the score carries no record for channels 16, 30,
## 32, 34 and 48 on that frame at all** — asked of `frame_sprites` before
## `_effective`, so this is "the movie places no sprite" and not "a member failed
## to resolve". So the cell set is derived from what the frame offers rather than
## from the range. Asserting the range would fail on the container's own
## authoring, which `AGENTS.md` says a harness may not do; the *count* is a check
## instead, so a board that collapsed to nothing cannot pass for having no
## disagreements.
##
## The movie's own endgame scan (`1:61`) exempts **4**, 30, 32, 34 and 48 — four of
## the same five, plus one the score does place and minus one it does not. That is
## the author's inconsistency rather than a difference this port makes, and it is
## recorded here only so the next reader does not take the two lists for one list.
##
## Title-agnostic driving, title-specific scenario, the same split every harness
## here uses: `harness.gd` and `args.gd` do not know which game this is.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Where the board is dealt. `1:99` is an `enterFrame`, so the playhead has to
## *arrive* here rather than be placed here, which is why the landing is two
## frames earlier and the movie walks in.
const LANDING := "start"

## The channels `valueOf` maps, as a range. Which of them are cells is decided by
## the frame, not by this pair.
const FIRST_CELL := 2
const LAST_CELL := 62

## `clearScreen`'s own mapping, cell value to the member it dresses the cell with.
const DRESSES := {0: 56, 1: 3, 2: 2}

## What a cell draws while it is offered as a destination: `lightUp1` puts 103 on
## a step and `lightUp2` puts 105 on a jump. Both are legal on a `0` cell only,
## and both are cleared by the next `clearScreen`.
const LIT := [103, 105]


func _init() -> void:
	var args := Args.parse()
	var settle := Args.number(args, "settle", 12)
	var h := Harness.new()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", "hex2.dir", null)
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
	# Two frames short, and left to walk in: `1:99` is an `enterFrame`, and a
	# playhead *placed* on f209 has not arrived there. Landing on it directly
	# leaves the board undealt and every cell reading 0 against the score's own
	# members, which is a red for the harness's own impatience rather than for
	# the port -- the same trap `puzzle_board` records for its `exitFrame` init.
	preview.set("_index", landing - 2)
	var waited := 0
	while int(preview.call("current_frame")) < landing and waited < 3000:
		await process_frame
		waited += 1
	for i in settle:
		await process_frame

	var interp: Object = preview.get("_interpreter")
	# The movie's own loop, before anything is asserted. Under 120's rule a board
	# held on its channels did not survive a rewind, so a run that never wrapped
	# would agree for the wrong reason.
	var wraps := 0
	var watched := 0
	var last := int(preview.call("current_frame"))
	for i in Args.number(args, "wraps", 900):
		await process_frame
		watched += 1
		var here := int(preview.call("current_frame"))
		if here < last:
			wraps += 1
		last = here
		if wraps > 0:
			break
	for i in settle:
		await process_frame

	var cells := _cells(preview)
	var seeded := _values(preview, interp, cells)
	var control: Array[String] = []
	var control_ok := _agrees(preview, interp, cells, control, true)

	# The player's own pieces are the `1`s, and the click that selects one is the
	# only way into `CastScript 3`. Derived from the field rather than named, so a
	# re-seeded board still finds a piece.
	var mine := _with_value(seeded, 1)
	var lit_after := 0
	var unlit: Array[String] = []
	var unlit_ok := false
	if not mine.is_empty():
		var at: Variant = _centre(preview, int(mine[0]))
		if at != null:
			preview.call("route_press", at)
			preview.call("route_release", at)
			for i in settle:
				await process_frame
		lit_after = _lit(preview, cells).size()
		# The lit cells are exempt and only the lit ones: a `0` cell offered as a
		# destination legitimately draws 103 or 105 rather than 56, and every
		# other cell must still say what the field says.
		unlit_ok = _agrees(preview, interp, cells, unlit, false)

	var before_move := str(preview.call("lingo_field", "Field", ""))
	var lit_cells := _lit(preview, cells)
	var moved := false
	if not lit_cells.is_empty():
		var at2: Variant = _centre(preview, int(lit_cells[0]))
		if at2 != null:
			preview.call("route_press", at2)
			preview.call("route_release", at2)
			for i in Args.number(args, "ticks", 120):
				await process_frame
		moved = str(preview.call("lingo_field", "Field", "")) != before_move

	var after := _cells(preview)
	var played: Array[String] = []
	var played_ok := _agrees(preview, interp, after, played, true)

	h.begin("a hex board's field and its channels draw the same board")
	h.check("the movie dealt a board into its own state field",
		seeded.size() == cells.size() and _with_value(seeded, 1).size() > 0
			and _with_value(seeded, 2).size() > 0,
		"%d cell(s), %d mine, %d theirs" % [seeded.size(),
			_with_value(seeded, 1).size(), _with_value(seeded, 2).size()])
	h.check("the playhead ran its backward board loop", wraps > 0,
		"%d backward jump(s) in %d frame(s)" % [wraps, watched])
	h.check("every cell matched the field before any click", control_ok,
		"" if control_ok else "%d of %d cell(s) disagree" % [control.size(), cells.size()])
	for line in control.slice(0, 8):
		print("     %s" % line)
	h.check("selecting a piece lit its destinations", lit_after > 0,
		"%d cell(s) lit" % lit_after)
	h.check("every unlit cell still matched the field while lit", unlit_ok,
		"" if unlit_ok else "%d of %d cell(s) disagree" % [unlit.size(), cells.size()])
	for line in unlit.slice(0, 8):
		print("     %s" % line)
	h.check("the move changed the board", moved,
		"field %s" % ("changed" if moved else "byte-identical"))
	h.check("every cell matched the field after the move", played_ok,
		"" if played_ok else "%d of %d cell(s) disagree" % [played.size(), after.size()])
	for line in played.slice(0, 8):
		print("     %s" % line)
	h.complete("a hex board's field and its channels draw the same board")

	print("")
	print("landing    : %s f%d, reached in %d frame(s)" % [LANDING, landing, waited])
	print("cells      : %d of %d channel(s) %d..%d are drawn" % [
		cells.size(), LAST_CELL - FIRST_CELL + 1, FIRST_CELL, LAST_CELL])
	print("field      : %s" % str(preview.call("lingo_field", "Field", ""))
		.replace("\r", "\n").replace("\n", " / "))
	print("wraps      : %d, lit after select: %d" % [wraps, lit_after])
	quit(h.finish("a board's own field and its drawn members agree"))


## The channels in the mapped range that the frame is actually drawing.
func _cells(preview: Node) -> Array[int]:
	var out: Array[int] = []
	var drawn := _drawn(preview)
	for channel in drawn:
		if int(channel) >= FIRST_CELL and int(channel) <= LAST_CELL:
			out.append(int(channel))
	out.sort()
	return out


## Cell -> the value the movie's own `valueOf` reads out of `field "Field"`.
##
## The movie's handler rather than a transcription of it: sixty-one `case` arms
## copied into this file would be a second authority on the same question, and
## the one place they differ is the one that matters -- `valueOf(44)` reads
## `item 8 of line 3`, which no assumed geometry produces.
func _values(preview: Node, interp: Object, cells: Array[int]) -> Dictionary:
	var out: Dictionary = {}
	for channel in cells:
		var value: Variant = interp.call("call_handler", "valueOf", [channel])
		if value == null:
			continue
		out[channel] = int(value)
	return out


func _with_value(values: Dictionary, want: int) -> Array:
	var out: Array = []
	for channel in values:
		if int(values[channel]) == want:
			out.append(int(channel))
	out.sort()
	return out


## The cells currently offered as a destination.
func _lit(preview: Node, cells: Array[int]) -> Array:
	var drawn := _drawn(preview)
	var out: Array = []
	for channel in cells:
		if LIT.has(int(drawn.get(channel, -1))):
			out.append(channel)
	return out


## Does every cell draw the member the field says it should?
##
## `strict` false exempts a cell that the movie has lit, and nothing else: a lit
## cell is a `0` cell showing 103 or 105, so the exemption cannot hide a piece
## that vanished or one that appeared.
func _agrees(preview: Node, interp: Object, cells: Array[int], out: Array[String],
		strict: bool) -> bool:
	var drawn := _drawn(preview)
	var right := true
	for channel in cells:
		var value: Variant = interp.call("call_handler", "valueOf", [channel])
		if value == null:
			out.append("ch%d: the movie's own valueOf answered nothing" % channel)
			right = false
			continue
		var member := int(drawn.get(channel, -1))
		if not strict and int(value) == 0 and LIT.has(member):
			continue
		var want := int(DRESSES.get(int(value), -1))
		if member != want:
			out.append("ch%d holds member %d, field says %d so it should hold %d" % [
				channel, member, int(value), want])
			right = false
	return right


## Channel -> the member it is drawing, for the channels the frame offers.
func _drawn(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		var live: Dictionary = preview.call("_effective", sprite)
		if live.is_empty():
			continue
		out[int(sprite["channel"])] = int(live.get("cast_id", sprite.get("cast_id", 0)))
	return out


## The centre of what a channel is drawing now, which is where a click on that
## cell goes. The same derivation `scene_probe.gd:_point` uses for `chN`.
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
	var labels: Object = preview.get("_labels")
	if labels == null:
		return -1
	for m in labels.markers:
		if str((m as Dictionary)["name"]).to_lower() == name.to_lower():
			return int((m as Dictionary)["frame"])
	return -1
