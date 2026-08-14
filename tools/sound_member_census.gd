extends SceneTree
## Every sound cast member in reach, decoded, and what the decoder makes of it.
##
##   godot --headless --script tools/sound_member_census.gd
##   godot --headless --script tools/sound_member_census.gd -- --roots res://games/piposh
##   godot --headless --script tools/sound_member_census.gd -- --list
##
## `director/director_sound.gd` decodes all three shapes Director ever wrote for
## a sound member -- an embedded AIFF or WAVE file, a Mac `snd ` resource, and
## the D4+ `sndH`/`sndS` pair -- and until this ran, **none of it had ever been
## handed a real one.** Three places said so in the same words, and all three
## were wrong about the corpus rather than about the code:
##
##   AGENTS.md                 "no cast in this game holds a sound member, so all
##   docs/ENGINE_TODO.md        of it is proved against synthesised bytes only"
##   scenes/preview/media.gd   "no cast in any of the six titles holds a sound
##                              member; every sound these games play is an
##                              external `.aif` reached by `sound playFile`"
##
## `tools/member_type_census.gd` counts **204 type-6 `CASt` chunks** across the
## eight corpus roots: 87 in `itamar-magichat`, 66 in `itamar-park`, and 17 each
## in `piposh`, `piposh-en` and `piposh-ru`. The claim was measured on Piposh 2,
## which genuinely has none, and then written as if it were about the corpus. Two
## of the six shipped titles are not Piposh 2 and were never checked.
##
## So the decoder has real input for the first time, and this is the instrument
## that hands it over. What it asserts is deliberately weak and deliberately not
## a count:
##
##   * every sound member the cast table can address has **either a payload chunk
##     or a linked filename** -- one with neither is a member the engine cannot
##     reach by any route, which is a decode bug and not an absent feature; and
##   * every payload that is found **decodes to a stream with samples**, or names
##     the reason it cannot in `director_sound.gd`'s own error list.
##
## The first check is deliberately not "owns a payload". Director allows a sound
## member to name an external file instead of embedding one, and
## `castmember/sound.cpp:load()` reaches that case from a payload that is absent
## *or* zero bytes. 54 of `itamar-park`'s 66 are that shape -- `%Coll1`, `%Eat1`,
## `%HiScore` in `Sound.cst` -- so asserting every member is embedded would have
## written this port's reach down as Director's rule, which is the failure mode
## `porting-fidelity-verification` exists to name.
##
## Neither is "204 members decode", because that number is a property of the
## corpus and would have to be edited every time a root is added -- the failure
## mode `docs/bugs-closed.md` records for pinned counts. The floor is 1: a run
## that found no sound member at all has lost the walk, and would otherwise
## report "0 failures" in exactly the voice of a clean pass.
##
## `--list` prints one line per member: where it is, which tag it came in under,
## and the rate, sample size, channel count, frame count and cue points the
## decoder computed. That listing is the point of the tool. A count proves the
## walk; the numbers are what a human compares against the original.
##
## Title-agnostic: it names no game and discovers its roots by listing them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const SoundMember := preload("res://director/director_sound.gd")
const Paths := preload("res://director/director_paths.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]
const SOUND := 6


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var list_them := Args.flag(args, "list")

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

	h.begin("every sound member in reach is opened and decoded")

	var members := 0
	var with_payload := 0
	var linked := 0
	var decoded := 0
	var by_tag: Dictionary = {}
	var by_corpus: Dictionary = {}
	var by_rate: Dictionary = {}
	var by_bits: Dictionary = {}
	var with_cues := 0
	var no_payload: Array[String] = []
	var failures: Array[String] = []
	var listed: Array[String] = []

	# Keyed the way `tools/xtra_members.gd` keys it, and for the same reason: a
	# shared cast that ninety movies link is one library, and walking it per movie
	# would multiply the whole corpus by the number of rooms.
	var seen_casts: Dictionary = {}

	for root in roots:
		var corpus := str(root).get_file()
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		# One `Paths` per root. It indexes the tree on first use, so a fresh one
		# per movie turns this into an O(movies x files) directory scan.
		var member_paths := Paths.new()
		member_paths.root = root
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var member_table := CastTable.new()
			if not member_table.open(f, member_paths):
				member_table.close()
				f.close()
				continue
			# Through the cast *table* rather than `Cast.open(container)`, because
			# that is how the player addresses a library and the survey should see
			# what the engine sees -- the internal cast, a library embedded in the
			# same container under its own `castID`, and a linked `.cst` alike.
			#
			# **It buys nothing for sound in this corpus, and that is worth saying
			# rather than implying otherwise.** `tools/member_type_census.gd`
			# reconciles both walks against the raw `CASt` chunks, and for type 6
			# they agree everywhere: `itamar-park` 66 of 66, `piposh` 17 of 17, and
			# `itamar-magichat` **39 of 87 through either route**. So 48 of Magic
			# Hat's sound members are type-6 `CASt` chunks that no `CAS*` the cast
			# table opens addresses -- unreferenced in the container, or in a
			# library nothing links. That is a finding about that corpus and an open
			# question, not something this tool has fixed.
			for lib in member_table.cast_libs.keys():
				var cast = member_table.cast_for(int(lib))
				if cast == null:
					continue
				var cast_key := "%s#%d" % [
					str(member_table.cast_libs[lib].get("resolved_path", "")),
					int(cast.cas_chunk_id),
				]
				if seen_casts.has(cast_key):
					continue
				seen_casts[cast_key] = true
				var source = member_table.file_for(int(lib))
				if source == null:
					continue
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if m.is_empty() or int(m.get("type", 0)) != SOUND:
						continue
					members += 1
					by_corpus[corpus] = int(by_corpus.get(corpus, 0)) + 1
					var where := "%s %s #%d '%s'" % [
						corpus, path.get_file(), number, str(m.get("name", ""))]

					var data_id := int(m.get("data_chunk_id", -1))
					var tag := str(m.get("sound_tag", ""))
					if data_id < 0:
						# Not a fault by itself. Director lets a sound member name
						# an external file instead of embedding it, and
						# `castmember/sound.cpp:load()` reaches that case from a
						# payload that is absent *or* zero bytes. The member is
						# only broken if it has neither a payload nor a name.
						var link := str(m.get("link_filename", ""))
						if link != "":
							linked += 1
							if list_them:
								listed.append("%-58s %-5s linked -> %s" % [where, "", link])
						else:
							no_payload.append(where)
						continue
					with_payload += 1
					by_tag[tag] = int(by_tag.get(tag, 0)) + 1

					var payload: PackedByteArray = source.read_chunk(data_id)
					var header := PackedByteArray()
					var header_id := int(m.get("sound_header_chunk_id", -1))
					if header_id >= 0 and header_id != data_id:
						header = source.read_chunk(header_id)

					var why: Array = []
					var stream: AudioStreamWAV = SoundMember.decode(payload, header, why)
					if stream == null or stream.data.size() == 0:
						failures.append("%s  [%s, %d bytes]: %s" % [
							where, tag, payload.size(),
							"decoded to nothing" if why.is_empty()
							else ", ".join(PackedStringArray(why))])
						continue
					decoded += 1

					var bits := 16 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 8
					var channels := 2 if stream.stereo else 1
					var frames := stream.data.size() / (bits / 8) / channels
					by_rate[stream.mix_rate] = int(by_rate.get(stream.mix_rate, 0)) + 1
					by_bits[bits] = int(by_bits.get(bits, 0)) + 1
					var cues: Array = SoundMember.cue_points(payload)
					if not cues.is_empty():
						with_cues += 1
					if list_them:
						listed.append("%-58s %-5s %6d Hz %2d-bit %dch %8d frames %6.2f s%s" % [
							where, tag, stream.mix_rate, bits, channels, frames,
							float(frames) / maxf(1.0, float(stream.mix_rate)),
							"" if cues.is_empty() else "  %d cue(s)" % cues.size()])
			member_table.close()
			f.close()

	print("")
	print("%d sound member(s) over %d cast librar(ies)" % [members, seen_casts.size()])
	if not by_corpus.is_empty():
		var corpora: Array = by_corpus.keys()
		corpora.sort()
		for c in corpora:
			print("  %-18s %d" % [c, int(by_corpus[c])])
	print("")
	print("  payload tag      %s" % _tally(by_tag))
	print("  sample rate      %s" % _tally(by_rate))
	print("  sample size      %s" % _tally(by_bits))
	print("  with cue points  %d" % with_cues)
	print("  linked (named an external file, no embedded payload)  %d" % linked)

	if list_them and not listed.is_empty():
		print("")
		listed.sort()
		for line in listed:
			print("  %s" % line)

	if not no_payload.is_empty():
		print("")
		print("sound members with no payload chunk and no linked filename:")
		for line in no_payload:
			print("  %s" % line)
	if not failures.is_empty():
		print("")
		print("payloads the decoder refused, with its own reason:")
		for line in failures:
			print("  %s" % line)

	print("")
	# The floor, not the count. A run that reached no sound member has lost the
	# walk, and every other check below would pass vacuously on an empty set --
	# which reads identically to a clean sweep in the gate's one-line table.
	h.check("the walk reached a sound member at all", members >= 1,
		"%d found; 0 means the cast-table walk broke, not that the corpus changed" % members)
	# Not "owns a payload": Director allows a linked sound member, and asserting
	# every member is embedded would encode this port's reach as Director's rule.
	# What is actually broken is a member with neither -- no chunk to decode and
	# no filename to look for.
	h.check("every sound member has either a payload or a linked filename",
		no_payload.is_empty(),
		"%d of %d have neither (%d embedded, %d linked)"
			% [no_payload.size(), members, with_payload, linked])
	h.check("every payload decodes to a stream with samples", failures.is_empty(),
		"%d of %d refused" % [failures.size(), with_payload])
	h.complete("every sound member in reach is opened and decoded")

	quit(h.finish("the sound member decoder against the real members in the corpus"))


func _tally(counts: Dictionary) -> String:
	if counts.is_empty():
		return "(none)"
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s x%d" % [str(k), int(counts[k])])
	return "  ".join(parts)


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var lower := str(name).to_lower()
		if lower.ends_with(".dir") or lower.ends_with(".cst") \
				or lower.ends_with(".dxr") or lower.ends_with(".cxt"):
			out.append(dir_path.path_join(name))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
