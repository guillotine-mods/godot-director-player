# ScummVM as an executable oracle: what actually works (task 1.4)

Answers the design's open question *"Does ScummVM's `piposh2` target actually reach
playable state, or is it detected but unstable? The detection entry proves intent,
not coverage."*

**Short answer: detected, and it runs — but only one movie, and under the wrong
Director version.** ScummVM 2026.3.0 (`brew install --cask scummvm`), against the
data at `~/Downloads/piposh2extracted/piposh2-data/`.

## What works

| | Result |
|---|---|
| Detection | **Works.** `--detect` reports `director:piposh2`, keyed on `PIPOSH2.EXE` + `PIP2DATA/AIR1.DXR`. Recovering the projector (task 1.2) is what made this possible. |
| Launching the target | **Plays the projector, not the game.** `PIPOSH2.EXE`'s own score is one frame; it reports `Finished playback of movie 'PIPOSH2.EXE'` and stops, having opened no movie under `PIP2DATA/` beyond hashing `AIR1.DXR` for detection. |
| `start_movie=strtgame.dxr` | **Works.** 19 frames, 167,400 channel records, 355,080 lines, clean exit under `fewframesonly`. |
| `start_movie=DAY1.DXR` | **Segmentation fault**, at `Starting playback`, after loading all 2784 frames and populating sprite casts for 120 channels. |
| `start_movie=DAGI.DXR` | **Segmentation fault**, same point, after `Number of frames: 331`. |

Both crashes come *after* the movie loads and *at* the transition into playback,
with the last dispatched event being `prepareMovie`. `strtgame.dxr` differs in
sitting at the data root and linking almost nothing; `DAY1` and `DAGI` live under
`PIP2DATA/` and link external `.CXT` casts. Pointing `path=` at `PIP2DATA/` instead
does not help — detection then fails and ScummVM sits at its launcher.

Not chased further. Diagnosing a crash inside ScummVM is upstream work, not this
change's, and the version defect below limits the payoff either way.

## The oracle runs this game as v850, and cannot be told otherwise

`ScummVM: Starting v850 Director game` — and `cast.cpp:630`:

```cpp
if (humanVer > _vm->getVersion()) {
    if (_vm->getVersion() > 0)
        warning("Movie is from later version v%d", humanVer);
    _vm->setVersion(humanVer);
}
```

The version is seeded from the detection entry (`director.cpp:61`,
`_version = getDescriptionVersion()`) and the correction path **only ever raises
it**. Every movie under `PIP2DATA/` is D7 (`0x57E`, see `director-version.md`), so
`700 > 850` is false and the 850 stands. There is no config key to lower it.

This is not cosmetic. It is visible in the trace as ScummVM misparsing this game's
own config chunk:

```
WARNING: STUB: Cast::loadConfig: 16 bit stageColor read instead of two 8 bit
         isStageColorRGB and stageColorR. Read value: 00ff!
WARNING: STUB: skipped using stageColorG, stageColorB for post-D7 movie in
         checksum calulation!
WARNING: BUILDBOT: The checksum for this VWCF resource is incorrect.
         Got 50141656, but expected 5d4003b6!
```

ScummVM is applying post-D7 config layout to a D7 movie and its own checksum
rejects the result.

## What this means for the change

The oracle is **not** the neutral referee Decision 1 assumes. Specifically:

- **Version-gated behaviour in any trace is D8.5's, not this game's.** That covers
  tempo encoding (the D6+ sentinels), the displayed-channel count, config-chunk
  layout, and anything else keyed on version. Do not diff those.
  Auto-puppeting survives, since it is gated on `>= 600` and both values pass.
- **Mechanism is still checkable**: message-hierarchy order, `pass` propagation,
  freeze/thaw around `go`, property get/set sequencing. These are the things the
  port most needs settled and they are not version-gated.
- **Task 4.8 is blocked.** It needs two movies that share handler names, diffed
  against the oracle. Both game movies tried segfault, and `strtgame.dxr` is the
  only one that plays.
- The 120-channel defect from `director-version.md` is confirmed live: the trace
  shows `Frame: 0 Channel: 120` as the ceiling, on movies that declare 150.

This strengthens rather than weakens Decision 2 (*the game's scripts outrank the
oracle*). It also means `data/declared_divergences.json` should not accumulate
version-gated entries — a difference caused by ScummVM running at 850 is a defect
in the comparison, not a divergence in the port.

## The diff tool exists; it has not yet produced a validated comparison (task 1.6)

`tools/oracle_diff.py` parses both traces, reads `data/declared_divergences.json`
and reports declared entries as expected, excludes version-gated fields for the
reason above, and treats the port's `"unavailable"` markers as known holes rather
than mismatches. Run end to end it works:

```
tools/capture_scummvm_trace.sh strtgame.dxr
PIPOSH2_TRACE=run.jsonl PIPOSH2_TRACE_KINDS=channel,dispatch \
    godot --headless --script tools/smoke.gd
python3 tools/oracle_diff.py .traces/scummvm-strtgame.log run.jsonl --movie strtgame
```

**It currently reports 414 undeclared differences, and that number means nothing
yet.** The blocker is alignment, not behaviour: the reference has 20 *rendered
frames* while the port trace has 600 *playback steps* for the same movie, and
those are different axes. Comparing them positionally lines up unrelated states.
Without `--movie` it is worse still — the port's trace spans a whole session, so
frame 0 of the oracle meets whatever the port was doing at step 0, usually a
different movie entirely. The tool now warns when that happens rather than
printing a confident wrong answer.

Aligning on Director frame number (both traces carry one) rather than on
sequence position is the next step, and it should come with a way to confirm the
alignment is real before any difference count is quoted. Until then this tool is
plumbing, not evidence — quoting its output as an agreement score would be exactly
the "check that cannot fail" mistake this change keeps finding elsewhere.

## Reproducing

```
tools/capture_scummvm_trace.sh strtgame.dxr        # works
tools/capture_scummvm_trace.sh DAY1.DXR            # segfaults, exits 2
```

Traces land in `.traces/` (git-ignored). The script uses a throwaway config so the
user's real `ScummVM Preferences` is never touched — `start_movie` persists, and
leaving it set would silently change what launching the game from the GUI does.

The per-frame channel dump comes from `debugC(9, kDebugLoading)` at
`score.cpp:2289`, **not** from the console `channels` command as task 1.5 assumed.
That is what makes capture scriptable at all; an interactive console would not be.

Headless is not available: `SDL_VIDEODRIVER=dummy` fails with *"Could not load any
graphics mode"* and `offscreen` fails the same way, while forcing
`--gfx-mode=surfacesdl --renderer=software` gets further and then dies on
*"SDL_BlitSurface failed: Parameter 'src' is invalid"*. A real window is required;
with frames bounded it opens, plays and closes on its own.
