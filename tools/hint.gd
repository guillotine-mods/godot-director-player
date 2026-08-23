extends SceneTree
## Does `hint` point at something a click would actually reach?
##
##   godot --headless --script tools/hint.gd -- --root piposh2 --boot strtgame.dir
##   godot --headless --script tools/hint.gd -- --root piposh --ticks 400
##
## `bugs.md` 130's harness. Three things are being held down, and only the second
## is about drawing anything.
##
## **1. The signal reaches something.** `project.godot` binds `hint` to H and to
## joypad button 3, `autoload/input_router.gd` emits `hint_requested`, and for as
## long as the entry was open the signal appeared three times, all inside the file
## that declares it. That is the defect as filed and it is one check: the autoload
## has a listener. It is also the check that fails first when the fix is reverted,
## which is the property `AGENTS.md` asks every harness to have.
##
## **2. The hint cannot lie.** This is the whole reason the feature is worth
## building rather than deleting by analogy with `skip_minigame` (`bugs.md` 129).
## A hint that names something a click would not reach is worse than no hint,
## because the player acts on it and then reads the engine as broken. So the
## assertion is not "the named sprite has a behaviour" -- it is the **click
## router's own descent**, `interaction.gd:channel_at`, called with the arguments
## `director_preview.gd:_channel_at` calls it with, answering the hint's own point
## with the hint's own channel. Every candidate on the frame is held to it, not
## just the one that was shown, because the one that is shown depends on which
## press you are on.
##
## The weaker half is asserted beside it -- `interaction.gd:responds_to_mouse`
## answers yes for the named sprite -- because the two can come apart in one
## direction and it is worth seeing which: a sprite can be eligible and wholly
## covered by a higher eligible sprite, in which case it is correctly **not** a
## candidate. Eligible-and-unreachable is a real state; reachable-but-ineligible
## is not, and would mean the descent and the filter disagree.
##
## **3. It is on the player's side of the debug switch.** `hint` is an `InputMap`
## action rather than a `DebugKeys` command, so `tools/debug_bindings.gd`'s "with
## the layer off the preview claims no key at all" is untouched -- asserted here
## too, from the other end, so that moving `hint` into `DEFAULTS` reds this file
## as well as that one. And with `[debug] enabled` false the hint still arms:
## turning the developer tools off must not take an accessibility affordance with
## them.
##
## ## What it measures rather than asserts
##
## **H is a key one of the six titles reads**, and this prints it rather than
## failing on it. `tools/lib/key_sites.gd` over all six roots: `rating` tests
## `(the key = "h") or (the keyCode = 4)` at 3 sites in 2 containers --
## `batzegoz.dir` members 6 and 81 and `beralgoz.dir` member 33, beside the same
## shape for `j` and `q`, which is that title's own cheat-key trio. The other five
## roots have 0.
##
## That is exactly the collision `debug_keys.gd` bans for a *preview* binding, and
## it is not the same hazard here: a debug binding paused the movie or jumped the
## playhead, so the game misbehaved. The hint takes nothing from the movie -- the
## key is polled, never consumed, so Rating's own handler still runs -- and
## changes no state the movie can observe, which is asserted below as "the frame
## did not move". What it costs is a 2.5-second outline appearing beside a cheat
## the player asked for. Moving the binding is a decision about the product rather
## than about the engine, so it is reported and left where `project.godot` and the
## entry both have it.
##
## **How often a frame offers nothing at all**, which is the evidence behind the
## design decision recorded in `hilite.gd:aim`: a frame with no clickable sprite
## is ordinary rather than a fault, so the hint arms nothing and says so only in
## the debug toast. The census below prints the split for whichever root it is
## pointed at rather than asserting a number, because the number is the title's.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Hilite := preload("res://scenes/preview/hilite.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Keys := preload("res://director/director_keys.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")


## The live sprite on `channel` this frame, or `{}`. Through `_effective`, because
## that is what both the descent and the mark see.
static func _sprite_on(host, channel: int) -> Dictionary:
	for raw in host.frame_sprites():
		var live: Dictionary = host._effective(raw)
		if not live.is_empty() and int(live["channel"]) == channel:
			return live
	return {}


## Everything about the stage a hint must not disturb.
##
## The point of the collision above: pressing H in a title that reads H has to be
## additive. A press that moved the playhead, puppeted a channel or swapped a
## member would be the `debug_keys.gd` failure wearing a different hat.
static func _stage_print(host) -> String:
	var members := PackedStringArray()
	for raw in host.frame_sprites():
		var live: Dictionary = host._effective(raw)
		if live.is_empty():
			members.append("-")
			continue
		members.append("%d:%d@%d,%d" % [
			int(live["cast_lib"]), int(live["cast_id"]),
			int(live["loc_h"]), int(live["loc_v"])])
	return "f%d o%d [%s]" % [
		int(host.get("_index")), (host.get("_overrides") as Dictionary).size(),
		",".join(members)]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	# ---------------------------------------------------------------- the defect
	#
	# **Below the `await`, and reached as a node rather than as a preload.** Both
	# halves are the same fact about a `--script` run and both are traps:
	#
	#   - the autoloads do not exist yet inside `_init`. `root.get_node_or_null`
	#     answers null there, so the whole of this case would have failed against
	#     a fix that is present and working.
	#   - `preload("res://autoload/input_router.gd")` from here compiles that
	#     script *before* the singletons are registered, and it names one --
	#     `AppSettings`. The compile fails with `Identifier not found`, the
	#     autoload node is then created **with no script**, and every check about
	#     it fails for a reason that has nothing to do with the subject. Measured,
	#     because the first version of this file did exactly that and reported
	#     `Nonexistent function 'answer'`.
	#
	# So everything below drives the real singleton through `call`, which is the
	# same reflective contract `tools/` already has with the preview node.
	var router: Node = root.get_node_or_null("InputRouter")
	h.begin("hint_requested reaches something")
	h.check("the InputRouter autoload is there, with its script", router != null \
		and router.get_script() != null)
	var listeners := 0
	if router != null and router.get_script() != null:
		listeners = router.hint_requested.get_connections().size()
	h.check("hint_requested has a listener (%d)" % listeners, listeners > 0,
		"bugs.md 130: the signal appeared three times, all inside the file that declares it")
	# The other half of the binding. A listener on a signal nothing can emit is
	# the same hole one step along, and `project.godot` is where it would open.
	h.check("the `hint` action still exists", InputMap.has_action("hint"))
	var on_key := false
	var on_pad := false
	for event in InputMap.action_get_events("hint") if InputMap.has_action("hint") else []:
		on_key = on_key or event is InputEventKey
		on_pad = on_pad or event is InputEventJoypadButton
	h.check("it is on a key and on a joypad button", on_key and on_pad,
		"key=%s pad=%s" % [on_key, on_pad])
	h.complete("hint_requested reaches something")

	# ------------------------------------------------- the player/debug boundary
	# Asserted from this end as well as from `debug_bindings.gd`'s, so that
	# putting `hint` on the wrong side of the switch reds both files rather than
	# leaving one of them agreeing with a stale idea of where it lives.
	h.begin("`hint` is a player affordance, not a preview binding")
	h.check("it is not a DebugKeys command", not DebugKeys.DEFAULTS.has("hint"),
		str(DebugKeys.DEFAULTS.get("hint", "-")))
	h.check("and H runs no preview command", DebugKeys.command_for(KEY_H) == "",
		DebugKeys.command_for(KEY_H))
	h.complete("`hint` is a player affordance, not a preview binding")

	if router == null or router.get_script() == null:
		quit(h.finish("the hint points at something clickable"))
		return
	for _i in 200:
		if preview.get("_score") != null:
			break
		preview.call("_advance")
	var table = preview.get("_table")
	var hit_pixels := bool(preview.get("_hit_pixels"))

	h.begin("a movie is loaded to ask about")
	h.check("the score is there", preview.get("_score") != null)
	h.check("the cast table is there", table != null)
	h.complete("a movie is loaded to ask about")
	if preview.get("_score") == null or table == null:
		quit(h.finish("the hint points at something clickable"))
		return

	# ------------------------------------------------------------- the census
	# **Settled, then scanned cold, and the two halves are for different reasons.**
	#
	# The settle is `--settle` ticks of the movie's own `_advance`, so `startMovie`
	# and the frame scripts of the opening have run and the globals a later frame
	# reads exist. The scan then pins `_index` frame by frame, which is
	# `tools/hotspots.gd`'s cold arm and carries its caveat: a member a *click*
	# would have swapped in is absent, so a frame can read as offering less than
	# it does in play.
	#
	# It is the cold arm rather than a walk because a walk cannot get there. This
	# corpus's boot movie holds on `go to the frame` over frames 43-49 while a
	# sound plays -- measured: 260 ticks of `_advance` visit 50 frames, all of them
	# before the menu, and 0 of the 50 offer a candidate. The menu whose buttons
	# this file wants to assert about is frame 850 of the same score. A harness
	# that only walked would have reported "no frame offers anything" about a title
	# whose first screen is four buttons.
	#
	# The caveat does not weaken what is asserted. Every check below compares the
	# hint against the **click router reading the same pinned frame**, so a cold
	# read makes the two agree about less rather than makes them agree wrongly.
	var settle := Args.number(args, "settle", 80)
	for _i in settle:
		preview.call("_advance")
	var score = preview.get("_score")
	var labels = preview.get("_labels")

	# **Where to look, in the order a frame is most likely to be worth looking
	# at.** The markers first, because a marker is where the movie's author put a
	# name and a screen the player interacts with is nearly always at one -- and
	# there are tens of them rather than the score's thousand-odd frames. Then a
	# strided sweep, so a score with no markers is still covered.
	#
	# Nothing here reads what a marker is *called*. That is the line `bugs.md` 129
	# could not cross and this one does not need to: a marker is used as a cheap
	# place to *look*, and every verdict below comes from the frame's own sprites.
	var frames := Args.number(args, "frames", 1400)
	var stride := maxi(1, Args.number(args, "stride", 8))
	var pinned := Args.number(args, "frame", -1)
	var order: Array[int] = []
	if pinned >= 0:
		order.append(pinned)
	else:
		if labels != null:
			for marker in labels.markers:
				order.append(int((marker as Dictionary)["frame"]))
		var walk := 0
		while walk < frames:
			order.append(walk)
			walk += stride

	# The cheap pass: `eligibility_reason` only, which is §4.3 over the frame's
	# sprites and touches no artwork. The expensive half -- `reachable_point`,
	# which runs the router's descent and therefore decodes bitmaps to sample
	# them -- is run only on the shortlist below. Doing it everywhere is what made
	# the first version of this file exceed a ten-minute ceiling on a 1,375-frame
	# score.
	var scanned := 0
	var bare := 0
	var eligible_total := 0
	var bare_frame := -1
	var shortlist: Array[int] = []
	var seen: Dictionary = {}
	for index in order:
		if seen.has(index):
			continue
		seen[index] = true
		if (score.frame(index) as Dictionary).is_empty():
			continue
		preview.set("_index", index)
		var count := 0
		for raw in preview.call("frame_sprites"):
			var live: Dictionary = preview.call("_effective", raw)
			if live.is_empty():
				continue
			if Interaction.eligibility_reason(preview, live, table) != "":
				count += 1
		scanned += 1
		eligible_total += count
		if count == 0:
			bare += 1
			if bare_frame < 0:
				bare_frame = index
		elif count >= 2 and shortlist.size() < 12:
			shortlist.append(index)

	# The expensive half, on the shortlist and in the order the shortlist was
	# built. A frame can carry two eligible sprites and offer fewer than two
	# candidates -- that is `reachable_point` refusing a sprite the descent does
	# not answer with, which is the whole point of it -- so the first frame that
	# survives is the one this file goes on to assert about.
	var rich_frame := -1
	var rich: Array[Dictionary] = []
	var refused := 0
	for index in shortlist:
		preview.set("_index", index)
		var found := Hilite.candidates(preview, table, hit_pixels)
		if found.size() >= 2:
			rich_frame = index
			rich = found
			break
		refused += 1
	if rich_frame >= 0:
		preview.set("_index", rich_frame)

	print("")
	print("%s: %d ticks settled, %d frame(s) read cold, %d with nothing clickable, %d eligible sprite(s) in all" % [
		str(preview.call("movie_name")), settle, scanned, bare, eligible_total])
	print("%d frame(s) shortlisted, %d of them offered fewer than two reachable points"
		% [shortlist.size(), refused])
	if rich_frame >= 0:
		print("frame %d offers %d:" % [rich_frame, rich.size()])
		for entry in rich:
			print("   ch%-4d %d:%-5d rect (%d,%d) %dx%d  click (%d,%d)  %s" % [
				int(entry["channel"]), int(entry["cast_lib"]), int(entry["cast_id"]),
				int((entry["rect"] as Rect2).position.x),
				int((entry["rect"] as Rect2).position.y),
				int((entry["rect"] as Rect2).size.x),
				int((entry["rect"] as Rect2).size.y),
				int((entry["point"] as Vector2).x), int((entry["point"] as Vector2).y),
				str(entry["reason"])])
	print("")

	h.begin("the scan found a frame with something to point at")
	h.check("a frame with two or more candidates was reached (frame %d)" % rich_frame,
		rich_frame >= 0, "%d frame(s) read, %d shortlisted" % [scanned, shortlist.size()])
	h.complete("the scan found a frame with something to point at")
	if rich_frame < 0:
		quit(h.finish("the hint points at something clickable"))
		return

	# ------------------------------------------- the hint agrees with the router
	# The assertion the whole feature stands on. `_channel_at` is the node's own
	# wrapper around `interaction.gd:channel_at` -- the function the player's
	# click goes through -- so a point that passes here is a point a click reaches.
	h.begin("every candidate is a point a click would actually reach")
	for entry in rich:
		var channel := int(entry["channel"])
		var at: Vector2 = entry["point"]
		var took: int = preview.call("_channel_at", at)
		h.check("ch%d: a click at (%d,%d) descends to ch%d" % [
			channel, int(at.x), int(at.y), channel], took == channel,
			"the router answered ch%d" % took)
		var live := _sprite_on(preview, channel)
		h.check("ch%d: interaction.gd's own eligibility answers yes" % channel,
			not live.is_empty() and Interaction.responds_to_mouse(preview, live, table),
			Interaction.eligibility_reason(preview, live, table) if not live.is_empty() \
				else "no sprite on that channel")
	h.complete("every candidate is a point a click would actually reach")

	# ------------------------------------------------------------- one press
	var before := _stage_print(preview)
	var first: Dictionary = router.call("answer", preview)
	h.begin("one press marks one of them")
	h.check("the press chose a candidate", not first.is_empty())
	h.check("it chose the topmost one (ch%d)" % int(rich[0]["channel"]),
		int(first.get("channel", 0)) == int(rich[0]["channel"]),
		"chose ch%d" % int(first.get("channel", 0)))
	h.check("the mark is live", Hilite.hint_live(preview))
	var state := Hilite.hint_state(preview)
	h.check("and it is the channel the answer named",
		int(state["channel"]) == int(first.get("channel", 0)),
		"%d vs %d" % [int(state["channel"]), int(first.get("channel", 0))])
	# The property that makes the H collision with `rating` benign rather than the
	# `debug_keys.gd` failure in a new coat. See this file's header.
	h.check("and the movie did not move", _stage_print(preview) == before,
		"%s -> %s" % [before, _stage_print(preview)])
	h.complete("one press marks one of them")

	# The mark has to go away on its own: nothing repaints a paused stage, so a
	# deadline that is never read is an outline that stays up for the rest of the
	# session. Reached by rewinding the stored deadline rather than by sleeping,
	# because `Time.get_ticks_msec()` is the clock and a harness may not wait 2.5s.
	h.begin("the mark expires")
	state["until"] = Time.get_ticks_msec() - 1
	preview.set_meta(Hilite.HINT_META, state)
	h.check("a deadline in the past is not live", not Hilite.hint_live(preview))
	h.check("but the channel is remembered, so the next press cycles from it",
		int(Hilite.hint_state(preview)["channel"]) == int(first.get("channel", 0)))
	h.complete("the mark expires")

	# ----------------------------------------------------------------- cycling
	# The design decision recorded in `hilite.gd:request`: a frame with five doors
	# and a hint that always names the same one answers one question once.
	h.begin("repeated presses walk the frame instead of repeating themselves")
	var walked: Array[int] = [int(first.get("channel", 0))]
	for _i in rich.size() - 1:
		walked.append(int((router.call("answer", preview) as Dictionary).get("channel", 0)))
	var distinct: Dictionary = {}
	for channel in walked:
		distinct[channel] = true
	h.check("%d press(es) named %d distinct channel(s)" % [walked.size(), distinct.size()],
		distinct.size() == rich.size(), str(walked))
	var wrapped := int((router.call("answer", preview) as Dictionary).get("channel", 0))
	h.check("and the next one wraps to the first (ch%d)" % int(rich[0]["channel"]),
		wrapped == int(rich[0]["channel"]), "ch%d" % wrapped)
	h.complete("repeated presses walk the frame instead of repeating themselves")

	# ------------------------------------------------------- the empty frame
	# The other design decision: silence on the stage, words in the debug toast.
	# Only asserted when the walk actually met such a frame -- `sprite_lifetime`'s
	# fourth case and `video_fallback` are the pattern, and the alternative is a
	# harness that fails on a corpus rather than on the engine.
	h.begin("a frame with nothing clickable arms nothing")
	if bare_frame < 0:
		h.check("no frame of the %d read offers nothing, so this is not asserted here"
			% scanned, true, "not a defect: see hilite.gd:aim")
	else:
		var was := int(preview.get("_index"))
		preview.set("_index", bare_frame)
		var empty: Dictionary = router.call("answer", preview)
		h.check("frame %d: the answer is empty" % bare_frame, empty.is_empty(),
			str(empty))
		h.check("frame %d: and nothing is marked" % bare_frame,
			not Hilite.hint_live(preview))
		h.check("frame %d: and the cycle cursor is cleared" % bare_frame,
			int(Hilite.hint_state(preview)["channel"]) == 0)
		if DebugKeys.enabled():
			h.check("frame %d: the debug toast says so" % bare_frame,
				str(preview.get("_toast")).contains("nothing"),
				str(preview.get("_toast")))
		preview.set("_index", was)
	h.complete("a frame with nothing clickable arms nothing")

	# --------------------------------------------------- the switch, both ways
	# With the debug layer off the mark is still drawn, because it is the
	# player's; the toast is not, because it is ours. Getting this backwards is
	# what `bugs.md` 130's own boundary paragraph is about.
	preview.set("_index", rich_frame)
	h.begin("the debug switch does not take the hint with it")
	var lit: Dictionary = router.call("answer", preview)
	h.check("with the layer on, the toast names the target",
		not DebugKeys.enabled() or str(preview.get("_toast")).contains(
			"ch%d" % int(lit.get("channel", 0))), str(preview.get("_toast")))
	var written := "user://hint_debug_off.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("debug", "enabled", "false")
	cfg.save(written)
	DebugKeys.load_config(written)
	preview.set("_toast", "")
	var dark: Dictionary = router.call("answer", preview)
	h.check("`enabled` reads false", not DebugKeys.enabled())
	h.check("the hint still chooses a target", not dark.is_empty(),
		str(dark))
	h.check("and still marks it", Hilite.hint_live(preview))
	h.check("but writes no toast over the movie", str(preview.get("_toast")) == "",
		str(preview.get("_toast")))
	h.check("and still claims no keycode", DebugKeys.command_for(KEY_H) == "",
		DebugKeys.command_for(KEY_H))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
	DebugKeys.load_config()
	h.check("and the tracked config is back", DebugKeys.enabled())
	h.complete("the debug switch does not take the hint with it")

	# ------------------------------------------------- qol/hotspot_hints reaches
	# `bugs.md` 130's secondary half. The toggle had no reader at all; this is the
	# assertion that it has one, driven through the same function the running
	# engine calls once a tick rather than through a re-statement of it.
	var settings: Node = root.get_node_or_null("AppSettings")
	h.begin("qol/hotspot_hints reaches the engine")
	h.check("the AppSettings autoload is there", settings != null)
	if settings != null:
		settings.set("show_hotspot_hints", false)
		router.call("serve", preview)
		h.check("off is off", not bool(Hilite.hint_state(preview)["all"]))
		settings.set("show_hotspot_hints", true)
		router.call("serve", preview)
		h.check("and the setting turns it on",
			bool(Hilite.hint_state(preview)["all"]),
			"the toggle had no reader at all before bugs.md 130")
		# And what it marks is the click router's set, sprite for sprite. The
		# predicate is shared rather than restated (`hilite.gd:marks_persistently`),
		# so this is holding the toggle to the mouse and not to a second opinion.
		var marked := 0
		var eligible := 0
		var disagreed := 0
		for raw in preview.call("frame_sprites"):
			var live: Dictionary = preview.call("_effective", raw)
			if live.is_empty():
				continue
			var would: bool = Hilite.marks_persistently(preview, live)
			var can: bool = Interaction.responds_to_mouse(preview, live, table)
			if would:
				marked += 1
			if can:
				eligible += 1
			if would != can:
				disagreed += 1
		h.check("it marks exactly what the mouse can reach (%d of %d)"
			% [marked, eligible], disagreed == 0 and marked > 0,
			"%d sprite(s) disagreed" % disagreed)
		settings.set("show_hotspot_hints", false)
		router.call("serve", preview)
		h.check("and off again is off", not bool(Hilite.hint_state(preview)["all"]))
	h.complete("qol/hotspot_hints reaches the engine")

	# ------------------------------------------------------- the H measurement
	# Printed, not asserted. The header says why, and it is the number a decision
	# about moving the binding would be made from -- so it is measured every run
	# rather than quoted from a comment, which is the failure `AGENTS.md` records
	# for the F10 band.
	var probe := InputEventKey.new()
	probe.keycode = KEY_H
	probe.unicode = "h".unicode_at(0)
	probe.pressed = true
	var mac := Keys.code_for(probe)
	var typed := Keys.char_for(probe)
	print("")
	print("H is Mac key code %d and types '%s'. Which titles read it:" % [mac, typed])
	var collisions := 0
	for source in KeySites.roots():
		var sites := KeySites.for_root(str(source))
		var by_code: Array = (sites["codes"] as Dictionary).get(mac, [])
		var by_char: Array = (sites["chars"] as Dictionary).get(typed, [])
		var here: Dictionary = {}
		for site in by_code + by_char:
			here[str(site)] = true
		collisions += here.size()
		print("   %-16s %d container(s), %d site(s)%s" % [
			str(source).get_file(), int(sites["containers"]), here.size(),
			("  e.g. " + str(here.keys()[0])) if here.size() > 0 else ""])
	h.begin("the collision is measured rather than remembered")
	h.check("every root was read, so this is a measurement", KeySites.roots().size() > 0,
		"%d root(s), %d H site(s) in all" % [KeySites.roots().size(), collisions])
	h.complete("the collision is measured rather than remembered")

	quit(h.finish("the hint points at something clickable"))
