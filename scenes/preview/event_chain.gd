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

## `the mouseDownScript`, `the mouseUpScript`, `the keyDownScript`,
## `the keyUpScript` -- the other half of tier 1. True when something ran.
##
## Here rather than in `interaction.gd` or in `director_preview.gd` because both
## of those run one, and they ran two different versions of it: the mouse arm
## looked the name up with `has_handler` and the key arm did the same thing four
## hundred lines away with its own tally spelling. §6.3 makes them one tier and
## one rule, so they are one function.
##
## **What the property holds is Lingo source, compiled on assignment**
## (`preview_lingo_host.gd:_compile_primary`), and what arrives here is the
## compiled record. Two forms, resolved in Director's own order: a bare word is a
## no-argument call, so if it names a handler the movie declares, that handler
## runs; otherwise the compiled statement runs and reaches whatever Lingo would
## have reached. The distinction is invisible to the movie and exists so that a
## name resolving to nothing stays silent rather than reporting an unbound
## builtin on every keypress -- see the field's own note.
##
## **It passes by default**, like every tier-1 element (§8.2), so the caller runs
## it and carries on unless the handler said `dontPassEvent`. The caller also
## resets `pass_event` before calling: two primary elements both default to
## passing, and the second must not inherit the first's flag.
static func run_primary_script(host, interpreter, compiled: Dictionary,
		label: String) -> bool:
	if interpreter == null or compiled.is_empty():
		return false
	var name := str(compiled.get("name", ""))
	var named: bool = name != "" and bool(interpreter.has_handler(name))
	var body: Array = (compiled.get("handler", {}) as Dictionary).get("body", [])
	if not named and body.is_empty():
		return false
	# The name where there is one, so `keyDownScript:fromnow` still reads as the
	# thing that was installed; a marker where the source is not a name, because
	# a tally key holding a whole script is a tally key nothing can look up.
	var tag := "%s:%s" % [label, name if name != "" else "<source>"]
	host._tally(host._sent, tag)
	host._tally(host._ran, tag)
	# The primary handler is the first element of the same queue and gets the same
	# `execute()` scope as the five tiers below (`lingo-events.cpp:809`, `831`, and
	# `LingoInterpreter.begin_execute`). Without it an abort inside
	# `the mouseDownScript` would unwind past the primary tier into whatever the
	# player was doing, which is further than the reference goes -- and the primary
	# tier is the one most likely to be a one-line fragment with a typo in it,
	# because it is installed from a string.
	var scope: int = interpreter.begin_execute()
	if named:
		interpreter.call_handler(name)
		interpreter.end_execute(scope)
		return true
	var ran: bool = bool(interpreter.run_compiled(compiled))
	interpreter.end_execute(scope)
	return ran


## One element of the queue.
##
## `movie` distinguishes the last element from the rest: a movie script is found
## by handler name across every loaded cast rather than by being a particular
## script, so it has no `script` dictionary to carry.
##
## `channel` is the **behaviour instance** this element runs as, and `sprite` is
## what `the currentSpriteNum` reads while it runs. They are two fields because
## the two tiers that belong to a sprite need different halves of the answer:
## only a behaviour is an instance (`LingoInterpreter.behaviour_instance`), but a
## cast script is still running *for* a sprite and has no other way to learn
## which. A frame script and a movie script belong to no sprite and read 0.
##
## **The cast tier reading its channel departs from the reference, deliberately,
## and this is the measurement.** ScummVM sets `_currentSpriteNum` only in
## `processEvent`'s `kScoreScript` arm and zeroes it between queued elements
## (`lingo-events.cpp:773,806`), and a mouse chain queues the cast, frame and
## movie tiers with `channelId = 0` (`queueEvent` only fills `channelId` from
## `targetId` for a key event), so on the reference a cast script reads 0.
##
## The corpus says that cannot be what Director did. **All 12 reads of `the
## currentSpriteNum` in the six titles are in cast scripts on bitmap members, and
## 0 are in behaviours** -- members 3, 103 and 105 of `hex1`/`hex2`/`hex3`, the
## Hexxagon board's piece, its "step here" tile and its "jump here" tile. Every
## one of the three is `jumpFrom = the currentSpriteNum` deciding which of the 58
## board channels was clicked, and with 0 there `lightUp1Hex(0)` matches no `case`
## arm, no tile lights, and the board cannot be played at all -- which is the
## player report this closes. A shipped title does not ship a minigame that never
## worked in the authoring tool.
##
## The design argument agrees: a behaviour already knows its channel from `me`
## (`the spriteNum of me`), so a property that answered only inside a behaviour
## would be redundant with one the language already has. What has no other way to
## ask is exactly a cast script, and that is what these twelve sites are.
##
## Reversible in one place if a D6 test ever says otherwise: pass 0 for `sprite`
## at the cast call in `build`.
##
## `sprite` defaults to **`channel`**, not to 0, so that every caller that builds
## a sprite element the way it always did still reads its own channel -- there are
## two in `tools/media_surface.gd` and a default of 0 would have quietly answered
## 0 in both. Only a tier where the two genuinely differ passes it.
static func element(tier: String, script: Dictionary, pass_by_default: bool,
		movie := false, channel := 0, sprite := -1) -> Dictionary:
	return {
		"tier": tier, "script": script, "channel": channel,
		"sprite": channel if sprite < 0 else sprite,
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
			# The one element of the five that is a sprite behaviour, so the one
			# that `the currentSpriteNum` answers a channel for.
			out.append(element("sprite", behaviour, false, false, channel))
	if not member.is_empty():
		# In the member's own library, not by number alone. A member number is
		# per cast, so a number-only search answers with a stranger and the click
		# runs a script belonging to some other cast's member of the same number
		# -- the fault `preview/scripts.gd` exists to prevent, and it is no less
		# a fault here than it was in the eligibility test.
		var cast_script: Dictionary = host._script_in_lib(
			int(member.get("lib", 0)), int(member.get("id", 0)))
		if not cast_script.is_empty():
			# Channel 0 so this stays a script rather than becoming a behaviour
			# instance, and `sprite` so `the currentSpriteNum` still answers the
			# channel it is running for -- see `element`'s note for why the two
			# come apart here and nowhere else.
			out.append(element("cast", cast_script, false, false, 0, channel))
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
	for raw in host.frame_sprites():
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
	# A fresh step budget per event, for the reason `preview/scripts.gd:dispatch`
	# gives at its own call: `MAX_STEPS` exists to stop a runaway loop inside one
	# dispatch, and a count that accumulates for the life of the session against a
	# fixed ceiling eventually aborts every handler with "step budget exhausted".
	# Once per *chain* rather than once per element -- the chain is the event, and
	# a per-element reset would hand a four-element queue four budgets.
	#
	# The line is here as well as there because this path replaced `dispatch` for
	# the mouse and the keyboard; without it those two would keep the bug the
	# other call site fixed, which is worse than the duplication.
	interpreter.reset_steps()
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
		# §7.1's `the currentSpriteNum`, around the one element of the five that
		# can be a sprite behaviour. Saved and restored rather than zeroed
		# afterwards: the reference resets it to 0 between queued elements, which
		# is the same answer only because a chain starts from 0, and it
		# saves/restores around `sendSprite` -- where a behaviour messages another
		# sprite and has to read its own channel again on the way back. One rule
		# covers both, and the nested case is the one that would be wrong.
		var outer := 0
		if host._host != null:
			outer = int(host._host.current_sprite_num)
			host._host.current_sprite_num = int(el.get("sprite", 0))
		# **One `Lingo::execute` scope per element**, not per chain, and it is
		# opened by the two calls below rather than here. The reference's
		# `processEvents` walks the queue calling `processEvent`
		# (`lingo-events.cpp:723-786`), and `processEvent` calls `execute()` around
		# the one handler it delivers (`809`, `831`) -- so the flag an abort sets is
		# cleared between tiers, and a behaviour that aborts does not swallow the
		# frame script's turn at the same event. `LingoInterpreter.call_in_script`
		# and `call_movie_handler` carry the scope because they *are* that
		# per-element delivery and they have a second caller --
		# `frame_loop.gd:send_sprite_message`, for `beginSprite` / `endSprite` /
		# `stepFrame` -- which needs the same boundary and would not get it from a
		# line written here. `LingoInterpreter.begin_execute` is the whole argument.
		#
		# What stops a *chain* is a different flag: `stopEvent` / a missing `pass`,
		# which is `_passEvent` and is tested at the bottom of this loop. Conflating
		# the two would make a call to an undefined handler behave like a
		# `stopEvent` nobody wrote.
		if is_movie:
			interpreter.call_movie_handler(handler)
		else:
			# The element's channel makes this a behaviour *instance* rather than a
			# script -- see `LingoInterpreter.behaviour_instance`. Only the sprite
			# tier carries one; a cast script's element has channel 0 and gets none.
			interpreter.call_in_script(handler, script, int(el.get("channel", 0)))
		if host._host != null:
			host._host.current_sprite_num = outer
		if (host._frozen_lingo as Array).size() > parked:
			return ran
		if host._host != null and not bool(host._host.pass_event):
			return ran
	return ran
