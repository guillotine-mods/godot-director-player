extends SceneTree
## Does a sprite draw at its member's size unless the score says stretch?
##
## Director draws a sprite's member at the member's own size, anchored on the
## member's registration point. The width and height the score stores are the drawn
## rect only when the sprite's stretch flag is set. The upstream exporter masks that
## flag out of the ink byte and writes the stored rect regardless, so the port scaled
## 22,806 sprite records into a rect the original ignores (bugs.md 14).
##
## The checks are on the drawn rect, which is also what hit-testing uses, not on the
## flag round-tripping through a getter.
##
## The named cases — ALLIN, its stale channel 19, CHESS and NIGHT1 — are what carry
## the correctness claim. The corpus check at the end re-runs the resolver's own
## predicate, so it guards the pipeline (the flag file present, loaded, and applied
## before anything reads a frame) rather than the semantics, and it cannot tell you
## the rects are right.
##
##   godot --headless --script tools/sprite_stretch.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _ok(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("ok    %s%s" % [name, "  (%s)" % detail if detail != "" else ""])
	else:
		failed += 1
		print("FAIL  %s%s" % [name, "  (%s)" % detail if detail != "" else ""])


func _rect_of(loader: RenderModelLoader, frame_index: int, channel: int) -> Rect2:
	var frame: Dictionary = loader.get_frame(frame_index)
	var sprites: Variant = frame.get("sprites", [])
	if typeof(sprites) != TYPE_ARRAY:
		return Rect2()
	for sprite_value in sprites as Array:
		var sprite: Dictionary = sprite_value
		if int(sprite.get("channel", 0)) == channel:
			return Rect2(
				float(sprite.get("x", 0)),
				float(sprite.get("y", 0)),
				float(sprite.get("width", 0)),
				float(sprite.get("height", 0)),
			)
	return Rect2()


func _run() -> void:
	var loader := RenderModelLoader.new()
	if loader.load_index() != OK:
		print("could not load the render model index")
		quit(1)
		return
	_ok("the recovered stretch flags load", not loader.sprite_stretch.is_empty(),
		"%d movies" % loader.sprite_stretch.size())

	# --- ALLIN: one member, one registration point, three stored widths.
	# Channel 1 is a whole hotel room. The score stores 1280 on 835 frames, 640 on
	# 259 and 639 on 337, with the member 640 wide throughout, so before the flags
	# were read the backdrop popped between the room and its right half at double
	# size as the playhead stepped.
	if loader.load_movie("ALLIN") != OK:
		print("could not load ALLIN")
		quit(1)
		return
	_ok("ALLIN's flags were recovered", loader.stretch_flags_known)
	var want := Rect2(0, -12, 640, 441)
	for frame_index in [0, 321, 718]:
		var rect := _rect_of(loader, frame_index, 1)
		_ok("ALLIN frame %d draws the whole room" % frame_index, rect == want,
			"%s wanted %s" % [str(rect), str(want)])

	# A channel whose stored rect is a previous member's size: 1:82 is 97x271 and the
	# score still holds 222x283, which is member 1:42's natural size exactly.
	var stale := _rect_of(loader, 979, 19)
	_ok("a stale channel rect follows the member", stale == Rect2(419, 158, 97, 271),
		"%s" % str(stale))

	# --- hit-testing follows the drawn rect, not the residue.
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK or not runtime.goto_movie("ALLIN", 0):
		print("could not enter ALLIN")
		quit(1)
		return
	var hit: Rect2 = runtime.sprite_stage_rect(runtime.effective_sprite(1))
	_ok("the room's hotspot is the room", is_equal_approx(hit.size.x, 640.0), str(hit))
	_ok("a point off the room is not in it", not hit.has_point(Vector2(900, 200)))

	# --- a sprite the score does mark as stretched keeps the author's rect.
	if loader.load_movie("CHESS") == OK:
		var chess := _rect_of(loader, 146, 5)
		_ok("CHESS keeps its stretched sprite", chess.size == Vector2(117, 26), str(chess))
	if loader.load_movie("NIGHT1") == OK:
		var night := _rect_of(loader, 2472, 5)
		_ok("NIGHT1 keeps its stretched sprite", night.size == Vector2(6, 265), str(night))

	# --- corpus: no unstretched sprite is left scaled, in any movie with flags.
	var known := 0
	var unknown: Array = []
	var resolved := 0
	var loops := 0
	var violations := 0
	var examples: Array = []
	for movie in loader.available_movies():
		if loader.load_movie(movie) != OK:
			continue
		if not loader.stretch_flags_known:
			unknown.append(movie)
			continue
		known += 1
		resolved += loader.resolved_sprite_rects
		loops += loader.skipped_film_loop_rects
		for frame_index in loader.frames.size():
			var sprites: Variant = loader.get_frame(frame_index).get("sprites", [])
			if typeof(sprites) != TYPE_ARRAY:
				continue
			for sprite_value in sprites as Array:
				var sprite: Dictionary = sprite_value
				if bool(sprite.get("stretch", false)):
					continue
				var cast_lib := int(sprite.get("cast_lib", 1))
				var cast_id := int(sprite.get("cast_id", 0))
				if not loader.get_film_loop(cast_lib, cast_id).is_empty():
					continue
				var member := loader.member_if_known(cast_lib, cast_id)
				var width := float(member.get("width", 0.0))
				var height := float(member.get("height", 0.0))
				if width <= 0.0 or height <= 0.0:
					continue
				if (
					not is_equal_approx(float(sprite.get("width", 0.0)), width)
					or not is_equal_approx(float(sprite.get("height", 0.0)), height)
				):
					violations += 1
					if examples.size() < 8:
						examples.append("%s frame %d ch %d: %sx%s for a %dx%d member" % [
							movie, frame_index, int(sprite.get("channel", 0)),
							str(sprite.get("width")), str(sprite.get("height")),
							int(width), int(height)])
	print("\n%d movies carry flags, %d rects resolved, %d film-loop sprites left alone"
		% [known, resolved, loops])
	print("%d movies have no recovered flags and keep the exported rects: %s"
		% [unknown.size(), ", ".join(unknown)])
	_ok("no unstretched sprite is left scaled", violations == 0,
		"%d, first: %s" % [violations, ", ".join(examples)])

	print("\n%d checks failed" % failed)
	quit(1 if failed > 0 else 0)
