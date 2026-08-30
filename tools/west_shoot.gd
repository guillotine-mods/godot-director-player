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

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const LingoValue := preload("res://lingo/lingo_value.gd")

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
	var fired := 0
	var idle_peak := 0
	for round in 2:
		# The aim key, whose key-up sets the flag the fire branch requires.
		idle_peak = maxi(idle_peak, await _press(preview, interp, AIM_KEY, ticks))
		fired += 1 if await _press(preview, interp, FIRE_KEY, ticks) > 0 else 0
	h.check("firing puts a bullet in flight", fired == 2,
		"%d of 2 presses produced one" % fired)
	# The control that keeps the check from passing against an engine that put a
	# bullet in flight on every tick regardless.
	h.check("and aiming alone does not", idle_peak == 0,
		"an arrow press produced %d" % idle_peak)
	h.complete("the gun puts a bullet in the street")

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
