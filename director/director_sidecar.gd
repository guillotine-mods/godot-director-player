extends RefCounted
## Where a transcoded copy of a media file lives, and whether the one on disc is
## still the one the source would produce.
##
## ## The problem this is the smallest possible answer to
##
## `docs/DIGITAL_VIDEO.md` §1 counts 22 MPEG-1 files, 197.3 MB, behind two
## `VisibleLightOnStageMedia` Xtra members in `itamar-magichat`. Godot decodes
## Ogg Theora and nothing else; §4C2 costs an MPEG-1 decoder in GDScript at 2.5
## Mpix/s of IDCT and refuses it, and §4D refuses a native plugin because it is a
## per-ABI dependency and a licensing decision the owner has not made. §4B — a
## transcode — is the only remaining way to get pictures, and the document's own
## objection to it is the one this file exists to remove:
##
## > **It writes into the corpus.** `games/` and `test-games/` are the owner's
## > data and are not to be modified; the transcodes would have to live somewhere
## > else and the resolver would need a second search root.
##
## So they live somewhere else. `user://` is the writable side of this project on
## every platform it targets — `docs/ANDROID.md` establishes that for the mobile
## export, where `res://` is inside the APK and nothing under it can be written
## at all — and a cache under it is the same shape as a shader cache or an
## imported texture: derived from an input the engine still reads, reproducible
## from it, and safe to delete.
##
## **Nothing is ever written under `games/` or `test-games/` by this port**, and
## that is not a convention this file follows, it is the reason it exists.
##
## ## Why this is not "the engine stops reading the original media"
##
## The engine still opens the original container, still reads the original cast
## member, and still resolves the member's own `the fileName` / `the
## mediaFilename` against the disc the way Director did. What changes is one
## step: when the *media stream* behind that name is in a format nothing here can
## decode, a decodable copy of it is played instead. That is what an operating
## system does with a codec it lacks and a transcoding filter it has, and it is
## the same substitution `preview/video.gd` already performs when it hands
## Director's MS-RLE bytes to an `Image` instead of to Video for Windows.
##
## The claim that would be worth refusing is a *corpus* rewrite — media replaced
## on disc, so that the original files stop being what the engine reads. That is
## not this, and the difference is exactly the `user://` boundary.
##
## ## The key, and why it is the path rather than the contents
##
## A sidecar is keyed by the **absolute path of its source**, normalised and
## hashed. Not by the source's contents, which would mean reading 15 MB to
## decide whether to open a 2 MB file, on every property read, for a member a
## movie polls once per tick. Not by the file name alone, which collides the
## moment two corpora both ship a `heb/album/magic1.mpg` — and both Itamar discs
## in this tree have the same layout under different roots.
##
## Staleness is then the one question the path cannot answer, and it is answered
## by modification time: a sidecar older than its source is one made from a file
## that has since changed, and it is ignored exactly as if it were absent. That
## is weaker than a content hash and it is the trade the paragraph above
## describes; it is also what every build system in existence uses, and the
## failure mode — a source touched without being re-transcoded plays the old
## picture — is visible, recoverable by deleting one file, and reported by name
## in `tools/video_sidecar.gd`'s status listing.
##
## ## What is not here
##
## No transcoder. This file finds and validates; `tools/video_sidecar.gd` is what
## produces, and it is a tool the owner runs deliberately rather than something
## that happens behind them — 197 MB of encoding is not a side effect a property
## read should have. A missing sidecar is not an error and is never repaired
## automatically: it falls back to whatever the engine could do without one,
## which for MPEG-1 is Director's own "no codec installed" and is a clean skip.

## The format a sidecar is in. Ogg Theora with Vorbis audio, because it is the
## only video format Godot 4 decodes with no addon, no GDExtension and no native
## dependency — which is the whole constraint this approach exists to satisfy.
const EXTENSION := "ogv"

## Where the cache lives. Under `user://` for the reason the header gives, and in
## a directory of its own so that deleting the transcodes is one `rm -r` and
## cannot take anything else with it.
const CACHE_DIR := "user://video-cache"

## How many hex digits of the path digest name the file. 16 is 64 bits: a corpus
## would need on the order of four billion distinct media paths before two
## collided, against 439 in the whole tree.
const KEY_DIGITS := 16


## Where the sidecar for a source file would go, whether or not it exists.
##
## The stem of the source is kept in the name purely so that a human listing the
## cache can tell `intro-3f2a…​.ogv` from `magic7-91be…​.ogv`; the digest is what
## actually identifies it, and two sources with the same stem in different
## directories get different files.
static func path_for(source: String) -> String:
	if source == "":
		return ""
	return CACHE_DIR.path_join("%s-%s.%s" % [
		_stem(source), key_for(source), EXTENSION])


## The digest half of a sidecar's name: SHA-256 of the normalised absolute source
## path, truncated.
##
## **Normalised before hashing**, and both halves of that matter on the platform
## this port is developed on. Windows opens `C:\games\X.mpg` and `c:/games/x.mpg`
## as the same file, so a key that distinguished them would transcode the same
## source twice and then fail to find either copy from the other spelling; the
## engine's own resolver already answers a mix of separators, because Director
## allowed `:`, `\` and `/` and the same title used more than one.
##
## Case is folded on every platform rather than on Windows alone. That is
## deliberately wrong in one direction — two files on a case-sensitive
## filesystem differing only in case share a key — and right in the direction
## that matters: a key computed on the machine that ran the converter has to
## match the key computed on the machine that plays, and a rule that changes with
## the host is a cache that silently misses after a checkout on another OS.
static func key_for(source: String) -> String:
	var normal := ProjectSettings.globalize_path(source).replace("\\", "/").to_lower()
	while normal.ends_with("/"):
		normal = normal.substr(0, normal.length() - 1)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(normal.to_utf8_buffer())
	return context.finish().hex_encode().substr(0, KEY_DIGITS)


## The sidecar to play for a source file, or `""` when there is none to play.
##
## The two conditions are the whole of the resolution rule
## `preview/video.gd:reader_for` implements: the file has to be there, and it has
## to be **at least as new as its source**. Anything else — absent, stale,
## unreadable — answers `""`, and the caller's fallback is what happens then.
##
## `>=` rather than `>`, because a transcode that finishes in the same second as
## a `touch` of its source is fresh and a strict comparison would call it stale
## for ever. Modification times on FAT are two-second granular besides.
static func fresh_for(source: String) -> String:
	if source == "" or not FileAccess.file_exists(source):
		# **No source, no sidecar**, even when a file with the right name sits in
		# the cache. A member pointed at media that is not on the disc must go on
		# answering exactly what it answered before this feature existed —
		# `logo.dir` #27 `prelogo` names a `prelogo.avi` that was never shipped,
		# and `tools/video_fallback.gd` asserts it reports a duration of 0. A
		# cache hit for a file the disc does not have would break that, and it
		# would break it in the direction that hangs.
		return ""
	var sidecar := path_for(source)
	if not FileAccess.file_exists(sidecar):
		return ""
	if FileAccess.get_modified_time(sidecar) < FileAccess.get_modified_time(source):
		return ""
	return sidecar


## `"missing"`, `"stale"` or `"fresh"` — the same question `fresh_for` answers,
## split so that `tools/video_sidecar.gd` can tell the owner *why* a clip is not
## playing. One reader for both, so the status listing and the engine can never
## disagree about which sidecars are live.
static func status_of(source: String) -> String:
	if source == "" or not FileAccess.file_exists(source):
		return "missing"
	var sidecar := path_for(source)
	if not FileAccess.file_exists(sidecar):
		return "missing"
	if FileAccess.get_modified_time(sidecar) < FileAccess.get_modified_time(source):
		return "stale"
	return "fresh"


## Make sure the cache directory exists. Called by the converter before it
## writes, and by nothing on the playback path — the engine only ever reads here,
## so a player that never transcodes never creates a directory.
static func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(CACHE_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(CACHE_DIR) == OK


## Every sidecar currently in the cache, as absolute `user://` paths. Used by the
## converter's listing and by nothing in the player.
static func existing() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if str(name).get_extension().to_lower() == EXTENSION:
			out.append(CACHE_DIR.path_join(str(name)))
	return out


static func _stem(source: String) -> String:
	var stem := source.replace("\\", "/").get_file().get_basename()
	var clean := ""
	for i in stem.length():
		var c := stem[i]
		clean += c if c.is_valid_identifier() or c.is_valid_int() else "_"
	return clean.substr(0, 24) if clean != "" else "media"
