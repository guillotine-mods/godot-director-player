extends SceneTree
## Which score format every container in a game uses, and which ones this engine
## can read.
##
##   godot --headless --script tools/container_versions.gd
##   godot --headless --script tools/container_versions.gd -- --verbose
##
## A Director title is not necessarily uniform. Piposh 1 ships `STRTGAME.dir`
## with 48-byte sprite records and 94 of its 97 room movies with 24-byte ones --
## two Director versions in one game, which is invisible until a movie fails to
## open and the symptom is "the music plays and the scene never changes".
##
## The sprite record size is the discriminator. 48 bytes is Director 5 and later;
## 24 is the older layout, with different field offsets, a different main-channel
## block and no cast-library field at all. `director_score.gd` reads the 48-byte
## form and refuses the other, so this reports the split rather than guessing at
## it.
##
## Two uses. Before a bulk conversion it says how much there is to convert; after
## one it says whether the conversion actually covered everything, which is the
## question a spot-check on a single file cannot answer.
##
## It reads whatever `director_game.cfg` points at, so it follows the configured
## game rather than naming one. `--root <name>` overrides that without writing to
## the shared config, which is what to use when comparing titles.
##
## ## What it asserts, and why "readable" alone is not enough
##
## On an **unconverted** title the first check does all the work: a 24-byte score
## is refused outright and the count is the answer. On a **converted** one every
## score parses by construction, and a harness whose only claim is "nothing
## failed" then passes over a corpus it has not actually looked at. So it also
## asserts that each score **decodes to something**: a frame count above zero, and
## a first frame that can be materialised. A score that parses its header and
## yields no frames is the failure a readability check cannot see, and it is the
## shape a bad conversion would take -- the chunk is well-formed and the frame
## stream inside it is not.
##
## It reports the **stated file version** beside the record size for the same
## reason. The two answer different questions and the second is the one usually
## wanted: the record size says what this decoder can read, the version says which
## Director wrote the movie and therefore which convention its tempo cell, its
## main-channel block and its sprite record are in. Measured here, they also
## correct an easy assumption -- Piposh 1's containers state `0x73A` and Piposh
## 2's are mostly `0x57E`, so the *older game ships the later format*, and
## "Piposh 1 is the old one, so it will be the D4 records" is wrong twice over.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var files: Array[String] = []
	_walk(paths.root, files)
	files.sort()

	var by_size: Dictionary = {}
	var by_version: Dictionary = {}
	var unreadable: Array[String] = []
	var empty: Array[String] = []
	var no_score := 0
	var scored := 0
	var total_frames := 0

	for path in files:
		var f := ContainerFile.new()
		if not f.open(path):
			unreadable.append("%s — %s" % [path.get_file(), f.error])
			continue
		# The stated version, read before the score because the score is decoded
		# *in* it: which convention the tempo cell and the sprite record are
		# written in is a property of the movie, not of the bytes.
		var config = Config.new()
		var version := int(config.version) if config.read(f) else 0
		var version_key := ("0x%X" % version) if version > 0 else "no config chunk"
		by_version[version_key] = int(by_version.get(version_key, 0)) + 1
		var ids: Array = f.ids_of("VWSC")
		if ids.is_empty():
			# A cast file has no score, which is not a fault.
			no_score += 1
			f.close()
			continue
		scored += 1
		var score := Score.new()
		if score.parse(f.read_chunk(int(ids[0])), version):
			var key := "%d-byte records" % score.sprite_record_size
			by_size[key] = int(by_size.get(key, 0)) + 1
			total_frames += score.frame_count
			# Parsing the header is not reading the score. A frame count of zero,
			# or a first frame that will not materialise, is a chunk that was
			# well-formed enough to be accepted and empty enough to play nothing —
			# which is what a conversion that dropped the frame stream looks like,
			# and what the readability check above cannot see.
			if score.frame_count <= 0:
				empty.append("%s — parsed, 0 frames" % path.get_file())
			elif score.frame(0).is_empty():
				empty.append("%s — parsed, %d frames, frame 0 will not decode"
					% [path.get_file(), score.frame_count])
		else:
			# The record size is reported in the error even when the parse is
			# refused, which is the whole point: an unreadable score still says
			# *why* it is unreadable.
			unreadable.append("%s — %s" % [path.get_file(), score.error])
		f.close()

	var verbose := Args.flag(args, "verbose")
	print("%s" % paths.root)
	print("  containers found : %d" % files.size())
	print("  with a score     : %d  (%d are cast-only)" % [scored, no_score])
	print("  frames decoded   : %d" % total_frames)
	print("")
	var keys: Array = by_size.keys()
	keys.sort()
	for key in keys:
		print("  readable, %-18s %d" % [key + ":", int(by_size[key])])
	print("  unreadable        : %d" % unreadable.size())
	_show(unreadable, verbose)
	print("  readable but empty: %d" % empty.size())
	_show(empty, verbose)
	print("")
	var versions: Array = by_version.keys()
	versions.sort()
	for key in versions:
		print("  stated version %-14s %d container(s)" % [key + ":", int(by_version[key])])

	h.begin("every score in the configured game can be read")
	h.check("at least one container was found", not files.is_empty(), paths.root)
	h.check("the game has movies in it, not only casts", scored > 0,
		"%d of %d containers carry a score" % [scored, files.size()])
	h.check("every score parses", unreadable.is_empty(),
		"%d of %d unreadable" % [unreadable.size(), scored])
	h.check("every score that parses also decodes to frames", empty.is_empty(),
		"%d of %d empty" % [empty.size(), scored])
	h.complete("every score in the configured game can be read")
	quit(h.finish("score formats across the configured game"))


static func _show(lines: Array[String], verbose: bool) -> void:
	if lines.is_empty():
		return
	var show: int = lines.size() if verbose else mini(8, lines.size())
	for i in show:
		print("      %s" % lines[i])
	if show < lines.size():
		print("      ... and %d more (pass --verbose)" % (lines.size() - show))
