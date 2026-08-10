extends RefCounted
## The two per-frame callouts a movie can install, and the timeout clock.
##
## Three Director features that this port had none of, all of them the same
## missing thing -- a place for the frame loop to call *out* to Lingo on a clock
## rather than on a score event:
##
##   `the perFrameHook`  one script object, sent `stepFrame` once per frame.
##   `the actorList`     a list of script objects, each sent `stepFrame` once
##                       per frame, after the hook.
##   the timeout family  `the timeoutLength` ticks of no player activity raise a
##                       `timeOut` event, which `the timeoutScript` and the
##                       movie's own `on timeOut` handlers answer.
##
## They are together because they are one hole. `docs/ENGINE_TODO.md` grouped
## them for that reason, and `AGENTS.md` names `timeout` and `stepFrame` among
## the calls already made the wrong way.
##
## **`stepFrame` is how a large class of Director titles animates.** A movie with
## one frame and a `go to the frame` in it drives everything from `the actorList`:
## each object steps itself, moves its own sprite and returns. Without the
## callout such a movie sits on its frame doing nothing at all, and nothing in a
## log says why -- the score is advancing, the handlers exist, and they are never
## sent a message.
##
## ## Where the ordering comes from
##
## `score.cpp:731-770` calls `executePerFrameHook` **as soon as a frame switch is
## done** -- after the playhead has moved and before `prepareFrame` and
## `enterFrame` -- and not at all when the movie is paused or has only just
## started. The reference's own comment on that call says it "also sends
## stepFrame message to actorList", so the hook and the list are one callout in
## one place and not two.
##
## The transition clause is reproduced as its condition rather than as its
## mechanism: the reference skips the hook here when the frame carries a
## transition, because it calls it once per transition *subframe* instead. This
## port draws a transition as a hold rather than as subframes (`frame_loop.gd`),
## so there are no subframes to hang it on; the hook is skipped on such a frame
## exactly as the reference skips it, and what the reference does instead is
## recorded here as absent rather than approximated by calling it once.
##
## ## The timeout clock
##
## `score.cpp:638-643` checks it **independently of the frame delay** -- once per
## engine tick, not once per score step -- and only while the movie is not
## `pause`d. Firing resets the clock, so a movie with a 60-tick timeout and no
## activity gets one event a second rather than one per tick for ever.
##
## The clock is reset by the events the three switches name: a mouse-down while
## `the timeoutMouse` is true (`events.cpp:270`), a key-down while `the
## timeoutKeyDown` is true (`events.cpp:371`), and -- the one the reference
## stores and never reads -- a `play` while `the timeoutPlay` is true.
##
## Defaults are Director's, from `movie.cpp:89-94`: 10800 ticks (three minutes),
## mouse and key on, play off.

const EventChain := preload("res://scenes/preview/event_chain.gd")
const LingoObject := preload("res://lingo/lingo_object.gd")

## Director's per-frame message to an actor. Spelled here once so the hook and
## the list cannot drift apart.
const STEP_FRAME := "stepFrame"
## The event a lapsed timeout raises.
const TIMEOUT := "timeOut"


## `the perFrameHook`, then every object in `the actorList`, each sent
## `stepFrame` (§6.1).
##
## Called from `frame_loop.gd:advance` at the reference's own point in the step:
## after the playhead has moved and before `prepareFrame`.
##
## Returns how many objects were stepped, so a harness can assert the callout
## happened rather than infer it from a side effect the movie might not have.
static func step_frame(host) -> int:
	var lingo_host = host._host
	if lingo_host == null or host._interpreter == null:
		return 0
	var stepped := 0
	if LingoObject.is_object(lingo_host.per_frame_hook):
		stepped += _send(host, lingo_host.per_frame_hook)
	# A copy, because `stepFrame` is exactly the handler a movie uses to remove
	# an actor from the list -- an exhausted animation deletes itself -- and
	# iterating the live Array while a handler mutates it skips its neighbour.
	for actor in (lingo_host.actor_list as Array).duplicate():
		if LingoObject.is_object(actor):
			stepped += _send(host, actor)
	return stepped


## One `stepFrame`, to one object. 1 when the object declared a handler for it.
##
## The `resolve` test is not redundant with `send_to_object`, which also answers
## nothing for an object that does not declare the handler: it is what keeps the
## *tally* honest. `host._ran` is the count of handlers that actually ran, and an
## actorList full of objects with no `stepFrame` would otherwise inflate it.
static func _send(host, actor: Variant) -> int:
	if (actor as Object).call("resolve", STEP_FRAME).is_empty():
		return 0
	host._tally(host._sent, STEP_FRAME)
	host._tally(host._ran, STEP_FRAME)
	host._interpreter.reset_steps()
	host._interpreter.send_to_object(actor, STEP_FRAME)
	return 1


## Has the player been away long enough? Raise `timeOut` if so (§6.2).
##
## Called once per engine tick from `frame_loop.gd:tick`, which is the
## reference's "independently of the frame delay", and refused while the movie is
## `pause`d because `Score::update` tests `_playbackPaused` before the check.
##
## A length of 0 or less disables the clock. That is not in the reference's
## arithmetic -- `ticks - lastTimeOut >= 0` is true every tick -- and it has to
## be here, because this port's default would otherwise fire a `timeOut` on the
## first tick of every movie for a property no title has set. Director's own
## default is 10800 and a movie that sets 0 means "off"; firing continuously is
## the one reading that cannot be what anybody wanted.
##
## Returns true when the event was raised.
static func check_timeout(host) -> bool:
	var lingo_host = host._host
	if lingo_host == null or host._interpreter == null:
		return false
	if lingo_host.timeout_length <= 0 or lingo_host.playback_paused:
		return false
	if lingo_host.timeout_lapsed_ticks() < lingo_host.timeout_length:
		return false
	lingo_host.reset_timeout()
	raise(host)
	return true


## Send the `timeOut` event down §6.3's chain for it: the primary handler `the
## timeoutScript` installs, then the frame script, then the movie scripts.
##
## `lingo-events.cpp:482` queues `kEventTimeout` at the primary tier with the
## mouse and key events, and `:639` falls it through the frame tier into the
## movie tier -- so it is neither a movie-only event like `startMovie` nor a
## sprite event. There is no sprite tier for it: a timeout is not about a place
## on the stage.
static func raise(host) -> void:
	var lingo_host = host._host
	host._tally(host._sent, TIMEOUT)
	lingo_host.pass_event = true
	var ran := EventChain.run_primary_script(
		host, host._interpreter, lingo_host.timeout_compiled, "timeoutScript")
	if ran and not lingo_host.pass_event:
		return
	host._dispatch(TIMEOUT, host._frame_script(host._index))
