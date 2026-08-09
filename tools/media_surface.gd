extends SceneTree
## `the currentSpriteNum`, `xtra`, and the digital-video property surface.
##
##   godot --headless --path . --script tools/media_surface.gd -- --root piposh2
##
## Three things landed together because they were the last three §19 gaps a title
## in this corpus could reach, and each is asserted here at the seam a *movie*
## reaches it through -- `get_system_prop`, `call_builtin`, `get_sprite_prop` --
## rather than against the field behind it. A setter and a getter agreeing is not
## evidence (`AGENTS.md`); what is evidence is that the answer arrives by the
## route Lingo takes.
##
## **`the currentSpriteNum` is driven through the real chain runner.** The script
## the sprite element carries is compiled here rather than taken from a
## container, which is the `tools/score_sound_check.gd` shape and for the same
## reason: no movie in this corpus both reads the property *and* leaves a value
## somewhere a harness can see. What is authored is three lines of ordinary
## Lingo, and everything under `EventChain.run` -- the queue, the pass flag, the
## save and restore -- is the engine's.
##
## The distinction that matters, and the one a naive implementation gets wrong,
## is the **tier**: Director answers a channel for a sprite behaviour and 0 for a
## cast script, a frame script and a movie script, so both are asserted rather
## than only the interesting one. A port that hung the value on the chain instead
## of the element would pass the first and fail the second.
##
## Title-agnostic: nothing here names a room, a channel or a member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const EventChain := preload("res://scenes/preview/event_chain.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Media := preload("res://scenes/preview/media.gd")

## The channel the sprite-tier element claims. Any number a score could hold; the
## point of the assertion is that the property answers *this* one and not the
## first channel that happens to have a sprite on it.
const PROBE_CHANNEL := 9

## What the probe script writes into. A global, because a global is the one piece
## of state a Lingo handler can leave behind that this harness can read back
## without reaching into the interpreter's private storage.
const PROBE_GLOBAL := "csnprobe"

const PROBE_SOURCE := """
on mouseUp
  global csnprobe
  set csnprobe = the currentSpriteNum
end
"""


func _init() -> void:
	Args.parse()
	var h := Harness.new()

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var host = preview.get("_host")
	var interpreter = preview.get("_interpreter")
	if host == null or interpreter == null:
		print("no movie loaded; nothing to assert against")
		quit(1)
		return

	_current_sprite_num(h, preview, host, interpreter)
	_xtra(h, host, interpreter)
	_video_sprite(h, host)
	_video_member(h, preview, host)

	preview.queue_free()
	quit(h.finish(
		"the currentSpriteNum through the chain runner, xtra against the registry, "
		+ "and the digital-video property surface"))


# ------------------------------------------------------------ the currentSpriteNum


func _current_sprite_num(h: Harness, preview: Node, host, interpreter) -> void:
	var name := "the currentSpriteNum answers the running behaviour's channel"
	h.begin(name)

	h.check(
		"at rest it is 0 -- no behaviour is running",
		int(host.get_system_prop("currentspritenum")) == 0,
		"a non-zero value with nothing on the stack would make every frame script "
		+ "in the movie believe it belongs to a sprite")

	var compiler = Compiler.new()
	var script: Dictionary = compiler.compile_source(PROBE_SOURCE, "csnprobe")
	if not h.check(
			"the probe script compiles",
			not script.is_empty() and not (script.get("handlers", []) as Array).is_empty(),
			str(compiler.error)):
		h.complete(name)
		return

	# The sprite tier. `EventChain.element` is the engine's own constructor, so if
	# the channel ever stops being carried on the element this stops compiling
	# rather than silently asserting nothing.
	interpreter.globals[PROBE_GLOBAL] = -1
	host.pass_event = true
	EventChain.run(preview, interpreter, "mouseUp",
		[EventChain.element("sprite", script, false, false, PROBE_CHANNEL)])
	h.check(
		"a sprite behaviour reads its own channel (%d)" % PROBE_CHANNEL,
		int(interpreter.globals.get(PROBE_GLOBAL, -1)) == PROBE_CHANNEL,
		"read %s; Piposh Dream's hex board is one behaviour attached to every "
			% str(interpreter.globals.get(PROBE_GLOBAL, -1))
			+ "tile, and this is the only thing that tells the tiles apart")

	h.check(
		"and it is 0 again once the element returns",
		int(host.get_system_prop("currentspritenum")) == 0,
		"the value is restored rather than left behind, or the next frame script "
		+ "to run would inherit the last behaviour's channel")

	# The other four tiers. Director answers 0 for every one of them, and the
	# same click can run a behaviour and a frame script back to back.
	for tier in ["cast", "frame"]:
		interpreter.globals[PROBE_GLOBAL] = -1
		host.pass_event = true
		EventChain.run(preview, interpreter, "mouseUp",
			[EventChain.element(str(tier), script, false)])
		h.check(
			"a %s script reads 0 -- it does not belong to a sprite" % tier,
			int(interpreter.globals.get(PROBE_GLOBAL, -1)) == 0,
			"read %s" % str(interpreter.globals.get(PROBE_GLOBAL, -1)))

	# Nesting, which is why the field is saved and restored rather than zeroed.
	# `sendAllSprites` from inside a behaviour is the corpus shape of this.
	interpreter.globals[PROBE_GLOBAL] = -1
	host.current_sprite_num = 4
	host.pass_event = true
	EventChain.run(preview, interpreter, "mouseUp",
		[EventChain.element("sprite", script, false, false, PROBE_CHANNEL)])
	var restored := int(host.current_sprite_num)
	host.current_sprite_num = 0
	h.check(
		"an outer behaviour's channel survives an inner one",
		restored == 4,
		"read %d after the inner element returned; a runner that zeroed the field "
			% restored + "instead of restoring it would tell the outer behaviour "
			+ "it is not on a sprite")

	h.complete(name)


# ---------------------------------------------------------------------- xtra


func _xtra(h: Harness, host, interpreter) -> void:
	var name := "xtra resolves against the registry the xtras reads"
	h.begin(name)

	var listed: Variant = host.get_system_prop("xtras")
	h.check(
		"the registry and `the xtras` are the same list",
		typeof(listed) == TYPE_ARRAY and (listed as Array).size() == host.xtras_loaded.size(),
		"two lists would let a lookup succeed for a name the movie cannot see in "
		+ "the roster, which is the disagreement the one list exists to prevent")

	var answer: Variant = host.call_builtin("xtra", ["FileIO.x32"])
	h.check(
		"a name that is not registered answers VOID",
		answer == null,
		"the registry is empty, so every lookup fails; a truthy answer would hand "
		+ "a script an object with nothing behind it")
	h.check(
		"and the host still counts as having answered",
		host.answered_builtin(),
		"otherwise the interpreter reports `xtra` as an unbound builtin as well, "
		+ "which is two complaints about one miss and neither is the useful one")

	# Director takes an index as well as a name, and the two have to agree about
	# an empty registry.
	h.check(
		"an index past the end answers VOID too",
		host.call_builtin("xtra", [1]) == null,
		"1 is the first Xtra; there is no first Xtra")

	# §7.3's normalisation, asserted on the key rather than through a lookup that
	# can only fail: the same library named three ways has to resolve once.
	h.check(
		"the platform extension and the path come off the lookup key",
		host.xtra_key("FileIO.x32") == "fileio"
			and host.xtra_key("Macintosh HD:Xtras:FileIO") == "fileio"
			and host.xtra_key("C:\\DIR\\FileIO.dll") == "fileio",
		"read %s / %s / %s" % [host.xtra_key("FileIO.x32"),
			host.xtra_key("Macintosh HD:Xtras:FileIO"), host.xtra_key("C:\\DIR\\FileIO.dll")])

	h.complete(name)


# ------------------------------------------------------- the digital-video sprite


func _video_sprite(h: Harness, host) -> void:
	var name := "the digital-video playhead round-trips through the sprite seam"
	h.begin(name)

	# Through `set_sprite_prop`/`get_sprite_prop`, which is the pair the
	# interpreter calls -- not through `media.gd` directly, because the thing
	# being asserted is that the names reach the model at all. Fourteen of them
	# were stored in the channel's override table and read back from there, which
	# is the `moveableSprite` shape and looks identical from a setter's side.
	host.set_sprite_prop(3, "volume", 128)
	h.check(
		"`the volume of sprite` reads back what was written",
		int(host.get_sprite_prop(3, "volume")) == 128,
		"read %s" % str(host.get_sprite_prop(3, "volume")))

	host.set_sprite_prop(3, "volume", 900)
	h.check(
		"and is clamped to Director's 0-255",
		int(host.get_sprite_prop(3, "volume")) == 255,
		"read %s; a port that stored the number raw would answer a volume no "
			% str(host.get_sprite_prop(3, "volume"))
			+ "mixer could have used")

	h.check(
		"a channel nothing has touched is at full volume, not silent",
		int(host.get_sprite_prop(4, "volume")) == Media.DEFAULT_VOLUME,
		"read %s; seeding a video sprite at 0 would make the default state muted"
			% str(host.get_sprite_prop(4, "volume")))

	host.set_sprite_prop(3, "movierate", 1)
	h.check(
		"`the movieRate of sprite` round-trips",
		int(host.get_sprite_prop(3, "movierate")) == 1,
		"read %s" % str(host.get_sprite_prop(3, "movierate")))

	# The in and out points bound the playhead, which is the one piece of real
	# arithmetic in the model and the part a decoder does not change.
	host.set_sprite_prop(3, "starttime", 100)
	host.set_sprite_prop(3, "stoptime", 200)
	host.set_sprite_prop(3, "movietime", 50)
	h.check(
		"`the movieTime` is held at or after `the startTime`",
		int(host.get_sprite_prop(3, "movietime")) == 100,
		"read %s" % str(host.get_sprite_prop(3, "movietime")))
	host.set_sprite_prop(3, "movietime", 5000)
	h.check(
		"and at or before `the stopTime`",
		int(host.get_sprite_prop(3, "movietime")) == 200,
		"read %s" % str(host.get_sprite_prop(3, "movietime")))
	h.check(
		"`the currentTime` is the same playhead by D6's spelling",
		int(host.get_sprite_prop(3, "currenttime"))
			== int(host.get_sprite_prop(3, "movietime")),
		"two names for one position; storing them apart would let a movie set one "
		+ "and read the other")

	# Read-only in Director, and refused rather than stored: a value a script can
	# set and cannot read back is worse than one it is refused.
	host.set_sprite_prop(3, "mostrecentcuepoint", 7)
	h.check(
		"`the mostRecentCuePoint` refuses a write",
		int(host.get_sprite_prop(3, "mostrecentcuepoint")) == 0,
		"read %s" % str(host.get_sprite_prop(3, "mostrecentcuepoint")))

	h.check(
		"`the digitalVideoTimeScale` defaults to 0 -- each member's own",
		int(host.get_system_prop("digitalvideotimescale")) == 0,
		"a non-zero default would silently rescale every movieTime in the language")
	host.set_system_prop("digitalvideotimescale", 600)
	h.check(
		"and is writable",
		int(host.get_system_prop("digitalvideotimescale")) == 600,
		"read %s" % str(host.get_system_prop("digitalvideotimescale")))
	host.set_system_prop("digitalvideotimescale", 0)

	h.complete(name)


# ------------------------------------------------------- the digital-video member


func _video_member(h: Harness, preview: Node, host) -> void:
	var name := "a member that is not time-based media is unaffected"
	h.begin(name)

	var table = preview.get("_table")
	if table == null:
		h.check("a cast is loaded", false, "nothing to read a member out of")
		h.complete(name)
		return

	# The regression this guards is the one worth guarding: `the mediaReady of
	# member` used to answer 1 for everything, and the media branch had to be
	# added *without* changing that for the bitmaps, fields and shapes this
	# corpus is made of. Every member here is one of those.
	var checked := 0
	var wrong: Array[String] = []
	for lib in table.cast_libs:
		var cast_file = table.cast_for(int(lib))
		if cast_file == null:
			continue
		for number in cast_file.member_numbers():
			var m: Dictionary = table.get_member(int(lib), int(number))
			if m.is_empty() or Media.is_media(m):
				continue
			checked += 1
			if checked > 200:
				break
			if int(host.get_member_prop(int(number), lib, "mediaready")) != 1:
				wrong.append("%d:%d %s" % [int(lib), int(number), m.get("type_name", "")])
		if checked > 200:
			break
	h.check(
		"%d ordinary members still report mediaReady TRUE" % mini(checked, 200),
		checked > 0 and wrong.is_empty(),
		("; ".join(wrong) if not wrong.is_empty() else "")
			if checked > 0 else "no member was read, so this asserted nothing")

	h.check(
		"`the duration of member` still means the transition's duration",
		not Media.is_media({"type_name": "transition"}),
		"one word asked of two things; the media branch must not swallow the "
		+ "transition arm that was there first")

	h.complete(name)
