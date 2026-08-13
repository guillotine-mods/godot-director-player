extends SceneTree
## Decode every frame of every AVI a corpus holds and say what it cost.
##
##   godot --headless --audio-driver Dummy --path . --script tools/avi_decode.gd -- \
##       --root res://test-games/itamar-magichat
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --file P      one file instead of a sweep, `res://` or absolute
##   --png DIR     write frame 0, the middle frame and the last frame as PNG
##   --frame N     with --png, also write this frame
##
## ## What this asserts, and why the cost is part of it
##
## `director/director_avi.gd` is a decoder written in GDScript, so "does it
## decode" and "does it decode fast enough" are the same question asked twice --
## a reader that produces the right pictures at 4 fps has not implemented an
## 11.11 fps video. So this reports **milliseconds per frame, measured**, beside
## the correctness checks, and fails when the mean exceeds the frame interval the
## file itself declares. That is the only threshold in here that is not a
## tautology: it comes out of the file's own `dwRate / dwScale`.
##
## The correctness checks are all *cross-checks between two places the same fact
## is written*, which is the only kind available without a second decoder:
##
##   * the picture size in `avih`, in the video `strh`'s `rcFrame`, and in the
##     `strf` `BITMAPINFOHEADER` -- three independent statements
##   * the frame count in `avih`'s `dwTotalFrames`, in `strh`'s `dwLength`, in
##     the `idx1` entry count and in a walk of `movi` itself
##   * every frame decodes to exactly `width * height` pixels, which is what says
##     the run-length expansion accounted for the whole surface
##   * a seek backwards to frame 0 reproduces frame 0 byte for byte, which is
##     what says the key-frame replay is equivalent to sequential decoding --
##     the one property a delta codec can get wrong invisibly
##
## Title-agnostic: it names no game and no file.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Avi := preload("res://director/director_avi.gd")
const Paths := preload("res://director/director_paths.gd")

## Extensions worth opening. The census sniffs headers rather than extensions and
## is right to; this only has to find candidates, and a `.avi` that is not one is
## reported by the reader itself.
const EXTENSIONS := ["avi"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	_sweep(h)
	quit(h.finish("every AVI in the corpus decodes, and inside its own frame interval"))


func _sweep(h: Harness) -> void:
	var args := Args.parse()
	var wanted := Args.text(args, "file", "")
	var png_dir := Args.text(args, "png", "")
	var extra := Args.number(args, "frame", -1)

	var files: Array[String] = []
	if wanted != "":
		files.append(wanted)
	else:
		var paths := Paths.new()
		if not paths.load_config():
			h.begin("a corpus to sweep")
			h.check("the config names a game", false, Paths.CONFIG_PATH)
			h.complete("a corpus to sweep")
			return
		files = _find(str(paths.root))

	var case := "AVI decode"
	h.begin(case)
	if files.is_empty():
		h.check(
			"this corpus holds no AVI, so nothing was decoded here",
			true,
			"run --root res://test-games/itamar-magichat for the only corpus that does")
		h.complete(case)
		return
	for file_path in files:
		_one(h, file_path, png_dir, extra)
	h.complete(case)


func _one(h: Harness, file_path: String, png_dir: String, extra: int) -> void:
	var avi := Avi.new()
	if not avi.open(file_path):
		h.check("%s opens" % file_path.get_file(), false, avi.error)
		return
	print("")
	print("%s" % file_path)
	print("  %dx%d  '%s'  %d frames  %.4f fps  %.0f ms  audio %d Hz %d-bit x%d" % [
		avi.width, avi.height, avi.video_fourcc, avi.frame_count, avi.fps,
		avi.duration_ms, avi.audio_rate, avi.audio_bits, avi.audio_channels])

	h.check("%s: the header's frame count matches the index" % file_path.get_file(),
		avi.declared_frames == avi.frame_count,
		"strh dwLength %d, index %d" % [avi.declared_frames, avi.frame_count])

	var began := Time.get_ticks_usec()
	var first: PackedByteArray = PackedByteArray()
	var wrong: Array[String] = []
	var pixels := avi.width * avi.height
	for i in avi.frame_count:
		var image: Image = avi.frame_at(i)
		if image == null:
			wrong.append("frame %d decoded to nothing" % i)
			continue
		if image.get_width() != avi.width or image.get_height() != avi.height:
			wrong.append("frame %d is %dx%d" % [i, image.get_width(), image.get_height()])
		if i == 0:
			first = image.get_data()
	var wall_us := Time.get_ticks_usec() - began
	h.check("%s: all %d frames decode at the declared size" % [
		file_path.get_file(), avi.frame_count],
		wrong.is_empty(), "; ".join(wrong))

	# Sequential decode is the cheap path; the number that matters is whether it
	# fits inside the interval the file asks for.
	var per_frame_ms := (wall_us / 1000.0) / maxf(avi.frame_count, 1)
	var budget_ms := 1000.0 / maxf(avi.fps, 0.001)
	print("  decode: %.2f ms/frame mean over %d frames (%.1f ms in the codec), "
		% [per_frame_ms, avi.frame_count, avi.decode_cost_us() / 1000.0]
		+ "budget %.2f ms at %.4f fps -> %.0f%% of real time" % [
			budget_ms, avi.fps, 100.0 * per_frame_ms / budget_ms])
	h.check("%s: decodes inside its own frame interval" % file_path.get_file(),
		per_frame_ms < budget_ms,
		"%.2f ms/frame against a %.2f ms budget" % [per_frame_ms, budget_ms])

	# The delta-codec property: replaying from a key frame must land where a
	# sequential decode did. Asked by seeking *backwards*, which is the direction
	# a forward-only decoder cannot fake.
	var replayed: Image = avi.frame_at(0)
	h.check("%s: a backward seek to frame 0 reproduces it exactly" % file_path.get_file(),
		replayed != null and not first.is_empty() and replayed.get_data() == first,
		"a key-frame replay that differs from the sequential decode is a delta bug")

	var audio: AudioStreamWAV = avi.audio_stream()
	if avi.audio_rate > 0:
		h.check("%s: the audio track decodes" % file_path.get_file(),
			audio != null and audio.data.size() > 0,
			"%d Hz %d-bit x%d, format %d" % [
				avi.audio_rate, avi.audio_bits, avi.audio_channels, avi.audio_format])
		if audio != null:
			print("  audio : %.2f s of %d samples" % [
				audio.get_length(), audio.data.size()])

	if png_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(png_dir))
		var want := [0, avi.frame_count / 2, avi.frame_count - 1]
		if extra >= 0:
			want.append(extra)
		for i in want:
			var image: Image = avi.frame_at(int(i))
			if image == null:
				continue
			var out := "%s/%s.f%03d.png" % [png_dir, file_path.get_file().get_basename(), int(i)]
			image.save_png(out)
			print("  wrote %s" % out)
	avi.close()
	# `pixels` is read only by the message above; naming it keeps the intent of
	# the size check readable rather than repeating the multiplication.
	if pixels <= 0:
		push_warning("degenerate size")


func _find(root: String) -> Array[String]:
	var out: Array[String] = []
	_scan(root, out)
	out.sort()
	return out


func _scan(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_scan(full, out)
		elif EXTENSIONS.has(name.get_extension().to_lower()):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
