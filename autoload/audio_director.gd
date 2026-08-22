extends Node
## Director's sound channels: `sound playFile`, `sound stop`, `soundBusy`,
## `the volume of sound N` and `the soundLevel`, over one `AudioStreamPlayer` per
## channel.
##
## Streams are decoded at runtime rather than imported, because the game's own
## files are read where they lie and Godot's importer has never seen them —
## `.aif` in this title, which Godot cannot load at all (`aiff_loader.gd`).
##
## This is the one place channel state lives. Both hosts route here, and the
## reason is that a channel outlives the movie that set it up: volume set in one
## room is still in force in the next, and `the soundLevel` is written in an
## options screen and read back somewhere else entirely. Two hosts each keeping
## their own copy is `docs/bugs-closed.md` 27 waiting to happen again.
##
## What the corpus asks of it, counted over `reference/lingo/`: 2,515
## `sound playFile`, 245 `soundBusy`, 69 `sound stop`, 67 lines naming
## `the volume of sound N` and 14 `the soundLevel`. Nothing calls `puppetSound`,
## `sound close`, `sound fadeIn` or `sound fadeOut`, and the score's own sound
## channels play nothing at all in *this* title. `tools/sound_survey.gd`.
##
## That last clause used to read "no cast in the game holds a `sound` member",
## which was true of Piposh 2 and false of the corpus: there are 204 sound cast
## members across the eight roots (`tools/sound_member_census.gd`), and 102 of
## them decode to real audio. Nothing here changes as a result — a member sound
## reaches these channels through the same `_start` — but the sentence was one of
## four saying the same wrong thing, so it is corrected rather than left to be
## quoted again.

## Director's default volume for a sound channel, and the range it is written in.
const VOLUME_MAX := 255
## `the soundLevel` is the *system* volume, 0-7, not a channel property — it is
## the Mac speaker setting Director exposed, and it multiplies whatever the
## channels are doing. 7 is the level a movie starts at.
const SOUND_LEVEL_MAX := 7

## Every path-tail of every file -> the file, so a request that carries part of a
## path is answered by that part rather than by the filename alone. `d1prom1`,
## `days/d1prom1` and `sounds/days/d1prom1` are three tails of one file and all
## three are keys; the bare filename is simply the shortest of them.
var _tail_index: Dictionary = {}
## Relative path (no extension) -> file on disc. The precise index.

var _path_index: Dictionary = {}

## Relative path **with** its extension -> file on disc. The exact index, and the
## one thing the stem index cannot answer.
##
## `_path_index` drops the extension on purpose — a script names `.aif` and a
## converted disc may hold `.wav`, and that tolerance is what lets the backing
## format change without a call site moving. The cost is that two files whose
## names differ only by extension collide on one key and the walk order decides
## which survives, silently. Piposh 1 ships two such pairs and they are not
## duplicates: `SOUNDS/DOCDAY1/PIP18` is 941 KB against `PIP18.AIF`'s 106 KB, and
## `SOUNDS/SAFEDAY1/CAP10` is 170 KB against `CAP10.AIF`'s 192 KB — different
## recordings of the same line, one of which was simply unreachable.
##
## So a request that names a file exactly is answered exactly, and only a request
## that does not gets the stem tolerance. Strictly more specific: it can only
## change the answer where the file the script asked for is actually on the disc.
## `tools/audio_coverage.gd` is the harness.
##
## **Whole relative paths only, no tails**, unlike `_tail_index`. Tails here would
## invert the ordering the lookup is built on -- whole path beats tail, longest
## match wins -- by letting a bare `pip18.aif` beat a fully-qualified stem match
## somewhere else, and that ordering is the thing standing between this corpus and
## the wrong take of a line. The narrower index decides only the case it was added
## for: a request whose own path, minus whatever leading segments the engine
## cannot see, is a file on the disc.
var _exact_index: Dictionary = {}

## Tails that more than one file ends with, so a request that resolves only by
## guessing can say so rather than silently picking one.

var _ambiguous: Dictionary = {}

var _root_key := ""

var _stream_cache: Dictionary = {} ## path -> AudioStream
var _channels: Dictionary = {} ## int -> AudioStreamPlayer
var _channel_file: Dictionary = {} ## int -> stem currently requested
var _channel_failed: Dictionary = {}

## Every distinct sound this session asked for and did not get:
## `"<channel>|<request>"` -> `{channel, request, why, count}`.
##
## **`bugs.md` 88's rule is that absent game data is not an engine defect
## *provided the engine reports it*, and this is the half of that rule this port
## did not hold.** `_fail` has always written one `warn` line per failed request,
## and `bugs.md` 68 says what that is worth in as many words: "nothing collects
## it ... the movies asking for it got `Audio miss: dream2\1` in a log nobody
## reads". The line is also the wrong shape to read even if somebody did.
## `audio_director.gd:321` short-circuits a repeat request only when the previous
## one matches *and* the channel is playing, so a failed request re-fails on
## every re-entry of the room that made it -- the count in the log measures how
## long the playhead sat there, not how many distinct sounds are missing. Piposh
## 1's deck loop asks 400 times for one file.
##
## So the per-occurrence `warn` stays (quieting it is what `bugs.md` 46 argues
## against: it would hide the symptom while the data is still absent) and this
## sits beside it, keyed by `(channel, request)` so a room held for four hundred
## frames contributes **one** entry with a count of 400. `miss_report()` turns it
## into the statement a session owes its reader, and `_exit_tree` prints it, so a
## run that could not play three sounds says which three when it ends rather than
## leaving them in the scrollback.
##
## Insertion-ordered, because Godot dictionaries are and first-asked is the order
## a reader wants: it is the order the rooms were entered in.
var _misses: Dictionary = {}
## `the volume of sound N`, 0-255, per channel. Kept here rather than in a host
## because both hosts set it and Director's channels outlive any one movie: a
## room that turns speech down to 75 and jumps to the next expects it to still
## be 75 there. 255 is Director's default and the level a channel starts at.
var _channel_volume: Dictionary = {}
## channel -> {from, to, seconds, elapsed} while a `sound fadeIn`/`fadeOut` runs.
var _fades: Dictionary = {}
## channel -> the cue points of the sound on it, and how many have been reported.
var _channel_cues: Dictionary = {}
var _channel_cues_passed: Dictionary = {}
## channel -> the wall-clock msec at which the sound now on it must be over,
## from the stream's own length. Absent for a channel whose stream could not
## state one.
##
## **`soundBusy` is a question about the sound and this port was answering with
## the device.** `AudioStreamPlayer.playing` is retired by the audio server, when
## its mix thread has consumed the stream, so on hardware it is the sound's
## length to within a fraction of a percent and on a slow or starved device it is
## whatever that device is slow by — measured at 2.09x on a macOS CI runner for a
## 0.63 s file (`bugs.md` 90, `tools/sound_rate.gd`).
##
## Nothing in the corpus ever asks how long a sound is; it asks `soundBusy`, and
## the shape it asks in holds the playhead:
##
## ```lingo
## on exitFrame
##   if not soundBusy(1) then play done
## end
## ```
##
## So a flag that retires at half speed does not play the speech slowly — it
## makes every *button on that frame* answer late by the remainder, which is what
## a player experiences as a dialogue whose options, exit included, take several
## seconds each. The ceiling is a bound and not a replacement: where the device is
## honest `playing` still ends first and nothing changes, and where it lags it can
## no longer hold a movie past the end of the sound.
var _channel_until: Dictionary = {}
## path -> cue points, so a sound played twice is not re-parsed for its markers.
var _cue_cache: Dictionary = {}
## `the soundLevel`, 0-7. Nothing else in the port owns the master bus, so
## `set_sound_level` drives it directly. Both hosts route here rather than each
## keeping a copy: one movie's option screen sets it and another reads it back.
var sound_level: int = SOUND_LEVEL_MAX

var _indexed: bool = false


func _ready() -> void:
	# Lazy index on first play — scanning 3k+ WAVs at boot stalls headless/editor.
	#
	# Ahead of the movie, deliberately. §12 steps sound fades "from the top of
	# the update, ahead of everything else", and the reason it matters is that a
	# fade-out reaching the bottom *stops* the channel: a `soundBusy` wait
	# released after the renderer has already decided this tick holds costs the
	# frame it was waiting on. An autoload processes before the main scene, and
	# this makes that ordering something the file states rather than something
	# the tree happens to give.
	process_priority = -100


## The fade ramp lives on the mixer's own clock rather than on a renderer's.
##
## Both renderers would otherwise have to remember to step it, and a harness that
## exercises a fade without a renderer at all — `tools/score_sound_check.gd` —
## would have to fake one. A fade that nothing steps does not fail, it holds at
## its starting level for ever, and a `soundBusy` wait behind a fade-out never
## releases. That is the failure mode this placement removes.
func _process(delta: float) -> void:
	step_fades(delta)


func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_build_index()


## Drop the index so the next lookup rebuilds it against the current config.
##
## The launcher changes the root after this autoload has already started, and
## `_indexed` is a one-shot latch: without this, anything that had touched audio
## before Play would leave the index pointing at the previous title and every
## lookup would miss. That is the silent game `director_paths.gd` documents,
## reached through a different door.
##
## **There are two latches, and both must go.** `_root_key` (`_root_prefix`,
## below) is the second: it is consulted *while the index is being built* --
## every key `_index_dir_recursive` writes goes through `_relative`/
## `_relative_named` -> `_strip_root` -> `_root_prefix()` -- so a stale value
## left over from the previous root does not merely answer one lookup wrong,
## it corrupts every key the rebuild produces, because the new root's prefix
## is never stripped from any of them. Clearing `_indexed` alone would rebuild
## the index and still get every key wrong; the bug this function exists to
## close would still be reachable, just one call deeper.
func reset_index() -> void:
	_indexed = false
	_root_key = ""


## Preloaded rather than reached by `class_name`: an autoload resolves global
## classes out of the editor's script cache, which a headless run has no reason
## to have refreshed, and the failure is "Identifier not declared" in a file
## nobody touched.
const Paths := preload("res://director/director_paths.gd")
const AiffLoader := preload("res://autoload/aiff_loader.gd")


func _build_index() -> void:
	_tail_index.clear()
	_path_index.clear()
	_exact_index.clear()
	_ambiguous.clear()
	# The game's own tree first. `_index_dir_recursive` is first-writer-wins, and
	# the game's files are the source of truth: everything under `assets/audio`
	# was produced from them by the Python pipeline and is scheduled for
	# deletion, so indexing it first would mean the port quietly played the
	# derived copy until the day that folder went away and then changed
	# behaviour with nothing to point at.
	var paths := Paths.new()
	if paths.load_config():
		_index_dir_recursive(paths.root)
	GameState.emit_log("Audio index: %d files, %d ambiguous tail(s)" % [
		_path_index.size(), _ambiguous.size()
	], "info")


## Extensions that name a sound file on a disc that has extensions at all.
const AUDIO_EXTENSIONS := ["wav", "ogg", "mp3", "aif", "aiff"]
## Enough of a file to recognise its container tag. `FORM` and `RIFF` carry a
## four-byte size before the form type, which is why this is twelve and not four.
const TAG_BYTES := 12


## Is this file a sound, judged by what is in it rather than by what it is called?
##
## **A Mac disc has no extensions**, and these are Mac discs. `piposh-dream`
## ships 1,711 sound files named `sounds/dream2/1`, `FX/264` and so on, against
## 187 that carry an extension — and the index took the 187. Nine tenths of that
## title's audio was unreachable: every line of speech, every effect, silently, and
## the movies asking for it got `Audio miss: dream2\1` in a log nobody reads.
## `piposh` ships three more (`SOUNDS/DOCDAY1/PIP18` and two others).
##
## The rule this restores is the one `_load_stream` already applies twenty
## screens below, with its own note that a disc's *filenames* are as much a guess
## as its paths are — `FX/DRILL.WAV` is an AIFF and `FX/BIRDS.AIF` is a RIFF, in
## the same folder. The loader reads the container tag for exactly that reason.
## The index was still filtering by name, so a file the loader would have decoded
## perfectly well never reached it.
##
## Consulted for **every name the extension list did not already accept**, and
## not only for a name with no extension at all. The narrower version was written
## first and `tools/audio_coverage.gd` found what it still missed on the next
## root it was pointed at: `piposh`'s `SOUNDS/PSYDEAD/PSYSCREE.M` is an AIFF
## called `.M`, so a rule keyed on "has no extension" skipped it exactly as the
## rule keyed on "has one of these extensions" did. There is no name-shaped
## version of this question that is right; the bytes are the question.
##
## The cost is twelve bytes off the front of every file under the root, once per
## session — 2,686 files for `piposh`, 3,229 for `piposh2` — and a Director
## container is `RIFX`/`XFIR`, which matches nothing here. Measured: the index
## build stays well under a second on every root.
static func _has_audio_tag(full: String) -> bool:
	var file := FileAccess.open(full, FileAccess.READ)
	if file == null:
		return false
	var head := file.get_buffer(TAG_BYTES)
	file.close()
	if head.size() < 4:
		return false
	var tag := head.slice(0, 4).get_string_from_ascii()
	# AIFF and WAVE both have the form type at byte 8; a bare `FORM` that is not
	# `AIFF`/`AIFC` is some other IFF document and not ours.
	if tag == "FORM" or tag == "RIFF":
		if head.size() < TAG_BYTES:
			return false
		var form := head.slice(8, TAG_BYTES).get_string_from_ascii()
		return form in ["AIFF", "AIFC", "WAVE"]
	if tag == "OggS":
		return true
	# MP3: an ID3 tag, or a bare frame sync.
	if head.slice(0, 3).get_string_from_ascii() == "ID3":
		return true
	return head[0] == 0xFF and (head[1] & 0xE0) == 0xE0


func _index_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_index_dir_recursive(full)
		else:
			var ext := name.get_extension().to_lower()
			if ext in AUDIO_EXTENSIONS or _has_audio_tag(full):
				# What the scripts actually name: a path. Keyed relative to the
				# game root, lowercased, separators normalised and the extension
				# dropped, so `songs\strtgame\krupsong.aif` can find
				# `SONGS/strtgame/KRUPSONG.WAV`.
				var key := _relative_key(full)
				_path_index[key] = full
				# And the same path with its extension left on, so a request that
				# names a file exactly is not resolved by the stem it shares with
				# another. See `_exact_index`.
				_exact_index[_relative_named(full)] = full
				# And every tail of it, because a script may name any suffix of
				# the path. This is where the folder used to be thrown away: only
				# the bare filename was indexed beside the whole path, so a
				# request for `days\d1prom1.aif` -- a real one, and what every
				# entry that skips the CD-drive probe builds -- fell through to
				# the filename and picked whichever of `SOUNDS/DAYS` and
				# `SOUNDS/S_DAY1` the directory walk reached first. That is a
				# wrong take of a line of speech, and it is silent.
				var parts := key.split("/", false)
				for start in range(parts.size()):
					var tail := "/".join(Array(parts).slice(start))
					if _tail_index.has(tail):
						_ambiguous[tail] = true
					else:
						_tail_index[tail] = full
		name = dir.get_next()
	dir.list_dir_end()


func resolve_path(file_name: String) -> String:
	_ensure_index()
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		return ""
	return _resolve_normalised(raw)


## A request is a path, and the folder in it is meaning, not decoration.
##
## Scripts build these by concatenation from a global -- `playfromdisk` is
## `"songs\strtgame\\"`, `soundspath` is `soundspathstart & "days" & "\"` -- so
## the same filename appears under several folders and only the folder picks the
## right one. Matching on the filename alone is how the wrong take of a line gets
## played, and it is silent: a sound plays, so nothing looks broken. 315 of this
## corpus's 3,142 sounds share a filename with another; 0 share a folder and a
## filename.
##
## Matched by suffix at **both** ends, because a request is a path fragment and
## may be missing segments from either side. It carries a prefix this engine
## cannot see -- `the moviePath` on the authoring machine, or a CD drive letter --
## so leading segments are dropped until something matches; and it may be missing
## a leading segment the disc has, because the global that supplies it was set by
## a movie this entry never passed through. `soundspath` is
## `soundspathstart & "days" & "\"`, and `soundspathstart` is written only by
## `strtgame`'s drive probe: reach the room any other way and every request is
## `days\<name>.aif` against a disc whose files are under `SOUNDS/DAYS/`.
##
## The longest match wins in both directions, so a more specific request beats a
## less specific one, and the whole path beats a tail of it. A bare filename is
## the shortest tail, still legal and still common, and it is the only one this
## corpus can leave ambiguous -- but a request that *carries* a folder is never
## reduced to one. `_request_tails` is where that bound is written down, and why:
## dropping the folder is how the wrong take gets played from the other side.
func _resolve_normalised(raw: String) -> String:
	# The exact name first, and only its leading segments dropped -- never its
	# extension. A request that names a file that is on the disc gets that file;
	# everything below is the tolerance for a request that does not. See
	# `_exact_index` for the two Piposh 1 pairs this decides between.
	var named := _normalise_named(raw)
	if named != "":
		for tail in _request_tails(named):
			if _exact_index.has(tail):
				return str(_exact_index[tail])
	var key := _normalise(raw)
	if key == "":
		return ""
	var tails := _request_tails(key)
	# Drop leading segments until something matches: the request may be absolute
	# where the index is relative to the game root.
	for tail in tails:
		if _path_index.has(tail):
			return str(_path_index[tail])
	# Then the other direction: the request may be a tail of a path on disc.
	for tail in tails:
		if not _tail_index.has(tail):
			continue
		if _ambiguous.has(tail):
			push_warning(
				"sound '%s' resolves only by '%s', which more than one file ends with"
				% [raw, tail]
			)
		return str(_tail_index[tail])
	return _search_path_hit(raw)


## The tails of a request the lookup may try, longest first.
##
## **Leading segments may go. The request's own trailing folder may not.** The two
## ends are asymmetric and this is the one place that says so. In front of the
## folder sits a prefix this engine cannot see -- a CD drive letter, `the
## moviePath` of the machine the movie was authored on, a `soundspathstart`
## written by a movie this entry never passed through -- and dropping it is the
## only reason an absolute 1997 path is answerable at all. The folder itself is
## the part the script composed on purpose, and Director plays **nothing** for a
## path that is not there. It never answers `dream3\149` out of `dream1`.
##
## So reducing a request to its bare filename is not a last resort, it is the
## wrong answer, and it is the same wrong-take-of-a-line failure `_tail_index` was
## built to stop -- reached from the other side, and worse than a silence, because
## a sound plays and nothing looks broken. Measured with `qa_walk --sweep` over
## all six roots before this bound existed: **52 distinct requests** resolved that
## way, and every one of them crossed into a folder the request did not name.
## `sounds\brjday3\brj1.aif` was answered out of `SOUNDS/BRJDAY1`, one of the
## eight different takes of `brj1` that disc carries, and `sounds\days\circ1.aif`
## out of `SOUNDS/NIGHTS`. Only 20 of the 52 printed anything at all -- the
## `push_warning` below, which nothing in this repository reads -- and the other 32
## were silent, because the filename they crossed to happened to be unique. A
## request that has no folder is untouched: a bare filename is the shortest
## **legal** tail, not a reduction, and it is what every entry that skips a drive
## probe composes.
##
## **52 is a floor.** A sweep opens each container cold, so a request only becomes
## folder-qualified there if the movie sets its own path global; one whose global
## was written by a movie the sweep never came through stays a bare filename and
## cannot be counted. `fx\1234.aif` -> `CFILES/SUEME/1234.AIF` is exactly that
## case and appears in none of the six sweeps: `effectspath` is set on the way
## through `STRTGAME.dir`, and only an entry that passes through it sees the
## folder at all (`docs/bugs-closed.md` 122).
##
## All 52 were answered by `_tail_index`. The two loops above it hold whole
## root-relative paths, so a bare-filename hit there needs a sound sitting
## directly under the game root and no root in this corpus has one -- the bound
## covers them because the rule is about requests and not about which index
## answers, not because anything measured them.
##
## The game root comes off first, because it is the one prefix the engine *can*
## see: `the moviePath & "click.aif"` is a whole-path request for a sound sitting
## beside the movie, and measuring the bound against the absolute form would
## refuse it. That arm is implemented from the rule and **unverified against
## data** -- no root in this corpus keeps a sound directly under it, 0 of 14,638
## across the six -- rather than left out because this corpus cannot exercise it.
func _request_tails(key: String) -> Array:
	var parts := _strip_root(key).split("/", false)
	var out: Array = []
	# The last tail kept is `<folder>/<filename>`, or the filename on its own
	# where that is the whole request.
	for start in range(maxi(1, parts.size() - 1)):
		out.append("/".join(Array(parts).slice(start)))
	return out


## The clause `_fail` adds when a request missed because of the rule above rather
## than because the disc is short of a file.
##
## Two different facts, and `miss_report`'s standing sentence only states one of
## them. A request whose path is absent is the disc's gap under `bugs.md` 88 --
## 46 and 68 are both that -- and a reader who has seen the line knows to go
## looking at the tree. A request whose named folder does not hold the file while
## another folder does is this engine declining to substitute a sibling, and it
## reads as the first one unless the line says otherwise. It is also the more
## actionable of the two, because it names a file that *is* on the disc.
##
## In the ledger and not in a `push_warning`, for the reason `_misses` gives:
## nothing here reads a warning, so a distinction that lives in one is nowhere.
func _folder_note(raw: String) -> String:
	var key := _strip_root(_normalise(raw))
	var file := key.get_file()
	if key == file or not _tail_index.has(file):
		return ""
	return " (the folder it names holds no such file; '%s' is on the disc elsewhere)" % file


## `the searchPath` — where Director looks once the indexed tree has said no.
##
## Set from Lingo (`preview_lingo_host.gd:search_path`) and empty otherwise, so
## the ordinary lookup above is unchanged for every title that never writes it.
## The entries are absolute paths outside the game root — Piposh 1 writes `d:`,
## `e:`, `f:` and `b:` in turn, looking for the CD — so they are tried directly
## against the filesystem rather than through the index, which only knows what is
## under the game folder.
##
## The request's own leading segments are dropped one at a time here too, for the
## same reason `_resolve_normalised` drops them: a request carries a prefix from
## the authoring machine and the search path supplies the real one.
##
## **And `_request_tails`'s bound deliberately does not apply here**, which is
## why this loop still reduces to the bare filename while the one above refuses
## to. The two are answering different questions. Above, the index knows the whole
## tree and a folder in the request is a claim about where in it the file is, so
## honouring the claim is the whole point. `the searchPath` is a list of folders
## Director *searches*, and what it searches them for is a name -- a folder in the
## request is the authoring machine's, not one of the entries', so keeping it
## would mean never finding anything through a search path at all. Do not make
## these two consistent; they are consistent, at the level of what each is for.
func _search_path_hit(raw: String) -> String:
	if search_path.is_empty():
		return ""
	var wanted := raw.replace("\\", "/").replace(":", "/").trim_prefix("/")
	var parts := wanted.split("/", false)
	for entry in search_path:
		var base := str(entry).replace("\\", "/").replace(":", "/")
		if base.strip_edges() == "":
			continue
		if not base.ends_with("/"):
			base += "/"
		for start in parts.size():
			var tail := "/".join(Array(parts).slice(start))
			for candidate in [base + tail, base + tail + ".aif", base + tail + ".wav"]:
				if FileAccess.file_exists(candidate):
					return candidate
	return ""


## `the searchPath`, as the movie last set it. Paths outside the game root, so
## they are never indexed and are only ever tried on demand — see
## `_search_path_hit`. Empty until a movie writes one, which is 326 sites in
## Piposh 1 and none anywhere else.
var search_path: Array = []


func set_search_path(paths: Array) -> void:
	search_path = paths.duplicate()


## Director's `beep`: the machine's alert sound, `repeats` times, 400 ms apart.
##
## Synthesised rather than shipped. There is no beep on the disc — it is the
## Mac's own system alert, which this port has no copy of and no licence to — so
## what is played is a short tone with a fast attack and a decay, which is what a
## 1997 Mac's simple beep was. The whole run including its gaps is rendered into
## one buffer, so `beep 3` does not stop the handler that asked for it.
##
## Its own player, deliberately off the numbered channels: `soundBusy(1)` is what
## every line of speech in this corpus waits on, and a beep that claimed a
## channel would make a room wait for it.
func system_beep(repeats: int = 1) -> void:
	var player := _beep_player()
	if player == null:
		return
	player.stream = _beep_stream(maxi(repeats, 1))
	# Full on its own player; `the soundLevel` is the master bus and still
	# applies, which is right — the system volume turns the beep down too.
	player.volume_db = _volume_db(VOLUME_MAX)
	player.play()


var _beep: AudioStreamPlayer = null
## One rendered beep run per repeat count. There is exactly one count in the
## corpus (all 154 sites are the bare `beep`), so this caches one entry in
## practice and exists so that a beep in a loop does not resynthesise.
var _beep_cache: Dictionary = {}

const BEEP_RATE := 22050
const BEEP_HZ := 1000.0
const BEEP_MS := 120
## Director's own spacing between repeats.
const BEEP_GAP_MS := 400


func _beep_player() -> AudioStreamPlayer:
	if _beep != null:
		return _beep
	_beep = AudioStreamPlayer.new()
	_beep.name = "SystemBeep"
	_beep.bus = "Master"
	add_child(_beep)
	return _beep


func _beep_stream(repeats: int) -> AudioStreamWAV:
	if _beep_cache.has(repeats):
		return _beep_cache[repeats]
	var tone := int(BEEP_RATE * BEEP_MS / 1000.0)
	var gap := int(BEEP_RATE * BEEP_GAP_MS / 1000.0)
	var frames := tone * repeats + gap * maxi(repeats - 1, 0)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for r in repeats:
		var at := r * (tone + gap)
		for i in tone:
			# A quick attack and a long decay, so the tone starts without a click
			# and ends without one either -- a raw square gate reads as two clicks
			# with a whistle between them rather than as a beep.
			var envelope := minf(float(i) / (BEEP_RATE * 0.004), 1.0) \
				* (1.0 - float(i) / tone)
			var sample := int(sin(TAU * BEEP_HZ * i / BEEP_RATE) * envelope * 20000.0)
			data.encode_s16((at + i) * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = BEEP_RATE
	stream.stereo = false
	stream.data = data
	_beep_cache[repeats] = stream
	return stream


## Lowercased, **all three separators** folded to `/`, extension dropped.
##
## Three, not two, and the third is the one a port forgets. Director ran on the
## Mac first and its path separator is the **colon**: `the moviePath` on a Mac
## answers `HD:Rating:` and a script concatenating onto it produces
## `HD:Rating:sounds:batzegoz:f1.aif`. The Windows player wrote backslashes, and
## the same corpus carries both -- `soundspath` is built as
## `soundspathstart & "days" & "\"` in one movie and `the moviePath &
## "sounds:batzegoz:f1.aif"` in another, and BATZEGOZ.dir is a movie that does
## both within four members of each other. They are one problem and this is the
## one rule: a request is a path, and which byte the author's machine wrote
## between its segments is not information the lookup may act on.
##
## Applied to the request *and* to every file on disc (`_relative_key`), so both
## sides of the comparison are in the same alphabet. It folds the colon in
## `res://` as well, which costs nothing: `_resolve_normalised` drops leading
## segments until something matches, and a prefix this engine cannot see -- an
## authoring machine's volume name, a CD drive letter -- is exactly what those
## leading segments are.
##
## The extension is dropped because the scripts name `.aif` and a converted disc
## may hold `.wav`.
static func _normalise(path: String) -> String:
	return path.to_lower() \
		.replace("\\", "/") \
		.replace(":", "/") \
		.trim_suffix("/") \
		.get_basename()


## `_normalise` with the extension left on. See `_exact_index`.
static func _normalise_named(path: String) -> String:
	return path.to_lower() \
		.replace("\\", "/") \
		.replace(":", "/") \
		.trim_suffix("/")


## The index key for a file on disc: its path relative to the game root.
func _relative_key(full: String) -> String:
	return _strip_root(_normalise(full))


## The same, with the extension kept.
func _relative_named(full: String) -> String:
	return _strip_root(_normalise_named(full))


func _strip_root(key: String) -> String:
	var root := _root_prefix()
	if root != "" and key.begins_with(root):
		key = key.substr(root.length())
	return key.lstrip("/")


func _root_prefix() -> String:
	if _root_key != "":
		return _root_key
	var paths := Paths.new()
	if paths.load_config():
		_root_key = _normalise(paths.root)
	return _root_key


func play_file(channel: int, file_name: String) -> void:
	_ensure_index()
	var ch := maxi(1, channel)
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		# A request for nothing is still a request, and it still takes the
		# channel. Returning here left the previous sound playing *and* left
		# `soundBusy` answering for it, so a `soundBusy` guard placed after the
		# `playFile` waited out a sound the script had already replaced -- and if
		# nothing ever replaced it, waited for ever. See `_fail` below.
		_fail(ch, "", "sound playFile named nothing")
		return
	# Idempotent: the same file already playing on this channel is left alone.
	#
	# A knowing deviation. Director's `sound playFile` restarts unconditionally,
	# and the reason this does not is `play_frame_sounds`: the older renderer
	# replays a frame's sounds on every frame *entry*, and a Director hold loop
	# re-enters the same frame every tick, so an unconditional restart machine-
	# guns the first 40 ms of the sound for as long as the room holds.
	#
	# It costs almost nothing here, measured over `reference/lingo/`: of the
	# 2,515 `sound playFile` statements, 11 sit in a frame handler that also
	# holds the playhead, 9 of those are behind a `soundBusy` guard, and the
	# remaining 2 (CHESS BehaviorScript 81 and 87) are gated on `the mouseDown`
	# and jump to another marker in the same branch — so no authored path in this
	# game re-plays a file on a channel that is already playing it.
	# Identity is the whole request, not the filename in it. Two folders holding
	# the same filename are two different sounds -- this game keeps the same
	# actor's lines under several -- and comparing stems made the second one
	# look like the first and skip.
	#
	# Compared *normalised*, for the reason `_normalise` gives: the same file can
	# be asked for with colons or with backslashes, and this corpus does both.
	# Comparing the raw strings made `sounds:batzegoz:h.aif` and
	# `sounds\batzegoz\h.aif` two different sounds, so a room that reached the
	# same line by two routes restarted it from the top instead of leaving it
	# alone -- which is the machine-gunning this guard exists to prevent, arrived
	# at through the separator instead of through the frame loop.
	# **The same question `sound_busy` asks, and it has to be.** This was
	# `existing.playing`, which stopped agreeing with `sound_busy` the moment that
	# gained its `_channel_until` ceiling, and the disagreement wedges a channel
	# silent for the rest of the movie: once the ceiling passes while the device is
	# still draining the stream, the channel is *free* to the movie and *already
	# playing* to this guard, so the replay is skipped, `_start` never re-arms
	# `_channel_until`, and `sound_busy` answers false for ever. Nothing recovers
	# it, because every later replay of the same file takes this same early return.
	#
	# Measured on `itamar-magichat` with `tools/scratch/soundstart.gd`:
	# `soundBusy` went false after 607 frames with `player.playing` still true and
	# the ceiling 78 ms into the past; 120 frames later the replay had reached
	# nothing and the ceiling was 4,175 ms into the past. Magic Hat's `PlayMusic`
	# busy-waits three seconds on `soundBusy` and then puts up
	# `alert("Sound file X is missing !")` for a file that exists -- and
	# `lingo_alert` sets `_paused`, so the movie stops behind a modal naming the
	# wrong cause. Seen twice in ordinary play, on `MAINMENU_M.MP3` and
	# `ALBUM_M.MP3`.
	#
	# Asking `sound_busy` also gets the failed-channel case right for free: a
	# channel whose last load failed is not busy, so the replay proceeds rather
	# than being skipped for ever on the strength of a dead player.
	var previous := str(_channel_file.get(ch, ""))
	if previous != "" and _normalise(previous) == _normalise(raw):
		if sound_busy(ch):
			return

	_channel_file[ch] = raw
	_channel_failed[ch] = false
	# The whole path, so the folder can pick between same-named files. Passing
	# the stem here is what made it play the wrong take: the resolver never saw
	# the folder the script had gone to the trouble of building.
	var path := resolve_path(raw)
	if path.is_empty():
		_fail(ch, raw, "Audio miss: %s%s" % [raw, _folder_note(raw)])
		return

	var stream := _load_stream(path)
	if stream == null:
		_fail(ch, raw, "Audio load fail: %s" % path)
		return
	_start(ch, stream, _cue_points_of(path))


## Play a stream the caller already has, which is how a *cast member* reaches a
## channel: the score's two sound channels and `puppetSound` name a member, not a
## file, and `director/director_sound.gd` is what turns one into a stream.
##
## `id` is what `sound_member` reports back and what restart-on-change compares,
## so it must identify the source rather than describe it — "<lib>:<member>" for
## a member, the stem for a file.
func play_stream(channel: int, id: String, stream: AudioStream, cues: Array = []) -> void:
	var ch := maxi(1, channel)
	if stream == null:
		_channel_failed[ch] = true
		return
	_channel_file[ch] = id
	_channel_failed[ch] = false
	_start(ch, stream, cues)


## A sound cast member whose audio is an **external file** rather than an
## embedded payload, onto a channel. `false` when the name resolves to nothing or
## the file will not decode, which is a fact about the movie and not an error.
##
## Director lets a sound member name a file instead of carrying one, and
## `castmember/sound.cpp:SoundCastMember::load()` reaches that case from a payload
## that is absent *or* zero bytes: it asks `_cast->getLinkedPath(_castId)` and
## builds an `AudioFileDecoder` on the answer. `director_cast.gd` has reported the
## state as `sound_linked` / `link_filename` all along and **nothing consumed
## it**, so 54 of `itamar-park`'s 66 sound members resolved to silence — `%Coll1`,
## `%Eat1`, `%HiScore` in `Sound.cst`, which is a game whose collect, eat and
## high-score effects were all mute.
##
## **This deliberately reuses `resolve_path` rather than resolving a second
## time.** A linked member's name is the same kind of string `sound playFile`
## takes — a fragment of a path from the authoring machine, in Mac or Windows
## separator form, possibly missing leading segments — and that resolver is where
## the tail index, the exact index and the ambiguity warning live. A second
## resolver beside it would be a second set of answers to the same question, and
## the one that got a wrong take of a line of speech would be silent about it.
##
## `id` is the member's `"<lib>:<member>"`, not the filename, because that is what
## `the member of sound` reports and what restart-on-change compares — the member
## is the identity, and the file behind it is an implementation detail of the
## member.
##
## **Looping is off, and that is the reference's rule rather than a default.**
## `load()` sets `_looping = 0` in the linked arm with the comment "Linked sound
## files always have the loop flag disabled", so a member whose Cast window tick
## box says loop does not loop when its audio came from a file. Godot carries the
## loop flag on the *stream*, and `_stream_cache` hands the same stream object to
## every caller, so a stream that arrives looping is duplicated before the flag is
## cleared — clearing it in place would silently unloop the same file for
## `sound playFile`.
func play_linked_member(channel: int, id: String, file_name: String) -> bool:
	_ensure_index()
	var ch := maxi(1, channel)
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		return false
	var path := resolve_path(raw)
	if path.is_empty():
		# Through `_fail`, for the reason `_fail` gives: Director claims the channel
		# before it opens the media, so a member that cannot be found leaves the
		# channel *empty* rather than still playing whatever was there. A `soundBusy`
		# poll after a score sound that missed must not wait out the previous sound.
		_fail(ch, id, "linked sound member %s: no file named %s%s" % [
			id, file_name, _folder_note(raw)])
		return false
	var stream := _load_stream(path)
	if stream == null:
		_fail(ch, id, "linked sound member %s: %s will not decode" % [id, path])
		return false
	stream = _without_loop(stream)
	_channel_file[ch] = id
	_channel_failed[ch] = false
	_start(ch, stream, _cue_points_of(path))
	return true


## The media behind a linked name, without touching a channel: `{"path",
## "stream", "cues"}`, with `path` empty when nothing resolved and `stream` null
## when nothing decoded.
##
## `preview/media.gd` needs exactly this and needs it *not* to play: `the
## duration`, `the sampleRate`, `the sampleSize`, `the channelCount` and `the
## cuePointNames` of a linked sound member are all questions about the file, and a
## script may ask any of them without ever putting the member on a channel. One
## resolver and one loader for both, so a member cannot answer a duration for one
## file and play another.
func linked_media(file_name: String) -> Dictionary:
	_ensure_index()
	var out := {"path": "", "stream": null, "cues": []}
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		return out
	var path := resolve_path(raw)
	if path.is_empty():
		return out
	out["path"] = path
	var stream := _load_stream(path)
	if stream == null:
		return out
	out["stream"] = _without_loop(stream)
	out["cues"] = _cue_points_of(path)
	return out


## The same stream with looping off, copied first when it is on.
##
## `_stream_cache` is keyed by path and shared, so this may not write through to
## the cached object. The duplicate is only paid for by a file that actually loops,
## which is none in any corpus in reach.
func _without_loop(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			return wav
		var copy: AudioStreamWAV = wav.duplicate()
		copy.loop_mode = AudioStreamWAV.LOOP_DISABLED
		return copy
	# `loop` is a plain bool on the Ogg and MP3 streams, and neither type is
	# reachable from any root today (0 ogg, 0 mp3 across all six shipped titles).
	# Handled by property rather than by type so that a title that ships one is not
	# a silent exception.
	if stream != null and bool(stream.get("loop")):
		var copy: AudioStream = stream.duplicate()
		copy.set("loop", false)
		return copy
	return stream


func _start(channel: int, stream: AudioStream, cues: Array) -> void:
	_channel_cues[channel] = cues
	_channel_cues_passed[channel] = 0
	# The one funnel both `play_file` and `play_stream` reach, which is why the
	# `soundBusy` ceiling is recorded here and nowhere else. A stream that cannot
	# state a length -- a generator, or a format whose header did not carry one --
	# gets no ceiling rather than a guessed one, and behaves exactly as before.
	var length := stream.get_length()
	if length > 0.0:
		_channel_until[channel] = Time.get_ticks_msec() + int(length * 1000.0)
	else:
		_channel_until.erase(channel)
	# A fade in progress belongs to the sound that was playing, not to this one.
	_fades.erase(channel)
	var player := _ensure_player(channel)
	player.stream = stream
	# Restored rather than assumed: `_fade_step` writes `volume_db` directly, so
	# a channel that was mid-fade when this sound started would otherwise inherit
	# the level the fade had reached.
	player.volume_db = _volume_db(channel_volume(channel))
	player.play()


## What is on a channel now: the stem of a file or "<lib>:<member>" of a cast
## member, and "" when nothing has been put there. Restart-on-change compares
## this, and so does `play_file`'s idempotence guard.
func channel_source(channel: int) -> String:
	return str(_channel_file.get(maxi(1, channel), ""))


## `the volume of sound N`. This game names it on 67 lines — 66 writes and 2
## reads — over channels 1 to 4, so a read has to answer what the last write said
## even on a channel that has never played: `set the volume of sound 3 to the
## volume of sound 3 - 20` steps a loop down and reads its own previous write
## every time round.
func channel_volume(channel: int) -> int:
	return int(_channel_volume.get(maxi(1, channel), VOLUME_MAX))


## Director's volume is 0-255 and linear in amplitude; Godot's is decibels, and
## the conversion is what makes 128 sound like half rather than nearly full.
## Applied to the channel's own player, so it survives the next `play_file` — a
## room sets the volume once and then speaks several lines through it.
func set_channel_volume(channel: int, level: int) -> void:
	var ch := maxi(1, channel)
	var clamped := clampi(level, 0, VOLUME_MAX)
	_channel_volume[ch] = clamped
	# A write to the volume cancels a fade. Director's fade *is* a series of
	# volume writes, so a script that sets the volume mid-fade has taken the
	# channel back; leaving the fade running would let it overwrite the value on
	# the very next tick.
	_fades.erase(ch)
	_ensure_player(ch).volume_db = _volume_db(clamped)


func _volume_db(level: int) -> float:
	return -80.0 if level <= 0 else linear_to_db(float(level) / VOLUME_MAX)


func set_sound_level(level: int) -> void:
	sound_level = clampi(level, 0, SOUND_LEVEL_MAX)
	AudioServer.set_bus_volume_db(0,
		-80.0 if sound_level == 0 else linear_to_db(float(sound_level) / SOUND_LEVEL_MAX))


# ------------------------------------------------------------------ fades

## `sound fadeIn <channel>, <ticks>` and `sound fadeOut`.
##
## Director ramps the channel's volume between 0 and whatever the channel's
## volume property says, over a number of ticks — 60 to the second — and a
## fade-out **stops the channel when it reaches the bottom**, which is the part
## that matters to a script: `sound fadeOut 1, 60` followed by a `soundBusy(1)`
## wait must eventually release. A fade that only turned the volume down would
## hold that loop for ever.
##
## The volume property itself is left alone. `the volume of sound N` after a fade
## reads what it read before, because Director fades the *output* and not the
## setting; that is why `set the volume of sound N` cancels a fade rather than
## being overridden by it.
##
## **Unexercised by the corpus this port was built on** — neither verb appears in
## any of its 3,349 scripts (`tools/sound_survey.gd`) — so the ramp shape and the
## stop-at-the-bottom rule are implemented from the reference, and
## `tools/sound_state.gd` asserts them against the engine rather than against the
## game.
const TICKS_PER_SECOND := 60.0
## Director's default when a fade names no duration.
const DEFAULT_FADE_TICKS := 60


func fade_in(channel: int, ticks: int = DEFAULT_FADE_TICKS) -> void:
	_begin_fade(channel, 0.0, 1.0, ticks)


func fade_out(channel: int, ticks: int = DEFAULT_FADE_TICKS) -> void:
	_begin_fade(channel, 1.0, 0.0, ticks)


func _begin_fade(channel: int, from: float, to: float, ticks: int) -> void:
	var ch := maxi(1, channel)
	var seconds := maxf(float(ticks) / TICKS_PER_SECOND, 0.0)
	if seconds <= 0.0:
		# A zero-tick fade is the endpoint, immediately — including the stop.
		_apply_fade(ch, to)
		if to <= 0.0:
			stop_channel(ch)
		return
	_fades[ch] = {"from": from, "to": to, "seconds": seconds, "elapsed": 0.0}
	_apply_fade(ch, from)


## Stepped once per tick from the top of the update, ahead of everything else —
## §12. Called by whichever renderer owns the clock; a fade that nothing steps
## simply holds at its starting level, which is visible rather than silent.
func step_fades(delta: float) -> void:
	if _fades.is_empty():
		return
	for ch in _fades.keys():
		var fade: Dictionary = _fades[ch]
		fade["elapsed"] = float(fade["elapsed"]) + delta
		var t: float = clampf(float(fade["elapsed"]) / float(fade["seconds"]), 0.0, 1.0)
		var level: float = lerpf(float(fade["from"]), float(fade["to"]), t)
		_apply_fade(int(ch), level)
		if t < 1.0:
			continue
		_fades.erase(ch)
		if level <= 0.0:
			stop_channel(int(ch))


func _apply_fade(channel: int, scale: float) -> void:
	var level := int(round(float(channel_volume(channel)) * clampf(scale, 0.0, 1.0)))
	_ensure_player(channel).volume_db = _volume_db(level)


func fading(channel: int) -> bool:
	return _fades.has(maxi(1, channel))


# ------------------------------------------------------------------ cue points

## Cue points passed since the current sound started, as `{index, name, frame}`,
## and cleared as they are read.
##
## Director sends `cuePassed me, channel, cueNumber, cueName` as the playhead of
## a *sound* crosses a marker in it, which is a second, sound-driven source of
## events alongside the frame's. Polled rather than pushed because the audio
## server has no callback at a sample position: the renderer asks once a tick,
## which is the same resolution every other Director event has.
##
## **Unexercised by the corpus this port was built on.** No script in it names
## `cuePoint`, `cuePassed` or `the cuePointNames of member`, and none of its
## 3,141 sounds carries a marker inside its own audio — 168 do carry a `MARK`
## chunk, and all 336 markers in them sit past the end of the file they are in
## (`tools/aiff_check.gd`). So this is implemented from the reference and proved
## against synthesised markers, not against the game.
func take_cues_passed(channel: int) -> Array:
	var ch := maxi(1, channel)
	var cues: Array = _channel_cues.get(ch, [])
	if cues.is_empty():
		return []
	var player: AudioStreamPlayer = _channels.get(ch)
	if player == null or not player.playing:
		return []
	var stream: AudioStream = player.stream
	var rate: float = float(stream.mix_rate) if stream is AudioStreamWAV else 44100.0
	var frame := int(player.get_playback_position() * rate)
	var passed := int(_channel_cues_passed.get(ch, 0))
	var out: Array = []
	while passed < cues.size() and int((cues[passed] as Dictionary).get("frame", 0)) <= frame:
		var cue: Dictionary = cues[passed]
		# 1-based: `cuePassed`'s cueNumber counts from 1, as every Director index
		# does, and an off-by-one here silences the first cue of every sound.
		out.append({
			"index": passed + 1,
			"name": str(cue.get("name", "")),
			"frame": int(cue.get("frame", 0)),
		})
		passed += 1
	_channel_cues_passed[ch] = passed
	return out


## Channels worth polling for cues: the ones something has actually been played
## on. Asking rather than assuming a count keeps the puppet channels above the
## score's two in scope without naming a limit Director does not have.
func cue_channels() -> Array:
	return _channel_cues.keys()


## The cue point names of whatever is on a channel, for
## `the cuePointNames of sound N`.
func cue_point_names(channel: int) -> Array:
	var out: Array = []
	for cue in _channel_cues.get(maxi(1, channel), []):
		out.append(str((cue as Dictionary).get("name", "")))
	return out


## True once every cue point of the sound on this channel has been passed, which
## is what a wait-for-cue tempo of −2 ("end") resolves to.
func cues_exhausted(channel: int) -> bool:
	var ch := maxi(1, channel)
	var cues: Array = _channel_cues.get(ch, [])
	return int(_channel_cues_passed.get(ch, 0)) >= cues.size()


func _cue_points_of(path: String) -> Array:
	if _cue_cache.has(path):
		return _cue_cache[path]
	var cues: Array = []
	# The tag, for `_load_stream`'s reason. Gating this on the extension instead
	# was the quieter half of the same bug: an AIFF named `.wav` would play once
	# the loader was fixed and then silently carry no cue points, so a tempo of
	# −2 waiting on one would wait forever with nothing to say why.
	if _container_tag(path) == "FORM":
		cues = AiffLoader.cue_points(FileAccess.get_file_as_bytes(path))
	_cue_cache[path] = cues
	return cues


## A `playFile` that could not start: the channel is taken, and it is silent.
##
## Director's `sound playFile` claims the channel before it opens the file, so a
## request it cannot satisfy leaves the channel *empty* -- not still playing what
## was there a moment ago. The distinction is the whole of `soundBusy`'s
## usefulness. `BehaviorScript 250` in this corpus is the shape that depends on
## it:
##
##     on exitFrame
##       if not soundBusy(1) then go(marker(0))
##     end
##
## and its counterpart is a frame that plays a line and then polls. Answering
## "busy" for a sound the script has already replaced makes that poll wait out the
## *old* sound; answering it for a sound that never started at all makes the poll
## wait for something that can never end. Both are the same mistake, and neither
## is recoverable from inside the movie -- the script has no way to ask whether
## its `playFile` worked.
##
## Stopping the player is the second half and it is not cosmetic: without it the
## previous sound stays audible while `soundBusy` says the channel is free, so
## the next line of speech is spoken over the last one.
func _fail(channel: int, request: String, why: String) -> void:
	var player: AudioStreamPlayer = _channels.get(channel)
	if player and player.playing:
		player.stop()
	_fades.erase(channel)
	_channel_cues[channel] = []
	_channel_cues_passed[channel] = 0
	_channel_until.erase(channel)
	_channel_file[channel] = request
	_channel_failed[channel] = true
	# Collected before it is logged, so a `warn` that scrolls past is still
	# counted. See `_misses` for why the log line alone was not reporting.
	var key := "%d|%s" % [channel, request]
	if _misses.has(key):
		_misses[key]["count"] = int(_misses[key]["count"]) + 1
	else:
		_misses[key] = {
			"channel": channel, "request": request, "why": why, "count": 1,
		}
	GameState.emit_log(why, "warn")


## Every distinct sound this session asked for and did not get, first-asked
## first. Each entry is `{channel, request, why, count}`.
##
## The reporting surface `bugs.md` 88 requires, and the thing a harness can
## assert against -- a `warn` line cannot be asserted on without scraping a log,
## which is how `docs/bugs-closed.md` 106's vacuous scrape happened.
func misses() -> Array:
	var out: Array = []
	for key in _misses.keys():
		out.append((_misses[key] as Dictionary).duplicate())
	return out


## How many *distinct* requests failed, which is the number that means something.
## The per-request `count` is how long the room holding the playhead asked.
func miss_count() -> int:
	return _misses.size()


## Forget them. For a harness that wants to measure one movie's requests without
## the boot sequence's in the total; nothing in the player calls it, because a
## session's misses are the session's.
func clear_misses() -> void:
	_misses.clear()


## The session's audio misses as one block of text, or `""` when there were none.
##
## Deliberately says the two things a reader needs and no more: **which files**,
## and **that the engine composed the request correctly and the disc did not have
## it**. The second sentence is there because every time this has come up -- 46,
## 68, and the `dream2\1` case before them -- the first reading was "the resolver
## is broken", and it has never once been that.
func miss_report() -> String:
	if _misses.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Audio: %d request(s) this session resolved to no file on disc." % _misses.size())
	lines.append("  The path was composed and searched; the file is not in the game tree.")
	for key in _misses.keys():
		var m: Dictionary = _misses[key]
		lines.append("  channel %d  %-40s  asked %d time(s)  [%s]" % [
			int(m["channel"]),
			str(m["request"]) if str(m["request"]) != "" else "(empty request)",
			int(m["count"]), str(m["why"]),
		])
	return "\n".join(lines)


## The report, at the one moment every session reaches.
##
## An autoload's `_exit_tree` runs on quit, including a headless `--script` run
## and a windowed one closed from the title bar, which is what makes this the
## place: a player who has just watched a room play silently gets told why on the
## way out, and a sweep that drove eighty movies gets the union of what they
## asked for. Through `print` rather than `GameState.emit_log`, because the log
## sinks are being torn down alongside this node and the whole point is that the
## statement survives.
func _exit_tree() -> void:
	release_playbacks()
	var report := miss_report()
	if report != "":
		print(report)


## Give every playback this node started back to the `AudioServer` before the
## tree finishes taking its players down. `bugs.md` 132.
##
## The exit path is the only one that needs telling. While the movie runs, a
## channel is stopped by the next sound on it, by `sound stop`, or by the stream
## ending, and all three release the playback in the normal way. What has no
## owner is the last moment: a title that quits mid-sentence -- which is every
## `quit` in every one of these titles, since the speech is longer than the click
## that ends the room -- left one `AudioStreamWAV` and its playback alive past the
## ObjectDB check, and the engine reported them on the way out of every such run.
##
## Two objects and no `ERROR` line is a small prize on its own. It is worth the
## call for the reason `efde7406` gives about the constant `4 resources still in
## use`: this suite's job is to say which entries are clean, and a `WARNING` that
## everybody has learned to read past costs more than the bytes it leaks.
##
## The beep is stopped beside the channels rather than through `stop_all`,
## because it is deliberately off the numbered channels -- `soundBusy(1)` is what
## every line of speech in this corpus waits on, and a beep that claimed a channel
## would make a room wait for it.
func release_playbacks() -> void:
	var watching := _playback_watches()
	stop_all()
	if _beep != null and is_instance_valid(_beep):
		_beep.stop()
	# Stopping only *asks*. The `AudioServer` marks the playback for deletion and
	# drops it on a later mix of its own thread, so whether the object is gone by
	# the time the engine counts leaked instances is a race with that thread --
	# measured, a child spawned from a busy parent still leaked the pair in 1 of 4
	# runs with the stop in place and nothing waiting on it. Waiting on the
	# condition under a ceiling is `bugs.md` 131's medicine applied to the same
	# shape one file over: the loop ends the moment the last playback is gone, so
	# a quiet machine pays nothing and a busy one pays what it has to.
	var deadline := Time.get_ticks_msec() + RELEASE_CEILING_MS
	while not _all_released(watching) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)


## Milliseconds `release_playbacks` will block the main thread waiting for the
## audio thread. Reached only when the server is genuinely slow to let go, and
## only on the way out of the process -- there is nothing left to be responsive
## for. Measured: the wait normally ends on the first or second poll.
const RELEASE_CEILING_MS := 250


## A `WeakRef` to every playback the numbered channels and the beep are holding.
##
## **Captured in a function of its own, and this is not style.** A `Ref` returned
## by `get_stream_playback()` also lands in the calling frame's temporary stack
## slot, and a slot that is not written again keeps the object alive for as long
## as the frame does -- long enough for a `WeakRef` beside it to never clear and
## for the caller to conclude the `AudioServer` never let go. That misreading
## cost this fix an afternoon: the harness written to prove the release said the
## playback was still held after ten seconds, and what was holding it was the
## harness's own `"%s" % [..., watch.get_ref()]` detail string. Returning from a
## function drops the frame and every temporary in it, which is the only way to
## be sure the reference under test is the one the engine holds.
func _playback_watches() -> Array[WeakRef]:
	var out: Array[WeakRef] = []
	for key in _channels.keys():
		_watch_player(_channels[key], out)
	_watch_player(_beep, out)
	return out


## One player's playback onto the watch list, if it has one.
##
## **Never gated on `player.playing`**, which is the trap this whole fix is about
## and which this function got wrong first time round: teardown pauses the
## playback before any of this runs, so `playing` is already false while the
## object is still there to wait for. Gating on it captured an empty list, the
## wait below returned instantly, and the pair still leaked in 1 of 6 runs --
## the same symptom as before the fix, from the same mistaken reading of the same
## property, one function further in.
func _watch_player(player: AudioStreamPlayer, out: Array[WeakRef]) -> void:
	if player == null or not is_instance_valid(player):
		return
	# **Not `playing`** -- teardown pauses the playback while the object is still
	# there to wait for, which is the whole trap this function's header records.
	# This asks the other question: does the player hold a playback at all.
	#
	# Without it `get_stream_playback()` prints `Player is inactive. Call play()
	# before requesting get_stream_playback()` once per finished channel, at exit,
	# in a suite whose entire job is to say which entries are clean. Found by
	# `tools/liveness_sweep.gd --scenes`, which exits with three channels done:
	# three engine ERROR lines that mean nothing and that a reader has to learn to
	# ignore, which is how a real one gets ignored with them.
	if not player.has_stream_playback():
		return
	var live: AudioStreamPlayback = player.get_stream_playback()
	if live != null:
		out.append(weakref(live))


## Whether every watched playback has been released. Its own function for the
## reason `_playback_watches` documents: the `get_ref()` result lives in this
## frame's temporaries and dies with the frame, so polling cannot pin the very
## object it is polling for.
func _all_released(watching: Array[WeakRef]) -> bool:
	for watch in watching:
		if watch.get_ref() != null:
			return false
	return true


func sound_busy(channel: int) -> bool:
	var ch := maxi(1, channel)
	if bool(_channel_failed.get(ch, false)):
		return false
	var player: AudioStreamPlayer = _channels.get(ch)
	if player == null:
		return false
	if not player.playing:
		return false
	# `and`, not `or`: the ceiling can only end a wait early, never extend one.
	# A `stop`, a replacement sound or a channel that finished before its stated
	# length all clear `playing` and are answered by the line above, so the only
	# case this arm decides is the one the flag gets wrong. See `_channel_until`.
	if not _channel_until.has(ch):
		return true
	return Time.get_ticks_msec() < int(_channel_until[ch])


func stop_all() -> void:
	for key in _channels.keys():
		stop_channel(int(key))


## **Unconditionally, and never `if player.playing`** -- `bugs.md` 132.
##
## `AudioStreamPlayer.playing` is not "this player holds a playback". Godot
## *pauses* a playback when its player leaves the tree rather than stopping it,
## so during teardown every channel reads `playing=false, in_tree=false` while
## its `AudioStreamPlaybackWAV` is still registered with the `AudioServer` --
## measured, printed from this node's own `_exit_tree`. A guard on `playing`
## therefore skipped the one call that had to happen, and the paused playback,
## which nothing ever mixes again, kept its stream alive past the ObjectDB check:
##
##   Leaked instance: AudioStreamWAV:...          - Reference count: 1
##   Leaked instance: AudioStreamPlaybackWAV:...  - Reference count: 1
##
## one pair per channel still sounding, in 4 of 6 `movie_churn` runs and in 3
## pairs at once on a probe that exited with three channels up. Reference count 1
## on both is the whole diagnosis: the player is gone and the server list is the
## last owner.
##
## Stopping a player that holds nothing is free -- `stop()` iterates an empty
## playback vector -- so the guard was never buying anything, and the whole of
## what it cost was the case it was reached in.
##
## Not a mix-timing race, which was the obvious candidate and is ruled out rather
## than assumed: holding the main thread in `_exit_tree` for 1.5 s, over 15
## observed `AudioServer` mixes, left 2 of 3 runs still leaking. It is the state
## the playback is parked in, not the time it is given.
func stop_channel(channel: int) -> void:
	var ch := maxi(1, channel)
	var player: AudioStreamPlayer = _channels.get(ch)
	if player != null and is_instance_valid(player):
		player.stop()
	_channel_file[ch] = ""
	_channel_failed[ch] = false
	_fades.erase(ch)
	_channel_cues[ch] = []
	_channel_cues_passed[ch] = 0
	_channel_until.erase(ch)


## `sound close <channel>` — stop, and give the channel's device back.
##
## Distinct from `sound stop` in Director, which leaves the channel allocated;
## `close` releases it, and the next `playFile` on it re-opens. Nothing here
## holds a scarce device, so the difference that survives the port is the volume:
## a closed channel is a *new* channel when it re-opens, so it comes back at
## Director's default rather than at whatever the last movie left. Written
## nowhere in the corpus this port was built on, so this is the reference's
## reading and not an observed one.
func close_channel(channel: int) -> void:
	var ch := maxi(1, channel)
	stop_channel(ch)
	_channel_volume.erase(ch)
	var player: AudioStreamPlayer = _channels.get(ch)
	if player != null:
		player.volume_db = _volume_db(VOLUME_MAX)


## A record with no file name in it is a record that names no sound, and it is
## not the same thing as `sound playFile <ch>, ""` — that is a script asking for
## nothing, which takes the channel. A score record that simply carries no name
## must leave the channel alone, or every frame entry would stop whatever a
## script had put there.
func play_frame_sounds(frame: Dictionary) -> void:
	for snd in frame.get("sounds", []):
		if typeof(snd) != TYPE_DICTIONARY:
			continue
		var file := str((snd as Dictionary).get("file", ""))
		if file.strip_edges().is_empty():
			continue
		play_file(int((snd as Dictionary).get("channel", 1)), file)


func play_click_sounds(on_click: Dictionary) -> void:
	for snd in on_click.get("sounds", []):
		if typeof(snd) != TYPE_DICTIONARY:
			continue
		var file := str((snd as Dictionary).get("file", ""))
		if file.strip_edges().is_empty():
			continue
		play_file(int((snd as Dictionary).get("channel", 1)), file)


func _ensure_player(channel: int) -> AudioStreamPlayer:
	if _channels.has(channel):
		return _channels[channel]
	var player := AudioStreamPlayer.new()
	player.name = "SoundCh%d" % channel
	player.bus = "Master"
	add_child(player)
	_channels[channel] = player
	return player


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream: AudioStream = null
	# The **container tag**, not the extension. A disc's filenames are as much a
	# guess as its paths are: `FX/DRILL.WAV` is an AIFF and `FX/BIRDS.AIF` is a
	# RIFF, in the same folder, in a game that ships 187 sounds. Choosing the
	# decoder by name sent each of those to the one that would refuse it, and a
	# sound that will not load is silent with the channel taken -- the exact state
	# `tools/sound_wait.gd` exists to prove impossible.
	#
	# `director/director_sound.gd:decode` had this right from the start, because a
	# *cast member* has no filename to be wrong about, so it had to read the tag.
	# This is the same dispatcher for the same formats, and it should never have
	# been the odd one out.
	var tag := _container_tag(path)
	# Never ask the importer about a container this port decodes itself. That is
	# already what happens on a clean checkout -- game data ships no `.import`
	# stubs, so `exists()` is false for all 12,794 sounds -- and `.gitignore` says
	# as much in as many words: "BMPs/WAVs load at runtime from source files".
	#
	# It stops being a no-op the moment the editor scans the project, which writes
	# a stub next to every `.wav` it finds. For a file whose name lies the import
	# then fails, leaving a stub pointing at a `.sample` that was never written --
	# so `exists()` answers true, `load()` fails, and four ERROR lines are printed
	# for a sound the next three lines go on to decode perfectly. The importer is
	# kept only for a container this port has no decoder for; no root holds one
	# today (0 ogg, 0 mp3 across all six), which is exactly why it must not be
	# consulted about the ones it does.
	if stream == null and not tag in ["RIFF", "FORM"] and ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is AudioStream:
			stream = res
	if stream == null and tag == "RIFF":
		stream = _load_wav_runtime(path)
	# Godot recognises neither AIFF nor AIFF-C, so a title whose sounds ship as
	# `.aif` is silent with nothing logged. See `autoload/aiff_loader.gd`.
	if stream == null and tag == "FORM":
		var error: Array = []
		stream = AiffLoader.load_from_buffer(FileAccess.get_file_as_bytes(path), error)
		if stream == null and not error.is_empty():
			GameState.emit_log("aiff %s: %s" % [path.get_file(), "; ".join(error)], "warn")
	# Neither tag, and `ResourceLoader` did not know it either: `ogg` and `mp3`
	# arrive that way and are fine, but so does a container this port cannot read,
	# and that one used to be indistinguishable from silence. `tools/sound_format_check.gd`
	# names the two the corpus holds.
	if stream == null and not tag in ["RIFF", "FORM"]:
		GameState.emit_log("sound %s: %s is no container this port decodes"
			% [path.get_file(), JSON.stringify(tag)], "warn")
	if stream != null:
		_stream_cache[path] = stream
	return stream


## A sound file's first four bytes, or `""` when it is empty or unreadable.
##
## Cheap enough to be unconditional: `_load_stream` and `_cue_points_of` each
## cache by path, so this opens a given file once per run.
func _container_tag(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var head := file.get_buffer(4)
	if head.size() < 4:
		return ""
	return head.get_string_from_ascii()


func _load_wav_runtime(path: String) -> AudioStreamWAV:
	## Minimal PCM WAV loader so audio works without editor import.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data := file.get_buffer(file.get_length())
	if data.size() < 44:
		return null
	if data[0] != 0x52 or data[1] != 0x49 or data[2] != 0x46 or data[3] != 0x46:
		return null
	var offset := 12
	var audio_format := 1
	var channels := 1
	var sample_rate := 22050
	var bits_per_sample := 16
	var pcm := PackedByteArray()
	while offset + 8 <= data.size():
		var chunk_id := data.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := data[offset + 4] | (data[offset + 5] << 8) | (data[offset + 6] << 16) | (data[offset + 7] << 24)
		offset += 8
		if chunk_id == "fmt " and offset + 16 <= data.size():
			audio_format = data[offset] | (data[offset + 1] << 8)
			channels = data[offset + 2] | (data[offset + 3] << 8)
			sample_rate = data[offset + 4] | (data[offset + 5] << 8) | (data[offset + 6] << 16) | (data[offset + 7] << 24)
			bits_per_sample = data[offset + 14] | (data[offset + 15] << 8)
		elif chunk_id == "data":
			var end := mini(offset + chunk_size, data.size())
			pcm = data.slice(offset, end)
			break
		offset += chunk_size
		if chunk_size % 2 == 1:
			offset += 1
	if pcm.is_empty():
		return null
	if audio_format != 1:
		GameState.emit_log("WAV not PCM: %s (fmt %d)" % [path.get_file(), audio_format], "warn")
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = channels > 1
	match bits_per_sample:
		8:
			stream.format = AudioStreamWAV.FORMAT_8_BITS
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:
			GameState.emit_log("WAV bits unsupported: %s (%d)" % [path.get_file(), bits_per_sample], "warn")
			return null
	stream.data = pcm
	return stream
