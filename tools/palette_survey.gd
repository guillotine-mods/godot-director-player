extends SceneTree
## What the palette subsystem actually has to resolve in this corpus.
##
##   godot --headless --script tools/palette_survey.gd -- --all
##   godot --headless --script tools/palette_survey.gd -- --file PIP2DATA/DAY1.dir
##
## §11 describes a resolution order (frame palette channel -> score cache ->
## movie default, with `puppetPalette` short-circuiting), colour cycling and
## palette fades. Every one of those is work, and none of it was worth writing
## against a guess. `director/director_palette.gd` asserted in its header that
## this game ships no `CLUT` chunk and no palette cast member and that every
## bitmap carries clut id 0 — an assertion nobody had run. Two thirds of it hold
## and the third is wrong: the clut id is -1, not 0. Same conclusion, different
## number, and the difference matters because `builtin()` only warned above zero
## and so could never have fired on either value.
##
## Four independent places a palette can be named, all counted here:
##   - a `CLUT` chunk in a container (a custom palette's own colour table),
##   - a cast member of type 4 (the palette member that owns such a table),
##   - a bitmap member's own clut id in its `CASt` specific block (offset **26**;
##     this said 24 for as long as the parser read 24, and 24 is the clut *cast
##     library* — see `director_cast.gd:_parse_clut`),
##   - the score's palette channel, decoded in `director_score.gd:_palette_record`.
##
## The conclusion above holds for the six shipped titles and for nothing else.
## `test-games/itamar-park` ships 162 `CLUT` chunks, 145 palette members and 655
## bitmap members naming one, which is what turned the header of
## `director_palette.gd` from an unverified claim into a measured wrong one:
## reading offset 24 answered "system Mac" for every bitmap of every title,
## including the ones that name a palette on every member.
##
## Director's built-in palettes are named by *negative* ids and a custom one by a
## positive member number, so 0 and -1 are different facts and are printed apart.
##
## The check that can fail is the one that matters to the renderer: every palette
## anything in the corpus names must be one this port can actually build. A title
## that named a second built-in, or a custom `CLUT`, would be drawn in the wrong
## colours with no other symptom.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")

## The `CASt` type code for a palette member.
const PALETTE_TYPE := 4


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	if Args.flag(args, "all") or not args.has("file"):
		_walk(paths.root, targets)
		targets.sort()
	else:
		var one: String = paths.resolve(Args.text(args, "file"))
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	var containers := 0
	var scores := 0
	var clut_chunks := 0
	var clut_files: Array[String] = []
	var palette_members: Array[String] = []
	var bitmap_clut: Dictionary = {}
	var bitmaps := 0
	var frames := 0
	var frame_palette: Dictionary = {}
	var effects: Array[String] = []
	var cycling := 0
	var fading := 0
	var naming_a_palette := 0
	var per_movie: Array[String] = []
	# Every palette member number the corpus holds, in any container. A positive
	# id names a cast member and a linked cast puts it in another file, so a
	# per-container set would call a perfectly resolvable palette missing.
	var palette_numbers: Dictionary = {}
	# A **built-in** this port has no table for. That is a gap in the port and it
	# is what makes this tool able to fail: art indexed against a table nobody has
	# draws in the wrong colours with no other symptom.
	var unbuildable: Dictionary = {}
	# A **member** id that resolves to no palette member anywhere in the corpus.
	# Reported and not failed, because §11 says Director tolerates exactly this --
	# a score authored against a palette whose member was later deleted still
	# plays, on whatever the resolution order reaches next -- so a title carrying
	# some is authentic data rather than a defect in the reader.
	var unresolved: Dictionary = {}

	# First pass: which palette members exist anywhere. A positive id names a cast
	# member and a linked cast puts it in another container, so deciding
	# buildability container by container would call a resolvable palette missing
	# — and would depend on the order the walk happens to visit the files in.
	for path in targets:
		var pf := ContainerFile.new()
		if not pf.open(path):
			continue
		var pc := Cast.new()
		if pc.open(pf):
			for number in pc.member_numbers():
				if int(pc.member(number).get("type", 0)) == PALETTE_TYPE:
					palette_numbers[number] = true
		pf.close()

	for path in targets:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		containers += 1
		var cluts: Array = f.ids_of("CLUT")
		if not cluts.is_empty():
			clut_chunks += cluts.size()
			clut_files.append("%s x%d" % [path.get_file(), cluts.size()])

		var c := Cast.new()
		if c.open(f):
			for number in c.member_numbers():
				var m := c.member(number)
				if m.is_empty():
					continue
				var type_code := int(m.get("type", 0))
				if type_code == PALETTE_TYPE:
					palette_members.append("%s #%d %s" % [
						path.get_file(), number, str(m.get("name", ""))
					])
				elif type_code == 1:
					bitmaps += 1
					var clut := int(m.get("palette_id", Palette.SYSTEM_MAC))
					bitmap_clut[clut] = int(bitmap_clut.get(clut, 0)) + 1
					if not _buildable(clut, palette_numbers):
						var where := "%s member %d -> %d" % [path.get_file(), number, clut]
						if clut < 0:
							unbuildable[where] = true
						else:
							unresolved[where] = true

		var vwsc: Array = f.ids_of("VWSC")
		if not vwsc.is_empty():
			var score := Score.new()
			if score.parse(f.read_chunk(int(vwsc[0]))):
				scores += 1
				var named_here := 0
				for i in score.frame_count:
					frames += 1
					var record: Dictionary = score.frame(i).get("palette", {})
					var id := int(record.get("member", 0))
					frame_palette[id] = int(frame_palette.get(id, 0)) + 1
					if id == 0:
						continue
					naming_a_palette += 1
					named_here += 1
					if not _buildable(id, palette_numbers):
						var where := "%s f%d -> %d" % [path.get_file(), i, id]
						if id < 0:
							unbuildable[where] = true
						else:
							unresolved[where] = true
					if bool(record.get("cycling", false)):
						cycling += 1
					if bool(record.get("fade", false)):
						fading += 1
					if int(record.get("flags", 0)) != 0 or int(record.get("speed", 0)) != 0:
						effects.append(
							"%s f%d  id %d  speed %d  flags 0x%02x%s%s  first/last %d/%d"
							% [
								path.get_file(), i, id,
								int(record.get("speed", 0)), int(record.get("flags", 0)),
								"  CYCLING" if bool(record.get("cycling", false)) else "",
								"  FADE" if bool(record.get("fade", false)) else "",
								int(record.get("first_color_raw", 0)),
								int(record.get("last_color_raw", 0)),
							]
						)
				if named_here > 0:
					per_movie.append("%s: %d frame(s)" % [path.get_file(), named_here])
		f.close()

	print("%d container(s), %d score(s), %d frame(s), %d bitmap member(s)" % [
		containers, scores, frames, bitmaps
	])
	print("")
	print("CLUT chunks          : %d" % clut_chunks)
	for line in clut_files:
		print("    %s" % line)
	print("palette members (t4) : %d" % palette_members.size())
	for line in palette_members:
		print("    %s" % line)
	print("")
	print("bitmap member clut id (CASt specific +26, built-ins already offset):")
	var clut_keys: Array = bitmap_clut.keys()
	clut_keys.sort()
	for k in clut_keys:
		print("  %6d %-12s -> %d member(s)" % [int(k), _name_of(int(k)), int(bitmap_clut[k])])
	print("")
	print("score palette channel, by member id:")
	var frame_keys: Array = frame_palette.keys()
	frame_keys.sort()
	for k in frame_keys:
		print("  %6d %-12s -> %d frame(s)" % [int(k), _name_of(int(k)), int(frame_palette[k])])
	for line in per_movie:
		print("    %s" % line)
	print("")
	print("frames naming a palette : %d" % naming_a_palette)
	print("  with colour cycling   : %d" % cycling)
	print("  with a fade           : %d" % fading)
	print("  carrying any effect   : %d" % effects.size())
	for line in effects:
		print("    %s" % line)

	var h := Harness.new()
	h.begin("every palette this corpus names can be built")
	h.check("read at least one score", scores > 0, "%d score(s)" % scores)
	h.check("read at least one cast", bitmaps > 0, "%d bitmap member(s)" % bitmaps)
	print("")
	print("palette member ids naming nothing (Director tolerates these): %d" % unresolved.size())
	for line in unresolved.keys().slice(0, 12):
		print("    %s" % line)
	# A built-in with no table is the failure, because art indexed against it is
	# silently the wrong colour and nothing else says so. A *member* id naming
	# nothing is not: §11 has Director falling through the resolution order for
	# exactly that case, so it is printed above and counted here only.
	h.check(
		"no member or frame names a built-in this port cannot build",
		unbuildable.is_empty(),
		"%d unbuildable: %s" % [unbuildable.size(), ", ".join(unbuildable.keys().slice(0, 6))]
	)
	h.complete("every palette this corpus names can be built")
	quit(h.finish("what names a palette in this corpus"))


## Whether the port can produce the table this id names.
##
## **This used to answer "0 or system Mac, and nothing else"**, on the standing
## assumption that the corpus could never name anything more -- which made the
## check a restatement of the survey above rather than a test of the port, and
## made it fail outright the first time a title with 145 palette members was
## pointed at it. 0 is "none named" and resolves to the movie default; a negative
## id is a built-in and `can_build` knows which of those have tables; a positive
## one is a palette cast member and is buildable when the corpus holds a member
## of that number.
##
## The pass is now two-sided in a way it was not: naming `Rainbow` still fails,
## because there is no table for it and art drawn against one would be silently
## wrong.
static func _buildable(id: int, palette_numbers: Dictionary) -> bool:
	if id == 0:
		return true
	if id < 0:
		return Palette.can_build(id)
	return palette_numbers.has(id)


static func _name_of(id: int) -> String:
	if id == Palette.SYSTEM_MAC:
		return "system Mac"
	if id == 0:
		return "none"
	if id < 0:
		return "built-in"
	return "member"


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
