extends SceneTree
## A point read back off a sprite equals the `point()` that was written to it --
## and the level that turns on it fires its gun.
##
##   godot --headless --path . --script tools/west_shoot.gd -- --root piposh-dream
##
##   --movie M    the level to fire in (default WEST1.dir)
##   --frame N    the frame to reach before pressing anything (default 351)
##   --ticks N    process frames to hold and to watch for (default 12)
##
## ## The engine property, which is the half that is not about this title
##
## Director has **one** point type. This port has two: the `point()` builtin
## builds a `Vector2` (`lingo_builtins.gd:_geometry`) and `the loc of sprite N`
## answers a two-element array, deliberately and with 361 sites reading it that
## way. Nothing was wrong with either choice on its own. What was missing is that
## `=` has to see through both, and `LingoValue.equal` sent anything non-numeric
## to a **string comparison of the two rendered values** -- which is right
## whenever the two happen to render the same and wrong the moment they do not.
##
## `LC::eqData` is the specification and it does not compare text: a list on
## either side goes to `LC::compareArrays`, which walks the two in step and
## recurses. §1 below asserts that shape directly -- including the two rules the
## reference states for D5 and up, that lists of different lengths are unequal
## and that a list and a scalar are unequal -- and does it on synthetic values,
## because the branch is the thing this port controls.
##
## ## The title half, which is what made anyone look
##
## `piposh-dream/WEST1.dir` is the Somi level: a western street where the player
## shoots. QA reported "bullets are not shooting, no way to kill enemies / die".
##
## The level's init parks fifteen bullet sprites off-stage --
##
##     repeat with i = 50 to 64
##       puppetSprite(i, 1)
##       set the loc of sprite i to point(690, 490)
##     end repeat
##
## -- and its `keyUpScript` finds a free one by asking which is still parked:
##
##     if the loc of sprite (49 + h) = point(690, 490) then
##       setAt(bltsprite, count(bltx) + 1, 49 + h)
##
## The left side is an array and the right is a `Vector2`. They rendered
## differently, so **no bullet was ever free**: the fire branch ran in full --
## the shot sound played, the player's member changed to the firing pose, `mnv`
## went to 6 -- and the search fell out at `"notok"` with nothing appended. Every
## visible sign of a working gun except the bullet.
##
## That is why §2 asserts a bullet **in flight** rather than a global left set
## afterwards. The game loop recycles a bullet the moment it leaves the street
## (`if not sprite(...).within(66)`), so sampling twelve frames after the press
## reads an empty list on a working engine too -- which is exactly what the first
## measurement of this bug did, and it would have called the fix a failure.
##
## ## The second defect, and why this harness did not catch it
##
## The list fix above was necessary and not sufficient, and **the first version
## of this file passed anyway**. It asserted that a bullet appeared at any point
## during the press -- "peak >= 1" -- which is true of a bullet that exists for
## exactly one frame and is then destroyed, and that is precisely what was still
## happening. The owner played the build and reported no bullets; the harness was
## green. That is the failure `porting-fidelity-verification` names: an assertion
## that passes without proving the thing anyone cares about.
##
## The second defect is that **Director spells `within` two ways and this port
## answered them differently**. `sprite a within b` is an operator and reaches
## `_binary`; `sprite(a).within(b)` is D5 dot notation that compiles to `objcall`
## and, in this interpreter, fell through to a *property read* of a property no
## sprite has -- answering 0 with the argument never evaluated. WEST1's loop
## recycles with the method spelling, so every bullet was destroyed on the frame
## after it was fired.
##
## So §2 now asserts that the bullet **travels**: that it is still alive several
## frames later and that its position has changed. A one-frame bullet fails that,
## and the previous engine fails it. §1 asserts the two spellings agree, which is
## the engine property underneath and is what a future reader should keep.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const LingoValue := preload("res://lingo/lingo_value.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

## The channels the level parks, and where. Read from the movie's own init in
## `1:140`; spelled here so the check has something to be wrong about.
const BULLET_FIRST := 50
const BULLET_LAST := 64
const PARKED := Vector2(690, 490)

## `the keyCode` for space on the Mac, which is what the level tests for. The
## arrow first, because the fire branch also requires `getAt(mnv, 1) = 1` and
## only an arrow's key-up sets it.
const FIRE_KEY := KEY_SPACE
const AIM_KEY := KEY_RIGHT


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	_equality_case(h)

	var preview: Node = (load("res://scenes/director_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	for i in 8:
		await process_frame

	var movie: String = Args.text(args, "movie")
	if movie == "":
		movie = "WEST1.dir"
	var want := int(Args.number(args, "frame", 351))
	var ticks := int(Args.number(args, "ticks", 12))
	preview.call("lingo_go_movie", movie, null)
	var waited := 0
	while waited < 2400 and int(preview.call("current_frame")) < want:
		await process_frame
		waited += 1
	h.begin("the level stands up")
	h.check("the level reached its game frame",
		int(preview.call("current_frame")) >= want,
		"stopped at %d of %d after %d ticks"
			% [int(preview.call("current_frame")), want, waited])
	var interp = preview.get("_interpreter")
	var ppl: Variant = interp.globals.get("ppl", null)
	h.check("its init has run", ppl is Array and (ppl as Array).size() > 0,
		"ppl = %s" % str(ppl))
	if not (ppl is Array and (ppl as Array).size() > 0):
		h.complete("the level stands up")
		quit(h.finish("a point written to a sprite reads back equal"))
		return

	# The fixture the search depends on, asserted before the search is.
	var parked := 0
	for ch in range(BULLET_FIRST, BULLET_LAST + 1):
		if LingoValue.equal(preview.call("lingo_sprite_prop", ch, "loc"), PARKED):
			parked += 1
	h.check("every bullet sprite is parked where the init put it",
		parked == BULLET_LAST - BULLET_FIRST + 1,
		"%d of %d read equal to %s"
			% [parked, BULLET_LAST - BULLET_FIRST + 1, str(PARKED)])
	h.complete("the level stands up")

	h.begin("the gun puts a bullet in the street")
	var idle_peak := await _press(preview, interp, AIM_KEY, ticks)
	# The control that keeps the checks below from passing against an engine that
	# put a bullet in flight on every tick regardless of the key.
	h.check("aiming alone puts no bullet in flight", idle_peak == 0,
		"an arrow press produced %d" % idle_peak)
	var born := await _press(preview, interp, FIRE_KEY, ticks)
	h.check("firing puts a bullet in flight", born > 0,
		"the press produced %d" % born)

	# **Where it travels, not merely that it appeared.** A bullet destroyed on
	# the frame after it was fired satisfies "one appeared", and that was the
	# state this file called green while the level was unplayable.
	var track := PackedStringArray()
	var moved := false
	var alive := 0
	var first := Vector2.INF
	for i in ticks * 2:
		await process_frame
		var live: Variant = interp.globals.get("bltsprite", null)
		if not (live is Array) or (live as Array).is_empty():
			continue
		alive += 1
		var ch := int((live as Array)[0])
		var at: Vector2 = preview.call("lingo_sprite_rect", ch).position
		if first == Vector2.INF:
			first = at
		elif not at.is_equal_approx(first):
			moved = true
		if track.size() < 6:
			track.append(str(at))
	h.check("the bullet is still there several frames later", alive >= ticks,
		"alive on %d of %d frames" % [alive, ticks * 2])
	h.check("and it has moved", moved, "positions seen: %s" % ", ".join(track))
	h.complete("the gun puts a bullet in the street")

	_spelling_case(h, preview)

	quit(h.finish("a point written to a sprite reads back equal"))


## Press and release one key, and report the most bullets that were in flight at
## any point while it was held or settling.
##
## The peak rather than the final count, for the reason in the file comment: a
## bullet is recycled the moment it leaves the street, so the list is empty again
## within a dozen frames on a working engine.
func _press(preview: Node, interp, code: Key, ticks: int) -> int:
	var peak := 0
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	preview.call("_dispatch_key", down)
	for i in ticks:
		await process_frame
		peak = maxi(peak, _in_flight(interp))
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	preview.call("_dispatch_key_up", up)
	for i in ticks:
		await process_frame
		peak = maxi(peak, _in_flight(interp))
	return peak


func _in_flight(interp) -> int:
	var live: Variant = interp.globals.get("bltsprite", null)
	return (live as Array).size() if live is Array else 0


## `LC::eqData`'s shape, on values built here.
##
## Synthetic rather than read off a movie, because what is being asserted is the
## branch this port owns. A corpus check would only say that one title's two
## spellings happen to agree today.
func _equality_case(h: Harness) -> void:
	h.begin("`=` compares a list element by element")
	h.check("a point equals the same point",
		LingoValue.equal(Vector2(690, 490), Vector2(690, 490)))
	# The pair that was broken: the two spellings of one Director point.
	h.check("a point equals the array spelling of itself",
		LingoValue.equal([690, 490], Vector2(690, 490)))
	h.check("and in the other order",
		LingoValue.equal(Vector2(690, 490), [690, 490]))
	h.check("an int element equals a float element",
		LingoValue.equal([690, 490], [690.0, 490.0]))
	h.check("a differing element makes them unequal",
		not LingoValue.equal([690, 490], [690, 491]))
	# The two rules the reference states for D5 and up.
	h.check("lists of different lengths are unequal",
		not LingoValue.equal([1, 2], [1, 2, 3]))
	h.check("a list and a scalar are unequal",
		not LingoValue.equal([1, 2], 1))
	h.check("and an empty list is still a list",
		LingoValue.equal([], []) and not LingoValue.equal([], 0))
	# Nesting, which a string comparison also gets right and is here so that the
	# recursion is covered rather than assumed.
	h.check("nesting compares through",
		LingoValue.equal([[1, 2], [3, 4]], [[1, 2], [3, 4]])
		and not LingoValue.equal([[1, 2], [3, 4]], [[1, 2], [3, 5]]))
	# Unchanged behaviour, asserted so that adding the list arm cannot have
	# quietly moved the scalar one.
	h.check("strings still compare without regard to case",
		LingoValue.equal("OK", "ok") and not LingoValue.equal("ok", "notok"))
	h.check("numbers still compare as numbers",
		LingoValue.equal(3, "3") and LingoValue.equal(3, 3.0))
	h.complete("`=` compares a list element by element")


## The operator and the method spelling of one test answer the same thing.
##
## Compiled and run here rather than read off the corpus, because the two
## spellings only diverge inside the interpreter and a corpus check would say
## only that one title happens to use the one that works. Both channels are the
## level's own, so the answer is a real geometric fact rather than a tautology:
## channel 50 is a bullet parked inside channel 66, the street.
func _spelling_case(h: Harness, preview: Node) -> void:
	h.begin("both spellings of a collision test agree")
	var c := Compiler.new()
	var ast: Dictionary = c.compile_source(
		"on probespelling
"
		+ "  global wop, wmeth, iop, imeth
"
		+ "  set the loc of sprite 50 to point(360, 200)
"
		+ "  wop = 0
  if sprite 50 within 66 then
    wop = 1
  end if
"
		+ "  wmeth = 0
  if sprite(50).within(66) then
    wmeth = 1
  end if
"
		+ "  iop = 0
  if sprite 50 intersects 66 then
    iop = 1
  end if
"
		+ "  imeth = 0
  if sprite(50).intersects(66) then
    imeth = 1
  end if
"
		+ "end
", "MovieScript 9100")
	if ast.is_empty():
		h.check("the probe compiles", false, c.error)
		h.complete("both spellings of a collision test agree")
		return
	var interp = preview.get("_interpreter")
	interp.load_bundle({"movie": "WESTSHOOT", "cast": "harness",
		"scripts": {"MovieScript 9100": ast}}, "WESTSHOOT")
	interp.call_handler("probespelling", [])
	var wop := int(LingoValue.to_int(interp.globals.get("wop", 0)))
	var wmeth := int(LingoValue.to_int(interp.globals.get("wmeth", 0)))
	var iop := int(LingoValue.to_int(interp.globals.get("iop", 0)))
	var imeth := int(LingoValue.to_int(interp.globals.get("imeth", 0)))
	# Asserted true rather than merely equal: two spellings that both answer 0
	# agree and prove nothing, and 0 is what the broken engine answered.
	h.check("`sprite a within b` is true for a bullet inside the street",
		wop == 1, "answered %d" % wop)
	h.check("and `sprite(a).within(b)` agrees", wmeth == wop,
		"operator %d, method %d" % [wop, wmeth])
	h.check("`sprite a intersects b` is true", iop == 1, "answered %d" % iop)
	h.check("and `sprite(a).intersects(b)` agrees", imeth == iop,
		"operator %d, method %d" % [iop, imeth])
	h.complete("both spellings of a collision test agree")
