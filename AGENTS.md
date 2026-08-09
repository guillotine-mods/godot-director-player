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
the wrong way, and worth revisiting: score sound channels, the transition wipe
algorithms, `beginSprite`/`endSprite`/`stepFrame`/`timeout`, sprite trails.

This is the counterweight to the rule above it, not a contradiction of it. The
engine stays ignorant of *this game's* rooms and channels; it does not stay
ignorant of Director's features.

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
  harnesses that run and are expected to pass — measured by a whole-suite run on
  4.7.1, 2026-08-10: **every entry passes, none fail.** Both of the two that this
  line used to name as standing failures now pass, and neither was fixed by
  changing what they assert: `debug_bindings` was config rather than code and the
  config moved, and `play_suspends` is the fixed-frame-count flake of `bugs.md` 41,
  which passing once does not close. Treat a green `play_suspends` as one sample.
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
