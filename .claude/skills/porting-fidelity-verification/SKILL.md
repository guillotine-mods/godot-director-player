---
name: porting-fidelity-verification
description: Use when verifying a port against derived or lifted reference data, when writing a new harness or assertion about the original's behaviour, when a fidelity metric moves unexpectedly, before flipping a behavioural flag on by default, or when deciding whether a measured difference is a regression. Covers why agreement metrics invert as a port gets more faithful, why to distrust the harness before the code, and how an assertion can pass while proving nothing.
---

# Verifying a port whose oracle is derived data

Written after a day on Piposh 2 in which five regressions shipped, every one found
by the user rather than by a harness, and three separate metrics turned out to be
measuring something other than what they claimed.

## Agreement with derived data is not higher-is-better

A port often has two sources: the original scripts, and an earlier tool's
extraction of them (lifted navigation, hotspot tables, guessed context). The
extraction is a genuine oracle — produced independently, from the same originals —
but it is lossy in specific ways.

The consequence is counterintuitive and it will mislead you:

**As the port becomes more faithful, agreement with the extraction falls.**

Piposh 2, walk outcomes over 117 hotspots:

| change | agreement | reading |
|---|---|---|
| baseline | 51/117 | |
| room-entry state fixed | 89/117 | genuine improvement |
| story gating started working | 84/117 | *also* an improvement |

The 5-case drop was two exits correctly refusing to open while a murder was
unresolved, plus knock-on. The extraction has no story gating at all, so honouring
it *must* register as disagreement. Two of those cases were reported as "dead
clicks", which sounds unambiguous and was not.

**So:** a fidelity number tells you where to look, never whether you are right.
Read every changed case. Assert specific behaviours separately, in both states
(gate closed *and* open), because that is a claim the extraction cannot contradict.

## Distrust the instrument before the code

Every metric that surprised me was wrong, and the code was right:

- **A number that will not move.** Four substantive changes produced byte-identical
  results. That is not four failed fixes, it is a harness not exercising the code.
  It was a compile error: one file failed to load, the engine was null, every case
  failed identically.
- **A number that is suspiciously perfect.** 117/117 identical, from that same
  broken build. Every case returned "enter-failed".
- **A number that halves.** Convergence "reached" fell from 533 to 273. I invented
  a plausible story about namespace collisions and wrote it into the tool's header
  as fact. The real cause was a binding I had added an hour earlier that navigated
  during a recording sweep, taking it out of the movie under measurement.

The discipline: when a metric jumps, prove the harness still exercises the path
before explaining the result. A cheap way is to assert something you already know
to be true and check it still holds.

## "Not a bug" is a claim about the original, and the export cannot make it

This is the mistake that has cost this port the most, because it is the one that
*stops* work. A bug report gets investigated. A verdict of "that is authentic, the
port is faithful here" closes the file, so it needs **more** evidence than the
report did, not less. Every time it has been given cheaply here it has been wrong.

The trap is that the export looks like an oracle and is not. It is the port's
*input*. When the renderer agrees with `frames.json` and `cast_registry.json`, that
is the renderer being correct about the data — it says nothing about whether the
data is what the player saw. Any argument of the form "the data says X, therefore
X is authentic" is circular, and it will feel like evidence because real numbers
went into it.

A player reported characters appearing twice in DAY1 `@field`, `@edge1` and
`@veranda`. Both film loops in `@veranda` resolved to the same cast member, both
drew exactly where the mini-score put them, and the member's `CASt` rect, stride
and `BITD` payload all agreed at 80x69. Every one of those checks passed, and the
conclusion drawn from them — "the original really does show this guest twice" —
was wrong. The rooms hold an `a` and a `b` loop of **one** character at two
positions, and `peoplefunk` hides one pair. No amount of internal consistency
could have revealed that, because the duplication is in the *port's behaviour*,
not in the data the port reads.

**Reach for a source outside the pipeline before ruling anything authentic.** In
descending order of cheapness:

1. **Member and cast names** (`data/lingo/member_names.json`). Nearly free, and
   the most underused thing in this repo. Geometry is derived and says what the
   art *is*; names are authored by a human and say what it is *for*. One lookup
   returned `atoflop1` / `btoflop1`, `arinlop1` / `brinlop1` — an `a`/`b` pair per
   character, which is the whole answer. It was available from the first minute
   and went unread for hours while three consistency checks were run instead.
2. **The original scripts** in `reference/lingo/`. They state intent directly.
   `MovieScript 246` shows one of each pair; `BehaviorScript 290` branches on
   `if sprite(18).visible = 1`, which is only meaningful if something hides it.
3. **ScummVM**, per `docs/SCUMMVM_REFERENCE.md`, when the scripts are ambiguous.

**The tell.** If a "faithful" verdict rests only on facts derived from
`assets/render_model/`, it is unsupported however many of them there are. Say "the
export is self-consistent here, and I have not checked it against the original" —
true and useful — rather than "this is authentic", which is a different and much
stronger claim.

**A corollary for grotesque art.** This game's caricatures genuinely look broken:
squashed bodies, heads at half the frame. "It looks wrong" is not evidence of a
bug and "it is a cartoon" is not evidence of authenticity. Neither impression
settles anything; go and find the name or the script.

## A revert that reverts nothing scores as a pass

`git stash push -- <file>` on a file with no working-tree changes stashes nothing
and exits non-zero, and a `&&`-chained harness run then measures the *unchanged*
tree. Attributing a fix this way after committing it produces a "before" run that
passes, which reads as the fix being unnecessary. Attribute against
`git checkout HEAD~1 -- <file>` once the change is committed, and treat a "before"
run that passes as a broken experiment until proven otherwise — the same reflex as
the section above.

Relatedly, when a sweep you have just written reports failures, suspect the sweep
first. A corpus check of film-loop children reported 273 wrong draws; the renderer
was right and the assertion had omitted the parent's scale factor.

## Do not assert a tidier game than the one being ported

A new harness is a set of assumptions about the original, written down. Two of mine
were wrong where the code was right:

- **Uniqueness.** A check that every room's collectable key is distinct failed on
  three rooms — which genuinely share one background member in the original, so the
  original shares the key too. It now reports sharing instead of failing on it.
- **A behaviour the port structurally cannot have.** A check that an item stayed
  hidden after a window closed was asserting Director's two stages. Worth keeping
  only once restated as what the player actually sees on the way back.

Before believing a new assertion, ask what in the original guarantees it. If the
answer is "it would be tidier that way", the assertion is the bug.

## Make a round-trip assertion show the state crossing the boundary

A smoke check asserted "the window shows this day's picture" and passed for months
by reading a property back out of the dictionary the write had just gone into. The
renderer never consulted that dictionary, so the picture was never drawn. The
assertion proved the setter and the getter agreed with each other.

Assert at the far end: the rect the renderer will use, the pixels, the value the
consumer reads — not the value you just stored.

## Look at the asset before reasoning about its coordinates

Two screenshots of a mispositioned image produced a long run of plausible theories
about registration points and sprite rects, none of which fitted, partly because
the "before" and "after" were mixed up. Converting the suspect bitmap and simply
viewing it identified the culprit outright, in seconds. Where an asset pipeline is
involved, extract and look before deducing.

## Find the silent caps

Two tools truncated their findings with no indication:

- a walk differ printed 12 of 66 differences
- a convergence checker printed 15 of 29

Both read as complete lists and shaped decisions for hours. Any tool that reports
a count and a list must print the whole list or say what it dropped.

## Check the baseline is what ships

A differ compared "both flags off" against "both flags on", but one of those flags
had defaulted on the day before. So it measured a change that had already
happened and attributed it to the flag under test. Correcting it happened to leave
the totals unchanged — which is the useful part, because it isolated the delta to
the right cause.

## Classify by-design behaviour out of the failure count

A convergence checker counted 29 divergences. Twenty-four were inventory slots
driven natively rather than by script, and two were save buttons the runtime
intercepts by design. Counting them as failures hid the three real ones. Report
categories, and make "forgiven" visibly distinct from "resolved" so a genuine
regression cannot hide inside a reclassification.

## Smoke the user's first minute before flipping a flag

All five Piposh 2 regressions landed on boot, intro, collectables or pickups.
Every harness measured walk destinations, so none could see any of them.

Before turning a behavioural flag on by default, assert end to end: boots to the
expected screen, new game reaches the expected movies, the opening sequence
advances rather than looping, an item can be picked up *and* leaves the room,
conditional content is hidden and shown in the right states.

`tools/smoke.gd` in this repo is that test — 20 checks, seconds to run. It was
described four times before it was written, and it would have caught four of the
five.

## When a fix changes nothing, do not keep it

Two speculative fixes measured identically to no fix. Both were discarded rather
than shipped, because keeping them would have left comments in the codebase
asserting a cause that was not the cause. Ship what you can demonstrate.
