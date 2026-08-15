extends SceneTree
## Where the port's "is this channel occupied" test and the reference's disagree.
##
##   godot --headless --path . --script tools/channel_occupancy.gd
##   godot --headless --path . --script tools/channel_occupancy.gd -- --roots res://games/rating
##   godot --headless --path . --script tools/channel_occupancy.gd -- --list 20
##   godot --headless --path . --script tools/channel_occupancy.gd -- --max-frames 120
##
##   --roots A,B       corpus roots (default: every subdirectory of games/ and test-games/)
##   --max-frames N    only the first N frames of each score (0 = all; see below)
##   --list N          print the first N disagreeing records in full
##
## `bugs.md` 49 is "the port's test is not the reference's and nobody has measured
## where they disagree". This is that measurement, over every container of every
## corpus root, on the raw channel buffer rather than on `_snapshot`'s output —
## a survey of a filter cannot run downstream of the filter.
##
## **The two tests, as they actually are.**
##
## The port (`director_score.gd:_snapshot`) drops a record when `cast_id <= 0`.
##
## The reference gates its render walk on `Channel::isEmpty()`
## (`channel.cpp:330`), which is `_spriteType == kInactiveSprite` and nothing
## else — reached from `Window::render` → `Window::renderChannel` →
## `Score::getSpriteIntersections` (`score.cpp:1723`), which is the only walk that
## puts a channel on the stage. (`director_score.gd`'s own comment cites
## `score.cpp:503` and `score.cpp:2474` for the member test instead; 503 is the
## rollOver-bbox cache and 2474 is `formatChannelInfo`, a debug printer. Neither
## is the render gate, so the comment names the right *rule* against the wrong
## two lines.)
##
## **But `_spriteType` is not the record's type byte by the time `isEmpty` reads
## it,** and that is the whole reason the two tests turn out to agree as often as
## they do. `Score::loadFrame` finishes with `setSpriteCasts()` (`score.cpp:2326`),
## which runs `Sprite::setCast` over every sprite of the frame it just loaded, and
## `setCast` (`sprite.cpp:588`) does:
##
##     if (version >= 400 && !isQDShape() && _castId != CastMemberID(0, 0))
##             _spriteType = kCastMemberSprite;
##
## — then narrows it to `kBitmapSprite`/`kTextSprite`/… if the member resolves.
## So a record whose type byte is 0 and whose member is set comes out of
## `loadFrame` as type 16, and `isEmpty()` answers false for it. The reference's
## effective per-record test is therefore
##
##     empty  ⟺  type byte == 0  and  member == 0  and  cast lib == 0
##
## and the port's is `member == 0`. One is strictly weaker than the other, which
## makes the disagreement one-directional by construction: **the port can drop a
## record the reference keeps, and can never keep one the reference drops.** The
## B column below is asserted to be zero for that reason rather than merely
## reported — if it is ever not zero, this file's reading of `setCast` is wrong.
##
## The A column splits three ways, because the three mean very different things
## on the stage:
##
##   A1  the type byte is a QuickDraw shape (2-6, 12-15) and there is no member.
##       The reference draws a rectangle/oval/line **from the sprite record
##       itself** — fore colour, back colour, thickness, pattern — with no cast
##       member involved at all. Every one of these is art the port cannot draw,
##       because the record never reaches the renderer.
##   A2  the type byte is a live non-shape type (1, 7-11, 16-18) and there is no
##       member. Occupied in the reference and drawing nothing, but it answers
##       `the type of sprite`, it takes part in rollOver and in
##       `getSpriteIntersections`, and `Channel::isEmpty` is false for it.
##   A3  the type byte is 0 and the member is 0, but the cast **lib** is not.
##       `CastMemberID(0, N) != CastMemberID(0, 0)`, so `setCast` promotes it to
##       `kCastMemberSprite` with a null cast. Occupied in the reference on a
##       technicality; nothing draws.
##
## A fourth column is counted beside them and is not a disagreement about
## occupancy at all — a record with a QD shape type **and** a member. Both tests
## call it occupied and they mean different things by it: the reference keeps the
## QD type (`setCast`'s `!isQDShape()` guard) and draws the shape, while the port
## has only the member. Reported because it is the same byte's meaning and this is
## the run that has the bytes open.
##
## ## Measured, 2026-08-14, all eight corpus roots
##
##     677 containers: 491 walked, 186 with no VWSC, 0 the reader refuses
##     65,883,235 channel records
##       A (port empty / reference occupied)  0     A1 0   A2 0   A3 0
##       B (port occupied / reference empty)  0
##       QD shape type with a member          0
##       type byte, records naming a member   16 x 8,079,420   and nothing else
##       type byte, records naming none        0 x 57,803,815  and nothing else
##
## **So the two tests are not merely compatible on this corpus, they are the same
## partition of it**: the type byte takes exactly two values and is perfectly
## correlated with whether the member field is set. `bugs.md` 49 asked which way
## they disagree and the answer is neither, 243 s and 65.9M records to say so.
##
## The entry's own guess about the second direction — "a record with a type of 0
## and a nonzero member is the reverse" — is wrong on the reference's semantics
## rather than on the data: `setCast` promotes exactly that record to
## `kCastMemberSprite`, so the reference calls it occupied too.
##
## **What is left is a gap and not a divergence, and it is worth keeping
## separate.** The port has no way to draw a QuickDraw shape *sprite* at all: the
## record never survives `_snapshot`, and `director_shape.gd` paints a type-8
## *member*. That is D2/D3-era authoring — from D5 a shape is a cast member, and
## `director_shape.gd`'s own docstring records `sprite type 16 in all 60,914`
## shape records — so no container here can express it, and the 24-byte score
## layout where it would live is one `director_score.gd` refuses outright.
## `AGENTS.md`'s "Build Director, not this game" says a measured zero is a reason
## to build it last, never a reason to call it absent by design.
##
## Title-agnostic: it names no game and discovers the roots by listing them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Ink := preload("res://director/director_ink.gd")
const Paths := preload("res://director/director_paths.gd")

## Where corpora live. Each *subdirectory* of one of these is one corpus root,
## the same discovery `tools/member_type_census.gd` does.
const CORPUS_DIRS := ["res://games", "res://test-games"]

## `types.h`'s `SpriteType`, for the report only.
const TYPE_NAME := {
	0: "inactive", 1: "bitmap", 2: "rect", 3: "roundrect", 4: "oval",
	5: "line \\", 6: "line /", 7: "text", 8: "button", 9: "checkbox",
	10: "radio", 11: "pict", 12: "outline rect", 13: "outline roundrect",
	14: "outline oval", 15: "thick line", 16: "cast member", 17: "film loop",
	18: "dir movie",
}


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


## The reference's `_spriteType` for this record **after** `loadFrame`, i.e. after
## `setSpriteCasts` has run `setCast` over it. Returns the raw byte unchanged
## whenever `setCast`'s promotion does not apply.
static func _ref_type(raw_type: int, member: int, cast_lib: int) -> int:
	if Ink.QD_SHAPE_SPRITE_TYPES.has(raw_type):
		return raw_type
	if member != 0 or cast_lib != 0:
		return 16
	return raw_type


func _print_hist(hist: Dictionary) -> void:
	var keys: Array = hist.keys()
	keys.sort()
	if keys.is_empty():
		print("    (none)")
		return
	for k in keys:
		print("    %3d %-18s %d" % [int(k), str(TYPE_NAME.get(int(k), "?")), int(hist[k])])


func _init() -> void:
	var args := Args.parse()

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
	var list_left := Args.number(args, "list", 8)
	# **Why a frame cap exists at all.** The full walk is 65.9M records and 243 s,
	# and almost none of that is the classification below — `channel_buffer`
	# replays the delta stream from the nearest keyframe on *every* call, so the
	# cost is frames x KEYFRAME_INTERVAL rather than frames. A cap keeps every
	# container in the run (which is the part that must not be sampled: a title
	# is not uniform, and the whole point is that a QuickDraw shape would live in
	# an old container) and takes the opening frames of each. 0 is no cap and is
	# the survey; the gate entry passes a small one.
	var max_frames := Args.number(args, "max-frames", 0)

	var records := 0
	var movies := 0
	var containers := 0
	# **The survey's own blind spot, counted rather than left implicit.**
	# `director_score.gd` reads the 48-byte sprite record and refuses the older
	# 24-byte one (`tools/container_versions.gd`), and the 24-byte layout is
	# exactly where a *QuickDraw shape sprite* — the A1 case, a shape drawn from
	# the record with no cast member — is most likely to live, because from D5 a
	# shape is a cast member instead. So a zero in the A column is a zero over
	# the containers this reader opens, and `refused` says how many it did not.
	var no_score := 0
	var refused := 0
	# Disagreement buckets, and the fourth column that is not one.
	var a1 := 0
	var a2 := 0
	var a3 := 0
	var b := 0
	var shape_with_member := 0
	# raw type byte -> count, over the A records only.
	var a_types: Dictionary = {}
	var sites: Array[String] = []
	var per_root: Dictionary = {}
	# The type byte's own distribution, split by whether the record names a
	# member. **This is the guard on the whole survey, not colour.** A run that
	# reports "0 disagreements" is indistinguishable from a run that read a
	# structurally-zero byte, and `director_score.gd`'s own header records the
	# port having done exactly that at offsets 4 and 19 for months. If the
	# `member = 0` column below is `{0: everything}` then the A columns are zero
	# by construction and prove nothing; the `member > 0` column is what says the
	# byte is live at all.
	var type_hist_empty: Dictionary = {}
	var type_hist_member: Dictionary = {}

	for root in roots:
		var targets: Array[String] = []
		_walk(root, targets)
		targets.sort()
		var root_a := 0
		var root_records := 0
		for path in targets:
			containers += 1
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var vwsc: Array = f.ids_of("VWSC")
			if vwsc.is_empty():
				no_score += 1
				f.close()
				continue
			var score := Score.new()
			if not score.parse(f.read_chunk(int(vwsc[0]))):
				refused += 1
				f.close()
				continue
			movies += 1
			var frames: int = score.frame_count
			if max_frames > 0:
				frames = mini(frames, max_frames)
			for i in frames:
				var buffer := score.channel_buffer(i)
				for channel in range(1, score.channels_displayed + 1):
					var at: int = Score.SPRITE_RECORD_SIZE * (channel + Score.CHANNEL_BIAS)
					if at + Score.SPRITE_RECORD_SIZE > buffer.size():
						break
					var raw_type: int = buffer[at]
					var cast_lib: int = (buffer[at + 4] << 8) | buffer[at + 5]
					if cast_lib >= 0x8000:
						cast_lib -= 0x10000
					var member: int = (buffer[at + 6] << 8) | buffer[at + 7]
					records += 1
					root_records += 1
					var port_occupied := member > 0
					if port_occupied:
						type_hist_member[raw_type] = int(type_hist_member.get(raw_type, 0)) + 1
					else:
						type_hist_empty[raw_type] = int(type_hist_empty.get(raw_type, 0)) + 1
					var ref_occupied := _ref_type(raw_type, member, cast_lib) != 0
					if port_occupied and Ink.QD_SHAPE_SPRITE_TYPES.has(raw_type):
						shape_with_member += 1
					if port_occupied == ref_occupied:
						continue
					if port_occupied and not ref_occupied:
						b += 1
						continue
					root_a += 1
					a_types[raw_type] = int(a_types.get(raw_type, 0)) + 1
					if Ink.QD_SHAPE_SPRITE_TYPES.has(raw_type):
						a1 += 1
					elif raw_type != 0:
						a2 += 1
					else:
						a3 += 1
					if list_left > 0:
						list_left -= 1
						sites.append("    %s  frame %d ch %d  type %d (%s) lib %d fore %d back %d thick %d  %dx%d at (%d,%d)" % [
							path.trim_prefix("res://"), i, channel, raw_type,
							str(TYPE_NAME.get(raw_type, "?")), cast_lib,
							buffer[at + 2], buffer[at + 3],
							buffer[at + Score.THICKNESS_AT] & Score.THICKNESS_MASK,
							(buffer[at + 18] << 8) | buffer[at + 19],
							(buffer[at + 16] << 8) | buffer[at + 17],
							(buffer[at + 14] << 8) | buffer[at + 15],
							(buffer[at + 12] << 8) | buffer[at + 13]])
			f.close()
		per_root[root] = [root_a, root_records]

	print("%d container(s): %d walked, %d with no VWSC, %d whose score this reader refuses" % [
		containers, movies, no_score, refused])
	print("%d channel records%s" % [records,
		"" if max_frames <= 0 else "  (first %d frame(s) of each score only)" % max_frames])
	print("")
	print("  A  port empty / reference occupied : %d" % (a1 + a2 + a3))
	print("       A1 QuickDraw shape, no member : %d" % a1)
	print("       A2 live non-shape type, no member : %d" % a2)
	print("       A3 type 0, member 0, cast lib set : %d" % a3)
	print("  B  port occupied / reference empty : %d" % b)
	print("")
	print("  (not a disagreement) QD shape type *with* a member : %d" % shape_with_member)
	print("")
	var keys: Array = a_types.keys()
	keys.sort()
	for k in keys:
		print("  A by type byte  %2d %-18s %d" % [int(k), str(TYPE_NAME.get(int(k), "?")), int(a_types[k])])
	print("")
	print("  type byte, records naming a member:")
	_print_hist(type_hist_member)
	print("  type byte, records naming no member:")
	_print_hist(type_hist_empty)
	print("")
	for root in roots:
		var row: Array = per_root.get(root, [0, 0])
		print("  %-34s A=%-8d of %d records" % [str(root).trim_prefix("res://"), int(row[0]), int(row[1])])
	if not sites.is_empty():
		print("")
		print("  first %d disagreeing records:" % sites.size())
		for line in sites:
			print(line)

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.check("walked records", records > 0, "%d records" % records)
	h.complete("the survey ran")

	h.begin("the type byte is live")
	# **The guard on everything else here.** A run that reports "0 disagreements"
	# is indistinguishable from a run that read a structurally-zero byte, and
	# `director_score.gd`'s own header records the port having read two such
	# bytes for months (offset 4 for the flags, offset 19 for the blend amount)
	# and drawing conclusions from the zeros. So the survey asserts that the byte
	# it is classifying on takes a live value somewhere before it reports on it.
	var live := false
	for k in type_hist_member:
		if int(k) != 0:
			live = true
	h.check("some record carries a non-zero sprite type", live,
		"member-bearing records by type: %s" % str(type_hist_member))
	h.complete("the type byte is live")

	h.begin("the disagreement is one-directional")
	# Asserted, not reported: `setCast` promotes any record with a member to
	# `kCastMemberSprite` before `isEmpty` ever reads the type, so a record the
	# port keeps cannot be one the reference drops. A non-zero B means this
	# file's reading of `sprite.cpp:588` is wrong and the whole A column is
	# suspect with it.
	h.check("no record is occupied here and empty in the reference", b == 0, "%d" % b)
	h.complete("the disagreement is one-directional")
	quit(h.finish("channel occupancy: port vs reference"))
