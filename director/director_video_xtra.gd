extends RefCounted
## Which cast members play video — the two Director ever had, under one
## predicate.
##
## Director shipped digital video twice. Cast type 10 (`#digitalVideo`) is the
## built-in member, backed by QuickTime or Video for Windows; cast type 15
## (`kCastXtra`) is a member owned by a third-party DLL, and several of those
## DLLs are video players with the same surface — `the mediaFilename`,
## `sprite(N).play()`, `sprite(N).stop()`, `sprite(N).getPlaybackEvent`. A port
## that answered only for type 10 would play `itamar-magichat`'s logo and none of
## its intro, its retro film or its twenty album clips, which is exactly the
## state `docs/DIGITAL_VIDEO.md` §6's second item describes.
##
## ## Why the symbol and not the type
##
## **566 of the 677 containers' members are type 15 and only 2 are video.**
## `tools/xtra_members.gd` counts the symbols across all eight corpora: `flash`
## (253), `animGif`/`animgif` (206), `vectorShape` (94), `text` (11) and
## `VisibleLightOnStageMedia` (2). Treating the type as the question would hand
## 564 Flash movies, animated GIFs, vector shapes and text fields to a video
## playhead, and — the half that actually breaks something — would make every one
## of them answer `the mediaFilename` and `getPlaybackEvent`, which are names
## their own Xtras do not carry. The symbol is the only thing that says what a
## type-15 member is.
##
## ## Why this table is here and a second copy is in `tools/video_census.gd`
##
## The census's copy is the *survey's*: it exists to count what a corpus holds
## and carries a human-readable reason per row, including symbols nobody has seen
## yet, because a census that only knows the symbols already found answers wrongly
## the first time a new disc arrives. This copy is the *player's*: it decides
## which members get a playhead. The two are the same set of names and must stay
## that way, which is asserted rather than hoped — `tools/video_sidecar.gd`
## checks that every symbol here is on the census's table and reports the
## difference by name if one drifts.
##
## They are not merged into one because the direction of the dependency matters:
## `tools/` reaches into the engine everywhere in this project and the engine
## reaches into `tools/` nowhere, and an engine file preloading a harness to
## borrow a constant would be the first exception.
##
## The evidence for a row is the same as the census's and is deliberately not the
## name: a symbol is here when a handler in the corpus sets `mediaFilename` on a
## member carrying it, or calls `play()` / `getPlaybackEvent` on a sprite showing
## one. That is why `flash` and `animGif` are absent — they are moving pictures
## with their own decoders and their own story — and why nothing was added
## because it sounded like a video player.

## Cast type codes, spelled out rather than written as bare numbers at the two
## call sites below. `director/director_cast.gd:TYPE_NAMES` is the same mapping
## from the other end.
const TYPE_DIGITAL_VIDEO := 10
const TYPE_XTRA := 15

## Xtra symbols whose members are video players, lowercased — `director_cast.gd`
## matches no symbol case-sensitively, because `itamar-park` spells the animated
## GIF Xtra `animgif` where `itamar-magichat` spells it `animGif`, and the same
## latitude has to apply here.
##
## Kept in step with `tools/video_census.gd:VIDEO_XTRAS`; see the header.
const SYMBOLS := {
	# Tabuleiro's DirectMedia Xtra: an MPEG/AVI/QuickTime player driven by
	# `mediaFilename`, `play()`, `stop()` and `getPlaybackEvent`.
	"directmediaxtra": true,
	"directmedia": true,
	# Macromedia's own QuickTime asset Xtras -- the type-10 member's D7 successors.
	"quicktimeasset": true,
	"qt3asset": true,
	# Macromedia's MPEG Xtra and the RealMedia one. Neither is in this corpus and
	# both are here for the reason `AGENTS.md` gives about corpus-driven scope: a
	# player that only knows the symbols this tree happens to hold is a hole that
	# surfaces the first time another title is loaded.
	"mpegxtra": true,
	"mpegadvance": true,
	"realmedia": true,
	"videosprite": true,
	# **The one Magic Hat's intro and album are built on.** `IntroRetroVideo`
	# (352x288) and `magicvideo` (320x240) both carry it, `init intro` sets
	# `member("IntroRetroVideo").mediaFilename` to
	# `<moviePath><lang>\mainmenu\intro.mpg`, and `BehaviorScript 134` polls
	# `sprite(1).getPlaybackEvent`. Visible Light's OnStage Media Xtra is an
	# MPEG-1 player with exactly that surface.
	"visiblelightonstagemedia": true,
}


## Is this member one the video playhead answers for?
##
## The one predicate every caller uses, so that "what counts as a video" is
## decided in one place. `preview/video.gd` asks it before opening a reader,
## `preview/media.gd` before storing a `mediaFilename` write, and
## `preview/stage_paint.gd` before drawing a frame.
static func is_video(member: Dictionary) -> bool:
	return is_digital_video(member) or is_xtra(member)


## Cast type 10 — Director's built-in digital video member.
static func is_digital_video(member: Dictionary) -> bool:
	return str(member.get("type_name", "")) == "digitalVideo"


## Cast type 15 whose Xtra is one of the video players above.
##
## A member whose specific block could not be read carries no `xtra_symbol` at
## all — an *external* Xtra's block is the link rather than the envelope, and
## `director_cast.gd`'s type-15 arm returns before reading one. Such a member
## answers false here, which is the honest state: nothing in the file says what
## DLL owns it, so nothing here can claim it is a video.
static func is_xtra(member: Dictionary) -> bool:
	if int(member.get("type", 0)) != TYPE_XTRA:
		return false
	return SYMBOLS.has(str(member.get("xtra_symbol", "")).to_lower())
