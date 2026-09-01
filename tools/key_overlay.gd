extends SceneTree
## The touch controls, driven on a real scene, from a desktop.
##
##   godot --headless --path . --audio-driver Dummy --script tools/key_overlay.gd -- \
##       --root piposh2 --boot PIP2DATA/ARCADE2.dir --touch-input --verbose
##   godot --headless --path . --audio-driver Dummy --script tools/key_overlay.gd -- \
##       --root rating --boot arcade1.dir --touch-input
##   godot --headless --path . --audio-driver Dummy --script tools/key_overlay.gd -- \
##       --root piposh --boot PIPDATA/ROULLETE.dir --touch-input
##
## **`--touch-input` is what makes this testable at all**, and it is the reason the
## flag exists rather than a debug convenience: it forces the whole mobile input
## path on regardless of the platform, and the path is driven by ordinary mouse
## events -- which is precisely what Godot's own emulation turns a finger into
## (`docs/MOBILE.md`, "Input"). So a mouse drag across the stick is the same event
## sequence a thumb produces, through the same code, and this harness is a real
## rehearsal rather than a test of the drawing.
##
## One movie per run, because the boot movie is a property of the process
## (`DirectorPaths._override_boot`); a second `instantiate()` in the same run would
## open the first title again, which is the shape of harness that passes while
## measuring the wrong thing twice.
##
## Three scenes, chosen because they are the three arms the design has, and
## `gate.sh` runs all three:
##
##   `piposh2 PIP2DATA/ARCADE2.dir`  `stg1go` is **entirely** directional -- Up/W,
##       Right/E, Down/D and nothing else -- so it gets the stick, and it is where
##       the steering is proved: a drag commits a direction, a *held* drag repeats
##       it, letting go stops it.
##   `rating arcade1.dir`            three directions **and** Escape, so the stick
##       and the row are on screen together. **The most valuable entry in the file**,
##       because it is the only one where the two controls have to coexist: the
##       stick answers its directions, the button answers Escape, neither swallows
##       the other's input, and the chip is offered because both modes can serve the
##       scene.
##   `rating navigate.dir`           Escape and F10 and **no direction anywhere in
##       the movie**, so the row is the whole answer and no chip is drawn. Chosen
##       from the census by rule rather than by eye: the movie with the most
##       named-key scenes (10) and not one directional scene in it. Three of
##       Rating's navigation variants tie on that count; this is the one
##       `new_game_reset` already boots, so a decode regression in the container
##       shows up in two entries rather than one.
##   `piposh PIPDATA/ROULLETE.dir`   an editable field, so neither control appears
##       and the system keyboard is left to `text_focus.gd`.
##
## **Which arm runs is decided from the split, not from the movie's name.** A movie
## named in a gate entry that quietly stopped producing a stick would otherwise take
## the row arm and pass, having asserted the opposite of what it is there for; so
## the shape is asserted first and the arm follows it.
##
## What is asserted, and why each one is a different way to be wrong on a phone:
##
##   1. **The flag turned it on.** Not the machine -- so a pass on a developer's
##      touchscreen laptop cannot be mistaken for a pass of the flag.
##   2. **The demand is derived from the movie**, not written here. A hand-written
##      table is the failure mode the whole design avoids, so what is asserted is
##      the *relationship* a table could not fake: every control offered is a key
##      this movie's own scripts test, and there are fewer controls than literals
##      because alternates fold.
##   3. **The stick rule agrees with the scene** -- a stick is offered exactly where
##      a direction participates, which is the rule
##      `KeyAffordance.STICK_NEEDS_EVERY_ACTION` selects.
##   4. **A drag on the stick reaches Lingo** as the right `the keyCode`.
##   5. **A held drag repeats**, which is the whole mapping: a stick pushed over is
##      a key held down. Counted, not sampled -- one press proves the edge and says
##      nothing about the hold, and steering is the hold.
##   6. **Letting go stops it**, or a character walks into a wall for ever.
##   7. **Pushing a way the scene has no key for sends nothing**, rather than the
##      nearest direction.
##   8. **The two controls partition the scene and do not fight**: every action is
##      on exactly one of them, driving the stick never fires a button, and tapping
##      a button never leaves a direction held.
##   9. **The mode chip switches** -- and switching folds *everything* into the row,
##      directions included -- and the choice survives a room change.
##  10. **The stick can be picked up and moved**, and that survives a room change
##      too -- and a drive never triggers a pick-up, which is the ambiguity the
##      long press exists to avoid.
##  11. **No chip where there is nothing to switch to**, or it is a control that
##      does nothing.
##  12. **A press outside every control reaches the movie**, or the overlay has
##      quietly taken the stage and every hotspot with it.
##
## A root that is not in this checkout is reported and skipped: `games/` is six
## private submodules, and an entry that can only pass against a corpus somebody may
## not have gates nothing (`AGENTS.md`). Skipping still records a check, because
## `harness.gd:finish` fails a run that asserted nothing.
##
## Title-agnostic: every number it asserts comes out of the movie it was pointed at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const KeyAffordance := preload("res://scenes/preview/key_affordance.gd")
const GameConfig := preload("res://director/game_config.gd")
const Keys := preload("res://director/director_keys.gd")
const Paths := preload("res://director/director_paths.gd")

## How long to wait for a repeat before calling it absent, and how many real frames
## that is worth. Waited on the condition under a ceiling rather than for a fixed
## number of frames, which is the fix `bugs.md` 41 records for exactly this shape of
## flake: a fixed budget passes on a fast machine and fails on a loaded one.
const REPEAT_BUDGET_FRAMES := 240


func _init() -> void:
	var args := Args.parse()
	var verbose := Args.flag(args, "verbose")

	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root" % Paths.CONFIG_PATH)
		quit(1)
		return

	var case_name := "%s %s" % [str(paths.root).get_file(), paths.boot_movie]
	var h := Harness.new()
	h.begin(case_name)

	if not DirAccess.dir_exists_absolute(paths.root):
		h.check("%s: corpus present" % case_name, true,
			"%s is not in this checkout, skipped" % paths.root)
		h.complete(case_name)
		quit(h.finish("the touch controls, on a scene that needs keys"))
		return

	# 1 -- the flag, before anything is instantiated, because `_key_overlay` is a
	# field initialiser on the preview and reads `enabled()` as the node is built.
	h.check("%s: --touch-input is what turned the overlay on" % case_name,
		KeyAffordance.forced_by_flag() and KeyAffordance.enabled(),
		"flag %s, enabled %s, and this machine reports a mouse (%s)" % [
			KeyAffordance.forced_by_flag(), KeyAffordance.enabled(),
			DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)])

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var score = preview.get("_score")
	if score == null:
		h.check("%s: the movie loads" % case_name, false, "no score")
		h.complete(case_name)
		quit(h.finish("the touch controls, on a scene that needs keys"))
		return

	h.check("%s: the preview took the flag" % case_name, bool(preview._key_overlay),
		"`_key_overlay` is %s on the node `_paint` and `_input` branch on" % preview._key_overlay)

	# **The frame is found, not named.** A frame number written into a gate entry is
	# a per-title constant that rots the first time anything about the score moves,
	# which is the same failure this whole feature exists to avoid one level up. So
	# unless `--frame` says otherwise the run picks the frame of this movie that
	# demands the most, and prints which one it chose.
	var frame := Args.number(args, "frame", -1)
	if frame < 0:
		frame = _busiest_frame(preview, int(score.frame_count))
	frame = clampi(frame, 0, maxi(int(score.frame_count) - 1, 0))
	preview._index = frame

	KeyAffordance.set_mode(KeyAffordance.Mode.STICK)
	var demand: Dictionary = KeyAffordance.demand_at(preview, frame)
	var shape: int = KeyAffordance.classify(demand)
	var split: Dictionary = KeyAffordance.stick_actions(preview)
	var rows: Array = KeyAffordance.buttons(preview)
	var literals: int = (demand["codes"] as Dictionary).size() \
		+ (demand["chars"] as Dictionary).size()
	var actions: int = (KeyAffordance.actions_of(demand) as Array).size()
	if verbose:
		print("   %s frame %d: %s -- %d literal(s), %d action(s); stick %d, buttons %d" % [
			paths.boot_movie, frame, KeyAffordance.SHAPE_NAMES[shape],
			literals, actions, (split["stick"] as Array).size(), rows.size()])
		for entry in split["stick"]:
			print("      stick  %-10s %-8s %s" % [
				entry["label"], entry["dir"], OS.get_keycode_string(entry["keycode"])])
		for row in rows:
			print("      button %-10s -> %s" % [
				row["label"], OS.get_keycode_string(row["keycode"])])

	if shape == KeyAffordance.Shape.TEXT:
		_typed_text(h, case_name, preview, frame, demand, rows)
		h.complete(case_name)
		quit(h.finish("the touch controls, on a scene that needs keys"))
		return

	# 2 -- the derivation.
	h.check("%s: the movie's own scripts asked for a key" % case_name,
		bool(demand["asks"]) and (not rows.is_empty() or not (split["stick"] as Array).is_empty()),
		"%s on frame %d: %d stick direction(s), %d button(s)" % [
			KeyAffordance.SHAPE_NAMES[shape], frame,
			(split["stick"] as Array).size(), rows.size()])
	h.check("%s: folding never invents an action" % case_name, actions <= literals,
		"%d literal(s) -> %d action(s)" % [literals, actions])

	var offered: Array = (split["stick"] as Array) + rows
	var stray: Array[String] = []
	for entry in offered:
		var mac := int(Keys.MAC_CODES.get((entry as Dictionary)["keycode"], -1))
		var ch := OS.get_keycode_string((entry as Dictionary)["keycode"]).to_lower()
		if not (demand["codes"] as Dictionary).has(mac) \
				and not (demand["chars"] as Dictionary).has(ch):
			stray.append(str((entry as Dictionary)["label"]))
	h.check("%s: every control is a key this movie tests" % case_name, stray.is_empty(),
		"%d of %d not tested anywhere in the movie: %s" % [
			stray.size(), offered.size(), ", ".join(stray)])

	# 3 -- the rule itself, asked of the demand rather than of the split so the two
	# sides of the comparison are independent. Every gate entry reaches this, from
	# whichever of the four shapes it is: a rule asserted only where it says yes is
	# not asserted.
	var wanted_stick := _any_directional(demand) \
		and not (KeyAffordance.STICK_NEEDS_EVERY_ACTION and not _all_directional(demand))
	h.check("%s: the stick rule agrees with what this scene needs" % case_name,
		bool(split["possible"]) == wanted_stick,
		"possible %s, a direction participates %s, all directional %s -> %s" % [
			split["possible"], _any_directional(demand), _all_directional(demand),
			"stick" if bool(split["possible"]) else "row only"])

	# **The arm follows the shape, not the movie's name.** A gate entry whose movie
	# quietly stopped producing a stick would otherwise take the row arm and pass,
	# having asserted the opposite of what it is there for.
	var has_stick := not (split["stick"] as Array).is_empty()
	var has_row := not rows.is_empty()
	if has_stick and has_row:
		await _both_case(h, case_name, preview, split, rows, actions, frame, verbose)
	elif has_stick:
		await _stick_case(h, case_name, preview, split, frame, verbose)
	elif has_row:
		await _row_case(h, case_name, preview, rows, frame)
	else:
		h.check("%s: a scene that asks for a key offers something" % case_name, false,
			"neither control was drawn on a frame whose shape is %s"
			% KeyAffordance.SHAPE_NAMES[shape])

	# 12 -- the stage is still the movie's everywhere else. The top-left corner,
	# which neither the stick (bottom-left), the row (bottom) nor the chip (above
	# the row) can reach at any stage size.
	var elsewhere: bool = KeyAffordance.pointer(preview, true, Vector2(2, 2))
	h.check("%s: a press outside every control reaches the movie" % case_name, not elsewhere,
		"the overlay claimed a press at the top-left corner")

	_restore(root)
	_switch_case(h, case_name)
	await _second_movie_case(h, case_name, preview)
	h.complete(case_name)
	quit(h.finish("the touch controls, on a scene that needs keys"))


## Whether a direction participates in this frame's demand at all, and whether every
## action is one.
##
## Both are asked of the **demand** rather than of the split, so the check comparing
## them to `possible` has two independent sides and is not a tautology. That matters
## more than it looks: the split is what the rule produced, and a rule that had
## drifted would agree with itself perfectly.
func _any_directional(demand: Dictionary) -> bool:
	for action in KeyAffordance.actions_of(demand):
		var keycode := KeyAffordance.keycode_of(action)
		if keycode == KEY_NONE:
			continue
		if KeyAffordance.ARROW_CODES.has(int(Keys.MAC_CODES.get(keycode, -1))):
			return true
	return false


func _all_directional(demand: Dictionary) -> bool:
	var any := false
	for action in KeyAffordance.actions_of(demand):
		var keycode := KeyAffordance.keycode_of(action)
		if keycode == KEY_NONE:
			continue
		if KeyAffordance.ARROW_CODES.has(int(Keys.MAC_CODES.get(keycode, -1))):
			any = true
		else:
			return false
	return any


## The typing arm: `text_focus.gd` raises the system keyboard, and neither control
## appears over the top of it.
func _typed_text(h: Harness, case_name: String, preview: Node, frame: int,
		demand: Dictionary, rows: Array) -> void:
	h.check("%s: recognised as a typed-text scene" % case_name,
		bool(demand["text"]), "an editable field is on stage at frame %d" % frame)
	h.check("%s: a typed-text scene draws no touch controls" % case_name,
		rows.is_empty() and not KeyAffordance.stick_available(preview),
		"%d button(s), stick %s" % [rows.size(), KeyAffordance.stick_available(preview)])
	_restore(root)


## The stick arm: steering, held repeat, release, a direction the scene does not
## have, the mode chip, and the pick-up.
func _stick_case(h: Harness, case_name: String, preview: Node, split: Dictionary,
		frame: int, verbose: bool) -> void:
	var centre: Vector2 = KeyAffordance.stick_centre(preview)
	var first: Dictionary = (split["stick"] as Array)[0]
	var dir: Vector2i = first["dir"]
	var expected := int(Keys.MAC_CODES.get(first["keycode"], -1))
	# Well past the dead zone, and along the action's own axis, so the direction the
	# stick commits is this entry's and not a neighbour's.
	var pushed := centre + Vector2(dir) * (KeyAffordance.STICK_RADIUS - 4.0)

	# 3 -- a drag on the stick reaches Lingo.
	preview._host.key_code = -1
	var claimed: bool = KeyAffordance.pointer(preview, true, centre)
	var moved: bool = KeyAffordance.motion(preview, pushed)
	await _step(preview, frame)
	await _step(preview, frame)
	h.check("%s: the stick claims a press and the drag that follows" % case_name,
		claimed and moved, "press at %v, drag to %v" % [centre, pushed])
	h.check("%s: a drag on the stick reaches `the keyCode`" % case_name,
		int(preview._host.key_code) == expected,
		"pushed %s, expected the keyCode %d, read %d" % [
			first["label"], expected, int(preview._host.key_code)])

	# 4 -- **the hold repeats.** Counted from the movie's own dispatch tally, which
	# is what a script polling `the keyCode` actually sees, and waited on the
	# condition under a frame ceiling rather than for a fixed number of frames.
	var before := int((preview._sent as Dictionary).get("keyDown", 0))
	var after := before
	var waited := 0
	while waited < REPEAT_BUDGET_FRAMES:
		KeyAffordance.tick(preview)
		await _step(preview, frame)
		waited += 1
		after = int((preview._sent as Dictionary).get("keyDown", 0))
		if after - before >= 2:
			break
	if verbose:
		print("   held for %d frame(s): keyDown %d -> %d" % [waited, before, after])
	h.check("%s: a held stick repeats the key" % case_name, after - before >= 2,
		"%d extra keyDown in %d frame(s) of holding -- a stick pushed over is a key held down"
		% [after - before, waited])

	# 5 -- letting go stops it.
	var released: bool = KeyAffordance.pointer(preview, false, pushed)
	await _step(preview, frame)
	var settled := int((preview._sent as Dictionary).get("keyDown", 0))
	var idle := 0
	while idle < 30:
		KeyAffordance.tick(preview)
		await _step(preview, frame)
		idle += 1
	h.check("%s: letting go stops the repeat" % case_name,
		released and int((preview._sent as Dictionary).get("keyDown", 0)) == settled,
		"%d more keyDown in %d frame(s) after release" % [
			int((preview._sent as Dictionary).get("keyDown", 0)) - settled, idle])

	# 6 -- a direction the scene has no key for sends nothing. Found rather than
	# assumed: the four axes minus the ones this scene actually uses.
	var missing := _missing_direction(split)
	if missing == Vector2i.ZERO:
		h.check("%s: a direction the scene lacks sends nothing" % case_name, true,
			"this scene uses all four directions, so there is none to test")
	else:
		preview._host.key_code = -1
		KeyAffordance.pointer(preview, true, centre)
		KeyAffordance.motion(preview, centre + Vector2(missing) * (KeyAffordance.STICK_RADIUS - 4.0))
		await _step(preview, frame)
		await _step(preview, frame)
		var quiet := int(preview._host.key_code) == -1
		KeyAffordance.pointer(preview, false, centre)
		h.check("%s: a direction the scene lacks sends nothing" % case_name, quiet,
			"pushed %v, `the keyCode` read %d" % [missing, int(preview._host.key_code)])

	# 7 -- the chip switches, and the choice survives a room change.
	h.check("%s: the mode chip is offered" % case_name,
		KeyAffordance.toggle_available(preview),
		"a scene with a stick has two answers, so there is something to switch")
	var chip: Rect2 = KeyAffordance.toggle_rect(preview)
	var took: bool = KeyAffordance.pointer(preview, true, chip.get_center())
	h.check("%s: the chip switches to the button row" % case_name,
		took and KeyAffordance.mode() == KeyAffordance.Mode.BUTTONS
			and not KeyAffordance.stick_available(preview)
			and not KeyAffordance.buttons(preview).is_empty(),
		"mode %s, stick %s, %d button(s)" % [
			KeyAffordance.mode(), KeyAffordance.stick_available(preview),
			KeyAffordance.buttons(preview).size()])

	# 8 -- the stick can be moved, and a drive never triggers a pick-up. Ordered
	# this way on purpose: the pick-up is armed by a hold that the *previous* checks
	# have already shown does not happen while driving.
	KeyAffordance.set_mode(KeyAffordance.Mode.STICK)
	var was: Vector2 = KeyAffordance.stick_centre(preview)
	KeyAffordance.pointer(preview, true, was)
	# A drive first: straight out past the dead zone, which must *not* pick the
	# stick up however long it is then held.
	KeyAffordance.motion(preview, was + Vector2(dir) * (KeyAffordance.STICK_RADIUS - 4.0))
	# Held well past `PICKUP_MS` — the point is that the timer never even starts
	# once a direction is committed, so waiting longer than it must change nothing.
	var drove_until := Time.get_ticks_msec() + KeyAffordance.PICKUP_MS * 2
	var drove := 0
	while drove < REPEAT_BUDGET_FRAMES and Time.get_ticks_msec() < drove_until:
		KeyAffordance.tick(preview)
		await _step(preview, frame)
		drove += 1
	var after_drive: Vector2 = KeyAffordance.stick_centre(preview)
	var drove_picked := KeyAffordance.picked_up()
	KeyAffordance.pointer(preview, false, was)
	h.check("%s: driving never picks the stick up" % case_name,
		after_drive == was and not drove_picked,
		"held a direction for %d frame(s), past %d ms of pick-up timer: picked up %s, stick at %v"
		% [drove, KeyAffordance.PICKUP_MS, drove_picked, after_drive])

	# Now the pick-up: press, hold *still* past `PICKUP_MS`, then drag.
	KeyAffordance.pointer(preview, true, was)
	var arming := 0
	while arming < REPEAT_BUDGET_FRAMES and not KeyAffordance.picked_up():
		KeyAffordance.tick(preview)
		await _step(preview, frame)
		arming += 1
	var target := Vector2(200, 150)
	KeyAffordance.motion(preview, target)
	KeyAffordance.pointer(preview, false, target)
	var moved_to: Vector2 = KeyAffordance.stick_centre(preview)
	h.check("%s: a long press picks the stick up and the drag moves it" % case_name,
		moved_to.distance_to(target) < 1.0 and moved_to != was,
		"armed after %d frame(s), stick %v -> %v" % [arming, was, moved_to])

	# Both preferences through a room change.
	KeyAffordance.set_mode(KeyAffordance.Mode.BUTTONS)
	var kept_mode := KeyAffordance.mode()
	KeyAffordance.forget()
	h.check("%s: the mode and the stick position survive a room change" % case_name,
		KeyAffordance.mode() == kept_mode
			and KeyAffordance.stick_centre(preview).distance_to(target) < 1.0,
		"after dropping every per-movie cache: mode %s, stick %v" % [
			KeyAffordance.mode(), KeyAffordance.stick_centre(preview)])


## The **coexistence** arm: a scene with directions *and* a named key, where both
## controls are on screen at once.
##
## This is the arm that earns its place. The other three each prove one control in
## isolation, and isolation is not where a two-control design goes wrong -- it goes
## wrong where they overlap: a stick that eats the press meant for the Escape
## button, a button tap that leaves a direction latched, an action that lands on
## both or on neither. So what is asserted here is the *partition* and the
## non-interference, not the presence.
func _both_case(h: Harness, case_name: String, preview: Node, split: Dictionary,
		rows: Array, actions: int, frame: int, verbose: bool) -> void:
	var stick: Array = split["stick"]
	h.check("%s: the stick and the row are on screen together" % case_name,
		not stick.is_empty() and not rows.is_empty(),
		"%d direction(s) on the stick, %d button(s) beside it" % [stick.size(), rows.size()])

	# **Every action on exactly one control.** Counted rather than eyeballed: an
	# action that reached both would be a key the player can send two ways, and one
	# that reached neither is a control the scene needs and does not have.
	# **Read off the split, not off `buttons()`.** The laid-out rows carry only
	# `{rect, label, keycode}` -- `dir` is dropped once a button has a rectangle,
	# because a rectangle is all a tap needs. Asking them which way they point reads
	# a key that is not there, which is how the first version of this check reported
	# "row free of directions false" for a row holding nothing but Escape.
	var named: Array = split["buttons"]
	var seen: Dictionary = {}
	var twice: Array[String] = []
	for entry in (stick + named):
		var label := str((entry as Dictionary)["label"])
		if seen.has(label):
			twice.append(label)
		seen[label] = true
	h.check("%s: every action is on exactly one control" % case_name,
		twice.is_empty() and seen.size() == actions and named.size() == rows.size(),
		"%d action(s) -> %d stick + %d row = %d distinct, %d duplicated" % [
			actions, stick.size(), named.size(), seen.size(), twice.size()])
	h.check("%s: the stick took the directions and the row took the rest" % case_name,
		_all_dirs(stick) and _no_dirs(named),
		"stick all directional %s, row free of directions %s" % [
			_all_dirs(stick), _no_dirs(named)])

	# Driving the stick must not fire a button. Counted from the movie's own
	# dispatch tally against the *button's* key, which is the only way to see a
	# press that went to the wrong control.
	var button: Dictionary = rows[0]
	var button_code := int(Keys.MAC_CODES.get(button["keycode"], -1))
	var centre: Vector2 = KeyAffordance.stick_centre(preview)
	var first: Dictionary = stick[0]
	var dir: Vector2i = first["dir"]
	var stick_code := int(Keys.MAC_CODES.get(first["keycode"], -1))

	preview._host.key_code = -1
	KeyAffordance.pointer(preview, true, centre)
	KeyAffordance.motion(preview, centre + Vector2(dir) * (KeyAffordance.STICK_RADIUS - 4.0))
	await _step(preview, frame)
	await _step(preview, frame)
	var drove_code := int(preview._host.key_code)
	KeyAffordance.pointer(preview, false, centre)
	await _step(preview, frame)
	h.check("%s: driving the stick sends its direction and not the button" % case_name,
		drove_code == stick_code and drove_code != button_code,
		"pushed %s, expected the keyCode %d, read %d (the button is %d)" % [
			first["label"], stick_code, drove_code, button_code])

	# ...and tapping the button must not leave a direction held. `picked_up` and the
	# repeat both key off the same gesture state, so a button tap that latched one
	# would keep steering after the finger had gone.
	preview._host.key_code = -1
	var took: bool = KeyAffordance.pointer(preview, true, (button["rect"] as Rect2).get_center())
	await _step(preview, frame)
	await _step(preview, frame)
	var tapped_code := int(preview._host.key_code)
	var before := int((preview._sent as Dictionary).get("keyDown", 0))
	var idle := 0
	while idle < 40:
		KeyAffordance.tick(preview)
		await _step(preview, frame)
		idle += 1
	h.check("%s: tapping the button sends its key and holds nothing" % case_name,
		took and tapped_code == button_code
			and int((preview._sent as Dictionary).get("keyDown", 0)) == before,
		"tapped %s, expected the keyCode %d, read %d; %d stray keyDown in %d idle frame(s)" % [
			button["label"], button_code, tapped_code,
			int((preview._sent as Dictionary).get("keyDown", 0)) - before, idle])

	# The chip is offered, and switching folds *everything* into the row -- the
	# directions included, which is what makes BUTTONS a complete answer rather than
	# a partial one.
	h.check("%s: the chip is offered where both controls could serve" % case_name,
		KeyAffordance.toggle_available(preview), "a scene with both has two answers")
	var chip: Rect2 = KeyAffordance.toggle_rect(preview)
	KeyAffordance.pointer(preview, true, chip.get_center())
	var folded: Array = KeyAffordance.buttons(preview)
	h.check("%s: switching folds every action into the row" % case_name,
		KeyAffordance.mode() == KeyAffordance.Mode.BUTTONS
			and not KeyAffordance.stick_available(preview)
			and folded.size() == actions,
		"mode %s, stick %s, %d button(s) for %d action(s)" % [
			KeyAffordance.mode(), KeyAffordance.stick_available(preview),
			folded.size(), actions])
	KeyAffordance.pointer(preview, true, KeyAffordance.toggle_rect(preview).get_center())
	h.check("%s: switching back restores the split" % case_name,
		KeyAffordance.mode() == KeyAffordance.Mode.STICK
			and KeyAffordance.stick_available(preview)
			and KeyAffordance.buttons(preview).size() == rows.size(),
		"mode %s, stick %s, %d button(s)" % [
			KeyAffordance.mode(), KeyAffordance.stick_available(preview),
			KeyAffordance.buttons(preview).size()])
	if verbose:
		print("   coexistence: stick %d, row %d, %d action(s) total" % [
			stick.size(), rows.size(), actions])


func _all_dirs(entries: Array) -> bool:
	for entry in entries:
		if (entry as Dictionary)["dir"] == Vector2i.ZERO:
			return false
	return not entries.is_empty()


func _no_dirs(entries: Array) -> bool:
	for entry in entries:
		if (entry as Dictionary)["dir"] != Vector2i.ZERO:
			return false
	return true


## The **row only** arm: a scene with no direction anywhere, so the row is the whole
## answer and no chip is drawn.
func _row_case(h: Harness, case_name: String, preview: Node, rows: Array,
		frame: int) -> void:
	h.check("%s: a scene with no direction gets the row and no stick" % case_name,
		not rows.is_empty() and not KeyAffordance.stick_available(preview),
		"%d button(s), stick %s" % [rows.size(), KeyAffordance.stick_available(preview)])
	h.check("%s: no mode chip where there is nothing to switch to" % case_name,
		not KeyAffordance.toggle_available(preview),
		"a scene the stick cannot serve has one answer, so the chip would do nothing")

	var target: Dictionary = rows[0]
	var expected := int(Keys.MAC_CODES.get(target["keycode"], -1))
	preview._host.key_code = -1
	var claimed: bool = KeyAffordance.pointer(preview, true, (target["rect"] as Rect2).get_center())
	await _step(preview, frame)
	await _step(preview, frame)
	h.check("%s: a tap on a button is claimed by the overlay" % case_name, claimed,
		"tapped %s at %v" % [target["label"], (target["rect"] as Rect2).get_center()])
	h.check("%s: `the keyCode` answers the button that was tapped" % case_name,
		int(preview._host.key_code) == expected,
		"tapped %s, expected the keyCode %d, read %d" % [
			target["label"], expected, int(preview._host.key_code)])


## One real frame, with the playhead put back where the run is measuring.
##
## **The movie keeps playing while a harness waits, and that is what this is for.**
## The first version of the stick case awaited plain frames, and `PIP2DATA/ARCADE2.dir`
## ran on from frame 27 to frame 1046 during the 35 frames spent proving the repeat
## -- a `gameover` span that needs no direction at all. Four checks then failed
## saying the chip was not offered and the stick could not be picked up, which was
## true of frame 1046 and said nothing about the scene under test. `tools/hotspots.gd`
## pins `_index` for the same reason and records the same hazard.
##
## Re-pinned on both sides of the await, because the frame loop can advance during
## it and anything read afterwards would be reading the wrong frame.
func _step(preview: Node, frame: int) -> void:
	preview._index = frame
	await process_frame
	preview._index = frame


## A direction this scene has no key for, or zero when it uses all four.
func _missing_direction(split: Dictionary) -> Vector2i:
	var have: Array[Vector2i] = []
	for entry in split["stick"]:
		have.append((entry as Dictionary)["dir"])
	for candidate in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if not have.has(candidate):
			return candidate
	return Vector2i.ZERO


## Put both switches back where the machine had them, on **every** preview in the
## tree rather than only the one this run drives: a movie can `open(window("x"))`,
## and `director_preview.gd` parents a second whole preview under the first. One
## constructed while the overlay was forced on took `true` from its own field
## initialiser.
##
## `force(0)` rather than `force(-1)`: -1 hands the decision back to `enabled()`,
## which would read `--touch-input` off this run's own command line and turn it
## straight back on. 0 is "off, and stay off", which is what a finished harness wants.
func _restore(from: Node) -> void:
	KeyAffordance.force(0)
	_clear(from)


func _clear(node: Node) -> void:
	if node.get("_key_overlay") != null:
		node.set("_key_overlay", false)
	for child in node.get_children():
		_clear(child)


## The frame of this movie whose scripts demand the most actions, or 0 if none do.
##
## Walks `demand_at` once per frame, which is cheap because the spans and the
## movie-wide demand are built by the first call and every later one is a range test
## over them. **A frame the stick can serve wins outright**, so a movie that has one
## directional scene among a hundred is measured on the scene this feature is for;
## after that the busiest wins, and the first of equals, so a failure names a frame
## somebody can go and look at.
func _busiest_frame(preview: Node, frame_count: int) -> int:
	var best := 0
	var most := -1
	for i in frame_count:
		var d: Dictionary = KeyAffordance.demand_at(preview, i)
		if not bool(d["asks"]):
			continue
		# A typing scene beats everything, because it is the one shape whose whole
		# assertion is that both controls decline -- a run that picked an ordinary
		# frame of the roulette would never reach the check the roulette is here for.
		if bool(d.get("text", false)):
			return i
		# A frame the stick can serve wins outright, so a movie with one directional
		# scene among a hundred is measured on the scene this feature is for. Under
		# the loose rule that is "a direction participates", which is also what puts
		# `arcade1.dir` on its coexistence frame rather than on a cutscene that
		# needs Escape alone.
		if _any_directional(d):
			return i
		var n: int = (KeyAffordance.actions_of(d) as Array).size()
		if n > most:
			most = n
			best = i
	return best


## The launcher's switch, which is the only way to reach these controls from a
## desktop without a command line.
##
## **Written to a file of this harness's own and never to the person's overlay.**
## `GameConfig.OVERLAY_PATH` is a real setting a real person edited from the
## launcher, and a gate entry that rewrote it would silently change how their
## next run behaves. `config_switch` takes `merged`'s own `overlay_path` seam for
## exactly this, and an explicit path is applied whether or not there is a
## display -- which matters, because a headless run ignores the real overlay by
## design and this branch would otherwise be unassertable in the gate.
##
## Asserted on `config_switch` rather than on `enabled()`, because `enabled()`
## caches in a `static var` and this harness has already forced it: re-deriving
## it here would measure the cache, not the rule. The wiring from one to the
## other is three lines in `enabled()` and is read there.
func _switch_case(h: Harness, case_name: String) -> void:
	var path := "user://key_overlay_switch_probe.cfg"
	for wanted in KeyAffordance.SWITCH_VALUES:
		var cfg := ConfigFile.new()
		cfg.set_value(KeyAffordance.CONFIG_SECTION, KeyAffordance.CONFIG_KEY, wanted)
		if cfg.save(path) != OK:
			h.check("%s: the switch probe could write its own overlay" % case_name,
				false, path)
			return
		GameConfig.invalidate()
		h.check("%s: `[qol] touch_controls = %s` reads back as itself"
			% [case_name, wanted],
			KeyAffordance.config_switch(path) == wanted,
			"read %s" % KeyAffordance.config_switch(path))
	# A value nobody wrote, and a missing key, both mean "decide from the device".
	var junk := ConfigFile.new()
	junk.set_value(KeyAffordance.CONFIG_SECTION, KeyAffordance.CONFIG_KEY, "sometimes")
	junk.save(path)
	GameConfig.invalidate()
	h.check("%s: an unknown value falls back to auto" % case_name,
		KeyAffordance.config_switch(path) == KeyAffordance.AUTO,
		"read %s" % KeyAffordance.config_switch(path))
	var empty := ConfigFile.new()
	empty.save(path)
	GameConfig.invalidate()
	h.check("%s: and so does an overlay that says nothing" % case_name,
		KeyAffordance.config_switch(path) == KeyAffordance.AUTO,
		"read %s" % KeyAffordance.config_switch(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameConfig.invalidate()


## A movie reached by `go to movie` gets its **own** key map.
##
## **This is the check that was missing, and its absence hid the feature's worst
## bug for as long as it existed.** `map_for` caches per movie, and the key it
## cached under was `movie_path()` -- Director's `the moviePath`, which is the
## *folder*. Every one of `rating`'s 124 containers shares one folder, so the
## first movie a session opened built the map and every movie after it was
## answered with that one's keys. `mainmenu.dir` needs none, so the overlay was
## blank for the whole title.
##
## Every existing entry booted straight into the movie it tested -- `--boot
## arcade1.dir` builds arcade1's map first -- so the cache always held the right
## answer by accident. **A per-movie entry can never see this.** Only going
## somewhere after booting can, which is what this does.
##
## Asserted as "the two maps differ", not as "the second has keys": a title where
## both movies happen to want the same keys would be a fixture that proves
## nothing, and this says so rather than passing quietly.
func _second_movie_case(h: Harness, case_name: String, preview: Node) -> void:
	var second: String = Args.text(Args.parse(), "second")
	if second == "":
		return
	var first := str(preview.call("movie_name"))
	var before: Dictionary = KeyAffordance.map_for(preview)
	var before_spans := (before["spans"] as Array).size()
	preview.call("lingo_go_movie", second, null)
	var waited := 0
	while waited < 600 and str(preview.call("movie_name")).to_lower() == first.to_lower():
		await process_frame
		waited += 1
	for i in 20:
		await process_frame
	var now := str(preview.call("movie_name"))
	h.check("%s: `go to movie %s` arrived" % [case_name, second],
		now.to_lower() != first.to_lower(), "still on %s after %d ticks" % [now, waited])
	if now.to_lower() == first.to_lower():
		return
	var after: Dictionary = KeyAffordance.map_for(preview)
	var after_spans := (after["spans"] as Array).size()
	_steady_case(h, case_name, preview)
	h.check("%s: the second movie built its own key map" % case_name,
		after_spans != before_spans,
		"%s has %d span(s), %s has %d -- equal counts mean the cache answered "
		% [first, before_spans, now, after_spans]
		+ "for the wrong movie, or the two movies genuinely agree and this "
		+ "fixture proves nothing")


## A key a scene waits for is offered on **every** frame of the wait, not on the
## one frame that happens to poll for it.
##
## The owner's second report on the same movie: "j is blinking". `BATZEGOZ.dir`'s
## conversation asks for H, then J, then Q, and each is an `on exitFrame` on a
## single frame -- 87, 91, 95 -- with `go(marker(0))` three frames later. The
## playhead cycles four frames, the button existed on one, and it flashed at a
## quarter duty.
##
## **Checked over every marker section, not over the first frame that asks.** The
## first version of this looked at the first demanding frame and its section, and
## passed with the fix disabled: that frame's script already spanned six frames on
## its own, so the check never reached a single-frame poll and proved nothing. It
## is the `porting-fidelity-verification` failure twice in one file -- an
## assertion that holds for a reason unrelated to what it is named after.
##
## Reported as the count of sections that flicker, so the failure names them.
func _steady_case(h: Harness, case_name: String, preview: Node) -> void:
	var score = preview.get("_score")
	var labels = preview.get("_labels")
	if score == null or labels == null or labels.markers.is_empty():
		return
	var starts: Array[int] = []
	for marker in labels.markers:
		var at := int((marker as Dictionary).get("frame", -1))
		if at >= 0:
			starts.append(at)
	starts.sort()
	if starts.is_empty():
		return
	var last := int(score.frame_count) - 1
	var uneven := PackedStringArray()
	var asked := 0
	for i in starts.size():
		var begin: int = starts[i]
		var finish: int = (starts[i + 1] - 1) if i + 1 < starts.size() else last
		if finish <= begin or finish > last:
			continue
		# What the section offers, and whether it offers it throughout.
		var seen := {}
		for f in range(begin, finish + 1):
			seen[_labels_at(preview, f)] = true
		if seen.size() <= 1:
			continue
		# **Only a section that loops.** A section the movie plays straight
		# through legitimately offers its key on the frame that polls for it and
		# not afterwards: once the playhead is past, the key does nothing and
		# advertising it would be worse than the flicker. The engine widens only
		# looping sections and this asks the same question with the same
		# function, so the two cannot drift apart.
		if not KeyAffordance._section_loops(
				score, preview.get("_table"), begin, finish):
			continue
		# More than one answer inside one section. Only a problem when one of
		# them is "something" and another is "nothing": two *different* keys in
		# one section is a section the author divided by something other than a
		# marker, and this is not the check for that.
		if not seen.has(""):
			continue
		asked += 1
		var offered := PackedStringArray()
		for k in seen:
			if str(k) != "":
				offered.append(str(k))
		uneven.append("%d..%d offers %s on some frames and nothing on others"
			% [begin, finish, "/".join(offered)])
	h.check("%s: a key holds for the whole wait, not one frame of it" % case_name,
		uneven.is_empty(),
		"%d section(s) flicker: %s" % [uneven.size(), "; ".join(uneven)]
			if not uneven.is_empty() else "no section offers a key on only part of itself")


## The action labels a frame offers, joined, so two frames can be compared.
func _labels_at(preview: Node, index: int) -> String:
	var d: Dictionary = KeyAffordance.demand_at(preview, index)
	var names := PackedStringArray()
	for a in KeyAffordance.actions_of(d):
		names.append(KeyAffordance.label_of(a))
	names.sort()
	return ",".join(names)
