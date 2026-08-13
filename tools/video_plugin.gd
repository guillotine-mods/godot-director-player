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
## one. Three things are checked and each has a named failure it prevents:
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
## The checks invert rather than disappear: the harness names the class, prints
## the extensions its loader claims, and asserts that at least one media file the
## corpus holds — one the AVI reader refuses — opens through it with a duration
## above zero. A run with an extension installed that opens nothing is a finding,
## because a member that would report ready with no duration is the hang §3 is
## about, and `director_plugin_video.gd:open` refusing it is the thing being
## tested.
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
	h.complete(gate_case)

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
		var tried := 0
		for file in media:
			if tried >= OPEN_LIMIT:
				break
			tried += 1
			var reader = Plugin.new()
			if reader.open(str(file)):
				opened.append("%s (%.2fs, %s)" % [
					str(file).get_file(), reader.duration_ms / 1000.0,
					reader.stream_class])
			else:
				declined.append(str(file).get_file())
				reasons[str(reader.error)] = int(reasons.get(str(reader.error), 0)) + 1
			reader.close()
		print("  %d media file(s) found, %d tried: %d opened, %d declined"
			% [media.size(), tried, opened.size(), declined.size()])
		for reason in reasons.keys():
			print("    %3d x %s" % [int(reasons[reason]), str(reason)])
		for line in opened:
			print("    opened %s" % line)
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
			# The point of installing one, and the assertion is deliberately about
			# the duration rather than about pictures: a stream that opens with no
			# duration is refused by the adapter, so a non-empty `opened` list is
			# already the statement that every one of them answered above zero.
			h.check(
				"%s opened %d of %d tried, each with a duration above 0"
					% [installed, opened.size(), tried],
				not opened.is_empty(),
				"an extension that opens nothing is either a build without these "
					+ "demuxers or a class that does not take `set_file`; either way "
					+ "the adapter refuses rather than reporting a ready member with "
					+ "no duration"
					if opened.is_empty() else "")
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
