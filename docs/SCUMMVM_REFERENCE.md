# ScummVM as a reference for this port

ScummVM's `engines/director` is the closest thing to a specification for the
engine this port reimplements. It is read for the model and cited by function; no
code is copied, and it is GPL-2.0-or-later.

Fetch the ~35 relevant files with `tools/fetch_scummvm_reference.sh`. They land in
`reference/scummvm/`, which is git-ignored, **pinned at
`805f259a19d71eb12db1e3b0b9b24c27ee18e8b6`**. Cite as `<file>:<function>` — a bare
line number against `master` rots, and a previous review of this engine lost its
notes and had to be redone from scratch because of exactly that.

> **It is a source, not an authority.** Where ScummVM and this game's own scripts
> disagree, the scripts decide. And ScummVM is measurably wrong about this game in
> two respects — see "Where it is wrong" below and
> `openspec/changes/director-playback-machine/oracle-status.md`.

## Implicit (automatic) puppeting

This was the question `director/sprite_channel.gd` deferred (deleted with the
retired renderer); the live equivalent is `scenes/preview/sprite_state.gd`, which
has not been re-read against this section. Three separate mechanisms, and they are easy to conflate.

**1. Acquisition — writing a property claims it.** `Lingo::setTheSprite`
(`lingo/lingo-the.cpp:1826`) calls `sprite->setAutoPuppet(kAP<Property>, true)` on
the write path of *specific* properties, not all of them:

| auto-puppets | does **not** auto-puppet |
|---|---|
| `backColor`, `blend`, `foreColor`, `height`, `ink`, `locH`, `locV`, `moveableSprite`, `rect`, `thickness`, `width` | `visible`, `puppet`, `cursor`, `constraint`, `volume` |

`memberNum` / `castNum` / `castLibNum` are a trap: they are absent from
`setTheSprite`'s `setAutoPuppet` calls, so reading that function alone suggests a
member write does not claim the channel. It does — indirectly.
`Channel::setCast` (`channel.cpp:511`) calls `setAutoPuppet(kAPCast, true)`, and
`setTheSprite`'s member arms go through `setCast`.

**2. The gate.** `Sprite::setAutoPuppet` (`sprite.cpp:465`):

```cpp
if (_puppet || g_director->getVersion() < 600)
    return;
```

So it is D6-and-above only, and it is skipped entirely on a channel that
`puppetSprite` already owns explicitly — explicit ownership is strictly stronger
and there is nothing to add. **This game is Director 7** (every movie reports
config `0x57E`; see `openspec/changes/director-playback-machine/director-version.md`),
so auto-puppeting applies.

**3. Release — asymmetric, and this is the part that is easy to build backwards.**
`Sprite::releaseAutoPuppet(copyBackMask)` (`sprite.cpp:481`) clears a property's
claim only when the incoming score frame actually re-specifies *that field*:

| claim | released when the score re-specifies |
|---|---|
| `kAPInk` | ink |
| `kAPForeColor` / `kAPBackColor` | the matching colour |
| `kAPCast` | cast id |
| `kAPLoc` | start point |
| `kAPHeight` | cast id **or** height |
| `kAPWidth` | cast id **or** width |
| `kAPMoveable` | moveable |

Per property, not per channel. And because release runs off the score's
copy-back mask, **a parked playhead never releases anything** — which is exactly
what this game's hub rooms need, since they sit on one frame calling
`updateStage()` and animate by writing sprite properties.

Explicit `puppetSprite N, 0` is different again: it hands the channel back and the
score reclaims it on the next reconcile.

**What it would take here.** `SpriteChannel` (deleted) had one boolean `puppet`
covering the whole channel. Implementing this properly means a per-property claim
set, a reconcile that consults it field by field, and score data that records
which fields each frame re-specifies — the port's exported frames do not carry
that today, which is why per-field release cannot be built yet.

**Whether it matters yet.** Probably not, and `sprite_channel.gd` was right to say
so: every channel this game drives from Lingo is claimed explicitly by its hub's
`init all` (`puppetSprite(30, 1)`, and 103-110 for the inventory), and the gate
above makes auto-puppet a no-op on an explicitly puppeted channel. It becomes
load-bearing for a channel a script writes without puppeting first.

## Other mechanisms verified against the source

**`updateStage()` is a render flush, not a frame tick.** `LB::b_updateStage`
(`lingo/lingo-builtins.cpp`) composites channels, plays queued puppet sounds,
updates the cursor and draws. No frame advance, no script dispatch. That is what
lets a parked room animate from inside one `exitFrame` without re-entrancy.

**`go` freezes the interpreter.** `Lingo::func_goto` sets the next frame and a
freeze flag; `Lingo::execute` halts at the next opcode and pushes the whole
`LingoState` — callstack, pc, operand stack, locals, `me` — onto
`Window::_frozenLingoStates`. The score advances, then `processFrozenScripts`
resumes after the `go`. It is a coroutine.

**`label(<int>)` is playhead-relative.** `LB::b_label`
(`lingo/lingo-builtins.cpp:2967`) branches on argument *type*: a string goes to the
position-indexed `func_label`, a number goes to `func_marker`
(`lingo/lingo-funcs.cpp:238`), which at 0 returns `Score::getCurrentLabelNumber()`
(`score.cpp:240`) — the last marker at or before the playhead, as a frame number.
This port already matches. A previous session recorded the opposite as a
divergence; it was never true.

**The per-frame channel dump is a debug channel, not a console command.**
`Score::formatChannelInfo()` is emitted by `debugC(9, kDebugLoading)` at
`score.cpp:2289`. That is what makes trace capture scriptable — see
`tools/capture_scummvm_trace.sh`.

## Where it is wrong for this game

**The displayed-channel count.** `score.cpp:1976` hard-codes
`_numChannelsDisplayed = 120` when `framesVersion <= 13`, *skipping* the `uint16`
that follows. That skipped field is the real count: 40 of this game's 61
score-bearing files declare 120 and **21 declare 150**, and `ENDMOVI1.DXR` writes
sprite channel 150. ScummVM truncates that movie. Read the per-movie field at
VWSC-header offset 18; do not copy the 120, and do not copy the
`director-data-recovery` skill's 200 either — that is a safe buffer size and a
useless channel count.

**The engine version.** ScummVM's detection entry classifies this game as 850,
which describes the *projector*. Every movie is D7. `Cast::loadConfig`
(`cast.cpp:630`) only ever *raises* the version, so the 850 sticks and cannot be
lowered, and ScummVM then applies post-D7 config layout to a D7 movie — its own
VWCF checksum rejects the result. Any version-gated comparison against a ScummVM
trace is therefore invalid.
