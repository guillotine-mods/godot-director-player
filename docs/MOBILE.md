# Shipping this on a phone

What Android and iOS impose on a port that reads the original Director files at
runtime. [`ANDROID.md`](ANDROID.md) is how to install a build; this is what has
to be true for one to work at all.

**The standing rule: rule on mobile before the refactor, not after.** These
limits are absolute rather than awkward — iOS forbids `fork`/`exec` and
unreviewed native code outright, and Android's W^X has blocked executing a
binary from the app's writable data dir since API 29. A design that shells out
to an external tool, ships a native executable, or wants Python at run time is
not "harder to port", it is unshippable, and the discovery arrives after the
work is done. ProjectorRays is the standing example: it produces
`reference/lingo/` as a developer tool and can never be a runtime dependency.

Everything below was measured on this game's own tree, reproduced on a throwaway
Godot 4.7.1 project, or — for the input section — driven through the engine's own
code path by `tools/touch_input.gd`. The section at the end lists what was *not*
verified, because some of the load-bearing claims are inferences.

Two questions, and they fail differently. **Packaging** decides whether a build
ships at all; **input** decides whether the thing that ships can be played. The
second is the one with a decision in it that nobody can make from the code.

## The blocker: the game data does not ship

`export_presets.cfg` carries `include_filter="data/*.json"`. `.dir`, `.cst` and
`.aif` are not Godot resource types, so **without a matching filter they are
silently dropped from the export.** No warning is emitted.

It works in the editor, where `FileAccess.open("res://games/...")` reaches the
real filesystem, and returns `ERR_FILE_NOT_FOUND` in an exported build. The whole
of `director/` fails at boot with nothing said at build time — the expensive
shape of bug, because the thing that catches it is a phone rather than a
compiler.

```
include_filter="games/*"
```

One pattern, recursive, extension-agnostic — and it keeps working if a title
ships `.dxr`/`.cxt`, which `director/director_paths.gd` already anticipates.

**Do not write `games/piposh2/**/*`.** Godot matches with `String.matchn()`,
where `*` already crosses `/` and `**` means nothing at all. The trailing `/`
requirement then excludes every top-level file — here `strtgame.dir` and
`MASTER.CST`, the boot movie and the shared cast that owns the globals. Measured:
that pattern ships 3,226 of 3,228 files and the two it drops are the two the game
cannot start without.

Matching is case-insensitive, so `*.dir` matches `MASTER.CST`. Given the mixed-case
tree, that is a mercy rather than a detail.

## What it weighs

Measured over `games/piposh2/`:

| | Files | Raw | Deflated |
|---|---|---|---|
| `.aif` | 3,142 | 432.2 MB | ~279 MB |
| `.dir` | 61 | 87.3 MB | ~28 MB |
| `.cst` | 25 | 61.6 MB | ~25 MB |
| **Total** | **3,228** | **581.2 MB** | **~332 MB** |

Transcoding the audio to Ogg Vorbis at 32 kbps takes 432 MB to ~77 MB, and the
whole payload to roughly **226 MB**. That is the difference between fitting and
fitting comfortably.

## Store limits

**Google Play.** The base module cap is **500 MB download**, not the 200 MB that
gets quoted — 200 MB is the threshold above which users on mobile data see a
non-blocking warning. Install-time asset packs raise the cumulative ceiling to
4 GB, on-demand to 30 GB. Legacy standalone APKs are capped at 100 MB, and
`export_presets.cfg` currently targets APK: **Play needs AAB.** APK expansion
(OBB) is not an escape hatch — it was removed in Godot 4.7 and app bundles never
supported it.

Godot's Play Asset Delivery support is minimal: an AAB export wraps assets in a
single *install-time* pack, and there is no engine API for on-demand or
fast-follow packs. Dynamic packs would need a custom Android plugin.

**Apple.** 4 GB uncompressed, 80 MB executable. 581 MB is legal untouched. The
200 MB cellular figure is a user-configurable prompt, not a cap. On-Demand
Resources is deprecated as of iOS 27 and Godot has no binding for it anyway —
which makes iOS the *easier* platform here: bundle everything and stop thinking
about it.

**Downloading data post-install is permitted** on both stores — Apple 2.5.2 and
Play's Device and Network Abuse policy both scope their bans to executable code,
not assets — but both require disclosing the size and prompting first, and Play
names silent CDN downloads as a violation. Note also that hosting the data makes
you its distributor, which is a different legal posture from shipping a copy the
player already owns. That is a decision to take deliberately, not a technique to
reach for because it is convenient.

## Android compresses what this reader seeks through

Godot's Android export does not put a `.pck` in the APK. It writes loose files
under `assets/` and deflates anything not on a hard-coded no-compress list.
`.dir`, `.cst` and `.aif` are all absent from that list; `.pck`, `.wav` and
`.ogg` are on it.

That matters because of how the container reader works. `director_file.gd` seeks
once per memory-map entry while indexing and again per chunk read, and the corpus
holds 90,385 entries across 86 containers — 3,158 in `strtgame.dir` alone, before
a single chunk is read. Godot opens Android assets with `AASSET_MODE_STREAMING`,
where a deflated entry is backed by a streaming inflater and a backward seek
plausibly re-inflates from the start of the entry.

**The mitigation sidesteps the question: pack the containers into one `.pck`.**
`.pck` is on the no-compress list, so it is stored rather than deflated, and
`FileAccessPack::seek` is a pass-through offset add. Load it with
`ProjectSettings.load_resource_pack()` from an autoload. Measured on desktop:
20,000 random seek+reads through a mounted pack, 78.4 ms total, no per-read
decompression — PCK has no compression flag in its format at all.

Two things to avoid: `encrypt_pck`, which wraps entries in `FileAccessEncrypted`
and buffers the whole file in memory; and `.zip` packs, whose `seek` rewinds and
re-inflates on backward seek, which is precisely this access pattern's worst case.

The cost is download size — stored containers are ~149 MB against ~53 MB
deflated. Against a 500 MB ceiling that is affordable, and it buys the seek
behaviour the reader depends on.

## Audio: Godot cannot load AIFF

Not at import, not at runtime. `ResourceImporterWAV` recognises `wav` only, and
`AudioStreamWAV.load_from_buffer` requires WAV data. AIFF support is an open
proposal with an unmerged PR; do not plan around it.

This game's AIFF files are unusually tractable, though — surveyed across all
3,142:

- every one is plain `AIFF`, not AIFF-C, with an 18-byte `COMM` — so uncompressed
  PCM only, no codec field
- 3,140 mono, 3,099 of them 8-bit
- 5.34 hours total
- one genuinely empty file, `SOUNDS/S_NIGHT3/HEZ61.AIF`, 0 bytes in the original

None of the usual AIFF horrors apply: no `sowt`, no float, no 24-bit. A decoder
needs a big-endian IFF walk with even-byte padding, the 80-bit extended sample
rate, and `SSND`'s 8-byte header. And there is a lucky alignment — **8-bit AIFF
samples are signed, and so is `AudioStreamWAV.FORMAT_8_BITS`** — so for 3,099 of
3,142 files the bytes transfer verbatim. Only the 41 16-bit files need a swap.

Two routes:

1. **Transcode to Ogg ahead of time.** 432 MB → ~77 MB at 32 kbps, and `.ogg` is
   on the Android no-compress list. The source is 8-bit 22 kHz, so 32 kbps is not
   the quality bottleneck.
2. **Decode AIFF in GDScript**, ~60 lines closely parallel to the existing
   `_load_wav_runtime`. Keeps the tree byte-original, costs 432 MB of payload and
   leaves the deflate problem in place.

Either way **no call site changes**: `AudioDirector.resolve_path` matches on stem
and discards the extension, which is why `play_file(1, "pi%s.aif" % item)` already
resolves to a `.wav` today. Only the index roots, the accepted-extension list and
one loader branch move.

Noted in passing: `autoload/audio_director.gd` sets `FORMAT_8_BITS` and assigns
raw WAV bytes without the unsigned→signed conversion 8-bit WAV needs. Latent —
nothing currently ships an 8-bit WAV — and exactly the conversion AIFF does not
require.

## Input: what a finger can and cannot do

Packaging decides whether a build *ships*. This decides whether it is *playable*,
and the two failure modes look nothing alike: a packaging mistake is a game that
will not start, an input mistake is a game that starts, draws correctly, and does
not respond where you touch it.

**How any of this could be checked without a phone.** Touch-to-mouse emulation is
not Android code. `input_devices/pointing/emulate_mouse_from_touch` is honoured
inside `Input` itself, on every platform, so an `InputEventScreenTouch` fed
through `Input.parse_input_event()` on Windows takes the same path it would take
on a device — synthesised into an `InputEventMouseButton`, queued, routed through
the viewport, delivered to `_input`. `tools/touch_input.gd` does exactly that,
windowed, and asserts what comes out the far end. That makes the section below
measurement rather than reasoning, with one named exception marked at the end.

The setting is **not** in `project.godot`. It is on by default in Godot 4, which
is why touch reaches the engine at all — and why the harness asserts it rather
than assuming it, since an unrelated edit to that file could switch it off with
nobody connecting the two.

**The harness runs headless now**, so it is in the gate rather than being a thing
somebody has to remember to run windowed. It used to bail out on
`DisplayServer.get_name() == "headless"` and so contributed one check —
"`emulate_mouse_from_touch` is enabled" — for as long as it sat in `gate.sh`'s
list. The touch point is mapped through the same three transforms either way, and
the run refuses to start if that composition has collapsed to an identity, which
is the only way a headless run could pass the coordinate checks vacuously. Run it
windowed as well when the pointer arbitration is what is in question: windowed
there is a real OS cursor to be wrong about, and section 3 is measuring rather
than pretending.

### What works

- **Coordinate mapping.** The stage is a fixed 640x480 letterboxed into the
  window by `_fit_to_window`, and a touch arrives in window pixels. Verified: a
  touch at a known stage point comes out of `the mouseH`/`the mouseV` at that
  point, within a pixel, and `the clickOn` names the sprite that was touched.
- **Tap = click.** Touch-down sends `mouseDown`, lift sends `mouseUp`, and the
  lift alone sends `mouseUp` — the press/release split holds for a finger.
- **`the mouseDown` / `the stillDown` / `the mouseUp`.** These are the one
  Director property answered from live hardware rather than from engine state,
  polled out of an `exitFrame` loop between events, and Godot's emulation does
  update the mouse button mask for a finger. So the click-to-skip idiom — 46
  scripts install `fromnow`, and `if the mouseDown then go ...` appears in both
  titles — works on touch. Verified: `the mouseDown` reads 1 while a finger is
  on the glass and 0 after it lifts.
- **Drag.** A finger drag is press, `InputEventScreenDrag` → motion, release. The
  moveable sprite follows the finger and the drop still delivers the `mouseUp` it
  is decided in. This is the corpus's whole inventory idiom, working on touch.
- **Multi-touch is safely ignored.** Exactly one finger is emulated — whichever
  went down while none was tracked. A second finger sends nothing, and lifting
  the first still completes its own click. No stray press without a release.
  The other order too: lift the *tracked* finger while a second is still on the
  glass and Godot stops tracking, so that second finger's drags and its eventual
  lift produce nothing at all and leave no press latched. Either leak would show
  up as a press with no release, or a second `mouseUp` for a click that already
  finished, and both latch into the next gesture rather than into the one that
  caused them.
- **The SKIP control** is a drawn rectangle tested before the hit test, so it is
  reachable by tap like anything else.

### What had to change to get there

Five faults, all found by the touch harness and all but one of which were also
wrong on desktop:

1. **`stage_mouse()` read the OS cursor.** `get_local_mouse_position()` ends in
   `Viewport.get_mouse_position()`, which on the *root* viewport does not answer
   from input at all — it falls through to `DisplayServer.mouse_get_position()`.
   Touch emulation synthesises the events and leaves that pointer alone. So every
   Director coordinate — `the mouseH`, `the mouseV`, the hit test, `rollOver`,
   the drag — read a cursor that does not exist. The message fired and every
   number in it was wrong, which on a phone reads as a broken hit test rather
   than a missing pointer. `_input` now routes the event's own position, and
   `stage_mouse` falls back to the last event.
2. **...and which of the two was authoritative was decided once, from the
   platform.** `_pointer_from_events` was `not has_feature(FEATURE_MOUSE)`,
   latched at load. That is right on a phone with no mouse and on a desktop with
   no touchscreen and **wrong on every machine that has both** — Windows laptops
   with touchscreens, Chromebooks, Android with a mouse attached or in DeX, an
   iPad with a trackpad. All of them report `FEATURE_MOUSE`, so the flag read
   false and fault 1 was alive on them untouched. Measured on a Windows box: a
   touch at stage (238,240) came out of `the mouseH`/`the mouseV` as (608,19) —
   wherever the cursor had been parked — and `the clickOn` as 0. It is a fact
   about the **last event** now: Godot stamps `DEVICE_ID_EMULATION` on the mouse
   events it synthesises from a finger, so `_input` reads the answer off the
   event. A player who plugs a mouse into a tablet mid-session gets the cursor
   back on its first motion and the finger back on the next tap, which no
   boot-time test can express at all.
3. **`InputRouter.mouse_button` called `route_click` on the press** — press *and*
   release back to back — so the split that made drag-and-drop work never applied
   to a real mouse at all. Every harness drove `route_press`/`route_release`
   directly, which is right for asserting the routing and is why nothing caught
   it; the touch harness goes in through `_input` and found it immediately. This
   was a live bug on desktop too: it is the inventory drop, still broken.
4. **The rollover was recomputed only on pointer motion.** §6.3 step 10 puts it
   in the frame update. On touch there is no motion between taps, so `the
   rollOver` would have named whatever was under the previous gesture for ever.
5. **...and a *press* did not re-aim it either**, which the frame tick hides
   everywhere except in the handler the press itself runs. The reference
   recomputes the hovered channel from the event's own position at the top of
   `processSysEvent`, before the switch that separates a move from a press
   (§4.5). A mouse cannot reach a button without a motion carrying it there, so
   on desktop this changes nothing; a finger sends no motion, so a tap dispatched
   `mouseDown` with the previous gesture's rollover latched and `the mouseH` and
   `the rollOver` described two different places inside one handler. Measured on
   `SAVELOAD.dir` frame 5: a mouse arriving over channel 5 pressed with `the
   rollOver` = 5, a finger tapping the same point pressed with 4 — the channel it
   had last touched. `preview/input_router.gd:aim_pointer` is the shared half of
   `mouse_motion` that both now call.

### Hover has no touch equivalent — and this game's menu is built on it

There is no hover state on a touchscreen. Nothing generates pointer motion unless
a finger is already down, so `rollOver`, `mouseEnter`, `mouseLeave`,
`mouseWithin` and the whole cursor-arbitration path have no input to run on
between taps.

The engine now recomputes the rollover every tick from the last known pointer,
which is the best that can be done and is what Director does anyway — so the
result is not that rollover is *absent* but that it is **sticky**. It names the
last place a finger touched, indefinitely. Verified: ten ticks with the glass
untouched move neither the pointer nor the rollover channel, and only another
touch moves either.

For a `rollOver` menu that means **every highlight is preceded by the click it
was meant to preview.** 94 sites across the corpus call `rollOver(n)`, in 28
scripts, and this title's menu is one of them: a frame script asks `rollOver(4)`
every tick and swaps the button art. On a phone the art swaps *after* you have
already committed to the button.

Whether that is fatal depends on what each menu does on `mouseUp`, and it is not
a question the engine can answer — it is a design decision about the port. Three
options, none of them free:

- **Do nothing.** Buttons still work; they just do not light up first. Playable
  wherever `rollOver` is decoration. Wrong wherever a script uses `rollOver` as
  the *only* way to reveal what a hotspot is.
- **Tap-to-focus.** First tap moves the pointer and runs the rollover; a second
  tap on the same target sends the click. Costs every menu a second tap and needs
  a rule for when focus is dropped. This is the conventional answer and it is a
  change to the engine's click model, which is exactly the thing that has been
  hard to get right twice already.
- **Hover-on-hold.** Touch-and-hold moves the pointer without clicking; the click
  goes out on lift only if the finger has not moved. Preserves single-tap
  actions, discoverable by nobody.

**This needs a decision before it is built.** Recorded here rather than chosen.

### Custom cursors cannot appear

`Input.set_custom_mouse_cursor` is a no-op on Android and iOS — there is no
cursor for it to set. `scenes/preview/cursor.gd` is a large and recently repaired
subsystem, and none of it will be visible on a phone: not the hand over a
hotspot, not the wait cursor, not the hidden-cursor case, not `the cursor` set
from Lingo.

Two consequences worth separating. The **visible** one is that a title using
cursor shape as its only affordance — this one uses the hand cursor to say "this
is clickable" — loses that affordance entirely, and a player has to guess or
tap around. The **invisible** one is cost: `_resolve_cursor` still runs on every
motion, every button-up and every frame, still builds and scales cursor images,
and throws all of it away. That is wasted work on the platform least able to
afford it, and short-circuiting the whole path where the DisplayServer has no
cursor is a small, safe change — but `cursor.gd` is not this session's file, so
it is recorded rather than done.

### The keyboard is unreachable

Every preview binding is an F-key (`[debug]` in `director_game.cfg`: boxes, hit
test, report, restart, step, fullscreen, quit, pause, snapshot, containers).
None of them can be pressed on a phone, and the F12 container picker also filters
by typed letters, so it is doubly unreachable.

Not a blocker — they are debug affordances, not gameplay. But note that the
*game* wants the keyboard too: 46 scripts install `fromnow`, which skips a line
of speech on key code 49 (space). On touch there is no way to skip speech at all.
If any of this is wanted on a device it needs an on-screen control or a gesture,
and `Input.show_virtual_keyboard()` is not the answer for a single key.

### The rest of the mouse, on touch

- **Right button.** `rightMouseDown`/`rightMouseUp` are dispatched now, and no
  touch gesture produces them. No script in either corpus declares one, so
  nothing is lost; a long-press mapping would be invention, not porting.
- **`the doubleClick`** is computed from the interval between presses rather than
  taken from `InputEventMouseButton.double_click`, which means it works for a
  double *tap* without special-casing touch.
- **`mouseUpOutSide`** works the same way for a finger: press, slide off, lift,
  and no `mouseUp` goes out. That is the standard way to cancel a mis-aimed
  press, and it matters more on a touchscreen than on a mouse.
- **Touch cancellation** (a system gesture stealing the finger — back swipe,
  notification shade) arrives as a release. **Measured now, not reasoned**: an
  `InputEventScreenTouch` with `canceled` set is emulated into an ordinary mouse
  *release*, so the engine ends the drag, clears the press and dispatches
  `mouseUp` exactly as it would for a lift. The item is dropped wherever it was
  and the click the player abandoned is delivered.
  **Left as it stands, and that is a decision rather than an oversight.** A
  finger produces something a mouse cannot, so there is no parity answer and no
  Director behaviour to match. The alternative is to route a cancel to
  `mouseUpOutSide` — the message the engine already has for a press the player
  backed out of — which is the honest reading of a system gesture stealing the
  finger and would stop a back swipe committing a game action. It is a design
  decision about the port, of the same kind as the `rollOver` menu question
  below, and it is recorded here rather than taken. `tools/touch_input.gd` pins
  the behaviour as it is, so changing it has to be deliberate.
  What is still not verified on a device: whether Android delivers the cancel to
  Godot at all when the OS takes the gesture, or simply stops sending events.

## Before shipping

- [ ] **A decision on `rollOver` menus.** See "Hover has no touch equivalent" —
      this is the one item on this list that is not an engineering task.
- [ ] **A decision on what a cancelled touch means.** Today it is an ordinary
      lift, so a back swipe commits the click it interrupted. Routing it to
      `mouseUpOutSide` instead is a one-branch change and uses a message Director
      already has; it is listed here because it is a design decision and not a
      bug. See "The rest of the mouse, on touch".
- [ ] `include_filter="games/*"` in `export_presets.cfg`
- [ ] `export_format` switched to AAB for Play
- [ ] Audio transcoded, or the AIFF loader landed
- [ ] Containers packed into a stored `.pck`, if the device test says deflate hurts
- [ ] **A CI assertion that the exported pack contains `strtgame.dir` and
      `MASTER.CST`.** The `**/*` result above is how quietly this breaks, and an
      export that silently drops the boot movie looks like a code bug for as long
      as it takes to think of checking the pack.

## Not verified

Stated as inference, and worth a device test before anything depends on it:

- **AOSP re-inflating on backward seek.** Reasoned from `AASSET_MODE_STREAMING`,
  not read from AOSP source or profiled on hardware. It is the argument for the
  `.pck` route and the weakest link in it.
- Whether AGP/AAPT2 compresses assets the same way on the Gradle path, which an
  AAB export requires. Check with `unzip -v` on the output.
- Whether assets inside an install-time asset pack are stored compressed.
- Google's own pages disagree on base-module size — 500 MB in the Console table,
  4 GB in the AAB guide. 500 MB is treated here as the enforced gate.
- Godot's lack of iOS ODR support is "no evidence found", not proven absent.
- `DirAccess` enumerating a runtime-loaded pack works on desktop 4.7.1 and
  contradicts the official documentation, which says it does not. Both
  `director_paths.gd` and `audio_director.gd` scan directories, so confirm on a
  device before relying on it.
- The 78.4 ms seek benchmark is desktop with the OS page cache, not Android
  storage.
- **Everything in "Input" was measured through the real code path, on a desktop.**
  `tools/touch_input.gd` injects genuine `InputEventScreenTouch` events and the
  emulation, routing, transforms and dispatch below them are the same objects a
  device would run — but the touch *driver* is not, and neither is the screen.
  The harness no longer fakes `_pointer_from_events`: the engine derives it per
  event now and the harness asserts that it did. What it does set is
  `_has_os_cursor`, which is a fact about the *machine* — true on a Windows box
  already, so windowed nothing there is pretended; headless it is set so that the
  arm every touchscreen-and-mouse platform takes is the one measured, instead of
  the phone arm being measured twice.
- **Whether Android reports `FEATURE_MOUSE`.** It no longer decides anything on
  its own — the event's device id does — but it is still the initial value of the
  flag, i.e. what the engine believes before the first event arrives. Not read
  from Godot's platform source and not checked on a device.
- **That a real mouse never carries `DEVICE_ID_EMULATION`.** The engine's pointer
  arbitration rests on it. Measured on Windows for events Godot synthesises from
  a finger (-1), for a freshly constructed `InputEventMouseButton` (32, not 0,
  which is why the harness asserts "not -1" rather than a number) and for the
  genuine OS motion a `warp_mouse` produces. Not measured on Android or iOS.
- `Input.set_custom_mouse_cursor` being a no-op on Android and iOS is read from
  Godot's own documentation, not from the platform source and not from a device.
  It is very unlikely to be wrong and it has not been proved here.
- Whether a touch cancelled by a system gesture arrives as a plain release, or as
  something the engine should distinguish. Reasoned from `InputEventScreenTouch`
  carrying a `canceled` flag that mouse emulation does not forward.
- Nothing here says anything about how big a target feels under a fingertip. The
  stage is 640x480 and this game's hotspots were drawn for a 1997 mouse; several
  are a few pixels across. That needs hardware and a hand.
