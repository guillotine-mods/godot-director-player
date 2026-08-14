# Known engine gaps, not yet implemented

Behaviour the reference describes and this port does not have. The full
descriptions are in [`DIRECTOR_ENGINE.md`](DIRECTOR_ENGINE.md) and
[`LINGO_SURFACE.md`](LINGO_SURFACE.md).

Entries were verified against ScummVM's Director engine and, where noted, against
"this repo's own working renderer" — which meant `movie_player.gd` /
`render_model_loader.gd`, drawing from a pre-decoded export. **That renderer has
been deleted.** A note here saying the two agreed is still evidence about
Director, and is not a statement about the live code; several such notes turned
out not to hold once checked against `scenes/preview/`. Two cost real debugging
time: `intersects` was listed as implemented while only the retired host bound
it, so every inventory drop in every title silently evaluated to nothing.

This is a work queue, not a bug list — nothing here is a mystery. Each item says
what Director does, what happens without it, and where the change goes. Ordered
by how visible the absence is.


## The reference map

**Reference names not live here: 114.** `tools/lingo_surface_audit.gd` reads
Director's own name tables out of `reference/scummvm/` -- 506 capabilities this
port can reach -- and pins how many of them are live. §19 measures the gaps a
*title in this corpus calls*; this measures the gaps against Director itself,
which is the wider and the more honest number. A name no Piposh or Rating
script happens to use is invisible to §19 and counted here.

The number is pinned so it cannot drift: if it falls, say which names landed;
if it rises, a binding stopped being live or the reference tree gained a name,
and neither should pass silently.

### What moved, and where the denominator went

It was **287 of 511**, then 173, then 130, and is 114 of 506. The most recent 16
are the object model, the frame callouts and the cast-library reads, and they
have their own section immediately below this one.

The 43 before them: **40 are the
digital-video block below, plus `the currentSpriteNum` and `xtra`**: 18 member
properties, 14 sprite properties that make up a video sprite's playhead, the 5
track and cue-point builtins, `the digitalVideoTimeScale`, `xtra` and `the
currentSpriteNum`. What that closed is the *surface*, not the playback, and the
distinction is written out in the block itself and in
`scenes/preview/media.gd`'s header rather than left to be inferred from a count
going down. The other 3 landed beside them and have their own entries:
`updateStage`, `puppetTempo` and the first of the timeout properties. The five names that left the
denominator are named in `tools/lingo_surface_audit.gd:INAPPLICABLE`, with the
reason per name: `openDA`, `closeDA`, `openResFile`, `closeResFile` and
`showResFile` address classic Mac OS system services -- desk accessories and the
resource fork -- which exist on no platform this engine runs on, so no
implementation could be written and the rows would be red for ever. That is the
only content exclusion there is, and the bar for it is deliberately *not* "we
have not built it": everything unbuilt is still counted.

Of the 109 that went live, a third were never missing. A property read is a
**chain** -- interpreter, then host, then the preview node, then the property
tables -- and the audit read only the last stage, so six sprite properties the
host and the node answer first (`the loc`, `the rect`, `left`, `top`, `right`,
`bottom`) were reported "stored in _overrides, consumed by nothing", and `the
itemDelimiter` was reported `absent` while three chunk functions consumed it.
§19's own `loc` row says the count was "one higher than the truth"; it was six.
Two scan anchors were wrong in the same way -- the member scan stopped at the
first `return 0` in `read_prop`, which hid thirty arms once that function grew
one -- and the probe reported `getPref`, the one arm whose correct answer is
VOID, as the one arm that is not there.

The rest were real, and mostly the same shape: a fact the engine already held
with no spelling to ask for it. See the two commits, `lingo: 45 Director names
this port could already answer` and `members: 46 properties a member could
answer about itself`.

### The 16 that landed with the object model and the frame callouts

Not a subsystem's worth of surface this time but four small ones, and the first
is the one the other three hang off.

**§7.1's object model** (`lingo/lingo_object.gd`). `send`, `call`,
`sendAncestor`, `callAncestor` and `script` are live, and `new` with them --
`new` is not in the reference's builtin table, because Director's compiler emits
it directly, so it moves the count by nothing and had to be built anyway. An
object is a script plus a bag of properties plus an `ancestor` property, and
both lookups walk the chain: a message the child does not answer goes up, and so
does a property the child does not declare. `me` is an ordinary first parameter,
which is what Director makes it.

Three things had to change under it and each was its own hole:

- **`#symbol` literals did not lex.** §16.2 recorded it as a known gap that
  "fails loudly", on the grounds that no corpus script writes one. Every object
  message is written `call(#mouseUp, obj)`, so the messaging half of §7.1 could
  not be spelled at all.
- **A dot was part of an identifier**, inherited from the Python compiler, so
  `myObject.pTag` lexed as one token named `myobject.ptag`. `member(x).name` was
  unaffected because the dot there follows a `)` -- which is exactly why it
  survived: the corpus's only dot spelling is the one shape the rule did not
  break. **0 identifier tokens contain a dot across all 38,396 scripts under
  `games/`**, measured before the rule was changed.
- **`script "base"` parsed as a command call**, whose argument loop crosses
  commas, so `new(script "base", who)` handed the constructor's arguments to the
  designator. Every property a parent script set from an argument came out 0.

**The timeout family and the per-frame callouts** (`scenes/preview/actors.gd`).
`the timeoutLength`, `timeoutLapsed`, `timeoutMouse`, `timeoutPlay`,
`timeoutScript`, `the actorList` and `the perFrameHook` are live, and `the
timeoutKeyDown` stopped being the inert store §19 recorded. The frame loop calls
out once per step for `stepFrame` -- the hook, then the list, at
`score.cpp:731-770`'s point in the step -- and checks the timeout once per engine
*tick*, which is `Score::update`'s "independently of the frame delay" and matters
because a movie held on `go to the frame` takes no steps at all. `the
timeoutScript` is the fifth `*Script` property and shares tier 1's machinery.

`AGENTS.md` named `timeout` and `stepFrame` among the calls already made the
wrong way; both are made now. **`beginSprite` and `endSprite` are sent now too**
(`scenes/preview/frame_loop.gd:sync_sprite_lifetime`, covered by
`tools/sprite_lifetime.gd`): the lifetime is the score's own span, the behaviour
channel counts as sprite 0 and gets both, and the messages stop at the sprite
tier. What is still not sent is `stepFrame` *to a sprite's own behaviours*, which
is a different mechanism -- a message per sprite, not per actor -- and stays in
the list below.

**`the updateLock`** is live and is the other half of `updateStage`. The
reference implements neither the read nor the write, so what is built is the
property's documented meaning, and the engine's own repaints are deliberately
outside it.

**`the name`, `the fileName` and `the number of castLib`**
(`scenes/preview/cast_libs.gd`). §5.1's third qualified entity had no dispatch
path at all: `the name of castLib 2` fell through to a property of a
*command-form call* to an unbound handler named `castlib`, so it reported a
missing builtin and answered VOID. `the preLoadMode` and `the selection` are
deliberately still absent and the module says why for each.

## What the remaining 114 are waiting for

Grouped by the subsystem each needs, because they are not 114 independent
tasks -- half of them land together or not at all. Counts are from the audit's
own grouping, and it prints the names.

**Digital video -- the surface landed, the playback did not.** 38 of the ~40
names are bound (`scenes/preview/media.gd`): 18 member properties, the 14 sprite
properties that make up the playhead, the five track and cue-point builtins, and
`the digitalVideoTimeScale`. A movie can now drive a video sprite -- set `the
movieRate`, the in and out points, `the volume`, read every one back, ask a
member for its duration, its cue points, its sample rate -- and get Director's
answers. `docs/LINGO_SURFACE.md` §19 carries the rows.

**One format of media now opens, and the rest still does not.**
`director/director_avi.gd` is a RIFF AVI reader and a Microsoft RLE (`mrle`,
`BI_RLE8`) decoder in GDScript -- `docs/DIGITAL_VIDEO.md` option C1, the one piece
of decoder work that document recommends -- and **both** `#digitalVideo` members in
all eight corpora point at that format. So a type-10 member whose file is an
MS-RLE AVI answers a real duration, plays, and draws its frames
(`scenes/preview/video.gd`); `tools/avi_decode.gd` measures it at **16.2 ms per
frame mean** for `logo.avi`'s 640x480, against a 90 ms budget at its own 11.11 fps.

QuickTime and MPEG-1 still cannot be opened, and neither can an AVI whose file is
missing. That is *reported* rather than papered over, and it is the same fallback
it always was: `the mediaReady of member` answers FALSE, the duration is 0, there
are no cue points and there are no tracks -- which is exactly what Director
answers for a video whose file is missing or whose codec is not installed.
`logo.dir` #27 `prelogo` is that state and stays in it, because `startMovie`
repoints it at a `prelogo.avi` that is not on the disc.

**That is a settled decision now rather than an open one, and
[`docs/DIGITAL_VIDEO.md`](DIGITAL_VIDEO.md) is where it is written down** -- the
census over all eight corpora, what each title loses, and four options costed
against each other. The two numbers that decide it: **the six shipped titles hold
0 video members, 0 video sprites and 0 bytes of video media**, and the one title
that has any degrades cleanly on all three of its video frames rather than
hanging on one (`tools/video_fallback.gd`, all eight roots green). The
recommendation is to leave the MPEG-1 decoder alone and build the two items that
are Director's own and need no decoder -- the specific block below, and the Xtra
sprite methods.

Two of the three things that were open under it have closed, and the third has
not:

- **The playhead advances now, for media that opened.**
  `scenes/preview/video.gd:advance` steps every playing channel by real time once
  per engine tick -- not per score step, because the movie that needs it is
  standing still on `go(the frame)` while it waits. It stays frozen for a member
  with no media, which is what makes Magic Hat's `Check avi` skip rather than
  hang. Both halves are asserted by `tools/video_fallback.gd`.
- **The authoring flags come out of the member's own specific block.** `the
  controller`, `directToStage`, `video`, `sound`, `crop`, `center`, `frameRate`,
  `pausedAtStart`, `loop` and `preLoad` are decoded by
  `director/director_cast.gd:_parse_specific`'s type-10 arm -- twelve bytes, a
  rect and one flag word, per `castmember/digitalvideo.cpp` -- and read back
  through `preview/media.gd:VIDEO_FLAG_KEYS`. Measured against `logo.dir` #27 and
  #28, whose 640x480 rect agrees with the media's own `BITMAPINFOHEADER`, with the
  score's recorded sprite size, and with the centre registration the sprite's
  `loc` implies.

  **`the scale of member` is the one that still answers a default**, and it is
  not the same gap: it is D7's playback-size percentage pair, it lives in no D5
  specific block, and 1.0 is the unscaled size the member actually has.
- **`the media of member`** is deliberately still absent: Director hands back a
  duplicate of the member's media as an object assignable into another member,
  and that needs the mutable cast below.
- **Still no decoder for QuickTime or MPEG-1 in this project**, and
  `docs/DIGITAL_VIDEO.md` §4 costs both: each needs a native, per-ABI dependency
  in a project that is pure GDScript against stock Godot, for one unshipped test
  title's intro. **What changed is that the engine can now use one it did not
  ship.** `scenes/preview/video.gd` has a third backend behind
  `director/director_plugin_video.gd`, gated on `ClassDB.class_exists` rather
  than on a `preload` of an addon path, so a decoder GDExtension the owner
  installs can play the 22 MPEG-1 clips from the original bytes and an absent one
  changes nothing at all — `tools/video_plugin.gd` in `gate.sh`'s `ALL` asserts
  the second half. `docs/DIGITAL_VIDEO.md` §8 is the install and which parts of
  the plugin's API are confirmed from its source versus inferred.

  **"Can play" is now known to be conditional, and the one extension anybody has
  tried does not satisfy it.** EIRTeam.FFmpeg 1.1.4 was installed and run
  (§9): its bundled FFmpeg is the `lgpl-godot` variant, built
  `--disable-demuxers --disable-decoders` with mov/matroska/avi/flv/aac and
  h264/vp9/mpeg4/aac/mp3 re-enabled. **No MPEG-PS demuxer, no MS-RLE decoder** —
  it opens 0 of this tree's 23 media files. Every *engine-side* inference §8 made
  held, including the one that mattered: `logo.avi` opened, found no decoder,
  reported no duration, and was refused rather than becoming a ready member with
  a frozen playhead.

  So this line stays and is now stronger than "nothing here ships one": out of
  the box there is no decoder for either format, and the obvious extension does
  not supply one either. Closing this properly still wants either C1 (the
  reference's own MS-RLE/type-10 work) or an FFmpeg build configured for the
  formats a 1990s Director title actually holds.

Two smaller things sit beside it. The tempo channel's video waits are **built on
the clock side and unwired on this one**: `director_score.gd` decodes
`wait_video_channel` in both numberings, `director_frame_clock.gd` holds the
playhead for it, and the wait is released by a `video_probe` callable nobody
installs. With none installed every video wait completes on its first poll, which
is what Director answers for a channel holding no video and is the right answer
while there is no media. When there is, the probe is one line and its contract is
the reference's condition -- keep waiting while the channel is an active video
**and** its rate is non-zero, so `Media.channel_state(host, channel)["rate"] != 0.0`
beside whatever answers "this channel is playing a video". And `trackCount(sprite N)`
versus `trackCount(member "x")`: the parser evaluates a sprite reference to its
channel number and a member reference to a packed `(library, slot)` integer, so
both arrive at a builtin as a bare integer and the spelling is gone. The five
builtins read the argument as a **sprite channel**, which is the form every one
of Director's own examples uses; a member-side call needs the reference to
survive the argument, which is a parser change.

**The sound-member half of the same surface is real and is unexercised.** `the
duration`, `the cuePointNames`, `the cuePointTimes`, `the sampleRate`, `the
sampleSize`, `the channelCount` and `the mediaReady` of a `#sound` member are
computed from the member's own bytes through `director/director_sound.gd`, which
decodes all three shapes Director wrote. No cast in any of the six titles holds a
sound member -- every sound these games play is an external `.aif` reached by
`sound playFile` -- so that path is written from the decoder and confirmed by
nothing. The first title that ships a sound member is what will check it.

**Score recording (8 builtins).** `beginRecording`, `endRecording`,
`updateFrame`, `insertFrame`, `deleteFrame`, `duplicateFrame`, `clearFrame`, and
the write half of the eight frame properties `the frameScript`, `the frameLabel`,
`the frameTempo`, `the framePalette`, `the frameTransition`, `the frameSound1`/`2`
now read (Director makes those writable inside a recording session and read-only
outside one, which is what they are here). *What it would take:* a mutable score.
`director_score.gd` decodes a delta stream into a per-frame snapshot and there is
no path back; recording needs the snapshot to be the authority and the stream to
be re-derived from it, or a per-frame override layer the frame loop merges the
way `preview/channel.gd` merges a sprite's.

**Xtras and XObjects (`openXlib`, `closeXlib`, `showXlib`, `xFactoryList`,
`factory`, `the interface of member`).** §7.3.

**The registry is no longer empty and the object model is built.** `xtra`
resolves a name or a 1-based index against the same registry `the xtras` reads,
with §7.3's name normalisation on both sides, and reports by name when it finds
nothing; `new(xtra("FileIO"))` makes an instance; and the interpreter dispatches
a method on a native object in both of Director's spellings -- `openFile(f, p,
1)` and `f.openFile(p, 1)`. `lingo/lingo_xtra.gd` is the protocol
(`lingo_responds_to`, `lingo_message_list`, `lingo_perform`), which is §7.3's
"a stubbed Xtra must answer the standard set" made into an interface rather than
a convention.

**Two Xtras are implemented, FileIO and BuddyAPI**, and both are worth more than
a dozen of the names above because they are what titles are *blocked on*.
Two movies pointed at this engine stop at startup without it, both while reading
a configuration file: `itamar-park` reads `safari.ini` into a field and parses
`[PATH]` .. `[ENDINI]` out of it to fill `the searchPaths` and choose a language,
and `itamar-magichat` carries `fileexist`, `loadfiletofield`, `copyfile`,
`deletefile` and `externalfileok` across its movie scripts. Neither has a Lingo
problem: both decompile, parse, compile and load. Measured after: `itamar-park`
now completes its ini parse -- `Languages ["hebrew"]`, seven entries in `the
searchPaths`, `CDpath` and `HDpath` set, and no `[ENDINI]` alert.

Two things are deliberately *not* in it, and each is named rather than left to be
found: **`getOSDirectory`, `displayOpen`, `displaySave` and `setFilterMask`** --
the first names a directory this player has no business writing to and the other
three are file dialogs, which a movie under a headless harness cannot be shown;
and **writes are refused** in a headless run without `--allow-writes`
(`-45`, locked, which is a real Xtra code) and outside the game root always
(`-37`, bad file name). The header says why: the corpus is six git submodules and
a movie calls `createFile` from its own Lingo without any tool asking for one.

**BuddyAPI is the second** (`lingo/lingo_buddyapi.gd`), and it is the one with a
measured consequence: `itamar-magichat`'s `ReadConfigLine` is one line,
`baReadIni(Section, Option, EMPTY, gIniFileName)`, and with the name unbound the
interpreter answered the integer 0, the movie's own `if tmp = EMPTY` fallback was
skipped, `#startFrame` became 0 and the playhead never left frame 0. Bound, the
playhead leaves frame 0 on the first tick and plays the intro loop, frames
124-138 (`bugs.md` 78 is closed on that measurement).

Its shape is not FileIO's, and the difference is the design rather than a detail:
**every `ba*` name is a global builtin**, so they are arms of `call_builtin`
rather than methods on an instance, which is what the reference does
(`budapi.cpp` registers all of them `HBLTIN` and gives the Xtra object only `new`
and `name`) and what all 46 sites in `itamar-magichat` write. The registry entry
exists so that `the xtras` and `xtra("BudAPI")` agree with the player about what
is loaded, and for nothing else.

Fourteen names are live and §19 has a row for each: the ini set (`baReadIni`,
`baWriteIni`, `baFlushIni`), the file set (`baFileExists`, `baFileSize`,
`baDeleteFile`, `baCopyFile`, `baRenameFile`, `baFileList`, `baFolderList`,
`baFolderExists`, `baCreateFolder`, `baDeleteFolder`) and `baOpenURL`, which
**declines and reports** rather than handing the host OS a URL a movie read out
of a configuration file. `tools/buddyapi_xtra.gd` is the harness.

*What is still missing from BuddyAPI*, in the order it is worth building:
`baCopyXFiles`, `baXCopy`, `baDeleteXFiles`, `baXDelete` and the
`baFindFirstFile`/`baFindNextFile`/`baFindClose` iterator -- the bulk and
iterator forms of file operations that are here singly, all well-defined and
none of them called by anything in reach. Everything else in the published API is
absent for a reason written per name at the bottom of `lingo_buddyapi.gd`'s
header: an `InfoType` string whose accepted values are not sourceable
(`baVersion`, `baSysFolder`, `baCpuInfo`, `baDiskInfo`, `baFileAttributes` …),
something that changes the machine or launches a program (`baRunProgram`,
`baShell`, `baExitWindows`, `baSetDisplay` …), or a subsystem there is nothing
here to answer about (the registry, the window handles, the Start Menu). An
absent name is reported by the unbound-name diagnostic; a bound one that answered
something invented would not be.

*What is still missing:* `openXlib`, `closeXlib`, `showXlib` -- loading a real
`.x32` or XObject library, which is native code this port cannot run -- and
`factory` / `xFactoryList`, which are D3's version of the parent-script model and
could now be built on `lingo/lingo_object.gd`. The corpus's only two `xtra` sites
are `xtra(#net, 2, ...)` in Piposh Dream's `ratA.dir`, inside a handler nothing
calls, with three arguments where Director takes one -- an arity error in 1997
and reported as one now.

**Menus (`installMenu`, `menu`, `menuItem`, `the name of menu`, and menuItem's
`checkMark`, `enabled`, `name`, `script`).** *What it would take:* a menu bar.
Director's `installMenu` reads a **field member** whose text is the menu
definition, so the parsing is small; what does not exist is anywhere to put the
result. No title in this corpus installs one.

**Cast authoring (`erase`, `move`, `findEmpty`, `importFileInto`, `save`,
`copyToClipBoard`, `pasteClipBoardInto`).** *What it would take:* a mutable cast.
`director_cast.gd` parses a container read-only and `director_writer.gd` writes
one back from the playing movie's field overrides; between them there is no
in-memory member a script can create, erase or move.

`script` has left this entry: it is a *reference* to a script member, not an
authoring verb, and it is live. So have three of `castLib`'s five properties --
`the name`, `the fileName` and `the number` are answered from the movie's own
`MCsL` mapping and need no mutable cast, because they are read-only in Director
too. The two that remain are `the preLoadMode`, which has no consumer here (this
port loads on demand, which *is* mode 0, and the preloader has no notion of a
library), and `the selection`, which is the Cast window's selection and has no
runtime meaning. Both are left absent rather than stored; the reasons are in
`scenes/preview/cast_libs.gd`.

**Text metrics (`charPosToLoc`, `locToCharPos`, `linePosToLocV`,
`locVToLinePos`, `lineHeight`, `scrollByLine`, `scrollByPage`, and the nine
`chunk` properties -- `the textFont of word 3 of field "x"`).** *What it would
take:* `preview/text_art.gd` to expose the laid-out glyph boxes it already
computes, and the parser to carry a chunk expression as a *property target*
rather than as a value (§11.8). The chunk properties additionally need STXT's
style **runs**; `director_cast.gd:_read_stxt_style` reads the first run only,
which is what `the textSize of member` answers from.

**The idle-load queue (`cancelIdleLoad`, `finishIdleLoad`, `idleLoadDone`, and
`the idleLoadMode`, `idleLoadPeriod`, `idleLoadTag`, `idleReadChunkSize`,
`idleHandlerPeriod`).** `director/director_preloader.gd` already walks ahead of
the playhead on a millisecond budget, which is the mechanism; what it has no
notion of is a *tagged* queue a script can add to, cancel and ask about.

**~~The timeout family and `the actorList` / `the perFrameHook`~~ -- done**, and
**`beginSprite`/`endSprite` with them.** See the section above. The instances and
the lifetime this entry asked for exist: `LingoInterpreter.behaviour_instance`
owns one object per (channel, script) and `release_behaviour` drops it,
`director_preview.gd:_begun_sprites` is the record of what is on stage, and
`frame_loop.gd:sync_sprite_lifetime` diffs it against the score's spans at every
frame entry. What is left of the shape this entry described is `stepFrame` to a
sprite's own behaviours and `prepareFrame` per channel; `the scriptInstanceList
of sprite` is still `inert`, and `sendSprite`/`sendAllSprites` still message the
behaviour's *script* rather than reaching the instance the frame loop now keeps
-- which is the next thing to join up, because the two now disagree about what
`me` is for the same sprite.

**~~`updateStage` (3,717 sites)~~ -- done; `the updateLock` is what is left.**
`updateStage` paints and presents from inside the handler
(`director_preview.gd:repaint_now`), which the entry this replaces said was
impossible. It was not, and the reasoning is worth keeping because the shape
recurs: the measurement behind it -- `queue_redraw()` followed by
`RenderingServer.force_draw()` leaves `_draw` unrun, because the redraw callback
is on the message queue and GDScript cannot flush it -- was correct and is still
asserted every run. The *inference*, that Godot therefore cannot present
synchronously, was not: `force_draw` presents the commands a canvas item already
holds, so the answer was to write those commands directly. `director/director_paint.gd`
does, `_draw` and `repaint_now` are two entry points into one `_paint`, and the
predicted "whole of `stage_paint.gd`, `sprite_art.gd`, `text_art.gd`,
`film_loop_view.gd` and `trails.gd`" turned out to be about twenty call sites,
because `Texture2D.draw`, `Texture2D.draw_rect` and `Font.draw_string` already
take a canvas-item RID and only `draw_rect` needed writing out. Measured on
4.7.1 with a 32-sprite frame of `SEA1.dir`: the paint costs 4.5-6 ms and the
present 25-30 ms, the second being two vsync intervals, so a Lingo animation
loop steps at about 30 fps -- inside the 10-30 ms per redraw the machines these
titles shipped for managed, and the reason vsync is left alone rather than
turned off for the duration of a call (without it the pair costs 5.3 ms).
Idle rooms call it **zero** times in twenty seconds, in `strtgame`, `SEA1`,
`MAP` and `DAY1` alike, so the cost is paid only where the animation is.

*What is left:* nothing. `the updateLock` is live, and the shape this entry
predicted is the shape it took -- a flag both `repaint_now` and the frame loop's
repaint honour, the second through `director_preview.gd:stage_redraw`. The
reference declares `kTheUpdateLock` and implements neither half, so the
behaviour is the property's documented meaning rather than a copy: the paint is
**skipped, not queued**, because a lock that queued would make the first
`updateStage` after it present a stale frame. 0 corpus sites.

**`the currentSpriteNum` -- done.** The channel is on the chain element now
(`preview/event_chain.gd:element`), `run` sets it on the host around the one tier
of the five that is a sprite behaviour and restores what it found, and
`sendSprite`/`sendAllSprites` bracket their sends the same way. A cast script, a
frame script and a movie script read 0 during the same click, which is Director's
answer. `beginSprite` and `endSprite` are the second place that sets this field
and they do (`frame_loop.gd:send_sprite_message`, saved and restored the same
way). `stepFrame` to a sprite's own behaviours is the third and is still absent;
the timeout entry below is where it is queued.

**~~Object messaging (`send`, `call`, `sendAncestor`, `callAncestor`)~~ --
done**, with `script` and `new`. See the section above. `sendSprite` and
`sendAllSprites` still message a behaviour's *script* rather than an instance,
which is the residue and is filed with the per-sprite messages.

**Named individually, each its own small thing:** `mci`/`mciWait` (the Windows
MCI string interface -- CD audio and video, a real capability this port could
talk to), `zoomBox` (an animated rectangle between two sprite rects),
`puppetTempo` (§9.1 gives it precedence over the score's tempo; the consumer is
`director/director_frame_clock.gd`), `playAccel` (undocumented D2),
`setCallback`, `the score` and `the scoreSelection` (the score as binary data,
and an authoring-only selection), `the stageColor`, `the buttonStyle`, `the
checkBoxAccess`/`checkBoxType`, `the searchCurrentFolder`, `the
emulateMultiButtonMouse`, `the paletteMapping`, `the alertHook`, `the
soundDevice`/`soundKeepDevice`, `the mouseChar`/`mouseWord`/`mouseItem`/
`mouseLine` (which want the text metrics above), and the memory and CPU budgets
`the preLoadRAM`, `the preLoadEventAbort`, `the cpuHogTicks`, `the
netThrottleTicks`, `the fixStageSize`, `the fullColorPermit`, `the imageDirect`,
`the switchColorDepth`, `the updateMovieEnabled`, `the traceLoad`.

**Every one of the last group is deliberately unbound rather than stored.** A
movie property this host keeps and nothing consults is the `moveableSprite`
shape one level up: it round-trips perfectly, reads as implemented from every
direction, and does nothing. Each of them is waiting for its consumer and not
for its setter.

**The write half of the member properties** is the other honest gap in what did
land. 46 of them are readable and only `text`, `editable` and `hilite` can be
written, because a write to `the textSize of member` has to reach
`preview/text_art.gd` and a write to `the pattern of member` has to reach
`sprite_art.gd`, and neither consults an override table today. A member write
with no arm is now *reported* (`LingoDiagnostics.MEMBER_PROP`, which had never
once been emitted), so the next session can see which ones a title actually
reaches instead of guessing.

## What is genuinely still missing

Corrected against the code on 2026-08-06, after the windows, palette, trails,
sound and preload work landed, and re-checked on 2026-08-07 after the player was
split into `scenes/preview/`. `DIRECTOR_ENGINE.md` §17 is the full table; this is
the short list of what has no implementation at all.

**Compiled Lingo (`Lscr`) is not decoded, and the corpus proves it costs nothing.**
The port runs Lingo from the **source text** stored in each cast member's info
block (`director_cast.gd`, info item 0); nothing reads the `Lscr` bytecode
Director actually executed, nor `Lctx`/`Lnam` beside it. Measured over all six
roots on 2026-08-13: **38,474 members carry a script, 64 of them carry a
`script_id` with no source text, and 0 of those 64 have a single handler.** Their
script chunks are 92-byte headers with empty tables -- empty script members an
author left behind, which Director runs as nothing too. Verified twice and from
outside this pipeline: `reference/lingo/BYAIR/External/BehaviorScript 60.ls` and
its `.lasm` are both 0 bytes, ProjectorRays reading the same bytecode; and
`DOCROOM.dir`, whose member 245 the score attaches as a sprite behaviour across
twelve spans on channel 35, holds 109 `Lscr` chunks of which exactly one has
`handlersCount == 0` (u16 at offset 72) and it is 92 bytes.

So no behaviour in any of the six titles is missing for want of this decoder, and
that is the reason it is not built rather than an oversight. **Do not re-run the
census to find out** -- it is the sixth thing this gap has been re-investigated
as, and the numbers above are the answer. The count of zero-handler chunks is
*not* an invariant to assert: `piposh-dream` has 369 of them against 0 sourceless
members, because a member with source can compile to a handler-less script.

Where it would be required: a **protected** movie (`.dxr`/`.cxt`/`.dcr`) ships
bytecode with the source stripped, and for one of those this port would have no
Lingo at all. Every container under `games/` is an unprotected `.dir`/`.cst`,
which is why the source text is there to read -- but the Movie-In-A-Window code
names `window("joke.dxr")`, so the original discs shipped protected builds and
one will eventually be handed to this engine. `tools/fetch_scummvm_reference.sh`
now fetches `lingo/lingo-bytecode.cpp`, which is the layout's specification.

**Tempo: the pre-D6 numbering is implemented and cannot be exercised.** §9.1.
Both the rate (`director_frame_clock.gd:rate_for`) and the one-shot meanings
(`director_score.gd:tempo_waits`) branch on the movie's file version, which is
the only thing that can decide it: 246/247/248 mean "set rate / delay /
wait-click" from D6 and "delay ten / nine / eight seconds" before it, and nothing
in the byte says which. What cannot be covered is the *input*: the owner has
ruled out D4/D5 container support, so `director_score.gd` decodes the D6/D7
main-channel layout only and no real file can produce a pre-D6 cell.
`tools/movie_tempo.gd:_check_reading` and `tools/frame_events.gd` drive both
branches by hand instead, which is the whole of that branch's cover and is said
here rather than left to look like corpus coverage.

**Tempo: the video waits are expressed, and there is nothing to wait on.** §9.1.
Both numberings decode -- pre-D6's `136 .. 195` biased by 135, and D6's "any
other non-zero cell numbers a sprite channel" -- and
`director_frame_clock.gd:_waiting_video` holds the playhead for them. What
resolves the wait is a `video_probe` callable nothing installs yet: with none,
every video wait reports *finished* on the first poll, which is the answer
Director gives for a channel holding no video and the only safe default for a
port with no decoder. Wiring the probe is one line wherever digital video lands;
the clock side needs nothing further.

**`puppetTempo` -- fixed.** §9.1. It is bound at
`scenes/preview_lingo_host.gd:puppettempo` -> `director_preview.gd:lingo_puppet_tempo`
-> `director_frame_clock.gd:set_puppet_tempo`, which holds the puppet rate and
releases it when the score writes a tempo or its effective tempo changes.
Previously: listed among the host's no-ops, so a script that set it changed
nothing. Two things about the implementation are worth knowing before touching
it, both written up in the source. The argument is read in the **pre-D6
numbering whatever the movie's version is**, because a Lingo integer is not a
score cell and the reference's version-based reading makes `puppetTempo 30` a
video wait in every D6 movie. And the release condition compares the *score's*
effective tempo across frames, not the puppet-substituted one the reference
records, which in the reference makes every puppet tempo exactly one frame long.

**`play` and `go` suspend a handler, with two residues.** §6.1/§9.4. Both now
capture the caller's position and resume it -- a `go` at the end of the step that
entered the destination, a `play` at `play done` **or at the end of the score**.
What is left: a `tell` body cannot suspend; and unwinding is statement-granular, so
a suspend inside a compound expression resumes at the statement rather than
mid-expression.

*This entry replaces the one that opened this file until 2026-08-09*, which
called `play`-non-suspension "the widest divergence in this engine" and described
the interpreter as unable to suspend mid-block. It had been contradicted by this
paragraph, four files below it, for however long the two sat here together:
`lingo_interpreter.gd` carries `_suspending`, `_take_suspend_request` and the
innermost-first resume chain, `frame_loop.gd:advance` and
`director_preview.gd:_return_from_play_stack` are the two resume points, and
`tools/play_suspends.gd` is in `gate.sh`'s `ALL`. A gap list is only worth
reading if it is true, and that entry's position at the top made it the first
thing a session would pick up and rebuild.

The measurement it carried is worth keeping, because it says how much of the
corpus the feature covers rather than what is missing: **922 of Rating's 1,075
`play frame` sites carry Lingo after them** -- 516 of those a `go`, 272 a
`sound` -- across EGOZEND, EGOZROO1/2, EGOZROOM, PHONE, MOVIEND, Panel, BLABOMB,
NIGHT1 and 20 more; Piposh 2 has 121 of 160, 10 of them a `go`. The 153 sites
where `play frame` is the last statement in its block are the ones that behave
identically either way. The case that drove it was `BATZEGOZ.dir`'s dialogue
(`BehaviorScript 39`-`40` and eleven near-copies), where the `go("batz2a")` after
`play frame "egozspeak1"` used to overwrite the branch `play` had just set and
cut the character off mid-line:

    godot --headless --script tools/click_trace.gd -- \
        --root rating --file BATZEGOZ.dir --marker Egoz1 --channel 11

The third -- *reaching the end of a score does not thaw a parked `play`* -- is
closed. `score.cpp:462-487` pops the movie stack in the
`nextFrameNumberToLoad >= getFramesNum()` branch of `updateCurrentFrame`, ahead of
the wrap to frame 1, and requeues the play state on the way past; that path is the
only thing that can wake a handler parked by an interlude which simply *ends*
rather than saying `play done`. Without it such a `play` wrapped to frame 0, played
the interlude again from the top, and left the caller parked for ever -- the same
hang, from the same cause, as the one that made Piposh Dream's save screen
unusable. `frame_loop.gd:advance` and `director_preview.gd:_return_from_play_stack`
now do it, and `tools/play_suspends.gd` asserts it: the case is built rather than
found, because no room in either corpus reaches the last frame of its score under a
headless drive.

**The event chain is queued, and both residues are gone.** §6.3/§8.2. The whole
chain -- primary, sprite behaviour, cast script, frame script, movie script -- is
built before any element runs (`preview/event_chain.gd`), and `pass` /
`dontPassEvent` are honoured per element on the mouse and key chains alike. The
two things that were left have both landed with the mouse-model work below: a
right click now latches its member at the press like a left one
(`director_preview.gd:_press_click` takes the button as an argument), and the
second primary element -- `the mouseDownScript` after a `when mouseDown then`, or
`the keyDownScript` after a `when keyDown then` -- gets its own flag reset, so it
no longer inherits the first element's `dontPassEvent`. No site in any of the six
titles installs two primary handlers for one event, so the second is unexercised.

**Modifier keys are latched with the event -- done.** §8.3.
`preview/input_router.gd:note_modifiers` records the word every key event carries
into `preview_lingo_host.gd:key_flags`, in both the down and the up arm and
nowhere else, which is where the reference writes `_keyFlags`; `the shiftDown`,
`optionDown`, `commandDown` and `controlDown` are four reads of that one number.
A **modifier key now returns without dispatching**, which is the other half of
§8.3 and which the port did not have: shift, control, alt and command recorded
nothing and ran the whole `keyDown` chain, so `fromnow` -- installed by 46
scripts -- fired once for the shift of every shifted character. `the
timeoutKeyDown` is bound, stored and read back; it is **inert** until there is a
timeout clock to feed, and §19 records it as such.

Previously: the four properties asked `Input.is_key_pressed` at the moment of the
read, which is wrong in both directions. A handler runs some milliseconds after
the event that started it, so a chord released in the gap read as never held; and
`Input` answers for the OS keyboard rather than for the event queue, so a
synthesised `InputEventKey` carrying `shift_pressed` could not make
`the shiftDown` true at all -- which is why nothing tested it.

**`LingoInterpreter.reset_steps()` -- fixed.** It now has two callers, `preview/scripts.gd:dispatch` and `preview/event_chain.gd:run`. Previously: `_steps` accumulates for the
life of a session against `MAX_STEPS`, so a long enough session eventually aborts
every handler with "step budget exhausted". Pre-existing; nothing has run long
enough to hit it.

**The property surface reports nothing when it drops a write.**
`LingoDiagnostics` declares `SPRITE_PROP`, `MOVIE_PROP` and `MEMBER_PROP`;
**nothing ever emitted one of the three.** `_host_call` reports a missing host
*method*, but a bound method answering VOID for a name it does not know is
silent -- which is why the builtin surface's gaps get found and the property
surface's do not, and why the same class has now bitten five times
(`moveableSprite`, which killed dragging outright, then `editableText`,
`constraint`, `the member of sprite`, and flip).

**Closed.** All three emit, each from the fall-through of the thing that
consumes that kind rather than from a list beside it -- a hand-written list is
how this stayed invisible, because the list and the code drift.

    SPRITE_PROP  director_preview.gd:_note_sprite_prop, against
                 sprite_props.gd:consumed, itself derived from
                 sprite_state.FIELDS and ROUTED
    MEMBER_PROP  director_preview.gd:_note_member_prop, on
                 lingo_set_member_prop's `_:` and on members.gd:read_prop
                 answering VOID for a name it has no arm for
    MOVIE_PROP   preview_lingo_host.gd:_note_movie_prop, on the fall-through
                 of get_system_prop and of set_system_prop

The member **read** half was the one still hiding when the other two landed, and
it was the worst of the three: `read_prop` answered **0** for every name it had
no arm for, so `the frameRate of member N` was a plausible integer rather than a
hole and a script that branched on it took a branch. It answers VOID internally
now; the node reports it and hands the caller the same 0, so nothing a movie
sees moves.

`tools/property_surface.gd` is the gate entry that keeps this from rotting, and
it asserts the half a harness normally forgets: that the reports stay *quiet* for
names the engine really does consume, and -- derived from the sources -- that
every property write arm reaches a store something outside the setter reads.
`tools/lingo_surface_audit.gd` scores any arm containing an `=` as live, so a
property bound to a field nobody reads is precisely what it cannot see.

Two things this does **not** close. `members.gd:read_prop`'s arms are recorded
`live` by the surface audit without an inertness test, so a member read arm whose
body is `return 0` reads as bound -- `the mediaBusy of member` is one, correctly,
and there is nothing to say the next one will be. And a *read-only* movie
property now reports on a write attempt, because this port has no read-only list
for `the X`; that is an honest over-report rather than a wrong one, and inventing
the list is the hand-written table this whole entry argues against.

**Digital video.** §13. No decoder, no sync, no `the movieRate`.

**Wait-for-video tempo -- the clock half is built.** §9. The tempo cell never
holds one in this corpus, which was a reason to build it last and not a reason to
skip it. The clock now decodes and holds for one in both numberings and releases
it through `FrameClock.video_probe`; what is missing is a decoder to install as
that probe, which is the digital-video entry above and not this one.

**Mask ink (9).** §2.6. Uses the *next* cast member as a 1-bit mask. No member
in this corpus carries it; it currently falls through to **Copy**. It used to fall
through to Matte, which was wrong in kind rather than by a degree -- flooding this
member's own paper is not the same mechanism as reading the next member as a mask
(`reference/scummvm/channel.cpp:228`) -- and `bugs.md` 50 moved it. The mask path
itself is still unbuilt, deliberately: with 0 records of ink 9 anywhere in the
corpus the polarity is undecidable, and guessing it backwards makes a sprite
invisible rather than merely wrong.

**`the clickOn` on mouse-up, and the recipient with it -- done, both halves.**
§15. Director rewrites `the clickOn` on the mouse-up when the release was over a
sprite **and** delivers the mouse-up to that same sprite
(`lingo-events.cpp:143-148`, `kSpriteHandler`, D4+). This port had neither: the
press latched the property and the press's channel took the message. The clause
was taken alone once and reverted the same day, because half of it makes one
dispatch give two answers to "which sprite is this about" and the corpus's whole
inventory idiom is written on the two agreeing:

    on mouseDown   objectxx = the locH of sprite the clickOn
    on mouseUp     ... set the locH of sprite the clickOn to objectxx

Both halves are in. `director_preview.gd:_release_click` builds the mouse-up
chain from `_channel_at(at)` -- the same eligibility-filtered, ink-aware descent
the press used -- and `interaction.gd:release` rewrites `click_sprite` from it
when it answered non-zero, which is the reference's own "do not override when
clicked on Score".

*Why the drop still works, which is the thing the revert was about.* A dragged
sprite is under the cursor by construction (§7.6), and **every drop target in the
corpus is a lower channel than the slot being dragged**: `MASTER/External/
BehaviorScript 52` and its eleven near-copies test `intersects 100` (Pip's head)
and `intersects 17` / `9` / `7` (room hotspots), while the slots are channels
103-110. The descent answers the highest eligible sprite, so on every drop the
game asks for, the dragged item answers for itself and the recompute names the
same sprite the latch used to. The two readings part company only where the
release lands on a *higher* eligible channel -- dropping one slot's item onto
another slot along the bar -- and there Director rewrites `the clickOn` and the
handler sends the wrong sprite home. That is the reference's answer to a gesture
the game does not ask for, and reproducing it is the job.

*What did not move.* A release **outside** the sprite that was pressed still
raises `mouseUpOutSide` to that sprite and no `mouseUp` at all, where the
reference raises the `mouseUp` to whatever is under the release and defers
`mouseUpOutSide` to the *next press*. It stays coherent under the change --
`the clickOn` is rewritten only on the arm that dispatches `mouseUp`, so the
sprite receiving `mouseUpOutSide` is still the one `the clickOn` names while it
runs -- and it is the only divergence left in §8.1's triple. It is also what
Director's own documentation describes for the message; it is ScummVM that
defers. Closing it means moving the raise to the press and letting a cancelled
click's `mouseUp` reach the frame script, which in this corpus means activating a
menu button the player deliberately slid off before letting go.

**A right click latches all five, like a left one -- done.** §15. The reference's
mouse-down block runs at the primary tier for `rightMouseDown` exactly as for
`mouseDown` and latches five things together: the empty-stage beep, the hilite
channel, "the press was in *a* button", the drag channel and grab offset for a
moveable sprite, and the cast id the mouse-up resolves against. `the clickOn` is
written by `rightMouseDown` and `rightMouseUp` too. `Interaction.right_button`
did none of it; there is no `right_button` any more. `route_right_button` calls
the same `_press_click` / `_release_click` the left button does with the button
as an argument, and the block itself is `interaction.gd:latch_press` /
`latch_release`, one function each, for both buttons.

Two of the five did not exist for **either** button before this and landed with
it: §15's empty-stage beep (`the beepOn`, which had been wired to gate the `beep`
builtin instead -- the reference's `LB::b_beep` never asks, and the property's
only reader is the empty-stage click), and the button hilite flip on mouse-up
(§15's "makes no sense and Director does it anyway" rule). `the beepOn` is now
**false** by default, which is the reference's and the original's; it read true
only because that was the value that made `beep()` audible while it was gating
the wrong thing.

What stays the left button's: the wait-for-click release and the palette-cycle
abort (§9.2, §11 -- both are about the click the player uses to get on with the
game), and `the mouseDownScript` / `the mouseUpScript`, which Director files
under the left events and gives the right button no property to install.

0 `rightMouseDown` or `rightMouseUp` handlers exist in any of the six titles, and
0 of the 51,350 members is of type `button`, so the right pair and the flip are
unexercised: built because Director has them.

**The hit test has no Hole.** §4.2. `isMouseIn` returns three values and
`Interaction.channel_at` models two: a miss and an ineligible sprite both
continue the descent, and there is no result that *aborts* it. The only producer
of a Hole is a text member whose point is over its scrollbar arrows — a scrollbar
swallows the click without being a target. This port draws no scrollbars, so
nothing can produce one today; §4.2 still says to write the loop with three
results, because adding scrolling fields later silently changes click routing
everywhere rather than in the fields.

**Cast-script targeting on mouse-up -- done.** §15.
`director_preview.gd:_press_member` latches the member under the pointer at the
start of the mouse-down chain, as the reference keeps `_currentMouseDownCastID`,
and the mouse-up's cast element resolves against it -- so a `mouseDown` handler
that swaps the member leaves the **old** member answering and the swapped-in one
never sees the release. `tools/click_chain.gd` asserts it with a real press that
swaps the member under itself.

**`pass` / `dontPassEvent` propagation -- done.** §8.2. The five tiers are queued
up front with `passByDefault` true for the primary element and false for the
rest; the flag is reset to each element's default before it runs, and the chain
stops only when an element that *found a script* left it false. A sprite
behaviour and its member's cast script are now cumulative rather than
alternatives, so a behaviour declaring only `mouseDown` no longer shadows a cast
script's `mouseUp`.

Measured over every clickable sprite occurrence in every movie
(`tools/click_chain.gd -- --survey`): **0 of 156,227 occurrences change tier in
Piposh 2, 310 of 337,568 in Piposh 1 and 98 of 142,066 in Rating**, all of them
`none -> cast`; 48, 9,669 and 1,268 respectively now run more than one handler,
traceable to 16 named scripts in Piposh 1 and 20 in Rating. The queue moves
almost nothing and the flag moves the rest, which is the shape that says the flag
is honoured -- had it been ignored, all 636k occurrences would run their whole
chain.

**The four `*Script` properties hold Lingo source -- done.** §6.3 tier 1.
Director's value is a *string of Lingo* compiled on assignment
(`Movie::setPrimaryEventHandler` -> `replaceCode(code, kEventScript, event)`, and
`resolveScriptEvent` then rewrites the event to `kEventGeneric`, so what runs is
the script's scopeless part). All four now do:
`preview_lingo_host.gd:_compile_primary` compiles in the field's **setter**, so
it compiles once per assignment and on every path that writes the field including
a save restore, and `preview/event_chain.gd:run_primary_script` is the one runner
the mouse and the keyboard share.

The recorded reason for the old shortcut -- "this port has no runtime
compile-a-string path" -- stopped being true when `do` landed;
`LingoInterpreter.compile_statements` is `_do`'s own wrapper, factored out.

**A bare identifier still resolves as a name**, and that is not a leftover. In
Director `set the keyDownScript to "fromnow"` compiles a one-statement script
whose statement is the no-argument call `fromnow`, so naming a handler is what
the source form *does* with a bare word. Both forms are kept on one compiled
record and tried in that order for two reasons that are about this port: 952
corpus sites across the six roots are that form (`fromnow`, `gomenu`,
`normalkeysx`) and it is the path that must not move, and a name resolving to no
handler stays silent where a compiled bare word would report an unbound builtin
on every single keypress -- `fromnow` sees every key in the game. A source that
will not compile installs nothing and says so on the log, as Director does for a
bad `do`.

**Seven mouse properties read something other than what the reference reads.**
§4.5, §15. All seven are one-line changes in `scenes/preview_lingo_host.gd`'s
`get_system_prop`, all are independent of each other and of the hit test, and all
are measured at 0 corpus sites — so they are a batch to be done together and last,
not a risk to be weighed one at a time. `tools/mouse_events.gd` already walks the
property list and would gain a check per row.

| Property | Reference | This port |
| --- | --- | --- |
| `the doubleClick` | the last two press times within **25 ticks** (~417 ms), evaluated on read | a boolean latched at the press, 500 ms |
| `the mouseDown` / `the mouseUp` | **left or right** button | left only |
| `the stillDown` | the window manager's tracked down-state, which a `repeat while` inside a handler is written against | the same read as `the mouseDown` |
| `the lastEvent` | ticks since the last mouse move, click **or key** | the smaller of click and roll; keys are not stamped |
| `the lastKey` | ticks since the last key | unbound, reads VOID |
| `the mouseCast` / `the mouseMember` | `getSpriteIDFromPos` — the ink-aware hit test; `0` and VOID respectively for "over nothing"; `mouseMember` is a member *reference*, not a number | the rollover channel, `-1` for both, a number for both |
| `the mouseChar` / `mouseWord` / `mouseLine` / `mouseItem` (D3) | the character, word, line or item of the text member under the pointer | unbound, read VOID |

Two engine behaviours in the same class, neither of them a property, and **both
landed with the right-button work above** — this said neither was implemented,
which the entry four screens up already contradicted. **`the beepOn`** makes a
mouse-down on empty stage beep: `preview/interaction.gd:719` reads it, and the
property defaults false, which is the reference's value and not the true it had
while it was wired to gate the `beep` builtin instead. §15's **button hilite
flip** — on mouse-up, if the last mouse-*down* was inside *any* button, the
button under the mouse-up inverts its hilite — is `interaction.gd:latch_release`,
gated on the member being a button exactly as `lingo-events.cpp:213-215` gates
it. Both are unexercised: 0 of the 51,350 members across the three corpora is of
type `button`. The flip writes the same store `set the hilite of member` does,
which draws for a button and nothing else (`bugs.md`/`docs/bugs-closed.md` 66),
so on this corpus it is inert twice over.

**D6+ click eligibility -- done, with the attachment list still narrow.** §4.3.
`preview/interaction.gd:eligibility_reason` implements all six clauses in the
reference's order and answers *which* one fired; `responds_to_mouse` is that
returning non-empty, so the descent and every debugging overlay cannot drift
apart -- which they did once already over `hits_per_pixel`'s arguments.

Measured before and after over every frame of every movie, because widening
eligibility is how a backdrop starts swallowing clicks: piposh2 2 frames changed
and 8 sprites newly eligible, piposh 543 / 28, rating 2,534 / 50. **Nothing lost
eligibility anywhere**, and no newly-eligible sprite is a full-stage backdrop.

**The literal reading of the reference was wrong here, and the sweep is how that
was found.** Clause 4 tests the *attachment*, and taking it literally made 188
pairs eligible -- including a 640x400 Copy-ink backdrop over the whole stage on
144 frames of `AIR1.dir`, on the strength of an attachment naming a **bitmap**.
**279 / 654 / 500 of the decoded intervals name a bitmap, film loop or shape**,
none of which can be a behaviour. Requiring the script lookup to succeed drops
118 of the 188 and four of the five backdrops; it also drops 41 that name a real
script member this port cannot resolve, which is narrower than Director in
§4.2's own default direction.

**The cause given for those attachments was wrong, and the score decode is not
where the fix is.** This entry said `_read_interval` "pairs a span's info entry
with the next non-empty 8-byte `VWSC` entry rather than indexing by the
`sprite_list_idx` the sprite record already carries", so a span could be handed
somebody else's attachment. Three measurements say otherwise, all in
`director_score.gd:parse`'s comment: the search took a later entry **0 times in
528,168 spans** across the three corpora, because a span is three consecutive
entries and the one after an empty behaviour list is an empty name string
followed by the next span's info record, which is too wide to match; every
interval it produced was claimed by the sprite record occupying that channel over
those frames, **14,247 spans and 0 orphans**, so matching by channel and frame
range is exactly the reference's `sprite_list_idx` lookup on this data; and the
unresolved ones are not a mis-mapped library, since no consistent offset relates
the library they name to one holding a script at that number and **206 / 585 /
393 of them have no script at that number in any library of the movie**.

So these are the sprite record's own attachments, correctly associated, naming a
member that is not a script -- a question about Director's authored data or about
the member-type decode. It is open, and the narrow clause stands on the
measurement rather than on the pairing story. Written out at this length because
the wrong cause was acted on: it is what a §4.3 clause was narrowed against, and
it survived in three files.

Clause 3 (movie member) and clause 5's generic-script arm are implemented and
unexercised: **0 of the 51,350 members across all three corpora is of type
`movie` or `button`**, so clause 2 has never fired on any title either.

**~~D6+ sprites carry a list of behaviours; the decode still caps it at one.~~ --
done.** §8.2. `director_score.gd:_read_interval` reads a span's behaviour entry
as a stream in 8-byte strides, as `score.cpp:loadFrameSpriteDetails` does, where
it used to take the entry only when it held exactly one element and drop a longer
one whole. The script channel still takes one element, which is the reference's
own asymmetry.

Measured over the three corpora, a behaviour entry is 0, 8 or 16 bytes and
nothing else, and the `initializerIndex` half of every one of Piposh 2's 14,903
elements is 0 -- which is what settled the element at 8 bytes rather than 4 with
padding. **2 spans of 158,001 in Piposh 2 carry two behaviours, 5 of 271,872 in
Piposh 1, 0 of 98,295 in Rating**, and both of Piposh 2's name the same script
twice, which Director answers by instantiating two objects and running the
handler twice. Before and after over every frame of every movie
(`tools/click_eligibility.gd`): **nothing lost eligibility anywhere**, 72 frames
gained a channel across the three titles, and the largest newly-eligible sprite
is 55x258 -- no backdrop. Nothing reads a behaviour's authored parameters yet;
that needs the entry `initializerIndex` names, and no title in the corpus writes
one.

**`mouseEnter` / `mouseLeave` / `mouseWithin` are driven off the wrong channel
and stop one tier too early.** §4.5, §8.2. The reference raises all three from
`getMouseSpriteIDFromPos` — the *eligibility-filtered*, ink-aware hit test, which
is this port's `_hover_channel` — and this port raises them from
`_rollover_channel`, the pure rect test. It also confines them to sprite
behaviours; the reference lets them fall through to the cast script, the frame
script and the movie scripts, in every version. Only `mouseUpOutSide`,
`beginSprite`, `endSprite` and `prepareFrame` stop at the sprite tier, and only
from D6. Two smaller clauses are absent as well: in D5 these three fire **only
while a mouse button is held**, and `mouseEnter`/`mouseLeave` are additionally
raised around a D5 press and release.

*What has to change with it.* Switching to `_hover_channel` needs it recomputed
**per tick** as well as per motion — `track_rollover` already is, `_hover_channel`
is only updated from `mouse_motion`, so a sprite moving under a stationary cursor
or a touchscreen tap would stop generating crossings. And it costs something: an
eligibility-filtered channel means a sprite whose behaviour declares *only*
`mouseEnter` never receives it, because `responds_to_mouse` does not look for
that handler. That is authentic — the reference has the same trap — but it is a
regression in the direction of doing less, so it should land together with the
D6+ eligibility clause above, which is what makes such a sprite eligible again.
Propagating past the sprite tier is separate again and needs the queued chain.
**0 sites in either corpus declare any of the three**, so nothing here is
verifiable against this data; `rollOver(n)` polled from `exitFrame` is the only
hover mechanism either title uses (94 sites, 28 files, 14 titles).

**The three rollover queries are two.** §4.5. `rollOver(n)` and `rollOver()` are
both answered by `Interaction.rollover_channel`, which is right for the builtin
in both forms; `the rollOver` as a **property** is a different query in Director —
the ink-aware hit test with no eligibility filter — and is answered here by the
*same* pure-rect descent, which is the wrong one of the two. **It is not unbound
and it does not read VOID**, which is what this entry said and what §19's `live`
row disagreed with; the arm is `preview_lingo_host.gd:get_system_prop`'s
`"rollover"`, and the gap is that it is aliased to the builtin's answer rather
than absent. A reader acting on the old wording would go looking for a binding
that has been there all along. 0 sites, in a corpus that writes every one of its
94 rollovers as the
function. Two further clauses: `rollOver(n)` is measured against the **score's**
geometry rather than the live channel's, deliberately (a menu that swaps art
because the rollover is true feeds its own answer back into the question), so a
sprite a script has *moved* rolls over at its old rectangle; and the D4-and-below
`getRollOverBbox` cache — a blanked channel keeps rolling over its last non-empty
box — is absent, which no D5+ title can reach and a D4 one would.

*What has to change with it.* Re-binding `the rollOver` means binding it to
`_hover_channel`-without-the-filter, which is a **third** channel this port does
not maintain; and moving `rollOver(n)` to live geometry means moving
`rollover_channel` with it, or `rollOver()` and `rollOver(n)` answer about
different rectangles — which the module's own comment argues is worse than either
being wrong on its own.

**`saveMovie` writes fields and nothing else.** `saveMovie` is implemented
(`director/director_writer.gd`) and writes a real container this engine reopens,
but the only chunks it re-emits are the `STXT` payloads of field members whose
text a script changed. Director saved the whole movie. Three specific holes, in
the order they will be missed: a member's cast entry is not updated when its
text changes, so cached metrics go stale; a rewritten chunk that grew leaves its
old bytes unreferenced rather than adding them to the container's `free` list,
so a repeatedly-saved file grows; and `save castLib` is not bound at all, so a
movie that keeps state in a *linked* cast cannot persist it. The corpus here
needs none of the three — `HEZSAVE.DIR` stores everything in its own internal
cast — which is a reason to have built the rest first and not a reason to close
this.

**Dirty rects.** §6.3. Acceptable to omit, but it forecloses
destination-reading inks and leaves one known trails divergence: a sprite in
front of an old mark that has not moved should occlude it and does not.

**Score recording.** Rarely needed.

## Mobile

[`MOBILE.md`](MOBILE.md) is the standing document. Its input section is now
measured rather than reasoned — `tools/touch_input.gd` drives real
`InputEventScreenTouch` events through `_input` — and it carries **one open
decision that is not an engineering task**: `rollOver` menus have no touch
equivalent, this title's menu is built on one, and the three options each cost
something. Nothing should be built for it until that is chosen.

Two engine consequences recorded there rather than here, because they are
platform facts and not gaps: `Input.set_custom_mouse_cursor` cannot show anything
on Android or iOS, so the whole of `preview/cursor.gd` is invisible on a phone
(and still runs, which is worth short-circuiting); and every `[debug]` binding is
an F-key, so none of them is reachable without a keyboard.


## Built but never compared against Director running

Worth separating from the above, because these are implementations rather than
gaps -- and an unverified implementation is an honest state, not a missing one.

- **Palette** cycling and fades, on a corpus that cycles 0 times. The rest of the
  palette subsystem is no longer in this list: reading a `CLUT`, a bitmap's own
  palette field, the movie's default palette and the per-member table the
  renderer decodes through are all asserted by `tools/palette_members.gd` against
  `test-games/itamar-park`, which names a palette on 655 of its 657 bitmaps.
  Seven built-in tables (Rainbow, Pastels, Vivid, NTSC, Metallic and **both
  Windows system palettes**) are authored data with no generating rule: the
  engine warns by name and substitutes system Mac rather than inventing them.
  Lifting them from a Director install is the fix, and it is now a visible defect
  rather than a theoretical one -- `bugs.md` 77 has the count.
- **Hilite on click.** §4.6, implemented clause for clause in
  `scenes/preview/hilite.gd`: `isActive()` presence-only, not moveable, not
  puppet, bitmaps only, the member's Auto Hilite info flag with "ink is Matte"
  as the no-cast-info fallback. The inversion is a masked XOR through the matte
  -- the inverted copy carries the source alpha and is drawn *instead of* the
  artwork, so an irregular sprite inverts its silhouette rather than its box. On
  at mouse-down, off when the pointer leaves by the ink-aware test, on again on
  re-entry, off at mouse-up.

  **0 cast members carry the flag in any of the three titles** -- 73,994 +
  282,995 + 75,000 (`tools/hilite_survey.gd`) -- and Piposh 2 cannot reach the
  fallback arm either, since every one of its members has an info block. These
  games swap members instead. So `tools/hilite.gd` drives it from a parsed
  member, the way `tools/trails.gd` does.

  The flag had never been decoded: it is bit 1 of the word at offset 12 of the
  cast info block, which `director_cast.gd:_parse_info` skipped. Two
  corroborations that offset 12 really is the flag word rather than a plausible
  guess -- Piposh 1's only non-zero value is `0x10` on 17 members, every one of
  them a *sound*, which is exactly where the reference reads a sound's looping
  bit; Piposh 2's is `0x40` on 32 bitmaps and 1 shape.

  Two deliberate divergences: hilite follows the channel the press latched
  rather than re-resolving under the pointer, and where an ink keys more than
  the matte does, the destination behind the holes is not inverted -- the same
  limit dirty rects already impose.

- **Editable text, focus, caret and selection.** §8.4/§7.7, in
  `scenes/preview/text_focus.gd`: `sprite OR member` editability,
  first-editable-claims-focus and keeps it while the cast id holds, movie-level
  `selStart`/`selEnd`, caret, selection, insertion, deletion, arrows, Home/End,
  Enter, auto-tab, click-to-caret, drag-to-select, and the typed text pushed back
  to the member through the same store `put x into field` writes. §8.3 routes
  `keyDown` to the focused sprite, channel 0 to the frame otherwise.

  Drag-to-select landed after the rest and is worth its own sentence, because
  its absence had the shape this file exists to prevent: the caret could be
  *placed* with the mouse and nothing could be *selected* with it, which reads
  as "the save screen is a bit awkward" rather than as a missing feature. The
  press anchors `_sel_start`, motion drags `_sel_end` (`TextFocus.drag`, called
  from `director_preview._input` ahead of the router), and the release ends it.
  It does not consume the motion: §7.6's moveable sprite uses the same button.

  **The member half was the whole feature and had never been decoded.** 0 of
  3,550,111 sprite records across the three titles set the score's editable bit;
  every editable field in all of them comes from byte 25 bit 0 of the text
  member's specific block (`director_cast.gd`) -- 1 member in Piposh 2
  (`SAVELOAD.dir`'s `save1`), 9 in Piposh 1, 0 in Rating. A wrong byte offset
  does not land on the save screen of three separate builds.

  Unverified against Director running: auto-tab (no member in any corpus sets
  the bit), the sprite-side editable flag (no record sets it), and Director's
  suppress-on-`keyDown` rule (no script in either corpus declares one). **One
  clause of §7.7 left open**: auto-expanding boxes do not push their laid-out
  size back onto the sprite.

- **`the constraint of sprite`.** §7.6, in `Interaction.constrain` /
  `constraint_box`, applied from `director_preview._write_position`. It clamps
  the position **point**, not the rect, so a sprite legitimately hangs outside
  the box by its registration offset -- measured at 320px of overhang on Piposh
  2 and 22px on SHUFFLE, which is what the harness discriminates on. Constraint
  0 is unconstrained and is the fast path.

  **Not a drag feature**, which is the thing to know before touching it. The
  clamp is on the position write, so a script's own `locH`/`locV` is clamped
  too. SHUFFLE proves it is not merely defensive: sprite 7 is constrained and
  nothing ever makes it moveable.

  Stored as **channel state**, like `the cursor of sprite`, not as a puppet
  override -- and that is settled by the corpus rather than by taste. All 10
  writes are `set the constraint of sprite N to 2` followed immediately by
  `go(marker(1))`, and `sprite_state.effective` discards a channel's overrides
  when the score moves it to another member, so an override-backed constraint
  would have been thrown away on arrival every time.

  The score record has no constraint field: bytes 36-47 hold one distinct value,
  `0x00`, across all 816,318 occupied records in Piposh 2 and all 1,886,362 in
  Piposh 1 (`tools/sprite_record_bytes.gd --all`). The 10 Lingo sites are all in
  SHUFFLE -- the shuffleboard puck fenced to the board. One stated divergence: a
  constraint naming an empty or hidden channel is treated as unconstrained,
  where the literal reference would ask an empty channel for a bounding box and
  teleport the sprite to (0,0).

- **Trails**, on a corpus where 0 of 816,318 records set the flag.
- **Score sound channels, `snd ` decoding, cue points and fades** -- no cast in
  this game holds a sound member, so all of it is proved against synthesised
  bytes only.
- **Flip** is decoded and applied -- `scenes/preview/sprite_art.gd` mirrors the
  draw with a negative extent and mirrors the hit-test sample with it, so the
  clickable pixels are not the mirror image of the visible ones. Unverified
  because 0 of Piposh 2's 816,318 sprite records and 0 of Piposh 1's 1,886,362
  set either bit; `tools/sprite_flip.gd` drives it from a synthetic record.
- **Rounded-rect, oval and line shapes** are drawn by `director/director_shape.gd`.
  Of the corpus's 169 shape members, 167 are plain rectangles and 2 are rounded
  rectangles; no member is an oval or a line, so those two are the unexercised
  pair. Director stores no corner radius, so the rounded inset is chosen to look
  like QuickDraw's default rather than decoded -- that is the part to check first
  against Director running.

## The rule that governs this list

A measured zero is a reason to build something *last* and to mark it unverified.
It is never a reason not to build it -- see `AGENTS.md`, "Build Director, not
this game". Several entries above were closed the wrong way once already and had
to be reopened.

An entry is closed when the reference section it names is implemented, not when
the current game stops misbehaving -- see `AGENTS.md`, "The reference documents
are the specification". Closing one is part of landing the change, because this
list is only worth reading if it is true: two entries above described the code as
it was several commits earlier, and both understated what was already built.
