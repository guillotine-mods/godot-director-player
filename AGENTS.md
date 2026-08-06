# Working on this port

Godot 4.7 port of Piposh 2, a Macromedia Director game. The decompiled original is
in `reference/lingo/`, its decoded score and art in `assets/render_model/`, and it is
the reference for every behavioural question.

Read `docs/ENGINE.md` for how the engine works, `bugs.md` for what is known broken,
`docs/bugs-closed.md` for what was fixed and what was ruled out along the way, and
`README.md` for the verification tools. A source comment citing `bugs.md <n>` may
mean either file: resolved entries keep their number and move to the second. The skills in `.claude/skills/` carry
what the port cost to learn; the one-line descriptions in `README.md` say when each
applies.

## Three standing rules

**Fix the engine, not the symptom.** The goal is an accurate Director engine, not a
game that happens to behave. A fix that special-cases one room, one channel or one
member is almost always the general mechanism written once per instance, and the
giveaway is the port growing another renderer exception. The channel 30, channel 100
and inventory-slot special cases all existed because there was no general sprite
path; one correct `SpriteChannel` replaced all of them.

**The engine decides from the scripts, not from hardcoded values.** The original's
logic is in `reference/lingo/`, and the interpreter can run it. Before writing a
table or a native handler, check whether a script already answers the question:
`BehaviorScript 207` knows its own destination from `nextroomdata`, so the
hand-authored transition table it was being asked instead is now only a fallback.
`data/movie_context.json` and `data/walk_doorways.json` are scaffolding with a
retirement plan, not data. Where a native reimplementation is unavoidable, drive it
from the original's own globals rather than inventing parallel state.

**The engine is agnostic to the game.** No room name, character, channel number or
per-title mapping belongs in engine code. If a fix needs to know that `field` is
slot 1 or that channels 18-21 hold guests, the fix is in the wrong place — that
knowledge is in the movie's own scripts, and the engine's job is to run them.
A native handler that reproduces half a Lingo handler is the shape to watch for:
`GameState.people_funk` reimplemented `peoplefunk`'s meeting routing and silently
dropped its character placement, which put every wandering guest on screen twice
(bugs.md 21) and left nothing in the code to say a half was missing.

**"Not a bug" needs more evidence than a bug does**, because it is the verdict
that stops work. The export is the port's *input*, not the original: the renderer
agreeing with `frames.json` or `cast_registry.json` proves the renderer, never
fidelity, so "the data says X, therefore X is authentic" is circular. Before
ruling anything authentic, get a source from outside the pipeline — start with
`data/lingo/member_names.json`, which is nearly free and the most underused file
here. The duplicated-guest report above was dismissed as authentic crowd art on
three passing consistency checks; one name lookup (`atoflop1` / `btoflop1`) said
the opposite and had been available from the first minute. Read
`porting-fidelity-verification` for the full account.

## Environment

- **There is no test suite.** `README.md` lists the tools; the pass/fail ones exit
  non-zero. Everything else prints a number that is not higher-is-better, which is
  why `porting-fidelity-verification` exists.
- **Open the Godot editor once on a fresh checkout or worktree** before running
  anything headless. `.godot/` is gitignored and `global_script_class_cache.cfg`
  inside it is what makes `class_name` scripts resolvable; without it a headless
  script fails with `Could not find type "RenderModelLoader"` in a file nobody
  touched. Seeding that one file from another checkout is enough.
- **The editor and headless runs contend over `.godot/`.** A headless sweep can hang
  indefinitely with an editor open on the same project. Close it, run, reopen.
- **Do not pipe a GUI launch through `tail` or `grep`.** Output buffers until the
  process exits, so a running editor looks like a failed one. Redirect to a file.
- **`git add -A` sweeps pre-existing untracked `.uid` files** into the commit. Stage
  paths deliberately.

## Fixing something

Reproduce it headlessly before theorising, and reach for
`tools/probe.gd -- --movie X --label Y --seconds N` before writing a throwaway
script: it boots anywhere, steps in real time and reports where the playhead went.
Where a harness is still the answer, build it on `tools/lib/` — `harness.gd` for
pass/fail, `driver.gd` for boot/step/click/trace, `args.gd` for the command line.
The scenario stays in the tool; only the driving is shared. Two rules there:
`harness.gd`, `driver.gd` and `args.gd` may not know which game this is, and
everything that does lives in `game_hooks.gd`, the one file rewritten when the lib
is carried to another Director port. And `driver.run_for` awaits real frames on
purpose — a synthetic `for i in N: tick()` loop advances the runtime's clock and
not the audio server's, so every `soundBusy` guard holds for ever and any scene
with speech in it looks stuck (bugs.md 22, diagnosed wrong twice). Where an asset is involved, extract and look at it: converting one bitmap
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
