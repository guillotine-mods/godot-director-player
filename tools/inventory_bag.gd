extends SceneTree
## An auto-puppeted member a movie never writes back is handed back by the score.
##
##   godot --headless --script tools/inventory_bag.gd -- --root rating
##
##   --root R       the corpus (default the config's)
##   --do SPEC      how to play into the room (default: Rating's menu, then the
##                  arrival scene, which needs Return)
##   --steps N      process frames the queue may take (default 2400)
##   --cycles N     open/close cycles to drive (default 4)
##   --gap N        process frames between a close and the next click (default 200)
##
## Runs headless, which `gate.sh` requires. Nothing here needs a window: the bag
## is read through `lingo_sprite_prop` and clicked through `route_click`.
##
## ## What it guards, and why `puzzle_board.gd` does not guard it
##
## `docs/bugs-closed.md` 133. `rating`'s inventory bag is `Panel.cst` 35, whose
## `mouseUp` swaps sprite 45 to `bagopen` and opens `inventor.dir`. **Twelve sites
## write that swap and none writes it back**, and `bagopen` carries no script, so
## a swap the score never takes back leaves the suitcase looking open and
## answering nothing -- one symptom, because click eligibility and the cast script
## both belong to the member.
##
## What takes it back is the reference's all-ones copy-back on a backward `go`
## (`score.cpp:2213-2215`), which the room's own idle loop performs several times
## a second. That blanket was removed once already, for entry **120**: taken
## literally it also releases `piposh-dream/puzzle.dir`'s sliding tiles and
## re-solves the board. Both titles are correct only because the two movies write
## *different properties* -- `the memberNum of sprite` here, `the member of
## sprite` there -- and `Sprite::releaseAutoPuppet` has a row for the first and
## none for the second (`preview/channel.gd:FIELDS`).
##
## So the two harnesses guard opposite ends of one rule and **neither is
## sufficient alone**. Collapse the two spellings again while keeping the blanket
## and `puzzle_board` reds; collapse them and drop the blanket too and
## `puzzle_board` goes green again with the suitcase silently broken. That second
## state is the one this exists for, and it is exactly the state the port shipped
## in for six days.
##
## ## Why it drives clicks rather than reading the override table
##
## The player-visible failure is "I cannot click it again", and the override table
## cannot answer that: the member decides both what is drawn *and* which cast
## script answers, so the assertion has to be a click that reaches a handler. The
## click record names the tier and the script that answered, which is what
## separates "the bag reopened" from "the click fell through to the movie script".
##
## ## The one timing caveat, stated rather than tuned away
##
## The release happens on the room's backward wrap, so a re-click inside the same
## movie frame as the close finds the bag still open -- an eighth of a second at
## this title's 8 fps. `--gap` is a *whole loop* rather than a fixed guess for
## that reason; a smaller one makes this flake for a reason that is not a bug, the
## `play_suspends` shape `bugs.md` has paid for twice.
##
## ## Why it plays in rather than jumping to the room
##
## A cold `lingo_go_movie` into `NAVIGATE.dir` leaves `clockspeed` and the rest of
## `Panel.cst`'s clock globals unset, so `ClockScript` -- which the room runs off
## `idle` -- races through its schedule and fires `opentimeout` within seconds.
## That opens `timeout.dir` **over the stage**, and every later click on the bag
## is routed to the cut-scene window instead. Measured: 2 of 4 cycles, reported as
## "the click reached a sprite" with the bag correctly closed underneath, which
## reads exactly like the bug this asserts and is not it.
##
## `director-qa-playthrough` names that shape -- a cold-entry finding that does
## not survive being reached by playing -- and this is a second instance of it.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const PlayQueue := preload("res://tools/lib/play_queue.gd")

## Rating's menu, its "new game" button, and the Returns the arrival scene wants.
## `mainscreen` is where the attract loop settles; channel 9 carries the button
## whose `mouseUp` sets `clockspeed` and enters `ARRIVEL.DXR`.
## **Keyed on the movie's own markers, never on a tick count.** Both steps fire
## on a state the title reaches: `hedartzi` is the first marker of the attract
## reel, so step one runs as soon as the boot movie is actually playing, and
## `mainscreen` is where the reel settles. Channel 9 carries the button whose
## `mouseUp` sets `clockspeed` and enters `ARRIVEL.DXR`.
##
## The first version of this held `+30` before the jump and `+120` between the
## Returns, and it passed alone and **failed inside `gate.sh`**: under the
## suite's load the boot movie had not loaded by tick 30, the jump ran against no
## movie, and all five later steps never fired. That is `docs/bugs-closed.md`
## 119's shape and `bugs.md` 134's -- a window measured in something other than
## the movie's own events -- committed in a harness written to close an entry
## that cites both.
const PLAY_IN := "hedartzi=lingo:go(\"mainscreen\");mainscreen=ch9"

## The arrival scene has **no markers**, so it cannot be keyed on one and the
## queue grammar cannot express "press until it ends". `_reach` below waits on the
## movie change instead -- the title's own event -- and presses Return on the way.
const ROOM := "NAVIGATE.dir"

## Where the bag sits on the panel, in stage coordinates. Inside the sprite in
## every room of this title -- the panel is one strip drawn at the same place.
const BAG := Vector2(83, 438)
const BAG_CHANNEL := 45


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var driver := PlayQueue.new(self, preview, Args.flag(args, "quiet"))
	var run: Dictionary = await driver.run(
		PlayQueue.parse(Args.text(args, "do", PLAY_IN)),
		int(Args.number(args, "steps", 3600)), 30, true)
	# The arrival scene is 335 frames the mouse cannot leave and Return can, and it
	# has no marker to key a queue step on. Waited on the *movie change* rather than
	# on a budget of presses, with the presses spaced by the movie's own frames.
	var arrived := await _reach(preview, driver, ROOM,
		int(Args.number(args, "arrive", 5400)))

	h.begin("the queue reached the room the bag is in")
	var unfired: Array = run["unfired"]
	h.check("every step of the play-in fired", unfired.is_empty(),
		"%d never fired: %s" % [unfired.size(), str(unfired)])
	h.check("the player was not stopped by quit/halt", not bool(run["stopped"]))
	h.check("the playhead reached %s" % ROOM, arrived, str(preview.call("movie_name")))
	var playing := int(preview.call("lingo_sprite_prop", BAG_CHANNEL, "membernum")) > 0
	h.check("the bag is on screen", playing, "%s, ch%d member %d" % [
		str(preview.call("movie_name")), BAG_CHANNEL,
		int(preview.call("lingo_sprite_prop", BAG_CHANNEL, "membernum"))])
	h.complete("the queue reached the room the bag is in")
	if not playing:
		quit(h.finish("the inventory bag survives its own member swap"))
		return

	var cycles := int(Args.number(args, "cycles", 4))
	var gap := int(Args.number(args, "gap", 200))
	var opened := 0
	var closed := 0
	var missed: Array[String] = []
	for i in cycles:
		var before := int(preview.call("lingo_sprite_prop", BAG_CHANNEL, "membernum"))
		preview.call("route_click", BAG)
		await _tick(10)
		var click: Dictionary = preview.get("_last_click")
		var window: Node = _window(preview)
		if window != null:
			opened += 1
			# Closed the way the movie closes it, so the assertion is about the
			# member and not about finding the window's close button.
			preview.call("lingo_forget_window", "inventor.dir", true)
			await _tick(6)
			if _window(preview) == null:
				closed += 1
			else:
				var w = preview.get("_windows")
				var bits := PackedStringArray()
				for k in w:
					bits.append("%s valid=%s shown=%s movie=%s" % [k,
						is_instance_valid(w[k]),
						w[k].get("_window_shown") if is_instance_valid(w[k]) else "-",
						w[k].call("movie_name") if is_instance_valid(w[k]) else "-"])
				print("   DEBUG cycle %d: windows after forget: %s" % [i + 1, str(bits)])
		else:
			missed.append("cycle %d: click on the bag reached %s (bag was member %d)" % [
				i + 1, str(click.get("tier", "nothing")), before])
		await _tick(gap)

	h.begin("every click on the bag opens the inventory")
	h.check("the bag opened the window on each cycle", missed.is_empty(),
		"%d of %d opened%s" % [opened, cycles,
			"" if missed.is_empty() else "; " + str(missed)])
	h.complete("every click on the bag opens the inventory")

	# A single open proves nothing: the defect is that the *second* click is dead,
	# so a run that never got past one cycle has not asserted this entry's subject.
	h.begin("the bag was re-clicked after a close")
	h.check("more than one cycle completed", opened > 1 and closed > 1,
		"%d opened, %d closed" % [opened, closed])
	h.complete("the bag was re-clicked after a close")

	h.begin("the score took the member back")
	h.check("the bag is not left showing the open member",
		int(preview.call("lingo_sprite_prop", BAG_CHANNEL, "membernum"))
			!= _open_member(preview),
		"member %d" % int(preview.call("lingo_sprite_prop", BAG_CHANNEL, "membernum")))
	h.complete("the score took the member back")

	quit(h.finish("the inventory bag survives its own member swap"))


## Wait for the title to reach a movie, pressing Return while it does not.
##
## Returns whether it arrived. **Not a fixed number of presses**: the scene it is
## getting through waits on `soundBusy`, which is real audio time, so the number
## of presses it takes is a property of the machine and not of the movie.
func _reach(preview: Node, driver, movie: String, budget: int) -> bool:
	var last := -1
	var since := 0
	for i in budget:
		await process_frame
		if str(preview.call("movie_name")).to_lower().ends_with(movie.to_lower()):
			# Arrived. Let its opening frames run before anyone clicks.
			await _tick(60)
			return true
		# Spaced by the movie's own frames rather than by ticks, so a slow machine
		# presses the same number of times a fast one does.
		var here := int(preview.call("current_frame"))
		if here != last:
			last = here
			since += 1
			if since >= 8:
				since = 0
				await driver.press_key("", 36)
	return false


func _tick(n: int) -> void:
	for i in n:
		await process_frame


## The inventory window, **by name**.
##
## Not "whichever window is open": `Panel.cst`'s `ClockScript` runs off the
## stage's `idle` and opens `timeout.dir` on its own schedule, so a helper that
## returned the first entry of `_windows` reported the story's cut-scene window as
## the inventory -- counting an open the bag never performed and a close that
## never happened. On a cold `lingo_go_movie` the clock's globals are unset and it
## reaches those events within seconds, so this is the common case here rather
## than a rare one.
func _window(preview: Node) -> Node:
	var windows = preview.get("_windows")
	if windows == null:
		return null
	var node = windows.get("inventor")
	return node if node != null and is_instance_valid(node) else null


## The member the movie swaps in, by name, so this does not carry a slot number
## that a re-authored cast would silently invalidate.
func _open_member(preview: Node) -> int:
	var where: Array = preview.call("_resolve_member_ref", "bagopen", "")
	return int(where[1]) if where.size() > 1 else -1
