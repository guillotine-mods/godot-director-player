# Digital video and video Xtras: the census, the verdict, and what the options cost

*Measured 2026-08-12 on Godot 4.7.1, Windows, against all eight corpora in the
tree. Every number here comes out of `tools/video_census.gd` and
`tools/video_fallback.gd`; re-run them rather than trusting the figures, and if a
figure has moved, correct it here rather than adding a second one.*

This is a decision document. It exists because `bugs.md` 82 and 84 both end at
"what is left here is a decoder", and a decoder is a project-shaped choice rather
than a bug someone can pick up. What follows is what the corpus actually holds,
what each title loses today, the four ways out, and which one this document
recommends.

> **Update, same day: C1 was taken.** `director/director_avi.gd` (the RIFF walk
> and the MS-RLE decoder), `scenes/preview/video.gd` (the reader per member, the
> playhead per channel, the frame the sprite draws) and
> `director/director_cast.gd`'s type-10 arm landed together, and Magic Hat's logo
> movie now plays its ten seconds and then proceeds. Measured:
> **16.2 ms per decoded frame** for 640x480 against a 90 ms budget at the file's
> own 11.11 fps (`tools/avi_decode.gd`), and **10.08 s** of wall clock from
> `movieTime` 0 to the member's own 6,048-unit duration. §6's first item is done;
> §6's second (the Xtra sprite methods) is not, and C2 and D are still refused.
> Everything below is the census and the costing as they were written, and they
> are still what the decision rests on -- read §3 before touching `the duration`.

**The short version.** Four cast members in eight corpora play video. All four
are in `test-games/itamar-magichat`. **The six shipped Piposh titles hold no
digital video member, no video Xtra, and not one byte of video media on disc**, so
the decoder question costs them nothing at all. Magic Hat loses 23 clips and keeps
its game: every one of its video frames releases the playhead, verified by driving
the playhead onto each of them. The recommendation is to leave the decoder alone,
keep the fallback asserted, and build the two *Director* features that the census
has now unblocked — which are not decoding.

---

## 1. The census

`godot --headless --audio-driver Dummy --path . --script tools/video_census.gd`

```
                           itamar-magichat     itamar-park          piposh    piposh-dream       piposh-en       piposh-ru         piposh2          rating     total
  containers                            16              10             124              79             121             123              86             118       677
  digitalVideo (10)                      2               0               0               0               0               0               0               0         2
  video Xtra                             2               0               0               0               0               0               0               0         2
  animation Xtra                       452               7               0               0               0               0               0               0       459
  Xtra members                         454               7               1              97               1               1               4               1       566
  video sprites scored                   3               0               0               0               0               0               0               0         3
  animation sprites scored             151               0               0               0               0               0               0               0       151
  casts driving video                    2               1               0               0               0               0               0               0         3
  media files on disc                  161             278               0               0               0               0               0               0       439
  media MB on disc                   315.5           111.3             0.0             0.0             0.0             0.0             0.0             0.0     426.9
```

### The four members

```
itamar-magichat  album.cst    #210   magicvideo         video-xtra    visiblelightonstagemedia
itamar-magichat  logo.dir     #27    prelogo            digitalVideo
itamar-magichat  logo.dir     #28    logo               digitalVideo
itamar-magichat  same.cst     #178   IntroRetroVideo    video-xtra    visiblelightonstagemedia
```

Three of them are placed by a score, and those three are the only places in the
tree where a player can arrive at a video:

```
itamar-magichat  logo/logo.dir  ch3   from frame 3     #28   logo              digitalVideo
itamar-magichat  magichat.dir   ch25  from frame 55    #210  magicvideo        video-xtra
itamar-magichat  magichat.dir   ch1   from frame 125   #178  IntroRetroVideo   video-xtra
```

`prelogo` is the fourth and is never scored — `logo.dir`'s `startMovie` points it
at a file by hand.

### What the media on disc actually is

Sniffed from each file's own first bytes rather than from its extension, because
the extension is not evidence: `windemo.dat` sits beside Magic Hat's movies and
is an icon table, not a fourth video.

```
Autodesk FLIC / FLC, 320x200                                185      18.6 MB
Autodesk FLIC / FLC, 640x400                                  1       0.4 MB
Autodesk FLIC / FLC, 640x480                                226     207.6 MB
Autodesk FLIC / FLC, 642x501                                  3       1.2 MB
MPEG-1 system / 320x240, 25.00 fps, 1500 kbit/s, with MPEG audio   20     177.5 MB
MPEG-1 system / 352x288, 25.00 fps, 1150 kbit/s, with MPEG audio    2      19.9 MB
RIFF AVI / 640x480 at 11.11 fps, video 'mrle', 8-bit, audio tag 1, 22050 Hz, 1 ch    1       1.7 MB
not video / icon table                                        1       0.0 MB
```

Three findings inside that table matter more than the totals:

- **The 22 `.mpg` are MPEG-1 *system* streams** — muxed video and MPEG audio, pack
  header `00 00 01 BA` with MPEG-1's marker rather than MPEG-2's. Two encodes:
  `heb/mainmenu/{intro,retro}.mpg` at 352x288 (CIF) 1150 kbit/s, and
  `heb/album/{magic,solution}1..10.mpg` at 320x240 1500 kbit/s. **The two encodes
  match the two Xtra members' own `xtraRect`s exactly** — `IntroRetroVideo` is
  352x288 and `magicvideo` is 320x240, measured independently by
  `tools/xtra_members.gd`. Two different parts of the container agreeing on the
  same pair of numbers is the strongest evidence in this document that the members
  and the files belong together.
- **The one `.avi` is trivially decodable and nobody has noticed.** `logo/logo.avi`
  is 640x480, 8-bit **Microsoft RLE** (`mrle`, `biCompression = BI_RLE8`), 112
  frames at 11.11 fps — ten seconds — with a raw PCM audio track at 22050 Hz,
  8-bit, mono. That is not a codec, it is a run-length encoding; see §4C.
- **`logo/prelogo.avi` does not exist.** `logo.dir`'s `startMovie` runs
  `member("prelogo").fileName = "prelogo.avi"` and the directory holds `logo.avi`
  and `logo.dir` and nothing else. `bugs.md` 84 said both files were on disk; that
  sentence was wrong and is corrected there. Whatever is decided about decoders,
  `prelogo` has no media to decode.

The 415 FLIC files are **not** Director's problem: they belong to the DOS demo
trees (`DEMO_DOS/`, `HIEND/`, `MENU/`) that both Itamar discs ship as loose data
for a separate DOS executable. No cast member in either corpus references one, and
no Director container in the tree can play a `.flc`. They are counted here so that
"427 MB of video-shaped files" does not later get mistaken for 427 MB of loss.

### The Xtras, and why 566 of them is not 566 video players

Across all eight corpora the 566 type-15 members carry five distinct symbols:

```
VisibleLightOnStageMedia   2      flash        253      vectorShape   94
animGif / animgif        206      text          11
```

Only `VisibleLightOnStageMedia` is a video player, and both members carrying it
are Magic Hat's. `flash` and `animGif` are moving pictures with their own decoders
and their own story; `text` and `vectorShape` are not moving pictures at all.
`tools/video_census.gd` keys this off a table with a reason per row and prints
every symbol that is on neither table, so a new disc adds a row rather than
producing a silent miscount.

**The reference does not implement this Xtra either.** ScummVM's
`castmember/xtra.cpp:xtraCastMemberProtos` promotes exactly one Xtra symbol into a
`DigitalVideoCastMember`, and it is `quickTimeMedia`; `VisibleLightOnStageMedia` is
not in the table, so an unregistered `XtraCastMember` falls through to
`CastMember::createWidget` returning `nullptr` (`castmember/castmember.h:70`,
ScummVM 805f259a). Drawing nothing for it is what the reference does.

### One live piece of code with no data behind it

`itamar-park`'s `utils.cst` carries a complete MPEG player — a `Mpeg Handlers`
script member with `startMpeg`, `pauseMpeg`, `stopAndRemoveMpeg`,
`RemoveMpegWhenFinished`, cue-point narration, the lot — driving `the movieRate`
and `the movieTime` on `kMpegSpriteNum`. It is inert in the copy in this tree, and
inert for a reason that is worth writing down rather than rediscovering:
`startMpeg` does `sprite(mySprite).member = member(myMovieName, "Video")` against a
cast library whose filename is set at runtime to `<gMpegCastPath>PCvideo.cst`.
**There is no `Video` cast, no `PCvideo.cst`, and no MPEG file anywhere under
`test-games/itamar-park`**, and nothing in the ten containers this copy has ever
calls `startMpeg`. It is Compedia's shared toolkit module shipped with a title
that does not use it, or with a title whose video data did not survive the
extraction. Either way it is 0 members, 0 sprites and 0 files, and the census
counts it as one cast library that *mentions* video rather than as a title that
plays one.

---

## 2. What each title loses today

Verdicts are `blocked` (a player cannot proceed), `degraded` (proceeds, misses
content) or `unaffected`. They are measured, not inferred:
`tools/video_fallback.gd` drives the playhead **onto** each of the three video
frames and watches what it does there — which is the only way to reach Magic Hat's
intro at all, because that region is entered only when its own `magichat.ini` says
`startframe=intro` and the file in this tree says `startframe=mainmenu`.

| title | video members | verdict | what is lost |
|---|---|---|---|
| `piposh` | 0 | **unaffected** | nothing |
| `piposh-en` | 0 | **unaffected** | nothing |
| `piposh-ru` | 0 | **unaffected** | nothing |
| `piposh2` | 0 | **unaffected** | nothing |
| `piposh-dream` | 0 | **unaffected** | nothing |
| `rating` | 0 | **unaffected** | nothing |
| `itamar-park` | 0 (dead player code) | **unaffected** | nothing — the data it would play is not in this copy |
| `itamar-magichat` | 4 | **degraded** ×3 | the Compedia logo (10s), the intro/retro films, and 20 album clips |

**No title is blocked.** Every one of Magic Hat's three video frames releases the
playhead, and each does so by its own authored fallback rather than by anything
this port added:

```
logo/logo.dir   frame 3     ch3   logo              -> left  (6 states)
magichat.dir    frame 55    ch25  magicvideo        -> left  (3 states)
magichat.dir    frame 125   ch1   IntroRetroVideo   -> left  (12 states)
```

- **`logo.dir` — the Compedia logo, 10 seconds of `logo.avi`.** `compedia logo`'s
  `enterFrame` sets `FilmLen = member("logo").duration` and starts the sprite;
  `Check avi`'s `exitFrame` is `if sprite(3).movieTime >= FilmLen then QuitFilm()`.
  With no media the duration is 0 and the playhead is 0, so `0 >= 0` is true on the
  **first** `exitFrame` and the logo is left behind before a frame of it could have
  shown. Degraded, cleanly, and only because `the duration of member` answers 0 —
  a port that answered a confident duration here would turn this into the hang.
  In this port `logo.dir` is additionally not on the boot path: the `.bat` boots
  `magichat.dir`, while the title's own `magichat.ini` has
  `startfile=CD$\logo\logo`. So today the logo movie is not even entered.
- **`magichat.dir` frame 125 — the intro and the retro film.** `init intro` sets
  `member("IntroRetroVideo").mediaFilename` to
  `<moviePath><lang>\mainmenu\intro.mpg` and `enterFrame` calls `sprite(1).play()`;
  `BehaviorScript 134` polls `sprite(1).getPlaybackEvent`. Nothing binds that name,
  so it is VOID, `VOID <> 1` is true, and the movie takes `QuitIntroRetro(1, 1)` —
  `go(the frame + 1)` — on every tick, walking the intro region one frame per tick.
  Twelve states in a 90-tick watch, then out. **The other arm is `go(the frame)`
  and never ends**, which is why binding `getPlaybackEvent` to answer 1 without a
  decoder would be strictly worse than leaving it unbound.
- **`magichat.dir` frame 55 — the album.** This one is new since `bugs.md` 82 was
  written and it is the larger content loss. `AlbumMenuObject.MenuMouseUp` sets
  `member("MagicVideo").mediaFilename` to `album\magic<page>.mpg` or
  `album\solution<page>.mpg` and jumps to the `video` marker;
  `BehaviorScript 38 - video loop` polls `sprite(25).getPlaybackEvent` and on the
  same VOID does `sprite(25).stop()` / `go(the frame + 1)`. Three states and back
  to `albumloop`. **Twenty clips — a magic and its solution for each of the ten
  album pages — are the album's actual content, and a player gets a flash of a
  blank frame instead.** Nothing is broken and nothing is stuck; the feature is
  simply empty.

The Xtra sprite draws nothing on those frames for a second and separate reason:
type 15 is not in `director_cast.gd`'s `DRAWING_TYPES`, so a type-15 sprite is not
even counted as missing art. That is `bugs.md` 82's own subject and it is
independent of the decoder — the `yes`/`no` buttons in `same.cst` are type-15 too,
and they need no video at all.

---

## 3. What the port answers today, and why it is right

`scenes/preview/media.gd` binds 38 of the ~40 names in Director's time-based media
surface and answers, for a member with no media: `the mediaReady` FALSE, `the
duration` 0, no cue points, no tracks, `the digitalVideoType` `#other`. **That is
what Director answers for a digital video whose file is missing or whose codec is
not installed**, which is a state Director really had and which every defensive
script in the language was written for. Both of Magic Hat's type-10 members are now
asserted to answer exactly that, by `tools/video_fallback.gd`, against real members
— which `media.gd`'s own docstring said did not exist in this tree.

So the fallback is not a stub that happens to work. It is the honest answer, and
it is the reason all three frames skip instead of waiting. Two things follow, and
both are rules rather than observations:

1. **Do not bind `getPlaybackEvent`, `mediaBusy` or `interface` to a plausible
   value while there is no decoder.** Every one of these movies branches on them,
   and every "success" answer selects the arm that waits for ever.
2. **Do not give `the duration of member` a non-zero answer for a video whose media
   cannot be opened.** `Check avi` exits *because* it is 0.

---

## 4. The options

### A. Leave the decoder alone and make the fallback deliberate

**What it takes.** Nothing to build. The work is already done in this pass: two
harnesses, `tools/video_census.gd` (what exists, in what format) and
`tools/video_fallback.gd` (every video frame releases the playhead, and the
property surface answers "not ready"), plus the corrections to `bugs.md` 82 and 84.
Adding both to `gate.sh`'s `ALL` is the remaining step and is one line each; it is
deliberately not done here because `gate.sh` is not this pass's file.

**What it breaks.** Nothing. `tools/video_fallback.gd` passes on all eight roots
and says out loud, on the seven with no video member, that it asserted nothing
about a surface those corpora do not exercise — rather than passing quietly, which
is the dark-harness failure `gate.sh` warns about.

**What it buys.** The distinction between "skips" and "hangs" stops being
something a reader has to take on trust. If a future change to `media.gd` starts
answering a duration, or somebody binds `getPlaybackEvent`, the harness turns the
resulting hang into a named failure instead of a bug report six months later.

**Cost: zero, and it is done.**

### B. Transcode the media to Ogg Theora as a build step

**What it takes.** An `ffmpeg` pass over 22 MPEG-1 files (197 MB) and one AVI,
producing `.ogv` beside them; a resolver arm so that a member asking for `X.mpg`
finds `X.ogv`; a `VideoStreamPlayer`-backed sprite path in
`scenes/preview/`; the type-10 specific block (see §5); and the
`VisibleLightOnStageMedia` Xtra binding with its `play` / `stop` /
`getPlaybackEvent` state machine. Call it an afternoon of ffmpeg and 200–400 lines
of engine.

**What it breaks.** Four things, in descending order of how much they should
matter:

- **It writes into the corpus.** `games/` and `test-games/` are the owner's data
  and are not to be modified; the transcodes would have to live somewhere else and
  the resolver would need a second search root, which is a real design decision
  about where a title's data lives rather than a build step.
- **It does not generalise.** This is a per-disc manual pass. The next Director
  title arrives with QuickTime and Cinepak and needs it again, which makes it a
  chore attached to every corpus rather than an engine feature.
- **It changes the premise.** The engine's stated design is that it reads the
  original containers at runtime. A transcode makes part of the media a build
  artifact, and that is a bigger claim to give up than one title's intro is worth.
- MPEG audio would become Vorbis; at 320x240 and 352x288 the picture quality cost
  of Theora is not a real objection, and neither is decode speed.

**What it buys.** All 23 clips actually play, on every platform Godot ships,
with no native dependency and no licensing question. It is the only option that
produces pictures for a bounded, known amount of work.

### C. Implement the decoders in this port

This splits into two options that have been treated as one, and separating them is
the most useful thing in this document.

**C1 — the AVI half is small, and it is the entire type-10 story in this corpus.**
`logo.avi` is 8-bit Microsoft RLE. That is not a codec, it is a run-length
encoding: roughly 60 lines to decode, plus ~150 for the RIFF walk and the index,
plus a `BITMAPINFOHEADER` palette read this port already does for bitmaps, plus
raw PCM into an `AudioStreamWAV` — which `director/director_sound.gd` already
builds. 640x480 at 11.11 fps is 3.4 Mpix/s of RLE expansion; in GDScript that is
marginal and in a `Image`-level blit it is fine. ScummVM implements exactly this
pair (`video/avi_decoder.cpp` with `image/codecs/msrle.cpp`) with no external
dependency, which is the shape to copy. **Both `#digitalVideo` members in eight
corpora are AVI**, so this alone closes the type-10 half.

**C2 — the MPEG-1 half is not small.** MPEG-1 video is variable-length codes,
inverse DCT and motion compensation; 352x288 at 25 fps is 2.5 Mpix/s of IDCT
output and GDScript will not do it. The realistic shape is a GDExtension wrapping
`pl_mpeg` — a single-file, public-domain MPEG-1 video+audio decoder of a few
thousand lines, which is exactly this format and nothing else. ScummVM's own
MPEG path (`video/mpegps_decoder.cpp`) is gated on `USE_MPEG2` and an external
libmpeg2, so the reference does not give this away for free either.

**What C2 breaks.** It puts a native build into a project that is pure GDScript
plus stock Godot today. Every desktop platform needs a binary, and — this is the
one to raise before anybody starts — **Android and iOS need one per ABI**, which
`docs/ANDROID.md` and `docs/MOBILE.md` would have to absorb. That is a mobile
export blocker introduced for one unshipped test title.

**What it buys.** C1 buys the logo, from the original file, with no dependency.
C2 buys the intro and the 20 album clips, from the original files, and generalises
to any MPEG-1 disc that arrives later.

### D. Use a Godot plugin

The FFmpeg-backed GDExtensions (EIRTeam.FFmpeg, and the older `godot-videodecoder`
lineage) provide a `VideoStream` implementation that decodes MPEG-1, AVI/MS-RLE and
QuickTime alike.

**What it takes.** The dependency, per-platform binaries, and the same 200–400
lines of engine glue as B.

**What it breaks.** More than any other option here:

- **Licensing.** An FFmpeg build is LGPL or GPL depending on how it is configured;
  shipping one changes this project's distribution terms. That is a decision for
  the owner, not a technical choice.
- **Size.** An FFmpeg build is tens of megabytes against a 1.7 MB AVI and 197 MB of
  MPEG the owner already has.
- **Mobile.** Per-ABI native builds, same blocker as C2 and larger.
- **Version coupling.** The project's Godot version becomes whatever the addon
  supports.

**What it buys.** Every format, including ones this corpus does not have.

---

## 5. The recommendation

**Take A now. Take C1 next if anybody wants the logo. Do not take C2 or D, and
take B only if the owner decides Magic Hat's album is worth changing what the
engine ships.**

The reasoning, in the order it should be weighed:

1. **The six shipped titles are unaffected, and that is a measurement rather than
   a hope.** 0 members, 0 sprites, 0 media files, 0 scripts. Nothing about the
   decoder question touches the titles this engine exists for.
2. **Nothing is blocked.** The one title with video degrades cleanly on all three
   of its video frames, by its own authored fallbacks, and the fallbacks work
   *because* the port answers honestly. That is the difference between a missing
   feature and a bug, and it is now asserted.
3. **A decoder is not a Director feature.** `AGENTS.md` is right that engine
   completeness is not corpus-driven — build what Director has because Director
   has it. Director's digital-video *feature* is the property surface and the
   sprite behaviour, and 38 of ~40 names of it are already bound. The decoding was
   QuickTime's and Video for Windows', and Director drew nothing when they were
   absent. "No codec installed" is a state Director had, and answering it exactly
   is fidelity, not a gap. That argument covers C2 and D; it does **not** cover the
   two items in §6, which are Director's own and are still missing.
4. **C1 is cheap and self-contained** — no dependency, no mobile question, a
   format the reference decodes in one small file, and it closes the whole type-10
   half of this corpus. It is the only decoder work with a good ratio.
5. **C2 and D both introduce a native, per-ABI dependency**, and the mobile export
   story has to absorb it before, not after. For one test title's intro, that is
   the wrong trade.
6. **B is the honest fallback if pictures are wanted.** It is bounded and it works
   everywhere, and its real cost is not technical — it is that the engine stops
   reading only the original media. That is the owner's call, not this document's,
   and it is a deliberate change of premise rather than an implementation detail.

## 6. What to build regardless of any of that

Two items are Director's own, are still missing, and are now unblocked by this
census. Neither needs a decoder.

- **The type-10 specific block.** ~~`director_cast.gd:_parse_specific` has no arm
  for it~~ **Done.** Twelve bytes -- a rect and one flag word -- decoded against
  both samples, so `the controller`, `directToStage`, `video`, `sound`, `crop`,
  `center`, `frameRate`, `pausedAtStart`, `loop` and `preLoad` now come out of the
  member rather than out of Director's dialog defaults, and the member reports its
  own 640x480 size and its centre registration point. `the scale` is the one that
  still answers a default and is D7's, which no D5 block carries. What follows is
  the argument as it was written.
  `docs/ENGINE_TODO.md` records that this "cannot get [an arm] honestly today: no
  member in any of the six titles is a digital video, so there is no sample to
  measure a layout against". **There are now two samples** — `logo.dir` #27 and
  #28 — and `ScummVM castmember/digitalvideo.h` names every field the block has to
  yield. A member with no width, height or registration point is also `bugs.md` 82's
  and 84's shared shape, and it is why a video sprite has no size even before it
  has no picture.
- **The Xtra sprite surface.** `sprite(N).play()`, `.stop()` and
  `.getPlaybackEvent` are Xtra sprite methods and none is bound. Building them is
  worthwhile — but read §3 first: `getPlaybackEvent` must **not** answer 1 while
  there is nothing behind it, because 1 is the arm that loops for ever. The correct
  unbound answer today is the one it already gives.

## 7. Reproducing all of it

```bash
G="/c/Program Files/Godot_v4.7.1/Godot_v4.7.1-stable_mono_win64_console.exe"

# the census, over every corpus, plus every media file classified
"$G" --headless --audio-driver Dummy --path . --script tools/video_census.gd
"$G" --headless --audio-driver Dummy --path . --script tools/video_census.gd -- --list

# the fallback: drive the playhead onto every video frame and watch it leave
"$G" --headless --audio-driver Dummy --path . --script tools/video_fallback.gd -- \
    --root res://test-games/itamar-magichat --boot magichat.dir --each
"$G" --headless --audio-driver Dummy --path . --script tools/video_fallback.gd -- \
    --root piposh2 --boot strtgame.dir

# the Xtra members, by symbol and by rect -- where the 352x288 / 320x240 pair comes from
"$G" --headless --audio-driver Dummy --path . --script tools/xtra_members.gd -- \
    --roots res://test-games/itamar-magichat --list

# the movies' own handlers
"$G" --headless --audio-driver Dummy --path . --script tools/director_extract.gd -- \
    --root res://test-games/itamar-magichat --file logo/logo.dir --out <dir>
"$G" --headless --audio-driver Dummy --path . --script tools/director_extract.gd -- \
    --root res://test-games/itamar-magichat --file magichat.dir --out <dir>
```
