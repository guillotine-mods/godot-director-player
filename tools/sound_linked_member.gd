extends SceneTree
## A sound cast member that names an **external file** instead of carrying one.
##
##   godot --headless --audio-driver Dummy --path . --script tools/sound_linked_member.gd
##   godot --headless --audio-driver Dummy --path . --script tools/sound_linked_member.gd -- --root piposh
##   godot --headless --audio-driver Dummy --path . --script tools/sound_linked_member.gd -- --list
##
## Director does not require a sound member to embed its audio.
## `castmember/sound.cpp:SoundCastMember::load()` reaches the external case from a
## payload that is **absent *or* zero bytes**, asks `_cast->getLinkedPath(_castId)`
## and builds an `AudioFileDecoder` on the answer — and it turns looping off for
## one, unconditionally, with the comment "Linked sound files always have the loop
## flag disabled".
##
## `director_cast.gd` has reported that state since sound members were first
## decoded and **nothing consumed it**, so a linked member played silence. 54 of
## `test-games/itamar-park`'s 66 sound members are that shape — `%Coll1`, `%Eat1`,
## `%HiScore` in `Sound.cst` — which is a game whose collect, eat and high-score
## effects were all mute with nothing in the log to say why.
##
## ## Three cases, and only one of them needs a linked member to exist
##
##   1. **The classification.** Every sound member the cast walk can reach, in
##      every root present, is either embedded or linked and never both, and a
##      linked one names a file. This is non-vacuous on a clean checkout: `piposh`,
##      `piposh-en` and `piposh-ru` ship 17 embedded sound members each, and every
##      one of them carries a **zero-length `snd ` chunk beside its real
##      `sndH`/`sndS` pair** — the exact shape the reference's zero-byte test looks
##      at. So those 51 are the regression guard for the branch stealing a member
##      that has perfectly good samples: classify on the *presence* of a `snd `
##      rather than on its size and all 51 go silent.
##   2. **The playback path**, `AudioDirector.play_linked_member`, against a real
##      audio file discovered under the root. The resolution, the decode and the
##      loop flag are all real; the only thing constructed is which member said so.
##      This is what runs on `GATE_ROOT` and it is corpus-independent by
##      construction — every title ships audio files.
##   3. **The linked members themselves**, where a root has any. Each must resolve
##      to a file on the disc that decodes to samples. `games/` ships none, so this
##      case **says out loud that it found nothing and asserts nothing** rather
##      than failing — the pattern `video_fallback` and `sprite_lifetime` use, and
##      the reason four `test-games/` entries are no longer in `gate.sh`.
##
## Title-agnostic: it names no game, no member and no sound file.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const SoundMember := preload("res://director/director_sound.gd")
const Paths := preload("res://director/director_paths.gd")
const MediaSurface := preload("res://scenes/preview/media.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]
const SOUND := 6
## A channel nothing else in a booted movie uses, so this cannot be measuring a
## sound the score started. `tools/sound_wait.gd` reserves one the same way.
const SPARE := 7
## A name no disc has, for the miss case. Deliberately not a plausible one: the
## point is that the *channel* ends up empty, not that some file was missing.
const ABSENT := "no-such-sound-anywhere.aif"


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var list_them := Args.flag(args, "list")

	# The autoloads are added to the root *after* `_init` returns, so a harness that
	# reaches for one before the first frame finds nothing. Every reader of
	# `AudioDirector` in `tools/` waits here first.
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if audio == null:
		print("no AudioDirector autoload")
		quit(1)
		return

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

	# ------------------------------------------------------------ classification
	var scanned := _scan(roots)
	var members := int(scanned["members"])
	var linked: Array = scanned["linked"]
	var embedded := int(scanned["embedded"])
	var both: Array = scanned["both"]
	var nameless: Array = scanned["nameless"]

	print("")
	print("%d sound member(s): %d embedded, %d linked" % [members, embedded, linked.size()])
	print("  reached the fallback through the reference's zero-byte arm: %d" % int(scanned["empty_beside"]))
	print("  ... and through its absent-payload arm: %d" % (linked.size() - int(scanned["empty_beside"])))
	if list_them:
		for line in (scanned["listing"] as Array):
			print("  %s" % line)

	h.begin("a sound member is embedded or linked, never both and never neither")
	h.check("the walk reached a sound member at all", members >= 1,
		"%d found; 0 means the cast-table walk broke, not that the corpus changed"
			% members)
	# The regression guard for the branch. A member with real samples beside a
	# zero-length `snd ` must be embedded, and 51 of this corpus's members are
	# exactly that shape -- so a `sound_linked` computed from the presence of a
	# `snd ` tag rather than from its size would light up here immediately.
	h.check("no member with a decodable payload is marked linked", both.is_empty(),
		"%d marked linked while holding samples: %s"
			% [both.size(), "; ".join(PackedStringArray(both.slice(0, 4)))])
	# The direct inverse of the check above, and the one that goes red if the
	# fallback is taken out again: a member with no payload chunk that does name a
	# file is a linked member by the reference's own test, and calling it embedded
	# is exactly the state 54 of `itamar-park`'s 66 were in.
	h.check("every member with no payload but a filename is marked linked",
		(scanned["missed"] as Array).is_empty(),
		"%d have a link and no payload and are not marked linked: %s"
			% [(scanned["missed"] as Array).size(),
				"; ".join(PackedStringArray((scanned["missed"] as Array).slice(0, 4)))])
	h.check("every linked member names a file", nameless.is_empty(),
		"%d marked linked with an empty filename: %s"
			% [nameless.size(), "; ".join(PackedStringArray(nameless.slice(0, 4)))])
	h.complete("a sound member is embedded or linked, never both and never neither")

	# ---------------------------------------------------------- the playback path
	var paths := Paths.new()
	paths.load_config()
	var sample := _some_audio(str(paths.root))
	h.begin("a linked member plays the file it names")
	if sample == "":
		h.check("the root ships an audio file to link to", false,
			"no .aif/.aiff/.wav anywhere under %s" % str(paths.root))
		h.complete("a linked member plays the file it names")
	else:
		audio.call("stop_channel", SPARE)
		var played: bool = audio.call("play_linked_member", SPARE, "3:17", sample)
		h.check("it starts", played and bool(audio.call("sound_busy", SPARE)),
			"play_linked_member('%s') returned %s" % [sample, str(played)])
		# The *member* is the identity, not the file behind it: `the member of
		# sound` answers a member, and restart-on-change compares members. A
		# linked member that reported its filename here would look like a
		# different sound every time two members linked the same file.
		h.check("and the channel reports the member, not the filename",
			str(audio.call("channel_source", SPARE)) == "3:17",
			str(audio.call("channel_source", SPARE)))
		var media: Dictionary = audio.call("linked_media", sample)
		var stream = media.get("stream")
		h.check("the same file answers `the duration` and the rest",
			stream != null and float(stream.get_length()) > 0.0,
			"linked_media('%s') -> %s" % [sample, str(media.get("path", ""))])
		# The reference's own rule and not a default: `load()` sets `_looping = 0`
		# in the linked arm whatever the member's own loop flag says.
		var loops := false
		if stream is AudioStreamWAV:
			loops = (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		elif stream != null:
			loops = bool(stream.get("loop"))
		h.check("and it does not loop, which is the reference's rule for a linked file",
			not loops, "loop flag is set on %s" % str(media.get("path", "")))
		h.complete("a linked member plays the file it names")

		# The miss. Director claims the channel before it opens the media, so a
		# member whose file is gone leaves the channel *empty* rather than still
		# playing what was there -- which is what makes a `soundBusy` poll after it
		# terminate. `AudioDirector._fail` carries the argument in full.
		h.begin("a linked member whose file is gone empties the channel")
		var missed: bool = audio.call("play_linked_member", SPARE, "3:18", ABSENT)
		h.check("it reports the miss", not missed, "returned true for '%s'" % ABSENT)
		h.check("and the channel is free rather than still playing the last sound",
			not bool(audio.call("sound_busy", SPARE)),
			"channel %d is still busy with %s"
				% [SPARE, str(audio.call("channel_source", SPARE))])
		h.complete("a linked member whose file is gone empties the channel")

	# ------------------------------------------------------- the linked members
	#
	# **Only the configured root's members**, and that restriction is not a
	# convenience. `AudioDirector` indexes one tree -- whichever `DirectorPaths`
	# was pointed at -- so asking it about a member from another root is asking the
	# wrong disc, and every answer would be "missing" for a file that is right
	# there. Run this once per root with `--root` to cover more than one.
	var here: Array = []
	for entry_value in linked:
		if str((entry_value as Dictionary).get("root", "")) == str(paths.root):
			here.append(entry_value)
	h.begin("every linked member in reach resolves to a file that decodes")
	if here.is_empty():
		# Said out loud rather than asserted: no root under `games/` ships a linked
		# sound member, and a check over an empty set reads exactly like a clean
		# pass. `test-games/itamar-park` has 54 and is not in this repository.
		print("")
		print("%s ships no linked sound member; nothing asserted here." % str(paths.root))
		print("%d exist in other roots and were not checked, because AudioDirector"
			% linked.size())
		print("indexes one tree. Run --root <that one> to reach them.")
		h.check("the scan ran over %d root(s)" % roots.size(), roots.size() >= 1,
			"no corpus root found at all")
	else:
		var missing: Array[String] = []
		var refused: Array[String] = []
		for entry_value in here:
			var entry: Dictionary = entry_value
			var media: Dictionary = audio.call("linked_media", str(entry["link"]))
			if str(media.get("path", "")) == "":
				missing.append("%s -> '%s'" % [str(entry["where"]), str(entry["link"])])
				continue
			var stream = media.get("stream")
			if stream == null or float(stream.get_length()) <= 0.0:
				refused.append("%s -> %s" % [str(entry["where"]), str(media["path"])])
		print("")
		print("%d linked member(s) under %s: %d resolved, %d unresolved, %d would not decode"
			% [here.size(), str(paths.root), here.size() - missing.size() - refused.size(),
				missing.size(), refused.size()])
		for line in missing.slice(0, 8):
			print("  no file: %s" % line)
		for line in refused.slice(0, 8):
			print("  no decode: %s" % line)
		h.check("every linked member's file is on the disc", missing.is_empty(),
			"%d of %d resolve to nothing" % [missing.size(), here.size()])
		h.check("and every one of them decodes to audio", refused.is_empty(),
			"%d of %d will not decode" % [refused.size(), here.size()])
	h.complete("every linked member in reach resolves to a file that decodes")

	# The property surface, which is the other half of the feature and reaches the
	# file by a different route (`media.gd:_linked_sound_facts`). A script asks `the
	# duration of member` of a linked member without ever putting it on a channel,
	# and before this it answered 0 and `the mediaReady` answered FALSE.
	h.begin("a linked member answers its own duration and rate")
	if here.is_empty():
		print("no linked member under %s to ask; nothing asserted here." % str(paths.root))
		h.check("the playback path above ran instead", sample != "",
			"and it did not, so nothing about linked members was proved at all")
	else:
		var first: Dictionary = here[0]
		var f := ContainerFile.new()
		var table := CastTable.new()
		var facts: Dictionary = {}
		if f.open(str(first["container"])) and table.open(f, paths):
			facts = MediaSurface.facts_of(null, [int(first["lib"]), int(first["number"])], table)
		h.check("%s is ready" % str(first["where"]), bool(facts.get("ready", false)),
			str(facts))
		h.check("and states a duration, a rate and a channel count",
			int(facts.get("duration", 0)) > 0 and int(facts.get("sample_rate", 0)) > 0
				and int(facts.get("channels", 0)) > 0, str(facts))
		table.close()
		f.close()
	h.complete("a linked member answers its own duration and rate")

	quit(h.finish("the linked-file fallback for a sound cast member"))


## Every sound member the cast walk can address, split by how it carries audio.
func _scan(roots: Array[String]) -> Dictionary:
	var out := {
		"members": 0, "embedded": 0, "empty_beside": 0,
		"linked": [], "both": [], "nameless": [], "missed": [], "listing": [],
	}
	var seen_casts: Dictionary = {}
	for root in roots:
		var corpus := str(root).get_file()
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		var member_paths := Paths.new()
		member_paths.root = root
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var table := CastTable.new()
			if not table.open(f, member_paths):
				table.close()
				f.close()
				continue
			for lib in table.cast_libs.keys():
				var cast = table.cast_for(int(lib))
				if cast == null:
					continue
				var key := "%s#%d" % [
					str(table.cast_libs[lib].get("resolved_path", "")),
					int(cast.cas_chunk_id)]
				if seen_casts.has(key):
					continue
				seen_casts[key] = true
				var source = table.file_for(int(lib))
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if m.is_empty() or int(m.get("type", 0)) != SOUND:
						continue
					out["members"] = int(out["members"]) + 1
					var where := "%s %s #%d '%s'" % [
						corpus, path.get_file(), number, str(m.get("name", ""))]
					if bool(m.get("sound_linked_empty", false)):
						out["empty_beside"] = int(out["empty_beside"]) + 1
					if bool(m.get("sound_linked", false)):
						var link := str(m.get("link_filename", ""))
						if link == "":
							(out["nameless"] as Array).append(where)
						else:
							(out["linked"] as Array).append({
								"where": where, "link": link, "root": root,
								"container": path, "lib": int(lib), "number": number,
							})
							(out["listing"] as Array).append(
								"%-58s linked -> %s" % [where, link])
						continue
					out["embedded"] = int(out["embedded"]) + 1
					# The other half of the same rule: a member that is *not* marked
					# linked must have samples something can decode, or the branch
					# has quietly moved the boundary in the other direction.
					var data_id := int(m.get("data_chunk_id", -1))
					# The reverted state, named so that it fails rather than counting
					# as an embedded member with an unlucky chunk id. Before the
					# fallback existed every one of these was "embedded" with nothing
					# to decode, and the census reported it as 0 failures.
					if data_id < 0 and str(m.get("link_filename", "")) != "":
						(out["missed"] as Array).append(where)
					if data_id < 0 or source == null:
						continue
					var payload: PackedByteArray = source.read_chunk(data_id)
					var header := PackedByteArray()
					var header_id := int(m.get("sound_header_chunk_id", -1))
					if header_id >= 0 and header_id != data_id:
						header = source.read_chunk(header_id)
					var stream := SoundMember.decode(payload, header, [])
					if stream == null or stream.data.size() == 0:
						continue
					if bool(m.get("sound_linked", false)):
						(out["both"] as Array).append(where)
			table.close()
			f.close()
	return out


## Any audio file under the root, as a path relative to it — the shape
## `resolve_path` takes and the shape a movie's own script builds.
func _some_audio(root: String) -> String:
	var files: Array[String] = []
	_walk_audio(root, files)
	if files.is_empty():
		return ""
	files.sort()
	return str(files[0]).trim_prefix(root).trim_prefix("/")


func _walk_audio(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var lower := str(name).to_lower()
		if lower.ends_with(".aif") or lower.ends_with(".aiff") or lower.ends_with(".wav"):
			out.append(dir_path.path_join(name))
	for sub in dir.get_directories():
		_walk_audio(dir_path.path_join(sub), out)


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
