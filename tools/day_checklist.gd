extends SceneTree
## One item of a seven-item checklist, driven the way the game drives it: the hub
## picks the game, the game writes the item, and the hub reads it back.
##
##   godot --headless --path . --script tools/day_checklist.gd -- --root piposh-dream
##
##   --root R        the corpus (default the config's)
##   --settle N      process frames after each movie change (default 4)
##   --arrive N      ceiling, in process frames, on one movie change (default 900)
##   --step N        ceiling, in process frames, on a movie crossing its own f0 (default 900)
##   --cold          the negative control. Skips the dinner and the hub click and
##                   enters the game directly, which is the probe this file exists
##                   to avoid. **It is expected to go red**, and it is not in
##                   `gate.sh`. See the control section below.
##   --verbose       print all fourteen slot channels, not just the disagreeing ones
##
## Runs headless, which `gate.sh` requires: every reading here is a Lingo global or
## the drawn set, and none of them goes near a framebuffer.
##
## ## The mechanism
##
## `piposh-dream`'s hub `mainmenu.dir` is a seven-item to-do list for the day. The
## list is one Lingo global, `advancekeeper`, holding seven comma-separated items,
## and four separate pieces of the title touch it:
##
## - A **dinner** opens the day. `dinner2.dir` `1:298` on f4413 is
##   `globalday = 2` / `advancekeeper = "hez,ish,hat,poz,krp,mus,psy"` /
##   `go(1, the moviePath & "mainmenu.dxr")`.
## - The hub's **slots**, `1:9` and `1:24`..`1:29` on ch4..ch10 of f1..f27, each
##   compose their destination from the global: ch5 is `1:24`, whose whole body is
##   `go(1, "hex" & globalday & ".dxr")`.
## - Seven **games** each write one item. `hex2.dir` `1:138` is
##   `put "done" into item 2 of advancekeeper` followed by
##   `go(1, the moviePath & "mainmenu.dxr")`, and its six siblings are the same
##   shape with a different index. Every one of them is an `on exitFrame`.
## - The hub's **init**, `1:13` on f0, reads the list and dresses the stage from it:
##   `sprite(3 + i).visible = 0` and `sprite(12 + i).visible = 1` for each item that
##   reads `"done"`. It is the only writer of those fourteen channels.
##
## Between them they are a state machine that spans three movie changes, and **not
## one of its transitions had ever been observed running.** Every claim about it came
## from reading container text. That is the gap this file closes for one item.
##
## ## Why the entry has to be warm, and what cold actually proves
##
## The obvious probe is to open `hex2.dir` and put the playhead on f344. `bugs.md`
## 121 predicted that would be a **false negative**: `advancekeeper` would be VOID,
## a VOID global would abort the handler rather than read as empty, and the run would
## report the checklist broken about a game that is fine. The same shape had been
## measured elsewhere: `hatul2.dir --play "stage8water@f982"` lands past `newgame` at
## f179, `hatmen` is never assigned, and a script takes its `go("gameover")` branch
## (`f204444d`).
##
## **`--cold` was run, and that prediction is wrong in this port.** Measured: with
## `advancekeeper` VOID, `put "done" into item 2 of advancekeeper` does not abort. The
## global comes out **`",done"`** — two items where there were seven — and the `go` on
## the next line fires normally. The hub then reads `item 2 of ",done"`, which *is*
## `"done"`, hides ch5 and shows ch14. The reading that explains it is
## `_chunk_source_text`, which is `LingoValue.to_str(_eval(node))`
## (`lingo_interpreter.gd`), so a VOID source stringifies to `""` rather than raising.
## The `",done"` is the measurement; that line is the candidate mechanism and was not
## separately tested.
##
## So a cold probe does not report the checklist broken. **It reports it working**,
## on a global that no longer holds items 1 or 3..7 and from which the day can never
## advance, which is precisely the failure entry 121 was raised about. That is worse
## than the false negative it expected, and it is the reason the entry conditions
## below are checks and not setup: the two crux readings — item 2 says `done`, `1:13`
## hides slot 2 — pass identically on both paths and **cannot tell warm from cold**.
## What tells them apart is `globalday`, the click, and the six items nobody wrote.
##
## Whether `put` into a chunk of a VOID variable should abort in the first place is
## an engine question and not this file's: the reference's answer is not established
## here, so the behaviour is recorded, asserted around, and left alone.
##
## So the globals arrive by the authored path and nothing else: `dinner2.dir` placed
## at f4412, which is one frame short of `1:298`, so the assignment is the *movie's*
## own step out of the frame rather than something this file arranged. Measured, it
## then walks to the hub in **2 process frames**.
##
## **And the game is chosen by the hub, not by this file.** That is the half a
## `lingo_go_movie("hex2.dir")` would throw away, and it is half of what was
## unmeasured: `1:24` composes `"hex" & globalday & ".dxr"`, so a run that named the
## movie itself would never learn whether `globalday` survived the trip either. The
## string `hex2` appears in this file only as an *expectation*. The engine derives it
## from a global written in a different movie, and the check is that the two agree.
##
## The one thing this file writes into the movie is a mouse press on ch5's own rect,
## read off the live frame. `advancekeeper` is never written from here: that would
## make the assertion the tautology of reading back a value this file put there.
##
## ## The three steps, and how a red says which one failed
##
## `1:138` writes the item and leaves the movie **in the same handler**, and that is
## what makes the three steps separable from outside:
##
## - the movie changes back to `mainmenu.dir` — the `go` fired, so the `put` on the
##   line above it executed. The **write ran**.
## - `item 2` reads `done` on the far side of that change. The value **survived
##   `go movie`**, which is the transition nothing in `gate.sh`'s `ALL` covers:
##   `new_game_reset` is about Director fields and about resetting them, and
##   `go_movie_arg` is about which argument of `go` names the movie.
## - ch5 is hidden and ch14 is drawn on the next hub visit. The **hub read it**.
##
## A run that never left the hub therefore cannot pass by accident: the movie-change
## check is the first of the three and it names the click point and the frame it was
## pressed on when it fails.
##
## ## `--cold`, and why a harness like this needs one
##
## Every check below would also pass if the warm entry were doing nothing and the
## globals were arriving from somewhere else, and `porting-fidelity-verification`'s
## worked example is a check whose two readings could not disagree on the data it was
## given. So the opposite entry is a flag rather than an argument in a comment:
## `--cold` skips the dinner and the hub click, opens the game with
## `lingo_go_movie` the way a naive probe would, and runs the same assertions.
##
## `--cold` is **expected to fail**, it is deliberately not in `gate.sh`, and the run
## prints a banner saying so. Measured, 15 checks warm and 12 cold:
##
##     --root piposh-dream           PASS  15 checks, 0 failed
##     --root piposh-dream --cold    FAIL  12 checks, 5 failed
##
## and the five it fails are `globalday`, the reset, the click, the composed movie
## name and the six untouched items. It **passes** "item 2 reads `done`" and "`1:13`
## hides slot 2 and shows its done marker", which is the whole argument for the five
## it fails being assertions rather than scaffolding. A version of this file that
## checked only the write and the hide would go green on the cold path, and the run
## that closed `bugs.md` 121 would have been the vacuous kind.
##
## ## Reaching the writing frame is placement, not play
##
## f344 has never been reached by playing, and neither has any of its six siblings:
## the day-2 sweep spent 20,000 fast-forward frames and 6,664 synthetic presses on
## `MAZE2` and got as far as the `loose` marker at f308. Whether synthetic input can
## win a hex puzzle is not the engine's business and is not what this asserts.
## **Whether the checklist cycle works is**, and that question is answerable by
## putting the playhead on the frame the movie itself would have reached — after the
## movie has run its own init, which is the difference between this and a cold entry.
## The init is waited for rather than counted: `hex2.dir` has to cross its own f0
## before the landing, and the run says so as a check.
##
## Placement is four fields and not one. `_index` alone is what `puzzle_board.gd`
## writes, and it is enough there because that movie's landing arms no hold; f344 is
## in the middle of a minigame and the frame the playhead is abandoned on may have
## armed a tempo wait or a sound gate — `hex2.dir`'s intro sits on a `soundBusy` poll
## at f38 — and the abandoned hold would then keep the playhead where it was put for
## the rest of the run. So the clock is reset, the owed `enterFrame` is dropped and
## the `exitFrame` latch is lowered: the same four the debug `restart` key writes
## (`input_router.gd`), plus the latch, which that key does not need because frame 0
## is always a fresh entry.
##
## ## Scope, said out loud
##
## **One item of the seven.** `hex2` is the case because item 2 is the only one with
## two writing frames, f344 and f688, so the derivation had the most to be wrong
## about there. The other six are printed as a table and **asserted about by
## nothing** — same call `video_fallback` and `sprite_lifetime`'s fourth case make.
## Two of them would need more than a landing: `hatul2.dir` `1:148` writes item 3
## only when `value(the text of field "score")` is at least 500, and `plane2.dir`
## `1:181` only when field `kereshcnt` exceeds 8 *and* field `scorecnt` exceeds 599,
## with no else at all. Forcing those fields is a second harness, not a flag here,
## because a run that only ever forced them past the threshold could not tell "the
## engine ran the movie's gate" from "the engine ran the `put` ungated".
##
## The **day advance** is out of scope for the same reason: `1:15` on f27 needs all
## seven items reading `done`, so asserting it means driving all seven writes, and
## six of them failing for six unrelated reasons would produce a red that says
## nothing about the mechanism. `1:15`'s `globalday = 2` arm is read here and
## reported, not asserted.
##
## ## What is printed rather than asserted
##
## `1:13`'s reset loop is `repeat with i = 1 to 30`, so of the three channel banks it
## writes, only two are re-shown on every visit: ch4..ch10, the seven characters, and
## ch13..ch19, the seven done-markers. The third, ch27..ch33, is reset for items 1..4
## and **write-once for items 5..7**, because the author's loop stops at 30. That is
## bad authoring in a shipped title and not something this port can fix, so those
## seven channels are printed and not asserted — the same call `palette_corpus.gd`
## makes about the 167 bitmaps that name a non-palette.
##
## `1:14` on f1..f26 is the hub's rollover handler and it reads the same state a
## second way, as `the visible of sprite 13`..`19` rather than as the drawn set. Its
## reading is printed beside this file's own. The two disagreeing would be an engine
## finding rather than a harness fault, and neither is asserted against the other.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## The authored way into day 2. Landed one frame short of `1:298` on f4413 so the
## placement is a frame entry and the assignment is the movie's own step out of it.
const ENTRY_MOVIE := "dinner2.dir"
const ENTRY_FRAME := 4412
## What `1:298` and `STRTGAME.dir` `1:258` put there. Seven items, none `"done"`.
const FRESH := "hez,ish,hat,poz,krp,mus,psy"

const HUB := "mainmenu.dir"
## The hub's idle span, from `1:24`'s own sprite span. ch5 is not in the frame
## outside it, so a press landing on f0 would route nowhere and time out downstream.
const IDLE_FIRST := 1
const IDLE_LAST := 27

## The one item driven. `channel` is the hub slot whose behaviour composes the
## destination; `stem` and `movie` are what the *engine* is expected to derive from
## `globalday`, never what this file hands it.
const ITEM := 2
const SLOT_CHANNEL := 5
const EXPECT_STEM := "hex"
const EXPECT_MOVIE := "hex2.dir"
const WRITE_FRAME := 344

## `1:13`'s three banks, as `channel = base + item`. The first two are asserted; the
## third is printed, for the `1 to 30` reason in the header.
const SHOWN_WHEN_OPEN := 3
const SHOWN_WHEN_DONE := 12
const BADGE := 26
const ITEM_COUNT := 7

## Derived by `tools/script_placement.gd --match advancekeeper --root piposh-dream`
## and driven by nothing. Printed so the file records which six it does not cover.
const NOT_DRIVEN: Array = [
	{"item": 1, "movie": "show.dir", "frame": 2377, "script": "6:62", "note": ""},
	{"item": 3, "movie": "hatul2.dir", "frame": 768, "script": "1:148",
		"note": "gated on field `score` >= 500, else go(\"finished\")"},
	{"item": 4, "movie": "MAZE2.dir", "frame": 303, "script": "1:223", "note": ""},
	{"item": 5, "movie": "plane2.dir", "frame": 1782, "script": "1:181",
		"note": "gated on fields `kereshcnt` > 8 and `scorecnt` > 599, no else"},
	{"item": 6, "movie": "WEST2.dir", "frame": 543, "script": "1:256", "note": ""},
	{"item": 7, "movie": "fritz2.dir", "frame": 853, "script": "1:463", "note": ""},
]

var _verbose := false
var _cold := false
var _arrive := 900
var _step_budget := 900
var _settle := 4

const CASE := "one checklist item, written by the game the hub chose"


func _init() -> void:
	var args := Args.parse()
	_verbose = Args.flag(args, "verbose")
	_cold = Args.flag(args, "cold")
	_arrive = Args.number(args, "arrive", 900)
	_step_budget = Args.number(args, "step", 900)
	_settle = Args.number(args, "settle", 4)
	var h := Harness.new()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	if preview.get("_score") == null:
		print("no score loaded: --root must name a corpus whose boot movie opens")
		quit(1)
		return

	if _cold:
		print("")
		print("=".repeat(78))
		print("--cold: the NEGATIVE CONTROL. The dinner and the hub click are skipped and")
		print("%s is opened directly, which is the probe this file exists to avoid." % EXPECT_MOVIE)
		print("A red below is the expected result and is not a defect. This flag is not in")
		print("gate.sh; the run without it is.")
		print("=".repeat(78))

	h.begin(CASE)

	# --------------------------------------------- step 0: the authored entry
	var day: Variant = null
	if _cold:
		# Everything the warm path proves, refused on purpose, so the two runs have
		# the same assertions below and differ only in how the movie was reached.
		print("")
		print("--- no authored entry: %s opened cold" % EXPECT_MOVIE)
		preview.call("lingo_go_movie", EXPECT_MOVIE, null)
		if not await _reach_movie(preview, EXPECT_MOVIE):
			h.check("%s opens" % EXPECT_MOVIE, false, "still in %s" % _movie(preview))
			quit(h.finish(CASE))
			return
		h.check("%s opens" % EXPECT_MOVIE, true, "f%d" % _frame(preview))
		day = _global(preview, "globalday")
		var cold_keeper := _keeper(preview)
		h.check("the authored entry sets `globalday` to 2", _int_or(day, -1) == 2,
			"globalday = %s" % str(day))
		h.check("the authored entry resets `advancekeeper`", cold_keeper == FRESH,
			"advancekeeper = %s" % _quote(cold_keeper))
		h.check("item %d does not read `done` before the game runs" % ITEM,
			_item(cold_keeper, ITEM) != "done",
			"item %d = %s" % [ITEM, _quote(_item(cold_keeper, ITEM))])
		h.check("clicking ch%d leaves %s" % [SLOT_CHANNEL, HUB], false,
			"--cold never visits the hub, so nothing was clicked")
		h.check("the movie ch%d chose is %s, composed from `globalday`" % [
			SLOT_CHANNEL, EXPECT_MOVIE], false,
			"--cold named %s itself; the hub was not asked" % EXPECT_MOVIE)
	else:
		print("")
		print("--- the authored entry: %s f%d" % [ENTRY_MOVIE, ENTRY_FRAME])
		preview.call("lingo_go_movie", ENTRY_MOVIE, null)
		if not await _reach_movie(preview, ENTRY_MOVIE):
			h.check("%s opens" % ENTRY_MOVIE, false, "still in %s" % _movie(preview))
			quit(h.finish(CASE))
			return
		h.check("%s opens" % ENTRY_MOVIE, true, "f%d" % _frame(preview))
		_place(preview, ENTRY_FRAME)
		var walk := await _reach_movie_counted(preview, HUB)
		var arrived := bool(walk["ok"])
		h.check("%s f%d walks to %s on its own" % [ENTRY_MOVIE, ENTRY_FRAME, HUB],
			arrived, "%s f%d after %d process frame(s)" % [
				_movie(preview), _frame(preview), int(walk["frames"])])
		if not arrived:
			quit(h.finish(CASE))
			return

		day = _global(preview, "globalday")
		var fresh := _keeper(preview)
		h.check("the authored entry sets `globalday` to 2", _int_or(day, -1) == 2,
			"globalday = %s" % str(day))
		h.check("the authored entry resets `advancekeeper`", fresh == FRESH,
			"advancekeeper = %s" % _quote(fresh))
		h.check("item %d does not read `done` before the game runs" % ITEM,
			_item(fresh, ITEM) != "done",
			"item %d = %s" % [ITEM, _quote(_item(fresh, ITEM))])

		# ------------------------------------- step 1: the hub picks the game
		# ch5's behaviour is placed on f1..f27 and the arriving playhead lands on f0,
		# so the press has to wait for the idle span. Waited for rather than settled
		# for: 27 frames of hub at the score's own rate is a few hundred process
		# frames, and a fixed count that was long enough on one machine is the flake
		# `docs/bugs-closed.md` 119 describes.
		print("")
		print("--- the hub picks the game: ch%d on f%d..f%d" % [
			SLOT_CHANNEL, IDLE_FIRST, IDLE_LAST])
		var idle := await _reach_frame(preview, IDLE_FIRST)
		h.check("%s reaches its idle span" % HUB,
			idle and _frame(preview) <= IDLE_LAST, "f%d" % _frame(preview))
		var at := _centre_of_channel(preview, SLOT_CHANNEL)
		h.check("ch%d is drawn and offers a click point" % SLOT_CHANNEL,
			at != Vector2.ZERO, "centre %s, drawn: %s" % [
				str(at), str(_drawn(preview).has(SLOT_CHANNEL))])
		if at == Vector2.ZERO or not idle:
			quit(h.finish(CASE))
			return

		var pressed_on := _frame(preview)
		var before_click := _movie(preview)
		preview.call("route_press", at)
		preview.call("route_release", at)
		var left := await _leave_movie(preview, before_click)
		var went := _movie(preview)
		# The first of the three steps, and the one that refuses a run that never
		# really left the hub. Its detail line carries the click point and the frame
		# it landed on, because those are the two things a silent miss is.
		h.check("clicking ch%d leaves %s" % [SLOT_CHANNEL, HUB], left,
			"pressed (%d, %d) on f%d, still in %s f%d" % [
				int(at.x), int(at.y), pressed_on, went, _frame(preview)])
		if not left:
			quit(h.finish(CASE))
			return
		# Not `lingo_go_movie(EXPECT_MOVIE)`: the engine composed this name out of a
		# global written in another movie, and this is the only place the expectation
		# is spelled. A `globalday` that had not survived would land somewhere else
		# and say so here rather than passing on a string this file supplied.
		h.check("the movie ch%d chose is %s, composed from `globalday`" % [
			SLOT_CHANNEL, EXPECT_MOVIE],
			went.to_lower() == EXPECT_MOVIE.to_lower(),
			"`%s%s.dxr` -> %s" % [EXPECT_STEM, str(day), went])
		if went.to_lower() != EXPECT_MOVIE.to_lower():
			quit(h.finish(CASE))
			return

	# ------------------------------------------- step 2: the game writes it
	# The movie is past its own f0 before the landing, which is where `1:258` runs.
	# Normally satisfied by the settle after the arrival, so this is a guard against a
	# movie that never leaves its first frame rather than a measurement — the landing
	# being warm is what the checks above establish, not this one.
	print("")
	print("--- the game writes it: %s f%d" % [EXPECT_MOVIE, WRITE_FRAME])
	var inited := await _reach_frame(preview, 1)
	h.check("%s is past its own f0 before the landing" % EXPECT_MOVIE, inited,
		"f%d" % _frame(preview))
	if not inited:
		quit(h.finish(CASE))
		return

	var before := _keeper(preview)
	_place(preview, WRITE_FRAME)
	var returned := await _reach_movie(preview, HUB)
	var after := _keeper(preview)
	# `1:138` writes the item and leaves the movie in the same handler, so the movie
	# change *is* the witness that the `put` on the line above the `go` executed.
	h.check("f%d's own `exitFrame` ran: its `go` returned the movie to %s" % [
		WRITE_FRAME, HUB],
		returned, "in %s f%d" % [_movie(preview), _frame(preview)])
	if not returned:
		print("    the placement was inert: the frame script never ran, so nothing")
		print("    can be said about the write or about its survival")
		quit(h.finish(CASE))
		return

	# ------------------------------- step 3: the value survives `go movie`
	# Read on the far side of the change, which is the only side it can be read on:
	# the write and the `go` are two lines of one handler. So this is the survival
	# assertion and not a second reading of the write.
	var wrote := _item(after, ITEM) == "done"
	h.check("item %d reads `done` on the far side of the movie change" % ITEM, wrote,
		"%s -> %s" % [_quote(before), _quote(after)])
	var others := _others_untouched(after)
	h.check("the other six items are untouched by the write", others.is_empty(),
		"" if others.is_empty() else ", ".join(others))

	# --------------------------------------------- step 4: the hub reads it
	# `1:13` is an `exitFrame` on f0, and f0 is crossed once per arrival and never
	# inside the idle loop: every game returns with `go(1, ...)`, which is Lingo
	# frame 1 and engine index 0, while `1:15`'s other arm is `go(marker(0))` from
	# f27 and `marker(0)` resolves to `day1` at f1. So the dressed stage is readable
	# from the first frame after the arrival and not before, and a harness that
	# waited for the init to come round again would wait for ever.
	print("")
	print("--- the hub reads it: `1:13` on f0")
	var stepped := await _reach_frame(preview, 1)
	h.check("%s steps off its init frame" % HUB, stepped, "f%d" % _frame(preview))
	var mismatch: Array[String] = []
	var dressed := _hub_agrees(preview, wrote, mismatch)
	h.check("`1:13` hides slot %d and shows its done marker" % ITEM, dressed,
		"" if dressed else "%d channel(s) disagree" % mismatch.size())
	for line in mismatch:
		print("    %s" % line)
	if _verbose:
		for line in _slot_table(preview):
			print("    %s" % line)
	print("    badges  : %s   (not asserted: `1:13`'s reset stops at ch30)" % _badges(preview))
	print("    `1:14`'s own reading, as `the visible of sprite`, not asserted:")
	print("      %s" % _visible_props(preview))
	h.complete(CASE)

	# ------------------------------------------------------ what was not driven
	print("")
	print("the day advance is not asserted here: `1:15` on f27 needs all seven items.")
	print("  advancekeeper : %s" % _quote(_keeper(preview)))
	print("  globalday     : %s" % str(_global(preview, "globalday")))
	print("  landed in     : %s f%d" % [_movie(preview), _frame(preview)])
	print("")
	print("six writing frames derived and driven by nothing:")
	for value in NOT_DRIVEN:
		var row: Dictionary = value
		print("  item %d  %-12s f%-5d %-7s %s" % [
			int(row["item"]), str(row["movie"]), int(row["frame"]),
			str(row["script"]), str(row["note"])])
	quit(h.finish(CASE))


## Put the playhead on `frame` as a frame entry, dropping whatever the frame it was
## abandoned on had armed.
##
## Four fields, for the reason in the header: `_index` alone leaves an abandoned
## tempo or sound hold in the clock, the `enterFrame` owed to the frame being left
## would be dispatched against the arriving one (`frame_loop.gd:advance`), and the
## `exitFrame` latch — which is what actually runs the write — is cleared only by a
## frame entry, so a placement that skipped it would be silently inert.
func _place(preview: Node, frame: int) -> void:
	preview.set("_index", frame)
	preview.set("_pending_enter", null)
	preview.set("_exit_frame_called", false)
	var clock = preview.get("_clock")
	if clock != null:
		clock.reset()


func _reach_movie(preview: Node, movie: String) -> bool:
	return bool((await _reach_movie_counted(preview, movie))["ok"])


## `{ok, frames}`, because "walks to the hub unaided in about 15 process frames" is a
## measurement this file should be able to print rather than a claim in a comment.
func _reach_movie_counted(preview: Node, movie: String) -> Dictionary:
	for i in _arrive:
		await process_frame
		if _movie(preview).to_lower() == movie.to_lower():
			for j in _settle:
				await process_frame
			return {"ok": true, "frames": i + 1}
	return {"ok": false, "frames": _arrive}


## Wait until the movie is anything other than `movie`.
##
## The click's `go` is dispatched inside `route_release` and takes effect in the same
## call, so this normally returns on its first look. It is a loop anyway because a
## press that routed nowhere is the failure this guards, and the difference between
## "immediately" and "never" is what the budget measures.
func _leave_movie(preview: Node, movie: String) -> bool:
	for i in _arrive:
		if _movie(preview).to_lower() != movie.to_lower():
			for j in _settle:
				await process_frame
			return true
		await process_frame
	return false


func _reach_frame(preview: Node, frame: int) -> bool:
	for i in _step_budget:
		if _frame(preview) >= frame:
			return true
		await process_frame
	return false


## Does the hub's dressing agree with the one item under test?
##
## Asked as "is it drawn" rather than as `the visible of sprite`, for the reason
## `puzzle_board.gd:_agrees` records: a hidden channel leaves `frame_sprites()`
## altogether, and a `lingo_sprite_prop(ch, "visible")` on a channel the frame does
## not offer answers from `EMPTY_CHANNEL`'s default rather than from the override, so
## the property read cannot tell a hidden sprite from an absent one and hidden is
## exactly what is under test. The frame's own channel list is consulted first so
## that "the score never placed it" is reported as itself.
##
## All fourteen channels are checked and not just the two for this item: `1:13`'s
## reset is a `repeat` over every one of them, so an off-by-one in the loop would
## show as a *neighbour* moving, and a check that looked only at ch5 and ch14 would
## agree with it.
func _hub_agrees(preview: Node, is_done: bool, out: Array[String]) -> bool:
	var drawn := _drawn(preview)
	var placed := _placed(preview)
	var right := true
	for item in range(1, ITEM_COUNT + 1):
		var done := is_done and item == ITEM
		for pair in [[SHOWN_WHEN_OPEN, not done], [SHOWN_WHEN_DONE, done]]:
			var channel: int = int(pair[0]) + item
			var want: bool = bool(pair[1])
			if not placed.has(channel):
				out.append("ch%d is not in the frame's channel list at all" % channel)
				right = false
				continue
			if drawn.has(channel) != want:
				out.append("ch%d (item %d, %s) is %s and should be %s" % [
					channel, item, "done" if done else "open",
					"drawn" if drawn.has(channel) else "hidden",
					"drawn" if want else "hidden"])
				right = false
	return right


func _slot_table(preview: Node) -> Array[String]:
	var drawn := _drawn(preview)
	var out: Array[String] = []
	for item in range(1, ITEM_COUNT + 1):
		out.append("item %d: ch%-2d %-6s  ch%-2d %s" % [
			item, SHOWN_WHEN_OPEN + item,
			"drawn" if drawn.has(SHOWN_WHEN_OPEN + item) else "hidden",
			SHOWN_WHEN_DONE + item,
			"drawn" if drawn.has(SHOWN_WHEN_DONE + item) else "hidden"])
	return out


## ch27..ch33, printed rather than asserted: `1:13`'s reset is `repeat with i = 1 to
## 30`, so items 5, 6 and 7 have no reset arm and their badges are write-once.
func _badges(preview: Node) -> String:
	var drawn := _drawn(preview)
	var out: Array[String] = []
	for item in range(1, ITEM_COUNT + 1):
		out.append("ch%d %s" % [BADGE + item,
			"drawn" if drawn.has(BADGE + item) else "hidden"])
	return ", ".join(out)


## What `1:14` sees when it asks `sprite(13 + n).visible`, which is the other reader
## of the same state. Printed, never asserted: on a channel the frame does not offer
## this answers from the empty-channel default, which is the trap `_hub_agrees`
## avoids by consulting the channel list instead.
func _visible_props(preview: Node) -> String:
	var out: Array[String] = []
	for item in range(1, ITEM_COUNT + 1):
		var channel := SHOWN_WHEN_DONE + item
		out.append("sprite(%d).visible = %s" % [
			channel, str(preview.call("lingo_sprite_prop", channel, "visible"))])
	return ", ".join(out)


## The centre of a channel's live rect, off the frame the playhead is on, so a rect
## the score moved is followed rather than a coordinate frozen into this file.
func _centre_of_channel(preview: Node, channel: int) -> Vector2:
	for value in preview.call("frame_sprites"):
		var raw: Dictionary = value
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty():
			return Vector2.ZERO
		var rect: Rect2 = preview.call("_sprite_rect", live)
		return rect.get_center()
	return Vector2.ZERO


## The channels the frame the playhead is on actually draws.
func _drawn(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		if (preview.call("_effective", sprite) as Dictionary).is_empty():
			continue
		out[int(sprite["channel"])] = true
	return out


## The channels the frame offers, drawn or hidden, so that "hidden" and "never
## placed" are two answers and not one.
func _placed(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	for value in preview.call("frame_sprites"):
		out[int((value as Dictionary)["channel"])] = true
	return out


## Which of the six items this run does not drive moved anyway. A write that reached
## the wrong index, or a `put ... into item N` that rewrote the whole global, would
## pass the item-2 check and fail here.
func _others_untouched(after: String) -> Array[String]:
	var out: Array[String] = []
	for item in range(1, ITEM_COUNT + 1):
		if item == ITEM:
			continue
		var was := _item(FRESH, item)
		var now := _item(after, item)
		if now != was:
			out.append("item %d: %s -> %s" % [item, _quote(was), _quote(now)])
	return out


func _keeper(preview: Node) -> String:
	var value: Variant = _global(preview, "advancekeeper")
	return "" if value == null else str(value)


## `item N of advancekeeper`, with Director's default comma delimiter.
func _item(text: String, index: int) -> String:
	var items := text.split(",", true)
	if index < 1 or index > items.size():
		return ""
	return str(items[index - 1]).strip_edges()


func _global(preview: Node, name: String) -> Variant:
	var lingo = preview.get("_interpreter")
	if lingo == null:
		return null
	return (lingo.globals as Dictionary).get(name, null)


func _movie(preview: Node) -> String:
	return str(preview.call("movie_name"))


func _frame(preview: Node) -> int:
	return int(preview.call("current_frame"))


## Quoted, so an empty global and a VOID one are not the same line of output. The
## whole false-negative story in the header turns on that difference.
func _quote(text: String) -> String:
	return "<empty or VOID>" if text == "" else "\"%s\"" % text


func _int_or(value: Variant, fallback: int) -> int:
	if value == null or not (value is int or value is float or value is String):
		return fallback
	if value is String:
		return int(str(value)) if str(value).is_valid_int() else fallback
	return int(value)
