extends SceneTree
## A `play` that never says `done` cannot grow the return stack without end.
##
##   godot --headless --audio-driver Dummy --path . --script tools/play_stack_bound.gd
##
## `play frame the frame` is a legal Director idiom and a common one: the frame
## re-enters itself, its `on exitFrame` runs again, and it calls `play` again. The
## reference pushes a return address every time and never looks at whether the
## destination is the frame the playhead is already on — `Lingo::func_play`
## records `getCurrentFrameNum()`, adds one when the caller is a frame or movie
## script, and pushes it into `Window::_movieStack` unconditionally
## (`lingo-funcs.cpp:207-213`, `window.h:238`). Nothing pops it but `play done`
## and the end-of-score return, so in ScummVM that list grows once per score step
## for as long as the loop runs. This port reproduced that faithfully, which is
## the finding of `bugs.md` 86 and *not* the bug in it: measured on Itamar Park's
## `BehaviorScript 24 - play frame` (`torfim.dir` frame 20, 80 fps tempo), the
## stack reached 7,283 entries in 4,000 rendered ticks and was still climbing 80
## a second.
##
## Two things make an unbounded copy worse here than in the reference. Its entry
## is six bytes; this one is a `{String, int}` dictionary carrying the movie's
## whole path. And `preview/save_state.gd` writes `_play_stack` into every save,
## so a long session in a self-`play` loop would put a quarter of a million
## identical return addresses into the player's save file — a cost the reference
## does not have because it has nothing to save.
##
## So the stack is capped, and this asserts the two halves that a cap must not
## break. **A nest shallower than the cap returns through every level, in order**
## — that is what the stack is *for*, and a cap that trimmed the newest entry
## would break it on the first `play done`. **A runaway stops growing**, and the
## return it hands the next `play done` is still the most recent one, because the
## entry that goes is the oldest. Both are player-visible: the first is whether a
## cut scene comes back to where it was called from, the second is whether the
## engine survives a movie that loops on `play` for an hour.
##
## Deliberately driven through `lingo_play_push`/`lingo_play_done` on the real
## preview rather than through a movie that happens to contain the idiom. No
## shipped title in this repo carries a `play frame the frame` loop — the one that
## does is `test-games/itamar-park`, which is untracked and ignored
## (`.gitignore:73`), and a gate entry that can only pass against a corpus outside
## the project gates nothing. The verbs are the whole subject here, and they are
## the same two verbs the title calls.
const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const SaveState := preload("res://scenes/preview/save_state.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var cap := int(preview.get("MAX_PLAY_STACK"))
	var frames := int(preview.get("_score").frame_count)
	if not h.check("the movie has frames to play between", frames >= 8,
			"%d frame(s)" % frames):
		quit(h.finish("the play stack is bounded"))
		return

	# ---------------------------------------------------------- ordinary nesting
	#
	# Three `play`s and three `play done`s, each from a *sprite* channel so the
	# recorded frame is the caller's own rather than the one after it
	# (`lingo-funcs.cpp:211-212`, the `currentChannelId == 0` line). Returning to
	# the exact frame it was called from is the assertion; returning to "somewhere
	# near" would pass a size check and still be the bug.
	h.begin("a nest shallower than the cap returns through every level")
	preview.set("_play_stack", [])
	var host = preview.get("_host")
	var outer := int(host.current_sprite_num)
	host.current_sprite_num = 4
	var called_from: Array = [2, 4, 6]
	for from in called_from:
		preview.set("_index", int(from))
		preview.call("lingo_play_push", [int(from) + 1])
	h.check("three plays record three returns",
		(preview.get("_play_stack") as Array).size() == 3,
		"%d recorded" % (preview.get("_play_stack") as Array).size())
	var seen: Array = []
	for i in 3:
		preview.call("lingo_play_done")
		seen.append(int(preview.get("_index")))
	called_from.reverse()
	h.check("and `play done` unwinds them newest first",
		seen == called_from, "returned to %s, called from %s" % [str(seen), str(called_from)])
	h.check("the stack is empty once the nest is unwound",
		(preview.get("_play_stack") as Array).is_empty(),
		"%d left" % (preview.get("_play_stack") as Array).size())
	h.complete("a nest shallower than the cap returns through every level")

	# ------------------------------------------------------------- the runaway
	#
	# The idiom itself: `play` to the frame the playhead is already on, from a
	# frame script (channel 0), over and over. This is what `bugs.md` 86 measured
	# and what a movie does when its `on exitFrame` ends in `play frame the frame`.
	h.begin("a `play` that never returns stops growing")
	preview.set("_play_stack", [])
	host.current_sprite_num = 0
	preview.set("_index", 3)
	for i in cap * 4:
		preview.call("lingo_play_push", [4])
	var depth: int = (preview.get("_play_stack") as Array).size()
	h.check("%d self-plays leave the stack at its ceiling, not at %d" % [cap * 4, cap * 4],
		depth == cap, "%d deep, ceiling %d" % [depth, cap])
	# The oldest is what goes, so the next `play done` still returns where the
	# most recent `play` came from. A cap that dropped the newest instead would
	# pass the size check above and send the playhead to a frame the movie left
	# thousands of steps ago.
	var top: Dictionary = (preview.get("_play_stack") as Array).back()
	preview.call("lingo_play_done")
	h.check("and the next `play done` still returns to the most recent caller",
		int(preview.get("_index")) == int(top["frame"]),
		"returned to %d, newest entry recorded %d" % [
			int(preview.get("_index")), int(top["frame"])])
	h.complete("a `play` that never returns stops growing")

	# ------------------------------------------------------- nothing was saved
	#
	# The second cost, and the one the reference does not share: whatever is on
	# this stack goes into every save file. Asserted through the save state's own
	# encoder rather than by reading the field, because that is the path a save
	# takes.
	h.begin("a save carries the bounded stack")
	preview.set("_play_stack", [])
	host.current_sprite_num = 0
	for i in cap * 4:
		preview.call("lingo_play_push", [4])
	var state: Dictionary = SaveState.capture(preview)
	# Round-tripped rather than read: `encode` wraps a typed array, and asserting
	# against the wrapper would be asserting about the encoder.
	var saved: Array = SaveState.decode(state.get("play_stack", []))
	h.check("the saved stack is bounded too", saved.size() <= cap,
		"%d entries in the save" % saved.size())
	h.complete("a save carries the bounded stack")

	host.current_sprite_num = outer
	preview.set("_play_stack", [])
	quit(h.finish("the play stack is bounded"))
