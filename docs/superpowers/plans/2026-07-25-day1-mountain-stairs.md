# Day 1 Mountain Stairs Redirect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Day 1 mountain-stairs route finish its climb-up animation at `lighttop` without falling through into `stairsclimbdown`.

**Architecture:** Add a focused headless route regression, then represent missing dynamic Day 1 completion redirects as a transition-label-to-destination map in `DirectorRuntime`. At frames using the original dynamic completion handler, the runtime consults that map before normal exported navigation, resolves the destination label, and enters it.

**Tech Stack:** Godot 4.x, GDScript, decoded Director render-model JSON

---

### Task 1: Reproduce the mountain-stairs fall-through

**Files:**
- Create: `tests/test_day1_navigation.gd`

- [ ] **Step 1: Write the failing route test**

```gdscript
extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	_expect_eq(runtime.boot(), OK, "mountain-stairs test loads the render-model index")
	_expect_true(
		runtime.goto_movie("DAY1", null, {"label": "stairs"}),
		"mountain-stairs test enters the stairs room"
	)

	runtime.perform_click(Vector2(100, 330))
	_expect_true(runtime.puppet.is_walking(), "mountain-stairs hotspot starts walking")

	var reached_lighttop := false
	var fell_into_stairsclimbdown := false
	for _step in 100:
		runtime.game_step()
		var marker: String = runtime.marker_name_for_frame(runtime.frame_index).to_lower()
		if marker == "stairsclimbdown":
			fell_into_stairsclimbdown = true
			break
		if marker == "lighttop":
			reached_lighttop = true
			break

	_expect_true(not fell_into_stairsclimbdown, "climb-up never enters climb-down")
	_expect_true(reached_lighttop, "climb-up finishes at lighttop")

	if failures.is_empty():
		print("PASS: Day 1 navigation regression suite")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		failures.append("%s: expected true, got false" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
```

- [ ] **Step 2: Run the route test and verify the expected failure**

Run:

```bash
godot --headless --path . --script tests/test_day1_navigation.gd
```

Expected: exit code `1`, with `climb-up never enters climb-down` and
`climb-up finishes at lighttop` failures caused by entering
`stairsclimbdown`.

- [ ] **Step 3: Commit the failing regression**

```bash
git add tests/test_day1_navigation.gd
git commit -m "test: reproduce Day 1 mountain stairs fall-through"
```

### Task 2: Redirect the completed climb to the mountain top

**Files:**
- Modify: `director/director_runtime.gd`
- Test: `tests/test_day1_navigation.gd`

- [ ] **Step 1: Add the missing dynamic redirect map**

Add beside the runtime constants:

```gdscript
const DAY1_TRANSITION_REDIRECTS := {
	"stairsclimbup": "lighttop",
}
const DAY1_DYNAMIC_REDIRECT_SCRIPT := 207
```

- [ ] **Step 2: Resolve dynamic redirects before exported frame navigation**

At the start of `game_step()`, after the puppet-walking branch and after
fetching the current frame, invoke:

```gdscript
	if _apply_day1_transition_redirect(frame):
		return
```

Add the focused helper:

```gdscript
func _apply_day1_transition_redirect(frame: Dictionary) -> bool:
	if (
		loader.movie_name.to_lower() != "day1"
		or int(frame.get("frame_script", -1)) != DAY1_DYNAMIC_REDIRECT_SCRIPT
	):
		return false
	var transition := marker_name_for_frame(frame_index).to_lower()
	var destination := _s(DAY1_TRANSITION_REDIRECTS.get(transition, ""))
	if destination == "":
		return false
	var destination_frame := loader.resolve_label(destination, false)
	if destination_frame < 0:
		nav_event.emit('Missing Day 1 transition label: "%s"' % destination)
		return false
	enter_frame(destination_frame)
	nav_event.emit("Day 1 transition: %s → %s" % [transition, destination])
	return true
```

- [ ] **Step 3: Run the route regression and verify it passes**

Run:

```bash
godot --headless --path . --script tests/test_day1_navigation.gd
```

Expected: exit code `0` and
`PASS: Day 1 navigation regression suite`.

- [ ] **Step 4: Run the existing runtime regression suite**

Run:

```bash
godot --headless --path . --script tests/test_director_runtime.gd
```

Expected: no new navigation, timing, boot-chain, or transactional-loading
failures. Any already-known invalid-numeric-metadata failures are reported
separately and are not changed as part of this route fix.

- [ ] **Step 5: Verify Godot parses the project**

Run:

```bash
godot --headless --path . --editor --quit
```

Expected: exit code `0` with no GDScript parse errors.

- [ ] **Step 6: Commit the fix**

```bash
git add director/director_runtime.gd
git commit -m "fix: route mountain stairs to lighttop"
```

### Task 3: Prepare the broader Day 1 redirect audit

**Files:**
- No file changes in this task

- [ ] **Step 1: Inventory the affected completion frames**

Run:

```bash
jq -r '.frames[] | select(.frame_script == 207) | .frame_index' \
  assets/render_model/DAY1/frames.json
```

Expected: a list of all Day 1 frames that depend on the original dynamic
completion handler, including frames `2007` and `2032`.

- [ ] **Step 2: Record the audit boundary**

Confirm that this implementation changes only `stairsclimbup → lighttop`.
The follow-up audit will compare every listed completion frame with its
decompiled `nextroomdata` destination and add a separate regression matrix
before expanding `DAY1_TRANSITION_REDIRECTS`.
