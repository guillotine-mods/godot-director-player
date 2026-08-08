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
## So the two assertions are one rule read from both ends:
##
## 1. a channel a script has `puppetSprite N, TRUE`'d is **still on the frame**
##    every tick, including frames whose score record for it is empty. Not "still
##    visible" -- a script may legitimately hide it -- but still *there*, because
##    a channel the score has dropped can never come back.
## 2. a channel it has *not* puppeted is back on **the score's** member once the
##    score has moved that channel, however recently a script wrote one -- and
##    the member the script wrote lasted longer than the tick it was written on.
##
## Each room says which of the two it actually proved. `exitforest3` into
## `dnzclicktalk` is where the score drops the puppeted channel; `veranda` into
## `tofclicktalk` is where it moves the un-puppeted one; neither exercises the
## other, and a check that proved nothing prints so rather than passing quietly.
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
	var swapped_away := false
	var score_moved := false
	var returned := false
	var held := 0
	var run := 0
	var began := int(preview.get("_ticks"))
	var start := Time.get_ticks_msec()
	var last := -1
	while int(preview.get("_ticks")) - began < Args.number(args, "ticks", 400) \
			and Time.get_ticks_msec() - start < 240000:
		await process_frame
		var now := int(preview.get("_ticks"))
		if now == last:
			continue
		last = now
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
	h.check("the clip wrote its own member over channel %d" % channel, swapped_away)
	h.check("and it lasted longer than the tick it was written on",
		not swapped_away or held > 1, "held for %d score tick(s)" % held)
	h.check("the clip returned to the frame it was entered from", returned,
		"stopped on f%d" % int(preview.get("_index")))
	# Both halves say when they proved nothing rather than passing on a vacuous
	# truth. `porting-fidelity-verification`: a green check nobody can attribute
	# is the shape that lets a fix look verified when it was never exercised.
	if returned and score_moved:
		h.check("channel %d is back on the score's member" % channel,
			_shown_member(preview, channel) == score_member,
			"score %d, showing %d" % [score_member, _shown_member(preview, channel)])
	elif returned:
		print("   the score never moved channel %d, so the write standing is" % channel
			+ " correct and this room does not test the release")
	if abandoned.is_empty():
		print("   the score carried every puppeted channel throughout, so this"
			+ " room does not test the persistence")
	return true


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
