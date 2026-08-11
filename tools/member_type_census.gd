extends SceneTree
## Which Director cast-member types exist in reach, counted over every corpus.
##
##   godot --headless --script tools/member_type_census.gd
##   godot --headless --script tools/member_type_census.gd -- --type 15 --list
##   godot --headless --script tools/member_type_census.gd -- --roots res://games/piposh2
##
## The question this exists to answer is "is there a member of type N anywhere",
## and it is asked *before* deciding how to decode one. `tools/director_members.gd`
## and `tools/draw_survey.gd` both count members by type, and neither can answer
## it: both follow `director_game.cfg`, so each run sees one title, and both walk
## a cast through its `CAS*` table, so a second library embedded in a `.dir`
## alongside the first is invisible to them. A type that occurs 0 times in the
## configured game and twice in a test corpus reads as "0 everywhere" through
## either.
##
## So this walks **every root** under `games/` and `test-games/` in one run, and
## it counts `CASt` chunks rather than `CAS*` slots. Every cast member in a
## container is a `CASt` chunk whatever library owns it, and its type is the first
## big-endian word of that chunk -- the one field of the record whose position
## does not depend on the type. That is the complete population by construction.
##
## The detail listing goes through `director/director_cast.gd` proper, so what it
## prints is what the engine will see, not a second parser's opinion -- and it is
## reconciled against the raw count, which is how the size of the shortcut's blind
## spot got measured rather than assumed. It is not small: `itamar-magichat` keeps
## 412 of its 454 Xtra members in a second library of `witch.dir`, which a
## first-`CAS*` walk never opens. `tools/xtra_members.gd` goes through
## `DirectorCastTable` for exactly that reason.
##
## Title-agnostic: it names no game, and it discovers the roots by listing the
## directories rather than carrying a list of them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")

## Where corpora live. Each *subdirectory* of one of these is one corpus root.
const CORPUS_DIRS := ["res://games", "res://test-games"]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	if explicit != "":
		for part in explicit.split(",", false):
			roots.append(str(part).strip_edges())
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	roots.sort()

	var want_type := Args.number(args, "type", -1)
	var list_them := Args.flag(args, "list")
	# How many raw records of `--type` to hexdump. The dump is driven off the CASt
	# scan rather than the CAS* walk on purpose: a type that is mostly unreachable
	# through the walk (see the reconciliation below) would otherwise be invisible
	# in exactly the corpus that has the most of it.
	var dump_left := Args.number(args, "dump", 0)

	# corpus -> {type code -> count}, from the CASt chunks themselves.
	var by_corpus: Dictionary = {}
	# type code -> count, over everything.
	var totals: Dictionary = {}
	# The members the per-CAS* walk reached, for the reconciliation below.
	var walked: Dictionary = {}
	var detail: Array[String] = []
	var containers := 0
	var chunks := 0

	for root in roots:
		var corpus := str(root).get_file()
		var counts: Dictionary = {}
		var walked_counts: Dictionary = {}
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			containers += 1
			var config = Config.new()
			var version := int(config.version) if config.read(f) else 0
			# --- the complete population: every CASt chunk in the file ----------
			# Only the type word is read here, and only because it is the one field
			# of the record whose position does not depend on the type. Everything
			# else about a member comes from `director_cast.gd` below, so this is
			# not a second parser -- it is the denominator the parser is checked
			# against.
			for id in f.ids_of("CASt"):
				var raw: PackedByteArray = f.read_chunk(int(id))
				if raw.size() < 4:
					continue
				var code := (raw[0] << 24) | (raw[1] << 16) | (raw[2] << 8) | raw[3]
				counts[code] = int(counts.get(code, 0)) + 1
				chunks += 1
				if code == want_type and dump_left > 0:
					dump_left -= 1
					print("")
					print("%s %s CASt %d  v0x%X  %d bytes"
						% [corpus, path.get_file(), int(id), version, raw.size()])
					_hexdump(raw)
			# --- what the engine's own parser makes of them ---------------------
			var cast := Cast.new()
			if cast.open(f):
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if m.is_empty():
						continue
					var code := int(m.get("type", 0))
					walked_counts[code] = int(walked_counts.get(code, 0)) + 1
					if want_type >= 0 and code != want_type:
						continue
					if not list_them:
						continue
					detail.append(_describe(corpus, path, version, number, m))
			f.close()
		by_corpus[corpus] = counts
		walked[corpus] = walked_counts
		for code in counts:
			totals[code] = int(totals.get(code, 0)) + int(counts[code])

	# ---------------------------------------------------------------- report
	var codes: Array = totals.keys()
	codes.sort()
	var corpora: Array = by_corpus.keys()
	corpora.sort()

	print("%d container(s) over %d corpus root(s), %d CASt chunk(s)"
		% [containers, roots.size(), chunks])
	print("")
	var header := "  %-6s %-12s" % ["type", "name"]
	for corpus in corpora:
		header += "%14s" % str(corpus).substr(0, 13)
	header += "%12s" % "total"
	print(header)
	for code in codes:
		var line := "  %-6d %-12s" % [int(code), Cast.TYPE_NAMES.get(int(code), "type%d" % int(code))]
		for corpus in corpora:
			line += "%14d" % int((by_corpus[corpus] as Dictionary).get(code, 0))
		line += "%12d" % int(totals[code])
		print(line)

	# How much of that population a *first-`CAS*`* walk sees, which is what
	# `director_members.gd`, `draw_survey.gd` and this tool's detail listing all
	# do. It is not a fault report -- the engine addresses members through
	# `DirectorCastTable`, which resolves the internal cast, a library embedded in
	# the same container under its own `castID`, and every linked `.cst`, so it
	# reaches all of them. It is the size of the blind spot a survey inherits by
	# taking the shortcut, and it is large: `itamar-magichat` puts 412 of its 454
	# Xtra members in a second library of `witch.dir`. Reported per type, because
	# "23 bitmaps" and "412 Xtras" are different findings and one total hides the
	# second behind the first.
	var unreached: Array[String] = []
	for corpus in corpora:
		for code in (by_corpus[corpus] as Dictionary):
			var whole := int((by_corpus[corpus] as Dictionary)[code])
			var reached := int((walked[corpus] as Dictionary).get(code, 0))
			if reached < whole:
				unreached.append("%s type %d (%s): %d of %d"
					% [corpus, int(code),
					Cast.TYPE_NAMES.get(int(code), "type%d" % int(code)),
					reached, whole])

	if not detail.is_empty():
		print("")
		print("members of type %d (%d):" % [want_type, detail.size()])
		for line in detail:
			print("  " + line)

	if not unreached.is_empty():
		print("")
		print("seen by a first-CAS* walk (the rest need DirectorCastTable):")
		for line in unreached:
			print("  " + line)

	h.begin("the census covered something")
	h.check("found corpus roots", not roots.is_empty(), "%d" % roots.size())
	h.check("opened containers", containers > 0, "%d" % containers)
	h.check("counted cast members", chunks > 0, "%d CASt chunks" % chunks)
	h.complete("the census covered something")
	quit(h.finish("cast member types present across every corpus in reach"))


## One member, as the engine parses it. Geometry is printed even when it is zero,
## because a zero is the finding for a type whose specific block is not decoded.
func _describe(corpus: String, path: String, version: int, number: int, m: Dictionary) -> String:
	var extra := ""
	if m.has("xtra_symbol"):
		extra = "  xtra=%s" % JSON.stringify(str(m["xtra_symbol"]))
	if m.has("xtra_data_size"):
		extra += " data=%dB" % int(m["xtra_data_size"])
	return "%-16s %-24s v0x%X  #%-4d %-16s %4dx%-4d reg(%d,%d)%s" % [
		corpus, str(path).get_file(), version, number, str(m.get("name", "")),
		int(m.get("width", 0)), int(m.get("height", 0)),
		int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0)), extra,
	]


## Offset, hex, and the printable bytes -- an Xtra record is mostly a name, and a
## name is unreadable in hex alone.
static func _hexdump(raw: PackedByteArray) -> void:
	var at := 0
	while at < raw.size():
		var hex := ""
		var text := ""
		for i in 16:
			if at + i < raw.size():
				var b: int = raw[at + i]
				hex += "%02x " % b
				text += char(b) if b >= 32 and b < 127 else "."
			else:
				hex += "   "
		print("    %04x  %s %s" % [at, hex, text])
		at += 16


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
