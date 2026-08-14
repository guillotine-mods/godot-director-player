extends SceneTree
## The decoder-extension gate: prove that with no extension installed the engine
## is the engine it was, and report exactly what changes when one is.
##
##   godot --headless --audio-driver Dummy --path . --script tools/video_plugin.gd
##   godot --headless --audio-driver Dummy --path . --script tools/video_plugin.gd -- \
##       --root res://test-games/itamar-magichat --boot magichat.dir
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --boot M      the movie to open before reading the engine's readers
##   --list        print every media file found and what the adapter says about it
##
## ## What this asserts, and why it is not `video_fallback`'s job
##
## `tools/video_fallback.gd` asserts the *player-visible* invariant: no video
## frame holds the playhead for ever, and the property surface answers what its
## media is. That is about behaviour with whatever backends happen to exist.
##
## This one is about the **gate** — the condition under which a third backend
## exists at all — and the reason it is a separate harness is that its subject is
## the absent case, which `video_fallback` cannot distinguish from the present
## one. Checks 1-3 below are the absent case and are what every shipped title and
## both nightly runners exercise; 4-8 are the present one and were written after
## an extension was installed and run. Each has a named failure it prevents:
##
##   1. **No engine file `preload`s an addon path.** `preload` of a script that
##      is not there is a GDScript *parse* error, and a parse error in a file the
##      preview preloads takes the whole engine down before a movie opens — every
##      gate entry, every title, over a decoder for one unshipped test title.
##      This is a source scan rather than a runtime check because that failure
##      happens at parse time, where no runtime check can reach it.
##   2. **With no extension installed the adapter declines everything**, by the
##      class gate and before the extension table is consulted, and
##      `handles()` is false for every container this tree holds.
##   3. **The engine's own readers carry no plugin backend** after a real boot
##      of a real corpus. That is the end-to-end form of 2: it reads
##      `host.video_readers`, which is what the movie actually got, rather than
##      re-asking the adapter the question the adapter already answered.
##
## And one contract check that belongs beside them because it is what the whole
## feature turns on: **`getPlaybackEvent` is VOID for a channel with no media.**
## `docs/DIGITAL_VIDEO.md` §3 has the account — `BehaviorScript 134`'s other arm
## is `go(the frame)` and never ends — and a third backend is exactly the kind of
## change that can make a channel answer 1 because a reader exists somewhere.
##
## ## When an extension *is* installed
##
## The checks invert rather than disappear, and **what they assert changed once
## an extension was actually run against them.** The first version of this branch
## asserted "at least one media file opens through it". That is not a statement
## about this port: whether any file opens is decided by the `configure` flags of
## somebody else's FFmpeg build, and EIRTeam.FFmpeg 1.1.4 — measured, and
## `docs/DIGITAL_VIDEO.md` §9 has it — decodes **none** of this tree's 22 MPEG-1
## clips or its one MS-RLE AVI. That assertion made the suite red over a build
## options, which is the same mistake `palette_corpus` made when it failed on a
## 1990s cast's bad member numbering: **a harness must assert what this port
## controls.**
##
## So the count is printed as a finding and the assertions are these, each of
## which is true whether the installed build decodes 23 files or 0:
##
##   4. **`handles()` answers exactly the loader's published list** — true for
##      every extension an installed `VideoStream` loader claims, false for every
##      one of `EXTENSIONS` it does not. That is the "published list *replaces*
##      `EXTENSIONS` rather than joining it" rule, and a union would show up here
##      as `handles("x.mpg")` true against a build with no MPEG demuxer.
##   5. **No stock extension is claimed.** `.ogv`, `.res` and `.tres` must stay
##      false, because the sidecar cache is full of `.ogv` and the project is full
##      of `.tres`; `STOCK_EXTENSIONS` is the subtraction that keeps them out and
##      this is what proves the subtraction is still applied.
##   6. **Nothing ever opens with a duration of nought.** The §3 invariant, and
##      the one `director_plugin_video.gd:open` exists to hold: a member that
##      reports ready with no duration turns `go(the frame)` into a hang. Asserted
##      from outside the adapter rather than trusted from inside it.
##   7. **Every decline carries a named reason** — an empty `error` is a decline
##      nobody can debug, and this is the difference between "declined" and
##      "silently did nothing".
##   8. **A file the plugin declines is still opened by the backend behind it.**
##      The resolution order proved end to end rather than read: `logo.avi` is a
##      container the installed loader *claims* (`avi` is in its published list)
##      and cannot *decode* (no `msrle`), so the adapter refuses on duration and
##      `director_avi.gd` takes it. If that ever stopped happening, one installed
##      extension would have taken away a format this port decodes in GDScript.
##
## And the ordering itself is asserted as a **source scan** of
## `scenes/preview/video.gd`, in both the installed and the absent case, because
## it is the one part of "the plugin is chosen over the sidecar" that no corpus
## can express: with a build that decodes nothing there is no file for which the
## two arms compete, and a runtime check would silently assert nothing. The scan
## says the plugin arm is written before the sidecar arm and the sidecar arm
## before the AVI arm, which is what §8.1 claims the order is.
##
## Title-agnostic: it names no game, no channel and no member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Plugin := preload("res://director/director_plugin_video.gd")
const Ogg := preload("res://director/director_ogg.gd")
const Avi := preload("res://director/director_avi.gd")
const Paths := preload("res://director/director_paths.gd")

## The directories whose scripts are loaded by the running engine. `tools/` is
## deliberately outside it: a harness that preloaded an addon would break itself
## and nothing else, and one of them may legitimately want to.
const ENGINE_DIRS := ["res://director", "res://scenes", "res://lingo",
	"res://autoload", "res://scripts"]

## Process frames to let `go to movie` land — the same budget `video_fallback`
## uses and for the same reason.
const OPEN_FRAMES := 8

## How many media files to try the adapter against. The tree holds 439 and
## opening every one of them through a native decoder is minutes; the point is
## made by a sample, and `--list` prints the whole set without opening it.
##
## The sample is drawn **one extension at a time** (`_sample`) rather than off
## the front of a sorted list, and that is not tidiness. Sorted, this corpus's
## first eight files are eight `.mpg` from `heb/album/` and the tree's only
## `.avi` never got opened at all — so the fallthrough check, the one that proves
## a format this port decodes in GDScript survives an extension claiming its
## extension, reported "no file in this corpus exercises" it while the file was
## sitting there at position 23. Eight copies of one container prove one thing
## eight times.
const OPEN_LIMIT := 8


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _sweep(h)
	quit(h.finish(
		"a decoder extension is used when installed and invisible when it is not"))


func _sweep(h: Harness) -> void:
	var args := Args.parse()
	var verbose := Args.flag(args, "list")
	var installed := Plugin.installed_class()

	var paths := Paths.new()
	if not paths.load_config():
		h.begin("a corpus to read")
		h.check("the config names a game", false, Paths.CONFIG_PATH)
		h.complete("a corpus to read")
		return
	var corpus := str(paths.root).get_file()

	print("")
	print("root              : %s" % paths.root)
	print("decoder extension : %s" % (installed if installed != "" else "none installed"))
	print("candidate classes : %s" % ", ".join(PackedStringArray(Plugin.CLASSES)))
	var claimed := Plugin._loader_extensions()
	print("extensions claimed by an installed VideoStream loader (minus the stock set): %s"
		% ("(none)" if claimed.is_empty() else ", ".join(claimed)))
	print("")

	# ------------------------------------------------- 1. no addon preload anywhere
	var scan_case := "no engine file preloads a path that may not exist"
	h.begin(scan_case)
	var offenders: Array[String] = []
	var mentions: Array[String] = []
	for dir in ENGINE_DIRS:
		_scan_scripts(dir, offenders, mentions)
	h.check(
		"no `preload(\"res://addons/…\")` under %s" % ", ".join(PackedStringArray(ENGINE_DIRS)),
		offenders.is_empty(),
		"; ".join(offenders) if not offenders.is_empty()
			else "a preload of a missing script is a parse error, and it takes the "
				+ "engine down before any movie opens")
	# A mention that is not a preload is a `load()` or a string, both of which are
	# runtime and both of which are allowed. Printed rather than asserted, because
	# the next session to add one should see it and decide.
	if not mentions.is_empty():
		print("  runtime (non-preload) references to res://addons/, which are allowed:")
		for line in mentions:
			print("    " + line)
	h.complete(scan_case)

	# ------------------------------------------------------ 2. the adapter's gate
	var gate_case := "the adapter's gate is the class, asked before anything else"
	h.begin(gate_case)
	if installed == "":
		h.check("`available()` is false with no extension installed",
			not Plugin.available(),
			"this is the state every shipped title runs in today")
		var wrongly: Array[String] = []
		for extension in Plugin.EXTENSIONS:
			if Plugin.handles("x.%s" % str(extension)):
				wrongly.append(str(extension))
		h.check(
			"`handles()` is false for all %d container extensions" % Plugin.EXTENSIONS.size(),
			wrongly.is_empty(),
			"took %s with nothing installed" % ", ".join(PackedStringArray(wrongly))
				if not wrongly.is_empty()
				else "the class gate runs first, so the extension table is never "
					+ "reached and cannot be wrong")
		# With nothing installed the only registered `VideoStream` loader is stock
		# Godot's Theora one, which `_loader_extensions` filters out. Anything else
		# here means a loader this harness did not account for is claiming the type.
		h.check("no non-stock loader claims the VideoStream type",
			claimed.is_empty(),
			"claimed: %s" % ", ".join(claimed) if not claimed.is_empty() else "")
	else:
		h.check("`available()` is true and names %s" % installed,
			Plugin.available() and Plugin.installed_class() == installed)
		h.check("it is concrete and instantiable",
			ClassDB.can_instantiate(installed),
			"an abstract class passes `class_exists` and returns null from "
				+ "`instantiate`, which is a null at the point the media is wanted")
		var made: Variant = ClassDB.instantiate(installed)
		h.check("`ClassDB.instantiate(%s)` yields a VideoStream" % installed,
			made != null and made is VideoStream,
			"the adapter type checks this and declines anything else")

		# Check 4. The published list *replaces* `EXTENSIONS`, and the two halves
		# of that are separate failures: a container the build demuxes that
		# `handles()` refuses is a format lost for no reason, and a container the
		# build does **not** demux that `handles()` takes is the file being opened
		# and failing later instead of being declined by one string comparison.
		var not_taken: Array[String] = []
		for extension in claimed:
			if not Plugin.handles("x.%s" % str(extension)):
				not_taken.append(str(extension))
		h.check("`handles()` is true for all %d extension(s) the loader publishes"
				% claimed.size(),
			not_taken.is_empty(),
			"refused %s" % ", ".join(PackedStringArray(not_taken))
				if not not_taken.is_empty() else "")
		var over_claimed: Array[String] = []
		for extension in Plugin.EXTENSIONS:
			var name := str(extension)
			if _published_has(claimed, name):
				continue
			if Plugin.handles("x.%s" % name):
				over_claimed.append(name)
		h.check(
			"`handles()` is false for the %d container(s) in `EXTENSIONS` the "
				% (Plugin.EXTENSIONS.size() - _overlap(claimed, Plugin.EXTENSIONS))
				+ "loader does not publish",
			over_claimed.is_empty(),
			"took %s anyway, so `EXTENSIONS` is being unioned with the published "
				% ", ".join(PackedStringArray(over_claimed))
				+ "list instead of replaced by it, and a stripped build is handed "
				+ "files it will fail on later"
				if not over_claimed.is_empty()
				else "a stripped build declines by one string comparison, before "
					+ "any file is opened")

		# Check 5. The sidecar cache is `.ogv` and this project is full of
		# `.tres`; an extension claiming either would move a working path onto an
		# untested one. `STOCK_EXTENSIONS` is the subtraction and this is its test.
		var stock_taken: Array[String] = []
		for extension in Plugin.STOCK_EXTENSIONS:
			if Plugin.handles("x.%s" % str(extension)):
				stock_taken.append(str(extension))
		h.check("no extension stock Godot already claims is offered to the plugin",
			stock_taken.is_empty(),
			"took %s, and `.ogv` is what the whole sidecar cache is"
				% ", ".join(PackedStringArray(stock_taken))
				if not stock_taken.is_empty() else "")
	h.complete(gate_case)

	# ---------------------------------------- 2b. the order, read from the source
	#
	# Asserted in both branches and by reading rather than by running, because it
	# is the half no corpus can express: an installed build that decodes none of
	# this tree's containers never puts the plugin arm and the sidecar arm in
	# competition, so a runtime check would pass while asserting nothing. That is
	# the shape `porting-fidelity-verification` calls a check whose two readings
	# cannot disagree.
	var order_case := "the resolution order in preview/video.gd is plugin, sidecar, AVI"
	h.begin(order_case)
	var order := _resolution_order()
	h.check("`video.gd:_open` tries the plugin before the sidecar",
		order.get("plugin", -1) > 0 and order.get("sidecar", -1) > 0
			and int(order["plugin"]) < int(order["sidecar"]),
		"plugin arm at line %s, sidecar arm at line %s — `docs/DIGITAL_VIDEO.md` "
			% [str(order.get("plugin", "?")), str(order.get("sidecar", "?"))]
			+ "§8.1 is the argument for that order: the extension plays the "
			+ "original media and the sidecar plays a copy")
	h.check("and the sidecar before the MS-RLE AVI reader",
		order.get("sidecar", -1) > 0 and order.get("avi", -1) > 0
			and int(order["sidecar"]) < int(order["avi"]),
		"sidecar arm at line %s, AVI arm at line %s"
			% [str(order.get("sidecar", "?")), str(order.get("avi", "?"))])
	h.complete(order_case)

	# -------------------------------------------- 3. what the adapter says on disc
	var media := _media_files(str(paths.root))
	var media_case := "%s: the adapter's verdict on the media this corpus holds" % corpus
	h.begin(media_case)
	if media.is_empty():
		h.check(
			"this corpus holds no media file a decoder extension could take",
			true,
			"run --root res://test-games/itamar-magichat for the only corpus that does")
	else:
		var opened: Array[String] = []
		var declined: Array[String] = []
		var reasons: Dictionary = {}
		var zero_duration: Array[String] = []
		var nameless: Array[String] = []
		# Files the plugin refused that another backend does take. Named rather
		# than counted, because the assertion below is that this list is *empty
		# of losses*: a container this port decodes in GDScript must not become
		# undecodable because an extension claimed its extension and then failed.
		var rescued: Array[String] = []
		var lost: Array[String] = []
		var sample := _sample(media, OPEN_LIMIT)
		# The positive control. Every assertion below is over `sample`, so an
		# empty one turns all of them into statements about nothing that report
		# `ok` — which is what `_sample` did on its first run and what its
		# docstring records. Asserted here rather than trusted, because a sampler
		# that quietly returns nothing is indistinguishable from a clean corpus.
		h.check("the sample is not empty against %d media file(s)" % media.size(),
			not sample.is_empty(),
			"every check below is over this list, so an empty one passes them all "
				+ "while asserting nothing")
		var tried := 0
		for file in sample:
			tried += 1
			var reader = Plugin.new()
			if reader.open(str(file)):
				opened.append("%s (%.2fs, %s)" % [
					str(file).get_file(), reader.duration_ms / 1000.0,
					reader.stream_class])
				# Check 6, asked from outside the adapter. `open` is supposed to
				# refuse a zero duration; this is the check that it did, rather
				# than the check that its source says it would.
				if reader.duration_ms <= 0.0:
					zero_duration.append(str(file).get_file())
			else:
				declined.append(str(file).get_file())
				reasons[str(reader.error)] = int(reasons.get(str(reader.error), 0)) + 1
				if str(reader.error).strip_edges() == "":
					nameless.append(str(file).get_file())
				# Check 8. Only asked of a decline, and only where a backend
				# behind the plugin exists for the format: the MS-RLE reader.
				if str(file).get_extension().to_lower() == "avi":
					var fallback = Avi.new()
					if fallback.open(str(file)):
						rescued.append("%s (%.2fs, %s backend)" % [
							str(file).get_file(), fallback.duration_ms / 1000.0,
							Avi.BACKEND])
					else:
						lost.append("%s (%s)" % [str(file).get_file(), str(fallback.error)])
			reader.close()
		print("  %d media file(s) found, %d tried: %d opened, %d declined"
			% [media.size(), tried, opened.size(), declined.size()])
		for reason in reasons.keys():
			print("    %3d x %s" % [int(reasons[reason]), str(reason)])
		for line in opened:
			print("    opened %s" % line)
		for line in rescued:
			print("    declined by the plugin, opened by the backend behind it: %s" % line)
		if verbose:
			for file in media:
				print("    %s" % str(file))
		if installed == "":
			h.check(
				"all %d declined, every one of them on the class gate" % declined.size(),
				opened.is_empty() and reasons.size() == 1
					and reasons.has("no decoder extension installed"),
				"reasons seen: %s" % ", ".join(PackedStringArray(reasons.keys())))
		else:
			# **How many opened is printed, not asserted.** It is decided by the
			# `configure` flags of a third party's FFmpeg build and not by
			# anything in this repository -- EIRTeam.FFmpeg 1.1.4 opens 0 of this
			# tree's 23, `docs/DIGITAL_VIDEO.md` §9 -- so gating on it would put a
			# standing red in `ALL` over somebody else's build options. The line
			# below is loud on purpose; the assertions that follow are the port's.
			print("  FINDING: %s opened %d of %d tried. That number is the installed "
				% [installed, opened.size(), tried]
				+ "build's codec set, not this port's behaviour.")
			h.check("nothing opened with a duration of nought",
				zero_duration.is_empty(),
				"%s reported ready with no duration, which is the state that turns "
					% ", ".join(PackedStringArray(zero_duration))
					+ "`go(the frame)` into a hang (`docs/DIGITAL_VIDEO.md` §3)"
					if not zero_duration.is_empty()
					else "the §3 invariant, asked of the adapter from outside it")
			h.check("every one of the %d decline(s) carries a named reason" % declined.size(),
				nameless.is_empty(),
				"%s declined with an empty `error`, which is a decline nobody can "
					% ", ".join(PackedStringArray(nameless))
					+ "debug" if not nameless.is_empty() else "")
			h.check(
				"no format this port decodes was lost to the plugin claiming it",
				lost.is_empty(),
				"%s: the plugin took the extension, failed, and the backend behind "
					% ", ".join(PackedStringArray(lost))
					+ "it could not open it either"
					if not lost.is_empty()
					else ("%d file(s) the plugin declined were opened by the "
						% rescued.size()
						+ "backend behind it" if not rescued.is_empty()
						else "no file in this corpus exercises the fallthrough"))
	h.complete(media_case)

	# ------------------------------------- 4. what the engine actually opened, and VOID
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var boot := Args.text(args, "boot", "")
	if boot != "":
		preview.call("lingo_go_movie", boot, null)
		for _i in OPEN_FRAMES:
			await process_frame

	var engine_case := "%s: the engine's own readers, and the VOID contract" % corpus
	h.begin(engine_case)
	var host = preview.get("_host")
	if host == null:
		h.check("the preview has a host", false)
		h.complete(engine_case)
		preview.queue_free()
		return
	var backends: Dictionary = {}
	for entry_value in host.video_readers.values():
		var entry: Dictionary = entry_value
		var reader = entry.get("reader", null)
		var kind := "none" if reader == null else str(reader.backend())
		backends[kind] = int(backends.get(kind, 0)) + 1
	print("  readers open after boot: %s" % (str(backends) if not backends.is_empty()
		else "(none — nothing has asked for a video yet)"))
	if installed == "":
		h.check("no reader the engine opened is on the plugin backend",
			not backends.has(Plugin.BACKEND),
			"with nothing installed the resolution order is the sidecar, the AVI "
				+ "reader and nothing, exactly as before the arm existed")
	else:
		h.check("the engine's readers are on backends this harness knows",
			_only_known(backends),
			"saw %s" % str(backends))

	# The contract `docs/DIGITAL_VIDEO.md` §3 turns on, asserted on a channel
	# nothing has touched: no member, so no reader, so VOID. `0` would take the
	# same arm in this corpus's two movies and be a different value to `voidP()`
	# in a title nobody has run yet.
	var untouched := 200
	var answer: Variant = host.get_sprite_prop(untouched, "getplaybackevent")
	h.check("`getPlaybackEvent` of a channel with no media is VOID",
		answer == null,
		"answered %s, and a false ready turns `go(the frame)` into a hang"
			% str(answer))
	h.complete(engine_case)
	preview.queue_free()


## At most `limit` files, spread across the distinct extensions present rather
## than taken off the front of the sorted list.
##
## Round robin: one file of each extension, then a second of each, until the
## budget runs out. The constant's docstring has the measurement that made this
## necessary — a front-of-list sample of this corpus is eight `.mpg` and misses
## the only `.avi`, which is the one file that exercises the fallthrough.
## **The buckets are `Array`, not `PackedStringArray`, and that is the bug this
## function shipped with for one run.** A `PackedStringArray` read out of a
## `Dictionary` is a *copy* — `(by_extension[ext] as PackedStringArray).append(x)`
## appends to a temporary and throws it away — so every bucket stayed empty, the
## sample came back with nothing in it, and the harness reported `0 tried, 0
## declined` and passed every downstream check vacuously. `AGENTS.md` names that
## shape ("four green runs are also what a vacuous scrape looks like"); the caller
## now asserts a non-empty sample against a non-empty corpus so it cannot recur
## silently.
static func _sample(media: PackedStringArray, limit: int) -> PackedStringArray:
	var by_extension: Dictionary = {}
	var order: Array[String] = []
	for file in media:
		var extension := str(file).get_extension().to_lower()
		if not by_extension.has(extension):
			by_extension[extension] = []
			order.append(extension)
		(by_extension[extension] as Array).append(str(file))
	var out := PackedStringArray()
	var round_index := 0
	while out.size() < limit:
		var took := false
		for extension in order:
			if out.size() >= limit:
				break
			var files: Array = by_extension[extension]
			if round_index < files.size():
				out.append(str(files[round_index]))
				took = true
		if not took:
			break
		round_index += 1
	return out


## Case-insensitive membership, because the loader publishes whatever case
## `av_demuxer_iterate()` yielded and `EXTENSIONS` is written lower case.
static func _published_has(published: PackedStringArray, wanted: String) -> bool:
	for known in published:
		if str(known).to_lower() == wanted.to_lower():
			return true
	return false


## How many of `EXTENSIONS` the installed loader also publishes, so the check's
## own label can say how many it is actually asserting over.
static func _overlap(published: PackedStringArray, table: Array) -> int:
	var n := 0
	for extension in table:
		if _published_has(published, str(extension)):
			n += 1
	return n


## The line each backend's arm starts on in `scenes/preview/video.gd:_reader`.
##
## A **source scan**, and the header says why: with an installed build that
## decodes none of this tree's containers there is no file the plugin arm and the
## sidecar arm both want, so nothing at run time can tell the two orders apart.
## Reading the order is the only way to assert it that cannot silently pass.
##
## Matched on the three distinct calls rather than on the constant names, because
## a rename of `Plugin` to something else should not quietly turn this check off:
## `Plugin.available()`, `Sidecar.fresh_for(` and `Avi.new()` are what the arms
## actually do, and the first occurrence of each inside the function is its arm.
const VIDEO_SOURCE := "res://scenes/preview/video.gd"

static func _resolution_order() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(VIDEO_SOURCE)
	if text == "":
		return out
	var line_number := 0
	var in_reader := false
	for line in text.split("\n"):
		line_number += 1
		var body := str(line)
		var trimmed := body.strip_edges()
		# Comments and docstrings name all three in prose; only code counts, the
		# same rule `_scan_scripts` applies for the same reason.
		if trimmed.begins_with("#"):
			continue
		if trimmed.begins_with("static func ") or trimmed.begins_with("func "):
			in_reader = trimmed.contains("_open(")
			continue
		if not in_reader:
			continue
		if not out.has("plugin") and trimmed.contains("Plugin.available()"):
			out["plugin"] = line_number
		if not out.has("sidecar") and trimmed.contains("Sidecar.fresh_for("):
			out["sidecar"] = line_number
		if not out.has("avi") and trimmed.contains("Avi.new()"):
			out["avi"] = line_number
	return out


## Every reader kind this harness expects to see, so an unknown one is a finding
## rather than something that slips past the check above.
static func _only_known(backends: Dictionary) -> bool:
	for kind in backends.keys():
		if not [Avi.BACKEND, Ogg.BACKEND, Plugin.BACKEND, "none"].has(str(kind)):
			return false
	return true


## Every file under a corpus root whose extension a decoder extension would take.
##
## Walked rather than read out of `tools/video_census.gd`, and the reason is the
## same one the census gives for keeping its own table: this asks a different
## question. The census classifies by *content* — it sniffs the first bytes,
## because `windemo.dat` is an icon table and not a fourth video. This asks what
## the **adapter's extension gate** would offer, which is a question about names,
## and answering it from the sniffed set would test the census instead.
static func _media_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, out, 0)
	out.sort()
	return out


static func _walk(where: String, out: PackedStringArray, depth: int) -> void:
	if depth > 8:
		return
	var dir := DirAccess.open(where)
	if dir == null:
		return
	for name in dir.get_files():
		if Plugin.EXTENSIONS.has(str(name).get_extension().to_lower()):
			out.append(where.path_join(str(name)))
	for name in dir.get_directories():
		_walk(where.path_join(str(name)), out, depth + 1)


## Every `.gd` under a directory, checked for a preload of an addon path.
##
## Read as text rather than parsed. A parse would need the file to compile, which
## is precisely the thing that fails in the case this is guarding against.
static func _scan_scripts(where: String, offenders: Array[String],
		mentions: Array[String]) -> void:
	var dir := DirAccess.open(where)
	if dir == null:
		return
	for name in dir.get_files():
		if str(name).get_extension().to_lower() != "gd":
			continue
		var file_path := where.path_join(str(name))
		var text := FileAccess.get_file_as_string(file_path)
		if not text.contains("res://addons/"):
			continue
		var line_number := 0
		for line in text.split("\n"):
			line_number += 1
			var body := str(line).strip_edges()
			if not body.contains("res://addons/"):
				continue
			# A comment mentioning the path is documentation, which this whole
			# feature has a lot of. Only code counts.
			if body.begins_with("#"):
				continue
			if body.contains("preload("):
				offenders.append("%s:%d" % [file_path, line_number])
			else:
				mentions.append("%s:%d  %s" % [file_path, line_number, body])
	for name in dir.get_directories():
		_scan_scripts(where.path_join(str(name)), offenders, mentions)
