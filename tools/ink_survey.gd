extends SceneTree
## What the ink byte and the thickness byte actually hold, across the corpus.
##
##   godot --headless --script tools/ink_survey.gd -- --file PIP2DATA/EXODUS.DIR
##   godot --headless --script tools/ink_survey.gd -- --root rating
##   godot --headless --script tools/ink_survey.gd -- --all
##
##   --root NAME     one corpus root under games/ (overrides the config in memory)
##   --roots A,B     explicit roots, `res://`-prefixed or bare
##   --all           every subdirectory of games/ and test-games/
##   --file PATH     one container of the chosen root
##   --masks N       print the first N Mask-ink records with the member they mask by
##
## The export cannot answer this: `frames.json` carries the ink but not the
## thickness byte or the blend amount, because nothing decoded them until now.
## This reads the containers.
##
## What it is for: deciding which inks are worth implementing properly and which
## can honestly fall through to Copy, and — for blend — what the stored amount
## actually ranges over, which decides how it maps to an alpha.
##
## ## `--all` used to mean "every container of the configured root"
##
## It walked `paths.root` and nothing else, so **every number this file has ever
## printed under `--all` was a measurement of whichever single root
## `director_game.cfg` named** — Piposh 2 in the tracked config. That is
## `AGENTS.md`'s "a measured zero in this repository is usually a measurement of
## Piposh 2" arriving in the instrument the rule tells you to reach for, and it is
## the same defect `18eab996` fixed in `tools/collision_ink.gd` one layer up: there
## the roots were enumerated and then all resolved against Piposh 2's *files*, here
## they were never enumerated at all. `--all` now walks `games/` **and**
## `test-games/`, one root at a time, and prints a per-root table beside the total
## so a number can never again name a scope nothing counted.
##
## Roots are opened through `load_config`'s `force_root` rather than by assigning
## `.root` afterwards, for the reason `collision_ink.gd` writes out at length: the
## path index latches on the first `resolve`, and a root assigned after
## `load_config` resolves its linked casts against the configured root's files.
## It matters here only for the Mask column, which is the one thing this survey
## asks a cast table for.
##
## ## The Mask column, and why it is here
##
## Ink 9 uses **the next cast member by number** as a 1-bit mask over the sprite's
## own artwork (§2.6, `channel.cpp:getMask`'s `else if` arm). Building it needs to
## know how often it appears and whether `castId + 1` is actually a 1-bit bitmap
## when it does, so every ink-9 record is followed to its mask member and the four
## outcomes are counted separately: resolved and 1-bit, resolved but not a bitmap,
## resolved but not 1-bit, and absent. The reference warns and draws unmasked for
## the last three; a survey that only counted ink 9 could not tell a corpus that
## uses the feature from one that names a mask that is not there.
##
## The cast table is opened **only for a container that holds an ink-9 record**,
## which on this corpus is none of them and costs nothing; a survey that opened
## 651 cast tables to print four zeros would not be run.
##
## The ink byte's top two bits are counted here for the same reason. Trails
## (0x40) is the expensive one to be wrong about: a trails sprite is not erased
## between frames, so §13 says an immediate-mode renderer needs an accumulation
## buffer that survives the repaint, which is a rewrite of how the stage is
## painted rather than a flag to honour. Measured over the whole corpus, **0 of
## Piposh 2's 816,318 sprite records carry it and 0 of Piposh 1's 1,886,362** —
## while 86,845 and 106,604 respectively carry stretch (0x80) out of the same
## byte, so the byte is being read and the bit is genuinely never set. Trails was
## built anyway, and `tools/stage_clip.gd` gates the assumption underneath it:
## the preview clears the stage every frame, which is correct only while nothing
## asks for trails.
##
## **The thickness-byte counts this printed used to be meaningless.** Flip, blend
## and tweened all read offset 4 of the sprite record, which is the high half of
## the cast lib and constant zero, so all four columns printed 0 whatever the
## data held. The byte is 22 (`director_score.gd`), and read from there the same
## corpora say: flip still 0 on both, but **has-blend 1,818 and 11,512** and
## **tweened 600,968 of 816,318 and 1,326,064 of 1,886,362**. A zero that came
## from the wrong offset is not a measurement, and this one had been quoted in
## three places as if it were.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Ink := preload("res://director/director_ink.gd")

## Where corpora live. The same two parents `tools/collision_ink.gd` and
## `tools/member_type_census.gd` discover, so "all eight roots" means the same
## eight set of directories in every survey that claims it.
const CORPUS_DIRS := ["res://games", "res://test-games"]

const INK_NAMES := {
	0: "Copy", 1: "Transparent", 2: "Reverse", 3: "Ghost", 4: "Not Copy",
	5: "Not Transp", 6: "Not Reverse", 7: "Not Ghost", 8: "Matte", 9: "Mask",
	32: "Blend", 33: "Add Pin", 34: "Add", 35: "Sub Pin",
	36: "BackgndTrans", 37: "Light", 38: "Sub", 39: "Dark",
}

## What `castId + 1` turned out to be, for a Mask-ink record.
const MASK_OK := "1-bit bitmap"
const MASK_ABSENT := "no such member"
const MASK_NOT_BITMAP := "not a bitmap"
const MASK_NOT_1BIT := "bitmap but not 1-bit"


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


## Which roots this run measures. Never "the configured root" unless that is what
## was asked for: the whole point of printing this list is that the scope of a
## number is visible beside it.
func _roots(args: Dictionary, configured: String) -> Array[String]:
	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	var one_root := Args.text(args, "root", "")
	if explicit != "":
		for part in explicit.split(",", false):
			var name := str(part).strip_edges()
			roots.append(name if name.begins_with("res://") else "res://games/%s" % name)
	elif Args.flag(args, "all"):
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	elif one_root != "":
		roots.append(one_root if one_root.begins_with("res://")
			else "res://games/%s" % one_root)
	else:
		roots.append(configured)
	roots.sort()
	return roots


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var roots := _roots(args, paths.root)
	var only_file := Args.text(args, "file", "")
	var masks_left := Args.number(args, "masks", 12)

	var inks: Dictionary = {}
	var blend_amounts: Dictionary = {}
	var flip_h := 0
	var flip_v := 0
	var has_blend := 0
	var tweened := 0
	var trails := 0
	var stretch := 0
	var thickness: Dictionary = {}
	var total := 0
	var movies := 0
	## root -> {"movies", "records", "mask"}
	var per_root: Dictionary = {}
	## outcome -> count, over every ink-9 record in every root.
	var mask_targets: Dictionary = {}
	var mask_lines: Array[String] = []

	for root in roots:
		# Through `force_root`, never by assigning `.root` afterwards: the path
		# index latches on the first `resolve`, so a root set after `load_config`
		# resolves its linked casts out of the *configured* root's files. That is
		# the defect `18eab996` measured at 82-versus-585 in `collision_ink.gd`,
		# and the Mask column below is exactly the kind of cast lookup it would
		# corrupt.
		var root_paths := Paths.new()
		root_paths.load_config(Paths.CONFIG_PATH, root)
		var targets: Array[String] = []
		if only_file != "":
			var resolved: String = root_paths.resolve(only_file)
			if resolved == "":
				print("no such container in %s: %s" % [root, only_file])
				continue
			targets.append(resolved)
		else:
			_walk(root, targets)
			targets.sort()

		var root_movies := 0
		var root_records := 0
		var root_masks := 0
		for path in targets:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var vwsc: Array = f.ids_of("VWSC")
			if vwsc.is_empty():
				f.close()
				continue
			var score := Score.new()
			if not score.parse(f.read_chunk(int(vwsc[0]))):
				f.close()
				continue
			movies += 1
			root_movies += 1
			# Opened lazily, and only for a container that actually holds an ink-9
			# record. On this corpus that is no container at all, so the Mask
			# column costs one integer comparison per record rather than 651 cast
			# tables.
			var table = null
			for i in score.frame_count:
				for sprite_value in score.frame(i).get("sprites", []):
					var sprite: Dictionary = sprite_value
					total += 1
					root_records += 1
					var ink := int(sprite["ink"])
					inks[ink] = int(inks.get(ink, 0)) + 1
					if ink == Ink.MASK:
						root_masks += 1
						if table == null:
							table = CastTable.new()
							table.open(f, root_paths)
						var outcome := _mask_outcome(table, sprite)
						mask_targets[outcome] = int(mask_targets.get(outcome, 0)) + 1
						if masks_left > 0:
							masks_left -= 1
							mask_lines.append("  %s frame %d ch %s  %d:%d -> %d:%d  %s" % [
								path.get_file(), i + 1, str(sprite.get("channel", "?")),
								int(sprite["cast_lib"]), int(sprite["cast_id"]),
								int(sprite["cast_lib"]), int(sprite["cast_id"]) + 1,
								outcome])
					if bool(sprite.get("trails", false)):
						trails += 1
					if bool(sprite.get("stretch", false)):
						stretch += 1
					if bool(sprite.get("flip_h", false)):
						flip_h += 1
					if bool(sprite.get("flip_v", false)):
						flip_v += 1
					if bool(sprite.get("tweened", false)):
						tweened += 1
					var t := int(sprite.get("thickness", 0))
					thickness[t] = int(thickness.get(t, 0)) + 1
					if bool(sprite.get("has_blend", false)):
						has_blend += 1
					if ink == 32 or bool(sprite.get("has_blend", false)):
						var a := int(sprite.get("blend_amount", 0))
						blend_amounts[a] = int(blend_amounts.get(a, 0)) + 1
			f.close()
		per_root[root] = {
			"movies": root_movies, "records": root_records, "mask": root_masks,
		}

	print("roots measured (%d):" % roots.size())
	for root in roots:
		var row: Dictionary = per_root.get(root, {})
		print("  %-32s %4d movie(s)  %9d records  %6d Mask" % [
			root, int(row.get("movies", 0)), int(row.get("records", 0)),
			int(row.get("mask", 0))])
	print("")
	print("%d movie(s), %d sprite records" % [movies, total])
	print("")
	print("ink:")
	var ink_keys: Array = inks.keys()
	ink_keys.sort()
	for k in ink_keys:
		print("  %3d  %-14s %8d  %5.2f%%" % [
			k, INK_NAMES.get(k, "?"), int(inks[k]), 100.0 * float(inks[k]) / maxf(total, 1)
		])
	print("")
	print("Mask ink (9): what castId + 1 resolves to")
	if mask_targets.is_empty():
		print("  no ink-9 record in any root measured")
	var mask_keys: Array = mask_targets.keys()
	mask_keys.sort()
	for k in mask_keys:
		print("  %-22s %d" % [k, int(mask_targets[k])])
	for line in mask_lines:
		print(line)
	print("")
	print("ink byte, above the six ink bits:")
	print("  stretch (0x80)  : %d" % stretch)
	print("  trails  (0x40)  : %d" % trails)
	print("")
	print("thickness byte:")
	print("  flip horizontal : %d" % flip_h)
	print("  flip vertical   : %d" % flip_v)
	print("  has-blend flag  : %d" % has_blend)
	print("  tweened         : %d" % tweened)
	var t_keys: Array = thickness.keys()
	t_keys.sort()
	var t_line := ""
	for k in t_keys:
		t_line += "%d:%d  " % [k, int(thickness[k])]
	print("  line thickness  : %s" % t_line)
	print("")
	print("blend amount, where blend applies:")
	var b_keys: Array = blend_amounts.keys()
	b_keys.sort()
	if b_keys.is_empty():
		print("  none")
	for k in b_keys:
		print("  %3d -> %d records" % [k, int(blend_amounts[k])])

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	# The scope guard. A survey whose roots list is empty prints zeros for every
	# column and reads exactly like a corpus that uses none of these inks.
	h.check("every root asked for was walked",
		per_root.size() == roots.size(), "%d of %d" % [per_root.size(), roots.size()])
	h.complete("the survey ran")
	quit(h.finish("ink and thickness byte usage"))


## What the member one past a Mask-ink sprite's own actually is.
##
## `channel.cpp:getMask` builds the mask from `CastMemberID(member + 1, castLib)`
## and refuses it with a warning when the member is absent, is not a bitmap, or is
## a bitmap of more than one bit. Those three refusals are counted apart from the
## success because they are what tells a corpus that *uses* Mask ink from one that
## names a mask that is not there — and the second is the case a port must render
## unmasked rather than invisible.
func _mask_outcome(table, sprite: Dictionary) -> String:
	var lib := int(sprite["cast_lib"])
	var m: Dictionary = table.get_member(lib, int(sprite["cast_id"]) + 1)
	if m.is_empty():
		return MASK_ABSENT
	if int(m.get("type", 0)) != Ink.TYPE_BITMAP:
		return MASK_NOT_BITMAP
	if int(m.get("bits_per_pixel", 8)) != 1:
		return MASK_NOT_1BIT
	return MASK_OK
