extends RefCounted
## §6.3/§8.2: the whole chain, decided before any of it runs.
##
## **Director commits to the list of recipients before it runs the first one.**
## `queueEvent` pushes one element per tier -- primary handler, sprite behaviour,
## cast member script, frame script, movie script -- and only then does the
## runner start popping them. This port used to resolve each tier as it reached
## it, which is the same shape of divergence as `play`/`go` running to the end of
## the handler that called them: a decision Director had already taken, taken
## later here, so a handler could change the answer to a question that was
## already settled.
##
## Two things follow from queueing, and they are the reason this module exists
## rather than an `if` in the dispatcher:
##
## **A tier that answers is not the end of the chain.** `pass` continues it and
## `dontPassEvent` stops it, and the flag is reset to *the element's own default*
## before that element runs -- true for the primary handler, false for every
## other tier. So a sprite behaviour that says nothing consumes the click, and
## one that says `pass` hands it to the member's cast script, then the frame
## script, then the movie. `ISLAND2/External/BehaviorScript 325` is the whole of
## `on mouseUp / pass() / end`: a sprite whose only purpose is to hand the click
## on, and which was a dead zone for as long as this port stopped at the first
## handler that answered.
##
## **A sprite behaviour and its member's cast script are cumulative, not
## alternatives.** The old resolution took the behaviour *or*, only if there was
## none, the cast script -- so a behaviour declaring `mouseDown` and nothing else
## shadowed a cast script's `mouseUp` completely. They are two elements of one
## queue; each runs if it declares the handler, and the first that declares it
## and does not `pass` ends the chain.
##
## **§15's cast-script targeting, which is the sharpest consequence.** The
## reference latches the member under the pointer at the *start of the mouse-down
## chain* and uses it for the cast element of the mouse-up chain
## (`_currentMouseDownCastID`, `lingo-events.cpp`). So a `mouseDown` handler that
## swaps the member leaves the **old** member's cast script answering the
## `mouseUp` -- the swapped-in member never sees it. That is why `build` takes
## the member as an argument rather than reading it off the channel: for a press
## it is the member the press landed on, and for a release it is still the member
## the *press* landed on.
##
## Everything takes the preview node as `host`, in the convention
## `scenes/preview/README.md` sets out: the elements are resolved through the
## node's own script lookups, so this module cannot answer differently from the
## dispatcher it replaced.

## One element of the queue.
##
## `movie` distinguishes the last element from the rest: a movie script is found
## by handler name across every loaded cast rather than by being a particular
## script, so it has no `script` dictionary to carry.
static func element(tier: String, script: Dictionary, pass_by_default: bool,
		movie := false) -> Dictionary:
	return {
		"tier": tier, "script": script,
		"pass_by_default": pass_by_default, "movie": movie,
	}


## The elements below the primary handler, for a mouse or key event.
##
## The primary tier is deliberately absent. It is run by the caller -- by
## `preview/interaction.gd:press` for the mouse and by
## `director_preview.gd:_dispatch_key_event` for the keyboard -- because it also
## has to happen before the rest of the click model is latched. What this module
## needs from it is only its verdict, and that arrives in the pass flag: the
## caller sets the flag to the primary element's default (true) before running
## it, so a false flag on entry to `run` can only be a `dontPassEvent` from a
## primary handler that actually ran.
##
## `channel` is the sprite the event belongs to, or 0 for "the chain starts at
## the frame". `member` is `{"lib":, "id":}` for the cast element, or `{}` for
## none -- see the note above on why it is passed rather than read.
static func build(host, channel: int, member: Dictionary) -> Array:
	var out: Array = []
	if channel > 0:
		var behaviour: Dictionary = host._sprite_script(channel, host._index)
		if not behaviour.is_empty():
			out.append(element("sprite", behaviour, false))
	if not member.is_empty():
		# In the member's own library, not by number alone. A member number is
		# per cast, so a number-only search answers with a stranger and the click
		# runs a script belonging to some other cast's member of the same number
		# -- the fault `preview/scripts.gd` exists to prevent, and it is no less
		# a fault here than it was in the eligibility test.
		var cast_script: Dictionary = host._script_in_lib(
			int(member.get("lib", 0)), int(member.get("id", 0)))
		if not cast_script.is_empty():
			out.append(element("cast", cast_script, false))
	var frame: Dictionary = host._frame_script(host._index)
	if not frame.is_empty():
		out.append(element("frame", frame, false))
	out.append(element("movie", {}, false, true))
	return out


## `{"lib":, "id":}` for whatever channel `channel` displays right now, or `{}`.
##
## The **effective** sprite, so a `puppetSprite` write that swapped the member is
## what the cast element resolves against -- the reference reads the live channel
## (`_score->_channels[id]->_sprite->_castId`) and not the score record, and a
## swapped member with a cast script of its own is exactly the case §15 is about.
static func member_on(host, channel: int) -> Dictionary:
	if channel <= 0 or host._score == null:
		return {}
	for raw in host._score.frame(host._index).get("sprites", []):
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = host._effective(raw)
		if live.is_empty():
			return {}
		return {"lib": int(live["cast_lib"]), "id": int(live["cast_id"])}
	return {}


## Run a built queue. Returns the number of elements that actually ran.
##
## The three rules, each of which is a way to get this wrong:
##
## 1. **An element that declares no handler is skipped, not counted.** It does
##    not consume the event and it does not end the chain -- the reference
##    `continue`s before it ever touches the flag (`kNoneScript`). Counting a
##    silent tier as an answer is what would make a behaviour with only a
##    `mouseDown` swallow the `mouseUp` all over again.
## 2. **The flag is reset to the element's own default before the element
##    runs**, never once per event. Two elements that both pass by default must
##    not have the second inherit the first's `dontPassEvent`.
## 3. **A suspended handler ends the chain.** `play` and `go` freeze the caller
##    (§6.1 step 18), and the reference stops an *input* event's queue the moment
##    an element fails to complete. Carrying on would run the frame script of a
##    room the `go` has already left, against a score that has moved.
##
## `_sent` is tallied once for the whole chain and `_ran` once per element that
## ran, plus a per-tier row. That split is deliberate: `_sent` answers "did the
## event get past the primary handler", which is what `tools/key_chain.gd`
## asserts and what the count must not change under; `_ran` answers "how many
## handlers did this event actually run", which is the number this change is
## measured by.
static func run(host, interpreter, handler: String, elements: Array) -> int:
	if interpreter == null:
		return 0
	# §8.2, the primary handler's verdict. Set to true by the caller before the
	# primary tier ran, so false here means one ran and said `dontPassEvent`.
	if host._host != null and not bool(host._host.pass_event):
		return 0
	var key := handler.to_lower()
	host._tally(host._sent, handler)
	var ran := 0
	for value in elements:
		var el: Dictionary = value
		var is_movie: bool = bool(el["movie"])
		var script: Dictionary = el["script"]
		var declares: bool = (
			interpreter.has_handler(key) if is_movie
			else interpreter.call("_script_has_handler", script, key)
		)
		if not declares:
			continue
		if host._host != null:
			host._host.pass_event = bool(el["pass_by_default"])
		host._tally(host._ran, handler)
		host._tally(host._ran, "%s@%s" % [handler, str(el["tier"])])
		ran += 1
		var parked: int = (host._frozen_lingo as Array).size()
		if is_movie:
			interpreter.call_movie_handler(handler)
		else:
			interpreter.call_in_script(handler, script)
		if (host._frozen_lingo as Array).size() > parked:
			return ran
		if host._host != null and not bool(host._host.pass_event):
			return ran
	return ran
