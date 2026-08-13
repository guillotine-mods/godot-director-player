extends RefCounted
## Playing a digital video: one reader per member, one playhead per channel, and
## the picture the sprite draws this tick.
##
## `preview/media.gd` is the *property surface* — the ~40 names Director gives a
## time-based member and its sprite — and it is deliberately not this file. This
## is the half that moves: it opens the media behind a `#digitalVideo` member,
## advances `the movieTime` on the engine's clock, hands `sprite_art` the current
## frame, and plays the soundtrack. Splitting them that way is the same split
## Director has — `DigitalVideoCastMember` holds the decoder and `Channel` holds
## `_movieRate` / `_startTime` / `_stopTime` (`castmember/digitalvideo.cpp`,
## `channel.h`, ScummVM 805f259a) — and it is what keeps `media.gd` answerable
## with no decoder at all, which is still the state for QuickTime and MPEG-1.
##
## ## The one thing that must not regress
##
## `docs/DIGITAL_VIDEO.md` §3 states two rules, and this file is exactly the
## change they were written to guard against:
##
##   1. do not answer a confident `the duration` for a video whose media cannot be
##      opened, and
##   2. do not answer `getPlaybackEvent` at all.
##
## The second is untouched — the two MPEG-1 Xtra members are type 15, `is_media`
## is false for them, and nothing here can reach one. The first is now *earned*
## rather than avoided: `the duration` becomes non-zero only when a reader
## actually opened the file and read its headers, and it stays 0 for
## `logo.dir` #27 `prelogo`, whose `prelogo.avi` is not on the disc. A member with
## no media answers exactly what it answered before this file existed.
##
## And it is only half the bargain. Magic Hat's `Check avi` is
##
##     if sprite(3).movieTime >= FilmLen then QuitFilm() else go(the frame)
##
## which exits on the first tick while both sides are 0. Make `the duration` real
## and leave `the movieTime` frozen and that clean skip becomes an **infinite
## loop**, because the other arm is `go(the frame)`. So `advance` is not a
## refinement of this change, it is the other half of it, and
## `tools/video_fallback.gd` asserts the pair.
##
## ## Why the playhead moves on the engine tick and not on the score step
##
## `Score::update` gates the *playhead* on the frame clock and pumps everything
## time-based outside it; a video is one of those. Magic Hat's logo movie is the
## proof: `Check avi` runs `go(the frame)`, so the score sits on frame 4 for the
## whole ten seconds and takes no step that could carry the video forward. The
## same argument the port already makes for `idle` and for the timeout clock
## (`preview/frame_loop.gd:send_idle`) applies unchanged.
##
## ## What this does not do
##
##   * **No `directToStage`.** `logo` sets the bit, and Director's meaning of it
##     is "draw over everything, bypassing the stage's compositing". This port
##     draws the video as an ordinary sprite in its own channel, which for a
##     640x480 picture centred on an 800x600 stage with nothing above it is the
##     same pixels. A movie that puts artwork *over* a direct-to-stage video would
##     differ, and none in this tree does.
##   * **No controller bar, no `crop`, no `center`, no `scale`.** The flags are
##     decoded (`director_cast.gd`'s type-10 arm) and read back; only the picture
##     is stretched to the sprite's drawn size, which is what `crop = false`
##     means and is what this member asks for. Cropping to the sprite rect is the
##     other arm and is unexercised by this corpus.
##   * **No cue points and no `#text` tracks.** An AVI carries neither.
##   * **No frame dropping under load.** The frame shown is the one the playhead
##     is on, computed from the time, so a slow machine skips pictures rather than
##     falling behind the clock — which is the behaviour a movie polling
##     `the movieTime` needs.

const Avi := preload("res://director/director_avi.gd")
const LingoValue := preload("res://lingo/lingo_value.gd")

## The units `the movieTime` and `the duration` of a digital video are counted
## in. **600, always**, which is QuickTime's time scale and what the reference
## answers for `kTheTimeScale` regardless of what `the digitalVideoTimeScale` has
## been set to (`digitalvideo.cpp`, "quicktime defaults to 600 / happens
## irrespective of"). A sound member answers Director's 60-per-second tick
## instead, which is why `media.gd` carries the two apart.
const TIME_SCALE := 600

## Director's own rounding of a millisecond duration into time-scale units:
## `1 + ((ms * scale - 1) / 1000)`, which is `getMovieTotalTime()`. Ceiling
## rather than round, and it matters at exactly the place `Check avi` reads it —
## a duration rounded *down* is a duration the playhead reaches one frame before
## the picture ends.
static func to_units(ms: float) -> int:
	if ms <= 0.0:
		return 0
	return 1 + int((ms * TIME_SCALE - 1) / 1000.0)


static func to_ms(units: int) -> float:
	return float(units) * 1000.0 / TIME_SCALE


# ============================================================== opening the media


## The reader behind a member, opened once and kept, or null.
##
## Cached on the host beside the other media state, so it is rebuilt per movie
## (`preview/boot.gd`) exactly as `media_facts` is — a `(library, slot)` pair
## names a different member in another movie's casts and the two must never meet.
##
## **A failure is cached too**, as an entry whose reader is null. Retrying on
## every property read would re-open a missing file once per tick for as long as
## a movie polls `the mediaReady`, which is Magic Hat's `prelogo` exactly.
static func reader_for(host, where: Array, table) -> RefCounted:
	if host == null or host._host == null or table == null:
		return null
	var lib := int(where[0])
	var slot := int(where[1])
	var member: Dictionary = table.get_member(lib, slot)
	if str(member.get("type_name", "")) != "digitalVideo":
		return null
	var store: Dictionary = host._host.video_readers
	var wanted := _wanted_file(host, where, member)
	var key := "%d:%d" % [lib, slot]
	var entry: Dictionary = store.get(key, {})
	# Keyed by the filename as well as the member, because `the fileName of
	# member` is writable and Magic Hat writes it: `magichat.dir`'s album repoints
	# one member at twenty different clips. A cache that ignored the name would
	# hand back the first file for ever.
	if entry.get("wanted", null) == wanted:
		return entry.get("reader", null)
	var previous = entry.get("reader", null)
	if previous != null:
		previous.close()
	var reader = null
	var resolved := media_path(host, wanted)
	if resolved != "":
		var avi = Avi.new()
		if avi.open(resolved):
			reader = avi
		else:
			host._trace("video %s: %s" % [wanted, str(avi.error)])
	elif wanted != "":
		host._trace("video %s: not found" % wanted)
	store[key] = {"wanted": wanted, "reader": reader, "path": resolved}
	return reader


## The file a member is pointed at: what a script last wrote, else the link the
## cast record carries.
static func _wanted_file(host, where: Array, member: Dictionary) -> String:
	var written: Variant = null
	if host != null and host._host != null:
		var overrides: Dictionary = host._host.media_members
		var entry: Dictionary = overrides.get("%d:%d" % [int(where[0]), int(where[1])], {})
		written = entry.get("filename", null)
	if written != null:
		return str(written)
	return str(member.get("link_filename", ""))


## Where a media file named by a member actually is on disc.
##
## Director resolved a linked media file the way it resolved a linked movie —
## beside the movie that named it, then along the search path — so that is what
## this does, through the movie's own directory and the game root. It is
## deliberately **not** `DirectorPaths.resolve`: that index holds containers only
## (`.dir`, `.cst`, ...) and a `.avi` is not one, so asking it would answer "not
## found" for every video in existence.
##
## The member's own `link_directory` is not consulted and `director_cast.gd`'s
## type-10 arm says why: `logo.dir` records `G:\magic\logo`, an authoring
## machine's drive letter from 2002.
##
## Separators are normalised first. A Director path may be written with `:`
## (Mac), `\` (Windows) or `/`, and the same title mixes them — `AudioDirector`
## carries the same rule for sounds and the same measurement behind it.
static func media_path(host, name: String) -> String:
	if name == "":
		return ""
	var tail := name.replace(":", "/").replace("\\", "/")
	while tail.begins_with("/"):
		tail = tail.substr(1)
	if tail == "":
		return ""
	var here := ""
	if host != null and host._movie != null:
		here = str(host._movie.path).get_base_dir()
	var root := ""
	if host != null and host._paths != null:
		root = str(host._paths.root)
	var tries: Array[String] = []
	for base in [here, root]:
		if base == "":
			continue
		tries.append(base.path_join(tail))
		if tail.get_file() != tail:
			tries.append(base.path_join(tail.get_file()))
	for candidate in tries:
		if FileAccess.file_exists(candidate):
			return candidate
	# Case-insensitive fallback, for the reason `DirectorPaths` gives at its own
	# index: the disc ships `LOGO.AVI` and the Lingo spells it `logo.avi`, and a
	# case-sensitive filesystem turns a working desktop build into a title that
	# cannot find its own media.
	for base in [here, root]:
		if base == "":
			continue
		var hit := _case_insensitive(base, tail)
		if hit != "":
			return hit
	return ""


static func _case_insensitive(base: String, tail: String) -> String:
	var dir_part := tail.get_base_dir()
	var want := tail.get_file().to_lower()
	var where := base if dir_part == "" else base.path_join(dir_part)
	var dir := DirAccess.open(where)
	if dir == null:
		return ""
	for name in dir.get_files():
		if str(name).to_lower() == want:
			return where.path_join(str(name))
	return ""


## What the media says about itself, merged into `media.gd`'s facts record.
##
## Zero and FALSE when nothing opened, which is the whole of §3's first rule.
static func fill_facts(host, where: Array, table, facts: Dictionary) -> void:
	facts["time_scale"] = TIME_SCALE
	var reader = reader_for(host, where, table)
	if reader == null:
		return
	facts["ready"] = true
	facts["duration"] = to_units(reader.duration_ms)
	# One video track, and one sound track when the file has audio this reader can
	# turn into samples. `trackCount(sprite N)` is asked of both.
	facts["tracks"] = 1 + (1 if reader.audio_rate > 0 else 0)
	facts["sample_rate"] = reader.audio_rate
	facts["sample_size"] = reader.audio_bits
	facts["channels"] = reader.audio_channels


# ================================================================== the playhead


## Step every playing video by real time. Called once per engine tick.
##
## **Not once per score step**, and the header says why: the movie that needs
## this is standing still on `go(the frame)` while it waits for the video, so a
## playhead carried by the step would never move and the wait would never end.
##
## `delta` is the same scaled delta the frame loop hands the clock, so the
## fast-forward key speeds a video up with everything else rather than leaving
## one sprite running at wall-clock speed inside a movie that is not.
static func advance(host, delta: float) -> void:
	if host == null or host._host == null or host._table == null:
		return
	var channels: Dictionary = host._host.media_channels
	if channels.is_empty():
		return
	for key in channels.keys():
		var channel := int(key)
		var state: Dictionary = channels[channel]
		var where := member_of_channel(host, channel)
		if where.is_empty():
			continue
		var reader = reader_for(host, where, host._table)
		if reader == null:
			# No media, so nothing moves — which is Director with an unloadable
			# video and is what makes `Check avi`'s `0 >= 0` exit rather than hang.
			continue
		var rate := float(state.get("rate", 0.0))
		if is_zero_approx(rate):
			_stop_audio(host, channel)
			continue
		var member: Dictionary = host._table.get_member(int(where[0]), int(where[1]))
		var total := to_units(reader.duration_ms)
		var stop := int(state.get("stop", 0))
		var last: int = stop if stop > 0 and stop < total else total
		# **The sub-unit remainder is carried, and that is not a nicety.** One time
		# scale unit is 1/600 s and an engine tick is about 1/60, so each tick is
		# worth ten units *and a fraction of one* -- and rounding that fraction away
		# every tick biases the clock by however far the frame rate is from a
		# divisor of 600. Measured before this line existed: `logo.avi` reached its
		# own 6,048-unit duration in **9.58 s** of wall clock instead of 10.08, a
		# 5% short play, because the process was turning over at about 61.7 fps and
		# each tick rounded 9.72 units up to 10. With the carry it lands within a
		# tick of the real length.
		var step := delta * rate * TIME_SCALE + float(state.get("frac", 0.0))
		var whole := int(floor(step))
		state["frac"] = step - whole
		var moved := int(state["time"]) + whole
		if moved >= last:
			if bool(member.get("looping", false)):
				# `the loop of member`. Rewound to the in point, which is what
				# `rewindVideo` does — `seekMovie(_channel->_startTime)` — and not
				# to zero, so a movie that trimmed the clip loops the trim.
				moved = int(state.get("start", 0))
				_start_audio(host, channel, reader, member, moved)
			else:
				# Clamped rather than run past, which is the reference's own
				# `MIN(ticks, getMovieTotalTime())` in `getMovieCurrentTime`. A
				# guard reading `>= the duration` must be able to become true, and
				# a playhead that overshot would make `the movieTime` report a
				# position the media does not have.
				moved = last
				_stop_audio(host, channel)
		elif moved < int(state.get("start", 0)):
			moved = int(state.get("start", 0))
		state["time"] = moved


## `[library, slot]` for whatever a channel is showing, or `[]`.
##
## The same read `media.gd:_member_of_channel` makes and for the same reason: a
## `puppetSprite` member swap is what the channel is actually showing. Public
## here because `advance` and the drawing path both need it and duplicating it is
## how the two would come to disagree about which member is playing.
static func member_of_channel(host, channel: int) -> Array:
	if host == null or channel <= 0:
		return []
	var lib: int = LingoValue.to_int(host.lingo_sprite_prop(channel, "castlibnum"))
	var slot: int = LingoValue.to_int(host.lingo_sprite_prop(channel, "membernum"))
	if slot <= 0:
		return []
	return [maxi(lib, 1), slot]


# ================================================================== the picture


## The frame a video sprite is showing, or null when it has no media.
##
## Null is the honest answer for a member whose file will not open, and it is the
## same answer `sprite_art.texture_for` gives for any type it cannot draw — so a
## video with no decoder draws nothing, which is what Director did with no codec
## installed and is `docs/DIGITAL_VIDEO.md` §5.3's whole argument.
##
## The texture is **updated in place** rather than recreated: `ImageTexture.update`
## re-uploads into the same GPU allocation, and a 640x480 RGBA texture recreated
## eleven times a second is eleven allocations a second the driver has to retire.
## Cached per channel and not in `host._textures`, which is keyed by
## (member, ink, size) and would hand back frame 0 for the whole movie.
static func texture_for(host, sprite: Dictionary, table, size: Vector2) -> Texture2D:
	if host == null or host._host == null:
		return null
	var lib := int(sprite.get("cast_lib", 0))
	var slot := int(sprite.get("cast_id", 0))
	var member: Dictionary = table.get_member(lib, slot)
	if str(member.get("type_name", "")) != "digitalVideo":
		return null
	var reader = reader_for(host, [maxi(lib, 1), slot], table)
	if reader == null:
		return null
	var channel := int(sprite.get("channel", 0))
	var state: Dictionary = host._host.media_channels.get(channel, {})
	var at_ms := to_ms(int(state.get("time", 0)))
	var index: int = reader.frame_index_at(at_ms)

	var store: Dictionary = host._host.video_frames
	var entry: Dictionary = store.get(channel, {})
	var wanted := Vector2i(maxi(int(size.x), 1), maxi(int(size.y), 1))
	if int(entry.get("frame", -1)) == index and entry.get("member", -1) == slot \
			and entry.get("size", Vector2i.ZERO) == wanted:
		return entry.get("texture", null)

	var image: Image = reader.frame_at(index)
	if image == null:
		return null
	# `the crop of member` is false for this corpus's member, which is Director's
	# "scale the picture to the sprite's rectangle". The sprite is 640x480 and so
	# is the media, so this is a no-op here and is written for the case where a
	# score stretched the sprite — the alternative, drawing at the media's own
	# size, would leave a stretched video sprite mis-sized and mis-hit-tested.
	if image.get_width() != wanted.x or image.get_height() != wanted.y:
		image.resize(wanted.x, wanted.y, Image.INTERPOLATE_BILINEAR)
	var texture: ImageTexture = entry.get("texture", null)
	if texture == null or texture.get_size() != Vector2(wanted):
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	store[channel] = {
		"frame": index, "member": slot, "size": wanted, "texture": texture,
	}
	return texture


# =================================================================== the sound


## The soundtrack, started when `the movieRate` goes non-zero and stopped when it
## returns to 0.
##
## On its own `AudioStreamPlayer` and **not** through a Director sound channel,
## which is Director's own arrangement: a digital video's audio belongs to the
## sprite, `the volume of sprite` attenuates it, and `sound stop 1` does not touch
## it. Routing it through `puppetSound` would make `soundBusy(1)` answer TRUE for
## the length of every video, and this corpus has 232 handlers that poll exactly
## that.
##
## Refused when `the sound of member` is off, which is the member's own tick box.
static func _start_audio(host, channel: int, reader, member: Dictionary,
		from_units: int) -> void:
	if not bool(member.get("sound", true)):
		return
	var player := _player(host, channel)
	if player == null:
		return
	# Keyed by the file the reader is on, not by "is there a stream": a member
	# whose `the fileName` was rewritten is a different soundtrack, and a player
	# that kept the first one would go on playing the previous clip's audio under
	# the new clip's pictures. Magic Hat's album repoints one member at twenty
	# files, which is the shape this is written for even though that member is an
	# Xtra and never reaches here.
	if player.stream == null or str(player.get_meta("avi_path", "")) != str(reader.path):
		var stream: AudioStreamWAV = reader.audio_stream()
		if stream == null:
			return
		player.stream = stream
		player.set_meta("avi_path", str(reader.path))
	var state: Dictionary = host._host.media_channels.get(channel, {})
	player.volume_db = linear_to_db(
		clampf(float(state.get("volume", 255)) / 255.0, 0.0001, 1.0))
	player.play(to_ms(from_units) / 1000.0)


static func _stop_audio(host, channel: int) -> void:
	var players: Dictionary = host._host.video_players
	var player = players.get(channel, null)
	if player != null and is_instance_valid(player) and player.playing:
		player.stop()


static func _player(host, channel: int) -> AudioStreamPlayer:
	var players: Dictionary = host._host.video_players
	var existing = players.get(channel, null)
	if existing != null and is_instance_valid(existing):
		return existing
	var player := AudioStreamPlayer.new()
	player.name = "VideoAudio%d" % channel
	host.add_child(player)
	players[channel] = player
	return player


## Called when `the movieRate` is written, so the soundtrack starts and stops with
## the picture rather than on the next tick.
##
## `media.gd:write_sprite` is the one caller: the rate is the only property that
## decides whether anything is playing, and hanging the transition off `advance`
## instead would put up to one engine tick of silence at the start of every clip.
static func rate_written(host, channel: int, rate: float) -> void:
	if host == null or host._host == null or host._table == null:
		return
	var where := member_of_channel(host, channel)
	if where.is_empty():
		return
	var reader = reader_for(host, where, host._table)
	if reader == null:
		return
	if is_zero_approx(rate):
		_stop_audio(host, channel)
		return
	var state: Dictionary = host._host.media_channels.get(channel, {})
	_start_audio(host, channel, reader,
		host._table.get_member(int(where[0]), int(where[1])),
		int(state.get("time", 0)))


## Drop every reader, texture and player. Called when the movie changes, because
## the caches are keyed by (library, slot) and those name different members in
## the next movie's casts.
static func release(host) -> void:
	if host == null or host._host == null:
		return
	for entry_value in host._host.video_readers.values():
		var entry: Dictionary = entry_value
		var reader = entry.get("reader", null)
		if reader != null:
			reader.close()
	host._host.video_readers.clear()
	host._host.video_frames.clear()
	for player_value in host._host.video_players.values():
		if player_value != null and is_instance_valid(player_value):
			(player_value as Node).queue_free()
	host._host.video_players.clear()
