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
## ## The second backend: an Ogg Theora sidecar, for the media nothing here can
## ## decode
##
## `docs/DIGITAL_VIDEO.md` §1 counts 22 MPEG-1 files, 197.3 MB, behind the two
## `VisibleLightOnStageMedia` Xtra members (cast type 15) that Magic Hat's intro
## and album are built on. §4C2 costs an MPEG-1 decoder in GDScript at 2.5
## Mpix/s of IDCT and refuses it; §4D refuses a plugin because it is a per-ABI
## native dependency and a licensing decision. What is left is §4B, a transcode,
## and this file is the half of it that runs at play time.
##
## The rule is one sentence: **the member names its media; if a decodable copy of
## that media exists and is at least as new as it, play the copy; otherwise do
## exactly what this file did before.** `director/director_sidecar.gd` owns where
## the copy lives (under `user://`, never under `games/` or `test-games/`) and
## `director/director_ogg.gd` reads what it says about itself.
##
## Three properties of that rule are the ones worth defending:
##
##   * **A missing sidecar is not an error.** `fresh_for` answers `""` for
##     absent, stale, and for a source that is not on the disc at all, and every
##     one of those falls through to the AVI reader and then to `null`. Nothing
##     is transcoded on demand, nothing is downloaded, and a corpus with no cache
##     behaves byte for byte as it did before this paragraph was written — which
##     is what keeps `tools/video_fallback.gd` green on a fresh machine.
##   * **The original is still what the engine reads.** The container, the cast
##     member, the member's own `the fileName` / `the mediaFilename` and the
##     resolution of that name against the disc are all unchanged; the
##     substitution is of the *media stream* alone, at the point where Director
##     would have handed the bytes to a codec it did not have. `prelogo` still
##     has no media, because its source file was never shipped.
##   * **The sidecar is consulted before the AVI reader, not instead of it.**
##     For the one MS-RLE file in the tree there is no sidecar and never needs to
##     be one, so `logo.avi` goes on being decoded from the original bytes. A
##     sidecar for a file this port *can* decode is the owner deliberately
##     overriding that, and doing what they asked is the right answer to it.
##
## ## The third backend: a decoder GDExtension, if one is installed
##
## The owner has since said plainly that the transcode route is not what they
## want, and `docs/DIGITAL_VIDEO.md` §8 is option D becoming real: when a decoder
## extension registering a `VideoStream` subclass is installed, the 22 MPEG-1
## files play from the original bytes and nothing is transcoded at all.
##
## **The entire feature is conditional on a class existing at run time**, and the
## condition is asked with `ClassDB.class_exists`, never with a `preload` of an
## addon path — a `preload` of a script that is not there is a *parse* error, and
## a parse error in a file this one preloads takes the engine down before a movie
## opens, for every title and every gate entry. `director/director_plugin_video.gd`
## is the adapter, it is the only file that names a plugin class, and its header
## separates what was read from the plugin's source from what is inference.
##
## With nothing installed the arm declines in one comparison and the resolution
## order below is byte for byte the one that existed before it, which is what
## `tools/video_plugin.gd` asserts.
##
## ## Three backends, one playhead
##
## The AVI reader is a **pull** decoder: `frame_at(n)` returns a picture and the
## soundtrack is one `AudioStreamWAV` on an `AudioStreamPlayer` this file drives.
## Theora and the plugin are **push** decoders: Godot's `VideoStreamPlayer` owns
## the clock, the pictures and the audio, and hands back a texture that changes
## under it. The two push backends differ only in where the `VideoStream` comes
## from — the `ResourceLoader` for a sidecar, `ClassDB.instantiate` for the
## plugin — and each reader answers `video_stream()` for its own, so `_stream`
## below has no backend test in it.
##
## `the movieTime` is computed the same way for both regardless — from the
## engine's own scaled delta, in `advance` — and the Theora player is *corrected*
## towards it rather than read from. That is not an accident of implementation:
## every guard in this corpus reads `the movieTime`, so a port where the number's
## meaning depended on which file format the member happened to point at would
## have two behaviours for one property. It also keeps the fast-forward key
## working, since `advance` gets the scaled delta and a `VideoStreamPlayer` does
## not.
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
const Ogg := preload("res://director/director_ogg.gd")
## The plugin **adapter**, which is a file in this repository and is always
## present; the decoder extension it looks for is not preloaded, is not named by
## path, and may be absent. That distinction is the whole of requirement 1 —
## see the adapter's header.
const Plugin := preload("res://director/director_plugin_video.gd")
const Sidecar := preload("res://director/director_sidecar.gd")
const VideoXtra := preload("res://director/director_video_xtra.gd")
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
	if not VideoXtra.is_video(member):
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
	# The channel's own player belongs to whatever was playing; a member repointed
	# at another file is another movie and must not go on showing the last one's
	# pictures. Released here rather than in `_open`, because this is the one
	# place that knows the file changed.
	_release_stream(host, _channel_showing(host, lib, slot))
	var reader = _open(host, wanted)
	store[key] = {
		"wanted": wanted, "reader": reader,
		"path": "" if reader == null else str(reader.path),
	}
	return reader


## The resolution order, in the order it is tried, and it is the whole of the
## sidecar feature at play time.
##
##   1. the member's own name, resolved against the disc the way Director
##      resolved a linked media file (`media_path`);
##   2. the original bytes through a **decoder GDExtension**, if one is installed
##      and it takes this container (`director_plugin_video.gd`);
##   3. a **fresh Ogg Theora sidecar** for that file, if the cache has one
##      (`director_sidecar.gd:fresh_for`, which answers `""` for absent, stale,
##      and for a source that is not on the disc at all);
##   4. the original bytes through the MS-RLE AVI reader;
##   5. nothing.
##
## Step 5 is not a failure path bolted on the end — it is the behaviour every one
## of Magic Hat's video frames is written against, and `docs/DIGITAL_VIDEO.md` §2
## measures all three of them leaving cleanly because of it. So each step that
## declines says why through `host._trace` and moves on, and none of them raises.
##
## **The plugin is tried before the sidecar, and the sidecar still exists.** The
## order is deliberate in both directions. Before, because the plugin plays the
## *original* media and the sidecar plays a copy, and the engine's stated premise
## is that it reads the original containers at run time — an owner who installs a
## decoder is asking for exactly that, and a cache entry left over from an
## experiment should not quietly override it. Still there, because it works, it
## costs nothing to keep, and a user who has already spent an afternoon of ffmpeg
## on 197 MB should not lose it the day a plugin lands. With no extension
## installed step 2 is one `ClassDB.class_exists` that answers false, and steps 3
## to 5 are the file as it stood.
##
## **A sidecar that will not parse is a decline, not a substitution.**
## `director_ogg.gd:open` refuses a file with no last granule position, which is
## what a truncated or still-being-written transcode has, and this then falls
## through to the AVI reader and to null exactly as if the cache were empty. A
## half-written sidecar therefore costs a skip, which is the state the movie
## already handles, rather than a member that reports ready and never advances.
##
## The plugin arm follows the same rule and `director_plugin_video.gd:open`
## enforces it: a stream that opens but reports no duration is refused, because a
## reader that comes back from here makes the member answer `the mediaReady` TRUE
## and a member that is ready with a duration of 0 is the hang
## `docs/DIGITAL_VIDEO.md` §3 is about.
static func _open(host, wanted: String):
	if wanted == "":
		return null
	var resolved := media_path(host, wanted)
	if resolved == "":
		host._trace("video %s: not found" % wanted)
		return null
	if Plugin.available():
		var plugin = Plugin.new()
		if plugin.open(resolved):
			host._trace("video %s: playing through %s (%.2fs)" % [
				wanted, plugin.stream_class, plugin.duration_ms / 1000.0])
			return plugin
		# Named rather than silent, and this is the line that separates "no
		# extension installed" from "the extension declined this file" — two
		# states that look identical from the movie's side and want completely
		# different answers from whoever is reading the trace.
		host._trace("video %s: %s" % [wanted, str(plugin.error)])
	var sidecar := Sidecar.fresh_for(resolved)
	if sidecar != "":
		var ogg = Ogg.new()
		if ogg.open(sidecar):
			host._trace("video %s: playing sidecar %s (%.2fs)" % [
				wanted, sidecar.get_file(), ogg.duration_ms / 1000.0])
			return ogg
		host._trace("video %s: sidecar %s unusable: %s" % [
			wanted, sidecar.get_file(), str(ogg.error)])
	var avi = Avi.new()
	if avi.open(resolved):
		return avi
	# Named rather than silent, and this is the line a reader follows when a clip
	# does not play: an MPEG-1 file reports the AVI reader's "not a RIFF file",
	# which is correct and is the cue to install a decoder extension
	# (`docs/DIGITAL_VIDEO.md` §8) or to run `tools/video_sidecar.gd`. Which of
	# the two is missing is stated rather than left to be inferred, because the
	# whole point of having three backends is that "it did not play" is now three
	# different diagnoses.
	host._trace("video %s: %s (decoder extension: %s; no sidecar in %s)" % [
		wanted, str(avi.error),
		Plugin.installed_class() if Plugin.available() else "none installed",
		Sidecar.CACHE_DIR])
	return null


## Which channel, if any, is currently showing a given member — so that a
## `mediaFilename` write can release that channel's player.
##
## Answered from the playhead table rather than by walking the score, because a
## channel only has a playhead once something drove it, and those are exactly the
## channels that can be holding a stream.
static func _channel_showing(host, lib: int, slot: int) -> int:
	if host == null or host._host == null:
		return 0
	for key in host._host.media_channels.keys():
		var where := member_of_channel(host, int(key))
		if where.size() == 2 and int(where[0]) == lib and int(where[1]) == slot:
			return int(key)
	return 0


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
##
## ## An already-absolute name is taken as one, and that is not a special case
##
## **This function silently mangled every path a script built from `the
## moviePath`**, which is how Magic Hat names all 22 of its MPEG-1 clips:
##
##     member("IntroRetroVideo").mediaFilename = the moviePath & Language() & "\mainmenu\intro.mpg"
##
## `the moviePath` answers `res://test-games/itamar-magichat/` here, so the name
## arrives as `res://test-games/itamar-magichat/heb\mainmenu\intro.mpg` — and the
## Mac-separator rule below turns *every* colon into a slash, including the one
## in `res://`. The result was `res///test-games/...`, joined onto the movie's own
## directory, and no candidate existed. Measured after the sidecar landed and the
## intro still would not play: the member's write was stored correctly, the file
## was on the disc, the sidecar was in the cache, and this line was the only
## reason the reader came back null.
##
## The type-10 member never showed it because `logo.dir` writes a bare
## `"prelogo.avi"`, which has no colon in it and no absolute prefix — so the one
## sample this function had been measured against was the one shape that cannot
## reach the bug.
static func media_path(host, name: String) -> String:
	if name == "":
		return ""
	# Godot's own prefixes and a Windows drive letter, recognised **before** the
	# colon is normalised away. A name that already says where it is needs no
	# search: Director resolved an absolute path by using it, and joining it onto
	# the movie's directory would produce a path that cannot exist.
	var direct := _absolute(name)
	if direct != "":
		return direct
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


## The file an already-absolute name points at, or `""` when the name is not
## absolute or the file is not there.
##
## Three spellings count as absolute, and no more: Godot's `res://` and `user://`
## — which is what `the moviePath` and `the pathName` answer in this port — and a
## Windows drive letter. A bare leading `/` is deliberately **not** one, because
## a Mac Director path (`Disk:folder:file`) normalises into exactly that shape
## and is a *relative* name once the volume is dropped, which is what the search
## below is for.
##
## The case-insensitive retry is the same rule the relative search uses and is
## here for the same measured reason: a disc that ships `INTRO.MPG` and a script
## that spells `intro.mpg` work on Windows and fail on Linux, and the port is
## meant to run on both.
static func _absolute(name: String) -> String:
	var normal := name.replace("\\", "/")
	var is_godot := normal.begins_with("res://") or normal.begins_with("user://")
	var is_drive := normal.length() >= 3 and normal[1] == ":" and normal[2] == "/"
	if not is_godot and not is_drive:
		return ""
	if FileAccess.file_exists(normal):
		return normal
	return _case_insensitive(normal.get_base_dir(), normal.get_file())


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
	var member: Dictionary = table.get_member(int(where[0]), int(where[1]))
	# The name the *member* carries, kept beside the decoded numbers so that the
	# type below is decided by what the movie asked for. A member playing a
	# sidecar is still a member that named `intro.mpg`.
	facts["wanted_file"] = _wanted_file(host, where, member)
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
	# `the digitalVideoType`, decided by what the **member named** rather than by
	# what is actually being decoded. That distinction only exists once a sidecar
	# can be playing, and answering from the sidecar would be this port telling a
	# movie its QuickTime clip is an Ogg file — a format Director had no symbol
	# for and no script can have been written against. `#videoForWindows` for an
	# AVI, `#quickTime` for a QuickTime container, and `#other` for everything
	# else, which is Director's own third value and is what it answered for a
	# video it could not identify. See `media.gd`'s own arm for why the file's
	# extension is a better witness than the member's flag word.
	facts["dv_type"] = _declared_type(str(facts.get("wanted_file", "")))


## `#videoForWindows`, `#quickTime` or `#other`, from the extension of the file
## the member named.
##
## Director's three answers, and the third is not a fallback for "we did not
## look" — it is the value it gave for a video whose type it could not
## establish, which is the honest answer for an MPEG-1 stream played through an
## Xtra that owned its own format.
static func _declared_type(wanted: String) -> StringName:
	match wanted.get_extension().to_lower():
		"avi":
			return &"videoForWindows"
		"mov", "qt", "moov":
			return &"quickTime"
	return &"other"


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
			# A `VideoStreamPlayer` is paused rather than stopped, because Director's
			# `the movieRate` of 0 is a pause: the playhead keeps its position and a
			# later non-zero rate resumes from it. `stop()` in Godot rewinds to the
			# start, which would make `sprite(N).stop()` followed by `play()` restart
			# the clip -- and Magic Hat's album loop does exactly that pair.
			_pause_stream(host, channel, true)
			continue
		_pause_stream(host, channel, false)
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
				_begin_media(host, channel, reader, member, moved)
			else:
				# Clamped rather than run past, which is the reference's own
				# `MIN(ticks, getMovieTotalTime())` in `getMovieCurrentTime`. A
				# guard reading `>= the duration` must be able to become true, and
				# a playhead that overshot would make `the movieTime` report a
				# position the media does not have.
				moved = last
				_stop_audio(host, channel)
				# The last picture stays on the stage, which is what Director
				# leaves when a video reaches its end without looping — and what
				# `getPlaybackEvent` reports as finished on the next poll.
				_pause_stream(host, channel, true)
		elif moved < int(state.get("start", 0)):
			moved = int(state.get("start", 0))
		state["time"] = moved
		# The Theora backend's own clock is Godot's and runs on wall time; this
		# one is the engine's and runs on the scaled delta. They agree until the
		# process drops frames or the fast-forward key is held, and then they do
		# not. `the movieTime` stays the authority and the player is nudged back
		# to it, which is the only arrangement where the number a script reads and
		# the picture a player sees are the same position.
		_sync_stream(host, channel, reader, moved)


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
	if not VideoXtra.is_video(member):
		return null
	var reader = reader_for(host, [maxi(lib, 1), slot], table)
	if reader == null:
		return null
	var channel := int(sprite.get("channel", 0))
	if _is_push(reader):
		return _stream_texture(host, channel, reader,
			Vector2i(maxi(int(size.x), 1), maxi(int(size.y), 1)))
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


# ================================================== the two push backends
#
# One `VideoStreamPlayer` per channel, off screen, driven by this file, for
# **both** the Theora sidecar and the decoder extension.
#
# ## Why Godot's node and not a decoder here
#
# Theora is a transform codec — the same shape of problem as MPEG-1, and
# `docs/DIGITAL_VIDEO.md` §4C2 is right that GDScript cannot do one at 2.5
# Mpix/s. The difference is that Godot already ships the decoder: `VideoStream`
# with an `.ogv` is the one video format stock Godot 4 plays with no addon, no
# GDExtension, no native code and no new dependency, which is the entire
# constraint this approach exists to satisfy. So the sidecar is not "a format we
# like better", it is *the* format the engine already has.
#
# ## Why the extension re-uses every line of it
#
# A decoder GDExtension of the shape §8 describes registers a `VideoStream`
# subclass, which means Godot's own `VideoStreamPlayer` drives it through exactly
# the four entry points used below — `play()`, `paused`, `stream_position`,
# `get_video_texture()`. Confirmed against EIRTeam.FFmpeg's
# `ffmpeg_video_stream.h` at commit 270e661, where `FFmpegVideoStreamPlayback`
# implements `play`, `stop`, `set_paused`, `is_playing`, `seek`, `get_length`,
# `get_playback_position` and `get_texture`. So the third backend cost this
# section nothing: only `_stream`'s first two lines differ, and they moved onto
# the readers as `video_stream()`.
#
# ## Why it is a hidden node rather than something drawn
#
# `VideoStreamPlayer` is a `Control` and draws itself where it sits. This port's
# stage is composited by `preview/stage_paint.gd` in channel order, so a video
# that painted itself would land outside that order — over everything, or under
# it, depending on tree position, and never in its own channel. The node is
# therefore hidden and used only as a decoder: `get_video_texture()` is the
# picture, and `preview/stage_paint.gd` draws it as an ordinary sprite.
#
# **Measured, because it is the assumption the whole backend rests on**: with
# `visible = false` and the engine started `--headless --audio-driver Dummy`, the
# player still advances and `get_video_texture()` still yields new frames —
# `tools/video_sidecar.gd`'s `--play` check reads pixels out of it. Godot drives
# playback from internal process notifications rather than from drawing, so
# hiding the node costs the decode nothing. Had that not held, the alternative
# was a node parked at a large negative offset, which works and is uglier.


## The `VideoStreamPlayer` a channel decodes on, created on first use.
##
## Under the preview node, so it dies with the movie exactly as the audio players
## do, and named per channel so a session's tree is readable when something has
## gone wrong.
static func _stream(host, channel: int, reader) -> VideoStreamPlayer:
	if host == null or host._host == null:
		return null
	var streams: Dictionary = host._host.video_streams
	var existing = streams.get(channel, null)
	if existing != null and is_instance_valid(existing) \
			and str((existing as Node).get_meta("stream_path", "")) == str(reader.path):
		return existing
	if existing != null and is_instance_valid(existing):
		(existing as Node).queue_free()
	# Asked of the **reader**, which is the seam between the two push backends: a
	# sidecar answers with `ResourceLoader.load(path, "VideoStream")` and the
	# plugin adapter with the class `ClassDB` named, and this function is not
	# allowed to know which. Before the plugin landed the `ResourceLoader` call
	# was inline here, and leaving it inline would have meant a backend test in
	# the one function whose whole job is to be backend-agnostic.
	var stream: VideoStream = reader.video_stream()
	if stream == null:
		# For Theora: the header parse said this is Theora and the loader
		# disagrees. For the plugin: the extension opened the file for the
		# duration probe and has nothing to hand over now. Either way it is
		# reported rather than retried, and the caller draws nothing — the same
		# clean skip a member with no media gets, arriving one step later.
		host._trace("video: %s did not yield a VideoStream (%s backend)" % [
			str(reader.path), str(reader.backend())])
		return null
	var player := VideoStreamPlayer.new()
	player.name = "VideoStream%d" % channel
	# Hidden for the reason the section header gives, and `expand` set so that the
	# node's own zero size cannot constrain the decode.
	player.visible = false
	player.expand = true
	player.stream = stream
	player.set_meta("stream_path", str(reader.path))
	host.add_child(player)
	streams[channel] = player
	return player


## Start, or resume, the stream behind a channel at a given playhead position.
static func _start_stream(host, channel: int, reader, member: Dictionary,
		from_units: int) -> void:
	var player := _stream(host, channel, reader)
	if player == null:
		return
	# `the sound of member` is the member's own tick box, and it is honoured by
	# muting rather than by refusing to play: the video track and the sound track
	# are one stream here, so "no sound" cannot be expressed by not starting it.
	var state: Dictionary = host._host.media_channels.get(channel, {})
	var level := clampf(float(state.get("volume", 255)) / 255.0, 0.0, 1.0)
	player.volume = 0.0 if not bool(member.get("sound", true)) else level
	if not player.is_playing():
		player.play()
	player.paused = false
	player.stream_position = to_ms(from_units) / 1000.0


## Hold the picture where it is without losing it, which is `the movieRate` of 0.
static func _pause_stream(host, channel: int, paused: bool) -> void:
	if host == null or host._host == null:
		return
	var player = host._host.video_streams.get(channel, null)
	if player != null and is_instance_valid(player):
		(player as VideoStreamPlayer).paused = paused


## Nudge the decoder back onto `the movieTime`, which is the authority.
##
## **Only when it has drifted past `SYNC_SLOP`**, and that threshold is the whole
## design of this function. Seeking a Theora stream costs a decode from the
## previous key frame, so correcting a two-millisecond difference every tick
## would re-decode a group of pictures sixty times a second and turn a 320x240
## clip into a stall. Half a frame at 25 fps is 20 ms and is invisible; a quarter
## of a second is not, and is what a dropped-frame burst or the fast-forward key
## produces. The slop is set between the two.
const SYNC_SLOP := 0.25


static func _sync_stream(host, channel: int, reader, at_units: int) -> void:
	if host == null or host._host == null or not _is_push(reader):
		return
	var player = host._host.video_streams.get(channel, null)
	if player == null or not is_instance_valid(player):
		return
	var want := to_ms(at_units) / 1000.0
	var stream_player := player as VideoStreamPlayer
	if not stream_player.is_playing():
		return
	if absf(stream_player.stream_position - want) > SYNC_SLOP:
		stream_player.stream_position = want


## The picture a Theora-backed channel is showing.
##
## The player's own texture is handed straight back when the sprite is drawn at
## the media's own size, which is every case in this corpus: the two Xtra members'
## `xtraRect`s are 352x288 and 320x240 and the MPEG-1 encodes behind them are
## 352x288 and 320x240, measured independently (`docs/DIGITAL_VIDEO.md` §1). No
## copy, no allocation, no per-frame work at all.
##
## A sprite stretched to some other size falls back to a resized copy, for the
## same reason the AVI path resizes: `preview/stage_paint.gd` draws a texture at
## its natural size, so a picture handed over unscaled would be drawn at the
## media's size inside a sprite rect of another, and the hit test — which uses the
## rect — would stop agreeing with the pixels. That path costs an `Image.resize`
## per frame and is unexercised here; it is written because a score is free to
## stretch a video sprite and a port that silently ignored it would be wrong in a
## way nothing reported.
static func _stream_texture(host, channel: int, reader, wanted: Vector2i) -> Texture2D:
	var player := _stream(host, channel, reader)
	if player == null:
		return null
	var texture := player.get_video_texture()
	if texture == null:
		return null
	if texture.get_size() == Vector2(wanted):
		return texture
	var image: Image = texture.get_image()
	if image == null:
		return null
	image.resize(wanted.x, wanted.y, Image.INTERPOLATE_BILINEAR)
	var store: Dictionary = host._host.video_frames
	var entry: Dictionary = store.get(channel, {})
	var scaled: ImageTexture = entry.get("texture", null)
	if scaled == null or scaled.get_size() != Vector2(wanted):
		scaled = ImageTexture.create_from_image(image)
	else:
		scaled.update(image)
	store[channel] = {"frame": -1, "member": 0, "size": wanted, "texture": scaled}
	return scaled


static func _release_stream(host, channel: int) -> void:
	if host == null or host._host == null or channel <= 0:
		return
	var player = host._host.video_streams.get(channel, null)
	if player != null and is_instance_valid(player):
		(player as Node).queue_free()
	host._host.video_streams.erase(channel)


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
## Start whichever kind of playback this channel's reader is — the one seam the
## two backends meet at.
##
## Written as a dispatcher rather than as a `backend()` test inside each of the
## two functions, because the call sites (`advance`'s loop rewind and
## `rate_written`) do not care which is which and a test duplicated into both
## halves is how one of them comes to be missing. `_start_audio` below would
## reach for `reader.audio_stream()` on a Theora reader, which does not have one
## — Godot's player owns that stream.
static func _begin_media(host, channel: int, reader, member: Dictionary,
		from_units: int) -> void:
	if _is_push(reader):
		_start_stream(host, channel, reader, member, from_units)
		return
	_start_audio(host, channel, reader, member, from_units)


## Does this reader hand its pictures to a `VideoStreamPlayer`, or does this file
## pull frames out of it?
##
## The one place the question is asked, so that a third push backend was a row
## here rather than three `==` comparisons in three functions that could come to
## disagree — which is exactly what the plugin backend would have found, since
## `advance`, `texture_for` and `_begin_media` each carried their own copy of the
## Theora test before it landed.
##
## Written against the backend names rather than against `has_method
## ("video_stream")`, because a reader that grew that method by accident would
## silently change which path it is driven down, and the failure would be a video
## that decodes into a texture nothing draws.
static func _is_push(reader) -> bool:
	if reader == null:
		return false
	var kind := str(reader.backend())
	return kind == Ogg.BACKEND or kind == Plugin.BACKEND


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
		_pause_stream(host, channel, true)
		return
	var state: Dictionary = host._host.media_channels.get(channel, {})
	_begin_media(host, channel, reader,
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
	# The Theora players go with them, and for a reason the audio players do not
	# have: each holds an open `.ogv` and a decoded frame buffer, and a
	# `go to movie` that left one behind would keep both for the session *and*
	# go on decoding a clip nothing can see.
	for stream_value in host._host.video_streams.values():
		if stream_value != null and is_instance_valid(stream_value):
			(stream_value as Node).queue_free()
	host._host.video_streams.clear()


# ============================================== the Xtra sprite, and its surface


## Draw a video **Xtra** sprite — cast type 15 with a video player's symbol.
##
## `preview/stage_paint.gd` calls this immediately after
## `director_preview.gd:_draw_video`, which is the same function for cast type
## 10. **They are two calls because this pass did not own that file**, not
## because the two member types want different treatment: everything below the
## type gate is shared, `texture_for` answers for both, and the right shape is
## one call whose gate is `VideoXtra.is_video`. Merging them is a two-line change
## the next session to touch `director_preview.gd` should make.
##
## True when the sprite was a video Xtra, whether or not a picture came out —
## the same contract `_draw_video` states, and for the same reason: the sprite
## *is* a video, so falling through would ask the cast for bitmap artwork a
## type-15 member does not have, and `sprite_art.texture_for` would answer null
## after doing the work of finding that out. A video Xtra with no sidecar
## therefore draws nothing and consumes the sprite, which is what Director did
## when the Xtra was not installed.
static func draw_xtra(host, sprite: Dictionary, table) -> bool:
	if host == null or table == null:
		return false
	var member: Dictionary = table.get_member(
		int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)))
	if not VideoXtra.is_xtra(member):
		return false
	var placed: Rect2 = host._stage_rect(sprite)
	var texture: Texture2D = texture_for(host, sprite, table, placed.size)
	if texture != null:
		host._draw_sprite_texture(texture, placed.position, sprite, Color(1, 1, 1, 1))
	return true


## `sprite(N).getPlaybackEvent` — the property Magic Hat's intro and album both
## poll, and the one `docs/DIGITAL_VIDEO.md` §3 forbids answering carelessly.
##
## ## The trap, restated because it is the whole of this function
##
## `BehaviorScript 134 - video intro retro loop` is:
##
##     if sprite(1).getplaybackevent <> 1 then QuitIntroRetro(1, 1) else go(the frame)
##
## and `BehaviorScript 38 - video loop` is the same shape on channel 25. **One of
## those two arms never ends.** `1` means "still playing, come back next tick",
## and every other value means "done, move on". So:
##
##   * answering 1 with nothing behind it is an infinite loop — the movie waits
##     for a video that will never finish, and the title is lost;
##   * answering anything else with a video genuinely playing cuts the clip off
##     on its first tick.
##
## The rule this implements is therefore: **1 only while there is real media,
## the rate is non-zero, and the playhead has not reached the end.** Every one of
## those three is a fact this file can check rather than assume, and the first is
## the one that keeps the no-sidecar case identical to the behaviour
## `tools/video_fallback.gd` asserts today.
##
## ## Why VOID and not 0 when there is no media
##
## VOID is what the name answered before it was bound to anything, and
## `VOID <> 1` is what all three of Magic Hat's video frames leave on today. `0`
## would take the same arm and look the same in these two movies — and would be
## a different value to `voidP()`, to `ilk()`, and to any handler in a title
## nobody has run yet that distinguishes "the Xtra is not installed" from "the
## Xtra says the clip has stopped". Director answers the former by not binding
## the name at all, so that is what an absent player answers here.
static func playback_event(host, channel: int) -> Variant:
	if host == null or host._host == null or host._table == null:
		return null
	var where := member_of_channel(host, channel)
	if where.is_empty():
		return null
	var reader = reader_for(host, where, host._table)
	if reader == null:
		return null
	var state: Dictionary = host._host.media_channels.get(channel, {})
	if is_zero_approx(float(state.get("rate", 0.0))):
		return 0
	var total := to_units(reader.duration_ms)
	var stop := int(state.get("stop", 0))
	var last: int = stop if stop > 0 and stop < total else total
	return 1 if int(state.get("time", 0)) < last else 0


## `sprite(N).play()` and `sprite(N).stop()` — the Xtra sprite's two commands.
##
## `play` rewinds to the in point and sets the rate to 1; `stop` sets the rate to
## 0 and leaves the playhead where it is. Both go through the same per-channel
## state `the movieRate` and `the movieTime` are stored in, so a movie that
## drives a clip with the commands and reads it back through the properties sees
## one playhead — which is the arrangement Director has, and the one a port
## breaks by giving the Xtra a private position.
##
## **`play` rewinds and `stop` does not**, and the asymmetry is the album's:
## `AlbumMenuObject.MenuMouseUp` repoints one member at a new clip and jumps to
## the `video` marker, and `BehaviorScript 38` calls `stop()` before leaving.
## A `play` that resumed from wherever the previous clip ended would start every
## clip after the first somewhere in the middle; a `stop` that rewound would make
## `the movieTime` after it report a position the player never saw.
static func command(host, channel: int, what: String) -> void:
	if host == null or host._host == null or host._table == null:
		return
	var state: Dictionary = host._host.media_channels.get(channel, {})
	if state.is_empty():
		return
	if what == "stop":
		state["rate"] = 0.0
		state["frac"] = 0.0
		rate_written(host, channel, 0.0)
		return
	state["time"] = int(state.get("start", 0))
	state["frac"] = 0.0
	state["rate"] = 1.0
	rate_written(host, channel, 1.0)
