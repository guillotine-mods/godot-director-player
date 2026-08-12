extends SceneTree
## Does a puppet outlive the score, and does a *non*-puppet stop when the score
## says so? The two halves of Director's puppet model, asserted through a save.
##
##   godot --headless --path . --script tools/puppet_persists.gd
##   godot --headless --path . --script tools/puppet_persists.gd -- --label veranda
##   godot --headless --path . --script tools/puppet_persists.gd -- \
##       --save saves/piposh2/tofi_bug.json --channel 18
##
##   --label A,B   the markers to click at (default `exitforest3,veranda`)
##   --channel N   the sprite channel to click (default 18)
##   --ticks N     score ticks to watch after each click (default 400)
##   --save F      click from state `F` instead of building one, once
##   --room M      the movie the rooms are in (default PIP2DATA/DAY1.dir)
##   --via M       the movie the boot chain passes through (default EXODUS.DIR)
##
## ## The rule, which knows no movie
##
## Director keeps one live sprite per channel and reconciles it from the score
## every frame. **A whole-sprite puppet stops that reconcile entirely**
## (`docs/DIRECTOR_ENGINE.md` §5.2: `Sprite::replaceFrom` copies the script
## attachment and returns), and §5.5: nothing in the frame loop clears it, so it
## survives frame jumps and `go to`. A **per-field auto-puppet** is the opposite:
## §5.3, it is released the moment the score writes that property, and §5.4, a
## cast-id write releases the size with it.
##
## So the assertions are one rule read from three ends:
##
## 1. a channel a script has `puppetSprite N, TRUE`'d is **still on the frame**
##    every tick, including frames whose score record for it is empty. Not "still
##    visible" -- a script may legitimately hide it -- but still *there*, because
##    a channel the score has dropped can never come back.
## 2. **and a channel the score dropped that nothing puppets is gone**, which is
##    what makes (1) a rule rather than a leak. The frame holds the score's
##    channels plus the flagged puppets and nothing else. A clip that drops a
##    foreground layer and the player behind it drops two records and only one may
##    survive, so the player is drawn unoccluded -- authentic, measured, and
##    `bugs.md` 48.
## 3. a channel it has *not* puppeted is back on **the score's** member once the
##    score has **written** that channel, however recently a script wrote one --
##    and the member the script wrote lasted longer than the tick it was written
##    on. Written, not changed: `bugs.md` 47 is a clip whose score puts the same
##    member on the channel as the room it was entered from, so every check
##    phrased as a change reports that it proved nothing, in the one room where
##    there was something to prove.
##
## Each room says which of the three it actually proved. `exitforest3` into
## `dnzclicktalk` is where the score drops the puppeted channel and rewrites the
## un-puppeted one in place; `veranda` into `tofclicktalk` is where it moves the
## un-puppeted one outright; neither exercises everything, and a check that proved
## nothing prints so rather than passing quietly.
##
## ## Why it goes through a save at all
##
## Two reasons, and the second is the one worth keeping. The first is speed: a
## state is seconds where the boot chain is four hundred steps, so a person
## chasing this reproduces it in one command. The second is that **the puppet
## claim is now saved state** -- it lives in `_overrides` beside the properties a
## script wrote -- and a claim that did not survive `capture`/`restore` would give
## a restored session a player character that vanishes in exactly the rooms this
## is about. Clicking from the record rather than from the live session is what
## tests that, and `save_state.gd`'s own gate cannot: `_overrides` was already
## accounted for, so a new key *inside* it is invisible to that check.
##
## The state is **built here** rather than committed. `saves/` is gitignored on
## purpose -- a save carries the movie's own field text, which is game data and
## does not belong in this repository -- so a fixture would be a gate that fails
## on a fresh checkout. Building it also keeps it honest: it is always this
## engine's own record, never one an older build left behind.
##
## ## What it was written from
##
## Both reports in `bugs.md` 36, which are one fault. DAY1 puppets channel 30 --
## the player -- in `init all` and never un-puppets it; its `dnzclicktalk`,
## `lilclicktalk` and `lilout1` clips carry **no channel 30 at all**, so the
## player vanished for the length of somebody else's conversation. And
## `BehaviorScript 291` swaps `btofspk1` onto channel 18 for the talking, which
## the score never took back, so the mouth kept moving after the clip had
## returned to the room and the speech had finished.
##
## Corpus-aware in its scenario and title-agnostic in its rule, the same way
## `frame_events.gd` and `playhead_escape.gd` are: the checks below name no
## channel, no member and no room. The state says which.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Escape := preload("res://tools/playhead_escape.gd")
const SaveFiles := preload("res://scenes/preview/save_files.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")
const LingoValue := preload("res://lingo/lingo_value.gd")

## The two rooms, because the two halves need different scores. See the header.
const LABELS := "exitforest3,veranda"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _play(h)
	quit(h.finish("a puppet outlives the score and an auto-puppet does not"))


## Returns whether it ran to a conclusion rather than whether the checks passed:
## a GDScript runtime error aborts this handler, and an open case reports FAIL
## rather than ending the run quietly. See `harness.gd`.
func _play(h: Harness) -> bool:
	var args := Args.parse()
	var channel := Args.number(args, "channel", 18)

	# A state named on the command line is somebody reproducing a report, so it is
	# taken as given and nothing is built. `preview/boot.gd` has already restored
	# it by the time this runs, which is why there is no load here.
	if args.has("save"):
		var named := Args.text(args, "save").get_file()
		var case := "%s: a puppet outlives the score, an auto-puppet does not" % named
		h.begin(case)
		var loaded: Node = load("res://scenes/director_preview.tscn").instantiate()
		root.add_child(loaded)
		for i in 5:
			await process_frame
		if not await _measure(h, loaded, args, channel):
			return true
		h.complete(case)
		return true

	for label in Args.text(args, "label", LABELS).split(","):
		if label.strip_edges() == "":
			continue
		if not await _room(h, args, label.strip_edges(), channel):
			return true
	return true


## One room: drive the boot chain to it, write the state, put the state back into
## a *fresh* preview, and click.
##
## The second preview is not ceremony. Restoring into the node that produced the
## record proves nothing about the record -- every field it failed to carry would
## still be sitting in memory answering for it. A save is only tested by a boot
## that had no other way to know.
func _room(h: Harness, args: Dictionary, label: String, channel: int) -> bool:
	var case := "%s: a puppet outlives the score, an auto-puppet does not" % label
	h.begin(case)

	var builder: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(builder)
	await process_frame
	# `_ticks` is the unit everything below is measured in and it is *not* in
	# `tools/preview_surface.gd`'s asserted list, so a rename would make `get()`
	# answer null, `int(null)` answer 0, and this go green over a movie it never
	# watched. `scenes/preview/README.md` names that failure mode.
	if not h.check("the movie's own tick counter is readable",
			builder.get("_ticks") != null):
		return false
	var path := await _build(h, builder, args, label, channel)
	builder.queue_free()
	await process_frame
	if path == "":
		return false

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	print("   %s" % InputRouter.load_save(preview, path))
	# `lingo_go_movie` inside the load enters the movie on the ticks *after* the
	# call, exactly as `tools/click_trace.gd` documents, so the frame is settled
	# before anything is read off it.
	for i in 4:
		await process_frame
	var ran := await _measure(h, preview, args, channel)
	preview.queue_free()
	await process_frame
	if not ran:
		return false
	h.complete(case)
	return true


## Click `channel` on whatever is playing, and hold the two rules to what happens.
func _measure(h: Harness, preview: Node, args: Dictionary, channel: int) -> bool:
	if not h.check("the state is playing",
			preview.get("_score") != null and int(preview.get("_index")) > 0,
			"%s frame %d" % [
				str(preview.call("movie_name")), int(preview.get("_index"))]):
		return false

	# Which channels are whole-sprite puppets, and which of them the frame the
	# state was taken on actually shows. A puppet on a channel that was never on
	# screen has nothing to lose and is not the subject.
	var watched: Array[int] = []
	var overrides: Dictionary = preview.get("_overrides")
	for key in overrides:
		if bool((overrides[key] as Dictionary).get("_puppet", false)):
			watched.append(int(key))
	watched.sort()
	var on_screen: Array[int] = []
	for ch in watched:
		if _channel_shown(preview, ch):
			on_screen.append(ch)
	# The claims are read off the *restored* record, so this is also the check
	# that a save carries them at all.
	if not h.check("the state carries a whole-sprite puppet that is on screen",
			not on_screen.is_empty(), "puppetSprite claims: %s" % str(watched)):
		return false
	print("   whole-sprite puppets on this frame: %s" % str(on_screen))

	# The member the *score* has on the clicked channel here. The clip is about to
	# write another one over it, and rule 2 is that the score gets it back.
	var score_member := _score_member(preview, channel)
	if not h.check("the score has a member on channel %d to click" % channel,
			score_member > 0, "frame %d" % int(preview.get("_index"))):
		return false
	var centre: Vector2 = Escape.sprite_centre(preview, channel)
	if not h.check("channel %d has a rect to click" % channel, centre.x >= 0.0):
		return false

	var before := int(preview.get("_index"))
	# Every channel the score carries on the frame the click is made from, so the
	# watch below can tell "the score let this one go" from "the score never had
	# it". Read before the click, because the click is what moves the playhead.
	var entry_channels: Array[int] = []
	for value in (preview.get("_score").frame(before).get("sprites", []) as Array):
		entry_channels.append(int((value as Dictionary)["channel"]))
	# Every channel a script has *hidden* on the way in, for the third rule below.
	# `the visible of sprite` is channel state rather than a puppeted sprite field
	# (`preview/sprite_state.gd:CHANNEL_STATE`), so nothing that hands a channel
	# back to the score may take a hide with it.
	var hidden_at_entry: Array[int] = []
	for key in overrides:
		if int((overrides[key] as Dictionary).get("visible", 1)) == 0:
			hidden_at_entry.append(int(key))
	hidden_at_entry.sort()
	var same_movie := str(preview.call("movie_name"))
	preview.call("route_press", centre)
	preview.call("route_release", centre)
	if not h.check("the click was answered", int(preview.get("_index")) != before,
			"f%d -> f%d" % [before, int(preview.get("_index"))]):
		return false

	# Watch. Real frames, never a synthetic tick loop: a `for i in N` advances the
	# runtime's clock and not the audio server's, every `soundBusy` guard holds
	# for ever and a talk clip never ends (AGENTS.md, bugs.md 22).
	var dropped: Dictionary = {}
	var abandoned: Dictionary = {}
	var stowaways: Dictionary = {}
	var left_with_the_score: Dictionary = {}
	var un_hidden: Dictionary = {}
	var released: Dictionary = {}
	var swapped_away := false
	var score_moved := false
	var score_wrote := false
	var returned := false
	var held := 0
	var run := 0
	var began := int(preview.get("_ticks"))
	var start := Time.get_ticks_msec()
	var last := -1
	var was_at := int(preview.get("_index"))
	# Two limits, and only the first is the measurement. The tick budget is the
	# movie's own clock and is the same number on every machine; the wall-clock
	# one is a hang guard and must never be what ends a healthy run, because the
	# moment it does the result depends on how fast the machine is. It did:
	# `puppet_persists` passed on this repo's Windows runner and on a developer
	# Mac and failed on every macOS runner, which is the signature of a
	# wall-clock budget rather than of a defect.
	var tick_budget := Args.number(args, "ticks", 400)
	# 240000 was the old value and it is exactly what this failed on: the macOS
	# runner's gate step ran 241s, hitting the guard to the second, while this
	# machine finishes the whole harness in 87s. Doubled, which clears the
	# measured need with room and still sits under the nightly's 600s
	# `GATE_TIMEOUT` so the harness reports its own FAIL rather than being killed
	# and reported as a TIMEOUT.
	var watch_ms := Args.number(args, "watch-ms", 480000)
	while int(preview.get("_ticks")) - began < tick_budget \
			and Time.get_ticks_msec() - start < watch_ms:
		await process_frame
		var now := int(preview.get("_ticks"))
		if now == last:
			continue
		last = now
		# Did the score *write* the clicked channel's member on the way here?
		#
		# Not "did the member change", which is what `score_moved` below asks and
		# what the release used to be inferred from. A score that rewrites a
		# channel with the member it already had has still written it, and Director
		# releases on the write (§5.3). The two questions have the same answer in
		# every room where a clip changes the member and different answers in the
		# room that found `bugs.md` 47 — so asking only the easy one is how a check
		# passes over the case it was meant to cover.
		var here := int(preview.get("_index"))
		if here != was_at:
			var writes: Dictionary = preview.get("_score").writes_between(was_at, here)
			for field in (writes.get(channel, {}) as Dictionary):
				if field == "cast_id" or field == "cast_lib":
					score_wrote = true
			was_at = here
		# `with_puppets`' whole contract, from the other side: the frame holds the
		# score's channels **plus the flagged puppets and nothing else**. The half
		# above proves a puppet is not dropped; this proves nothing else is kept.
		#
		# It is the rule the player sees as depth. A clip that drops a foreground
		# layer *and* the player standing behind it drops both records, and only
		# the puppeted one may survive — so the player is drawn unoccluded, which
		# looks like a layering bug and is the movie's own doing (`bugs.md` 48).
		# A port that carried the un-puppeted channel too would hide the fault by
		# reproducing the occlusion for the wrong reason, and this is what says so.
		for value in (preview.call("frame_sprites") as Array):
			var ch := int((value as Dictionary)["channel"])
			if _score_member(preview, ch) > 0:
				continue
			if bool((overrides.get(ch, {}) as Dictionary).get("_puppet", false)):
				continue
			stowaways[ch] = here
		# **A hide is not a puppet, and only a script may lift it.** Director keeps
		# `the visible of sprite` on the channel, and the reference writes that
		# field in exactly one place -- its own setter. So a hide surviving is not
		# a nicety: an override entry that loses its `visible` key without a script
		# writing one has had the hide taken by the engine, and the sprite appears.
		#
		# Phrased as "the key is gone", never as "the sprite is hidden". A script
		# that legitimately un-hides writes `visible = 1` and the key stays, so the
		# two cases are distinguishable -- and asserting the sprite is still hidden
		# would fail on the movie doing exactly what it is entitled to do.
		#
		# Three saves are behind this: `puppetSprite(i, 0)` over a range that
		# `init all` had hidden erased those channels outright, and four dwarves and
		# Renati walked back into shot while somebody else walked off.
		if str(preview.call("movie_name")) == same_movie:
			for ch in hidden_at_entry:
				if not (overrides.get(ch, {}) as Dictionary).has("visible") \
						and not un_hidden.has(ch):
					un_hidden[ch] = here
		# And whether this room ever released a puppet at all, so a green check
		# above can be attributed rather than assumed.
		for ch in watched:
			if not bool((overrides.get(ch, {}) as Dictionary).get("_puppet", false)) \
					and not released.has(ch):
				released[ch] = here
		for ch in on_screen:
			# A script may un-puppet a channel, and then the score owns it again
			# and dropping it is correct. Only a channel that is *still* claimed
			# is being asserted about.
			if not bool((overrides.get(ch, {}) as Dictionary).get("_puppet", false)):
				continue
			# Where the score itself went silent about the channel, so the report
			# below can say whether rule 1 was ever put to the question.
			if _score_member(preview, ch) <= 0:
				abandoned[ch] = int(preview.get("_index"))
			if not _channel_shown(preview, ch):
				dropped[ch] = int(preview.get("_index"))
		# And the channels the score dropped that *nothing* puppets, which is the
		# comparison that makes the check above mean anything: "a puppet survived"
		# proves the rule only beside "an un-puppeted neighbour did not".
		for ch in entry_channels:
			if _score_member(preview, ch) <= 0 \
					and not bool((overrides.get(ch, {}) as Dictionary).get("_puppet", false)):
				left_with_the_score[ch] = here
		# How long the clip's own member *lasted*, not merely that it appeared.
		# One tick is the signature of something releasing the write behind the
		# movie's back -- `director_preloader.gd` asking `_effective` about frames
		# 24 ahead did exactly that, and every animation a script drove was undone
		# on the step after it was asked for.
		if _shown_member(preview, channel) != score_member:
			swapped_away = true
			run += 1
			held = maxi(held, run)
		else:
			run = 0
		# Did the *score* move the clicked channel? That is the precondition of
		# the release rule (§5.3), not a detail of it: an auto-puppet is released
		# when the score writes the property, so a clip whose score keeps the same
		# member on that channel leaves the script's write standing -- in Director
		# too. Asserting a release there would be asserting a bug.
		var under := _score_member(preview, channel)
		if under > 0 and under != score_member:
			score_moved = true
		if swapped_away and int(preview.get("_index")) == before:
			returned = true
			break

	print("   %d score tick(s); the score dropped %s and moved channel %d: %s;"
		% [int(preview.get("_ticks")) - began, str(abandoned.keys()), channel,
			"yes" if score_moved else "no"]
		+ " the clip's own member held for %d tick(s)" % held)
	h.check("every channel still claimed by `puppetSprite` stayed on the frame",
		dropped.is_empty(),
		"dropped: %s" % str(dropped) if not dropped.is_empty() else "")
	h.check("and no channel the score dropped stayed without one",
		stowaways.is_empty(),
		"carried unpuppeted: %s" % str(stowaways) if not stowaways.is_empty() else "")
	h.check("no script-set hide was discarded by anything but a script",
		un_hidden.is_empty(),
		"lost `visible` on %s" % str(un_hidden) if not un_hidden.is_empty() else "")
	h.check("the clip wrote its own member over channel %d" % channel, swapped_away)
	h.check("and it lasted longer than the tick it was written on",
		not swapped_away or held > 1, "held for %d score tick(s)" % held)
	# The detail names which limit ended the watch, because "stopped on f2621" on
	# its own cannot distinguish a clip that went somewhere wrong from one that
	# simply ran out of budget, and those want opposite fixes. A nightly failure
	# is read once, on a runner that no longer exists.
	var spent_ticks := int(preview.get("_ticks")) - began
	var spent_ms := Time.get_ticks_msec() - start
	h.check("the clip returned to the frame it was entered from", returned,
		"stopped on f%d after %d/%d tick(s) and %d/%d ms -- ended by %s" % [
			int(preview.get("_index")), spent_ticks, tick_budget, spent_ms, watch_ms,
			"the wall-clock guard, so this is a budget and not a defect"
				if spent_ms >= watch_ms else "the tick budget"])
	# Every branch says when it proved nothing rather than passing on a vacuous
	# truth. `porting-fidelity-verification`: a green check nobody can attribute
	# is the shape that lets a fix look verified when it was never exercised.
	#
	# The release is asked on the **write** and not on the change. Those were one
	# question here, worded as the change, and `bugs.md` 47 is the gap between
	# them: at `exitforest3` the score puts `adnzlop1` on channel 18 both in the
	# room and inside `dnzclicktalk`, so the member never moves, so this branch
	# used to print "does not test the release" over the room that had the bug in
	# it. Now it tests it, and only a score that never touches the channel at all
	# is excused.
	if returned and score_wrote:
		h.check("channel %d is back on the score's member" % channel,
			_shown_member(preview, channel) == score_member,
			"score %d, showing %d%s" % [score_member, _shown_member(preview, channel),
				"" if score_moved else "; the score rewrote the member it already had"])
	elif returned:
		print("   the score never wrote channel %d's member, so the write standing"
			% channel + " is correct and this room does not test the release")
	if hidden_at_entry.is_empty():
		print("   nothing was hidden by a script here, so this room does not test"
			+ " that a hide survives")
	elif released.is_empty():
		print("   %d hide(s) on %s, and nothing un-puppeted a channel, so this room"
			% [hidden_at_entry.size(), str(hidden_at_entry)]
			+ " does not test that a hide survives the release")
	else:
		print("   %d hide(s) on %s survived the release of %s"
			% [hidden_at_entry.size(), str(hidden_at_entry), str(released.keys())])
	_release_keeps_the_hide(h, preview, channel)
	if abandoned.is_empty():
		print("   the score carried every puppeted channel throughout, so this"
			+ " room does not test the persistence")
	elif left_with_the_score.is_empty():
		print("   the score dropped only puppeted channels here, so this room does"
			+ " not test that an un-puppeted one goes")
	else:
		print("   the score dropped %s and kept the puppeted ones; %s went with it"
			% [str(abandoned.keys()), str(left_with_the_score.keys())])
	return true


## `puppetSprite N, FALSE` hands the **sprite** back and leaves the **channel**
## alone, stated directly rather than waited for.
##
## The rule above is watched while a movie plays, and both rooms print "does not
## test that a hide survives the release" -- neither un-puppets anything, so the
## check that three bug reports are behind passes over a movie that never puts it
## to the question. A rule only a movie can choose to exercise is a rule that is
## usually not exercised, and this is the one that walked four dwarves and Renati
## back into shot: DAY1's walk-away path runs `puppetSprite(i, 0)` over a range of
## channels `init all` had hidden with `sprite(i).visible = 0`.
##
## So it is driven here instead: hide a channel the score is drawing, claim the
## whole sprite, write a member onto it, and hand it back. Director's
## `b_puppetSprite` is one line for the FALSE case -- `chan->setClean(the score's
## record for this channel)` -- and `setClean` replaces the fields of the
## **Sprite**. `Channel::_visible` is not in that object, so the hide stays; the
## member is, so the script's write goes.
##
## **Both halves, because either alone passes for a `set_puppet` that does
## nothing at all.** "The hide survived" is also what a no-op release does, and
## "the member came back" is also what erasing the whole entry does -- which is
## precisely the pair of behaviours this port has shipped, one each way.
##
## Asked of the stage rather than of the property: `_effective` is what the
## painter, the hit test and `rollOver` all go through, so a sprite that is not in
## its answer is a sprite the player cannot see or click.
func _release_keeps_the_hide(h: Harness, preview: Node, channel: int) -> void:
	var score_member := _score_member(preview, channel)
	if score_member <= 0:
		print("   the score has no member on channel %d here, so the release rule"
			% channel + " could not be driven directly")
		return
	# A member the score is not showing, so "the script's write went" is
	# distinguishable from "nothing was ever written". It does not have to resolve
	# to real artwork -- nothing draws during this, and the assertion is about
	# which number the channel is carrying.
	var written := score_member + 1
	preview.call("lingo_set_sprite_prop", channel, "visible", 0)
	h.check("a script's hide takes channel %d off the stage" % channel,
		not _channel_drawn(preview, channel))
	preview.call("lingo_puppet_sprite", channel, true)
	preview.call("lingo_set_sprite_prop", channel, "membernum", written)
	h.check("and the whole-sprite puppet holds the script's member",
		_shown_member(preview, channel) == written,
		"wrote %d, showing %d" % [written, _shown_member(preview, channel)])

	preview.call("lingo_puppet_sprite", channel, false)
	h.check("`puppetSprite %d, FALSE` gives the sprite back to the score" % channel,
		_shown_member(preview, channel) == score_member,
		"score %d, showing %d" % [score_member, _shown_member(preview, channel)])
	h.check("and leaves the channel's own hide standing",
		int(LingoValue.to_int(preview.call("lingo_sprite_prop", channel, "visible"))) == 0,
		"the visible of sprite %d reads %s" % [
			channel, str(preview.call("lingo_sprite_prop", channel, "visible"))])
	h.check("so the channel is still off the stage",
		not _channel_drawn(preview, channel))
	# Put it back, so a later reader of this state is not looking at the harness's
	# own hide. Through the same setter a movie would use, which is also the only
	# thing in Director that may lift one.
	preview.call("lingo_set_sprite_prop", channel, "visible", 1)


## Is `channel` drawn -- the question the painter and the hit test ask, which is
## `_channel_shown` **and** the channel's visibility. `_effective` answers `{}` for
## a hidden channel, and every path to the screen goes through it.
func _channel_drawn(preview: Node, channel: int) -> bool:
	for value in (preview.call("frame_sprites") as Array):
		var raw: Dictionary = value
		if int(raw["channel"]) != channel:
			continue
		return not (preview.call("_effective", raw) as Dictionary).is_empty()
	return false


## Is `channel` on the frame at all -- not "is it visible"?
##
## `frame_sprites` rather than the score's own list, because that is the
## difference this harness exists to measure: a whole-sprite puppet is on the
## frame whether or not the score's record for it is there.
func _channel_shown(preview: Node, channel: int) -> bool:
	for value in (preview.call("frame_sprites") as Array):
		if int((value as Dictionary)["channel"]) == channel:
			return true
	return false


## The member the *score* puts on `channel` on this frame, or 0.
func _score_member(preview: Node, channel: int) -> int:
	var score = preview.get("_score")
	if score == null:
		return 0
	for value in score.frame(int(preview.get("_index"))).get("sprites", []):
		var sprite: Dictionary = value
		if int(sprite["channel"]) == channel:
			return int(sprite["cast_id"])
	return 0


## The member `channel` is actually showing: the score plus whatever is puppeted.
func _shown_member(preview: Node, channel: int) -> int:
	for value in (preview.call("frame_sprites") as Array):
		var raw: Dictionary = value
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", raw, true)
		return 0 if live.is_empty() else int(live["cast_id"])
	return 0


## Drive the boot chain to `label` and write the state. Returns the path, or "".
##
## The chain, and not `--file`: `puppetSprite` is issued by the movie's own
## `init all`, so a room opened any other way carries no puppet claim at all and
## this would be asserting about a channel nothing has claimed. That is
## `bugs.md` 36's still-open half seen from the other side.
func _build(h: Harness, preview: Node, args: Dictionary, label: String,
		channel: int) -> String:
	var room := Args.text(args, "room", "PIP2DATA/DAY1.dir")
	preview.call("lingo_go_movie", Args.text(args, "via", "PIP2DATA/EXODUS.DIR"), null)
	for i in Args.number(args, "via-steps", 400):
		preview.call("_advance")
	preview.call("lingo_go_movie", room, null)
	await process_frame
	if not h.check("%s is playing" % room.get_file(),
			str(preview.call("movie_name")).to_lower() == room.get_file().to_lower(),
			str(preview.call("movie_name"))):
		return ""
	# The movie's own opening frame first -- `init all` is DAY1's, and it is what
	# issues the `puppetSprite` this is about -- then the room, then the room's
	# idle span, because a marker frame is the room's *entry* and the sprite a
	# player clicks is the one standing in the loop the entry falls into.
	await Escape.run_ticks(self, preview, Args.number(args, "settle", 60), 60000)
	preview.call("lingo_go_label", label)
	await Escape.run_ticks(self, preview, Args.number(args, "arrive", 24), 30000)
	var waited := 0
	while Escape.sprite_centre(preview, channel).x < 0.0 and waited < 40:
		await Escape.run_ticks(self, preview, 1, 5000)
		waited += 1
	var path: String = SaveFiles.directory(preview).path_join(
		"puppet_%s.json" % label.to_lower())
	var wrote: Dictionary = SaveFiles.save(preview, path)
	if not h.check("the state at %s was written" % label,
			str(wrote["error"]) == "", str(wrote["error"])):
		return ""
	return path
