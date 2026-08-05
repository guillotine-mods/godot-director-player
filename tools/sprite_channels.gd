extends SceneTree
## Do interpreted sprite property writes reach the stage?
##
## Before the channel array existed, `LingoHost.set_sprite_prop()` wrote into a
## dictionary nothing outside that file read, so 1548 of the corpus's 1954 sprite
## writes had no effect: `memberNum` 624, `locV` 397, `locH` 347, `cursor` 155.
## Only `visible` reached the stage, forwarded separately.
##
## These checks assert the contract directly rather than measuring agreement with
## the lifted export, because the export has no opinion about a property write.
##
##   godot --headless --script tools/sprite_channels.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _ok(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("ok    %s%s" % [name, "  (%s)" % detail if detail != "" else ""])
	else:
		failed += 1
		print("FAIL  %s%s" % [name, "  (%s)" % detail if detail != "" else ""])


func _run() -> void:
	# The host is built by DirectorRuntime.boot() when a Lingo flag is on. Building
	# one directly here compiles lingo_host.gd outside the autoload context and its
	# GameState reference fails to resolve.
	var settings: Node = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK or not runtime.goto_movie("DAY1", null, {"label": "shore2"}):
		print("could not reach DAY1 @shore2")
		quit(1)
		return
	var host: Object = runtime.lingo.host

	# A channel the score actually fills, so there is something to move.
	var subject := -1
	for sprite in runtime.channel_sprites():
		var channel := int(sprite.get("channel", 0))
		if channel > 0 and channel != 30 and int(sprite.get("cast_id", 0)) > 0:
			subject = channel
			break
	if subject < 0:
		print("no scored channel to test against")
		quit(1)
		return

	var before: Dictionary = runtime.effective_sprite(subject).duplicate(true)
	_ok("the score fills a channel", not before.is_empty(), "ch%d member %s" % [
		subject, str(before.get("cast_id", "?"))])

	# --- writes are readable back through the same property
	host.set_sprite_prop(subject, "locH", 111)
	host.set_sprite_prop(subject, "locV", 222)
	_ok("locH write reads back", int(host.get_sprite_prop(subject, "locH")) == 111,
		"got %s" % str(host.get_sprite_prop(subject, "locH")))
	_ok("locV write reads back", int(host.get_sprite_prop(subject, "locV")) == 222,
		"got %s" % str(host.get_sprite_prop(subject, "locV")))

	# --- the write reaches what the renderer and hit-testing read
	var drawn: Dictionary = runtime.effective_sprite(subject)
	_ok("the channel the renderer draws moved",
		int(drawn.get("loc_h", -1)) == 111 and int(drawn.get("loc_v", -1)) == 222)
	var rect: Rect2 = host.sprite_rect(subject)
	_ok("intersects/rollOver measure the new position",
		rect.has_point(Vector2(111, 222)),
		"rect %s" % str(rect))
	var moved := false
	for sprite in runtime.channel_sprites():
		if int(sprite.get("channel", 0)) == subject and int(sprite.get("loc_h", -1)) == 111:
			moved = true
	_ok("channel_sprites() carries the write", moved)

	# --- the bounding box moves rigidly, keeping the member's own reg offset
	var offset_before := Vector2(
		float(before.get("x", 0)) - float(before.get("loc_h", 0)),
		float(before.get("y", 0)) - float(before.get("loc_v", 0)))
	var offset_after := Vector2(
		float(drawn.get("x", 0)) - float(drawn.get("loc_h", 0)),
		float(drawn.get("y", 0)) - float(drawn.get("loc_v", 0)))
	_ok("the registration offset survives a move", offset_before.is_equal_approx(offset_after),
		"%s then %s" % [str(offset_before), str(offset_after)])

	# --- memberNum
	host.set_sprite_prop(subject, "memberNum", 29)
	_ok("memberNum write reads back",
		int(host.get_sprite_prop(subject, "memberNum")) == 29,
		"got %s" % str(host.get_sprite_prop(subject, "memberNum")))
	_ok("memberNum write reaches the renderer",
		int(runtime.effective_sprite(subject).get("cast_id", -1)) == 29)

	# --- reconcile: the score takes an unpuppeted channel back
	runtime.reconcile_channels(runtime.loader.get_frame(runtime.frame_index))
	_ok("the score reclaims an unpuppeted channel",
		int(runtime.effective_sprite(subject).get("cast_id", -1)) == int(before.get("cast_id", -1)),
		"member %s" % str(runtime.effective_sprite(subject).get("cast_id", "?")))

	# --- reconcile: a puppeted channel keeps what the script wrote
	host.call_builtin("puppetSprite", [subject, 1])
	host.set_sprite_prop(subject, "locH", 333)
	runtime.reconcile_channels(runtime.loader.get_frame(runtime.frame_index))
	_ok("a puppeted channel survives reconcile",
		int(runtime.effective_sprite(subject).get("loc_h", -1)) == 333,
		"locH %s" % str(runtime.effective_sprite(subject).get("loc_h", "?")))

	host.call_builtin("puppetSprite", [subject, 0])
	runtime.reconcile_channels(runtime.loader.get_frame(runtime.frame_index))
	_ok("puppetSprite N, 0 hands the channel back",
		int(runtime.effective_sprite(subject).get("loc_h", -1))
			== int(before.get("loc_h", -1)))

	# --- reading a channel must not conjure a sprite onto the stage
	var count_before: int = runtime.channel_sprites().size()
	host.get_sprite_prop(147, "visible")
	host.get_sprite_prop(148, "memberNum")
	_ok("reading an empty channel draws nothing",
		runtime.channel_sprites().size() == count_before,
		"%d then %d" % [count_before, runtime.channel_sprites().size()])

	# --- a movie change resets channel ownership (bugs.md 3)
	host.call_builtin("puppetSprite", [subject, 1])
	runtime.set_channel_visible(subject, false)
	runtime.goto_movie("SEA1")
	var carried: Variant = runtime.channels.get(subject, null)
	_ok("a movie change clears puppet ownership and hides",
		carried == null or (not carried.puppet and carried.visible))

	print("\n%d checks failed" % failed)
	quit(1 if failed > 0 else 0)
