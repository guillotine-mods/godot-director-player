extends SceneTree
## A `sound playFile` for a file that is not on the disc is **reported**, not
## swallowed.
##
##   godot --headless --path . --script tools/audio_misses.gd
##   godot --headless --path . --script tools/audio_misses.gd -- --root rating
##
## `bugs.md` 88 is the precedent this enforces and it has two halves: absent game
## data is not an engine defect **provided** the absence is proved from outside
## the pipeline that noticed it *and* the engine **reports** it rather than
## failing silently. `bugs.md` 46 (Piposh 1 and `piposh-ru` compose a
## `PIPDATA/FX` path against a tree that has none) and `bugs.md` 68 (Rating asks
## for `startmus.aif`, `brakemus.aif` and `midgame.aif`, none of which is
## anywhere under `games/rating` under any name) are both the first half. This is
## the second, and it is the half this port did not hold: `_fail` wrote one
## `warn` line per failure and **nothing collected it**, so a session that could
## not play three sounds ended without saying so anywhere a person or a harness
## could read.
##
## ## Why this drives `AudioDirector` directly and not a movie
##
## The subject is the mixer, not any title. Asserting through a movie would need
## a movie that asks for an absent file, which is exactly the data gap this
## project is not allowed to depend on -- `games/piposh` got its `FX` tree back
## from the disc between two re-checks of entry 46, and a harness keyed on that
## absence would have gone red for the *good* news. Requesting a name that cannot
## exist on any disc measures the engine instead.
##
## ## What is asserted
##
##   * a request that resolves to nothing is recorded as a distinct miss, with
##     the request in it, and reaches `miss_report()`;
##   * the same request repeated is **one** miss with a count, not N misses --
##     which is the shape the log has never had. `audio_director.gd:321`
##     re-fails on every re-entry of the room, so Piposh 1's deck loop writes
##     four hundred identical lines for one absent file, and a reader counting
##     lines counts how long the playhead sat there;
##   * two different absent requests are two misses, so the collapse above is by
##     request and not by "something failed";
##   * an empty request is recorded too, because `sound playFile 2, ""` claims
##     the channel exactly like a missing file does and is the one failure a
##     script can cause on its own;
##   * a request that **does** resolve records nothing, so the ledger cannot be
##     passing by saying yes to everything;
##   * and the channel is not busy afterwards either way -- `soundBusy` answering
##     true for a sound that never started is the unrecoverable wait `_fail`'s own
##     header is about, and it is worth re-asserting beside the reporting because
##     the two are the same function.
##
## Title-agnostic: the absent names are nonsense on any disc, and the present one
## is found by walking whatever root this is pointed at.

const Harness := preload("res://tools/lib/harness.gd")
const Paths := preload("res://director/director_paths.gd")

## Names no disc can hold. Long, and with a marker in them, so a root that
## somehow did carry one would be obvious rather than confusing.
const ABSENT_A := "harness\\no-such-sound-a-4f3c21.aif"
const ABSENT_B := "harness\\no-such-sound-b-4f3c21.aif"

## Enough repeats to tell "one entry counted N times" from "N entries".
const REPEATS := 5

## Extensions the index accepts, used only to pick a subject that certainly
## resolves. A root with none skips that one case and says so.
const SOUND_EXTENSIONS := ["wav", "ogg", "mp3", "aif"]


## The first sound file at least two folders deep, root-relative -- deep enough
## that the request carries a folder and exercises the same resolver path a
## movie's would.
func _subject(root: String, at: String = "") -> String:
	var here := root if at == "" else root.path_join(at)
	var dir := DirAccess.open(here)
	if dir == null:
		return ""
	var subs: Array = []
	for name in dir.get_files():
		if name.get_extension().to_lower() in SOUND_EXTENSIONS \
				and at.split("/", false).size() >= 2:
			return at.path_join(name)
	for name in dir.get_directories():
		if not name.begins_with("."):
			subs.append(name)
	subs.sort()
	for name in subs:
		var found := _subject(root, at.path_join(name) if at != "" else str(name))
		if found != "":
			return found
	return ""


func _init() -> void:
	var h := Harness.new()
	# An autoload is not on the tree during `_init`.
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if audio == null:
		print("no AudioDirector; this has to run in the project, not standalone")
		quit(1)
		return
	var paths := Paths.new()
	paths.load_config()
	print("root: %s" % paths.root)

	# The boot sequence may legitimately have missed something already; this
	# harness is about its own requests.
	audio.call("clear_misses")

	# ------------------------------------------------ one absent file, repeated
	h.begin("an absent file is reported once, with a count")
	for i in REPEATS:
		audio.call("play_file", 1, ABSENT_A)
	var after: int = int(audio.call("miss_count"))
	h.check("the request was recorded at all", after == 1, "%d distinct miss(es)" % after)
	var entries: Array = audio.call("misses")
	var found := {}
	for entry_value in entries:
		var entry: Dictionary = entry_value
		found[str(entry["request"])] = entry
	h.check(
		"recorded under the request the script made",
		found.has(ABSENT_A.to_lower()),
		", ".join(PackedStringArray(found.keys())),
	)
	if found.has(ABSENT_A.to_lower()):
		h.check(
			"%d asks are one miss counted %d times, not %d misses" % [
				REPEATS, REPEATS, REPEATS],
			int(found[ABSENT_A.to_lower()]["count"]) == REPEATS,
			"count %d" % int(found[ABSENT_A.to_lower()]["count"]),
		)
	# The other half of `_fail`, re-asserted here because it is the same function
	# and a channel that answers busy for a sound that never started is a wait
	# nothing in the movie can end.
	h.check(
		"the channel is not busy for a sound that never started",
		not bool(audio.call("sound_busy", 1)),
		"soundBusy(1)",
	)
	h.complete("an absent file is reported once, with a count")

	# ------------------------------------------------- a second, different name
	h.begin("two different absent files are two misses")
	audio.call("play_file", 1, ABSENT_B)
	var two: int = int(audio.call("miss_count"))
	h.check("the ledger collapses by request, not by outcome", two == 2, "%d" % two)
	h.complete("two different absent files are two misses")

	# --------------------------------------------------------- an empty request
	# `sound playFile 2, ""` is a real thing a script does -- a global holding the
	# filename was never set -- and it takes the channel exactly as a missing file
	# does. It has its own `_fail` call site, so it needs its own case.
	h.begin("an empty request is reported too")
	audio.call("play_file", 3, "")
	var three: int = int(audio.call("miss_count"))
	h.check("recorded", three == 3, "%d" % three)
	h.complete("an empty request is reported too")

	# ------------------------------------------------------------- the report
	h.begin("the session can state what it could not play")
	var report := str(audio.call("miss_report"))
	print("")
	print(report)
	print("")
	h.check("the report is not empty", report != "", "%d chars" % report.length())
	h.check(
		"it names every distinct request",
		report.contains(ABSENT_A.to_lower()) and report.contains(ABSENT_B.to_lower()),
		"",
	)
	# The sentence that stops the next reader re-diagnosing this as a resolver
	# fault, which is what happened every previous time.
	h.check(
		"it says the path was composed and the file is absent, not that lookup failed",
		report.to_lower().contains("not in the game tree"),
		"",
	)
	h.complete("the session can state what it could not play")

	# ---------------------------------------------- and a file that does resolve
	h.begin("a request that resolves records nothing")
	var subject := _subject(str(paths.root))
	if subject == "":
		# Says so rather than passing quietly. A root with no sound two folders
		# deep cannot express this case and the run should show that it did not.
		h.check(
			"this root holds no sound to test the negative with",
			false,
			"point it at a root that does; searched %s" % paths.root,
		)
	else:
		var before: int = int(audio.call("miss_count"))
		audio.call("play_file", 4, subject.to_lower())
		var after_ok: int = int(audio.call("miss_count"))
		h.check(
			"%s played without being recorded as a miss" % subject,
			after_ok == before,
			"%d -> %d" % [before, after_ok],
		)
		audio.call("stop_channel", 4)
	h.complete("a request that resolves records nothing")

	quit(h.finish("a missing sound is reported, bugs.md 46/68 under 88's rule"))
