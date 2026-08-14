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
##
## **Each of these is half of a pair.** The main channel block is six 48-byte
## records and every one opens with `castLib` at +0 and the member at +2, so the
## library the port resolves in is always the 16-bit slot two bytes ahead --
## `director_score.gd:frame` reads 0 with 2, 96 with 98 and 240 with 242 and
## never resolves a member number on its own. `_record_slot` therefore has to
## resolve these three the same way, and `bugs.md` 114 is what it cost not to:
## resolving them against *every* library made the check report a sound member
## whenever any library in the movie happened to hold a sound at that number,
## which is a fact about the other library and not about the slot.
const MEMBER_REFERENCE_SLOTS := [2, 98, 242]
## member slot -> the library slot that pairs with it, for the three above.
const MEMBER_REFERENCE_LIB_AT := {2: 0, 98: 96, 242: 240}
## The three member references `director_score.gd:frame` hands out of the main
## channel, and the cast member type each one must name. Keyed by what the decode
## calls them rather than by an offset, so this tool cannot drift from the engine
## the way a second copy of the offsets did.
const DECODED_MEMBER_REFERENCES := {
	"frame script": "script", "transition": "transition", "palette": "palette",
}
## What share of the frames carrying a reference must resolve to that type.
##
## **A majority, not a purity test**, and the number was chosen by looking at
## what each kind of failure scores rather than at what the corpus scores. A
## misaligned offset reads two bytes out of the middle of another record and gets
## the expected type on approximately none of them; a corpus with a missing
## linked cast misses a handful out of hundreds. There is no value between those
## two that is wrong, and picking one near the corpus instead of near the middle
## is how a check ends up asserting the data: `itamar-park` names palette member
## 200 in library 6 on three consecutive frames of `torfim.dir` and that library
## is not in the recovery, so a 95% floor failed a *recovered corpus for being
## incomplete* — which is the `palette_corpus` mistake in AGENTS.md, made again.
const MEMBER_TYPE_FLOOR := 0.5
## Below this many frames a corpus cannot be expected to carry a frame script, so
## the presence half of the check below does not run. Any real corpus is orders
## of magnitude above it -- `piposh2` is 61,371 frames -- and a single `--file`
## run of one short movie is what it is here for.
const FRAME_SCRIPT_PRESENCE_MIN_FRAMES := 100
## `castLib` written as "this movie's own", which `director_score.gd` and every
## reader here fold to library 1. 0 means the same thing in the frame script and
## sound records, where an unauthored slot is left blank rather than set.
const OWN_CAST_LIB := 0xFFFF
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
	# Every slot that resolved to a sound member, named: movie, frame, the
	# library the slot's own record declares, the member number and its name.
	# A count alone cannot be followed up -- `bugs.md` 114 was opened on
	# "offset 2 in 16 frame(s)" and the next question was always "which 16".
	var sound_hits: Array[String] = []
	# What the *port's own decode* makes of the three member references it reads
	# out of the main channel, resolved in the library the same decode names:
	# reference name -> {member type name -> times}. Read through
	# `director_score.gd:frame` rather than off the raw offsets, so that moving an
	# offset in the engine moves this. See the check.
	var decode_shape: Dictionary = {}
	# Every frame where one of those three resolved to something other than the
	# type it is for, named. The share alone says a decode is wrong; this says
	# which frames, which is what tells a systematic miss from an authoring slip.
	var decode_misses: Array[String] = []
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
			var decoded: Dictionary = score.frame(i)
			decoded_cues += decoded.get("sound_channels", []).size()
			_record_decoded(decode_shape, table, decoded,
				"%s f%d" % [path.get_file(), i], decode_misses)
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
					_record_slot(slot_types, table, libs, at16, value, block,
						"%s f%d" % [path.get_file(), i], sound_hits)
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

	print("every 16-bit slot of the block, resolved as a member number")
	print("  (the three the port pairs with a castLib -- 2, 98, 242 -- in the library")
	print("   their own record declares; every other slot against every library):")
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

	if not sound_hits.is_empty():
		print("every frame whose slot resolved to a sound member (first 40):")
		for line in sound_hits.slice(0, 40):
			print("  %s" % line)
		if sound_hits.size() > 40:
			print("  ... %d more" % (sound_hits.size() - 40))
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
	if not h.check("read at least one score", scored > 0,
			"%d of %d containers" % [scored, movies]):
		# **Everything below is a conclusion about a population, and over an empty
		# one all of them are true and none of them means anything.** Run with a
		# `--root` this tool cannot resolve -- `test-games/` corpora, or a typo --
		# it read 0 containers and still printed "ok the score's sound channels
		# are unexercised by this corpus", which is *the exact sentence* that got
		# written into `AGENTS.md` and `preview_lingo_host.gd` as a fact about the
		# engine. The floor check turned the run red, so the gate was safe; a human
		# reading the output was not, because three green lines stating the
		# conclusion sat directly beneath the one red line explaining that nothing
		# had been counted.
		#
		# So the conclusions do not run at all without a denominator. A tool that
		# refuses is worth more than one that answers over nothing --
		# `bugs.md` 105 is the same lesson from the other direction, where an
		# instrument reported a board dead and was quoted as the state of the frame.
		print("")
		print("no score was read, so nothing below is asserted. A bare `--root "
			+ "<name>` resolves under `games/`; a corpus anywhere else needs its "
			+ "whole path, as `--root res://test-games/itamar-magichat`.")
		h.complete("the score's own sound channels are measured, not assumed")
		quit(h.finish("score sound channels across the corpus"))
		return
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
	# **The check above narrowed when `bugs.md` 114 turned out to be reading 3, so
	# this one exists to more than make up the catching power.** "Names a sound"
	# is a tripwire for one wrong answer out of a dozen, and only fires on the
	# frames that happen to land on a sound. What a wrong offset actually produces
	# is a *reference to the wrong kind of thing, on every frame*, because the two
	# bytes then come from the middle of some other record. So this asserts the
	# positive claim: what `director_score.gd` calls a frame script resolves to a
	# `script` member, what it calls a transition to a `transition`, and what it
	# calls a palette to a `palette` — each in the library that same decode names
	# beside it.
	#
	# **It reads the decode, not the offsets, and that is the point.** The first
	# version of this check walked the raw block at 2/98/242 — a copy of the
	# engine's constants living in this tool — and the control proved it useless:
	# moving the frame script member to offset 4 made it report "nothing resolves"
	# and **pass**, because offset 4 is zero in every frame of `piposh2` and a slot
	# that is never authored has nothing to be wrong about. Going through
	# `score.frame(i)` means the engine moving an offset moves this measurement,
	# and the same perturbation now turns it red.
	#
	# **Every frame that carries a reference counts**, including the ones that
	# resolve to nothing: "the number names no member" is exactly what a
	# misaligned read looks like, so excluding it is excluding the evidence. The
	# one value excluded is a **negative palette id**, which is not a member
	# reference at all — Director numbers its built-in palettes negatively, and
	# −1 (system Mac) is what all 267 of `piposh2`'s palette frames carry.
	#
	# **The floor is 95% and every corpus measured sits at 100% bar one frame:**
	# `piposh` has a single frame whose frame script names a bitmap in its own
	# library out of 64,624, and `piposh-en`, `piposh-ru`, `itamar-magichat` and
	# `itamar-park` have one apiece that names nothing. Requiring 100% would gate
	# this project on a 1997 authoring slip, which is the `palette_corpus` lesson
	# in AGENTS.md. A wrong offset does not score 95%.
	var shape_lines: Array[String] = []
	var shape_bad: Array[String] = []
	for what in DECODED_MEMBER_REFERENCES:
		if not decode_shape.has(what):
			continue
		var types: Dictionary = decode_shape[what]
		var want: String = DECODED_MEMBER_REFERENCES[what]
		var total := 0
		var right := 0
		for t in types:
			total += int(types[t])
			if str(t) == want:
				right += int(types[t])
		if total == 0:
			continue
		var share := float(right) / float(total)
		var parts: Array = []
		var kinds: Array = types.keys()
		kinds.sort()
		for t in kinds:
			parts.append("%s x%d" % [str(t), int(types[t])])
		shape_lines.append("%s %d/%d %s (%.1f%%) [%s]" % [
			what, right, total, want, share * 100.0, ", ".join(parts),
		])
		if share < MEMBER_TYPE_FLOOR:
			shape_bad.append("%s resolves to %s on %.1f%% of %d frame(s)" % [
				what, want, share * 100.0, total,
			])
	print("")
	print("what the port's own decode resolves each main-channel reference to:")
	if shape_lines.is_empty():
		print("  no frame in this corpus carries one")
	for line in shape_lines:
		print("  %s" % line)
	if not decode_misses.is_empty():
		print("  every frame that resolved to something else (first 20):")
		for line in decode_misses.slice(0, 20):
			print("    %s" % line)
		if decode_misses.size() > 20:
			print("    ... %d more" % (decode_misses.size() - 20))
	h.check("and each main-channel reference resolves to the member type it is for",
		shape_bad.is_empty(), "; ".join(shape_bad))
	# **The other half, and the one the control demanded.** A ratio can only speak
	# about frames that carry a reference, so an offset moved onto bytes that are
	# zero in every frame produces *no* references, an empty population and a
	# green ratio. That is not a hypothetical: the first version of this check was
	# handed exactly that perturbation — the frame script member read from offset 4
	# instead of 2 — and passed it.
	#
	# So: a corpus of any size has frame scripts. Measured, every root: 48,813 in
	# `piposh2`, 64,624 in `piposh`, 64,942 in `piposh-en`, 65,041 in `piposh-ru`,
	# 165 in `itamar-magichat`, 125 in `itamar-park`. Transition and palette are
	# deliberately **not** asserted this way, because a corpus really can have
	# none: `piposh2` names a transition on 5 frames out of 61,371 and a custom
	# palette on none at all — all 267 of its palette frames carry the built-in
	# system Mac id.
	var frame_scripts := 0
	for t in decode_shape.get("frame script", {}):
		frame_scripts += int(decode_shape["frame script"][t])
	if frames >= FRAME_SCRIPT_PRESENCE_MIN_FRAMES:
		h.check("and a corpus this size names a frame script somewhere",
			frame_scripts > 0, "%d frame script(s) in %d frame(s)" % [frame_scripts, frames])
	else:
		print("(%d frames read, below the %d this corpus needs for the frame script "
			% [frames, FRAME_SCRIPT_PRESENCE_MIN_FRAMES]
			+ "presence check; not asserted)")
	# The same question asked through the decoder rather than through the bytes. It
	# is not redundant: `_sound_channels` reads two specific offsets, and this is
	# what catches those two offsets being read wrong in the direction that yields
	# *more* sound than there is.
	h.check("the score decoder finds no sound cue in any frame", decoded_cues == 0,
		"%d cue(s)" % decoded_cues)
	# **A finding, not an assertion, and it used to be the other way round.**
	# "No frame's tempo cell is a wait-for-sound" was true of Piposh 2 and is false
	# of `rating`, which has **259 frames of tempo 255 and 17 of tempo 254** --
	# wait on sound channel 1 and channel 2. Asserting it made this tool answer
	# FAIL to the news that a title uses a feature Director has and the port
	# implements, which is the fourth time in one day a claim measured on Piposh 2
	# was written down as a property of the engine (see AGENTS.md, "a measured zero
	# here is usually a measurement of Piposh 2").
	#
	# It is also a different question from the one this tool asks. A wait-for-sound
	# *tempo cell* holds the playhead until a sound started from anywhere -- almost
	# always `sound playFile` from Lingo -- has finished. It is not a **score sound
	# channel** naming a member, which is what the two checks above are about, and
	# a corpus can have thousands of the first and none of the second. `rating` is
	# exactly that corpus.
	#
	# The path is implemented and wired: `director_score.gd:tempo_waits` decodes
	# the cell, `director_frame_clock.gd:_arm_waits` sets `_waiting_sound` from it,
	# and `playhead_held()` counts it. **The gap this number exposed is closed**:
	# `tools/sound_tempo_wait.gd` walks the corpus for one of these cells, lands on
	# it, plays a real sound into it and asserts the playhead is held and then
	# released, with `--root rating` in `gate.sh`. Before it, `sound_wait` ran bare
	# on `GATE_ROOT` and never read a tempo cell in any case, `frame_events`
	# fabricated one for a bare clock and `movie_tempo` said the holds were out of
	# its scope. `bugs.md` 115.
	if sound_waits.is_empty():
		print("frames whose tempo cell waits for a sound: none")
	else:
		print("frames whose tempo cell waits for a sound: %s" % "; ".join(sound_waits))
		print("  (a Lingo-played sound holding the playhead, not a score sound "
			+ "channel; decoded by director_score.gd:tempo_waits and held by "
			+ "director_frame_clock.gd:_arm_waits)")
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


## The three member references one decoded frame carries, resolved as the engine
## itself would resolve them: each member number in the library the same decode
## names beside it.
##
## A frame that names nothing in a slot contributes nothing — "no frame script"
## is not a wrong frame script. A frame that names a number contributes whatever
## that number turns out to be, `unresolved` included, because a reference to
## a member that is not there is the signature this exists to catch.
##
## The one exception is a **negative palette id**, which Director uses for its
## built-in palettes (−1 is system Mac) and which is therefore not a member
## reference at all. `director_score.gd:_palette_record` reads that field signed
## for the same reason.
func _record_decoded(shape: Dictionary, table, decoded: Dictionary, where: String,
		misses: Array[String]) -> void:
	var refs: Array = [
		["frame script", decoded.get("frame_script"), int(decoded.get("frame_script_lib", 1))],
		["transition", decoded.get("transition_member"), int(decoded.get("transition_lib", 1))],
	]
	var palette: Dictionary = decoded.get("palette", {})
	if not palette.is_empty() and int(palette.get("member", 0)) > 0:
		refs.append(["palette", int(palette["member"]), int(palette.get("cast_lib", 1))])

	for ref in refs:
		var number: int = int(ref[1]) if ref[1] != null else 0
		if number <= 0:
			continue
		var member: Dictionary = table.get_member(int(ref[2]), number)
		var kind := str(member.get("type_name", "unresolved")) if not member.is_empty() else "unresolved"
		var bucket: Dictionary = shape.get(ref[0], {})
		bucket[kind] = int(bucket.get(kind, 0)) + 1
		shape[ref[0]] = bucket
		if kind != DECODED_MEMBER_REFERENCES[ref[0]]:
			misses.append("%s %s -> lib %d member %d is %s" % [
				where, str(ref[0]), int(ref[2]), number, kind,
			])


## One 16-bit slot of one frame, resolved as a member number.
##
## **Two resolutions, and which one a slot gets is the whole of `bugs.md` 114.**
##
## A slot the port *reads* as a member reference is resolved in the library that
## slot's own record declares, because that is what the engine does with it: the
## frame script at 2 is looked up in the library named at 0, and a hit in some
## other library is not a thing the port can ever reach. Resolving those against
## every library is a strictly larger question than the one the check below asks,
## and it answered "sound" for 16 frames of Magic Hat and 13 of Itamar Park where
## the declared library holds a *script* at that number and a different library
## happens to hold a sound at it. That is the tool being wrong, not the decode.
##
## Every other slot has no declared library -- offset 52 is two bytes at an
## alignment inside the tempo record that nothing pairs with anything -- so the
## only honest question about it is "does this number name a sound anywhere",
## and that is what it still gets. Those are reported and asserted over by
## nothing, which is the correct weight for an arithmetic coincidence.
func _record_slot(types: Dictionary, table, libs: Array, at: int, value: int,
		block: PackedByteArray, where: String, sound_hits: Array[String]) -> void:
	var kind := "unresolved"
	var lib_note := "any library"
	if MEMBER_REFERENCE_LIB_AT.has(at):
		var lib_at: int = MEMBER_REFERENCE_LIB_AT[at]
		var declared := (block[lib_at] << 8) | block[lib_at + 1]
		var lib := 1 if declared == OWN_CAST_LIB or declared == 0 else declared
		lib_note = "lib %d" % lib
		var member: Dictionary = table.get_member(lib, value)
		kind = str(member.get("type_name", "unresolved")) if not member.is_empty() else "unresolved"
		if kind == "sound":
			sound_hits.append("%s offset %d -> %s member %d '%s'" % [
				where, at, lib_note, value, str(member.get("name", "")),
			])
	else:
		for lib in libs:
			var member: Dictionary = table.get_member(int(lib), value)
			if member.is_empty():
				continue
			var found := str(member.get("type_name", ""))
			if found == "sound":
				kind = found
				sound_hits.append("%s offset %d -> %s member %d '%s'" % [
					where, at, "lib %d" % int(lib), value, str(member.get("name", "")),
				])
				break
			if kind == "unresolved":
				kind = found
	var bucket: Dictionary = types.get(at, {})
	bucket[kind] = int(bucket.get(kind, 0)) + 1
	types[at] = bucket
