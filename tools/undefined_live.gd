extends SceneTree
## Fire `UNDEFINED_HANDLER` on the corpus's own undefined call, and read what the
## abort did to the movie around it.
##
##   godot --headless --audio-driver Dummy --path . --script tools/undefined_live.gd -- \
##       --root rating --movie BATZROOM.dir --site 231 --member 103 --name mraker
##   ... -- --root rating --movie XROOM.dir --site 350 --member 173 --name mraker
##
##   --root R     the corpus (`DirectorPaths` honours it)
##   --movie C    the container that carries the site
##   --site N     the frame whose own frame script makes the undefined call
##   --enter N    the frame the playhead is placed on, 0-based; defaults to the
##                site, and see "the third wall" below for why nothing earlier
##                works
##   --name X     the undefined handler expected, lowercased
##   --member N   the script member expected to carry it, for the pointed-at-it check
##   --ticks N    process frames to watch after entering (default 240)
##   --speech N   `AudioServer.playback_speed_scale`, so the movie's own opening
##                sound retires N times sooner (default 24; 1 is real time)
##   --quiet-ms N how long to wait for channel 1 to fall silent before entering
##                (default 20000 ms of wall clock)
##   --strict     also assert that no builtin ran after the abort was raised --
##                what the reference does, and what this port does not; see "what
##                the abort did to the statement" below
##   --verbose    print (tick, frame, builtin counts) every time the playhead moves
##
## ## Why this exists
##
## `docs/bugs-closed.md` 123 closed with one thing unproven and said so twice:
## **nobody had ever seen `UNDEFINED_HANDLER` fire on real corpus data.** Every
## attempt stayed silent, and the entry's explanation was that the reproducing
## arm "sits behind `if not soundBusy(1)`" -- so `liveness_sweep --speech`, which
## scales `AudioServer.playback_speed_scale` and retires a `soundBusy` wait N
## times sooner, was named as the flag that would get past it.
##
## **It is not, and the `soundBusy` guard is not what blocks it.** Two things
## were wrong with that reading, and both were found by reading the container
## rather than by driving it harder:
##
## 1. **The entry names the wrong containers.** It says the arm lives in
##    `rating`'s `NAVIGATE.dir` and `BATZROOM.dir`. Re-measured --
##    `tools/undefined_calls.gd --root rating --verbose` -- the two `mraker` sites
##    are `BATZROOM.dir` member 103 and **`XROOM.dir` member 173**; `NAVIGATE.dir`
##    carries `dont(pass)` and no `mraker` at all. Half of every earlier attempt
##    was pointed at a container that cannot fire it.
## 2. **The site is walled off by an unconditional `go`, one frame region
##    earlier.** Both movies carry the same copy-pasted block, and both hang off
##    their container's last marker:
##
##        BATZROOM.dir  marker[19] f165 `play done`   XROOM.dir marker[32] f272
##          f189  Panel.cst 175  rollover tracking      f308  Panel.cst 175
##          f203  Panel.cst 177  `go to marker(0)`      f322  Panel.cst 177
##          f219  Panel.cst 181  `go to marker(0)`      f338  Panel.cst 181
##          f223  `if not soundBusy(1) then go(marker(1))`   f342  same
##          f231  `if not soundBusy(1) then go(mraker(1)) else go(marker(0))`  f350
##
##    `Panel.cst` 177's **first statement** is `go to marker(0)`, and `marker(0)`
##    from anywhere in that region is the region's own marker. So a playhead that
##    falls into f166 is returned to f165 at f203 and can never reach f223, let
##    alone f231. `marker(1)` is the same frame -- `lingo_marker` clamps to the
##    last marker and f165/f272 *is* the last -- so the f223 gate is a second wall
##    behind the first. **`--speech` cannot help with either.** It gets past a
##    `soundBusy` *hold*; it cannot get past an unconditional jump, and where the
##    `soundBusy` gate does apply, retiring the sound sooner makes f223 jump away
##    from the site rather than towards it.
##
## So the site is dead score in the shipped title: nothing in either movie's
## `VWLB` marks f220-f231, no `go` in the corpus names a bare frame number in that
## range, and falling in is what f203 prevents. That is why it has never fired,
## and it is a fair guess at why the typo survived to ship -- the author never ran
## the line either. **A cold entry is therefore the only way to reach it**, which
## is exactly what `liveness_sweep --scenes` already does for markers and what
## `tools/scene_probe.gd --frame N` already does for frames: everything executed
## here is the movie's own compiled Lingo, on its own frame, in the real player;
## only the arrival is chosen.
##
## ## `--speech` earns its place here, one wall further in
##
## Standing on the site is still not enough, and the first run of this harness
## proved it: `f231 soundBusy ch1 -> true`, so the movie took its `else` arm and
## `go(marker(0))` sent the playhead back to f165 -- into the f165->f203->f165
## loop above, which never returns to f231. The sound holding it is the
## container's **own opening line**: `BATZROOM.dir` frame 0, marker[0], runs
## `sound playFile 1, soundspath & "musgad.aif"` before anything else, and it is
## still playing 231 frames later.
##
## So `bugs.md` 123 was right that a `soundBusy` hold stands between a driven run
## and this diagnostic, and right that `--speech` is the lever for it -- it was
## wrong only about *which* wall comes first, and the unconditional `go` in front
## of it is why pointing `liveness_sweep --speech` at the container could never
## have worked. Here the wait is explicit: `playback_speed_scale` is raised so
## the opening line retires in seconds instead of minutes, and the run then
## **waits on the condition** -- `lingo_sound_busy(1)` going false -- rather than
## on a frame count, which is `AGENTS.md`'s own rule from `play_suspends` and
## `bugs.md` 41. A fixed budget here would be the same flake in a new file.
##
## ## The third wall, and why `--enter` defaults to the site itself
##
## The obvious way to arrive is to stand a few frames short and let the score
## walk in, and this harness did that first. It does not work, and the reason is
## the score's **script channel spans**: the frame map above prints a script only
## where it changes, and f223's `if not soundBusy(1) then go(marker(1))` is not
## one frame but the span **f223-f230**. Measured rather than inferred -- the
## first run's sound trace has `soundBusy ch1` asked on every one of f224, f225,
## f226, f227, f228, f229, f230 and f231.
##
## So each of the seven frames before the site runs the *other* gate, and its
## false branch is `go(marker(1))`, which clamps to the region's own marker. With
## channel 1 silent the walk-in jumps to f165 at the very first frame; with it
## busy the walk-in reaches f231 and the site takes its `else`, `go(marker(0))`,
## back to f165 as well. The site's true arm needs channel 1 busy through f230
## and silent on f231 -- a one-frame race in a 66-frame loop -- so it is not
## reachable by advance in any state, only by standing on it. `--enter` therefore
## defaults to `--site`, and `enterFrame`/`exitFrame` for that frame are run by
## the awaited frames after the index is set, exactly as `scene_probe.gd` does.
##
## ## What the abort is asserted to have done
##
## `bugs.md` 123's resolution made the abort live, and `Lingo::execute`'s epilogue
## is two things, not one: it drops every remaining `CFrame` of the scope that
## caught the flag, **and** it clears the flag so that scope's caller carries on.
## `tools/lingo_execute_boundary.gd` asserts both synthetically. Here they are
## read off the corpus:
##
##   * the statement was abandoned -- `go` is **not** reached on the tick that
##     fired, though the abandoned statement is `go(mraker(1))` and `go` is
##     reached elsewhere in the same run;
##   * the caller resumed -- the score kept ticking after the abort, which is the
##     frame loop running on after the aborted dispatch returned.
##
## Both are the *player-visible* invariant rather than a flag read back, which is
## `AGENTS.md`'s rule for covering a fix.
##
## **The second holds and the first does not**, which is this harness's finding
## and the reason the first is behind `--strict`. Measured on both sites: `go`
## goes 1 -> 2 *across* the aborted statement, so this port evaluates
## `mraker(1)` to the fall-through's 0 and then calls `go(0)` anyway. The
## player-visible effect is that `BATZROOM.dir` jumps to its own frame 0 and
## replays its opening -- `sound playFile 1, ... "musgad.aif"`, then
## `go("mainframe")` -- where Director stops at the undefined call and lets the
## score advance to f232. Same shape at `XROOM.dir` f350. See `bugs.md` for the
## entry and the one-line patch.
const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Diagnostics := preload("res://lingo/lingo_diagnostics.gd")


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var movie := Args.text(args, "movie", "BATZROOM.dir")
	var site := int(Args.number(args, "site", 231))
	var enter := int(Args.number(args, "enter", site))
	var want := Args.text(args, "name", "mraker").to_lower()
	var member := int(Args.number(args, "member", 0))
	var ticks := int(Args.number(args, "ticks", 240))
	var quiet_ms := int(Args.number(args, "quiet-ms", 20000))
	var verbose := Args.flag(args, "verbose")
	var strict := Args.flag(args, "strict")
	# Set before the preview exists, so the movie's opening line is mixed fast
	# from its first sample rather than from wherever this happened to run.
	var speech := maxf(float(Args.number(args, "speech", 24)), 0.01)
	AudioServer.playback_speed_scale = speech

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	h.begin("the container opened")
	preview.call("lingo_go_movie", movie, null)
	for i in 16:
		await process_frame
	var opened := str(preview.call("movie_name"))
	var score = preview.get("_score")
	h.check("the movie under test is loaded and its score is up",
		score != null and opened.to_lower().contains(
			movie.get_file().get_basename().to_lower()),
		"%s, %d frame(s)" % [opened, 0 if score == null else int(score.frame_count)])
	h.complete("the container opened")

	# **Pointed at the game before explaining what the game did.** The site is a
	# frame script in the container's own cast, and the whole of
	# `director-qa-playthrough`'s warning is that a harness aimed at the wrong
	# container reports a silence as a finding. This asserts the text is there
	# before anything is driven, so a rename or a re-numbering fails loudly here
	# rather than looking like "the diagnostic did not fire".
	h.begin("the site is where this run says it is")
	var frame: Dictionary = score.frame(site) if score != null else {}
	var script_member := int(frame.get("frame_script", 0)) if not frame.is_empty() else 0
	var source := ""
	var table = preview.get("_table")
	if table != null and script_member > 0:
		source = str(table.get_member(
			int(frame.get("frame_script_lib", 1)), script_member).get("source", ""))
	h.check("frame %d's own frame script calls %s" % [site, want],
		source.to_lower().contains(want),
		"member %d, %d char(s) of source" % [script_member, source.length()])
	if member > 0:
		h.check("and it is the member the report names", script_member == member,
			"expected %d, score says %d" % [member, script_member])
	h.complete("the site is where this run says it is")

	# The container's own opening line is what holds `soundBusy(1)` at the site,
	# so the run waits for it to retire before entering. On the condition, not on
	# a tick count: `bugs.md` 41 is the entry about a harness whose fixed budget
	# was the flake, and `--speech` is what makes the wait short enough to have.
	h.begin("the movie's own opening sound retired before the site was entered")
	var quiet_start := Time.get_ticks_msec()
	while bool(preview.call("lingo_sound_busy", 1)) \
			and Time.get_ticks_msec() - quiet_start < quiet_ms:
		await process_frame
	var silent := not bool(preview.call("lingo_sound_busy", 1))
	h.check("channel 1 fell silent, so the site's own guard can be reached",
		silent, "waited %d ms at speech x%.0f" % [
			Time.get_ticks_msec() - quiet_start, speech])
	h.complete("the movie's own opening sound retired before the site was entered")

	# `_index` alone is an index and not an arrival -- `scene_probe.gd` carries
	# the same note -- so the awaited frames after it are what run `enterFrame`,
	# `exitFrame` and everything downstream.
	h.begin("the movie ran the site's own handler")
	var host = preview.get("_host")
	var interpreter = preview.get("_interpreter")
	if interpreter != null and interpreter.diagnostics != null:
		interpreter.diagnostics.clear()
	# Every builtin the abandoned statement could have reached, counted before
	# the site runs. Read as a group rather than one name, because which builtin
	# the aborted call is an argument to is a property of the movie and this file
	# may not know one title's spelling of it.
	var watched := PackedStringArray(["go", "play", "marker", "sound", "updatestage"])
	var before: Dictionary = {}
	for name in watched:
		before[str(name)] = _reached(host, str(name))
	preview.set("_index", enter)
	var visited: Array[int] = []
	var at_fire: Dictionary = {}
	var frame_at_fire := -1
	var seen_site := false
	var left_site := false
	for i in ticks:
		await process_frame
		# `current_frame()` returns `_index` itself, so this is already the
		# score's own 0-based space and no adjustment belongs here. Checked
		# against `director_preview.gd:2787` rather than assumed: `the frame` is
		# 1-based in Lingo and `lingo_frame_number` is the converter, so a tool
		# that reads one and compares against the other is off by one silently.
		var at := int(preview.call("current_frame"))
		if visited.is_empty() or visited[visited.size() - 1] != at:
			visited.append(at)
			if verbose:
				print("      tick %-4d frame %-5d %s" % [i, at, _counts(host, watched)])
		if at == site:
			seen_site = true
		elif seen_site:
			left_site = true
		# **The first sample at which the diagnostic exists is the reading that
		# matters**, and it is not "the first sample on the site": the site's
		# `exitFrame` runs inside the very first awaited frame, so by tick 0 the
		# playhead has already been moved on by whatever the aborted statement
		# did or did not do. Sampling on frame identity missed it entirely and
		# reported `go` "not reached" because the site was never seen -- a check
		# that cannot fail, which is `harness.gd`'s own warning.
		if at_fire.is_empty() and _fired(interpreter, want):
			frame_at_fire = at
			for name in watched:
				at_fire[str(name)] = _reached(host, str(name))
	h.check("the site's own `exitFrame` ran", not at_fire.is_empty() or seen_site,
		"visited %s" % str(visited.slice(0, 12)))
	h.complete("the movie ran the site's own handler")

	h.begin("the diagnostic fired on real corpus data")
	var fired: Array = []
	if interpreter != null and interpreter.diagnostics != null:
		fired = interpreter.diagnostics.entries(Diagnostics.UNDEFINED_HANDLER)
	var hit: Dictionary = {}
	for entry in fired:
		if str((entry as Dictionary).get("name", "")).to_lower() == want:
			hit = entry
	h.check("UNDEFINED_HANDLER reported %s" % want, not hit.is_empty(),
		"%d entr(ies): %s" % [fired.size(), JSON.stringify(fired)])
	if not hit.is_empty():
		print("      the line, as the diagnostic names it: %s / %s / line %d / name %s / x%d" % [
			str(hit.get("script", "")), str(hit.get("handler", "")),
			int(hit.get("line", 0)), str(hit.get("name", "")), int(hit.get("count", 1))])
	# The other half of the same report: `_call` goes through `_fail` as well, so
	# a running game leaves a sign a harness can read without scraping stdout.
	# 123's whole complaint was that it left none.
	#
	# **Read off `session_faults()`, not off `errors`.** `errors` is cleared by
	# `reset_steps` at the start of *every* dispatch, so a poll once per process
	# frame misses a fault raised and cleared between two of them -- which is
	# what happened here on the first green run: the diagnostic fired, the
	# `lingo:` line printed, and the array was empty every time it was looked at.
	# `_reported` outlives `reset_steps` on purpose and `session_faults()` is it
	# as a value.
	var spoken := ""
	var faults: PackedStringArray = PackedStringArray()
	if interpreter != null:
		faults = interpreter.session_faults()
	for message in faults:
		if str(message).to_lower().contains(want):
			spoken = str(message)
	h.check("and the interpreter's fault sink carries it too", spoken != "",
		JSON.stringify(spoken))
	h.check("and no *other* name aborted in the same run", fired.size() <= 1,
		"names: %s" % str(fired))
	h.complete("the diagnostic fired on real corpus data")

	# `Lingo::execute`'s epilogue is two things. The second one is what this
	# checks: the flag is cleared at the scope that caught it, so that scope's
	# caller carries on. The caller here is the frame loop, and it carrying on is
	# the movie still running afterwards -- an abort that unwound further than
	# Director's would have taken the frame loop with it and parked the movie.
	h.begin("the caller resumed")
	h.check("the score kept running after the abort", left_site or visited.size() > 1,
		"frames visited (0-based): %s" % str(visited.slice(0, 16)))
	h.complete("the caller resumed")

	# The first one -- **the statement the undefined call sits in is abandoned**
	# -- is reported here and asserted only under `--strict`, because this port
	# does not do it and the divergence is a `bugs.md` entry rather than a
	# regression this run introduced.
	#
	# `Lingo::execute`'s loop condition is tested between *bytecode
	# instructions* (`reference/scummvm/lingo/lingo.cpp:634`), and
	# `go(mraker(1))` compiles to `push 1` / `call mraker` / `call go`. `LC::call`
	# raises `lingoError` on the middle one (`lingo-code.cpp:1770`), which sets
	# `_abort` (`lingo.cpp:811`), so the loop never reaches the `go`. This port
	# tests `_aborting` in `_exec_from`, i.e. after the whole **statement**, and
	# its own comment says so; one granularity too coarse for exactly this shape,
	# and `rating`'s two `mraker` sites are the only shape in the corpus where it
	# is observable, because the aborting call is an argument to a command with a
	# side effect.
	h.begin("what the abort did to the statement")
	var deltas: Array[String] = []
	var moved := 0
	for name in watched:
		var was := int(before.get(str(name), -1))
		var now := int(at_fire.get(str(name), was))
		if now != was:
			moved += 1
		deltas.append("%s %d->%d" % [str(name), was, now])
	print("      builtins across the aborted statement: %s" % ", ".join(deltas))
	print("      frame when the diagnostic fired: %d (site %d)" % [frame_at_fire, site])
	if strict:
		h.check("no builtin ran after the abort was raised", moved == 0,
			"%d of %d moved: %s" % [moved, watched.size(), ", ".join(deltas)])
	else:
		print("      %d of %d watched builtins ran anyway -- --strict asserts 0" % [
			moved, watched.size()])
		h.check("the reading was taken at all (0 would mean the site never fired)",
			not at_fire.is_empty(), "watched %s" % str(watched))
	h.complete("what the abort did to the statement")

	quit(h.finish("the corpus's own undefined call fires, is reported by name, "
		+ "script and line, and leaves the frame loop running"))


## How many times the host has answered a builtin by that name. Read off
## `preview_lingo_host.reached`, which is the same counter `liveness_sweep` reads
## for its `soundBusy` clause; -1 when there is no host to ask, so a missing host
## cannot read as "the builtin was never called".
static func _reached(host, name: String) -> int:
	if host == null:
		return -1
	return int((host.reached as Dictionary).get(name, 0))


## The watched builtins as one line, for `--verbose`.
static func _counts(host, names: PackedStringArray) -> String:
	var out: Array[String] = []
	for name in names:
		out.append("%s %d" % [str(name), _reached(host, str(name))])
	return "  ".join(out)


## Whether the undefined-handler diagnostic for `want` exists yet. Asked once a
## process frame, so it has to be cheap and it has to be exact: the sink is
## keyed by (category, name, script, handler, line) and never cleared by a
## dispatch, so the first frame it answers true is the frame the call was made.
static func _fired(interpreter, want: String) -> bool:
	if interpreter == null or interpreter.diagnostics == null:
		return false
	for name in interpreter.diagnostics.names_in(Diagnostics.UNDEFINED_HANDLER):
		if str(name).to_lower() == want:
			return true
	return false
