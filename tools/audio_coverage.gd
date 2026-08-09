extends SceneTree
## Every sound on the disc is reachable through the index that plays it.
##
##   godot --headless --path . --script tools/audio_coverage.gd
##   godot --headless --path . --script tools/audio_coverage.gd -- --root piposh-dream
##   godot --headless --path . --script tools/audio_coverage.gd -- --root piposh --verbose
##
## `AudioDirector` builds one index of the game's audio at startup and every
## `sound playFile`, every score sound channel and every `puppetSound` goes
## through it. A file the index never saw is a sound the game can never play, and
## the failure is **silent in both senses**: the movie asks, nothing answers, the
## channel is claimed and empty, and the only trace is one `Audio miss:` line in a
## log nobody is reading.
##
## ## The regression this exists for
##
## The index took a file when its *name* ended in `wav`, `ogg`, `mp3` or `aif`.
## These are Mac discs and **a Mac file has no extension** — `piposh-dream` ships
## 1,711 sound files called `sounds/dream2/1`, `FX/264`, `sounds/dream1/100`, and
## 187 that happen to carry one. The index held the 187. Nine tenths of that
## title's audio was unreachable: every line of speech, every effect, in every
## room, from the first commit that walked the tree.
##
## The odd part is that the *loader* twenty screens further down
## (`audio_director.gd:_load_stream`) had always read the container tag instead of
## the name, with a comment explaining that a disc's filenames are as much a guess
## as its paths are — `FX/DRILL.WAV` is an AIFF and `FX/BIRDS.AIF` is a RIFF, in
## the same folder. The rule was right in one half of the file and absent from the
## other, so a file the loader would have decoded perfectly never reached it.
##
## ## Why the sniff below is a second copy of the engine's, deliberately
##
## Asking `AudioDirector` which files are sounds and then asserting it indexed
## exactly those is a tautology: any rule it applies, it applies to both sides,
## and the extension filter would have passed this test on the day it was wrong.
## So the walk here recognises a sound from its own reading of the bytes —
## `FORM....AIFF`/`AIFC`, `RIFF....WAVE`, `OggS`, an `ID3` tag or an MP3 frame
## sync — and the two only agree if they are independently right.
##
## That is the same argument `porting-fidelity-verification` makes about a decode
## agreeing with the data it was handed. It costs a duplicated constant; the
## alternative costs the finding.
##
## ## What is asserted
##
##   * every file whose bytes say it is a sound resolves through
##     `AudioDirector.resolve_path`, and resolves to **itself** — resolving to
##     some other take of the same line is the failure `resolve_path`'s own header
##     is about, and "it resolved to something" would pass through it;
##   * the corpus has sounds at all, so a root with none cannot pass over the
##     empty set.
##
## Reported and not asserted: how many files carry a usable extension and how
## many do not. That split is a property of the disc, not of the engine, and a
## title that is all one or all the other is not a fault.
##
## Title-agnostic: it knows container tags and file trees, and no movie.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")

## Enough bytes to see a form type at offset 8.
const TAG_BYTES := 12
## Extensions that name a sound where a disc has extensions at all. Only used to
## *report* the split; nothing is included or excluded by it.
const NAMED := ["wav", "ogg", "mp3", "aif", "aiff"]


## `_initialize`, not `_init`: the script is constructed before the tree is
## populated, so an autoload looked up in `_init` is reliably absent.
func _initialize() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var audio := root.get_node_or_null("AudioDirector")
	if audio == null:
		print("AudioDirector autoload is not present")
		quit(1)
		return
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie"
			% Paths.CONFIG_PATH)
		quit(1)
		return

	var case := "%s: every sound on the disc is reachable" % paths.root.get_file()
	h.begin(case)

	var sounds: Array[String] = []
	_walk(paths.root, sounds)
	if not h.check("the corpus ships sounds", not sounds.is_empty(),
			"%d file(s)" % sounds.size()):
		h.complete(case)
		quit(h.finish("audio index coverage"))
		return

	var named := 0
	var unreachable: Array[String] = []
	var elsewhere: Array[String] = []
	for full in sounds:
		if NAMED.has(full.get_extension().to_lower()):
			named += 1
		# Asked for by the path a script would name — root-relative, which is what
		# `resolve_path` normalises both sides to.
		var wanted := full.substr(paths.root.length()).lstrip("/")
		var got := str(audio.call("resolve_path", wanted))
		if got == "":
			unreachable.append(wanted)
		elif got != full:
			elsewhere.append("%s -> %s" % [wanted, got])

	h.check("all %d sound file(s) resolve" % sounds.size(),
		unreachable.is_empty(),
		"%d unreachable" % unreachable.size() if not unreachable.is_empty() else "")
	for line in unreachable.slice(0, 12):
		print("     never resolves: %s" % line)
	if unreachable.size() > 12:
		print("     ... and %d more" % (unreachable.size() - 12))

	h.check("and each resolves to itself rather than to another take",
		elsewhere.is_empty(),
		"%d misdirected" % elsewhere.size() if not elsewhere.is_empty() else "")
	for line in elsewhere.slice(0, 12):
		print("     %s" % line)

	print("")
	print("sounds on disc     : %d" % sounds.size())
	print("  named with an extension : %d" % named)
	print("  no extension at all     : %d" % (sounds.size() - named))
	if Args.flag(args, "verbose"):
		print("root: %s" % paths.root)
	h.complete(case)
	quit(h.finish("audio index coverage"))


## Every file under `path` whose *bytes* say it is a sound.
func _walk(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_walk(full, out)
		elif _is_sound(full):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


## This tool's own reading of a file's container tag. See the header for why it
## is not `AudioDirector`'s.
##
## Director containers are `RIFX`/`XFIR` and are deliberately not matched: the
## four-character tag is the whole discriminator, and a movie is not a sound.
static func _is_sound(full: String) -> bool:
	var file := FileAccess.open(full, FileAccess.READ)
	if file == null:
		return false
	var head := file.get_buffer(TAG_BYTES)
	file.close()
	if head.size() < 4:
		return false
	var tag := head.slice(0, 4).get_string_from_ascii()
	if tag == "FORM" or tag == "RIFF":
		if head.size() < TAG_BYTES:
			return false
		return head.slice(8, TAG_BYTES).get_string_from_ascii() in ["AIFF", "AIFC", "WAVE"]
	if tag == "OggS":
		return true
	if head.slice(0, 3).get_string_from_ascii() == "ID3":
		return true
	return head[0] == 0xFF and (head[1] & 0xE0) == 0xE0
