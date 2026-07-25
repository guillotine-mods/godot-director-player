# Godot Score Catch-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent slow Godot process frames from fast-forwarding score movies, so New Game plays EXODUS normally before entering DAY1.

**Architecture:** Keep scheduling inside the generic `DirectorRuntime` score clock. Calculate due score steps once per Godot tick, execute at most three, discard excess whole-step backlog, and stop catch-up when a score step changes movies.

**Tech Stack:** Godot 4.7.1, GDScript, Godot headless execution

---

## File Structure

- Create `tests/test_director_runtime.gd`: dependency-free headless regression runner for score timing and the title-to-EXODUS-to-DAY1 boot chain.
- Modify `director/director_runtime.gd`: bound score catch-up and stop catch-up at movie boundaries.
- Modify `docs/ENGINE.md`: document the score clock's bounded catch-up behavior.

### Task 1: Add the Failing Godot Runtime Regression

**Files:**
- Create: `tests/test_director_runtime.gd`

- [ ] **Step 1: Create the headless test runner**

Create `tests/test_director_runtime.gd`:

```gdscript
extends SceneTree

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_large_delta_is_bounded()
	_test_excess_backlog_is_discarded()
	_test_normal_delta_advances_once()
	_test_new_game_boot_chain()

	if _failures.is_empty():
		print("PASS: DirectorRuntime regression suite")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _runtime_with_frames(count: int, fps: float = 10.0) -> DirectorRuntime:
	var runtime := DirectorRuntime.new()
	runtime.loader.movie_name = "TEST"
	runtime.loader.frames = []
	for i in count:
		runtime.loader.frames.append({
			"frame_index": i,
			"fps": fps,
			"nav": null,
			"delay_ms": 0,
			"wait_click": false,
			"sounds": [],
			"sprites": [],
		})
	runtime.current_fps = fps
	runtime.enter_frame(0)
	return runtime


func _test_large_delta_is_bounded() -> void:
	var runtime := _runtime_with_frames(100)
	runtime.tick(1.0)
	_expect_eq(runtime.frame_index, 3, "large delta advances at most three score steps")


func _test_excess_backlog_is_discarded() -> void:
	var runtime := _runtime_with_frames(100)
	runtime.tick(1.0)
	var bounded_frame := runtime.frame_index
	runtime.tick(0.01)
	_expect_eq(runtime.frame_index, bounded_frame, "excess score backlog is discarded")


func _test_normal_delta_advances_once() -> void:
	var runtime := _runtime_with_frames(10)
	runtime.tick(0.1)
	_expect_eq(runtime.frame_index, 1, "ordinary delta advances one score step")


func _test_new_game_boot_chain() -> void:
	var runtime := DirectorRuntime.new()
	_expect_eq(runtime.boot(), OK, "render-model index loads")
	_expect_true(runtime.goto_movie("strtgame"), "title movie loads")
	_expect_true(runtime.goto_movie("exodus", 1), "New Game loads EXODUS")
	_expect_eq(runtime.loader.movie_name, "EXODUS", "New Game enters EXODUS")
	_expect_eq(runtime.frame_index, 0, "EXODUS starts at frame index zero")

	runtime.enter_frame(runtime.loader.frames.size() - 1)
	runtime.game_step()
	_expect_eq(runtime.loader.movie_name, "DAY1", "EXODUS final navigation enters DAY1")
	_expect_eq(runtime.frame_index, 0, "DAY1 starts at requested frame one")


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		_failures.append("%s: expected true" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
```

- [ ] **Step 2: Run the test and verify the timing regression fails**

Run:

```bash
godot --headless --path . --script tests/test_director_runtime.gd
```

Expected: exit code `1`, with the failure `large delta advances at most three score steps: expected 3, got 10`. The normal timing and boot-chain assertions should not report failures.

### Task 2: Bound Score Catch-Up in DirectorRuntime

**Files:**
- Modify: `director/director_runtime.gd:20-26`
- Modify: `director/director_runtime.gd:77-86`

- [ ] **Step 1: Define the generic catch-up limit**

Add the constant beside `MAX_GUARD_HOLD_MS`:

```gdscript
const MAX_GUARD_HOLD_MS := 20000.0
const MAX_SCORE_STEPS_PER_TICK := 3
```

- [ ] **Step 2: Replace the unlimited tick loop**

Replace `DirectorRuntime.tick` with:

```gdscript
func tick(delta: float) -> void:
	_time_ms += delta * 1000.0
	if not running or loader.frames.is_empty():
		return

	_accum_ms += delta * 1000.0
	var frame_ms := 1000.0 / maxf(current_fps, 1.0)
	var steps_due := floori(_accum_ms / frame_ms)
	if steps_due <= 0:
		return

	var steps_to_run := mini(steps_due, MAX_SCORE_STEPS_PER_TICK)
	_accum_ms = fmod(_accum_ms, frame_ms)
	for _step in steps_to_run:
		var movie_before := loader.movie_name
		game_step()
		if loader.movie_name != movie_before:
			_accum_ms = 0.0
			break
```

- [ ] **Step 3: Run the focused regression suite**

Run:

```bash
godot --headless --path . --script tests/test_director_runtime.gd
```

Expected: exit code `0` and `PASS: DirectorRuntime regression suite`.

- [ ] **Step 4: Check the project for parse and resource-loading errors**

Run:

```bash
godot --headless --path . --editor --quit
```

Expected: exit code `0`, with no `SCRIPT ERROR`, parse error, or missing project-resource error.

- [ ] **Step 5: Commit the tested runtime fix**

```bash
git add director/director_runtime.gd tests/test_director_runtime.gd
git commit -m "fix: bound Godot score catch-up"
```

### Task 3: Document and Manually Verify the Playback Contract

**Files:**
- Modify: `docs/ENGINE.md:17-29`

- [ ] **Step 1: Document bounded score scheduling**

Add this paragraph after the game-loop list:

```markdown
The score clock executes at most three catch-up steps per Godot process tick.
Long render or asset-loading stalls discard excess whole-step backlog, preventing
cutscenes from fast-forwarding. A movie change ends catch-up so the destination
movie starts with a fresh timing accumulator.
```

- [ ] **Step 2: Re-run automated verification**

Run:

```bash
godot --headless --path . --script tests/test_director_runtime.gd
godot --headless --path . --editor --quit
git diff --check
```

Expected: both Godot commands exit `0`, the regression suite prints its PASS message, and `git diff --check` produces no output.

- [ ] **Step 3: Verify the user-visible boot sequence**

Run:

```bash
godot --path .
```

Then click New Game and verify:

1. EXODUS appears instead of DAY1.
2. EXODUS animates and plays audio at score timing.
3. DAY1 loads only when EXODUS finishes.
4. With intro skipping enabled, pressing Esc still moves to DAY1 intentionally.

Close the game after verification.

- [ ] **Step 4: Commit the documentation**

```bash
git add docs/ENGINE.md
git commit -m "docs: describe bounded score scheduling"
```
