extends SceneTree
## Cast members read from the containers, checked against the exported JSON.
##
##   godot --headless --script tools/director_members.gd
##   godot --headless --script tools/director_members.gd -- --file DAY1.DIR --list 20
##
## SCAFFOLDING. The `--oracle` half compares against `assets/render_model/`,
## which is generated game data with a retirement date: when the container path
## renders, that tree and this comparison both go. What survives is the corpus
## sweep, which asks only whether every container yields members.
##
## The names case is the one worth keeping longest. A member's name and its Lingo
## source share the info block, and reading "the first Pascal string" out of it
## returns the script body for any member that carries a script — which is why
## `master` 77 has been coming out as a fragment of Lingo instead of `shell`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")

## Members whose names the info-block offset table must recover exactly. These
## are the ones the current pipeline gets wrong or needs a repair pass for.
const KNOWN_NAMES := {
	9: "object0", 30: "sciser", 40: "sulam", 54: "piphead1",
	55: "piphead2", 57: "invright", 59: "invleft", 69: "jokebtl", 77: "shell",
}


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var single := Args.text(args, "file")
	if single != "":
		_list(paths, single, Args.number(args, "list", 20))
		quit(0)
		return

	# --- names, against members the exporter is known to get wrong -----------
	h.begin("member names come out of the offset table")
	var master_path := paths.resolve("MASTER.CST")
	if h.check("MASTER.CST resolves", master_path != "", master_path):
		var mf := ContainerFile.new()
		if h.check("MASTER.CST opens", mf.open(master_path), mf.error):
			var mc := Cast.new()
			if h.check("its cast indexes", mc.open(mf), mc.error):
				var wrong: Array[String] = []
				for number in KNOWN_NAMES:
					var got := str(mc.member(number).get("name", ""))
					if got != KNOWN_NAMES[number]:
						wrong.append("%d: expected %s, got %s" % [
							number, KNOWN_NAMES[number], JSON.stringify(got),
						])
				h.check(
					"%d known member names exact" % KNOWN_NAMES.size(),
					wrong.is_empty(),
					"" if wrong.is_empty() else "; ".join(wrong),
				)
				h.check(
					"number_of() round-trips a name",
					mc.number_of("shell") == 77,
					"shell -> %d" % mc.number_of("shell"),
				)
			mf.close()
	h.complete("member names come out of the offset table")

	# --- corpus sweep --------------------------------------------------------
	var containers := _find(paths.root)
	var totals := {}
	var named := 0
	var fields := 0
	var missing_payload := 0
	var broken: Array[String] = []

	# Two costs, measured apart because only one of them is on the room-load
	# path: indexing is what opening a movie pays, parsing every member is what
	# a sweep pays and the game never does.
	var index_us := 0
	var parse_us := 0
	var slowest: Array[Dictionary] = []

	h.begin("every container yields a cast")
	for path in containers:
		var t0 := Time.get_ticks_usec()
		var f := ContainerFile.new()
		if not f.open(path):
			broken.append("%s: %s" % [path.get_file(), f.error])
			continue
		var c := Cast.new()
		if not c.open(f):
			# A container with no CAS* is not a cast; that is a fact, not a fault.
			f.close()
			continue
		var t1 := Time.get_ticks_usec()
		index_us += t1 - t0
		for number in c.member_numbers():
			var m := c.member(number)
			if m.is_empty():
				continue
			var type_name := str(m.get("type_name", "?"))
			totals[type_name] = int(totals.get(type_name, 0)) + 1
			if str(m.get("name", "")) != "":
				named += 1
			if int(m.get("type", 0)) == 3:
				fields += 1
			# Bitmaps, film loops and fields each own exactly one payload chunk.
			if int(m.get("type", 0)) in [1, 2, 3] and int(m.get("data_chunk_id", -1)) < 0:
				missing_payload += 1
		var t2 := Time.get_ticks_usec()
		parse_us += t2 - t1
		slowest.append({
			"name": path.get_file(),
			"index_ms": (t1 - t0) / 1000.0,
			"parse_ms": (t2 - t1) / 1000.0,
			"members": c.member_numbers().size(),
		})
		f.close()
	h.check(
		"all %d container(s) parsed" % containers.size(),
		broken.is_empty(),
		"" if broken.is_empty() else "%d failed" % broken.size(),
	)
	for line in broken:
		print("     %s" % line)
	h.check("members carry names", named > 4000, "%d named" % named)
	h.check("text members carry text", fields > 300, "%d field(s)" % fields)
	# The spec measured exactly three bitmaps in this corpus with no BITD.
	h.check(
		"members own their payload chunk",
		missing_payload <= 3,
		"%d without one" % missing_payload,
	)
	h.complete("every container yields a cast")

	# Opening a movie pays the index cost for that container plus its linked
	# casts; it never parses every member of the corpus. The budget that matters
	# is the worst single container, not the total.
	slowest.sort_custom(func(a, b): return float(a["index_ms"]) > float(b["index_ms"]))
	print("")
	print("index total   : %.0f ms for %d container(s)" % [index_us / 1000.0, containers.size()])
	print("parse total   : %.0f ms for every member (a sweep, not a room load)" % [parse_us / 1000.0])
	print("slowest index :")
	for row in slowest.slice(0, 5):
		print("  %-16s index %6.1f ms   parse %7.1f ms   %d members" % [
			row["name"], row["index_ms"], row["parse_ms"], row["members"],
		])
	h.begin("opening a movie is fast enough to do on a room change")
	var worst: float = float(slowest[0]["index_ms"]) if not slowest.is_empty() else 0.0
	h.check("slowest container indexes under 100 ms", worst < 100.0, "%.1f ms" % worst)
	h.complete("opening a movie is fast enough to do on a room change")

	print("")
	print("named members : %d" % named)
	print("text members  : %d" % fields)
	print("by type       :")
	var keys := totals.keys()
	keys.sort_custom(func(a, b): return int(totals[a]) > int(totals[b]))
	for key in keys:
		print("  %8d  %s" % [int(totals[key]), key])

	quit(h.finish("the cast layer reads this game's own files"))


func _list(paths, wanted: String, limit: int) -> void:
	var path = paths.resolve(wanted)
	if path == "":
		print("no such container: %s" % wanted)
		return
	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		return
	var c := Cast.new()
	if not c.open(f):
		print("%s: %s" % [path, c.error])
		f.close()
		return
	print("%s  %d slot(s)" % [path, c.member_count])
	var shown := 0
	for number in c.member_numbers():
		if shown >= limit:
			break
		var m := c.member(number)
		if m.is_empty():
			continue
		shown += 1
		var size := ""
		if int(m.get("width", 0)) > 0:
			size = "  %dx%d reg(%d,%d)" % [
				m["width"], m["height"], m["reg_offset_x"], m["reg_offset_y"],
			]
		var depth := ""
		if m.has("bits_per_pixel"):
			depth = "  %dbpp stride %d" % [m["bits_per_pixel"], m["row_stride"]]
		print("  %4d  %-10s %-16s%s%s" % [
			number, m.get("type_name", "?"), m.get("name", ""), size, depth,
		])
	f.close()


func _find(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, out)
	out.sort()
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
