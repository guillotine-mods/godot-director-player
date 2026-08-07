extends SceneTree
## What the score asks the clock for: transitions, delays and waits.
##
##   godot --headless --script tools/transition_survey.gd -- --all
##   godot --headless --script tools/transition_survey.gd -- --file PIP2DATA/DAY1.dir
##
## Written before implementing transitions, to find out whether there was
## anything to implement. `docs/DIRECTOR_ENGINE.md` §10 describes about fifty
## numbered types over thirteen algorithms; this asks how many of them a real
## title reaches for, and the answer decided how much of §10 got built.
##
## It reports the three sources §10 lists, as far as a container can answer them:
##
##   - a **puppet transition** from Lingo — not visible in the score at all, so
##     the count is a grep of `reference/lingo/` and is quoted in
##     `director/director_transition.gd` rather than measured here;
##   - the **frame's** transition, a member reference in the main channel;
##   - the **transition cast member** it names, which is where the type,
##     duration and chunk size actually live.
##
## The tempo waits are in the same report on purpose. Transitions, `delay` and
## wait-for-click are one question — how much real time the score takes that
## nothing in the port was taking — and separating them into two surveys would
## have made each look smaller than it is.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Transition := preload("res://director/director_transition.gd")


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

	var movies := 0
	var frames := 0
	var transition_frames := 0
	var members_declared := 0
	var unresolved: Array[String] = []
	## transition type -> frames that play it.
	var types: Dictionary = {}
	## duration in ms -> frames that spend it.
	var durations: Dictionary = {}
	var total_hold_ms := 0.0
	var sites: Array[String] = []

	var delay_frames := 0
	var delay_ms_total := 0
	var wait_click_frames := 0
	var tempo_frames := 0
	## Where the first few holds are, so "the intro feels slow now" can be traced
	## to the frames the score asked to be slow on rather than argued about.
	var wait_sites: Array[String] = []

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
		var table := CastTable.new()
		table.open(f, paths)
		movies += 1

		# Every member of type 14 the container declares, whether or not a frame
		# names it. An authored-then-unused transition is a different fact from a
		# transition the movie plays, and only the second costs time.
		for lib in table.cast_libs:
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			for number in cast.member_numbers():
				var member: Dictionary = cast.member(int(number))
				if int(member.get("type", 0)) == 14:
					members_declared += 1

		for i in score.frame_count:
			var frame: Dictionary = score.frame(i)
			frames += 1
			if int(frame.get("tempo", 0)) != 0:
				tempo_frames += 1
			if bool(frame.get("wait_click", false)):
				wait_click_frames += 1
				if wait_sites.size() < 12:
					wait_sites.append("%-14s f%-5d wait for a click" % [path.get_file(), i])
			var delay := int(frame.get("delay_ms", 0))
			if delay > 0:
				delay_frames += 1
				delay_ms_total += delay
				if wait_sites.size() < 12:
					wait_sites.append("%-14s f%-5d delay %d ms" % [path.get_file(), i, delay])
			var number := int(frame.get("transition_member", 0))
			if number <= 0:
				continue
			transition_frames += 1
			var cast = table.cast_for(int(frame.get("transition_lib", 1)))
			var member: Dictionary = cast.member(number) if cast != null else {}
			if not Transition.is_transition(member):
				unresolved.append("%s f%d member %d (type %s)" % [
					path.get_file(), i, number, str(member.get("type_name", "missing")),
				])
				continue
			var type_code := int(member.get("transition_type", 0))
			var duration := int(member.get("duration_ms", 0))
			types[type_code] = int(types.get(type_code, 0)) + 1
			durations[duration] = int(durations.get(duration, 0)) + 1
			total_hold_ms += Transition.hold_ms(member)
			sites.append("%-14s f%-5d member %-4d %s" % [
				path.get_file(), i, number, Transition.describe(member),
			])
		table.close()
		f.close()

	print("%d movie(s), %d frames" % [movies, frames])
	print("")
	print("transitions:")
	print("  cast members of type 14   : %d" % members_declared)
	print("  frames naming one         : %d" % transition_frames)
	print("  time they hold the playhead: %.1f s" % (total_hold_ms / 1000.0))
	if not types.is_empty():
		var type_keys: Array = types.keys()
		type_keys.sort()
		print("  by type:")
		for k in type_keys:
			print("    %3d  %-26s %d frame(s)" % [
				k, str(Transition.TYPE_NAMES.get(k, "unnamed")), int(types[k])
			])
		var duration_keys: Array = durations.keys()
		duration_keys.sort()
		print("  by duration:")
		for k in duration_keys:
			print("    %5d ms  %d frame(s)" % [int(k), int(durations[k])])
	print("  where:")
	if sites.is_empty():
		print("    nowhere")
	for line in sites:
		print("    %s" % line)
	if not unresolved.is_empty():
		print("  frames naming a member that is not a transition:")
		for line in unresolved:
			print("    %s" % line)
	print("")
	print("the rest of the tempo channel, for scale:")
	print("  frames writing any tempo  : %d" % tempo_frames)
	print("  wait-for-click frames     : %d" % wait_click_frames)
	print("  delay frames              : %d  (%.1f s in total)" % [
		delay_frames, delay_ms_total / 1000.0
	])
	for line in wait_sites:
		print("    %s" % line)

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	# Not "there are transitions": a corpus with none is a legitimate answer and a
	# gate that failed on it would be asserting something about this game rather
	# than about the reader. What must hold is that every frame naming a member
	# resolved to one this port can time, because that is the reader's own job.
	h.check("every named transition member resolved", unresolved.is_empty(),
		"%d unresolved" % unresolved.size())
	h.complete("the survey ran")
	quit(h.finish("transition and tempo-wait usage"))
