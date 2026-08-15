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
> §6's second (the Xtra sprite methods) is not. **C2 and D have both since been
> taken — see §4C2 and §8 — and C2 is what plays the 22 MPEG-1 clips today.**
> Everything below is the census and the costing as they were written, and they
> are still what the decision rests on -- read §3 before touching `the duration`.

> **Update, later: D was taken and B was dropped.** The owner has ruled out the
> transcode route and asked for a decoder plugin instead, which reverses §5's
> ordering of the last two options — not its costing of them, which stands and is
> why §8 opens with the licensing paragraph. §4D's four objections are all still
> true of *installing* an extension; none is true of being able to use one, and
> that split is the whole of what landed. **`scenes/preview/video.gd` now has a
> third backend, gated on `ClassDB.class_exists` rather than on a `preload` of an
> addon path, and with nothing installed the engine is byte for byte the engine
> below.** §8 is the install steps, the Android per-ABI blocker, what breaks if
> the plugin's Godot floor rises, and — named separately from the rest — which
> parts of the plugin's API were read from its source and which are inference.
> The §4B sidecar path is untouched and still works; it is now step 3 of five
> rather than step 2 of four.

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

> **C2 was taken on 2026-08-15 and works. Everything in this subsection is the
> argument against doing it, kept because it is what the attempt had to answer —
> and one clause of it is simply wrong.** All 22 clips decode from the original
> bytes in GDScript, with no native build, no plugin and no transcode:
> `director/director_mpeg1_ps.gd`, `director_mpeg1_video.gd`, `director_mpeg1.gd`.
> The wrong clause is "GDScript will not do it". It does it — **not at real time**,
> which is the honest correction: 53-366 ms per coded picture, 8% to 42% of real
> time, so a 25 fps clip plays at roughly 2-10. `preview/video.gd` picks the frame
> from `the movieTime`, so a slow decode drops pictures and keeps the clock rather
> than falling behind. The prediction was right about the cost and wrong about the
> verdict, and a clip that plays slowly is worth more than one that does not play.
>
> What it does **not** buy: MPEG-1 Layer II audio, so the clips are silent. That
> is a second decoder — a 512-tap polyphase filterbank, ~45 million multiplies for
> `intro.mpg` — and it is a named gap rather than a claim the files have no sound.
> The reader parses the audio frame header, so `the sampleRate`, `the sampleSize`
> and `the channelCount` answer the file's own numbers.

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

> **This is the option that was taken; §8 is what landed.** Everything below is
> the costing as it was written and every objection in it still stands — which is
> why §8 ships no binary, requires none, and downloads none. What §8 adds is the
> engine code that *uses* one when the owner installs it, gated so that an
> uninstalled one changes nothing.

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

> **Superseded on the last two items, and §8 is why.** A and C1 were taken and
> are still right. B was taken and has been *demoted*: the owner ruled out the
> transcode route, and the sidecar path survives as a fallback rather than as the
> answer. D was taken in the only form that does not pay §4D's costs — the engine
> can use a decoder extension, and ships none. The reasoning below is what that
> decision was weighed against and is unchanged; read item 3 in particular, since
> it is the argument §8 had to answer rather than one §8 overturned.

> **Superseded 2026-08-15.** D was taken (§8) and then measured as decoding 0 of
> this tree's 23 files; **C2 was taken and plays all 22 MPEG-1 clips**. The verdict
> below is kept because its *reasoning* is still the right reasoning — item 3
> especially — and because a recommendation that turned out wrong is worth more
> visible than deleted. What it got wrong was one engineering estimate, not a
> principle: it refused C2 on "GDScript will not do it", and the correct answer
> was "GDScript will do it at 8-42% of real time, which for a 1997 cutscene is
> enough".

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
- **The Xtra sprite surface.** ~~`sprite(N).play()`, `.stop()` and
  `.getPlaybackEvent` are Xtra sprite methods and none is bound.~~ **Done**, and
  the §3 rule survived intact: all three are in `preview/media.gd:SPRITE_PROPS`
  and answered off the same per-channel playhead as `the movieTime`, so a movie
  that starts a clip with `play()` and reads it back through the properties sees
  one position. `getPlaybackEvent` answers **1 only while a reader is open, the
  rate is non-zero and the playhead is short of the end**, `0` when stopped or
  finished, and **VOID when there is no media at all**
  (`preview/video.gd:playback_event`) — VOID rather than 0 because that is what
  the name answered when it was bound to nothing, and it is what all three of
  Magic Hat's video frames leave on today. What follows is the warning as it was
  written, and it is still the thing not to get wrong: 1 with nothing behind it
  is the arm that loops for ever.

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

# the decoder-extension gate: what is installed, and that absence changes nothing
"$G" --headless --audio-driver Dummy --path . --script tools/video_plugin.gd -- \
    --root res://test-games/itamar-magichat --boot magichat.dir
"$G" --headless --audio-driver Dummy --path . --script tools/video_plugin.gd -- \
    --root res://test-games/itamar-magichat --list

# the Xtra members, by symbol and by rect -- where the 352x288 / 320x240 pair comes from
"$G" --headless --audio-driver Dummy --path . --script tools/xtra_members.gd -- \
    --roots res://test-games/itamar-magichat --list

# the movies' own handlers
"$G" --headless --audio-driver Dummy --path . --script tools/director_extract.gd -- \
    --root res://test-games/itamar-magichat --file logo/logo.dir --out <dir>
"$G" --headless --audio-driver Dummy --path . --script tools/director_extract.gd -- \
    --root res://test-games/itamar-magichat --file magichat.dir --out <dir>
```

---

## 8. Option D, taken: a decoder extension, gated on it being installed

> **§9 supersedes this section on three points, and they are the three that
> matter to anybody acting on it.** §8 was written with no addon installed and
> says so; §9 is what happened when one was. Read §9 first if you are about to
> install anything.
>
> 1. §8.3's install listing shows `macos/` and `android/` directories. **The
>    archive does not contain them** — win64 and linux64 only.
> 2. §8.4 says an Android APK "runs on 64-bit ARM devices and on nothing else".
>    It runs on nothing: there is no Android binary at all, and an export made
>    with the addon in the tree shipped seven **zero-byte** `.so` files. §9.2 has
>    the measurement and the export-preset fix.
> 3. §8.6 and §4D both assume the plugin decodes this corpus. **It decodes none
>    of it** — no MPEG-PS demuxer, no MS-RLE decoder. §9.1.
>
> Everything §8 says about the *engine side* was measured correct and stands.

> **Update.** §4D refused a plugin and §5.5 restated the refusal. The owner has
> since ruled out the transcode route (§4B) instead, and asked for a decoder
> plugin. §4D's four objections are all still true — they are the reasons the
> extension is **not shipped in this repository**, is not downloaded by anything
> here, and is not required by anything here. What landed is the engine-side half:
> the code that *uses* one when the owner installs it, and that is bit-for-bit
> inert when they have not.
>
> This section is what the owner must do, in order, and what breaks if a step is
> skipped. §4D's costing above is unchanged and is still the argument for reading
> the licensing paragraph before the install one.

### 8.1 What was built

Three files and one harness:

| file | what it is |
|---|---|
| `director/director_plugin_video.gd` | the **adapter** — the only file that names a plugin class; decides whether one is installed, hands it a path, exposes `duration_ms` |
| `director/director_ogg.gd` | gained `video_stream()`, the seam the two push backends meet at |
| `scenes/preview/video.gd` | a third arm in the resolution order, and one `_is_push` predicate replacing three copies of a Theora test |
| `tools/video_plugin.gd` | the gate's harness — in `gate.sh`'s `ALL` |

The resolution order is now, in the order it is tried:

1. the member's own name, resolved against the disc (`video.gd:media_path`);
2. **a decoder extension**, if one is installed *and* it takes this container;
3. a fresh Ogg Theora sidecar, if the cache has one;
4. the original bytes through the MS-RLE AVI reader;
5. nothing.

Step 2 is before step 3 because the extension plays the **original** media and
the sidecar plays a copy, and the engine's premise is that it reads the original
containers at run time; an owner who installs a decoder is asking for exactly
that. Step 3 survives because it works, costs nothing to keep, and an owner who
has already spent an afternoon of `ffmpeg` on 197 MB should not lose it the day a
plugin lands.

**`getPlaybackEvent` keeps its contract exactly**, and none of the three
backends changed it (`video.gd:playback_event`): `1` only when a reader is open,
the rate is non-zero and the playhead is short of the end; `0` when stopped or
finished; **VOID when there is no media**. §3 is the account of why the third of
those is the one that matters — the other arm of `BehaviorScript 134` is
`go(the frame)` and never ends.

### 8.2 The rule that makes absence free

**Nothing in the engine may `preload` an addon path.** A `preload` of a script
that is not there is a GDScript *parse* error, and a parse error in a file the
preview preloads takes the whole engine down before a movie opens — every gate
entry and every title, over a decoder for one unshipped test title. So the only
questions asked are `ClassDB.class_exists`, `ClassDB.can_instantiate` and
`ClassDB.instantiate`, all three of which answer honestly at run time for a class
that was never registered.

`tools/video_plugin.gd` asserts that as a **source scan** over `director/`,
`scenes/`, `lingo/`, `autoload/` and `scripts/`, because the failure it guards
happens at parse time where no runtime check can reach it.

Measured with nothing installed, `4.7.1`, Windows, `--audio-driver Dummy`:

```
decoder extension : none installed
ok    no `preload("res://addons/…")` under res://director, res://scenes, res://lingo, res://autoload, res://scripts
ok    `available()` is false with no extension installed
ok    `handles()` is false for all 22 container extensions
ok    no non-stock loader claims the VideoStream type
ok    all 8 declined, every one of them on the class gate
ok    no reader the engine opened is on the plugin backend
ok    `getPlaybackEvent` of a channel with no media is VOID
PASS  (7 checks, 0 failed)
```

and `video_fallback` on both roots is unchanged: `piposh2` asserts nothing and
says so, `itamar-magichat` still reports `1 with media / 1 without`, all three
video frames leaving, and the one started video advancing.

### 8.3 Installing EIRTeam.FFmpeg 1.1.4 — what the owner must do

The engine looks for the class **`FFmpegVideoStream`**. That is EIRTeam.FFmpeg's,
and it is the only name in `director_plugin_video.gd:CLASSES`.

1. **Decide the licensing question first.** An FFmpeg build is LGPL or GPL
   depending on how it was configured, and the plugin's binaries embed one.
   Shipping them changes this project's distribution terms. The plugin's own code
   is MIT; the FFmpeg inside it is not, and that is the part that travels. This is
   the owner's decision and no code here can make it.
2. **Get the release.** `eirteam-ffmpeg-1.1.4.zip`, the asset on the
   `autobuild-2025-11-12-13-44` tag of `github.com/EIRTeam/EIRTeam.FFmpeg`
   (commit `270e661`). Nothing in this repository downloads it.
3. **Unzip into `addons/`**, so the layout is what the `.gdextension` already
   declares. **Corrected against the archive** — the last two lines were in this
   listing and are not in the zip:

   ```
   addons/ffmpeg/ffmpeg.gdextension
   addons/ffmpeg/win64/libgdffmpeg.windows.template_{debug,release}.x86_64.dll
   addons/ffmpeg/win64/{avcodec,avfilter,avformat,avutil,swresample,swscale}-*.dll
   addons/ffmpeg/linux64/libgdffmpeg.linux.template_{debug,release}.x86_64.so
   addons/ffmpeg/linux64/lib{avcodec,avfilter,avformat,avutil,swresample,swscale}.so.*
   ```

   That is the whole archive: two platform directories and the `.gdextension`.
   The `.gdextension` nonetheless declares `android.*.arm64` and `macos.*`
   libraries, and EIRTeam builds only Linux and Windows (`.github/workflows/`
   has `linux_builds.yml` and `windows_builds.yml` and nothing else). §9.2 is
   what that costs an export.

   `bash tools/fetch_video_plugin.sh` does steps 2 and 3 against a pinned tag
   with a sha256 check, and prints the declared-versus-present platform lists so
   the gap above is visible at install time rather than at export time.

   The paths inside `ffmpeg.gdextension` are absolute `res://addons/ffmpeg/...`,
   so the directory name is not negotiable: unzipping to `addons/EIRTeam.FFmpeg/`
   leaves an extension that loads nothing and reports nothing.
4. **`project.godot` needs no edit.** A `.gdextension` anywhere under `res://` is
   scanned and loaded at startup; it is not an EditorPlugin and has no
   `enabled_plugins` entry. Nothing has to be ticked in Project Settings, and
   `director/video/extra_stream_classes` — the setting the adapter reads for
   *other* plugins — stays absent.
5. **Open the editor once, then close it.** The extension's classes must be in
   the editor's class database before a headless run resolves them, and this
   project already requires that step for `global_script_class_cache.cfg`
   (`AGENTS.md`, Environment).
6. **Verify with the harness, not by playing:**

   ```bash
   "$G" --headless --audio-driver Dummy --path . --script tools/video_plugin.gd -- \
       --root res://test-games/itamar-magichat --boot magichat.dir
   ```

   It should name `FFmpegVideoStream`, print the extensions the loader claims,
   and report the MPEG-1 clips opening with real durations. Then
   `tools/video_fallback.gd` on the same root, which is the one that would catch
   a member reporting ready with a frozen playhead.

### 8.4 What breaks, and where

- **Android needs one binary per ABI, and 1.1.4 ships ~~one~~ none.**
  ~~The `.gdextension` declares `android.template_debug.arm64` and
  `android.template_release.arm64` and **nothing else** — no `arm32`, no
  `x86_64`. So an APK built with the extension in the tree runs on 64-bit ARM
  devices and on nothing else.~~ **Corrected by measurement, §9.2.** The
  `.gdextension` does declare exactly those two `arm64` entries — but the release
  archive contains no `android/` directory, so the APK gets *zero-byte* files
  where those libraries should be and the extension loads on no device at all.
  The rest of the paragraph as written was right and is the reason it does not
  matter much: the failure is at extension load, before any Godot code runs, and
  it is **non-fatal** — three console errors and an engine that carries on with
  no video decoding. `docs/ANDROID.md` and `docs/MOBILE.md` carry that, and the
  export presets now exclude `addons/*` on Android, iOS and macOS so the broken
  libraries are not written in the first place. iOS has no entry in the
  `.gdextension` at all, so an iOS export with this addon is not a per-ABI problem
  but an absent one.
- **Size.** An FFmpeg build is tens of megabytes per platform, against 197 MB of
  MPEG-1 the owner already has and a 1.7 MB AVI this port decodes in GDScript.
  Every platform's binaries ship in every export unless the export presets are
  told otherwise.
- **A compatibility floor above 4.7.1 is a hard stop, not a warning.**
  1.1.4 declares `compatibility_minimum = 4.1`, so 4.7.1 is fine today. If a
  future release raises it *above* the project's Godot version, Godot refuses to
  load the extension: the classes are never registered,
  `ClassDB.class_exists("FFmpegVideoStream")` answers false, and — this is the
  design working — the engine falls straight back to the sidecar, the AVI reader
  and nothing. The videos stop playing and **nothing else changes**. The failure
  is loud in the console and silent in the game, which is the right way round.
  The other direction is the real trap: an extension built against a *newer*
  Godot than the one running it is the case Godot cannot always detect, and it
  crashes rather than declines. Match the build to the engine.
- **A plugin that is installed but declines the file** is a normal state, not a
  bug: a stripped FFmpeg build without the MPEG-1 demuxer says so through
  `ResourceLoader.get_recognized_extensions_for_type("VideoStream")`, and the
  adapter's `handles()` reads exactly that list.

### 8.5 What is confirmed from the plugin's source, and what is not

The plugin could not be run here — it is not installed and nothing was
downloaded — so its API was read from source on `raw.githubusercontent.com` at
commit `270e661`. Reading text is not installing a binary.

**Confirmed** (`register_types.cpp`, `ffmpeg_video_stream.h`,
`video_stream_ffmpeg_loader.cpp`, `gdextension_build/ffmpeg.gdextension`):

- `FFmpegVideoStream` is registered with `GDREGISTER_CLASS` — concrete and
  script-instantiable — and is `GDCLASS(FFmpegVideoStream, VideoStream)`.
- It declares **no** `set_file`/`get_file`; it uses the `VideoStream` base
  class's, which is stock Godot's scripting API. So the adapter's one call into
  it is Godot's, not the addon's.
- `FFmpegVideoStreamPlayback` implements `play`, `stop`, `set_paused`,
  `is_paused`, `is_playing`, `seek`, `update`, `get_length`,
  `get_playback_position`, `get_texture`, `get_mix_rate`, `get_channels` — which
  is exactly the set `VideoStreamPlayer` drives, and is why the existing Theora
  playback path in `video.gd` works against it unchanged.
- The loader handles type `"VideoStream"` and takes its extensions from
  `av_demuxer_iterate()`, i.e. whatever the linked FFmpeg build demuxes.
- Entry symbol `ffmpeg_init`, `compatibility_minimum = 4.1`, Android `arm64`
  only.

**Not confirmed, and isolated in the adapter with the uncertainty in its
docstring:**

1. **That `VideoStreamPlayer.get_stream_length()` answers before `play()`.** This
   is how `the duration of member` is learned. If the inference is wrong the
   answer is 0, and **0 is refused** — `open()` returns false and the member falls
   through to the sidecar, the AVI reader and nothing, which is today's
   behaviour. A wrong guess therefore costs a clip that does not play, never a
   movie that hangs, which is the split §3 is entirely about.
2. **That the sound track's rate and channel count cannot be read.** Godot
   exposes no script accessor and the plugin's are on `VideoStreamPlayback`, which
   scripts cannot reach. So `the sampleRate`, `the sampleSize` and `the
   channelCount of member` answer 0 on this backend and `trackCount` counts the
   video track alone. `director_ogg.gd` reads both out of the Vorbis
   identification header; there is no equivalent parse for an arbitrary container,
   and answering `44100` would be exactly the plausible invention §3 forbids.
3. **That a different plugin can be named rather than coded for.**
   `director/video/extra_stream_classes` is a comma-separated project setting of
   further class names. It works for any extension that registers a *concrete*
   `VideoStream` subclass driven by the base-class `file` property. An extension
   shaped differently — one whose player is a `Node` of its own — cannot be made
   to work by naming it, and the adapter type-checks what `ClassDB.instantiate`
   returns and declines anything that is not a `VideoStream`.

**And one thing this backend gives up on purpose.** `director_ogg.gd`'s header
argues that the property surface must not be answered by asking the thing that
plays the file, because a duration out of the player cannot be used to check the
player. That is why the Theora backend has a parser beside it. It cannot be
honoured here and pretending otherwise would be worse than saying so: there is no
single format to parse — the point of a decoder extension is that the set of
formats is open-ended, so a parser covering them would *be* the decoder. What
keeps it safe is not an independent parse but the refusal in item 1.

### 8.6 Also fixed here, because it is one condition and it guards this feature

`tools/video_fallback.gd:_visit` counted a frame as "held for a reason" only when
the **clock** had one — a tempo delay, a transition, `pause`, a sound. A playing
video was not on that list, and it cannot be: a video runs on the engine tick,
*outside* the score step, precisely so that a movie sitting on `go(the frame)`
can wait for it.

It passed only by luck. All three of Magic Hat's video frames record several
states while they walk their region today, so `frames.size() > 1` returns `left`
before the hold logic is reached. A movie that **settled** on a video frame —
which is what this feature makes possible for the 87-second intro and the twenty
album clips — would have been reported `parked-on-video`: the harness calling a
working feature a hang, on the day the feature started working.

The condition added is the narrow one, and every part of it is measured by the
harness rather than asked of the engine: **a non-zero `the movieRate` and a
`the movieTime` that moved since the previous tick.** Deliberately not
`getPlaybackEvent`, which is the engine's own answer and would make the check
circular; and deliberately not a non-zero rate alone, because a rate against a
*frozen* playhead is exactly the hang the harness's third check exists to name.

---

## 9. The extension installed and run: what it actually does

> **Everything in §8 was written with no addon present.** §8 says so plainly and
> that was honest, but it means every sentence in it about what an installed
> extension *does* was inference. The extension has now been installed and run.
> The engine-side inferences all held. **The one thing nobody inferred is that
> the plugin cannot decode a single file this project has**, and that is the
> finding this section exists for.
>
> Measured on Godot 4.7.1 stable mono, Windows, `--audio-driver Dummy`, against
> the `addons/ffmpeg/` already in the working tree, stated to be
> EIRTeam.FFmpeg 1.1.4 unpacked.
>
> **Provenance, with the one thing that does not line up.** That release has
> exactly one asset — `eirteam-ffmpeg-1.1.4.zip`, 11,003,257 bytes, sha256
> `1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c`, tag
> `autobuild-2025-11-12-13-44`, commit `270e661` — and the zip itself was not
> available here to re-hash, so the tree was **not** verified against it. It does
> contain four files EIRTeam's `windows_builds.yml` deletes before packaging
> (`Remove-Item … -Include *.exp,*.lib,*.pdb`): two `.exp` and two `.lib`, 6 KB
> total, MSVC link-time artifacts that do nothing at run time. So either the
> workflow's delete does not cover the release path, or this tree came from
> somewhere other than that asset. Nothing below depends on which — every
> behavioural claim here was measured against these binaries as they sit — but
> `tools/fetch_video_plugin.sh` fetches and hashes the asset, so a re-run from
> scratch does not carry the same doubt.

### 9.1 It decodes none of this corpus, and that is a build-flags fact

The plugin prints its own codec table at startup. On this build it is:

```
Supported video codecs:
	decode h263      decode mpeg4     decode h264      decode vp8    decode vp9
	decode mp3       decode aac       decode vorbis    decode opus   decode aac_latm
```

and `ResourceLoader.get_recognized_extensions_for_type("VideoStream")` gains
exactly these 21 names:

```
aac avi flv mkv mk3d mka mks webm mov mp4 m4a 3gp 3g2 mj2 psp m4b ism ismv isma f4v avif
```

**`mpg`, `mpeg` and `m1v` are not among them, and neither is any MPEG-1 or MS-RLE
decoder.** This corpus is 22 MPEG-1 program streams and one MS-RLE AVI. The
plugin takes **0 of 23**.

The two failures are different and both were measured directly:

| file | what happens | where it fails |
|---|---|---|
| `heb/mainmenu/intro.mpg` | `avformat_open_input` returns *Invalid data found when processing input* | the **demuxer**: MPEG-PS is not compiled in, so the container is not even recognised. Handed to the class directly, bypassing the adapter's extension gate, it still fails. |
| `logo/logo.avi` | opens, then *Couldn't find video stream: Decoder not found*, playback null, `get_stream_length()` 0 | the **decoder**: the AVI demuxer *is* in, so the extension gate takes the file; there is no `msrle` decoder behind it. |

This is not a stripped-by-accident build. EIRTeam's Windows workflow downloads
`ffmpeg-master-latest-win64-lgpl-godot.tar.xz` from `EIRTeam/FFmpeg-Builds`,
whose `variants/lgpl-godot.sh` begins

```
--disable-decoders --disable-demuxers --disable-encoders --disable-muxers …
```

and then re-enables `--enable-demuxer=mov,aac,flv,avi`, `--enable-demuxer=matroska`
and `--enable-decoder=mpeg4,h264,aac,aac_latm,mp3` plus vp8/vp9/vorbis/opus. The
running library and the build recipe agree exactly. **The variant is called
`lgpl-godot` because it exists to give Godot games h264 and WebM playback** — a
modern-media codec set. It was never a general FFmpeg, and §4D's "every format,
including ones this corpus does not have" was wrong about this plugin.

**Every engine-side inference in §8 held**, which is the other half of the
result and is worth stating separately from the disappointment:

- `FFmpegVideoStream` is registered, concrete and instantiable; `ClassDB` is the
  right gate and answers correctly.
- `VideoStream.set_file` is the right call — the base class's, not the addon's.
- `VideoStreamPlayer.get_stream_length()` **does** answer before `play()`
  (unverified item 1). It is how `logo.avi`'s refusal was detected: the probe
  returned 0 and `open()` refused, exactly as designed.
- **The zero-duration refusal is load-bearing and did its job on the first file
  that reached it.** `logo.avi` would otherwise have become a member reporting
  ready with no duration — the §3 hang — *and* would have taken a format this
  port decodes in GDScript away from the reader that decodes it. Instead the
  adapter refused and `director_avi.gd` opened it at 10.08 s.

The cost of that refusal is two engine `ERROR` lines per attempt, from inside the
extension, which GDScript cannot suppress. They are noise in a suite whose job is
to say which entries are clean, and they are the price of the plugin being asked
about a file its build cannot decode.

**One open question this raises, deliberately not answered here.** The plugin is
offered `.avi` *before* `director_avi.gd`, because §8.1's ordering argument was
about the plugin versus the *sidecar* — original media beats a transcoded copy —
and the AVI reader also reads the original, so that argument does not decide
between them. Today it does not matter: the plugin fails, is refused, and the AVI
reader gets the file. Whether it *should* be asked at all for a format this port
already decodes is a scope decision, and narrowing it would mean the engine
preferring its own GDScript decoder over an installed native one for one
container — which is a different premise from "an installed extension plays the
original media". Left as it is, recorded here, and the harness now asserts the
fallthrough so a change to it cannot go unnoticed.

### 9.1.1 What frame 125 does now

`magichat.dir` frame 125 channel 1, `IntroRetroVideo` → `heb/mainmenu/intro.mpg`.
Windowed run, sidecar cache emptied first so the Theora path could not answer:

```
readers : { "6:178": "none <- …/heb/mainmenu/intro.mpg" }
streams : []
```

The member resolved its file on disc, the plugin declined it, there was no
sidecar, the AVI reader declined it, and the movie skipped the frame and carried
on — which is the correct behaviour and is what `video_fallback` asserts. **The
intro does not play through the plugin.**

With the sidecar put back, the same frame in the same windowed run:

```
ch1 getPlaybackEvent=1 movieTime=  159  pos= 0.13s  flat 352x288 1 colour
ch1 getPlaybackEvent=1 movieTime= 2256  pos= 3.76s  352x288 235 distinct colours mean rgb(0.40,0.35,0.20)
ch1 getPlaybackEvent=1 movieTime= 9026  pos=15.04s  352x288 234 distinct colours mean rgb(0.41,0.36,0.20)
ch1 getPlaybackEvent=1 movieTime=15671  pos=26.12s  352x288 255 distinct colours mean rgb(0.51,0.38,0.24)
```

`getPlaybackEvent` 1, `movieTime` advancing, a texture with real colour — on the
**theora** backend. That is what the plugin was installed to replace and it is
still the only thing that plays this clip. The colours are sampled on a 16x16
grid of a real window; the same run headless reads the texture back flat, which
is `a938a7f3`.

### 9.2 What each export actually gets, measured

The archive carries **`win64` and `linux64` only**. Its own `.gdextension`
declares `windows`, `linux`, `android` and `macos`. §8.3's install listing showed
`macos/` and `android/` lines as if the zip had them; it does not, and the
listing is wrong. There is no iOS entry at all.

Exports run with `addons/ffmpeg/` in the tree, before the preset fix below:

| preset | result | what shipped |
|---|---|---|
| **Windows Desktop** | clean, exit 0 | the six FFmpeg DLLs and `libgdffmpeg….dll` beside the exe, `ffmpeg.gdextension` in the pck. **+10.4 MB.** Correct. |
| **Linux** | not run here; same declaration shape as Windows and the binaries are present | — |
| **Android** | **exit 0, and this is the bad one.** Seven `ERROR: Can't open file from path 'res://addons/ffmpeg/android/…'` | the APK contains **seven zero-byte `.so` files** in `lib/arm64-v8a/` — `libgdffmpeg.android.template_debug.arm64.so`, `libavcodec.so`, `libavfilter.so`, `libavformat.so`, `libavutil.so`, `libswresample.so`, `libswscale.so` — plus `assets/addons/ffmpeg/ffmpeg.gdextension` naming them. The exporter wrote empty entries rather than skipping. |
| **macOS** | exit 0, one `ERROR: Failed to open '…macos/libgdffmpeg.macos.template_debug.framework'` | no framework, no dylibs, but `ffmpeg.gdextension` **is** in the pck, declaring a macOS library that is not there. |
| **iOS** | could not be measured — this host refuses an Apple Embedded export with the mono build. Not asserted. |

**The export does not abort on a missing GDExtension library.** That was the open
question and the answer is no, on both platforms it could be asked on.

**And at runtime a missing library is a clean decline.** Simulated on Windows by
pointing the `windows.*.x86_64` entries at a path that does not exist and running
the real harness:

```
ERROR: Condition "!FileAccess::exists(path)" is true. Returning: ERR_FILE_NOT_FOUND
ERROR: GDExtension dynamic library not found: 'res://addons/ffmpeg/ffmpeg.gdextension'.
ERROR: Error loading extension: 'res://addons/ffmpeg/ffmpeg.gdextension'.
Godot Engine v4.7.1.stable.mono.official …
```

then the engine starts normally, `ClassDB.class_exists("FFmpegVideoStream")` is
false, and `tools/video_plugin.gd` passes **every one of its absent-case checks**
and exits 0. Three console errors, no crash, no player-visible failure — the
failure point is `GDExtensionManager::load_extensions`, which continues past a
failed extension, and `OS::open_dynamic_library`, which is the same call on
Android. So an APK built with those zero-byte libraries **runs**, logs three
errors to logcat, and has no video decoding. The player sees nothing wrong.

What was **not** measured, and is not asserted anywhere: whether Android's
package installer accepts an APK containing zero-byte files under `lib/`. No
device was attached. A zero-byte file is not a valid ELF, `dlopen` on it cannot
succeed, and nothing in the Android toolchain is designed to produce one — that
is reason enough not to ship it, without needing to know whether install also
fails.

**The fix, applied.** `export_presets.cfg` now carries `addons/*` in the
`exclude_filter` of the **Android, macOS and iOS** presets and not the Windows or
Linux ones. Re-measured on Android: **0 export errors**, no `ffmpeg.gdextension`
in the APK, and `lib/arm64-v8a/` back to Godot's own two libraries. Windows keeps
its DLLs. That is the right split, because the split is not a preference — it is
which platforms the archive has binaries for.

If a release ever ships Android or macOS binaries, those two exclusions come out
in the same commit that fetches them, and not before.

### 9.3 The licence position, plainly

**The plugin's own code is MIT** — `LICENSE` at the repository root,
"Copyright (c) 2018 Álex Román (EIRTeam)". That is not the part that travels.

**The FFmpeg it carries is LGPL-2.1-or-later.** The build is
`ffmpeg-master-latest-win64-lgpl-godot`, from the `lgpl-godot` variant: no
`--enable-gpl`, no `--enable-nonfree`. That matters and it is the good outcome —
a GPL build would have pulled this project's distribution terms with it. LGPL,
with FFmpeg as six **separate shared libraries** the executable loads at runtime,
does not.

**The archive contains no licence text of any kind.** Confirmed by listing every
file in `addons/` — 21 in total: one `.gdextension`, sixteen shared libraries
(six FFmpeg plus a debug and a release `libgdffmpeg` on each of two platforms),
and four MSVC `.exp`/`.lib` link artifacts. No `LICENSE`, no `COPYING.LGPLv2.1`,
no `NOTICE`, no `README`, no source URL.

So, shipping a build that contains these binaries obliges the project to:

1. **Include the LGPL-2.1 text** and a notice that the work uses FFmpeg under it.
   FFmpeg's own guidance is the line "This software uses libraries from the FFmpeg
   project under the LGPLv2.1" plus the licence text.
2. **Offer the corresponding source** for the FFmpeg version shipped — including
   any patches. A written offer or a URL to the exact sources both satisfy this;
   pointing at `EIRTeam/FFmpeg-Builds` and the upstream commit it built is the
   cheap route, and pinning is what makes "the exact sources" a true statement.
3. **Keep the libraries replaceable**, which dynamic linking against separate
   `.dll`/`.so` files already satisfies. Do not statically link them into the
   executable without re-reading LGPL §6.
4. **Not restrict reverse engineering** of the combined work in any terms the
   project ships under.

Three things this does **not** oblige, stated because overstating is as unhelpful
as waving it away: it does not make this engine LGPL, it does not require
publishing the engine's source, and it does not affect a developer running the
plugin locally without distributing a build.

**One item that is not a licence question and is easy to file as one.** EIRTeam's
README says the bundled FFmpeg "allows loading of videos using the
patent-encumbered h264 codec, check with your local laws". That is a patent
question, separate from copyright, and it does not arise for anything in this
corpus: MPEG-1's patents expired years ago and the plugin cannot decode it anyway.
It arises only if someone re-encodes the media to h264 and ships that.

### 9.4 Vendoring: the decision, and the argument

**The binaries do not go in git.** `addons/` is gitignored;
`tools/fetch_video_plugin.sh` fetches the pinned release and verifies its sha256;
this section and `docs/MOBILE.md` are the documented install step. That is option
(b) of the three, with the fetch script borrowed from option (c).

The three candidates and what each costs here:

**Commit them.** 26 MB on disc, ~11 MB compressed, into a repository that is
otherwise pure GDScript. Against:

- **It buys zero.** Not "little" — zero. 0 of 23 media files. Committing 11 MB of
  third-party binaries for a measured zero is not a close call.
- **It makes this repository a distributor of LGPL FFmpeg**, moving §9.3's four
  obligations onto every clone and every fork, permanently, and git history
  cannot un-ship a binary.
- **It is wrong on half the platforms.** No macOS binary, and the nightly runs on
  macOS. Every macOS checkout would carry a `.gdextension` declaring a framework
  the archive does not contain.
- Binary blobs in history are the one thing a repository cannot cheaply undo, and
  a 1.1.5 would add another 11 MB rather than replace it.

**Fetch in CI.** Rejected because there is nothing for CI to do with it. The
nightly's job is that `ALL` is green, and `ALL` is green **without** an extension
— that is the whole design, and `tools/video_plugin.gd` asserts the absent case
as its primary branch. Fetching 11 MB per run to exercise a second branch that
decodes nothing would add network flakiness to a suite whose value is that a red
means something. If a future build decodes this corpus, this is the option to
revisit.

**Fetch on demand, ignored in git.** Taken. It is `tools/fetch_scummvm_reference.sh`'s
exact shape — a pinned third-party thing, verified, git-ignored, documented,
never vendored — and the reasons match line for line: read/used locally, not
ours to redistribute, and pinned because "latest" rots. The one thing added over
that precedent is a digest check, because unlike ScummVM sources this download is
a compiled library the editor loads on next launch.

The thing that would make committing correct is a build that plays this corpus.
That is not this build, and the decision should be revisited the day it changes
rather than inherited.

### 9.5 Reproducing §9

```bash
G="/c/Program Files/Godot_v4.7.1/Godot_v4.7.1-stable_mono_win64_console.exe"

bash tools/fetch_video_plugin.sh          # then open the editor once and close it

# the gate, with the extension present: 15 checks
"$G" --headless --audio-driver Dummy --path . --script tools/video_plugin.gd -- \
    --root res://test-games/itamar-magichat --boot magichat.dir

# the player-visible half, which must stay green either way
"$G" --headless --audio-driver Dummy --path . --script tools/video_fallback.gd -- \
    --root res://test-games/itamar-magichat --boot magichat.dir --each

# what a mobile export contains -- inspect the APK, do not trust exit 0
"$G" --headless --path . --export-debug Android build/android/probe.apk
python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print([(n,z.getinfo(n).file_size) for n in z.namelist() if 'ffmpeg' in n or n.endswith('.so')])" build/android/probe.apk

bash tools/fetch_video_plugin.sh --remove # and open the editor once again
```

The two facts hardest to get right by reading rather than running are both in
that list: `--export-debug Android` **exits 0** while writing seven broken
libraries, and the codec table only appears when the extension actually loads,
which needs an editor run first.
