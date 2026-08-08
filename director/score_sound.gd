extends RefCounted
## The score's own sound channels: what a frame asks for, and when that restarts.
##
## Director's score has two sound channels below the sprites, each naming a cast
## member per frame, and puppet channels above them. The rule that makes them
## usable is **restart-on-change**: a frame naming the same member as the frame
## before it leaves the sound alone, and a frame naming a *different* one starts
## the new one. Restarting every frame stutters a sound held across a span;
## never restarting misses a genuine re-trigger of the same sound two spans
## apart. D6 compares against the previous frame explicitly, which is what this
## does; earlier versions restart more eagerly.
##
## A channel `puppetSound` has claimed is not the score's to drive, and it stays
## claimed until the script hands it back — `puppetSound <n>, 0`. That is the
## same ownership rule `puppetSprite` has for a sprite channel, and it is kept
## here rather than in the host so that both renderers get it from one place.
##
## Held per movie, not per frame: the comparison is against the frame before, so
## a movie change has to forget what the last movie's channels held or the first
## frame of the new one compares against a stranger and stays silent.
##
## **Unexercised by the corpus this port was built on**, which has no sound cast
## member in any of its 86 containers and never writes either score sound channel
## in any of its 61,371 frames (`tools/sound_survey.gd`). The semantics are the
## reference's; `tools/score_sound_check.gd` drives them against a stub so the
## state machine is proved even though the game cannot prove it.

## channel -> "<lib>:<member>" the score last put there. Absent means silent.
var _score_source: Dictionary = {}
## channel -> true while a script owns it.
var _puppeted: Dictionary = {}


## Forget everything. Called on a movie change: channel state is per movie, and
## comparing the first frame of a new movie against the last frame of the old one
## is how a room opens silent.
func reset() -> void:
	_score_source.clear()
	# Puppet claims deliberately survive nothing: Director tears down puppets on
	# a movie change, and a claim that outlived its movie would mute the new
	# one's score channel with no script left to release it.
	_puppeted.clear()


## `puppetSound <channel>, <member>` claims a channel; `puppetSound <channel>, 0`
## and `puppetSound 0` give it back.
func set_puppet(channel: int, claimed: bool) -> void:
	if claimed:
		_puppeted[channel] = true
		return
	_puppeted.erase(channel)
	# Releasing does not restore what the score had — it forgets it, so the next
	# frame that names a member is a *change* and plays. Director hands the
	# channel back to the score at the next frame rather than resuming mid-sound,
	# and remembering the old source here would suppress exactly that restart.
	_score_source.erase(channel)


func is_puppeted(channel: int) -> bool:
	return bool(_puppeted.get(channel, false))


## Both dictionaries, for a save state.
##
## The puppet claims matter more than they look: a channel a script claimed and
## has not handed back is a channel the score may not drive, and a save that
## dropped the claim would have the next frame's sound cell start a sound the
## script had taken ownership of -- which is a sound arriving over a line of
## speech, with nothing in the log to say why.
##
## The score sources matter for the other half of the same rule: restart-on-change
## compares this frame against the frame before, so a restore with an empty table
## treats every channel as changed and re-triggers whatever the frame names.
func state() -> Dictionary:
	var sources: Dictionary = {}
	for channel in _score_source:
		sources[str(channel)] = str(_score_source[channel])
	var claimed: Array = []
	for channel in _puppeted:
		claimed.append(int(channel))
	claimed.sort()
	return {"sources": sources, "puppeted": claimed}


func restore_state(from: Dictionary) -> void:
	_score_source.clear()
	_puppeted.clear()
	if from.is_empty():
		return
	for channel in (from.get("sources", {}) as Dictionary):
		_score_source[int(str(channel))] = str((from["sources"] as Dictionary)[channel])
	for channel in (from.get("puppeted", []) as Array):
		_puppeted[int(channel)] = true


## What this frame changes, as `[{channel, cast_lib, cast_id}]` to start and
## `[channel]` to stop. The caller resolves members and drives the mixer; keeping
## the decision separate from the playing is what lets a harness assert the rule
## without an audio device.
##
## `channels` is `DirectorScore.frame(i)["sound_channels"]`.
func changes(channels: Array) -> Dictionary:
	var start: Array[Dictionary] = []
	var stop: Array[int] = []
	var named: Dictionary = {}

	for entry_value in channels:
		var entry: Dictionary = entry_value
		var channel := int(entry.get("channel", 0))
		if channel <= 0:
			continue
		named[channel] = true
		if is_puppeted(channel):
			continue
		var source := "%d:%d" % [int(entry.get("cast_lib", 1)), int(entry.get("cast_id", 0))]
		if str(_score_source.get(channel, "")) == source:
			continue
		_score_source[channel] = source
		start.append(entry)

	# A channel the score was driving and this frame does not name is silenced.
	# Not the same as "leave it alone": an empty sound cell in Director ends the
	# sound at the end of the span that held it, which is what makes a score
	# sound stop without a script.
	for channel in _score_source.keys():
		if named.has(channel) or is_puppeted(int(channel)):
			continue
		_score_source.erase(channel)
		stop.append(int(channel))

	return {"start": start, "stop": stop}
