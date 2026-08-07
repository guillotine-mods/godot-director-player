extends SceneTree
## Who carries the Auto Hilite flag, and does anything on screen display them?
##
##   godot --headless --script tools/hilite_survey.gd -- --file PIP2DATA/EXODUS.DIR
##   godot --headless --script tools/hilite_survey.gd -- --all
##
## `DIRECTOR_ENGINE.md` §4.6. `shouldHilite()` inverts a sprite's silhouette on
## mouse-down, and for a bitmap the switch is the member's **Auto Hilite** info
## flag -- bit 1 of the flag word at offset 12 of the cast info block, which
## nothing in this port decoded until `director/director_cast.gd:_parse_info`
## started reading it. Before that the question could not be asked at all.
##
## What this decides. Hilite is built either way -- Director has it, so the
## engine has it -- but the measurement decides two real things: how much of the
## corpus can exercise it (and therefore whether the harness has to synthesise
## its own case, as `tools/trails.gd` does), and whether this title's buttons
## rely on hilite at all or swap members instead, which many Director titles do.
##
## Three numbers per container, because a flag nobody displays is not a feature
## anybody sees:
##
##   members         bitmap members whose info block sets the flag
##   sprite records  score records naming one of them
##   eligible        those records after §4.6's own filters -- not moveable, and
##                   a *bitmap*, which is where a shape cast member drops out
##
## Eligibility is only approximated here: `isActive()` also needs to know whether
## a score or cast script exists for the sprite, which is a movie-level question
## and a running interpreter's to answer. `tools/hilite.gd` asserts the real
## predicate against the live player; this counts what the containers hold.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Ink := preload("res://director/director_ink.gd")


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
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	# A survey is asked across titles, and the configured root is a working file
	# several agents and `gate.sh` share -- so this overrides it in memory rather
	# than rewriting the config out from under whoever else is running.
	var other_root := Args.text(args, "root", "")
	if other_root != "":
		paths.root = other_root if other_root.begins_with("res://") \
			else "res://games/%s" % other_root

	var targets: Array[String] = []
	if Args.flag(args, "all"):
		_walk(paths.root, targets)
		targets.sort()
	else:
		var one: String = paths.resolve(Args.text(args, "file", paths.boot_movie))
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	var containers := 0
	var members_total := 0
	var members_with_info := 0
	var members_hilite := 0
	var bitmaps_hilite := 0
	var records_total := 0
	var records_hilite := 0
	var records_eligible := 0
	var records_matte_no_info := 0
	var flag_words: Dictionary = {}
	var no_info_types: Dictionary = {}
	var named: Array[String] = []

	for path in targets:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		containers += 1
		var table := CastTable.new()
		table.open(f, paths)

		# Every member this container's cast bundle can reach, not just its own:
		# a movie draws from the shared casts and the flag lives with the member.
		var hilite_members: Dictionary = {}
		for lib in range(1, 40):
			var cast = table.cast_for(lib)
			if cast == null:
				continue
			for number in cast.member_numbers():
				var m: Dictionary = cast.member(number)
				if m.is_empty():
					continue
				members_total += 1
				var word := int(m.get("info_flags", 0))
				# Kept per member type, because that is what says the offset is
				# right: a word that is flags will set its documented bits on the
				# member types those bits belong to, and a word that is something
				# else will scatter.
				if not flag_words.has(word):
					flag_words[word] = {}
				var by_type: Dictionary = flag_words[word]
				var tn := str(m.get("type_name", "?"))
				by_type[tn] = int(by_type.get(tn, 0)) + 1
				if bool(m.get("has_cast_info", false)):
					members_with_info += 1
				else:
					var tn2 := str(m.get("type_name", "?"))
					no_info_types[tn2] = int(no_info_types.get(tn2, 0)) + 1
				if not bool(m.get("auto_hilite", false)):
					continue
				members_hilite += 1
				if int(m.get("type", 0)) == Ink.TYPE_BITMAP:
					bitmaps_hilite += 1
					hilite_members["%d:%d" % [lib, number]] = true
					if named.size() < 24:
						named.append("%s %d:%d %s" % [
							path.get_file(), lib, number,
							str(m.get("name", "")) if str(m.get("name", "")) != "" else "(unnamed)",
						])

		var vwsc: Array = f.ids_of("VWSC")
		if not vwsc.is_empty():
			var score := Score.new()
			if score.parse(f.read_chunk(int(vwsc[0]))):
				for i in score.frame_count:
					for sprite_value in score.frame(i).get("sprites", []):
						var sprite: Dictionary = sprite_value
						records_total += 1
						var lib := int(sprite["cast_lib"])
						var id := int(sprite["cast_id"])
						var m: Dictionary = table.get_member(lib, id)
						# The fallback arm: a bitmap with no cast info at all
						# hilites when its ink is Matte (§4.6). Counted apart,
						# because it is the arm this corpus might reach instead.
						if int(m.get("type", 0)) == Ink.TYPE_BITMAP \
								and not bool(m.get("has_cast_info", false)) \
								and (int(sprite["ink"]) & Ink.INK_MASK) == Ink.MATTE:
							records_matte_no_info += 1
						if not hilite_members.has("%d:%d" % [lib, id]):
							continue
						records_hilite += 1
						if not bool(sprite.get("moveable", false)):
							records_eligible += 1
		f.close()

	print("%d container(s), %d cast members, %d sprite records" % [
		containers, members_total, records_total])
	print("")
	print("cast info block:")
	print("  members with an info block   : %d" % members_with_info)
	print("  members without one          : %d" % (members_total - members_with_info))
	var no_info_keys: Array = no_info_types.keys()
	no_info_keys.sort()
	for k in no_info_keys:
		print("    %-12s %d" % [k, int(no_info_types[k])])
	print("  Auto Hilite set (any type)   : %d" % members_hilite)
	print("  Auto Hilite set on a bitmap  : %d" % bitmaps_hilite)
	print("")
	print("flag word values (offset 12 of the info block):")
	var words: Array = flag_words.keys()
	words.sort()
	for w in words:
		var by_type: Dictionary = flag_words[w]
		var total := 0
		var parts: Array[String] = []
		var type_names: Array = by_type.keys()
		type_names.sort()
		for tn in type_names:
			total += int(by_type[tn])
			parts.append("%s %d" % [tn, int(by_type[tn])])
		print("  0x%08x  %8d  %s%s" % [
			w, total,
			"AUTO HILITE  " if (int(w) & 0x02) != 0 else "",
			", ".join(parts),
		])
	print("")
	print("sprite records:")
	print("  naming an auto-hilite bitmap : %d" % records_hilite)
	print("  ... and not moveable         : %d" % records_eligible)
	print("  Matte ink, bitmap, no info   : %d  (the D3 fallback arm)"
		% records_matte_no_info)
	if not named.is_empty():
		print("")
		print("the members themselves (first %d):" % named.size())
		for line in named:
			print("  %s" % line)

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one container", containers > 0, "%d" % containers)
	# Only over a whole title. One container legitimately holds one flag value --
	# `strtgame.dir`'s 498 members are all plain zero -- so asserting this on a
	# single file would report the corpus as a decoding fault. Across a title it
	# is the check that says offset 12 is really the flag word: Piposh 1's only
	# non-zero value is 0x10 and it appears on 17 members, every one of them a
	# **sound** -- which is where the reference reads its looping bit from
	# (`cast.cpp:loadCastInfo`, `flags & 16`). A word that happened to be
	# something else could not land its documented bit on the one member type
	# that bit belongs to.
	if Args.flag(args, "all"):
		h.check("the flag word was decoded, not defaulted",
			flag_words.size() > 1 or members_total == 0,
			"%d distinct values -- one value for everything means the offset is wrong"
				% flag_words.size())
	h.complete("the survey ran")
	quit(h.finish("Auto Hilite across the corpus"))
