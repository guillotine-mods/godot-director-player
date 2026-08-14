# Working on this port

Godot 4.7 general Macromedia Director engine, reading original `.dir`/`.cst`
containers at runtime. It is title-agnostic: `director_game.cfg` names a folder
under `games/` and a boot movie, and the same engine runs whichever is pointed at.
The decompiled Lingo of the title it was built on is in `reference/lingo/`, and it
is the reference for every behavioural question.

`docs/ENGINE.md` and `docs/PROJECT.md` describe the **retired** renderer and have
not been rewritten — read their headers before believing a word of either. For
how the engine works now, read `scenes/preview/README.md` and the two reference
documents. Then `bugs.md` for what is known broken,
`docs/bugs-closed.md` for what was fixed and what was ruled out along the way, and
`README.md` for the verification tools. A source comment citing `bugs.md <n>` may
mean either file: resolved entries keep their number and move to the second. The skills in `.claude/skills/` carry
what the port cost to learn; the one-line descriptions in `README.md` say when each
applies.

**Start at [`scenes/preview/README.md`](scenes/preview/README.md).** The player is
a node plus nineteen modules, and that file has a symptom-to-file table — which
one your bug is in — plus the two conventions the split relies on. Most
importantly: `tools/` reaches into the preview *by name*, and a field moved off
the node makes a harness read null and report zero rather than fail. Run
`tools/preview_surface.gd` before and after anything you move.

## Standing rules

**Fix the engine, not the symptom.** The goal is an accurate Director engine, not a
game that happens to behave. A fix that special-cases one room, one channel or one
member is almost always the general mechanism written once per instance, and the
giveaway is the port growing another renderer exception. The channel 30, channel 100
and inventory-slot special cases all existed because there was no general sprite
path; one correct sprite channel replaced all of them. (That was the retired
renderer's `SpriteChannel`; the lesson carried over to `scenes/preview/`, the
class did not.)

**The engine decides from the scripts, not from hardcoded values.** The original's
logic is in `reference/lingo/`, and the interpreter can run it. Before writing a
table or a native handler, check whether a script already answers the question:
`BehaviorScript 207` knows its own destination from `nextroomdata`, so the
hand-authored transition table it was being asked instead is now only a fallback.
That scaffolding — `data/movie_context.json`, `data/walk_doorways.json` and the
rest of `data/` — has since been deleted outright along with the renderer that
read it, which is the retirement plan carried out. Where a native
reimplementation is unavoidable, drive it
from the original's own globals rather than inventing parallel state.

**The engine is agnostic to the game.** No room name, character, channel number or
per-title mapping belongs in engine code. If a fix needs to know that `field` is
slot 1 or that channels 18-21 hold guests, the fix is in the wrong place — that
knowledge is in the movie's own scripts, and the engine's job is to run them.
A native handler that reproduces half a Lingo handler is the shape to watch for:
`GameState.people_funk` reimplemented `peoplefunk`'s meeting routing and silently
dropped its character placement, which put every wandering guest on screen twice
(bugs.md 21) and left nothing in the code to say a half was missing.

**Build Director, not this game.** The target is a general Director engine --
Piposh 1 and *Rating* are meant to run on it -- so a feature is implemented
because Director has it, not because this corpus exercises it. "0 uses in
`reference/lingo/`, so I did not build it" is not diligence, it is a hole that
surfaces the first time another title is loaded, by which point nobody remembers
the decision was made.

Measurement is for **prioritisation and verification, never for scope.** Survey
the corpus to decide what to build *first*, and to prove an implementation right
against real data -- both are worth doing and this port has been repeatedly saved
by them. Then build the rest anyway. Where the corpus cannot exercise something,
implement it from the reference and say in the comment that it is unverified;
that is an honest state, and it is not the same as absent. The calls already made
the wrong way, and worth revisiting: score sound channels,
`beginSprite`/`endSprite`/`stepFrame`/`timeout`, sprite trails. The transition
wipe algorithms were on that list and came off it on 2026-08-14; how they read
before they did is the worked example below.

This is the counterweight to the rule above it, not a contradiction of it. The
engine stays ignorant of *this game's* rooms and channels; it does not stay
ignorant of Director's features.

**A "measured zero" in this repository is usually a measurement of Piposh 2.**
This is the specific way the rule above has been broken, over and over, and it is
worth knowing as a fact about the files rather than as a principle. Piposh 2 is
the corpus the port was built on and the one `director_game.cfg` points at, so a
survey run without arguments measures it and nothing else. Several such numbers
were then written into comments, into `AGENTS.md` and into `docs/` as statements
about *the corpus* or *the engine*, and the sentence gives no sign of which it
is. Three found in one day:

- "no cast in this game holds a sound member, so all of it is proved against
  synthesised bytes only" -- in three files, in those words. Piposh 2 has none;
  the corpus has **204**, and neither of the two defects between them and the
  speaker had ever run.
- "thirteen transition algorithms would be thirteen pieces of dead code for this
  title, and four seconds of held playhead is the whole of what is missing" --
  measured at 2 types over 5 frames. The corpus plays **12 types over 125 frames
  and 140 seconds**, and `rating`, never swept, is more than the other five
  titles together.
- "the score's own sound channels are empty in all 61 movies" -- carried in
  `preview_lingo_host.gd`. This one is the adjacent failure rather than the same
  one, and it is worth seeing beside them: 61 is Piposh 2's movie count, so it
  reads as measured, and the score decoder did not read those bytes at all at the
  time. A number that names a scope is not evidence that anything counted it.

So: **a number is about the roots it was run over, and the sentence must say
which those were.** `tools/member_type_census.gd` walks every root under `games/`
and `test-games/` in one pass and is the cheapest way to find out whether a "this
corpus has none" is true; most surveys take `--root <name>` and many take `--all`.
If you are about to write "this corpus does not ..." into a comment, either run it
over all eight roots or write down the one you ran.

**The reference documents are the specification.** `docs/DIRECTOR_ENGINE.md` is
everything the engine does without a script; `docs/LINGO_SURFACE.md` is the
language surface. Between them they are what *finished* means, and
`docs/ENGINE_TODO.md` is the running list of what is still missing against them.
Read the section before building the thing it describes, and close its entry when
the thing lands -- a stale gap list is worse than no list, because it is trusted.
It claimed flip was "decoded and never applied" long after `sprite_art.gd` was
applying it *and* mirroring the hit test with it, and claimed no member in this
corpus draws a rounded rectangle when two do. Either reading sends the next
session to build what is already there, or to skip what is not.

Done is what the document describes, not what this game stops complaining about.
A room that renders correctly proves the paths that room exercises and nothing
else, so "the symptom is gone" closes a bug and never closes a feature. The
engine is complete when the reference has no unimplemented section left; until
then `ENGINE_TODO.md` is the honest statement of the distance, and keeping it
honest is part of the work rather than bookkeeping after it.

**"Not a bug" needs more evidence than a bug does**, because it is the verdict
that stops work. A decode is the port's *input*, not the original: the renderer
agreeing with the data it was handed proves the renderer, never fidelity, so "the
data says X, therefore X is authentic" is circular. Before ruling anything
authentic, get a source from outside the pipeline — member *names* are the
cheapest one and still the most underused, now read from the container itself
rather than from the deleted `data/lingo/member_names.json`. The
duplicated-guest report above was dismissed as authentic crowd art on
three passing consistency checks; one name lookup (`atoflop1` / `btoflop1`) said
the opposite and had been available from the first minute. Read
`porting-fidelity-verification` for the full account.

## Environment

- **There is no test suite.** `gate.sh`'s `ALL` list is the authoritative set of
  harnesses that run and are expected to pass, and **`gate.sh` exits 1 when any
  of them does not** — TIMEOUT, EMPTY and ERROR count as failures alongside FAIL,
  because a run that hung, asserted nothing, or died before it could report has
  not passed. Measured by whole-suite runs on 4.7.1 on macOS: **every entry in
  `ALL` passes.** The suite is green, and that is new — it is worth
  keeping that way, because a suite with a standing red teaches everyone to read
  past reds.
  **The count is deliberately not written here**, which is the rule the paragraph
  below states and this line used to break: it said "all 78 entries pass" while
  `ALL` held 88, a drift of ten that nobody noticed because a sentence carrying a
  number reads as measured whether or not anybody re-measured it. The set is
  uniform, so the count adds nothing the sentence above does not. If you want it:
  `sed -n 's/^ALL="\(.*\)"$/\1/p' gate.sh | wc -w`, anchored at the line start
  because the obvious `grep -o` form matches its own occurrence in a comment. `.github/workflows/nightly.yml` runs it on macOS and Windows every
  night, so a red is now something that arrives rather than something somebody
  has to go looking for.
  - `lingo_surface_audit` was red and is fixed. It failed for one reason and it
    was documentation, not code: `4b2e9371` bound `the mouseLoc` and never added
    it to §19's claim table, and this harness's rule is that every name the
    engine binds is recorded there. Fixed by adding the row. If it goes red
    again, read which of its 11 checks failed before assuming the engine moved.
  - `palette_members` was the other red and **is no longer in `ALL`**, on the
    grounds that its subject is not this project: the only corpus whose bitmaps
    name palette *members* is `test-games/itamar-park`, which is not a submodule,
    not tracked, ignored at `.gitignore:73`, and never shipped with the six
    titles this engine is for. An entry that can only pass against a corpus
    outside the project gates nothing here.
    `tools/palette_corpus.gd` replaced it and is in `ALL`: 14 checks over all six
    roots, 651 containers and 118,991 bitmaps, versus 9 over one title nobody
    has. The one thing only `palette_members` asserts is that a bitmap's own
    named palette reaches the decoder and changes the pixels, which no shipped
    title can express; run it by hand against `piposh-ru` (7 of 9) for that.
  - **Four `test-games/itamar-magichat` entries are gone from `ALL` for exactly that
    reason**, and the rule is worth stating as a rule now that it has caught two
    groups: `go_movie_arg`, `video_fallback` and `avi_decode`'s fixture entries, and
    `video_plugin`, which is bare now because its own five checks are
    corpus-independent. `test-games/` is ignored at `.gitignore:73`, **no file under
    it has ever been committed on any branch**, and it is not a submodule — so a
    clean checkout, a fresh worktree and both nightly runners have no such
    directory, and what those entries did there was
    `no such container: magichat.dir` reported as a failed assertion. Measured: 2
    reds in a 92-entry run, neither about the engine.
    The honest cost is recorded in `gate.sh` beside the entries rather than smoothed
    over: **the video decode path now has no gate on it at all.** Every video member
    in all eight corpora is that corpus's, so MS-RLE pixels, backward seek and the
    frozen-`movieTime` hang are unguarded until the project owns a fixture of its
    own. That is a hole, not a decision, and it is the argument for committing a few
    frames of video under `games/` rather than for putting the entries back.
    The pattern that stayed green throughout is the one to copy when a harness needs
    a corpus it may not have: `video_fallback` bare and `sprite_lifetime`'s fourth
    case both say out loud that they found nothing and assert nothing.
- **A harness must assert what this port controls, not what a 1990s cast got
  right.** `palette_corpus`'s first version failed, correctly-looking, on
  `piposh-dream`'s 167 bitmaps naming member 154, which is a type-2 member. That
  is bad authoring in a shipped title: the container states file version `0x57E`,
  so the D5 layout the reader uses is right, and the reference resolves the same
  pair to the same non-palette. What the engine does with that is the port's to
  get right, and it is what the check asserts now. Asserting the data instead
  would have gated this project on files it cannot fix.
  **The first version of that check then passed while the engine had it wrong**,
  which is the more useful half of the story: it handed system Mac in as the
  stage, so "fall back to the stage" and "fall back to system Mac" returned the
  same bytes and the check agreed with itself. The reference falls back to system
  Mac (`castmember/bitmap.cpp:484`) and the engine fell back to the stage, which
  drew 81 of those 167 members — Piposh's own face among them — in the Windows D5
  table on the six `piposh-dream` movies that declare it. `bugs.md` 104. A check
  whose two readings cannot disagree on the data it is given is the shape to
  watch for; this one now passes each movie its own declared default.
  Both of the two that this line used to name as standing failures now pass,
  and neither was fixed by
  changing what they assert: `debug_bindings` was config rather than code and the
  config moved, and `play_suspends` *was* the fixed-frame-count flake of
  `bugs.md` 41 until `b8466abb` — which replaced its six-frame budget with a wait
  on the condition under a 600-frame ceiling and tightened the assertion in the
  same commit. **A green `play_suspends` is a result, not one sample**, and this
  line said the opposite for long enough that three separate sessions treated a
  closed entry as open.
  Before that this said 62 entries / 60 pass, and earlier 23 pass / 1 fail, and
  later 40 pass / 1 fail naming a `boot_state` that passes now — none of which
  summed to the list, for as long as nobody ran the whole thing and counted. The
  count is deliberately not written here: it changed twice in the day this line
  was last corrected, and a number nobody re-measures is what sent the previous
  three readers looking for a failure that was not there. Run it and count.
  `README.md` lists more tools than that; the ones outside `ALL` are surveys and
  one-offs, and are the ones that rot, because nothing runs them. Everything that
  is not pass/fail prints a number that is not higher-is-better, which is why
  `porting-fidelity-verification` exists.
- **Open the Godot editor once on a fresh checkout or worktree** before running
  anything headless. `.godot/` is gitignored and `global_script_class_cache.cfg`
  inside it is what makes `class_name` scripts resolvable; without it a headless
  script fails with `Could not find type "DirectorContainer"` in a file nobody
  touched. Seeding that one file from another checkout is enough.
- **The editor and headless runs contend over `.godot/`.** A headless sweep can hang
  indefinitely with an editor open on the same project. Close it, run, reopen.
- **Do not pipe a GUI launch through `tail` or `grep`.** Output buffers until the
  process exits, so a running editor looks like a failed one. Redirect to a file.
- **`git add -A` sweeps pre-existing untracked `.uid` files** into the commit. Stage
  paths deliberately.
- **A modified file is not evidence of authorship.** More than one session can
  share this checkout, and `git status` does not say who wrote a hunk. `edaeba49`
  bundled two sessions' work because one of them found `tools/preview_surface.gd`
  modified, recognised the subject as something it had asked an agent about, and
  committed it: a plausible inference, and wrong. So `git add -A` is unsafe
  whenever another session may be live, `git add <path>` is not sufficient either
  unless you wrote that path, and the cheap check is to ask before committing a
  file you did not write. Same hazard as the `.uid` line above, one step up: those
  only add noise, this misattributes work and makes a bisect point lie.
  Two more consequences, both paid for on 2026-08-14. `bugs.md` and
  `docs/bugs-closed.md` need a **single owner** while two sessions are live,
  because both append numbered entries and neither can see the other's draft. And
  **`.gate.lock` only excludes other `gate.sh` runs**: a plain `godot --headless`
  invocation is not covered, and concurrent ones contend over `.godot/` badly
  enough to hang rather than fail. The convention that worked is `mkdir
  .agent.lock` with a `trap ... EXIT` around every Godot call, removing only a
  lock you created. A `gate.sh` that waits its full 900s and exits **2** means the
  lock is held, not that anything hung, and a stale lock from a run whose trap did
  not fire blocks everyone for the whole 15 minutes.
- **`titles/piposh3d.pck` builds itself, and the first run after a fresh clone
  pays minutes for it.** The pack is gitignored — it is the `titles/piposh-3d`
  submodule's own bytes with the import saved ahead of time, not new data — so no
  clean checkout has one. Three places now build it rather than asking you to:
  `autoload/piposh3d_pack.gd` in `_init`, before the four autoloads whose scripts
  live *inside* the pack are instantiated, so the run that builds it is also the
  run that has the 3D title; and `gate.sh`/`check.sh` through
  `gate_env.sh`'s `gate_require_pack`, so the wait lands once, up front, instead
  of inside whichever harness ran first. `bash build_pack.sh` is the same thing
  by hand.
  Without it the 3D title is missing from the launcher, and — the half that
  reaches everything else — those four autoloads print twelve engine `ERROR`
  lines before every harness, in a suite whose job is to say which entries are
  clean.
  **A submodule bump rebuilds it too.** `titles/piposh3d.pck.stamp` holds the
  commit the pack was built from, and a mismatch against what is checked out now
  rebuilds. Mtimes cannot answer that question — a checkout rewrites them and a
  pack newer than its sources is the normal case — but a commit hash is exact.
  The check answers "not stale" whenever it cannot tell (no `.git`, no `git` on
  PATH), because a wrong yes costs a rebuild on every run and a wrong no costs
  one stale pack. Uncommitted edits *inside* the submodule do not register: the
  commit has not moved, and somebody working on the 3D title does not want a
  four-minute rebuild per launch. They run `bash build_pack.sh` themselves.

## Fixing something

Reproduce it headlessly before theorising. Build the harness on `tools/lib/` —
`harness.gd` for pass/fail, `args.gd` for the command line — and boot the real
player the way every harness in `gate.sh` does, by instantiating the main scene
and awaiting a frame:

```gdscript
const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
root.add_child(preview)
await process_frame
```

`tools/hotspots.gd` is the shortest worked example. The scenario stays in the
tool; only the driving is shared, and `harness.gd` and `args.gd` may not know
which game this is.

**There is no general "where did the playhead go" probe right now.** There was —
`tools/probe.gd`, on `tools/lib/driver.gd` — and this section told you to reach
for it before writing anything throwaway. Both drove `DirectorRuntime`, the
retired renderer, and were deleted with it; the instruction outlived the tool by
long enough to be worth this paragraph. Rebuilding one on the preview is the
single most useful tool this repo is missing.

The nearest thing that does exist is `tools/liveness_sweep.gd`: it opens every
movie of a corpus, samples `(movie, frame, sprites drawn, what is holding)` once
per score tick off real awaited frames, and reports the ones that are stuck,
blank, cycling across a movie boundary or raising a Lingo error — with the holds
that legitimately explain a still playhead (`go to the frame`, a tempo wait,
`pause`, a `soundBusy` poll while a sound is playing) separated out, which is the
whole difficulty. `--only <movie> --verbose` is the closest to a probe on one
movie, and `--click` drives hotspots. It is still a sweep and not a probe: it
cannot be pointed at a marker, stepped, or stopped somewhere interesting.

Whatever you build, **await real frames.** A synthetic `for i in N: tick()` loop
advances the runtime's clock and not the audio server's, so every `soundBusy`
guard holds for ever and any scene with speech in it looks stuck (bugs.md 22,
diagnosed wrong twice). That rule cost two misdiagnoses and it did not retire
with the renderer that taught it.

Where an asset is involved, extract and look at it: converting one bitmap
and viewing it identified a mystery sprite in seconds after a long run of wrong
theories about coordinates.

Then find the root cause before changing anything, and follow the trace to the end.
A symptom filed as a bug is a bug not understood: "the hide does not stick" sat in
`bugs.md` as its own entry when it was one print away from being
`go_back` never re-scoping the interpreter, which was breaking every script in the
movie rather than one sprite.

Cover the fix with a pass/fail harness that asserts the player-visible invariant,
not that a setter and a getter agree. Attribute the change by measuring the same
thing before and after, stashing if necessary, and compare the walk differ row by
row rather than by total. Read `porting-fidelity-verification` before believing any
number, and do not copy numbers into prose: the stale figures in `docs/ENGINE.md`
sent a session chasing a regression that had never happened.

Anything found and not fixed goes in `bugs.md` with the evidence and a command that
reproduces it. Commit messages carry the root cause and the measurements, because
they are the only durable record of why the code looks the way it does.
