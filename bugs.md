# Known bugs and open engine gaps

One entry per issue, worst first. Each carries the evidence it was found with, so
the next session can confirm it still reproduces before working on it rather than
trusting this file.

Numbers here were measured on the commit that added the entry. Re-run the tool
named in the entry before acting on a figure. Agreement with the lifted export
falls as the port gets more faithful, so a moved number is not automatically a
regression: see `.claude/skills/porting-fidelity-verification/SKILL.md`.

---

## 1. Interpreted sprite property writes never reach the renderer

**Status:** CLOSED — `SpriteChannel`, see the Closed section · **Area:** renderer / interpreter host

`LingoHost.set_sprite_prop()` writes every `set the <prop> of sprite N` into its
`puppet` override dictionary, and nothing outside `lingo_host.gd` ever reads that
dictionary. `MoviePlayer.draw_current_frame()` takes member, position and size
straight from the score frame. Only `visible` reaches the stage, because it is
forwarded separately to `DirectorRuntime.set_channel_visible()`.

Corpus counts of sprite property writes in the compiled scripts:

| property | writes | reaches the stage |
|---|---|---|
| `memberNum` | 624 | no |
| `visible` | 406 | yes |
| `locV` | 397 | no |
| `locH` | 347 | no |
| `cursor` | 155 | no |
| `moveableSprite` | 15 | no |
| `constraint` | 10 | no |

That is 1548 of 1954 writes with no effect on what is drawn. Any original
animation driven by Lingo rather than by the score is therefore dead: ARCADE2
puppets sprites 7 and 40 and moves them, MIROLO drives a row of channels,
FIGTBRJ sets `the memberNum of sprite 30`. The `puppetSprite N, 1` calls are
already tracked in `LingoHost.puppeted` (288 call sites), so the state needed to
know which channel Lingo owns is present and unused.

The fix is one effective-sprite resolution the renderer reads through: score
frame first, puppet overrides on top, visibility last. It replaces the current
special cases for channel 30 and the inventory slots rather than adding to them.

**Reproduce:** `grep -rn "set_sprite_prop" lingo/lingo_host.gd`, then confirm no
consumer: `grep -rn "host.puppet" director/ ui/` returns nothing.

---

## 2. `whatodoeveryframe` is reimplemented natively, not run

**Status:** open · **Area:** puppet

`PuppetController` is a hand-written version of the original's walk state machine.
It reads the original's globals (`ifmovie`, `nextroomdata`, `egozh`, `egozv`,
`whatodo`, `syz`) but decides everything itself, so each of the original's lines
that the port needs has to be copied across by hand. The room-transition hide
(`sprite(30).visible = 0`) is the most recent example, and every one of these is a
place the copy can drift from the script.

Blocked on 1: `whatodoeveryframe` drives Piposh entirely through
`the memberNum of sprite 30` and `the locH/locV of sprite 30`, which is exactly
what the renderer ignores today. Fix 1 and this script becomes runnable.

---

## 3. `_lingo_hidden` is never cleared on a movie change

**Status:** CLOSED — channels are cleared on movie load, see the Closed section · **Area:** score runner

`DirectorRuntime._mark_movie_loaded()` clears the timing accumulator, the pending
transition and the film-loop cursors. It does not clear `_lingo_hidden`, and
`enter_frame()` only replaces `_hidden_channels`. A `sprite(N).visible = 0` in one
movie therefore keeps channel N hidden in the next movie, where that channel is
unrelated artwork.

Not simply "clear it on load": DAY1's `init all` hides sprites 6, 15 and 33 once,
on its init frame, and a return into DAY1 from SEA1 lands at `shore2downdeck`
rather than that frame. Clearing without replaying those hides would show three
sprites that should be hidden. Needs a decision about what a movie load resets,
which is the same question 1 answers for the override table.

Channel 30 is not affected: it routes to `PuppetController.visible` instead.

---

## 4. Two exits stop working when clicks are interpreted

**Status:** open · **Area:** interpreter / walk

`DAY1 @edge2go ch10` and `NIGHT1 @edge2go ch10` walk to `edge1go` with
`use_lingo_clicks` off and do not walk at all with it on. Present before the
current session's changes; confirmed by running the harness against a clean
checkout.

**Reproduce:** `godot --headless --script tools/lingo_walk_diff.gd`, rows tagged
`[no-walk]`.

---

## 5. Nineteen walks reach a different room than the export

**Status:** open · **Area:** interpreter / walk · **Related:** 9

Most are HOTEL1, where the export is the weaker of the two references:
`movie_context.json` has 23 unmapped transitions there and no verified ones, and
its destinations repeat per channel across unrelated rooms. Some of the 19 are
likely the interpreter being right and the export wrong. Each row needs reading
against the original handler before it is called a bug.

**Reproduce:** `tools/lingo_walk_diff.gd`, rows tagged `[wrong-room]`.

---

## 6. SEA1 and AIR1 stall under interpreted frames

**Status:** open · **Area:** interpreter / frames

With `use_lingo_frames` off, SEA1 visits 24 distinct frames over 220 ticks and
AIR1 visits 34. With it on, SEA1 sits on frame 3 for the whole run and AIR1 stays
between 3 and 29. Agreement with the score runner is 0/220 ticks for both, against
220/220 for DAY1, NIGHT1 and HOTEL1.

**Reproduce:** `godot --headless --script tools/lingo_frames.gd`.

---

## 7. Two clicks produce no navigation or sound under the interpreter

**Status:** open · **Area:** interpreter / clicks

`SEA1 ch9 frame 1234` and `AIR1 ch8 frame 707`: the export carries a destination
and a sound list, the interpreted handler produces neither. These are the only two
outright disagreements in the convergence run, so they are small and specific
enough to read end to end.

**Reproduce:** `godot --headless --script tools/lingo_converge.gd`, lines tagged
`differ`.

---

## 8. Both `movie_context.json` and `walk_doorways.json` paths are still live

**Status:** open · **Area:** scaffolding retirement · **Related:** 5

The transition destinations now have a Lingo answer: `BehaviorScript 207` reads
`item 1 of nextroomdata`, and the native redirect only runs when that script does
not. The rest of the tables have no Lingo answer yet: hub membership, meeting
triggers, phase transitions, day advance, per-hotspot walk doorways. Every one is
a guess that will eventually contradict the scripts, and the HOTEL1 and NIGHT1
rows are marked inferred rather than verified in the data file itself.

Retire in the order they become redundant, and delete rather than leave both
paths live.

---

## 9. `init all`'s puppeting is lost on every movie change

**Status:** open · **Area:** score runner / Movie-In-A-Window

DAY1's `init all` runs `puppetSprite` on channels 30, 100 and 103-110, once, on frame
1. `_mark_movie_loaded()` clears the channels on every movie load, so one round trip
through the joke window drops all of it:

    after init all:            puppeted=[30, 100, 103, 104, 105, 106, 107, 108, 109, 110]
    after a JOKE round trip:   puppeted=[]

Clearing is right — channel N in the next movie is unrelated artwork — but Director
never unloads the parent movie for a Movie In A Window in the first place, so the
question does not arise there. The port returns mid-room without re-running `init all`,
so the score reclaims channels Lingo is supposed to own. Nothing depends on it today:
the puppet draw asks `score_uses_channel()` instead, and the inventory slots are drawn
from their own override. It will matter the moment a script drives one of those
channels after a round trip.

**Reproduce:** enter DAY1 at frame 1, tick, read `channels[103].puppet`; open and
forget the joke window; read it again.

---

## 10. Convergence is measured on 5 of 61 movies

**Status:** open · **Area:** verification

`lingo_converge.gd` and `lingo_frames.gd` cover DAY1, NIGHT1, HOTEL1, SEA1 and
AIR1. Nothing measures the other 56, including every minigame and meeting movie.
An engine change can only be checked against the five.

---

## 11. The upstream exporter decodes every 1-bit member as 8-bit

**Status:** open upstream, worked around here · **Area:** assets / export

Director's CASt chunk holds a `u16` pitch whose `0x8000` bit is the depth flag and
whose low 15 bits are the row stride, then a **signed** rect. The exporter records
that high byte as `bpp_marker`, ignores it, reads every member as 8 bits per pixel
and infers geometry from the decoded byte count. Correct for 8-bit members, wrong
for every 1-bit one: `wlkcur1` came out 5x6 pixels of colour noise instead of
13x17.

That exporter is not in any repo on this machine. `assets/SOURCE.txt` records the
assets as a robocopy from `E:\games\piposh2\reports\render_model\` on a Windows
box; `Piposh2-Port` is a separate migration effort whose `spike/bitd-export`
self-describes as disposable and emits a different format, and
`~/Projects/_private_projects/piposh2/` has no exporter either.

`tools/repair_1bit_members.py` re-decodes the affected members in place from the
raw chunks and `tools/verify_1bit_members.py` is the pass/fail check. **A future
re-export from the Windows toolchain will silently undo the repair** unless the
decoder is fixed there first, or the repair is re-run after syncing.

Reproduce:

```
python3 tools/verify_1bit_members.py     # PASS once repaired
python3 -c "import struct;b=open('/Users/yonatankarp-rudin/Projects/_private_projects/Piposh2-Port/originals/recovery/web-alpha/decompiled_chunks/DAY1/DAY1/chunks/CASt-51.bin','rb').read();t,c,s=struct.unpack_from('>III',b,0);p,=struct.unpack_from('>H',b,12+c);print('pitch',hex(p),'rect',struct.unpack_from('>hhhh',b,14+c))"
```

**134 members repaired, every one from its own chunks.** `tools/dump_movie_chunks.py`
reads the `.DXR`/`.CXT` containers directly, so the coverage gap that once forced
NIGHT1 to borrow its cursors by name is closed, and ENDMOVI4's `handcur1` and
`handcur2` — which appear in no other movie and so had no donor — are repaired too.
Nothing is borrowed any more.

Only `HEZSAVE` still has no chunks, and the port intercepts it for JSON saves
rather than running it.

Note that an unrepaired cursor does *not* degrade to the arrow. The size guard in
`cursor_image` catches only a wildly wrong decode; NIGHT1's members came out 5x6 to
24x26, all small enough to compose into a plausible-looking block of noise and
install as the cursor. Anything that regresses the decode will look like static,
not like a missing cursor.

---

## 12. One DAY1 film loop still does not parse

**Status:** almost closed · **Area:** assets / renderer · **See also:** 15

This entry began as the report now filed as 15, and was rewritten into a
film-loop entry when that fix was believed to have closed it. It had not been
confirmed with the reporter, and it had not: the loops resolved, and then their
children resolved against the wrong cast library. 15 is now closed by that second
fix. What is left here is one loop that still does not parse at all.

A movie's internal cast is now registered under the movie's name, so film loops
living there resolve. Before that, `get_film_loop` refused `cast_lib 1` outright
and `generate_cast_registry.py` collected only linked casts, so MURDER1's `tofi
right`, `goldolin left` and `tofi walking back` — members 5, 10 and 13 of its own
cast, used by the score on channels 9, 3 and 17 — could never be found, and the
characters never animated.

Corpus-wide there were 17,506 sprites across 49 of the 88 movies pointing at an
internal member with no bitmap, which is what a film loop looks like from
`members.json`. 21 internal casts now carry their loops.

The coverage half is closed. `tools/dump_movie_chunks.py` reads the containers
directly, so 84 of the 88 movies now have chunks and the registry carries 497 film
loops across 60 internal casts. **17,426 of those 17,506 sprites now resolve**, up
from none.

What is left is one member: DAY1's 309, `loshuaa`, on channel 19 for 80 sprites.
Its `SCVW-1800` trips "channel data exceeds D7 limit" in
`tools/director_film_loops.py`, so the loop is skipped rather than mis-parsed. The
D7 constants in that file (`MAIN_CHANNEL_SIZE = 288`, `SPRITE_CHANNEL_SIZE = 48`,
`MAX_D7_SPRITE_CHANNELS = 200`) are the thing to re-derive against this one chunk;
the recovery skill warns that score format is the part that moved most between
versions.

Reproduce: `goto_movie("MURDER1")` then `loader.get_film_loop(1, 5)` resolves to 7
frames at 168x279; `goto_movie("DAY1")` then `get_film_loop(1, 309)` returns `{}`.

---

## 13. `init all` never runs on movie entry

**Status:** open · **Area:** interpreter / score

Each hub's `init all` sits at the movie's frame 1 and the port jumps straight to a
room's `*go` frame, so it is never played. `DAY1/wonder/BehaviorScript 56` sets
`shelltoday`, `bath`, `dubi`, `mirror`, `inexits`, `wreck` and `firsttalk`, and
calls `cursorfunk()` and `peoplefunk()`. None of that happens; `GameState` supplies
its own new-game values instead, which is why the game plays at all.

`_run_cursor_funk()` calls the one handler cursors need, deliberately and no more:
running the rest here would reset that state over whatever a save had just
restored. Everything else `init all` does is still missing.

Reproduce: after `goto_movie("DAY1")`, every global above reads `<unset>` from
`runtime.lingo.interpreter.globals`.

---

## 14. Art draws stretched on one axis. Two causes; the score-side one is fixed.

**Status:** the score-side half is CLOSED — the stretch flag, see the Closed
section. The member-side half below is open. · **Area:** assets and score

Reported twice from play: art "scratching over too much". The clearest instance is
the raft in the opening, where the bearded man's head is smeared horizontally
across the sky.

**Read the Closed entry first.** The score's stored width and height are only the
drawn rect when the sprite's stretch flag is set, and that flag was being dropped on
export. The 979 sprites counted below split three ways on it: **925** were the
residue and are no longer drawn that way (ALLIN 839, DAGI 51, INVESTIG 34, MORN3 1);
**47** carry the flag, so Director really does stretch them and they were never bugs
at all (SEA1 32, NIGHT1 6, ARCADE2 5, CHESS 4); and **7** are `strtgame`, whose
flags could not be read. What is left in this entry is that `strtgame`, where the
member's own geometry is wrong and the score is right.

That head is `strtgame` member 26, channel 15, frames 122-128. `members.json`
records it 45x34 and the score draws it at 135x34: a 3x stretch on width with
height untouched. On the same channel member 25 draws at exactly its natural
37x26, so the score is not stretching the channel — this member's recorded size is
wrong, and the renderer stretches a too-small bitmap into a correct sprite rect.

Three signals agree that the member, not the score, is wrong:

- its registration point is (68, 17) on a 45-wide bitmap, outside the image, and
  68 is half of 135 while 17 is half of 34;
- `BITD-2774` PackBits-decodes to 13,568 bytes consuming its payload exactly, not
  the 1,564 that stride 46 x 34 rows implies;
- its `CASt` rect nonetheless reads 45x34, so rect and raster disagree.

Corpus-wide, searching for the signature — one axis stretched more than 1.8x while
the other stays within 5% of natural — finds **979 sprites in 9 movies**:

| movie | sprites | example |
|---|---|---|
| ALLIN | 839 | `1:1` 640x441 -> 1280x441 |
| DAGI | 51 | `1:13` 129x19 -> 129x35 |
| INVESTIG | 34 | `1:76` 186x13 -> 368x13 |
| SEA1 | 32 | `1:245` 56x12 -> 109x12 |
| strtgame | 7 | `1:26` 45x34 -> 135x34 |
| NIGHT1 | 6 | `1:371` 6x174 -> 6x325 |
| ARCADE2 | 5 | `1:103` 34x10 -> 68x10 |
| CHESS | 4 | `1:21` 60x27 -> 117x26 |
| MORN3 | 1 | `1:10` 136x13 -> 335x13 |

**These are not all the same bug.** The first draft of this entry generalised the
strtgame finding to all nine movies, on the strength of the ratio being close to
2x, and that was wrong. Checking the other movies' `CASt` chunks:

| member | members.json | CASt rect | stride | depth |
|---|---|---|---|---|
| ALLIN `1:1` | 640x441 | 640x441 | 640 | 8 |
| INVESTIG `1:76` | 186x13 | 186x13 | 186 | 8 |
| SEA1 `1:245` | 56x12 | 56x12 | 56 | 8 |
| DAGI `1:13` | 129x19 | 129x19 | 130 | 8 |
| CHESS `1:21` | 60x27 | 60x27 | 60 | 8 |

Every one of those agrees with the container exactly, so their member geometry is
right and the stretch comes from the score's sprite rect instead. strtgame member
26 is the only one measured so far where the member itself is inconsistent. Two
different causes wearing the same symptom.

**The score-side group was the score's rect being read as an instruction.** The
theory recorded here was that ALLIN's `(-641, -12)` at `1280x441` looked like "a
left coordinate and a width derived from each other wrongly". It was not: the
score really does store 1280, and Director really does ignore it, because the
sprite's stretch flag is clear. That is the Closed entry below.

A 4-bit-read-as-8-bit theory was tested and rejected: every member above reports
depth 8 with stride equal to width.

**What is left is the member-side case, and only in `strtgame`.** Member 26 is the
one member measured anywhere in the corpus that does not agree with its own
container, per the three signals above.

`strtgame` is also the one movie whose stretch flags could not be recovered, so it
keeps the rects the exporter wrote for all 4,500 of its sprite records where the
rect and the member disagree — see the Closed entry. Both halves of the remaining
work are therefore in the same movie, and both are blocked on the same thing: its
container is XFIR (little-endian) and `tools/dump_movie_chunks.py` refuses to dump
it, so there are no chunks to re-derive from. Fixing the little-endian reader
unblocks both.

**Ruled out: endianness as the cause of the other eight movies.** The first theory
was that little-endian containers were being mis-read, because `strtgame.dxr` is
XFIR. Only two files in the whole corpus are — `strtgame.dxr` and `MASTER.CST` —
and every other affected movie is big-endian. Recorded because it is a
plausible-looking dead end. It is, however, exactly what blocks `strtgame` now.

Not the same bug as entry 11. That one is 1-bit members read as 8-bit and is fixed.
This is a member whose geometry is wrong in some other way, and the fix is the
same shape: re-derive from the container.

Reproduce. Note what this counts: it reads `frames.json`, which still holds the
rect the exporter wrote, so it reports the same 979 as before the fix. The score-
side ones are no longer drawn that way — `tools/sprite_stretch.gd` is the check for
that. What this is still good for is finding the member-side cases, which are the
rows the stretch flag does *not* explain:

```
python3 - <<'EOF'
import json, glob, os, collections
stretch=json.load(open('assets/render_model/sprite_stretch.json'))['movies']
hits=collections.Counter()
for p in sorted(glob.glob('assets/render_model/*/frames.json')):
    m=os.path.basename(os.path.dirname(p))
    fr=json.load(open(p)); me=json.load(open(f'assets/render_model/{m}/members.json'))['members']
    flags=stretch.get(m, {}).get('frames')
    for i,f in enumerate(fr.get('frames',[])):
        for s in f.get('sprites',[]):
            mm=me.get(f"{s.get('cast_lib',1)}:{s.get('cast_id')}")
            if not (mm and s.get('has_image')): continue
            mw,mh,sw,sh=mm.get('width'),mm.get('height'),s.get('width'),s.get('height')
            if not all((mw,mh,sw,sh)): continue
            rw,rh=sw/mw,sh/mh
            if not ((abs(rh-1)<0.05 and rw>1.8) or (abs(rw-1)<0.05 and rh>1.8)): continue
            if flags is None: hits[(m,'flags unread')]+=1
            elif s['channel'] in flags.get(str(i),[]): hits[(m,'stretched, correct')]+=1
            else: hits[(m,'residue, now ignored')]+=1
print(sum(hits.values()), hits.most_common())
EOF
```

The stage-clipping fix and the film-loop fix were both landed against this report
and neither addressed it. They fixed real but different defects.

---

## 15. A character is missing or flickering while it moves within a room

**Status:** CLOSED — the film-loop child cast library, see the Closed section ·
**Area:** assets / renderer

Reported: characters that should animate while moving around inside a room are
missing, and the one clearest case flickers rather than being absent outright.
Reported as worst "on the cliff between Tofi and Gondolin", and still present after
entry 12's fix, which is why this entry outlived it.

The room was MURDER1 after all, and entry 12's fix was necessary but not
sufficient. It made the loops in the movie's own cast *resolve*; their children
still resolved against the wrong cast library, so the frames the loops play were
either missing or a stranger's bitmap. The cause is in the Closed section.

The reporter's two symptoms were the two halves of the same defect. Goldolin is
absent for the 11 frames from 108 where channel 3 holds loop `goldolin left`,
whose children are goldolin members 63-69: none resolved, so she vanished and
came back, which is the flicker. And "at the beginning Tofi's mouth appears but he
does not" is frames 5-18: channel 11 carries tofi member 34, the mouth, as a
plain score sprite, which drew, while channel 9 carries loop `tofi right`, whose
child is tofi member 4, the body, which did not. A floating mouth over Goldolin.

What was ruled out along the way, all still true and all still worth not
re-checking:

- **Not the transition spans being skipped.** They play: walking `edge1go` to
  `gatego` visits frames 237..338, covering `gatefromedge1` at 324.
- **Not the puppet's size.** Channel 30 draws at the member's natural size in 1290
  of 1290 room sprites, which is what the score does.
- **Not ink coverage.** The only unhandled inks are 0, which is Copy and correctly
  opaque, and 32 at 948 sprites.
- **Not film loops failing to advance**, at least where they resolve: MURDER1 1 of
  1 film-loop channels advances over 60 ticks, RUNAWAY 3 of 3, SHUFFLE 2 of 2.
- **Not the sprite stretch flag**, checked because the fix for 14's score-side half
  moved 22,806 sprite rects and many of them are character members: `fat` 3,491,
  `hatuli` 3,414, `rinati` 3,008, `hezi` 586. But almost all of those are in the
  ENDMOVI cutscenes, and the two characters actually named in the report are the two
  it barely touches — `tofi` 20 records, `goldolin` none. Their in-room animation
  runs through film loops, which that fix deliberately leaves alone. Independently
  confirmed by this fix: every one of the 2,145 external children has a rect exactly
  equal to its member's own size, so no stretch question arises on them.

**History worth keeping:** this entry was twice believed closed by a fix that had
not been confirmed with the reporter — once when it was rewritten into entry 12,
and the ruled-out list above is what that cost. It is closed now on a
screenshot A/B of the two frames the reporter described, not on a resolve count.

---

## 16. `the number of member X of castLib Y` drops the library

**Status:** open, worked around in one place · **Area:** interpreter host

`LingoHost.member_number()` resolves the name through the cast search order and
returns a bare integer, so the library the script named is lost. Writing that
integer to `the memberNum of sprite N` then keeps whichever library the sprite
already had, which for an empty channel defaults to 1, the movie's own cast.

Seen twice while wiring cursors. `cursorfunk` does

    set the memberNum of sprite 93 to the number of member ("day" & globalday) of castLib "master"

and `displayobject` does the same with `member "object0" of castLib "master"`.
Run against an empty channel both resolved master's member into the movie's
internal cast, and MURDER1, HATDAY1 and GOLDDEAD warned "Missing cast member ...
linked cast internal, member 9" on every load. `_run_cursor_funk()` gates
`displayobject` to hubs to avoid it, which is a workaround at one call site, not
a fix.

1064 sites in the corpus use `of castLib`, so this is not a two-handler problem.

The fix is the same one `the castNum` already has: return a packed reference
(`_pack_member`) so the library survives the assignment. The risk is that
`the number of member ...` results are also compared and used in arithmetic, and
a packed value is a large integer, so every consumer has to be checked first.
That is why it was not done alongside the cursor work.

Reproduce: `goto_movie` any non-hub movie with an empty channel 103 after
removing the `context.is_hub` gate in `_run_cursor_funk()`, and watch for the
missing-member warning.

---

## 17. 478 of the registry's 497 film loops are unverified

**Status:** open · **Area:** verification

`tools/verify_film_loops.gd` walks a hardcoded `CASES` list, now 19 loops: 13 in
seven shared casts, plus 6 added with the child-cast fix that also pin which cast a
named child comes from and its size there. It predates internal-cast film loops,
which took the registry from 295 loops in 21 casts to 497 in 60, and it still
enumerates none of them.

So the harness that gates film loops covers 3.8% of them. A film loop that resolves
to a rectangle of nothing, or to children whose textures are missing, would not fail
any check in the repo unless it is one of the 19.

Two sweeps written for the child-cast fix show what enumeration would buy and are
the shape to keep: every film-loop child any score plays resolves to a bitmap
(7,843 of 7,843), and every sprite and child in MURDER1's 884 frames does too. Both
were throwaway scripts. The fix is to enumerate `cast_registry.json` rather than a
literal list, keep the per-loop assertion it already makes, and report the count so
a drop in coverage is visible.

Reproduce: `godot --headless --script tools/verify_film_loops.gd` prints 19
against `python3 -c "import json;c=json.load(open('assets/render_model/cast_registry.json'))['casts'];print(sum(len(v.get('film_loops',{})) for v in c.values() if isinstance(v,dict)))"`.

---

## 18. The gamepad cursor is drawn by code that has never run

**Status:** open, untested rather than known-broken · **Area:** input / renderer

The mouse gets a hardware cursor. The gamepad pointer is somewhere else on the
stage than the OS pointer, so `MoviePlayer.draw_current_frame()` draws the same
composed cursor at `InputRouter.virtual_cursor` instead, and
`_update_virtual_cursor_visual()` hides the plain block while it does.

Neither branch has ever executed. Every check on the cursor work drove the mouse
path: the harness calls `cursor_at` directly, and the scene probes called
`_apply_cursor` without touching `using_gamepad`. The code parses and the game
boots, which is all that is established.

Two things to look at when someone first plays with a controller: whether
`_apply_cursor` installing a hardware cursor while on the gamepad path leaves a
stray OS cursor wherever the physical mouse happens to sit, and whether the drawn
cursor lands on the hotspot or half a cursor away from it.

---

## 19. The cursor never scales at the most common window sizes

**Status:** open, cosmetic · **Area:** renderer

`MoviePlayer._apply_cursor()` scales the cursor with
`maxi(1, int(floor(_stage_scale())))`. Director cursors here are 13x17 to 17x17,
authored for a 640x480 screen, so at a stage scale of 1.5 — which is what a
default window gives — `floor` yields 1 and the cursor is drawn at native size
against artwork that is half again as large. It only doubles once the window is
big enough for scale 2.

Flooring is deliberate: rounding 1.5 up would draw the cursor larger than the art
around it. The result is still that the cursor is visibly small at the size most
people will play at, and it steps rather than tracking the stage.

Reproduce: run the game at the default window size, hover the floor in DAY1, and
compare the cursor against the artwork it sits on. `_stage_scale()` reports 1.5.

---

## Closed

- **A film loop's frames were looked for in the wrong cast library** (was 15).
  A loop's children are usually members of the cast the loop itself lives in, and
  `_draw_film_loop` assumed always: it resolved every child against the loop's owning
  cast. MURDER1 keeps `tofi right`, `goldolin left` and `hezi right + angry` in its
  own cast while the frames they play are members of `tofi.cst`, `goldolin.cst` and
  `hezi.cst`, so the children resolved to whatever the movie's own cast happened to
  have at that number — nothing at all for most, and MURDER1's own member 4, a
  533x17 strip, for the rest, stretched into the child's 108x273 rect as a green
  smear. Both characters on the cliff were drawn from those loops.

  A loop's mini-score does say which library, at offset 4 of the 48-byte sprite
  record, the same place the movie's own score keeps it. `0xFFFF` is the owning cast,
  as in the main score. What differs is that a number there is **not** a cast-library
  index: it is a zero-based index into the file's `ccl ` chunk, an ordered list of the
  cast paths its loops reference, which is a different order. MURDER1's libraries run
  internal, goldolin, hezi, tofi; its `ccl ` runs tofi, goldolin, hezi.

  Read off the containers, not recalled: `ccl [raw]` predicts the cast for all
  **2,145** external children in the corpus, and the member is present in the named
  cast for every one of them — 0 out of range, 0 absent. The parse agrees with a byte
  scan of the same chunk in 29 of 31 dumps, the two exceptions being the chunks whose
  single entry is a genuinely empty path. The negative control holds too: the 9
  cast-only exports have no `ccl ` and emit nothing but `0xFFFF`.

  `tools/director_film_loops.py` now resolves the index to the cast's registered
  name and `generate_cast_registry.py` writes it on the child as `cast`, checking
  against the built registry that the name can answer for the member. A child that
  cannot be resolved is dropped and counted rather than left to fall back on the
  owner, because that fallback is this bug. **98 are dropped**, all in WONDER, whose
  `ccl ` holds one empty path; their members (222 at 70x51 and 983 at 153x197) are in
  no cast in the corpus, so there is nothing yet to point them at.

  Of those 2,145 children, **1,529 previously drew a real but unrelated member of
  the owning cast** and 616 drew nothing, so most of this was wrong art rather than
  absent art — which is why it read as flicker. Counting only the loops a score
  actually plays, 592 of 7,917 children came out blank before and 0 of 7,843 do now,
  across 21 movies (ALLIN 111, SEA1 74, MURDER1 62, SAMNIGHT 59, MORN3 44, …). The 74
  fewer are SEA1's `wonder` loop 673 shedding the unresolvable children described
  above; they drew nothing before and are simply no longer claimed.

  Every sprite and every film-loop child in MURDER1's 884 frames now resolves to a
  bitmap: 5,378 plain sprites and 1,534 children, 0 blank. `lingo_converge`,
  `lingo_frames`, `verify_1bit_members`, `check_cast_coverage` and
  `generate_sprite_stretch --check` are byte-identical across the change, and
  `lingo_walk_diff` differs only in Godot's exit-time leak counters. Covered by
  `tools/verify_film_loops.gd`, which now asserts the cast a named child comes from
  and its size there, and fails on all 6 of the added cases without the fix.

- **Art drew scaled to a rect Director ignores** (the score-side half of 14).
  A Director sprite draws its member at the member's own size, anchored on the
  member's registration point. The width and height in the score are the drawn rect
  only when the sprite's **stretch** flag — bit `0x80` of the sprite record's ink
  byte — is set. With it clear they are authoring residue: the last size the channel
  was dragged to, or the size of a member that used to be there. The upstream
  exporter masks the ink byte to its low 6 bits, dropping the flag, and writes the
  residue into `frames.json` regardless, so the port scaled 22,806 sprite records
  into a rect the original never draws.

  Three independent measurements say that is the flag, two of them on populations
  not used to find it. Of 437,926 sprite records whose rect already equals the
  member's natural size, **zero** carry the bit; 12,265 records differ from their
  member and carry it. On film loops, which the fix does not touch: all 37,329
  records with the bit clear have a rect exactly equal to the loop's own initial
  rect, and all 1,295 with it set differ. And in ALLIN, channel 1 holds the same
  member at the same registration point for all 1438 frames with a stored width of
  1280 on 835 of them, 640 on 259 and 639 on 337, the member being 640 wide — so the
  backdrop popped between the hotel room and its right half at double size as the
  playhead stepped, and the 640 frames are what the fixed 1280 frames now look like.
  That within-movie A/B is the cheapest way to see it: render frame 718 and frame 0.

  `tools/generate_sprite_stretch.py` recovers the flags from the containers into
  `assets/render_model/sprite_stretch.json`, verifying each movie's score against
  `frames.json` field by field and refusing the movie outright if it does not
  reproduce the export. `RenderModelLoader._resolve_sprite_rects()` applies them
  once per movie load, so the channel array, drawing, hit-testing and any script
  reading the sprite all see one rect. Covered by `tools/sprite_stretch.gd`.

  Three things to know. **16 movies have no recovered flags and keep the exported
  rects**; only `strtgame` matters, and it is entry 14's remaining work. **820 of
  the moved rects belong to sprites with click data** (477 smaller, 343 larger),
  which is intended — Director hit-tests the sprite it drew — and `lingo_walk_diff`,
  `lingo_converge` and `lingo_frames` are row-for-row identical across it. And
  `data/walk_doorways.json` derives its walk targets from these rects offline, from
  `frames.json`, which still holds the residue: checked, and 1 of its 77 overrides
  sits on a channel whose rect moved, that one sourced from `reciprocity` rather
  than a hotspot centre. Regenerating it would have to apply the flags first.

- **An uncovered shell or bottle vanished after one frame.**
  `_run_skipped_entry_scripts()` replayed the room's entry frames on every entry into
  a `*go` frame. The room loop is `go(marker(0))`, which throws the playhead from
  anywhere in the idle span back to the `*go` frame, so by frame number every
  iteration looked like an arrival; each replay re-ran `b4 bk's` and its
  `set the visible of sprite 15 to 0`. Arrival is now decided by the marker.
  Covered by `tools/collectables.gd`.
- **Every interpreted script died after a window, meeting or minigame.** `go_back`
  reloaded the movie but never called `lingo.prepare_movie()`, so the interpreter's
  current movie stayed on the one being left. `frame_script(1858)` then looked for
  member 83 in JOKE's casts, found nothing, and the room's entry scripts silently did
  not run — which left every collectable in the room on show, because the blanking in
  `b4 bk's` never executed, and left `whereami` stale so hotspots gated on it took
  their dead branches. This was `bugs.md` 10, and it was far wider than the bottle it
  was found through.
- **Piposh vanished for the length of every room transition.** The first version of
  the fix below tested whether the *current frame* has a channel 30. A transition span
  such as `edge3up` carries none for twelve frames while he walks through it. The test
  is now per movie, via `RenderModelLoader.score_uses_channel()`, which also does not
  depend on the puppet flag — `init all` sets that once and `channels.clear()` drops it
  on the next movie change.
- **A second joke was drawn on the page.** The puppet was drawn over every movie, at
  `cast_lib 1` plus whatever member `PuppetController` held, resolved against the new
  movie's own internal cast. JOKE's member 29 is the joke bitmap `joke33`, and Piposh's
  syz-9 stand member is 29, so on the beach his sprite came out as a second joke at his
  stage position. Other sizes and the walk frames land on members 31-54, which in JOKE
  are more jokes, so it changed from room to room. Piposh is channel 30 of his own
  movie; a Movie In A Window has its own channels and JOKE never mentions 30, so there
  is nothing to draw there.
- **The joke picture was never drawn.** JOKE parks channel 3 on `jokepfff`, a 1x1
  placeholder at (318, 199); the Lingo swaps in a 214x120 joke with its own
  registration point. With member writes reaching the channel it now lands at
  (133, 67) at full size. This is what made the joke text look off-centre and
  partly cut off.
- **Interpreted sprite property writes never reached the renderer** (was 1).
  `SpriteChannel` is Director's live channel array; drawing and hit-testing read it.
- **`_lingo_hidden` leaked across movies** (was 3). Channels belong to the movie and
  are cleared on load, which drops the previous movie's puppet ownership, its hides
  and its film-loop cursors together.
- **Shells and bottles recorded against the wrong room.** `the castNum` dropped the
  cast library, so `member(...)` resolved in the movie's own cast: DAY1's sprite 1 is
  `island:10` (`shore2`) while DAY1's own member 10 is the cursor `wlkcur1`. 25 of 32
  rooms answered with a cursor name and 7 with the empty string, and `nof` is the key
  `shellfield` and `jokefield` are written under, so one shell taken in any of those
  7 marked all of them collected. Covered by `tools/room_names.gd`.

- **Piposh drawn twice across a room transition.** The canned transition animation
  draws him in a low channel while the puppet drew unconditionally. `the visible of
  sprite 30` is now a real property (`PuppetController.visible`), hidden on the
  original's own `ifmovie` condition and restored by `BehaviorScript 207`.
  Covered by `tools/puppet_visibility.gd`.
- **`LingoHost.navigated` was never raised**, so every interpreted `go` was
  overridden by the exported fallthrough one step later.
- **`_try_transition_redirect` ran before `exitFrame` dispatch**, answering from
  `movie_context.json` a question `BehaviorScript 207` answers from the script's
  own globals. It is now the fallback.
- **Not a bug: the "undispatched event classes".** `docs/ENGINE.md` listed
  `keyDown`, `startMovie`, `stopMovie` and `idle` as never dispatched. The corpus
  contains no `stopMovie`, `idle`, `mouseEnter` or `mouseLeave` handler at all; its
  only handler classes are `exitFrame` (2504), `mouseUp` (721), `mouseDown` (40)
  and `enterFrame` (33), and all four are dispatched. `keyDown` works through
  `the keyDownScript`, which `LingoHost` honours and `DirectorRuntime` routes
  keypresses into. Nothing to do; the doc line was stale.
