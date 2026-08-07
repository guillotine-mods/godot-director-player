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

`tools/smoke.gd` in this repo *was* that test — 20 checks, seconds to run. It was
described four times before it was written, and it would have caught four of the
five. It drove the retired renderer and has been deleted; **nothing replaced it,
and that is the largest hole in this repo's verification.** `gate.sh` covers
mechanisms one at a time and nothing walks the first minute of play end to end.

## When a fix changes nothing, do not keep it

Two speculative fixes measured identically to no fix. Both were discarded rather
than shipped, because keeping them would have left comments in the codebase
asserting a cause that was not the cause. Ship what you can demonstrate.
