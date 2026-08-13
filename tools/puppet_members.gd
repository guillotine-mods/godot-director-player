extends SceneTree
## Which members a movie's scripts puppet onto channels, what those members are,
## and which of them are film loops with film-loop children.
##
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --file COMEIN.dir
##   godot --headless --path . --script tools/puppet_members.gd -- --root rating --file blatack1.dir
##   godot --headless --path . --script tools/puppet_members.gd -- --source
##
##   --root R     the corpus (default the config's)
##   --file F     the container (default the config's boot movie)
##   --play S     after the static report, enter scene S the way the movie does and
##                say what drew. `--play all` walks every scene it derived.
##   --ticks N    process frames to give one played scene (default 4000)
##   --source     print each script's handler text under its findings
##   --verbose    print every element of every game, not the first 12
##
## A survey and not a gate: it prints a table and numbers rather than pass/fail,
## so it is not in `gate.sh`'s `ALL`.
##
## ## What this answers, and why the question needed a tool
##
## A film loop whose child was itself a film loop drew nothing: `film_loop_view.gd`
## asked `host._texture_for` per child and that path is bitmap-and-shape only, so a
## type-2 child returned null and the inner loop was skipped whole. Fixed, in
## `paint_loop`'s recursion. **What that fix was worth needed a different question
## answered: which of a movie's scripted scenes had a nested loop in it at all.**
## `tools/film_loop_nesting.gd` says which loops nest and `tools/film_loop_cast.gd`
## says where their children resolve; neither says which *scene* the player would
## have noticed it in, because neither reads the scripts that put a loop on a
## channel.
##
## So this walks the other way round: from the movie's own markers and score to the
## scripts, from those scripts to the members they assign, and from a type-2 member
## into its children. The measured answer for `piposh-dream/COMEIN.dir` — six
## minigames, one per character — is that **exactly one of the six was hit**, and it
## is recorded in `docs/bugs-closed.md` beside `bugs.md` 98.
##
## ## How a "scene" is derived, with no table anywhere
##
## Nothing here names a movie, a marker, a channel or a member. Four rules, each
## read off the container:
##
## **An init is a frame script that claims a channel.** `puppetSprite(N, 1)` takes
## channel N away from the score so a script can dress it; `puppetSprite(N, 0)`
## gives it back. Only the claim counts, and that one bit is the whole
## discriminator: of COMEIN's **15** frame scripts calling `puppetSprite`, **6
## claim and 9 release**. The releases are the two ways a scene can end — the
## `fritzend`/`docend`/`krupend`/`rafend`/`hatend`/`pozend` frames handing the
## channels back when the character has been hit, and the six `*win` frames doing
## it inside a `repeat with i`, where the channel is a variable this cannot bound
## and does not need to. Count mentions instead of claims and this file would report
## fifteen games in a movie that has six, and the nine extras would all be endings.
##
## **A scene is the covered run its init sits in.** Frame scripts arrive as score
## interval entries — a span of frames with a script attached — so "which frames
## does a script run on" is a fact the score states. Take the maximal *contiguous*
## stretch of frames that some frame-script interval covers, and the run containing
## an init is that init's scene. In COMEIN the six runs come out
## f177..f207, f294..f318, f436..f474, f573..f610, f722..f753 and f894..f921: the
## init, the throw, the collision poll and the settle, and nothing else. The
## outcome frames (`fritzend` f209, `fritzwin` f226) are runs of their own, one
## frame each, because the frames between are uncovered — which is the score
## saying they are a different scene, not this file deciding it.
##
## **The narrowest covering interval wins.** That is `scenes/preview/scripts.gd`'s
## rule, carried here rather than called: `for_frame` takes the preview node and
## reaches `host._script_in_lib`, so a headless static pass cannot use it. A movie
## carries both scene-specific frame scripts and ones that span everything, and
## taking the first match hands every frame to the widest.
##
## **A script member number is resolved in the library the interval names.** With
## `0` and `0xFFFF` normalised to 1, which `scripts.gd:in_lib` does and
## `DirectorScore._read_interval` deliberately does not — it stores the raw `_i16`.
## Skip the normalisation and the resolution lands in the wrong cast, which is the
## bug class `scripts.gd` exists around: it returns a stranger rather than nothing.
##
## ## Members from expressions, not only from literals
##
## Half of what a scene assigns is not a literal. COMEIN's throw handlers say
##
##     set the member of sprite (26 + x) to member(155 + x, 1)
##
## and a literal scan finds neither the channels nor the members. So an operand is
## either an integer or `<int> + <var>`, and **a variable's range is bounded by the
## comparisons the same handler makes against it**: `if (x = 1) or (x = 2) or
## (x = 3)` admits exactly 1, 2 and 3, so the channels are 27, 28, 29 and the
## members 156, 157, 158. That is a general mechanism rather than a special case —
## an author who writes an offset writes the guard beside it — and it is
## corroborated on every run rather than trusted: each scene's line **compares** the
## channels the arithmetic derived against the ones its init claimed and says whether
## they agree, which for COMEIN's six is where 27, 28, 29 meets `puppetSprite(27, 1)`
## three times over. Where a handler dresses a channel the init never claimed, the line
## names it — `hat` and `poz` do exactly that, dressing 3 and 4 with a literal after
## claiming them, and `doc` dresses 3 and 4 **without** claiming them, which is the lead
## at the bottom of this file. A `derived` member is labelled as such in the output, and an
## operand this cannot bound is reported verbatim as `unbounded` rather than
## dropped, because a member silently missing from a survey of members is the
## failure mode worth avoiding.
##
## Only assignment reaches a channel, so only assignment is scanned:
## `set the member[Num] of sprite`, and the dot form `sprite(N).member[Num] =`.
##
## ## The nesting question
##
## For every member a scene assigns: its type, and for a type-2 member its frame
## count, its `looping` flag, and whether any child resolves to another type-2
## member. Opened through `FilmLoopView.open_loop` and resolved through
## `FilmLoopView.child_lib` — the preview's own entry points, so what is reported
## is what the painter walks rather than a second reading written here, which is
## the discipline `tools/film_loop_cast.gd` and `tools/film_loop_scale.gd` both
## keep.
##
## ## Where the player gets in
##
## The played half of this question needs an entry, and the entry is derivable too.
## An idle span is a closed loop: a frame in the run, *before* the init, whose
## script jumps back to the marker covering it (`go(marker(0))`, or `go to the
## frame`). Nothing in the score can leave such a loop, so whatever does is a
## sprite behaviour — and the one to click is the sprite over those frames whose
## script has an `on mouseUp`/`on mouseDown` that calls `go`. Its rect comes from
## the score's own record through `Geometry.stage_rect`, so the click point is the
## movie's and not a coordinate written down here.
##
## `--play` then uses it: a scene with a click entry is entered by putting the
## playhead inside the idle span and pressing the derived point, and a scene without
## one by putting the playhead a little before its span and letting the movie walk in.
## **Neither ever jumps to the init marker**, and that is not superstition — landing on
## the init means the score's own arrival at that frame is what would have run the
## `puppetSprite`, the globals and the `keyUpScript`, and skipping it leaves a scene
## whose channels were never claimed. Frames are awaited, never ticked in a loop, for
## `AGENTS.md`'s reason: a synthetic tick advances the runtime clock and not the audio
## server's, so every `soundBusy` gate holds for ever and the speech before a scene
## never ends. The arrow keys are pressed on the movie's *score ticks* rather than per
## process frame, because these scenes read them through a `keyUpScript` and a press per
## frame pins the playhead (`tools/film_loop_restart.gd`'s `PRESS_EVERY`).
##
## Measured on COMEIN: **one** of the six scenes is behind such a loop —
## `fritz`, whose f178 runs `go(marker(0))` and whose channel 36 carries
## `on mouseUp ... go(marker(1))`, the doorbell. The other five have no gating
## behaviour anywhere in or before their run; the movie plays into them through the
## speech gate (`if not soundBusy(1) then go(marker(1))`). So the general shape does
## *not* repeat, and a survey that assumed it did would have gone looking for five
## hotspots that are not there.
##
## ## A lead this survey turned up and did not settle
##
## Five of the six scenes dress their lanes and draw. **`doc` does not**, and the shape
## is specific rather than vague: entered by walking in from f292, its init at f295 runs
## (`enterFrame` ran 1, `puppetsprite` reached 8 times, its `keyUpScript` fired 7), and
## then over a 20,000-frame window channels 27, 28 and 29 are never dressed with
## 187/188/189 at all. What the playhead does instead is the measurement: it walks
## f293..f308 and jumps straight to **f315, `y2`** — the branch `1:195` takes only on
## `((sprite(27).visible = 1) or (sprite(3).visible = 1)) and (sprite(5).visible = 1)`.
## Channel 27 was sampled at member 0 throughout, so the term that read true is
## `sprite(3)`, and the scene registers a hit at `plantcounter = 7` on its first pass
## and leaves for `docend` before anything is ever thrown.
##
## Two script-level facts sit under that, both readable with `--source`. `1:193` is the
## only one of the six inits that omits `puppetSprite(3, 1)`, `puppetSprite(4, 1)` and
## `sprite(3).visible = 0` — `1:147` (hat) and `1:181` (poz) both have all three, and
## their handlers dress 3 and 4 exactly as `doc`'s do. And `1:193` is the only init
## written `on enterFrame` rather than `on exitFrame`. Two anomalies in one script,
## which is what makes it a lead rather than a coincidence.
##
## **It is deliberately not concluded here.** Either reading is available — an authoring
## slip in a 1997 container, or this port answering `the visible of sprite 3` where
## Director answered otherwise — and `AGENTS.md`'s rule is that "not a bug" needs more
## evidence than a bug does, which cuts the same way in reverse. The score's own record
## puts member 187 on channel 3 from f295, so the sprite is *there*; whether it was
## visible is a runtime question and the score cannot answer it. Settling this needs the
## reference, not another run of this file.

const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")

## How many score ticks apart the synthetic arrow presses are. Three, for
## `film_loop_restart.gd`'s measured reason: a press per tick holds the playhead on the
## frame that arms the throw and nothing is ever thrown.
const PRESS_EVERY := 3
## How far before its span a walk-in scene is dropped. Two frames, so the movie plays
## the span's own first frame -- which is where the `starter` reset and the speech gate
## live -- rather than starting inside it.
const LEAD_IN := 2

const LOOP_TYPE := 2

## `puppetSprite N, 1` and `puppetSprite(N, 1)` are the same call; Director's
## parentheses are optional on a command. The flag is captured rather than assumed
## because the release form is what separates a scene's init from its exit.
const PUPPET := "(?i)puppetsprite\\s*\\(?\\s*([^,()]+?)\\s*,\\s*([^,()]+?)\\s*\\)?\\s*(?:\\n|$)"
## `set the member of sprite <chan> to <rhs>` and its `memberNum` spelling.
const SET_MEMBER := "(?i)set\\s+the\\s+member(num)?\\s+of\\s+sprite\\s+(\\(?[^\\n]+?\\)?)\\s+to\\s+([^\\n]+)"
## `sprite(<chan>).member = <rhs>`, the same assignment in the dot spelling.
const DOT_MEMBER := "(?i)sprite\\s*\\(\\s*([^\\n]+?)\\s*\\)\\s*\\.\\s*member(num)?\\s*=\\s*([^\\n]+)"
## `member(<id>[, <lib>])` on the right-hand side of either.
const MEMBER_OF := "(?i)member\\s*\\(\\s*([^,()]+?)\\s*(?:,\\s*([^,()]+?)\\s*)?\\)"
## `the number of member "name" [of castLib N]` — the other way a script names a
## member, and the one `rating/blatack1.dir` uses at six sites. A name is a *better*
## reference than a number, because a number is per cast and a name is what the
## author typed; `Cast.number_of` resolves it in the library named, or in the
## script's own where none is.
const NUMBER_OF := "(?i)the\\s+number\\s+of\\s+member\\s+\"([^\"]+)\"(?:\\s+of\\s+castlib\\s+([^\\s]+))?"
## A closed idle loop: the frame sends the playhead back to its own marker.
const HOLDS := "(?i)go\\s*(?:to\\s*)?\\(?\\s*(?:marker\\s*\\(\\s*0\\s*\\)|the\\s+frame)\\s*\\)?"
## A hold that a sound releases is not an idle loop, and this is the whole of the
## difference. COMEIN's speech gate is
##
##     if not soundBusy(1) then go(marker(1)) else go(marker(0))
##
## which matches `HOLDS` exactly and yet leaves on its own the moment the line of
## speech ends. Counting it made this file report a click entry for `krupnik` (f448)
## and `sue` (f586) and then admit it could find no hotspot over either -- which is
## the honest failure of a wrong rule rather than a missing behaviour. A loop only a
## sprite can leave is one with no sound gate in it.
const SOUND_GATED := "(?i)soundbusy"
## A behaviour that answers the mouse and moves the playhead is the way out of one.
const MOUSE_GO := "(?i)^\\s*on\\s+mouse(up|down)\\b"

var _verbose := false
var _show_source := false


func _init() -> void:
	var args := Args.parse()
	_verbose = Args.flag(args, "verbose")
	_show_source = Args.flag(args, "source")

	var paths = Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root" % Paths.CONFIG_PATH)
		quit(1)
		return
	var rel := Args.text(args, "file", str(paths.boot_movie))

	var f := ContainerFile.new()
	if not f.open(paths.resolve(rel)):
		print("cannot open %s under %s" % [rel, paths.root])
		quit(1)
		return
	var table = CastTable.new()
	if not table.open(f, paths):
		print("no cast in %s" % rel)
		f.close()
		quit(1)
		return
	var ids: Array = f.ids_of("VWSC")
	if ids.is_empty():
		print("%s has no score" % rel)
		f.close()
		table.close()
		quit(1)
		return
	var score = Score.new()
	if not score.parse(f.read_chunk(ids[0])):
		print("%s: score will not parse" % rel)
		f.close()
		table.close()
		quit(1)
		return
	var labels = Labels.new()
	var label_ids: Array = f.ids_of("VWLB")
	if not label_ids.is_empty():
		labels.parse(f.read_chunk(label_ids[0]))

	print("root       : %s" % paths.root)
	print("movie      : %s  %d frames, %d markers, %d score intervals" % [
		rel, score.frame_count, labels.markers.size(), score.intervals().size()])

	var cover := _coverage(score)
	var runs := _runs(cover)
	var scenes := _scenes(table, score, labels, cover, runs)
	print("covered    : %d of %d frames, in %d contiguous run(s)" % [
		cover.size(), score.frame_count, runs.size()])
	var puppets := _puppet_sites(table, cover)
	print("puppetting : %d frame script(s) mention puppetSprite — %d claim a channel," % [
		int(puppets["mention"]), int(puppets["claim"])]
		+ " %d release one" % int(puppets["release"]))
	# Not one per scene in general: `rating/blatack1.dir` has 5 claiming frames in 3
	# runs, because one fight re-arms its channels partway through. The scene count is
	# the run count, so a run with two claims is one scene and the first claim is its
	# init -- which the per-scene report says outright rather than averaging away.
	print("claims     : %d frame(s) claim a channel" % scenes["claim_sites"])
	print("scenes     : %d run(s) hold a claiming init" % scenes["list"].size())
	print("")

	var hit := 0
	for scene in scenes["list"]:
		if _report(scene, table, score, labels, cover):
			hit += 1

	print("=".repeat(78))
	print("summary")
	print("  %-10s %-7s %-20s %-18s %s" % [
		"scene", "init", "channels claimed", "film loops", "loops that nest"])
	for scene in scenes["list"]:
		var loops: Array = []
		var nests: Array = []
		for key in scene["elements"]:
			var el: Dictionary = scene["elements"][key]
			if int(el["type"]) != LOOP_TYPE:
				continue
			loops.append(int(el["id"]))
			if not (el["loop_children"] as Array).is_empty():
				nests.append(int(el["id"]))
		loops.sort()
		nests.sort()
		print("  %-10s %-7s %-20s %-18s %s" % [
			str(scene["name"]), "f%d" % int(scene["init"]),
			str(scene["claimed"]), str(loops),
			"none" if nests.is_empty() else str(nests)])
	print("")
	print("  %d of %d scene(s) assign a film loop that has a film-loop child."
		% [hit, scenes["list"].size()])
	print("  Those, and only those, drew nothing inside the inner loop before the")
	print("  nested-loop recursion in film_loop_view.gd:paint_loop landed.")

	var play := Args.text(args, "play", "")
	if play == "":
		f.close()
		table.close()
		print("")
		print("  (--play <scene>, or --play all, enters them and says what drew)")
		quit(0)
		return

	print("")
	print("=".repeat(78))
	print("played")
	for scene in scenes["list"]:
		if play != "all" and str(scene["name"]) != play:
			continue
		await _play(rel, scene, table, Args.number(args, "ticks", 4000))
	f.close()
	table.close()
	quit(0)


## Enter one scene the way the movie does, and report what reached the painter.
##
## The two entries are the two the derivation found, and nothing else is tried. What
## is read back afterwards is the painter's own record and never a field written from
## here: `_textures` is the decode cache keyed by `Geometry.texture_key`, so an
## element's key appearing in it means the painter asked the cast to decode that
## member at that size; `_loop_stats` is the paint tally, including the recursion's
## own `nested loop drawn` and `nested children offered`; and the live membership of a
## channel comes through `lingo_sprite_prop`, which is what a script would read.
##
## `_last_member` is deliberately not touched. It is the painter's record of what it
## painted and `tools/update_stage.gd` uses it as a probe that `updateStage` paints
## inside a handler, so writing it from a harness makes that entry assert nothing.
func _play(rel: String, scene: Dictionary, table, ticks: int) -> void:
	var run: Array = scene["run"]
	print("-".repeat(78))
	print("scene      : %s" % str(scene["name"]))

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", rel, null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("  ENTERED  : no — no score loaded for %s" % rel)
		preview.queue_free()
		return

	var entry := str(scene["entry"])
	var how := ""
	if entry.begins_with("click"):
		# Inside the idle span, a few frames short of the frame that jumps back, so the
		# score is genuinely looping when the press lands.
		var hold := int(entry.split("f")[1].split(" ")[0])
		var at: int = maxi(0, hold - 5)
		preview.set("_index", at)
		for i in 8:
			await process_frame
		var centre := _centre_of(entry)
		preview.call("route_press", centre)
		preview.call("route_release", centre)
		how = "clicked (%d, %d) from f%d, inside the idle span" % [
			int(centre.x), int(centre.y), at]
	else:
		var at2: int = maxi(0, int(run[0]) - LEAD_IN)
		preview.set("_index", at2)
		for i in 8:
			await process_frame
		how = "playhead put at f%d, %d before the span, and left to walk in" % [
			at2, LEAD_IN]
	print("  entered  : %s" % how)

	# The elements this scene is expected to put on a channel, and the channels the
	# init claimed. Both come from the static half rather than from the run.
	var want: Dictionary = {}
	for key in scene["elements"]:
		want[str(key)] = int(scene["elements"][key]["type"])
	var alive: Dictionary = {}   # channel -> {member: times seen visible}
	var reached: Dictionary = {} # "lib:id" -> the first texture key it decoded under
	var frames: Dictionary = {}
	var last := -1
	var since := 0
	# What the painter had already parsed when the init first ran. **The cache is
	# cumulative and the score places film loops of its own**, so "in `_loops`" is not
	# by itself evidence that a *scene* drew its element: `doc` and `poz` both have
	# 187..189 painted at their span's first frame, before their init has run, because
	# the score puts them on channels there. Without this baseline the run stopped after
	# one frame with all three loops "painted" and the init never reached -- a pass that
	# proved nothing, and exactly the shape `film_loop_nesting.gd`'s population guard
	# exists to refuse.
	var baseline: Dictionary = {}
	var on_channel: Dictionary = {}
	var init_seen := false
	var right := true
	var spent := 0
	for tick in ticks:
		await process_frame
		spent = tick + 1
		var here := int(preview.call("current_frame"))
		frames[here] = true
		if here == int(scene["init"]) and not init_seen:
			init_seen = true
			for key in preview.get("_loops") as Dictionary:
				baseline[str(key)] = true
		if here != last:
			last = here
			since += 1
			if since >= PRESS_EVERY:
				since = 0
				right = not right
				_press(preview, KEY_RIGHT if right else KEY_LEFT)
			# Sampled once per *score* frame and on every one of them, not only on the
			# rising edge of `visible`. The rising edge misses a channel that was
			# already dressed when the sampler first looked, which showed up as `doc`
			# reporting nothing but member 0 on all three lanes while the painter's own
			# loop cache held all three of its spears.
			for channel in scene["claimed"]:
				if not bool(preview.call("lingo_sprite_prop", int(channel), "visible")):
					continue
				var member := int(preview.call(
					"lingo_sprite_prop", int(channel), "membernum"))
				var seen: Dictionary = alive.get(int(channel), {})
				seen[member] = int(seen.get(member, 0)) + 1
				alive[int(channel)] = seen
				# Which claimed channels an element was actually dressed onto, after
				# entry. This is the evidence that survives a loop the score has
				# already parsed: the cache cannot say who put it there, and a channel
				# holding the member can only be the scene's own assignment, because
				# `puppetSprite` has taken the channel off the score.
				#
				# The library comes from `the castLibNum of sprite` rather than being
				# assumed to be 1. A number alone is not a member reference -- that is
				# the one rule `scenes/preview/scripts.gd` exists to hold -- and a
				# hardcoded 1 here would make this evidence silently never match on a
				# title whose elements live in a linked cast, reporting zero rather than
				# failing, which is `scenes/preview/README.md`'s named failure mode.
				var ekey := "%d:%d" % [_lib(int(preview.call(
					"lingo_sprite_prop", int(channel), "castlibnum"))), member]
				if want.has(ekey):
					var where: Dictionary = on_channel.get(ekey, {})
					where[int(channel)] = true
					on_channel[ekey] = where
		for key in preview.get("_textures") as Dictionary:
			for ekey in want:
				if reached.has(ekey):
					continue
				if str(key).begins_with("%s:" % ekey):
					reached[ekey] = str(key)
		# Stopped on the answer rather than after a fixed window, and the reason is the
		# movie's own `random(5)`: the throw handler picks a lane per pass and only three
		# of five values throw at all, so which of a scene's three loops a bounded window
		# happens to see is a coin toss. Measured over two 3000-frame runs of all six
		# scenes, every element loop was painted in at least one and none in both --
		# `krup` showed 84 and 85 in the first and only 86 in the second. Waiting for the
		# set instead turns that into a difference in how long a run takes rather than a
		# difference in what it reports, which is `film_loop_nesting.gd`'s rule and the
		# same argument `gate.sh`'s header makes about `play_suspends`.
		# The init having run is half the condition. Painted-before-the-init is the
		# score's doing and says nothing about the scene.
		if init_seen and _all_painted(preview, want, on_channel):
			break

	var visited: Array = frames.keys()
	visited.sort()
	print("  played   : %d process frame(s), %d distinct frame(s) f%s..f%s" % [
		spent, visited.size(),
		str(visited[0]) if visited.size() > 0 else "?",
		str(visited[-1]) if visited.size() > 0 else "?"])
	if _verbose:
		print("  frames   : %s" % str(visited))
	var reached_init := frames.has(int(scene["init"]))
	print("  init ran : %s (f%d %s in the frames played)" % [
		"yes" if reached_init else "NO", int(scene["init"]),
		"is" if reached_init else "is NOT"])
	var chans: Array = alive.keys()
	chans.sort()
	for channel in chans:
		var seen: Dictionary = alive[channel]
		var members: Array = seen.keys()
		members.sort()
		var parts: Array = []
		for member in members:
			parts.append("%d on %d frame(s)" % [int(member), int(seen[member])])
		print("  ch %-3d   : visible with %s" % [int(channel), ", ".join(parts)])
	if chans.is_empty():
		print("  channels : none of %s ever became visible" % str(scene["claimed"]))
	var els: Dictionary = scene["elements"]
	var keys: Array = els.keys()
	keys.sort_custom(func(a, b): return int(els[a]["id"]) < int(els[b]["id"]))
	# Two different questions, because a film loop is *painted* and a bitmap is
	# *decoded*. A type-2 member never reaches `_textures` at all -- `_texture_for` is
	# bitmap-and-shape only, which is the whole origin of the bug this survey exists
	# beside -- so asking the texture cache about a loop answers "never" for a loop that
	# drew perfectly. `_loops` is the painter's parse cache, keyed `"lib:id"`, and a key
	# in it means `paint_loop` opened that member to draw it.
	var painted: Dictionary = preview.get("_loops")
	for key in keys:
		var el: Dictionary = els[key]
		if int(el["type"]) == LOOP_TYPE:
			var chans_of: Array = (on_channel.get(str(key), {}) as Dictionary).keys()
			chans_of.sort()
			var verdict := "never painted — not in the painter's loop cache"
			if painted.has(str(key)):
				verdict = "PAINTED"
				if baseline.has(str(key)):
					verdict += " (the score had parsed it before the init too)"
			verdict += ", dressed onto ch %s after the init" % str(chans_of) \
				if not chans_of.is_empty() else ", never dressed onto a claimed channel"
			print("  %-9s: %-9s %-14s %s" % [str(key), "filmLoop",
				('"%s"' % str(el["name"])).left(14), verdict])
			for kid in el["loop_children"]:
				var inner: Array = kid["children"]
				print("             nested %s %s: %d of %d of its own children reached the"
					% [str(kid["key"]),
						"PAINTED" if painted.has(str(kid["key"])) else "NOT painted",
						_decoded(preview, inner), inner.size()]
					+ " texture cache")
			continue
		print("  %-9s: %-9s %-14s %s" % [str(key), str(el["type_name"]),
			('"%s"' % str(el["name"])).left(14),
			("DECODED, texture key %s" % str(reached[key])) if reached.has(key)
				else "no texture key — never decoded"])
	var stats: Dictionary = preview.get("_loop_stats")
	var stat_keys: Array = stats.keys()
	stat_keys.sort()
	for key in stat_keys:
		print("  tally    : %-34s %d" % [str(key), int(stats[key])])
	preview.queue_free()
	await process_frame


## Has every film loop the scene assigns reached the painter's parse cache?
##
## Only the loops. A bitmap element may legitimately never be decoded -- COMEIN's
## `1:87` blank is assigned onto channels that are hidden at the time, and
## `_effective` answers `{}` for a hidden sprite, so the painter never asks for it --
## and waiting for it would spend the whole ceiling on every scene.
func _all_painted(preview: Node, want: Dictionary, on_channel: Dictionary) -> bool:
	var painted: Dictionary = preview.get("_loops")
	var loops := 0
	for key in want:
		if int(want[key]) != LOOP_TYPE:
			continue
		loops += 1
		if not painted.has(str(key)) or not on_channel.has(str(key)):
			return false
	return loops > 0


## How many of a list of `"lib:id"` members the painter asked the cast to decode.
func _decoded(preview: Node, members: Array) -> int:
	var hit := {}
	for key in preview.get("_textures") as Dictionary:
		for member in members:
			if str(key).begins_with("%s:" % str(member)):
				hit[str(member)] = true
	return hit.size()


## The click point out of the entry line the derivation wrote, so the played half and
## the static half cannot disagree about where the hotspot is.
func _centre_of(entry: String) -> Vector2:
	var re := RegEx.create_from_string("centre \\((-?[0-9]+), (-?[0-9]+)\\)")
	var hit := re.search(entry)
	if hit == null:
		return Vector2.ZERO
	return Vector2(int(hit.get_string(1)), int(hit.get_string(2)))


func _press(preview: Node, code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	preview.call("_dispatch_key", down)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	preview.call("_dispatch_key_up", up)


## One scene, printed. True when it assigns a loop that nests.
func _report(scene: Dictionary, table, score, labels, cover: Dictionary) -> bool:
	var run: Array = scene["run"]
	print("-".repeat(78))
	print("scene      : %s" % str(scene["name"]))
	print("  init     : f%d, marker %s, frame script %s" % [
		int(scene["init"]), _marker_label(labels, int(scene["init"])),
		str(scene["init_script"])])
	print("  span     : f%d..f%d (%d frames), scripts %s" % [
		int(run[0]), int(run[-1]), run.size(), str(scene["scripts"])])
	# Derived against claimed, compared here rather than left to the reader. The
	# docstring's argument for the `<int> + <var>` rule is that the movie corroborates
	# it -- the channels the arithmetic yields are the channels the init took off the
	# score -- and an argument from a comparison nobody runs is the stale-claim shape
	# `AGENTS.md` opens with.
	var claimed: Array = scene["claimed"]
	var assigned: Array = (scene["assigned_channels"] as Dictionary).keys()
	assigned.sort()
	var extra: Array = []
	for channel in assigned:
		if not claimed.has(int(channel)):
			extra.append(int(channel))
	print("  claims   : channels %s claimed by the init; %s dressed by its handlers — %s"
		% [str(claimed), str(assigned),
			"agree" if extra.is_empty() else "handlers also dress %s, unclaimed" % str(extra)])
	print("  markers  : %s" % str(_markers_in(labels, int(run[0]), int(run[-1]))))
	print("  exits to : %s" % str(scene["exits"]))

	var els: Dictionary = scene["elements"]
	var keys: Array = els.keys()
	keys.sort_custom(func(a, b): return int(els[a]["id"]) < int(els[b]["id"]))
	print("  elements : %d member(s) assigned onto %d channel(s)" % [
		keys.size(), (scene["assigned_channels"] as Dictionary).size()])
	var nests := false
	var shown := 0
	for key in keys:
		var el: Dictionary = scene["elements"][key]
		var chans: Array = (el["channels"] as Dictionary).keys()
		chans.sort()
		if not _verbose and shown >= 12:
			print("     ... and %d more (use --verbose)" % (keys.size() - shown))
			break
		shown += 1
		var what := str(el["type_name"])
		if int(el["type"]) == LOOP_TYPE:
			what = "filmLoop %d frames looping=%s" % [
				int(el["frames"]), str(el["looping"])]
		print("     %-9s %-34s on ch %-14s %s" % [
			"%d:%d" % [int(el["lib"]), int(el["id"])],
			"%s %s" % [what, ('"%s"' % str(el["name"])) if str(el["name"]) != "" else ""],
			str(chans), str(el["how"])])
		if int(el["type"]) != LOOP_TYPE:
			continue
		var kids: Array = el["loop_children"]
		if kids.is_empty():
			print("        children: %d, none a film loop" % int(el["child_count"]))
			continue
		nests = true
		for kid in kids:
			print("        NESTS   : child %s is a filmLoop, %d frames looping=%s%s"
				% [str(kid["key"]), int(kid["frames"]), str(kid["looping"]),
					(' "%s"' % str(kid["name"])) if str(kid["name"]) != "" else ""])
			print("                  its own children: %s" % str(kid["children"]))

	for note in scene["unbounded"]:
		print("  UNBOUND  : %s" % str(note))

	print("  entry    : %s" % str(scene["entry"]))
	if _show_source:
		for key in scene["sources"]:
			print("  --- script %s" % str(key))
			for line in str(scene["sources"][key]).split("\n"):
				print("      %s" % line)
	return nests


## Frame -> the narrowest frame-script interval covering it.
##
## `scenes/preview/scripts.gd:for_frame`'s rule, carried rather than called: that
## function takes the preview node and resolves through `host._script_in_lib`, so a
## static pass cannot use it. The main channel's own script slot is deliberately
## *not* consulted — this asks which frames a script *runs on as a span*, and the
## per-frame slot answers a different question that has no span to make a run out
## of.
func _coverage(score) -> Dictionary:
	var out := {}
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var span := int(interval["end"]) - int(interval["start"])
		var entry := {
			"lib": _lib(int(interval["script_cast_lib"])),
			"member": int(interval["script_member"]),
			"span": span,
		}
		for frame in range(int(interval["start"]), int(interval["end"]) + 1):
			if out.has(frame) and int(out[frame]["span"]) <= span:
				continue
			out[frame] = entry
	return out


## The covered frames as maximal contiguous runs.
func _runs(cover: Dictionary) -> Array:
	var frames: Array = cover.keys()
	frames.sort()
	var out: Array = []
	var run: Array = []
	for frame in frames:
		if not run.is_empty() and int(frame) != int(run[-1]) + 1:
			out.append(run)
			run = []
		run.append(int(frame))
	if not run.is_empty():
		out.append(run)
	return out


## How many distinct covered-frame scripts mention `puppetSprite`, split by what
## they do with it. Printed beside the scene count because the gap between the two
## is the whole of the discriminator this file rests on: a movie where every mention
## is a claim is a movie where the discriminator has not been exercised, and the
## reader should know that before trusting the scene count.
func _puppet_sites(table, cover: Dictionary) -> Dictionary:
	var out := {"mention": 0, "claim": 0, "release": 0}
	var seen := {}
	var re := RegEx.create_from_string(PUPPET)
	for frame in cover:
		var key := "%d:%d" % [int(cover[frame]["lib"]), int(cover[frame]["member"])]
		if seen.has(key):
			continue
		seen[key] = true
		var hits := re.search_all(_source(table, int(cover[frame]["lib"]),
			int(cover[frame]["member"])))
		if hits.is_empty():
			continue
		out["mention"] = int(out["mention"]) + 1
		var claims := false
		for hit in hits:
			if str(hit.get_string(2)).strip_edges() == "1":
				claims = true
		out["claim" if claims else "release"] = int(out["claim" if claims else "release"]) + 1
	return out


## Every scene in the movie: a covered run holding a frame script that *claims* a
## channel, with the members its own scripts assign.
func _scenes(table, score, labels, cover: Dictionary, runs: Array) -> Dictionary:
	var puppet := RegEx.create_from_string(PUPPET)
	var claim_sites := 0
	var list: Array = []
	for run in runs:
		var init := -1
		var init_script := ""
		var claimed := {}
		for frame in run:
			var lib := int(cover[frame]["lib"])
			var member := int(cover[frame]["member"])
			var src := _source(table, lib, member)
			var mine := {}
			for hit in puppet.search_all(src):
				# The flag, not the call. `, 0` hands the channel back, and six of
				# COMEIN's twelve sites are that -- the losing screens.
				if str(hit.get_string(2)).strip_edges() != "1":
					continue
				for channel in _operand(str(hit.get_string(1)), src)["values"]:
					mine[int(channel)] = true
			if mine.is_empty():
				continue
			claim_sites += 1
			if init >= 0:
				continue
			init = int(frame)
			init_script = "%d:%d" % [lib, member]
			claimed = mine
		if init < 0:
			continue
		var chans: Array = claimed.keys()
		chans.sort()
		list.append(_scene(table, score, labels, cover, run, init, init_script, chans))
	_disambiguate(list)
	return {"list": list, "claim_sites": claim_sites}


## One scene, filled in: its scripts, the members they assign, and its entry.
func _scene(table, score, labels, cover: Dictionary, run: Array, init: int,
		init_script: String, claimed: Array) -> Dictionary:
	var set_re := RegEx.create_from_string(SET_MEMBER)
	var dot_re := RegEx.create_from_string(DOT_MEMBER)
	var member_re := RegEx.create_from_string(MEMBER_OF)
	var named_re := RegEx.create_from_string(NUMBER_OF)

	# The scene's own scripts: the frame scripts covering its frames, and the
	# sprite behaviours whose interval overlaps them. Both can assign a member, and
	# leaving the behaviours out would report a scene's elements as whatever half of
	# them the frame scripts happen to own.
	var scripts := {}
	var order: Array = []
	for frame in run:
		var key := "%d:%d" % [int(cover[frame]["lib"]), int(cover[frame]["member"])]
		if not scripts.has(key):
			scripts[key] = [int(cover[frame]["lib"]), int(cover[frame]["member"])]
			order.append(key)
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite":
			continue
		if int(interval["end"]) < int(run[0]) or int(interval["start"]) > int(run[-1]):
			continue
		var key2 := "%d:%d" % [
			_lib(int(interval["script_cast_lib"])), int(interval["script_member"])]
		if scripts.has(key2):
			continue
		scripts[key2] = [_lib(int(interval["script_cast_lib"])),
			int(interval["script_member"])]
		order.append(key2)

	var elements := {}
	var assigned := {}
	var unbounded: Array = []
	var sources := {}
	for key in order:
		var lib: int = scripts[key][0]
		var member: int = scripts[key][1]
		var src := _source(table, lib, member)
		if src == "":
			continue
		sources[key] = src
		var found: Array = []
		for hit in set_re.search_all(src):
			found.append([str(hit.get_string(2)), str(hit.get_string(3)),
				str(hit.get_string(1)) != ""])
		for hit in dot_re.search_all(src):
			found.append([str(hit.get_string(1)), str(hit.get_string(3)),
				str(hit.get_string(2)) != ""])
		for pair in found:
			var chan_expr: String = pair[0]
			var rhs: String = pair[1]
			var is_num: bool = pair[2]
			var chans: Dictionary = _operand(chan_expr, src)
			if (chans["values"] as Array).is_empty():
				unbounded.append("%s: channel `%s` unbounded" % [key, chan_expr.strip_edges()])
				continue
			# A name reference is resolved before any arithmetic is looked for, because
			# it is not arithmetic: `the number of member "dotdot" of castLib 1` is a
			# lookup, and treating it as an unbounded expression loses a member the
			# container can name exactly.
			var named := named_re.search(rhs)
			if named != null:
				var named_lib := lib
				if str(named.get_string(2)) != "":
					var nl: Dictionary = _operand(str(named.get_string(2)), src)
					if not (nl["values"] as Array).is_empty():
						named_lib = _lib(int((nl["values"] as Array)[0]))
				var by_name := _number_of(table, named_lib, str(named.get_string(1)))
				if by_name <= 0:
					unbounded.append("%s: member \"%s\" names nothing in cast %d"
						% [key, str(named.get_string(1)), named_lib])
					continue
				_record(table, elements, assigned, named_lib, by_name, chans["values"],
					"named \"%s\"" % str(named.get_string(1)))
				continue
			# `member(id, lib)` names its own library; `memberNum` and a bare number
			# do not, and the loop's own library is then the answer.
			var wrapped := member_re.search(rhs)
			var id_expr := str(wrapped.get_string(1)) if wrapped != null else rhs
			var lib_expr := str(wrapped.get_string(2)) if wrapped != null else ""
			if wrapped == null and not is_num:
				# `set the member of sprite N to <not a member() call>` is a member
				# reference this scan cannot follow -- a variable holding one, say.
				unbounded.append("%s: member expression `%s` is not a member() call"
					% [key, rhs.strip_edges()])
				continue
			var ids: Dictionary = _operand(id_expr, src)
			if (ids["values"] as Array).is_empty():
				unbounded.append("%s: member `%s` unbounded" % [key, id_expr.strip_edges()])
				continue
			var target_lib := lib
			if lib_expr != "":
				var libs: Dictionary = _operand(lib_expr, src)
				if not (libs["values"] as Array).is_empty():
					target_lib = _lib(int((libs["values"] as Array)[0]))
			var how := "literal" if str(ids["how"]) == "" else str(ids["how"])
			for id in ids["values"]:
				_record(table, elements, assigned, target_lib, int(id),
					chans["values"], how)

	var exits := _exits(sources, labels, int(run[0]), int(run[-1]))
	return {
		"name": _name_of(labels, init, exits),
		"run": run, "init": init, "init_script": init_script,
		"claimed": claimed, "scripts": order, "exits": exits,
		"elements": elements, "assigned_channels": assigned,
		"unbounded": unbounded, "sources": sources,
		"entry": _entry(table, score, cover, run, init),
	}


## The markers this scene's own scripts leave for, and which of them are outside
## it: `go("fritzwin")` and `go("fritzend")` in the throw and collision handlers.
##
## Worth deriving because they are the only place in the container that **names the
## character** — the init's own marker is `return1`, which numbers the scenes and
## says nothing about whose game it is. A scene called `return5` and a scene called
## `hatuli` are the same finding and only one of them can be read.
func _exits(sources: Dictionary, labels, from: int, to: int) -> Array:
	var go := RegEx.create_from_string("(?i)go\\s*(?:to\\s*)?\\(?\\s*\"([^\"]+)\"")
	var seen := {}
	for key in sources:
		for hit in go.search_all(str(sources[key])):
			var name := str(hit.get_string(1))
			var frame := int(labels.labels.get(name.to_lower(), -1))
			if frame < 0 or (frame >= from and frame <= to):
				continue  # unresolvable, or a jump inside the scene's own span
			seen[name] = frame
	var out: Array = []
	for name in seen:
		out.append("%s f%d" % [str(name), int(seen[name])])
	out.sort()
	return out


## What to call a scene. Its init's marker where it has a name, and the longest
## common prefix of the names it exits to where those agree on one — which for
## COMEIN turns `return1` into `fritz`, because the scene leaves for `fritzend` and
## `fritzwin` and for nothing else.
func _name_of(labels, init: int, exits: Array) -> String:
	var stem := ""
	for entry in exits:
		var name := str(entry).split(" ")[0]
		if stem == "":
			stem = name
			continue
		var shared := 0
		while shared < stem.length() and shared < name.length() \
				and stem[shared] == name[shared]:
			shared += 1
		stem = stem.substr(0, shared)
	if stem.length() >= 3:
		return stem
	var marker := str(labels.marker_at(init))
	return marker if marker != "" else "f%d" % init


## Scenes that derived the same name are told apart by their init frame. Three of
## `rating/blatack1.dir`'s exit to the same marker and so earn the same stem, and a
## report with three rows called `egozdead` is a report nobody can quote from.
static func _disambiguate(list: Array) -> void:
	var tally := {}
	for scene in list:
		tally[str(scene["name"])] = int(tally.get(str(scene["name"]), 0)) + 1
	for scene in list:
		if int(tally[str(scene["name"])]) > 1:
			scene["name"] = "%s@f%d" % [str(scene["name"]), int(scene["init"])]


## One member landing on some channels, folded into the scene's element set.
func _record(table, elements: Dictionary, assigned: Dictionary, lib: int, id: int,
		channels: Array, how: String) -> void:
	var key := "%d:%d" % [lib, id]
	if not elements.has(key):
		elements[key] = _element(table, lib, id)
	for channel in channels:
		assigned[int(channel)] = true
		(elements[key]["channels"] as Dictionary)[int(channel)] = true
	if not (elements[key]["how"] as Array).has(how):
		(elements[key]["how"] as Array).append(how)


## A member number for a name, in one library. 0 where the cast has no such name.
func _number_of(table, lib: int, name: String) -> int:
	var cast = table.cast_for(lib)
	if cast == null:
		return 0
	return int(cast.number_of(name))


## One assigned member: what it is, and what is inside it if it is a film loop.
func _element(table, lib: int, id: int) -> Dictionary:
	var m: Dictionary = table.get_member(lib, id)
	var out := {
		"lib": lib, "id": id, "type": int(m.get("type", 0)),
		"type_name": str(m.get("type_name", "absent")),
		"name": str(m.get("name", "")), "how": [] as Array,
		"channels": {}, "frames": 0, "looping": false,
		"child_count": 0, "loop_children": [] as Array,
	}
	if int(m.get("type", 0)) != LOOP_TYPE:
		return out
	out["looping"] = bool(m.get("looping", true))
	# Through the preview's own entry point, so the nesting reported is the one the
	# painter walks rather than a second reading written here.
	var loop = FilmLoopView.open_loop(lib, m, table)
	if loop == null:
		return out
	out["frames"] = int(loop.frame_count)
	var seen := {}
	for i in loop.frame_count:
		for kid in loop.children(i):
			var kid_lib: int = FilmLoopView.child_lib(kid, lib, table)
			if kid_lib < 0:
				continue
			var kid_key := "%d:%d" % [kid_lib, int(kid["cast_id"])]
			if seen.has(kid_key):
				continue
			seen[kid_key] = true
			var cm: Dictionary = table.get_member(kid_lib, int(kid["cast_id"]))
			if int(cm.get("type", 0)) != LOOP_TYPE:
				continue
			var inner = FilmLoopView.open_loop(kid_lib, cm, table)
			var grandkids := {}
			if inner != null:
				for j in inner.frame_count:
					for gk in inner.children(j):
						var gk_lib: int = FilmLoopView.child_lib(gk, kid_lib, table)
						grandkids["%d:%d" % [gk_lib, int(gk["cast_id"])]] = true
			var names: Array = grandkids.keys()
			names.sort()
			(out["loop_children"] as Array).append({
				"key": kid_key, "name": str(cm.get("name", "")),
				"frames": 0 if inner == null else int(inner.frame_count),
				"looping": bool(cm.get("looping", true)),
				"children": names,
			})
	out["child_count"] = seen.size()
	return out


## How a player gets into this scene.
##
## An idle span is a closed loop of frames whose last frame's script sends the
## playhead back to the marker covering it, so nothing in the score can leave it
## and whatever does is a sprite behaviour. Where the run has such a frame *before*
## its init, the way in is a click; where it has none, the movie plays in on its
## own and the entry is the run's first frame.
func _entry(table, score, cover: Dictionary, run: Array, init: int) -> String:
	var holds := RegEx.create_from_string(HOLDS)
	var gated := RegEx.create_from_string(SOUND_GATED)
	var mouse := RegEx.create_from_string(MOUSE_GO)
	var at := -1
	for frame in run:
		if int(frame) >= init:
			break
		var src := _source(table, int(cover[frame]["lib"]), int(cover[frame]["member"]))
		if holds.search(src) != null and gated.search(src) == null:
			at = int(frame)
	if at < 0:
		return "walk in: no closed loop before f%d, land before f%d and play" % [
			init, int(run[0])]

	# The span the loop covers: back to the marker the jump returns to, which is the
	# last covered frame before it that is not part of the same jump. The score's own
	# sprite intervals over that span are where the way out has to be.
	var span_from := at
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite":
			continue
		if int(interval["end"]) < at or int(interval["start"]) > at:
			continue
		var lib := _lib(int(interval["script_cast_lib"]))
		var member := int(interval["script_member"])
		var src := _source(table, lib, member)
		if mouse.search(src) == null or not src.to_lower().contains("go"):
			continue
		var channel := int(interval["channel"])
		var rect := _rect_of(table, score, channel, at)
		span_from = int(interval["start"])
		return ("click: idle loop holds at f%d (%d:%d), left by ch %d behaviour %d:%d "
			% [at, int(cover[at]["lib"]), int(cover[at]["member"]), channel, lib, member]
			+ "on mouse -> go; sprite spans f%d..f%d, rect %s, centre (%d, %d)"
			% [int(interval["start"]), int(interval["end"]), str(rect),
				int(rect.get_center().x), int(rect.get_center().y)])
	return "click: idle loop holds at f%d but no mouse behaviour over it" % span_from


## A channel's stage rect on a frame, from the score's own record.
func _rect_of(table, score, channel: int, frame: int) -> Rect2:
	for sprite in score.frame(frame).get("sprites", []):
		if int(sprite["channel"]) != channel:
			continue
		var m: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		return Geometry.stage_rect(sprite, m)
	return Rect2()


## What integers an operand can be, and how it was decided.
##
## A literal, or `<int> + <var>` in either order — in which case the variable's
## range is whatever the same handler compares it against. `if (x = 1) or (x = 2)`
## bounds `x` to 1 and 2, and `x = random(5)` contributes nothing because it is not
## a literal comparison. Loose about which of the two an author meant, because
## Lingo spells assignment and equality the same way and the union is the honest
## answer either way: an assignment of a literal is a value the variable takes, and
## a comparison against one is a value it is expected to take.
func _operand(expr: String, source: String) -> Dictionary:
	var text := expr.strip_edges()
	while text.begins_with("(") and text.ends_with(")"):
		text = text.substr(1, text.length() - 2).strip_edges()
	if text.is_valid_int():
		return {"values": [int(text)], "how": ""}
	var sum := RegEx.create_from_string(
		"(?i)^(?:([0-9]+)\\s*\\+\\s*([a-z_][a-z0-9_]*)|([a-z_][a-z0-9_]*)\\s*\\+\\s*([0-9]+))$")
	var hit := sum.search(text)
	if hit == null:
		return {"values": [] as Array, "how": "unbounded `%s`" % text}
	var base := int(hit.get_string(1) if str(hit.get_string(1)) != "" else hit.get_string(4))
	var name := str(hit.get_string(2) if str(hit.get_string(2)) != "" else hit.get_string(3))
	var offsets := _bounds(name, source)
	if offsets.is_empty():
		return {"values": [] as Array, "how": "unbounded `%s`" % text}
	var values: Array = []
	for offset in offsets:
		values.append(base + int(offset))
	return {"values": values, "how": "derived %d+%s, %s in %s" % [
		base, name, name, str(offsets)]}


## The literals a handler compares or assigns a name against, ascending.
func _bounds(name: String, source: String) -> Array:
	var re := RegEx.create_from_string(
		"(?i)(?<![a-z0-9_])%s\\s*=\\s*(-?[0-9]+)(?![0-9])" % name)
	var seen := {}
	for hit in re.search_all(source):
		seen[int(hit.get_string(1))] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## A member's Lingo text, or "". `director_cast.gd` puts it in `member["source"]`.
func _source(table, lib: int, member: int) -> String:
	if member <= 0:
		return ""
	var m: Dictionary = table.get_member(lib, member)
	return str(m.get("source", ""))


## The score writes a script's library raw; `scripts.gd:in_lib` normalises it.
## Missing this resolves the number in the wrong cast, where it finds a stranger.
func _lib(raw: int) -> int:
	return 1 if raw <= 0 or raw == 0xFFFF else raw


func _marker_label(labels, frame: int) -> String:
	for i in labels.markers.size():
		if int(labels.markers[i]["frame"]) != frame:
			continue
		var name := str(labels.markers[i]["name"])
		return "%d \"%s\"" % [i, name] if name != "" else "%d (unnamed)" % i
	return "none at this frame"


func _markers_in(labels, from: int, to: int) -> Array:
	var out: Array = []
	for marker in labels.markers:
		var frame := int(marker["frame"])
		if frame < from or frame > to:
			continue
		out.append("f%d %s" % [frame,
			str(marker["name"]) if str(marker["name"]) != "" else "(unnamed)"])
	return out
