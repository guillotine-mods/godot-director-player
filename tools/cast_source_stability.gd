extends SceneTree
## Does a cast hand back the same Lingo source every time it is parsed?
##
##   godot --headless --path . --script tools/cast_source_stability.gd -- \
##       --file games/piposh/PIPDATA/MASTER.CST --repeat 5
##   godot --headless --path . --script tools/cast_source_stability.gd -- \
##       --root piposh --file PIPDATA/MASTER.CST --members 3,34,35,40,41,43
##
##   --file F      the container, absolute-ish (`res://` prepended) or --root relative
##   --root R      the corpus, when `--file` is relative to it
##   --repeat N    parse the container N times in this process (default 4)
##   --members L   comma-separated member numbers to print in full detail
##   --verbose     print every member's length, not only the ones that differ
##
## ## Why
##
## Measured on 2026-08-14: three identical runs of
##
##   godot --headless --path . --script tools/liveness_sweep.gd -- --root piposh --only slotmach
##
## printed `lingo: master 46 script(s)` once and `lingo: master 40 script(s)`
## twice, the second and third naming the same six casualties —
##
##   MovieScript 3 - CLOCK SCRIPT: line 70: expected end
##   MovieScript 34: line 3: unexpected ""
##   MovieScript 35/40/41/43 - CLOCK SCRIPT2..5: line 45: expected end
##
## Those five CLOCK SCRIPTs are Piposh 1's clock: they advance `GlobalHour` and
## `GlobalSecond`, ring the hourly gong, arm `the mouseDownScript` for the
## `frizz` interruption, and gate every mission and meeting in the game on
## `h & s`. Losing them at random is not a rendering difference — it is half the
## title's logic present or absent per launch, and every casino minigame's exit
## (`go to movie "day" & globalday`) reads state the clock keeps.
##
## `tools/script_compile_check.gd` cannot see this: it compiles all 8754 scripts
## of `piposh` and passes, because it parses each container **once**. The failure
## is not "this source does not compile", it is "this source is not always the
## same source", and telling those apart needs the same bytes asked for twice.
##
## So this asks the narrowest possible question, with the compiler out of the
## picture: parse the container repeatedly and compare each member's `source`
## string to what the first parse returned. A difference here puts the bug in
## `director/director_cast.gd`'s info-block read; no difference here, with the
## drop still reproducible through `boot.gd`, puts it in the compiler or in what
## `boot.gd` hands it.
##
## Reports and asserts: a container that decodes differently on two reads in one
## process is wrong under every reading, so this exits non-zero when it happens.

const Args := preload("res://tools/lib/args.gd")
const Harness := preload("res://tools/lib/harness.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var path := Args.text(args, "file", "")
	if path == "":
		print("--file is required")
		quit(1)
		return
	if not path.begins_with("res://"):
		var root_name := Args.text(args, "root", "")
		if root_name != "" and not path.begins_with("games/"):
			path = "res://games/%s/%s" % [root_name, path]
		else:
			path = "res://" + path
	if not FileAccess.file_exists(path):
		print("no such container: %s" % path)
		quit(1)
		return

	var repeat := maxi(2, Args.number(args, "repeat", 4))
	var wanted: Array = []
	for text in Args.text(args, "members", "").split(",", false):
		wanted.append(int(text))
	var verbose := Args.flag(args, "verbose")

	print("container: %s" % path)
	var baseline: Dictionary = {}
	var order: Array = []
	var drift: Array[String] = []
	var counts: Array[int] = []

	for pass_index in repeat:
		var sources := _read(path)
		counts.append(sources.size())
		if pass_index == 0:
			baseline = sources
			order = sources.keys()
			order.sort()
			continue
		for number in order:
			if not sources.has(number):
				drift.append("pass %d: member %d has no source at all" % [
					pass_index, int(number)])
				continue
			var was := str(baseline[number])
			var now := str(sources[number])
			if was != now:
				drift.append("pass %d: member %d  %d chars -> %d chars%s" % [
					pass_index, int(number), was.length(), now.length(),
					"" if was.length() != now.length() else "  (same length, different bytes)"])
		for number in sources.keys():
			if not baseline.has(number):
				drift.append("pass %d: member %d gained a source" % [
					pass_index, int(number)])

	print("members with source, per pass: %s" % str(counts))
	if verbose or not wanted.is_empty():
		for number in order:
			if not wanted.is_empty() and not wanted.has(int(number)):
				continue
			var text := str(baseline[number])
			print("  member %-5d %5d chars  %s" % [
				int(number), text.length(),
				text.substr(0, 60).replace("\r", " ").replace("\n", " ")])

	h.begin("a container decodes to the same Lingo every time")
	h.check("no member's source changed between passes", drift.is_empty(),
		"\n      ".join(drift.slice(0, 12)))
	var stable := true
	for count in counts:
		if count != counts[0]:
			stable = false
	h.check("the same number of members carry source", stable, str(counts))
	h.complete("a container decodes to the same Lingo every time")
	quit(h.finish("cast source stability"))


## One parse, as `boot.gd` gets it: open the container, parse the cast, and take
## `member(n)["source"]` for every member the cast lists. Deliberately a fresh
## `DirectorFile` and a fresh `DirectorCast` each pass — a cached parse would
## answer the question "does the cache return itself", which is not the question.
func _read(path: String) -> Dictionary:
	var out: Dictionary = {}
	var file = ContainerFile.new()
	if not file.open(path):
		return out
	var cast = Cast.new()
	if not cast.open(file):
		file.close()
		return out
	for number in cast.member_numbers():
		var member: Dictionary = cast.member(int(number))
		var source := str(member.get("source", ""))
		if source.strip_edges() != "":
			out[int(number)] = source
	return out
