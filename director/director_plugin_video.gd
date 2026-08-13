extends RefCounted
## The third video backend: a decoder **GDExtension**, used only if one is
## actually installed, and invisible when it is not.
##
## ## What this file is, and what it deliberately is not
##
## It is an **adapter**, not a decoder. Every byte of decoding happens inside a
## native extension this project does not ship, does not download and does not
## build; what is here is the twenty-odd lines that decide whether such an
## extension is present, hand it a path, and expose the same four numbers
## (`path`, `duration_ms`, `audio_*`) that `director/director_avi.gd` and
## `director/director_ogg.gd` expose, so that `scenes/preview/video.gd` can treat
## all three the same way.
##
## It is one file for a reason stated in the task that produced it: the plugin's
## API cannot be executed here — the extension is not installed and nothing may
## be downloaded — so parts of it are read from the project's source on the web
## and parts are *inference from Godot's own base classes*. Every inference is
## named below under "unverified". When one turns out wrong, the fix is in this
## file and nowhere else: `video.gd` never names a plugin class, never touches a
## `VideoStreamPlayback`, and never imports an addon path.
##
## ## Absence must change nothing, and how that is enforced
##
## `docs/DIGITAL_VIDEO.md` §4D refused a plugin on four grounds — licensing,
## size, per-ABI mobile builds and version coupling — and every one of them is
## still true of *installing* one. None of them is true of being **able** to use
## one, which is what this file adds. The rule that makes that safe is:
##
##   **Nothing here may reference an addon by path.** `preload("res://addons/…")`
##   of a script that is not there is a *parse* error in GDScript, and a parse
##   error in a file `video.gd` preloads takes the whole engine down before a
##   movie has opened — every gate entry and every title, over a decoder for one
##   unshipped test title. So the only questions asked are
##   `ClassDB.class_exists(...)` and `ClassDB.instantiate(...)`, both of which
##   answer honestly at run time for a class that was never registered, and
##   neither of which needs the addon to exist at parse time.
##
## With no extension installed `available()` is false, `open()` returns false
## with a named reason, and `preview/video.gd`'s resolution order falls through
## to exactly the two backends it had before this file was written.
## `tools/video_plugin.gd` asserts that, including the "no addon preload
## anywhere" rule, by reading the engine's own sources.
##
## ## What was confirmed from source, and what was not
##
## Read from EIRTeam.FFmpeg at commit `270e661` — the tree behind release asset
## `eirteam-ffmpeg-1.1.4.zip`, tagged `autobuild-2025-11-12-13-44` — via
## `raw.githubusercontent.com`. Reading text is not installing a binary; nothing
## was downloaded.
##
## **Confirmed:**
##
##   * `register_types.cpp` registers `FFmpegVideoStream` with `GDREGISTER_CLASS`
##     — a *concrete*, script-instantiable class — plus
##     `FFmpegVideoStreamPlayback` and `VideoStreamFFMpegLoader` as abstract.
##     So `ClassDB.class_exists("FFmpegVideoStream")` and
##     `ClassDB.instantiate("FFmpegVideoStream")` are the right two questions.
##   * `ffmpeg_video_stream.h`: `GDCLASS(FFmpegVideoStream, VideoStream)`, and it
##     declares **no** `set_file`/`get_file` of its own — it relies on the
##     `VideoStream` base class, whose `file` property is part of stock Godot's
##     scripting API. That is why `open()` below calls `set_file` and not some
##     plugin-specific loader entry point: the call is Godot's, not the addon's.
##   * `ffmpeg_video_stream.h`: `FFmpegVideoStreamPlayback` implements
##     `get_length`, `get_playback_position`, `seek`, `play`, `stop`,
##     `set_paused`, `is_paused`, `is_playing`, `update`, `get_texture`,
##     `get_mix_rate` and `get_channels`. Those are exactly the entry points
##     `VideoStreamPlayer` drives, which is why the existing Theora playback path
##     in `preview/video.gd` — `play()`, `paused`, `stream_position`,
##     `get_video_texture()` — works unchanged against this stream.
##   * `video_stream_ffmpeg_loader.cpp` registers a `ResourceFormatLoader` that
##     handles type `"VideoStream"` and whose recognised extensions come from
##     `av_demuxer_iterate()` — i.e. every container the linked FFmpeg build can
##     demux, MPEG-1 program streams included. `EXTENSIONS_FROM_LOADER` below
##     uses that.
##   * `gdextension_build/ffmpeg.gdextension`: entry symbol `ffmpeg_init`,
##     `compatibility_minimum = 4.1`, libraries under
##     `res://addons/ffmpeg/{win64,linux64,android,macos}/`, and **Android
##     `arm64` only** — no `arm32`, no `x86_64`. `docs/DIGITAL_VIDEO.md` §8
##     carries what that costs the mobile export.
##
## **Unverified, and isolated here:**
##
##   1. **That `VideoStreamPlayer.get_stream_length()` answers before `play()`.**
##      This is how `open()` learns `the duration of member`, and it is the one
##      number `docs/DIGITAL_VIDEO.md` §3 says must never be confidently wrong.
##      The reasoning: Godot's `VideoStreamPlayer::set_stream` instantiates the
##      playback immediately, and `get_stream_length()` forwards to
##      `VideoStreamPlayback::get_length()`, which the plugin implements from the
##      container header the demuxer already read. If that reasoning is wrong the
##      answer is 0, and **0 is refused** — `open()` returns false and the member
##      falls back to the sidecar, the AVI reader and then to nothing, which is
##      the behaviour that exists today. The failure mode of a wrong guess here
##      is therefore a clip that does not play, never a movie that hangs.
##   2. **That the sound track's rate and channel count cannot be read.** Godot's
##      `VideoStreamPlayer` exposes no accessor for either, and the plugin's are
##      on `VideoStreamPlayback`, which scripts cannot reach. So
##      `the sampleRate`, `the sampleSize` and `the channelCount of member`
##      answer 0 on this backend and `trackCount` counts the video track alone.
##      `director_ogg.gd` reads both out of the Vorbis identification header and
##      answers properly; there is no equivalent parse for an arbitrary
##      container, and inventing 44100 would be the kind of plausible answer §3
##      exists to forbid.
##   3. **That another plugin can be named rather than coded for.**
##      `EXTRA_CLASSES` reads a project setting, so an owner running GoZen,
##      `godot-mp4-player` or any other extension that registers a concrete
##      `VideoStream` subclass with a base-class `file` property can name its
##      class without touching this file. An extension shaped differently — one
##      whose player is a `Node` of its own rather than a `VideoStream` — is
##      **not** supported and cannot be made to work by naming it: `open()` type
##      checks what `ClassDB.instantiate` hands back and declines anything that
##      is not a `VideoStream`.
##
## ## Why the duration probe is a throwaway player
##
## `director_ogg.gd`'s header argues at length that the property surface must not
## be answered by asking the thing that plays the file, because "a decode is the
## port's input, not the original" and a duration that comes out of the player
## cannot be used to check the player. That argument stands and is why the Theora
## backend has a parser beside it.
##
## It cannot be honoured here, and saying so is better than pretending: there is
## no format to parse. The whole point of a decoder extension is that the formats
## behind it are open-ended, so a parser that answered `the duration` for all of
## them would be the decoder this file exists to avoid writing. The probe is
## therefore the honest arrangement — and the check that keeps it safe is not an
## independent parse but a refusal: a duration that does not come back positive
## is treated as "this file did not open".

## Which playback path `preview/video.gd` drives this reader with. A **push**
## backend, like `director_ogg.gd`: Godot's `VideoStreamPlayer` owns the pictures
## and the sound, and this port corrects it towards `the movieTime` rather than
## reading a position out of it.
const BACKEND := "plugin"

## Concrete `VideoStream` subclasses this adapter knows how to drive, in the
## order they are tried.
##
## One entry, because one is all that has been read from source. A second name
## added on the strength of a README would be exactly the invented API the header
## refuses: a class that exists but does not take `set_file`, or whose playback
## does not implement `get_length`, would produce a member that reports ready
## with a duration of 0 — and `docs/DIGITAL_VIDEO.md` §3 is the account of what
## that costs. `EXTRA_CLASSES_SETTING` is how a second one arrives without a code
## change and without this table making a claim it cannot support.
const CLASSES := [
	# EIRTeam.FFmpeg, MIT, wrapping an FFmpeg build. Confirmed concrete and
	# `VideoStream`-derived at commit 270e661 (release 1.1.4); see the header.
	"FFmpegVideoStream",
]

## A project setting naming further classes to try, comma-separated, so that an
## owner running a different extension is not blocked on this file being edited.
##
## Deliberately a setting rather than a scan of every `VideoStream` subclass in
## `ClassDB`: a scan would pick up Godot's own `VideoStreamTheora` and hand it
## every MPEG-1 file in the corpus, which fails *after* reporting the member
## ready — the one shape that turns a clean skip into a hang.
const EXTRA_CLASSES_SETTING := "director/video/extra_stream_classes"

## Container extensions this adapter will offer to a decoder extension when the
## installed loader does not enumerate its own.
##
## Not consulted at all when `ResourceLoader` answers, which for EIRTeam.FFmpeg
## it does — its loader reports every extension `av_demuxer_iterate()` yields.
## This list is the floor for an extension whose loader is registered differently
## or not at all, and it holds the Director-era containers plus the modern ones a
## replacement disc might arrive with.
##
## **`ogv` is deliberately absent.** Stock Godot decodes Theora with no
## extension at all, and the sidecar cache is full of `.ogv`; letting a plugin
## claim that extension would move a working path onto an untested one for no
## gain. `preview/video.gd` reaches the plugin arm only for the *original* media
## a member names, and no Director title on any disc names an `.ogv`.
const EXTENSIONS := [
	"mpg", "mpeg", "mpe", "m1v", "m2v", "mpv", "vob", "ps",
	"avi", "mov", "qt", "moov", "dv",
	"mp4", "m4v", "mkv", "webm", "wmv", "asf", "flv", "rm", "3gp",
]

var error: String = ""
var path: String = ""

var duration_ms: float = 0.0

## Zero on this backend, for unverified item 2 in the header: Godot exposes no
## script accessor for a video's sound track format, so 0 is what is known rather
## than a plausible guess. `preview/video.gd:fill_facts` turns `audio_rate == 0`
## into a track count of 1, which is the video track alone.
var audio_rate: int = 0
var audio_bits: int = 0
var audio_channels: int = 0

## The class that actually opened this file, kept for the trace line and for
## `tools/video_plugin.gd`'s report. Empty until `open` succeeds.
var stream_class: String = ""

var _stream: VideoStream = null


# ================================================================== is it there


## Is a decoder extension installed right now?
##
## The whole of requirement 1. Asked through `ClassDB` and never through a file
## path, for the reason the header gives about `preload`. A run with no extension
## answers false here, and every caller's next line is the behaviour that existed
## before this file did.
static func available() -> bool:
	return installed_class() != ""


## The first known `VideoStream` class that is actually registered, or `""`.
##
## `ClassDB.class_exists` is true for a class the engine knows; `can_instantiate`
## is the second half and is what separates a concrete class from an abstract
## one. Both are asked, because a registered-but-abstract class would pass the
## first and return null from `instantiate` — which is a null dereference at the
## point the media is wanted rather than a decline at the point the question is
## asked.
static func installed_class() -> String:
	for name in _candidates():
		var wanted := str(name)
		if wanted == "":
			continue
		if ClassDB.class_exists(wanted) and ClassDB.can_instantiate(wanted):
			return wanted
	return ""


## `CLASSES` plus whatever the project setting names.
static func _candidates() -> Array:
	var out: Array = []
	out.append_array(CLASSES)
	if ProjectSettings.has_setting(EXTRA_CLASSES_SETTING):
		for name in str(ProjectSettings.get_setting(EXTRA_CLASSES_SETTING)).split(","):
			var trimmed := str(name).strip_edges()
			if trimmed != "" and not out.has(trimmed):
				out.append(trimmed)
	return out


## Would a decoder extension take this file, by its extension?
##
## **The class gate is asked first and this second**, in that order and never the
## other way round: with nothing installed the answer is false for every file in
## existence, so a corpus with no extension never even reaches the extension
## table. That ordering is what makes "absence changes nothing" a property of the
## control flow rather than of a table someone has to keep right.
##
## The list of extensions comes from the installed loader **when it publishes
## one**, and from `EXTENSIONS` only when it publishes nothing at all.
## `ResourceLoader.get_recognized_extensions_for_type("VideoStream")` returns the
## union over every registered loader that handles that type, and EIRTeam's is
## registered exactly that way, taking its own list from `av_demuxer_iterate()`.
##
## **The published list is used instead of `EXTENSIONS` rather than alongside
## it**, and that is the point of preferring it: it reflects the FFmpeg build
## that is actually linked, so a stripped build with no MPEG-1 demuxer declines
## `.mpg` here — one comparison, before any file is opened — instead of being
## handed the file and failing later. A union would throw that away, since
## `EXTENSIONS` names `mpg` unconditionally.
##
## `EXTENSIONS` is therefore the floor for an extension whose loader is
## registered differently or not at all, which is the case this file cannot
## observe and must not assume away.
static func handles(file_path: String) -> bool:
	if not available():
		return false
	var extension := file_path.get_extension().to_lower()
	if extension == "":
		return false
	var published := _loader_extensions()
	if published.is_empty():
		return EXTENSIONS.has(extension)
	for known in published:
		if str(known).to_lower() == extension:
			return true
	return false


## What `ResourceLoader.get_recognized_extensions_for_type("VideoStream")` answers
## on stock Godot with no extension installed.
##
## **Measured, and it is not just `ogv`.** On 4.7.1, headless, with this project's
## own `addons/` absent, the call answers `tres, res` and *not* `ogv` — the text
## and binary resource loaders handle every type there is, so they claim their own
## two extensions for `VideoStream` as they would for any other, and the Theora
## loader's `ogv` did not appear at all. `tools/video_plugin.gd` found this on its
## first run, by asserting that nothing but the stock set is claimed when nothing
## is installed; the constant was `["ogv"]` until then, which would have made
## `handles("x.res")` true the moment an extension was installed.
##
## `ogv` is kept in the list regardless. It is what stock Godot's Theora loader
## *is*, an installed extension claiming it would be claiming a format this port
## already plays through the sidecar cache, and the whole point of this list is to
## be "extensions nothing stock would have offered".
const STOCK_EXTENSIONS := ["ogv", "res", "tres", "scn", "escn"]


## Extensions the installed loaders claim for `VideoStream`, minus the ones stock
## Godot claims anyway.
##
## The subtraction is what makes the answer mean "what an extension added" rather
## than "what some loader somewhere will accept" — and without it this function
## would offer a decoder every `.res` and `.tres` in the project.
static func _loader_extensions() -> PackedStringArray:
	var out := PackedStringArray()
	for known in ResourceLoader.get_recognized_extensions_for_type("VideoStream"):
		if not STOCK_EXTENSIONS.has(str(known).to_lower()):
			out.append(str(known))
	return out


# ===================================================================== opening


## Open a media file through the installed decoder extension.
##
## False, with `error` set, for every one of: no extension installed, an
## extension that does not take this container, a file that is not there, a class
## that turned out not to be a `VideoStream`, and — the important one — a stream
## that opened but reports no duration.
##
## **A zero duration is a refusal and not a fact**, which is the same rule
## `director_ogg.gd:open` states and it is load-bearing for the same reason:
## `preview/video.gd` treats an opened reader as a member whose media is ready,
## and a ready member with a duration of 0 is exactly the state
## `docs/DIGITAL_VIDEO.md` §3 warns turns Magic Hat's one-tick skip into
## `go(the frame)` for ever. It is also the safety net under unverified item 1 in
## the header: if `get_stream_length()` does not answer before playback starts,
## this returns false and the member behaves as it does today.
func open(file_path: String) -> bool:
	error = ""
	path = file_path
	duration_ms = 0.0
	stream_class = ""
	_stream = null
	var wanted_class := installed_class()
	if wanted_class == "":
		error = "no decoder extension installed"
		return false
	if not handles(file_path):
		error = "%s does not take .%s" % [wanted_class, file_path.get_extension()]
		return false
	if not FileAccess.file_exists(file_path):
		error = "not found"
		return false
	var made: Variant = ClassDB.instantiate(wanted_class)
	if made == null or not (made is VideoStream):
		error = "%s is not a VideoStream" % wanted_class
		return false
	var stream: VideoStream = made
	# `set_file` is `VideoStream`'s own, not the plugin's — see the header. A
	# plugin whose stream needed a different call would fail the probe below and
	# be refused rather than half-opened.
	stream.set_file(file_path)
	var length := _probe_length(stream)
	if length <= 0.0:
		error = "%s opened %s and reports no duration" % [
			wanted_class, file_path.get_file()]
		return false
	_stream = stream
	stream_class = wanted_class
	duration_ms = length * 1000.0
	return true


## How long the stream is, in seconds, or 0.
##
## A `VideoStreamPlayer` created, asked and thrown away. It is never added to the
## tree and never played: Godot's `VideoStreamPlayer::set_stream` instantiates the
## playback inside the assignment, so the question can be asked and the node
## dropped in the same frame.
##
## Unverified item 1 in the header is this function. If the answer is 0 the
## caller refuses the file, so the cost of the guess being wrong is a clip that
## does not play rather than a member that lies about being ready.
##
## The stream is cleared before the node is freed rather than left to the
## destructor, because that is what releases the plugin's own file handle:
## `set_stream(null)` stops and unrefs the playback, and a probe that dropped a
## live playback on the floor would hold a handle on every clip a movie ever
## asked the duration of.
func _probe_length(stream: VideoStream) -> float:
	var probe := VideoStreamPlayer.new()
	probe.stream = stream
	var seconds := float(probe.get_stream_length())
	probe.stream = null
	probe.free()
	return seconds


## The `VideoStream` `preview/video.gd` should put on this channel's player.
##
## The same resource each time rather than a fresh one per channel: a
## `VideoStream` is a description of a file and `VideoStreamPlayer` instantiates
## its own playback from it, so two channels showing one clip get two decoders
## and one description — which is what Director's own arrangement is, one media
## and a playhead per sprite.
##
## Named identically on `director_ogg.gd`, and that is the seam: `video.gd`'s
## `_stream` asks the reader for a stream and never knows which backend answered.
func video_stream() -> VideoStream:
	return _stream


func backend() -> String:
	return BACKEND


## Drop the stream. The extension's own file handle goes with the playback the
## player owns, which `preview/video.gd:release` frees alongside this.
func close() -> void:
	_stream = null
