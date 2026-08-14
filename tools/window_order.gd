extends SceneTree
## Which of two Movie-In-A-Windows is in front, and who takes the click there.
##
##   godot --headless --script tools/window_order.gd
##   godot --headless --script tools/window_order.gd -- --root piposh2 \
##     --window-a PIP2DATA/MAP.dir --window-b PIP2DATA/JOKE.dir
##
## `moveToFront` and `moveToBack` are §7.4 window methods that nothing bound
## (`bugs.md` 107), and the reason that was worth more than a line in the unbound
## report is that **`windows.gd` parents every window above the stage
## unconditionally**. So the one arrangement Itamar Park asks for is the one it
## already got, its four `moveToFront` calls did nothing and nothing looked wrong,
## and a title that opens *two* windows had no way at all to say which was in
## front. The symptom of the gap is not an error: it is a window drawn behind the
## one a script raised over it, which reads as a rendering bug.
##
## ## What it asserts, and why through Lingo
##
## Every ordering change here is made by **compiling and running the Lingo**, not
## by calling `Windows.move_to_front`. The bug was a missing binding, so a harness
## that called the module directly would pass with the binding still missing --
## which is the whole failure mode, one level up.
##
## The three questions asked after each move are the three that differ, and a
## port can get any one of them right while the other two are wrong:
##
## 1. `the windowList` order -- what the engine thinks the stack is;
## 2. the **node tree**, which is what actually draws: a Godot child draws over
##    its parent, so "in front of the stage" is a later child and "behind the
##    stage" is `show_behind_parent`, and a list that says one thing while the
##    tree says another is a stack that is right in the report and wrong on
##    screen;
## 3. `Windows.at`, which is who gets the click. A window sent behind the stage
##    must stop taking clicks where it used to be, or the player is clicking a
##    window they cannot see.
##
## ## The stage is in the stack
##
## Director has no "stage plus windows on top": the stage is a window in the same
## list (§14), which is what makes `moveToFront(the stage)` a sentence.
## Itamar Park says exactly that, twice --
## `levels.dir` and `study/ChapTrfm.dir` both `on exitFrame  moveToFront(the
## stage)  forget(<window>)` -- and `torfim.dir on stopMovie` says
## `moveToBack(StudyWindow)` before its `forget`. So both directions and both
## kinds of target come from a real title.
##
## ## Fixtures
##
## `PIP2DATA/MAP.dir` and `PIP2DATA/JOKE.dir` are Piposh 2's two real window
## movies, and they are **flags with defaults** rather than constants, for the
## reason `director-qa-playthrough` gives: `tools/window_renders.gd` defaults its
## window to `joke.dxr`, and run against another title it reports
## `joke.dxr -> not found`, which reads exactly like a missing asset in that
## title. Both are checked to have opened before anything is asserted about them,
## so a corpus without them fails loudly here rather than quietly asserting over
## one window or none.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Windows := preload("res://scenes/preview/windows.gd")

## Both windows are given the same rect, so every point inside it is inside both
## and "who takes the click here" has exactly one right answer at every step.
## Without that the test would be measuring which window happens to cover the
## probe rather than which one is in front.
const SHARED_RECT := [120, 100, 360, 300]
const PROBE := Vector2(240, 200)

var _preview: Node


## Run a Lingo statement on the stage's interpreter and say whether it compiled.
##
## The binding is the subject, so this is the only way the ordering is changed.
func _lingo(source: String) -> bool:
	var interpreter = _preview.get("_interpreter")
	if interpreter == null:
		return false
	var errors: Array = []
	var code = interpreter.compile_statements(source, "window_order", errors)
	if not errors.is_empty():
		print("  !! compile %s -> %s" % [source, str(errors)])
		return false
	interpreter.reset_steps()
	interpreter.run_compiled(code)
	return true


## The window nodes' child indices on the stage, and whether each draws behind it.
## This is the tree, which is what the screen shows.
func _tree_place(key: String) -> Array:
	var node: Node = _preview.get("_windows").get(key)
	if node == null:
		return [-1, false]
	return [node.get_index(), bool(node.show_behind_parent)]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	_preview = (load("res://scenes/director_preview.tscn") as PackedScene).instantiate()
	root.add_child(_preview)
	for i in 6:
		await process_frame

	var name_a := Args.text(args, "window-a", "PIP2DATA/MAP.dir")
	var name_b := Args.text(args, "window-b", "PIP2DATA/JOKE.dir")
	var key_a: String = _preview.window_key(name_a)
	var key_b: String = _preview.window_key(name_b)

	h.begin("two windows opened")
	var opened := _lingo('open(window("%s"))' % name_a) \
		and _lingo('open(window("%s"))' % name_b)
	for i in 3:
		await process_frame
	# Same rect for both, so the probe point is inside both and the answer to
	# "who takes this click" is only ever about the order.
	_preview.lingo_set_window_prop(key_a, "rect", SHARED_RECT)
	_preview.lingo_set_window_prop(key_b, "rect", SHARED_RECT)
	var open_keys: Array = _preview.window_keys()
	h.check("both fixture windows opened", opened
			and open_keys.has(key_a) and open_keys.has(key_b),
		"asked for %s and %s, windowList is %s" % [key_a, key_b, str(open_keys)])
	# Everything below is about ordering *between* two windows, so there is
	# nothing to say if there are not two. Bail rather than assert over one.
	if not (open_keys.has(key_a) and open_keys.has(key_b)):
		h.complete("two windows opened")
		quit(h.finish("window stacking order"))
		return
	# The second `open` raises, which is what Director does and what this port
	# already did -- recorded here as the baseline the moves are measured against
	# rather than as something new.
	h.check("the second window opened is in front",
		Windows.front(_preview) == _preview.get("_windows").get(key_b),
		"front is %s" % str(Windows.front(_preview)))
	h.check("and the click at the probe goes to it",
		Windows.at(_preview, PROBE) == _preview.get("_windows").get(key_b))
	h.check("and it is the later child, so it draws over the other",
		int(_tree_place(key_b)[0]) > int(_tree_place(key_a)[0]),
		"%s at %d, %s at %d" % [key_b, int(_tree_place(key_b)[0]),
			key_a, int(_tree_place(key_a)[0])])
	h.complete("two windows opened")

	h.begin("moveToFront raises a window over another window")
	h.check("the Lingo compiled and ran",
		_lingo('moveToFront(window("%s"))' % name_a))
	h.check("the raised window is now the front one",
		Windows.front(_preview) == _preview.get("_windows").get(key_a),
		"front is %s" % str(Windows.front(_preview)))
	h.check("the click at the probe goes to it",
		Windows.at(_preview, PROBE) == _preview.get("_windows").get(key_a))
	h.check("and the tree agrees: it is the later child",
		int(_tree_place(key_a)[0]) > int(_tree_place(key_b)[0]),
		"%s at %d, %s at %d" % [key_a, int(_tree_place(key_a)[0]),
			key_b, int(_tree_place(key_b)[0])])
	h.check("neither window is drawn behind the stage",
		not bool(_tree_place(key_a)[1]) and not bool(_tree_place(key_b)[1]))
	h.complete("moveToFront raises a window over another window")

	h.begin("moveToBack sends a window behind the stage")
	h.check("the Lingo compiled and ran",
		_lingo('moveToBack(window("%s"))' % name_a))
	h.check("the other window is the front one again",
		Windows.front(_preview) == _preview.get("_windows").get(key_b),
		"front is %s" % str(Windows.front(_preview)))
	# The whole point of the stage being in the stack. A window behind it is
	# behind it for the mouse as well as the eye, and the flag is the only thing
	# in Godot that puts a child under its parent's own drawing.
	h.check("the sent-back window draws behind the stage",
		bool(_tree_place(key_a)[1]),
		"show_behind_parent is %s" % str(_tree_place(key_a)[1]))
	h.check("the front window does not",
		not bool(_tree_place(key_b)[1]))
	h.complete("moveToBack sends a window behind the stage")

	h.begin("a window behind the stage stops taking clicks")
	h.check("the Lingo compiled and ran",
		_lingo('moveToBack(window("%s"))' % name_b))
	h.check("with both behind it, the stage takes the probe click",
		Windows.at(_preview, PROBE) == null,
		"at() answered %s" % str(Windows.at(_preview, PROBE)))
	h.check("and there is no front window",
		Windows.front(_preview) == null)
	h.complete("a window behind the stage stops taking clicks")

	h.begin("moveToFront(the stage) raises the stage over the windows")
	h.check("the Lingo compiled and ran",
		_lingo('moveToFront(window("%s"))' % name_a) \
			and _lingo('moveToFront(window("%s"))' % name_b))
	h.check("both windows are in front of the stage again",
		Windows.at(_preview, PROBE) == _preview.get("_windows").get(key_b),
		"at() answered %s" % str(Windows.at(_preview, PROBE)))
	h.check("`moveToFront(the stage)` compiled and ran",
		_lingo("moveToFront(the stage)"))
	h.check("the stage is now in front: no window is",
		Windows.front(_preview) == null,
		"front is %s" % str(Windows.front(_preview)))
	h.check("and the probe click belongs to the stage",
		Windows.at(_preview, PROBE) == null)
	h.check("both windows are drawn behind it",
		bool(_tree_place(key_a)[1]) and bool(_tree_place(key_b)[1]),
		"%s %s, %s %s" % [key_a, str(_tree_place(key_a)[1]),
			key_b, str(_tree_place(key_b)[1])])
	h.check("raising one back over the stage restores it",
		_lingo('moveToFront(window("%s"))' % name_a) \
			and Windows.front(_preview) == _preview.get("_windows").get(key_a) \
			and not bool(_tree_place(key_a)[1]),
		"front is %s" % str(Windows.front(_preview)))
	h.complete("moveToFront(the stage) raises the stage over the windows")

	# The report the bug was filed from. `bugs.md` 107 quotes
	# `builtins unbound : {"movetofront":2, ...}`, so the binding existing is
	# exactly the absence of these two names from that dictionary -- and a name
	# lands there on its first *reached* call, which the runs above have made.
	h.begin("neither name is reported unbound any more")
	var unbound: Dictionary = _preview.get("_host").unbound
	h.check("moveToFront is bound", not unbound.has("movetofront"), str(unbound))
	h.check("moveToBack is bound", not unbound.has("movetoback"), str(unbound))
	h.complete("neither name is reported unbound any more")

	print("windowList: %s   stage at index %d of the order"
		% [str(_preview.window_keys()), Windows.stage_index(_preview)])
	quit(h.finish("window stacking order"))
