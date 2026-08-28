extends SceneTree
## Does `director_score.writes_between` name every channel the score actually
## rewrote between two frames?
##
##   godot --headless --script tools/score_write_mask.gd
##   godot --headless --script tools/score_write_mask.gd -- --root rating
##   godot --headless --script tools/score_write_mask.gd -- --root rating --file NAVIGATE.dir
##   godot --headless --script tools/score_write_mask.gd -- --all
##
##   --root R      the corpus (default the config's)
##   --file F      one container of it
##   --all         every root under `games/`, one process
##   --frames N    frames per container (default 400, from frame 0)
##   --verbose     print every container, not only the ones with findings
##
## ## The invariant
##
## `writes_between(n - 1, n)` is the port's copy-back mask -- the reference's
## `Sprite::_copyBackMask`, the set of fields frame `n`'s own delta touched, and
## the only thing `sprite_state.release_auto_puppets` consults when deciding
## whether the score has taken a script's value back (`score.cpp:514`). It is
## derived from the *delta stream*; `frame(n)` is derived from the *accumulated
## buffer*. Two readings of one file, and they must agree in one direction:
##
##   **every channel whose decoded record differs between frame n-1 and frame n
##   must appear in `writes_between(n - 1, n)`.**
##
## Only that direction. The mask is deliberately allowed to name a channel the
## score rewrote with the value it already had -- that is the whole reason it is
## read off the delta rather than off a value comparison (`bugs.md` 47, and
## `writes_between`'s own header). A record that *changed* with nothing written is
## the impossible half, and it is the half that was true.
##
## ## What it was written for
##
## `_writes_into` mapped a delta chunk's byte range onto channels against
## `SPRITE_RECORD_SIZE * CHANNEL_BIAS`, one 48-byte record below channel 1's real
## base (`MAIN_CHANNEL_SIZE`, and the reference's `kMainChannelSizeD7` in
## `frame.cpp:readChannelD7`). It therefore named channel N+1 for a chunk writing
## channel N -- and because it then intersects the chunk with each field's extent
## *within that channel's record*, a chunk lying inside a single record matched no
## field at all and the frame reported **nothing**. Director writes sub-ranges far
## more often than whole records: `rating/NAVIGATE.dir` frame 3 rewrites bytes
## 0-7 and 10-19 of nineteen channels in 34 chunks -- `sprite_type`, `ink`, both
## colours, `cast_lib` and `cast_id` -- and `writes_between(2, 3)` answered `{}`.
##
## The player-visible consequence is an auto-puppet that is never handed back. A
## harness that only asserted "the mask is a subset of what changed" would have
## passed throughout, which is why the assertion runs the other way.
const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")

## The record fields a change is judged on: everything `_snapshot` decodes that
## `FIELD_BYTES` also claims a byte range for, so a mismatch is always a
## statement about the mask and never about a field one side does not carry.
const WATCHED := ["cast_lib", "cast_id", "loc_h", "loc_v", "width", "height",
	"ink", "fore_color", "back_color", "sprite_type"]


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var paths := Paths.new()
	paths.load_config()
	var roots: Array = []
	if args.has("all"):
		var d := DirAccess.open("res://games")
		if d != null:
			d.list_dir_begin()
			var name := d.get_next()
			while name != "":
				if d.current_is_dir() and not name.begins_with("."):
					roots.append(name)
				name = d.get_next()
			d.list_dir_end()
		roots.sort()
	else:
		roots.append(Args.text(args, "root", paths.root).get_file())
	var only := Args.text(args, "file", "")
	var frames := int(Args.number(args, "frames", 400))
	var verbose := args.has("verbose")

	for root in roots:
		var case := "%s: every changed channel is in the copy-back mask" % root
		h.begin(case)
		var files := PackedStringArray()
		_collect("res://games/%s" % root, files)
		var containers := 0
		var checked := 0
		var missed: Array = []
		for path in files:
			if only != "" and not str(path).to_lower().contains(only.to_lower()):
				continue
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var score := Score.new()
			var payload := _payload(f, "VWSC")
			if payload.is_empty() or not score.parse(payload, 0):
				continue
			containers += 1
			var report := _walk(score, mini(frames, score.frame_count))
			checked += int(report["frames"])
			if not (report["missed"] as Array).is_empty():
				missed.append("%s %s" % [
					str(path).get_file(), str((report["missed"] as Array).slice(0, 4))])
			elif verbose:
				print("   ok %s (%d frames)" % [str(path).get_file(), int(report["frames"])])
		# A root with no readable score asserts nothing, and says so rather than
		# passing quietly -- `test-games/` is gitignored and a clean checkout has
		# containers this cannot open.
		if not h.check("%s: %d container(s) read, %d frame step(s) compared"
				% [root, containers, checked], containers > 0 and checked > 0):
			continue
		h.check("%s: no frame changes a channel the mask does not name" % root,
			missed.is_empty(), "; ".join(PackedStringArray(missed.slice(0, 6))))
		h.complete(case)
	quit(h.finish("writes_between covers every record the score rewrites"))


## One container: for each frame step, which channels changed and which the mask
## named.
func _walk(score, frames: int) -> Dictionary:
	var missed: Array = []
	var steps := 0
	var before: Dictionary = _records(score, 0)
	for i in range(1, frames):
		var after: Dictionary = _records(score, i)
		var mask: Dictionary = score.writes_between(i - 1, i)
		steps += 1
		for ch in after:
			if before.get(ch, null) != after[ch] and not mask.has(ch):
				missed.append("f%d ch%d" % [i, ch])
		for ch in before:
			if not after.has(ch) and not mask.has(ch):
				missed.append("f%d ch%d gone" % [i, ch])
		before = after
		if missed.size() > 8:
			break
	return {"missed": missed, "frames": steps}


## Frame N's sprite records, reduced to the watched fields, keyed by channel.
func _records(score, index: int) -> Dictionary:
	var out: Dictionary = {}
	for value in (score.frame(index).get("sprites", []) as Array):
		var sprite: Dictionary = value
		var key: Array = []
		for field in WATCHED:
			key.append(sprite.get(field, null))
		out[int(sprite["channel"])] = key
	return out


static func _payload(f, tag: String) -> PackedByteArray:
	for id in f.ids_of(tag):
		var bytes: PackedByteArray = f.read_chunk(int(id))
		if not bytes.is_empty():
			return bytes
	return PackedByteArray()


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := "%s/%s" % [dir, name]
		if d.current_is_dir():
			_collect(full, out)
		elif name.to_lower().ends_with(".dir") or name.to_lower().ends_with(".dxr"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
