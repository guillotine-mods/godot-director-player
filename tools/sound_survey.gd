extends SceneTree
## Does the score itself ever play a sound in this corpus?
##
##   godot --headless --script tools/sound_survey.gd -- --all
##   godot --headless --script tools/sound_survey.gd -- --all --offsets
##   godot --headless --script tools/sound_survey.gd -- --file PIP2DATA/AIR1.dir --dump
##
## `scenes/preview_lingo_host.gd` carried the claim that "the score's own sound
## channels are empty in all 61 movies", and §12 of `docs/DIRECTOR_ENGINE.md`
## describes two score sound channels with restart-on-change semantics. Nothing
## had measured the claim: the score decoder never read those bytes, so it could
## only ever have been an assumption about a region no code looked at.
##
## **The answer does not decide whether the feature gets built.** It is built --
## `director/score_sound.gd` and `director_score.gd:_sound_channels` -- because
## Director has it and the next title may use it. What this decides is what to
## trust: everything the engine does with score sound is unverified against real
## data, and these numbers are why, so a future session reads "unexercised" here
## rather than re-deriving it or, worse, assuming it was tested.
##
## Two independent measurements, because the layout of the main channel block is
## only partly understood and a claim resting on one guessed offset is worth
## nothing:
##
##  1. **The cast census.** A score sound channel names a *cast member* of type
##     `sound`. If the game's casts hold no sound members, no frame can name one,
##     whatever the byte layout turns out to be. This is the argument that does
##     not depend on knowing where the slots are.
##  2. **The block survey.** Every byte of every frame's 288-byte main channel
##     block, and every 16-bit slot in it resolved as a member number against
##     *every* cast library the movie can address. A slot naming sound members
##     would show up here regardless of which offset it sits at.
##
## `--offsets` prints the per-byte histogram; `--dump` walks one movie's block
## frame by frame. Both are for the next person who has to re-derive the layout,
## and bugs.md 31 is the nine bytes of it still unaccounted for.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")

## Main-channel offsets the port resolves as a cast member number: the frame
## script, the transition and the palette. The two sound channels are handled
## separately because they are the subject of this survey rather than a control.
const MEMBER_REFERENCE_SLOTS := [2, 98, 242]
const CastTable := preload("res://director/director_cast_table.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")

## Offsets in the main channel block this port's decoder claims to understand,
## so an unexplained non-zero byte stands out in the histogram.
const KNOWN := {
	0: "frame script cast lib", 1: "frame script cast lib",
	2: "frame script member", 3: "frame script member",
	53: "tempo operand", 54: "tempo code",
	96: "transition cast lib", 97: "transition cast lib",
	98: "transition member", 99: "transition member",
	# Main-channel records 3 and 4, Director's two sound channels. Zero in every
	# frame of this corpus, which is what the checks below assert.
	144: "sound 1 cast lib", 145: "sound 1 cast lib",
	146: "sound 1 member", 147: "sound 1 member",
	192: "sound 2 cast lib", 193: "sound 2 cast lib",
	194: "sound 2 member", 195: "sound 2 member",
	# The palette channel is the last of the six main-channel records and is
	# decoded as a whole by `director_score.gd`; listed here so the "not
	# attributed" report below stays about the bytes nobody has claimed.
	240: "palette record", 241: "palette record", 242: "palette record",
	243: "palette record", 244: "palette record", 245: "palette record",
	246: "palette record", 247: "palette record", 248: "palette record",
	249: "palette record", 250: "palette record", 251: "palette record",
}
## Tempo codes that mean "hold the playhead until a sound finishes": D6's pair,
## which carry a cue-point index beside them, and D5's. §9.1.
const SOUND_WAIT_TEMPO := [255, 254, 135, 134]


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

	if Args.flag(args, "dump") and targets.size() == 1:
		_dump(targets[0], paths, Args.number(args, "frames", 60))

	# --- 1. the cast census -------------------------------------------------
	# Counted per *container*, not per library reference, so a shared cast linked
	# by forty movies is counted once.
	var member_types: Dictionary = {}
	var sound_members: Array[String] = []
	var casts_read := 0
	for path in targets:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var cast := Cast.new()
		if cast.open(f):
			casts_read += 1
			for number in cast.member_numbers():
				var m: Dictionary = cast.member(int(number))
				var kind := str(m.get("type_name", "?"))
				member_types[kind] = int(member_types.get(kind, 0)) + 1
				if kind == "sound" and sound_members.size() < 20:
					sound_members.append("%s #%d %s" % [
						path.get_file(), int(number), str(m.get("name", "")),
					])
		f.close()

	# --- 2. the main channel block survey -----------------------------------
	var byte_values: Dictionary = {}
	# 16-bit offset -> {member type name -> times}, over every library.
	var slot_types: Dictionary = {}
	var movies := 0
	var scored := 0
	var frames := 0
	var undecoded: Dictionary = {}
	# What the decoder itself makes of the two sound channels, alongside the raw
	# byte survey. Both, because they answer different questions: the byte survey
	# says what is in the block, and this says what the engine reads out of it.
	var decoded_cues := 0

	for path in targets:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		movies += 1
		var vwsc: Array = f.ids_of("VWSC")
		if vwsc.is_empty():
			f.close()
			continue
		var score := Score.new()
		if not score.parse(f.read_chunk(int(vwsc[0]))):
			f.close()
			continue
		scored += 1
		var table := CastTable.new()
		table.open(f, paths)
		var libs: Array = table.cast_libs.keys()

		for i in score.frame_count:
			frames += 1
			decoded_cues += score.frame(i).get("sound_channels", []).size()
			var block := score.main_channel(i)
			for at in block.size():
				if block[at] == 0:
					continue
				var seen: Dictionary = byte_values.get(at, {})
				seen[block[at]] = int(seen.get(block[at], 0)) + 1
				byte_values[at] = seen
				if not KNOWN.has(at):
					var who: Array = undecoded.get(at, [])
					if who.size() < 4 and not who.has(path.get_file()):
						who.append(path.get_file())
					undecoded[at] = who
			var at16 := 0
			while at16 + 1 < block.size():
				var value := (block[at16] << 8) | block[at16 + 1]
				if value != 0:
					_record_slot(slot_types, table, libs, at16, value)
				at16 += 2
		table.close()
		f.close()

	print("%d container(s), %d cast(s) read, %d with a score, %d frames" % [
		movies, casts_read, scored, frames,
	])
	print("")
	print("cast members by type, over every container:")
	var type_keys: Array = member_types.keys()
	type_keys.sort()
	for k in type_keys:
		print("  %-14s %6d" % [str(k), int(member_types[k])])
	if not sound_members.is_empty():
		print("  sound members found:")
		for line in sound_members:
			print("     %s" % line)
	print("")

	if Args.flag(args, "offsets"):
		print("main channel bytes that are ever non-zero:")
		var keys: Array = byte_values.keys()
		keys.sort()
		for at in keys:
			var seen: Dictionary = byte_values[at]
			var vals: Array = seen.keys()
			vals.sort()
			var shown: Array = []
			for v in vals.slice(0, 8):
				shown.append("%d x%d" % [int(v), int(seen[v])])
			print("  %3d  %-22s %s%s" % [
				at, str(KNOWN.get(at, "")), ", ".join(shown),
				" ..." if vals.size() > 8 else "",
			])
		print("")

	print("every 16-bit slot of the block, resolved against every cast library:")
	var slots: Array = slot_types.keys()
	slots.sort()
	for at in slots:
		var types: Dictionary = slot_types[at]
		var parts: Array = []
		var kinds: Array = types.keys()
		kinds.sort()
		for t in kinds:
			parts.append("%s x%d" % [str(t), int(types[t])])
		print("  %3d  %-22s %s" % [at, str(KNOWN.get(at, "")), ", ".join(parts)])
	print("")

	print("bytes no part of this port attributes, that are ever non-zero:")
	if undecoded.is_empty():
		print("  none")
	else:
		var keys: Array = undecoded.keys()
		keys.sort()
		for at in keys:
			print("  %3d  in %s" % [at, ", ".join(undecoded[at])])
	print("")

	# Split in two, because "some 16-bit slot resolves to a sound member" and
	# "a score writes a sound channel" are different claims and only the second
	# is about score sound. A slot at an odd alignment inside the tempo record
	# resolves to *something* in any large enough cast, and Piposh 1 has one that
	# lands on a sound member in two frames purely by arithmetic.
	var sound_channel_slots: Array[String] = []
	var other_slots_naming_sound: Array[String] = []
	for at in slots:
		var types: Dictionary = slot_types[at]
		if not types.has("sound"):
			continue
		var line := "offset %d in %d frame(s)" % [at, int(types["sound"])]
		# The member half of each sound record: `SOUND_CHANNEL_AT` plus two.
		if Score.SOUND_CHANNEL_AT.has(at - 2):
			sound_channel_slots.append(line)
		else:
			other_slots_naming_sound.append(line)

	# The other way a frame can be about sound: a wait-for-sound tempo. D6
	# numbers those 255 and 254 (with a cue-point index beside them) and D5 used
	# 135 and 134. The histogram above is where the answer comes from — byte 54
	# only ever holds 246, 247 or 248 — and this turns it into a gate, because
	# "nothing waits on sound" is what lets §9's clock ignore the case entirely.
	var sound_waits: Array[String] = []
	for code in byte_values.get(54, {}):
		if SOUND_WAIT_TEMPO.has(int(code)):
			sound_waits.append("tempo %d in %d frame(s)" % [int(code), int(byte_values[54][code])])

	var h := Harness.new()
	h.begin("the score's own sound channels are measured, not assumed")
	h.check("read at least one score", scored > 0, "%d of %d containers" % [scored, movies])
	# This used to assert that no container held a sound cast member at all,
	# which was true of the first title and is not a property of anything:
	# Piposh 1 ships 17 of them, so the tool answered FAIL to the news that a
	# second game had been loaded. Whether a corpus *has* sound members is a
	# measurement and is printed above; what the port claims is narrower and is
	# what is asserted here.
	print("sound cast members in this corpus: %d" % int(member_types.get("sound", 0)))
	print("frames whose score sound channels name a member: %s" % (
		"none" if sound_channel_slots.is_empty() else "; ".join(sound_channel_slots)))
	print("")
	# The claim: the two offsets `_sound_channels` reads are the only places a
	# score keeps sound. Both corpora leave them empty, which is why §12's
	# frame-driven half is still labelled unverified rather than done -- and
	# Piposh 1 makes that a real finding rather than a tautology, because it has
	# 17 sound members to put there and puts none of them there.
	h.check("the score's sound channels are unexercised by this corpus",
		sound_channel_slots.is_empty(), "; ".join(sound_channel_slots))
	# Any *other* slot that resolves to a sound member is only interesting if the
	# port reads that slot as a member reference. It reads four besides the sound
	# channels -- the frame script, the transition and the palette -- and a hit on
	# one of those would mean an offset is wrong. A hit anywhere else is two bytes
	# at an alignment nothing uses, resolving by arithmetic in a large enough
	# cast, and Piposh 1 has one inside the tempo record.
	var misread: Array[String] = []
	for line in other_slots_naming_sound:
		for claimed in MEMBER_REFERENCE_SLOTS:
			if line.begins_with("offset %d " % claimed):
				misread.append(line)
	h.check("and no slot the port reads as a member reference names a sound",
		misread.is_empty(), "; ".join(misread))
	if not other_slots_naming_sound.is_empty():
		print("")
		print("slots that resolve to a sound member and are read by nothing: %s"
			% "; ".join(other_slots_naming_sound))
	# The same question asked through the decoder rather than through the bytes. It
	# is not redundant: `_sound_channels` reads two specific offsets, and this is
	# what catches those two offsets being read wrong in the direction that yields
	# *more* sound than there is.
	h.check("the score decoder finds no sound cue in any frame", decoded_cues == 0,
		"%d cue(s)" % decoded_cues)
	h.check("no frame's tempo cell is a wait-for-sound",
		sound_waits.is_empty(), "; ".join(sound_waits))
	h.complete("the score's own sound channels are measured, not assumed")
	quit(h.finish("score sound channels across the corpus"))


## Frame by frame, for reading one movie's main channel block by eye. The
## histogram says which offsets move; this says what they move *with*.
func _dump(path: String, paths, count: int) -> void:
	var f := ContainerFile.new()
	if not f.open(path):
		return
	var vwsc: Array = f.ids_of("VWSC")
	if vwsc.is_empty():
		f.close()
		return
	var score := Score.new()
	if not score.parse(f.read_chunk(int(vwsc[0]))):
		f.close()
		return
	var table := CastTable.new()
	table.open(f, paths)
	print("cast libraries of %s:" % path.get_file())
	for lib in table.cast_libs:
		var info: Dictionary = table.cast_libs[lib]
		print("  %2d  %-14s %d..%d" % [
			int(lib), str(info.get("name", "")), int(info.get("min", 0)),
			int(info.get("max", 0)),
		])
	print("")
	print("frame  script    4..7       48..51     tempo")
	for i in mini(count, score.frame_count):
		var b := score.main_channel(i)
		print("%5d  %3d,%-5d %3d,%-5d  %3d,%-5d  %3d/%3d" % [
			i, (b[0] << 8) | b[1], (b[2] << 8) | b[3],
			(b[4] << 8) | b[5], (b[6] << 8) | b[7],
			(b[48] << 8) | b[49], (b[50] << 8) | b[51],
			b[54], b[53],
		])
	table.close()
	f.close()
	print("")


## One 16-bit slot of one frame, resolved as a member number in every library the
## movie can address. The best answer any library gives wins: `unresolved` only
## when no library holds that number at all.
func _record_slot(types: Dictionary, table, libs: Array, at: int, value: int) -> void:
	var kind := "unresolved"
	for lib in libs:
		var member: Dictionary = table.get_member(int(lib), value)
		if member.is_empty():
			continue
		var found := str(member.get("type_name", ""))
		if found == "sound":
			kind = found
			break
		if kind == "unresolved":
			kind = found
	var bucket: Dictionary = types.get(at, {})
	bucket[kind] = int(bucket.get(kind, 0)) + 1
	types[at] = bucket
