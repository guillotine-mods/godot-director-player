# Resolved bugs and closed engine gaps

Nothing here is open. `bugs.md` is the live list; this file is where an entry goes
once its defect is fixed, so that the numbers keep resolving. Around twenty source
comments cite `bugs.md <n>` by number, and several of those numbers are here.

Entries keep the number they were filed under. Where an entry was only partly
resolved, the fixed half is here and the remainder is still in `bugs.md` under the
same number.

**Two sections were appended on 2026-08-14 by a sweep of the whole queue**, and
they are not the same kind of closed. The first holds 20 entries whose defect was
fixed and whose entry was simply never moved. The second holds **18 entries that
were never fixed**: the retired renderer deleted their subject, so they cannot be
re-measured and cannot be worked on. Read the second section's own preamble before
citing anything in it, and read each entry's closing note before its `**Status:**`
line, which is kept as filed and is history.

**Three numbers are now two entries each, and all six are here**, which is not an
error: `bugs.md`'s collision table records the reused numbers and says why
renumbering is the wrong repair. Cite 33, 34 and 41 by title, because a bare
citation to any of them resolves to two entries **in this file**.

Kept rather than deleted for one reason: most of the value in these entries is the
list of things that were measured and ruled out. Re-deriving "the D7 constants were
right all along" or "endianness was not the blocker" costs a session each.


---

## 53 and 35. A field designator threw away both of its halves: the library it named, and the property it asked for

**Status:** FIXED · **Area:** `scenes/director_preview.gd:lingo_field` /
`lingo_set_field` / `lingo_field_prop`, `scenes/preview/text_art.gd:resolve`,
`scenes/preview/members.gd:library_named`, `lingo/lingo_interpreter.gd`'s two
`field_prop` arms · covered by `tools/field_designator.gd`, in `gate.sh`, which
fails on the code before the fix in both halves (2 checks red for the library
half, 4 for the property half)

Two entries, one designator, and they are here together because the second was
found while fixing the first and neither is complete without the other. `35` and
`53` were the same defect filed twice; the numbers are kept because source
comments cite them.

### The library it named

`lingo_field(name, _cast)` and `lingo_set_field(name, _cast, text)` took the cast
library the script wrote and spelled the parameter `_cast`. Both went through
`_resolve_field(name)`, which asked `Members.resolve_ref(name, "")` — the
*unnamed* path, which walks every library in number order and takes the first
member of that name. So `field "objectsfield" of castLib "master"` was resolved
as though the clause had never been written.

`Movie::getCastMemberIDByNameAndType(name, castLib, type)` is the rule
(`reference/scummvm/movie.cpp:720-759`): the `castLib == 0` arm is the only one
that walks every cast, a named library is searched *and nothing else*, and a
named library that does not hold the name answers -1 rather than falling through.
`preview/members.gd`'s own header had been saying the same thing about
`member(...)` since `docs/bugs-closed.md` 29 and 34.

**Measured before it was changed**, because `35` recorded the blast radius as
unknown and that was the reason it had sat open. `tools/field_designator.gd
--survey` opens every movie of a root and compares the two resolutions for every
`field "x" of castLib Y` its scripts spell:

| root | qualified references | resolve differently |
|---|---|---|
| piposh | 16 | 2 |
| piposh-en | 9 | 2 |
| piposh-ru | 9 | 2 |
| piposh2 | 170 | 0 |
| piposh-dream | 10 | 10 |
| rating | 0 | 0 |

So the fix moves **nothing** in Piposh 2, which is the corpus every other harness
is measured against — the 170 qualified references all name the library that was
going to win anyway. What it moves is the shape the corpus cannot produce by
luck, which is what `tools/field_designator.gd` asserts instead: a field asked for
in a library that does not hold it must answer nothing rather than the copy next
door.

**The port keeps one deliberate deviation, and it is why the fix is not simply
"pass the argument through".** Three of those 214 references name a library the
movie does not have. Piposh 1's `mainmenu.dir` writes
`field "globalmoney" of castLib "master.cst"` and `field "afganifield" of castLib
"master.cst"` where its own `MCsL` calls that library `master` — both spellings
exist across the corpus, `zoom1`/`zoom1.cst` and `pirats`/`pirats.cst` among
them, because each movie names its linked casts itself. Ten `piposh-dream`
movies say `castLib "panel.cst"` for a library they do not load at all.
`getCastLibIDByName` answers -1 for all three and the reference then finds
nothing, which would take the money off Piposh 1's slot machine — a field the
original draws. So `_resolve_field` asks `Members.library_named` whether the
clause names a library that *exists*: one that does stops the search, which is the
rule and the whole of the defect; one that does not falls back to the unqualified
walk, which is this port's reading and is written down as such at the call site.

### The property it asked for

Found while fixing the above, and the worse of the two. `the <prop> of field "x"`
parses to a `field_prop` node carrying the property name, and both of the
interpreter's arms for it **threw the property away**: the read answered
`get_field` and the write called `_set_field_node`. So every one of the fifty
member properties read back as the field's *text*, and every write replaced the
text.

`Lingo::getTheField` resolves the designator to a cast member, refuses one that
is not a field, and answers `member->getField(prop)`; `Lingo::setTheField` is
`member->setField(prop, value)` (`reference/scummvm/lingo-the.cpp:2334-2398`).
`docs/LINGO_SURFACE.md` §5.1 has listed the fourteen properties a field
designator carries the whole time.

The write is the player-visible half. `set the textSize of field "globalmoney"
to 24` — Piposh 1's slot machine, in all three language builds — put the string
`24` where the money was. That is the failure mode this repo keeps naming: a
write that lands on the value it was *not* addressing round-trips perfectly,
because the next read of `the text` answers what the wrong write put there. The
harness sees it exactly that way with the fix reverted:

```
FAIL  and the member spelling agrees with the field spelling  (`the textSize of member` answered 12)
FAIL  and the text it was not addressing is untouched  ("33")
```

Both directions now go through `_member_prop_at` / `_set_member_prop_at`, which
are `lingo_member_prop` and `lingo_set_member_prop` split so that the reference
can be resolved by the caller. That is deliberate rather than tidy: a field
property that answered differently from the member property of the same name
would be a divergence invented here, and `the textSize of field "x"` and
`the textSize of member "x"` are one question in `lingo-the.cpp`.

---

## 66. `set the hilite of member` inverted the artwork of every member type; the reference draws it for a button and nothing else

**Status:** FIXED · **Area:** `scenes/preview/hilite.gd`
· reported from play, `rating` NAVIGATE.dir marker `thepool`
· covered by `tools/hilite.gd`, group "the script-set flag draws on nothing, and
the button arm is unreachable", which fails against the code before the fix

Zehava swam in reverse video: green hair, dark blue skin, the whole 77x84 sprite
photographically negative while everything else on the stage was right. `HOTEL.cst`
does it to her on purpose, in an ordinary `on exitFrame`:

```lingo
set the hilite of member "hotelrectang" of castLib 2 to 1
set the hilite of member 196 of castLib 1 to 1
set the hilite of member 197 of castLib 1 to 1
set the hilite of member 198 of castLib 1 to 1
```

196, 197 and 198 of castLib 1 are `NAVIGATE.dir`'s three frames of her.

**The reference stores this flag for every member type and draws it for one.**
`castmember.cpp:CastMember::setField(kTheHilite)` sets `_hilite` on the base class
whatever the type and never refuses, and `getField` answers from it — so the write
is legal on a bitmap and `the hilite of member` reads back what was written. There
is exactly one consumer: `text.cpp:355`, inside `case kCastButton:`, where it
becomes `MacButton::setHilite`. `bitmap.cpp` and `shape.cpp` do not contain the
string `_hilite`. So on anything that is not a button, Director stores the value
and draws the authored picture.

`hilite.gd:artwork` consumed the store with no type test, so every one of those
writes reached `Ink.invert`.

**Scope, measured rather than inferred from the one room.** `set the hilite of
member` appears at **39 sites across 21 containers** in `rating`, and at **0
sites** in `piposh`, `piposh-en`, `piposh-ru`, `piposh2` and `piposh-dream` — which
is why this survived: the corpus the port was built against never writes it.

**All 39 must draw nothing, and the number that settles it is not the sites but the
members.** *Rating* has **0 button cast members across all 19,074** it ships
(13,278 bitmaps, 5,338 scripts, 178 shapes, 158 fields, 93 film loops, 28
transitions); so do `piposh` (0 of 972), `piposh2` (0 of 897) and `piposh-dream`
(0 of 15,095). No site in any corpus can name a button because no corpus has one.
Most of the 39 name a hotspot rectangle (`rectang`, `hotelrectang`, `ribua`,
`recu` — shape members) and were being inverted unnoticed, because an invisible
rectangle looks the same either way; Zehava is the one the eye catches.

The fix is a type test — `hilite.gd:is_button`, the same `type_name == "button"`
question `interaction.gd:_is_button` asks — on the *drawing* path only. Gating the
**write** instead would have been wrong for a reason the file next door states:
`the hilite of member 196` would then read back 0 after being set to 1, which is
the round-tripping lie `preview/sprite_props.gd` exists to prevent. The harness
asserts both halves separately for that reason.

**The button arm is unreachable, which is stronger than the "approximation and
unverified" this said when it was filed.** ScummVM hilites a `MacButton` widget —
a Mac control redrawing itself inverted — not `Ink.invert` over authored artwork,
and this port draws no button widget. It draws no button member *at all*:
`preview/sprite_art.gd:texture_for` decodes bitmaps and shapes and returns null
for every other type, a button is type 7, and `hilite.gd:artwork` returns on its
first line when handed a null texture. So the arm has never run and cannot until
a button member becomes drawable.

That correction came out of the harness rather than from re-reading. As filed,
the check stamped `type_name = "button"` on the cached member and asserted that
`artwork` then inverted — and it passed while proving nothing, because
`is_button` reads `type_name` and `texture_for` reads `type`, so the stamp moved
only the first and what inverted was the **bitmap** path wearing a button label.
A member whose two fields disagree cannot exist; `director_cast.gd:204` derives
one from the other. `tools/hilite.gd` now stamps `type`, asserts the predicate
directly, and asserts the unreachability — so the day a button widget lands, the
check fails and points at the arm that has to be compared against Director.

One clause narrower than the reference, unreachable for the same reason and
recorded so it is not rediscovered: `castmember/text.cpp:320-322` reassigns
`type = kCastButton` when a **text** member sits on sprite type 8, 9 or 10
(`util.cpp:1361` — button, checkbox, radio), so Director's `setHilite` reaches a
field on a button sprite too. This port draws a field as glyphs, never through
`texture_for`, so that path is as dead as the other. None of Rating's 39 sites
names a field, so nothing in this corpus could reach it either way.

Two things this did **not** turn out to be, both measured before the artwork was
suspected, and worth keeping because they are the expensive half of the search:

- **The palette.** `MANAEGOZ.dir`'s config declares default palette `castLib -1,
  member 0`, which is `kClutSystemMac` by `cast.cpp:loadConfig`'s own `member -= 1`
  rule; no `CLUT` chunk, no palette member and no frame naming a palette exists in
  the container; and the port's *generated* system Mac table is byte-identical to
  ScummVM's `macPalette[768]` on all 256 entries. Nothing on that stage is
  recoloured by a palette choice.
- **The decode.** `tools/director_render.gd` draws the same member from the same
  bytes the right way up. That is what localised the defect to the preview's draw
  path and made the one-line minimal test — clear `_member_hilite`, repaint, look —
  worth running.

---

## 65. `the number of member X of castLib Y` drops the library, so a cursor pair resolves into whatever cast happens to have a bitmap at that number

**Status:** FIXED · **Area:** `scenes/director_preview.gd`, `scenes/preview/members.gd`, `scenes/preview/cursor.gd`
· reported from play, `rating` BLAEGOZ.dir, the שיחה button
· covered by `tools/cursor_cross_cast.gd`

```
set x to the number of member "cutcursor" of castLib "panel.cst"
set y to the number of member "cutcursor2" of castLib "panel.cst"
set the cursor of sprite 46 to [x, y]
```

`lingo_member_number` answered `_resolve_member(which, cast)`, which is
`_resolve_member_ref(...)[1]` — **the slot, with the library thrown away**. The
lookup had just found `cutcursor` in library 7 and then returned a bare `166`.
Member numbers are per library, so a number without its library is not an answer.

`Cursor.library_of` then guessed, as it is designed to for a number that genuinely
named no library: walk the libraries ascending, take the first with a bitmap at
that slot. In a movie with seven casts that always finds something.

| | the script named | the port resolved |
|---|---|---|
| data `166` | `cutcursor`, Panel.cst, **lib 7** | `leftcursor2`, **lib 1** |
| mask `167` | `cutcursor2`, **lib 7** | `aa`, Hotel.cst, **lib 2** |

One authored pair, two different wrong casts: a filled arrow silhouette from the
movie's own cast, masked by an unrelated bitmap from another, composed onto
opaque white. That is the white card under the pointer on the שיחה button.

**Every cheap check passed while this was broken**, and that is the part worth
keeping. Both members resolved. Both were named. Both were 1-bit bitmaps that
decoded. The image was 16x16 with something visible in it. `cursor_preview`
asserted all four and was green. The only observable that disagreed was the HUD's
`cur:custom 166/167`, and only because a player looked at it.

**The fix is a mechanism the port already had and this path was not using.**
`Members.pack_ref` carries `(library, slot)` in one integer — `the castNum of
sprite` has needed it since it must survive being handed back to `member()` — and
library 1 packs to the bare number, so every same-cast site in all six titles is
byte-identical and only cross-library reads move. Both spellings now pack:
`lingo_member_number` for `the number of member`, which has its own AST node, and
`members.gd:read_prop` for `member("x").memberNum`. Fixing one and not the other
fixes nothing, because the corpus writes its cursor pairs in the first.
`Cursor.where` decodes: a packed reference names its library outright, a bare
number still goes to `library_of`. That fallback is kept deliberately — it is what
closes entry 29, a cursor member living in a linked cast addressed by a bare
number.

**Latent, beyond cursors.** `set the castNum of sprite 18 to the number of member
"flameFire" of castLib "weapons.cst"` had the same hole and would have drawn
whatever library 1 holds at that slot.

**Coverage.** `cursor_preview`'s new "data and mask share one library" check is
red on the unfixed code — `[166, 167]: data lib 1 (leftcursor2), mask lib 2 (aa)`
— but only when pointed at Rating. Piposh 2 puts every cursor in the movie's own
cast, so on the gate's pinned corpus that check cannot fail whatever the resolver
does. `tools/cursor_cross_cast.gd` exists for that: it finds a cross-cast pair
rather than naming one, and **fails when the corpus has none** instead of passing
over an empty set.

---

## 64. A cursor pair that names no mask is composed opaque, so the artwork's paper is drawn as a white card under the pointer

**Status:** FIXED · **Area:** `scenes/preview/cursor.gd`
· found while investigating 65
· covered by `tools/cursor_preview.gd`

**This entry originally claimed Rating's שיחה button as its reproduction. That was
wrong and the claim was pushed before it was checked** — the שיחה button is
channel 46, its pair is `[166, 167]`, and it is entry 65. The two defects are
independent, look identical from the player's chair, and the first fix shipped
against the second one's symptom. Both are real; only one of them was the report.

`set the cursor of sprite 2 to [the number of member "talkcursor" of castLib 1]`
is a **one-element** pair, and `compose` read that as "no mask", which it turned
into "every pixel opaque". `talkcursor` is a 17x13 speech bubble drawn as a black
outline on white, so any sprite carrying it handed the OS a white rectangle with a
bubble drawn on it. The rule is that a missing mask member means **the data member
is its own mask**: black draws black, white is transparent.

**The reference implementation cannot be cited for this, and that is worth being
precise about** rather than glossing. ScummVM `cursor.cpp:Cursor::readFromCast`
composes each pixel as `(!mask || *mask) ? (*cursor ? 0 : 1) : 3` — so its
*intent* is the opaque reading, the same one this port had. Two lines above,
its bounds guard is `x >= cursorSurface->w || (!maskSurface || x >= maskSurface->w)`,
which nulls **every** pixel when there is no mask surface, so what it *delivers*
is a fully transparent cursor. Intends one wrong answer, produces a different
wrong answer. Neither is the artwork's.

**The artwork is the evidence.** Rating names one member without a mask at 31
sites, and where it does supply a mask the mask is a filled, dilated silhouette
whose only job is to make the drawing's white interior opaque:

```
#132 leftcursor           #166 leftcursor2 (its mask)
|       ##       |        |       ##       |
|      # #       |        |      ###       |
|    #   ########|        |    ############|
|   #  # #      #|        |   #############|
```

`WalkLeftCursor` settles it. It is a **solid black arrow**, 13x12, no outline and
no white it wants kept — opaque composition can only render that as a white card
with an arrow on it, and no artist ships that. `talkcursor` and `weaponCursor`
are the same story with outline art.

**Scope.** Only the *absent* mask defaults to the data. A mask that was named and
did not resolve still falls through to the opaque path: substituting the data
there would compose a plausible-looking cursor out of a library lookup that
failed, which is exactly the silent shape of entry 29.

| root | single-element `set the cursor` sites | of those, literal `[1]` |
|---|---|---|
| `rating` | 834 | 803 |
| `piposh` / `piposh-en` / `piposh-ru` | 3 | 3 |
| `piposh2` | 3 | 3 |
| `piposh-dream` | 0 | — |

So the visible change is Rating's 31 real ones. The `[1]` sites are the corpus's
"back to the arrow" and are almost all unaffected: member 1 is scenery in 100 of
Rating's 101 containers and `MAX_CURSOR_SIZE` refuses it. The one exception is
itself a small confirmation — **`BATZBERA.dir`'s member 1 is `WalkupCursor`,
12x13**, a real cursor that had been drawing as a white card too.

Second behaviour change, small and named because it is not a colour change:
maskless art that is entirely white now composes to nothing visible and reaches
the existing arrow fallback instead of installing a blank white square.

**The harness had the shape of this check and not the check.** `cursor_preview`
already asserted "no image is fully opaque", which never fired: `talkcursor` is
13 rows of a 16-row image, so the bottom three rows stay transparent and the
white card passes a whole-image test. The new group counts opaque **white**
pixels, and measures the maskless rule over every data member the movie uses —
composed again without its mask — rather than only over pairs that happen to be
single-element. Without that second set the gate's own corpus, whose every cursor
carries a mask, would have skipped the rule entirely. Run against the unfixed
code it fails on all seven of `AIR1.dir`'s members.

---

## 63. Nine tenths of Piposh Dream's audio was never indexed, because the index asked the filename and not the file

**Status:** FIXED · **Area:** `autoload/audio_director.gd`
· found by `tools/liveness_sweep.gd`

`AudioDirector._index_dir_recursive` took a file when its name ended in `wav`,
`ogg`, `mp3` or `aif`. **A Mac file has no extension**, and these are Mac discs.

| root | sound files on disc | indexed before | after |
|---|---|---|---|
| `piposh-dream` | 1,897 | **187** | 1,897 |
| `piposh` | 2,559 | 2,555 | 2,559 |
| `piposh2` | 3,141 | 3,141 | 3,141 |
| `rating` | 2,617 | 2,617 | 2,617 |

`piposh-dream` names its speech `sounds/dream2/1`, `sounds/dream1/100`, `FX/264`
— 1,711 extensionless AIFFs against 187 that happen to carry a suffix. The index
held the 187, so **every line of speech and every effect in that title was
unreachable**, in every room, from the first commit that walked the tree. The
movies asked and got nothing: a `sound playFile` that cannot be satisfied claims
the channel and leaves it empty, so a room that waits on `soundBusy` sails
straight through the line it was meant to speak. The only trace was
`Audio miss: dream2\1` in a log nobody reads, one line per request.

**The rule was already correct in the other half of the same file.**
`_load_stream` reads the container tag rather than the extension, with a comment
saying in as many words that a disc's filenames are as much a guess as its paths
are — `FX/DRILL.WAV` is an AIFF and `FX/BIRDS.AIF` is a RIFF, in the same folder.
The loader had known this from the start; the index had never been told. So a
file the loader would have decoded perfectly well never reached it.

`_has_audio_tag` now reads twelve bytes off the front of every file the extension
list did not already accept — `FORM....AIFF`/`AIFC`, `RIFF....WAVE`, `OggS`, an
`ID3` tag, an MP3 frame sync. **Twice**, because the first version only sniffed
files with *no* extension and `tools/audio_coverage.gd` found what that still
missed on the next root it was pointed at: `piposh`'s `SOUNDS/PSYDEAD/PSYSCREE.M`
is an AIFF called `.M`. There is no name-shaped version of this question that is
right. A Director container is `RIFX`/`XFIR` and matches nothing here; the index
build stays well under a second on every root.

**A second defect fell out of the harness**, and it is the silent one:
`_path_index` is keyed by the path with the extension *dropped* — deliberate, and
what lets a script that names `.aif` find a converted `.wav` — so two files whose
names differ only by extension collide on one key and the directory walk decides
which survives. Piposh 1 ships two such pairs and they are **not** duplicates:

```
SOUNDS/DOCDAY1/PIP18    941,246 bytes   29230d90...
SOUNDS/DOCDAY1/PIP18.AIF 106,170 bytes  68eef03a...
SOUNDS/SAFEDAY1/CAP10   170,682 bytes   a7c3276f...
SOUNDS/SAFEDAY1/CAP10.AIF 192,442 bytes 6e840645...
```

Different recordings of the same line, one of each pair simply unreachable.
`_exact_index` now holds the whole relative path *with* its extension and is
consulted first, so a request that names a file that is on the disc gets that
file and only a request that does not gets the stem tolerance. Whole paths only,
no tails: tails would invert the "whole path beats tail, longest match wins"
ordering that is the thing standing between this corpus and the wrong take of a
line.

**Covered by** `tools/audio_coverage.gd` — every file under the root whose *bytes*
say it is a sound must resolve through `AudioDirector.resolve_path`, and must
resolve to **itself**. The tool sniffs the bytes itself rather than asking the
engine which files are sounds, deliberately: any rule the engine applies it would
apply to both sides of that comparison, and the extension filter would have
passed such a test on the day it was wrong. Green on all four roots after the
fix; `sound_paths`, `sound_wait`, `sound_format_check`, `aiff_check`,
`audio_index` and `sound_survey` are green on `piposh2` before and after.

**Still open, and worth a look:** `tools/aiff_check.gd` does its own directory
walk and filters by extension too, so it has only ever examined 186 of
`piposh-dream`'s 1,897 sounds. It is in `gate.sh` on `piposh2`, where every file
has an extension, so it is green and covers everything there.

---

## 58. A bitmap wider than 4,095 bytes per row decoded off the end of its own buffer, on every repaint

**Status:** FIXED · **Area:** `director/director_cast.gd`, `director/director_bitmap.gd`
· found by `tools/liveness_sweep.gd`

`STRIDE_MASK` was `0x0FFF`. That is the identity for every row stride below
4,096 and a truncation for every one above, and the corpus the gate is pinned to
has no member above it — so the fault lived entirely in a title nothing had ever
swept.

Three members in six titles are above it, all three the panoramic backdrop of a
`piposh-dream` cat room: `hatul1.dir` #3 `stage1` and `hatul3.dir` #3 `hat3bk`
are 4943 x 400 and 4944 x 400 at 8 bits, `hatul2.dir` #3 `hat2bk` is 4940 x 400,
and their pitch words are `0x9350`, `0x9350` and `0x934C`. Masked to twelve bits
those became 848, 848 and 844.

**What that does.** `director_bitmap.gd:unpack` produces exactly `stride * height`
bytes, and `_blit_8` then reads `src[y * stride + x]` for `x` up to `width`. With
a stride of 848 and a width of 4943 that is out of bounds on the *first row*:

```
SCRIPT ERROR: Out of bounds get index '339200' (on base: 'PackedByteArray')
   at: _blit_8 (res://director/director_bitmap.gd:137)
       decode -> texture_for -> _texture_for -> paint_frame -> _paint -> _draw
```

A GDScript out-of-bounds read aborts the function it happens in, so the blit
stopped part-written and `Image.create_from_data` was handed the rest of the
buffer as it stood. The room drew a wrong picture, on every repaint, for as long
as it was on screen, and the only trace was an engine error in a log nobody
reads.

**The mask is `0x7FFF` now, and the corpus settled it rather than a document.**
`tools/scratch`-grade scans over all six roots, 119,013 bitmap members: the top
nibble of the pitch word is `0x8` everywhere (bit 15 is `DEPTH_FLAG`, "not
1-bit"), `0x0` for the 1-bit members, and `0x9` for exactly those three. With bit
15 alone removed, the remaining value equals the member's own width times its own
depth rounded up to an even byte count for **every one of the 119,013**, no
exceptions in either direction. Before the fix, three members had a stride
exactly 4,096 short of that; after it, none in any root does.

**Two changes, and the second is the one that matters next time.**
`director_bitmap.gd:decode` now refuses a stride shorter than the row its width
and depth need, and says so in `error`, instead of letting a blit index off the
end. Reported rather than clamped: clamping would draw *something* for a member
whose geometry the port has misunderstood, and the wrong picture is the failure
that survives review.

**Covered by** `tools/bitmap_geometry.gd` — every bitmap member of a root, stride
against the row it needs, plus the distribution of the padding so a title that
pads differently shows up as a new row rather than as a failure. Seconds per
title, in `gate.sh`'s `ALL`.

**How it was found**, because the route is the point: `tools/liveness_sweep.gd`
watches the playhead of every movie in a corpus and reports how much of each one
it managed to sample. The three cat rooms came back at **0% coverage** — the
repeated decode error made each paint slow enough that the score clock ran four
steps between two samples — and chasing "why can this movie not be sampled"
landed on the error. Nothing was looking for a decode bug. After the fix the same
three sample at 71-84%.

---

## 54. Rating's `inventorylist` is reset after all, and the reset is a literal inside `initDemo`

**Status:** CLOSED, no defect · **Area:** data / `rating`

Filed as "the shipped `Panel.cst` already has the first item collected, something
must reset it on New Game, and it was not found". It was not found because it is
not where the entry looked. The search was for an `inventorylistinit` member
beside the `TimeBaseinit`/`TimeBaseBackup` and `GuestBaseinit`/`GuestBaseBackup`
pairs. There is no such member. The reset is a **literal**, inside
`NAVIGATE.dir`'s `on initDemo`, on the same line-2 write the entry was looking
for:

```
put "0,0,0,0,...,0" into line 2 of field "inventorylist" of castLib "panel.cst"
```

`initDemo` is Rating's whole New Game reset — it also does the two field-to-field
copies the entry named — and it is reached in real play by `MAINMENU.dir` script
10, `go(1, "ARRIVEL.DXR")`, then `ARRIVEL.dir`'s `go(1, "navigate.dir")`, then
frame 1's `exitFrame`. The entry searched `NAVIGATE.dir` only as a container of
gating logic and never as the container that resets the game.

**Measured, not reasoned.** `tools/new_game_reset.gd`, in `gate.sh`'s `ALL`, boots
`--root rating --boot NAVIGATE.dir`, awaits real frames, and reads the live
fields: 6 checks, 0 failed. Both init->backup copies come back byte-identical
(4,069 and 1,223 chars), and line 2 of `inventorylist` reads 39 items, all `0`.
The check can fail — `od -c` on the extracted member shows the shipped line 2
beginning `1,` — so "all zeros" is the reset having happened and not the file
having been clean.

Of the entry's three candidate outcomes it is the first: the reset was in one of
the containers not searched.

**A data point for entry 53, which stays open.** A whole-field `put ... into field
"x" of castLib "panel.cst"` does land on the right member here. That is one
observation on one name in one cast, and 53's defect is that the library the
script named is discarded and the first cast to answer wins — which this cannot
rule out, because the name happens to be unique across the casts `NAVIGATE.dir`
loads. Same luck the original entry noted.

---

## 56. Director's `idle` event was never dispatched, so Rating's clock — and the story schedule that gates the game — never ran

**Status:** FIXED · **Area:** `scenes/preview/frame_loop.gd` · reported from play
as "most screens should not be accessible to the player until after they pass
Bila and the reception guy"

`grep -rni idle --include='*.gd'` over `scenes/ lingo/ director/ autoload/` found
two comments and **no dispatch site**. The port sent `idle` nowhere, and had
never sent it.

That is invisible to everything the gate measures. Nothing draws differently, no
handler errors, no `go` goes astray — the `lingo dispatched` tally simply has no
row for `idle`, and a missing row looks like a movie that has no such handler.

**What it cost.** `rating` hangs its entire story schedule off it. `NAVIGATE.dir`,
`BLAEGOZ.dir`, `BATZEGOZ.dir` and `HEZSAVE.dir` each carry the same handler:

```
on idle
  ClockScript()
end
```

and `Panel.cst`'s `ClockScript` (member 31, with a trailing comment that says in
as many words "the clockscript is being called from idle") is the clock:

- it advances `GlobalSecond` past a `the timer > clockspeed` guard, rolls
  `GlobalHour` at 60, and writes `h & ":" & s` into `field "GlobalTime"`, the
  clock the player can see;
- it fires seventeen timed story events out of a `case h&s of` — `opentimeout`,
  `explainsave`, `menacall`;
- at 30 and 60 seconds it calls `checkroom`, which does `put TIMEKEEPER + 1 into
  TIMEKEEPER` and reads `item ITEMKEEPER of line TIMEKEEPER of field
  "timebasebackup"` to decide **where the player is sent and which people are
  where**;
- and `if globalhour >= "19" and whichday = 1 then go to movie "karioki.dir"` is
  how day one ends.

None of it had ever run. **The player's own save is the proof:**
`saves/rating/quicksave.json` reads `timekeeper = 2`, `globalhour = 8`,
`globalsecond = 0` — the exact values `NAVIGATE.dir`'s `initDemo` and script 13
set at New Game — beside `itemkeeper = 14` and four items collected in
`objectsfound`. Hours of play, real progress, and the clock had not ticked once.

**The fix.** `frame_loop.gd:advance` now sends it once per step, guarded on no
pending jump. Both facts are the reference's: `score.cpp:336-338` sends it from
the interactivity block once per `Score::update`, gated on `!hasJump`, and
`lingo-events.cpp:552` queues it as a `kMovieHandler`, so it goes to the movie
script rather than to a sprite. It is sent *before* the pause check, because
`pause` stops the playhead and leaves the movie live, and the reference's idle
sits in a block a pause does not suspend.

**Blast radius.** `piposh2`'s only `on idle` is `HEZSAVE/master/MovieScript 209`,
whose entire body is `dontPassEvent()` — so the title the port was built on could
never have revealed this, and turning the event on cannot disturb it. That is the
same shape as entry 55: a path the reference title does not exercise, dead in the
port, and load-bearing in another title.

**Covered by** `tools/idle_clock.gd`, in `gate.sh`'s `ALL`. It asserts the event
is dispatched once per step on whichever root it is given — measured against
`prepareFrame`, the other once-per-step event, rather than against the harness's
own loop count, because the frame clock takes steps of its own while a harness
awaits real frames. Where the movie has an `on idle` it then asserts the *clock*,
on the globals the game reads: `GlobalSecond` advances, `GlobalHour` does not roll
early, and `field "GlobalTime"` is written. On `rating` that is 7 checks; on
`piposh2` it asserts the dispatch, says so, and stops rather than inventing a
clock the title does not have.

With the change reverted the harness reports `idle is dispatched at all (0 -> 0)`,
2 checks, 2 failed.

**What this does not claim.** That every screen the player reached was reachable
*because* of this. The eight hotel-map hotspots on `NAVIGATE.dir` channels 30-37
carry behaviours (`hotel2.cst` 242-249) that are bare `on mouseUp / go("flush1") /
end` with no gate inside them, so those are ungated in the original too. What was
broken is the schedule that moves the player and changes who is where, which is
the mechanism this title gates with.

**Measured and found correct along the way**, so nobody re-derives it: the New
Game reset works. `NAVIGATE.dir`'s `initDemo` copies `timebaseinit` ->
`timebasebackup` and `Guestbaseinit` -> `Guestbasebackup` and zeroes
`inventorylist`; it is reached in real play by `MAINMENU.dir` -> `go(1,
"ARRIVEL.DXR")` -> `go(1, "navigate.dir")` -> frame 1's `exitFrame`. Returns from
rooms come back through `backfrommovie`, which *writes* to `timebasebackup` rather
than resetting it, so re-entry does not wipe progress. `tools/new_game_reset.gd`
asserts all of it. `PERSONFOUND = "1,0"` at the start is set deliberately by
script 13 alongside thirteen zeros in `OBJECTSFOUND` — Bila first with everything
else locked, which is what the player expected.

**Unexplained, not chased.** `MAINMENU.dir` script 4 is `on exitFrame / go(1,
"startmov.dir") / end`, and no `startmov` exists in `games/rating` under any
extension. It is not on the New Game path — script 10's `go(1, "ARRIVEL.DXR")` is
— so nothing observed depends on it, but a frame script pointing at a movie that
is not on the disc is either a data gap or a dead branch and it has not been
established which.

---

## 55. The command spelling of `window` never created a window, and `open` lost the filename's extension before the resolver saw it

**Status:** FIXED · **Area:** `scenes/preview_lingo_host.gd` · reported from play
as "the suitcase of Egoz isn't opening in any screen during the entire game"

Egoz's suitcase is the bag on `rating`'s shared bottom panel, drawn in every
room. It is `Panel.cst` member 35 (the closed-bag bitmap, 115x102) on channel 45,
and the handler is that **member's cast script**, not a sprite behaviour:

```
on mouseUp
  global soundspath,effectspath
  sound playfile 2, effectspath & "openbag.aif"
  set the membernum of sprite 45 to the number of member "bagopen" of castlib "panel.cst"
  updatestage
  ...
  set the windowType of window "inventor.dir" to 2
  open window "inventor.dir"
end
```

**Two independent defects, either one fatal.** Both are in the same place: the
port handled `window(...)` — the *call* spelling — and not `window "x"`, the
*designator* and *command* spelling. Every one of Piposh 2's 54 opening sites uses
the call spelling, and every one of Rating's 12 uses the command spelling, so a
path exercised 54 times by the title the port was built on was never reached once
by the title it was being played on.

**A. Naming a window in a designator created nothing.** `set the windowType of
window "inventor.dir" to 2` parses to a bare String, and `set_window_prop` /
`get_window_prop` guarded on `is_window_ref(which)`, which requires a Dictionary
handle. A String failed the guard, the write was dropped, and — the part that
mattered — *no window was created*, so the `open` on the next line had nothing to
find. That contradicted the port's own rule, written at
`scenes/director_preview.gd:2400`: "Director makes the window object exist as soon
as it is named, which is what lets a script set properties on it and `tell` it
before `open`."

**B. `open window "x"` reached the resolver with the extension gone.**
`_first_window_key` returned `window_key_of(...)`, which is `get_basename()`, so
`"inventor.dir"` became `"inventor"`. Its two callers hand that to
`lingo_open_window` / `lingo_forget_window`, which take a **name**: they key it
themselves, and on a miss call `_create_window`, which resolves the name against
the disc. `DirectorPaths._index` is keyed by full filename, and
`ContainerName.spellings` refuses to try container extensions on a bare stem *on
purpose* (`director/director_container.gd:73-75`, "`day1` is not `day1.dxr`"), so
`resolve("inventor")` answered `""`.

The fix is not in `resolve` or `spellings` — the extension must not be discarded
upstream in the first place. `_first_window_key` became `_first_window_name` and
answers the most specific spelling it has: the raw string for a string argument,
the key only for a handle, where no name exists and the window is already in
`_windows` so the resolver is never reached. `window_key` is idempotent, so a key
passed back as a name is a no-op.

**Why this is one bug and not one room's.** `tools/window_survey.gd -- --root
rating --all`: 12 `open`, 52 `forget`, 56 `window`, 12 `windowType` writes, and
**all 12 opens were broken** — the bag in every room, plus all three `timeout`
interstitials. `Panel.cst` script 176 opens the inventory and then `tell`s it; the
`tell` parses as a call, so it *did* create the window, after the failed `open` —
`INVENTOR.dir` loaded there and was never shown, invisible rather than an
artifact.

**Reproduce, before and after:**

```bash
godot --headless --path . --script tools/click_trace.gd -- \
    --root rating --boot NAVIGATE.dir --movie NAVIGATE.dir --frame 1241 --channel 45
```

Before: `window inventor -> not found` / `open window inventor -> no such movie`.
After: `window INVENTOR.dir: 125 frames` and the window runs its own movie. The
same two failure lines are recorded inside `saves/rating/quicksave.json`, the
player's own session.

**Covered by** `tools/window_preview.gd`, which had 44 checks and now has 58: the
three command-form spellings are asserted apart, because the two halves failed for
different reasons and one combined check could not say which broke. It is asserted
on `joke.dxr` under `--root piposh2` rather than on `inventor.dir`, because this is
an engine rule and asserting it on the corpus the gate pins to is what makes it
one. With the engine change reverted and the harness kept, the run is 45 checks, 1
failed, on `naming the window in a designator created it`.

**Ruled out along the way.** Attachment (`mouseUp@cast x1` ran, channel 45, lib 6,
member 35). Dispatch (`clickable because member script declares mouseDown/mouseUp`).
The handler body — `openbag.aif` played and the sprite-45 write landed on `bagopen`
at its extracted 121x102. Filename case: `resolve` is index-based and
case-insensitive, and `resolve("inventor.dir")` answers `INVENTOR.dir` in the same
process that `resolve("inventor")` answers `""`. The extension was gone before case
could matter.

**16 was dodged here, not avoided.** (It was `bugs.md` 16 when this was written;
it is closed now and further down this file.) `the number of member "bagopen" of
castlib "panel.cst"` returns a bare int and the sprite keeps its existing library.
Channel 45 was already on lib 6, so `36` landed on `bagopen`. In a room where
channel 45 starts empty the same line resolves into the movie's own cast.

---

## 52. `pause` parked the playhead one frame past the frame that paused, so a hotspot scoped to that frame could never be clicked

**Status:** FIXED · **Area:** `scenes/preview/frame_loop.gd`,
`scenes/director_preview.gd` · reported from play as "i cannot collect the key
from the desk", from `.snapshots/2026-08-08T22-06-09.png`

`rating`'s `BLAEGOZ.dir` `EgozKey` is the hotel reception desk. The manager
finishes his line, the score pauses on the key lying on the counter, the cursor
becomes a take cursor, and clicking the key resumes the score — which is what
collects it. The room could not be finished: the click did nothing, for ever.

**The three scripts that are the whole pickup.** Frame 1079, `BehaviorScript 126`:

```
on exitFrame
  set the cursor of sprite 7 to [the number of member "takecursor" of castLib 1, the number of member "takecursor2" of castLib 1]
  pause()
end
```

channel 7's behaviour on that frame, `BehaviorScript 127`:

```
on mouseUp
  continue()
  set the cursor of sprite 7 to [1]
end
```

and frame 1080, `BehaviorScript 161`:

```
on exitFrame
  put "1" into item 1 of line 2 of field "inventorylist" of castLib "panel.cst"
end
```

`line 2 of field "inventorylist"` is the have-list: `OBJECTS.cst`
`BehaviorScript 71` and `156` walk its items and show inventory sprite `i + 1`
for each `1`. Frame 1085 plays `keys.aif`, 1089 the manager's follow-up.

**The defect.** `pause` is the one hold in Director that does not name a
destination. `go`, `go to the frame` and `play done` all write `_index` and set
`_held`; `pause` sets a flag and nothing else. The port read that flag at the top
of a step — `director_preview.gd:_advance` and `frame_loop.gd:tick` — and `pause`
is called from an `exitFrame` handler, so by the time it is set the step has
already committed to advancing. `frame_loop.gd:advance` went on to `_index += 1`,
`sync_frame_entry`, `prepareFrame` and `enterFrame` for the *next* frame, and only
the following step was refused.

The reference reads it between the two, in `Score::updateCurrentFrame`
(`reference/scummvm/score.cpp:443-452`):

```cpp
uint32 nextFrameNumberToLoad = _curFrameNumber;
if (!_window->_playbackPaused) {
    if (_nextFrame) { nextFrameNumberToLoad = _nextFrame; }
    else if (!_window->_newMovieStarted) nextFrameNumberToLoad = (_curFrameNumber+1);
}
```

`update()` sends `exitFrame` at `score.cpp:668-678` and calls
`updateCurrentFrame()` at `:706` in the same cycle, so a `pause` from inside the
handler is visible to the advance. `prepareFrame`/`stepMovie` and `enterFrame` are
guarded the same way (`:812`, `:827`), and `killScriptInstances` is skipped while
paused (`:701-702`) — Director explicitly keeping the paused frame's behaviours
alive to receive the click that resumes it.

**Why one frame was fatal here and invisible elsewhere.** Eligibility is a
behaviour interval test at the current frame (`preview/interaction.gd:181-191`,
§4.3 clause 4, and `:256-264`), and the author attached the take behaviour to
frame 1079 alone. Measured: the score rows for 1079, 1080 and 1081 are identical —
channel 7 is `1:3` at (131,326) on all three — while `_channel_at(104,317)`
answered 7 on 1079 and 0 on 1078, 1080 and 1081. So the port parked the playhead
on the one frame either side where the key was not clickable, `continue` was never
reached, and the room was a lock. `cursor.gd:54-55` does not filter the cursor
descent on eligibility, which is correct (`the cursor of sprite N` is a channel
property) and is why the player was still shown a take cursor over a sprite no
click could reach.

**The second half, and why it had to land in the same change.** With only the
guard above, holding on 1079 means the next runnable step sends 1079's `exitFrame`
again and `pause` runs again, so `continue` is undone before the playhead can
move: the 1080 lock becomes a 1079 lock. `Score::_exitFrameCalled`
(`score.cpp:672-675`) makes `exitFrame` at most once per frame, and it is cleared
in the unpaused `enterFrame` arm (`:827-828`). `director_preview.gd:_exit_frame_called`
is that flag, cleared in `_enter_frame_or_defer`. **Not on a frame-number change**,
which is the tempting spelling: `frame_loop.gd:sync_frame_entry` early-returns when
the index has not moved, so a latch cleared there would never clear under `go to
the frame` and every room in every title would stop polling what it waits on.
`score.cpp:519` is the reference being explicit about the same case — loading the
same frame takes the `else if (!_playbackPaused)` arm and reloads nothing, and the
flag is cleared anyway because the clear lives beside `enterFrame`.

**Measured before and after**, `tools/pause_holds.gd` against the pinned piposh2
corpus (`PIP2DATA/SAVELOAD.dir` `savegame2`, whose frame 8 is `on exitFrame /
pause()`):

| | before | after |
|---|---|---|
| the step that paused stayed on frame 8 | FAIL, left the playhead on 9 | ok |
| the playhead reads that frame afterwards | FAIL, `current_frame 9` | ok |
| a `mouseUp` behaviour is reachable on frame 8 | FAIL, none | ok, ten of them |
| the resuming step sent no `exitFrame` | FAIL, `exited 9` | ok |

and end to end in Rating, playing in to `EgozKey` rather than jumping: the
playhead parks on 1079, the click at (104,317) reports `ch7 sprite script
BehaviorScript 127 mouseUp:yes` — the same line the player's snapshot recorded —
`keys.aif` plays at 1085, `_field_text` gains
`res://games/rating/panel.cst:147`, and the room walks on to its next beat at
1132, whose frame script is the movie's second `on exitFrame / pause()`.

**Sites this was never about Rating.** `preview_lingo_host.gd:341-361` lists the
corpus's pause frames: `mainmenu.dir` 92, `hezsave.dir` 8, `psyday1.dir` 200,
`exchange.dir` 33, `docroom.dir` 301, plus `PIP2DATA/SAVELOAD.dir` 2 and
`ARCADE1`/`ARCADE2`/`SHUFFLE` in piposh2 and three frame scripts in `BLAEGOZ.dir`
alone. Every one of them parked on the wrong frame and ran a `prepareFrame` and an
`enterFrame` Director does not.

**What is still uncovered, deliberately stated.** `tools/pause_holds.gd` asserts
that an unpaused step still receives `exitFrame` for the frame it is on, which
catches a latch that is never cleared. It does **not** assert the sharpest form —
a frame holding *itself* with `go to the frame`, where `sync_frame_entry`
early-returns and a wrongly-placed clear would go deaf and nowhere else. Neither
`strtgame.dir` nor `PIP2DATA/CHESS.dir` reaches its `go(the frame)` within 4,000
headless steps (CHESS's sits inside a handler waiting on a move the harness does
not make), so there is no subject to assert against and the harness reports the
gap instead of carrying a check that is red for a reason no engine change can fix.
`--hold <container>` exists to point the search at a movie that does.

**One divergence identified and left in place, unverified.** The reference holds the
destination in `_nextFrame` and `updateCurrentFrame` skips the whole
`if (!_playbackPaused)` arm — the `_nextFrame` branch included — before clearing
`_nextFrame` to 0, so in Director a handler that calls `go` *and then* `pause`
loses the jump and stays where it was. This port writes `_index` eagerly in
`lingo_go_frame`, so by the time `pause` is read the jump has already happened and
cannot be discarded; the paused return here can only decline to advance further.
Nothing found in six roots does both in one handler, so this is a difference on
paper with no measured consequence, and it is written down rather than fixed
because the fix is a `_nextFrame`-shaped change to how every `go` in the port
works.

**One thing that was not reconciled.** The player's snapshot reads `frame 1079`,
and the HUD prints `_index` raw (`preview/stage_paint.gd:156-157`). The pre-fix
tree parks on **1080**, measured five ways — `_index` set to 1046, 1070, 1077 and
1078, and playing in with `lingo_go_label("EgozKey")` from the movie's own first
frame. Version skew was checked and excluded: before `7411d1ed` unnamed markers
were dropped, so `marker(1)` at 1051 was `Egoz4` (1176) and the room never reached
1079 at all. The debug step-back key was excluded too — it sets `_paused`, and
`stage_paint.gd:159` would have printed `PAUSED`. So the reading is unexplained by
either tree, and it is recorded here rather than resolved. It changes nothing about
the fix: both halves are required either way, and after the fix the playhead parks
on 1079, which is what the snapshot said.

---

## 47. The dwarf's mouth never stops, because the release of an auto-puppet was inferred from a value instead of an event

**Status:** FIXED · **Area:** `scenes/preview/sprite_state.gd`,
`director/director_score.gd` · reported from play as "his mouth keeps moving,
like we had with tofi", from `saves/piposh2/dwarf_speaking.json`

Same symptom as the Tofi half of entry 36, same channel, a sibling script — and
it survived that fix, because it arrives through the one gap that fix could not
close.

**The trace.** DAY1 `exitforest3`, frame 1551. Clicking (384,224) hits channel 18
and `WONDER/External/BehaviorScript 642`, whose whole body is `go("dnzclicktalk")`.
The clip's preamble, `DAY1/wonder/BehaviorScript 281`, does
`set the memberNum of sprite rin to the number of member (xxx & who) of castLib
"wonder"` with `rin` = 18 and `xxx` = "b" — the talking loop. The clip plays its
line and returns with `go(lastmark)`. Channel 18 kept showing the script's member
for the rest of the movie.

**Why the entry 36 fix does not cover it.** That fix removed `membernum` from the
release exemption, so a script's member swap is given back when the score moves
the channel. The score does not move this one. Measured off the delta stream:

| where | score, channel 18 |
|---|---|
| `exitforest3` 1546-1556 | `5:596` `adnzlop1` |
| `dnzclicktalk` 2613-2614 | `5:596` `adnzlop1` |

Same member on both sides, so the port's release test — "the member the override
was taken against is not the one the score now holds" — was false every frame and
the write was never taken back.

**The rule it was standing in for.** Director releases an auto-puppet **when the
score writes that property**, whatever value it writes. The reference does this
with `Sprite::releaseAutoPuppet`, called once per frame change from `Score::update`
and handed `_copyBackMask` — the set of fields *the frame's own delta touched*.
Value never enters it. Frame 2613's delta writes channel 18's whole record and
frame 1548's writes it again, so in Director the release fires twice on this
journey; the port could see neither, because it reads the accumulated channel
buffer, where a field rewritten with the value it already held is indistinguishable
from a field nobody wrote.

**The fix, in three parts.**

- `director_score.writes_between(from, to)` answers which fields of which channels
  the score writes moving the playhead between two frames, from the delta byte
  ranges. Three cases, all the reference's `Score::loadFrame`: nothing before the
  first frame is entered; the union of the deltas of `from+1 .. to` going forward;
  and *everything on every channel* going backwards, because Director cannot walk
  a delta stream in reverse and rebuilds the frame from the start of the movie.
- `sprite_state.release_auto_puppets` is `Sprite::releaseAutoPuppet` transcribed
  into this port's two vocabularies. A whole-sprite puppet is skipped, exactly as
  `setAutoPuppet` does nothing while `_puppet` is set; `visible` is untouched,
  because in Director it is channel state and no score write can reach it.
- It is called from `frame_loop.sync_frame_entry`, which is this port's "the frame
  number changed" event and mirrors the `if (_curFrameNumber != nextFrameNumberToLoad)`
  the reference hangs the same call on. Every path that moves the playhead goes
  through it, and it runs before the new frame's scripts.

`effective()` is a pure read again as a result, and the `peek` flag entry 36 had to
add — a second code path through one rule, because the preloader could not be
allowed to ask a question that mutated — is gone with it. So is `_member`, the
bookkeeping the value comparison needed.

Attributed by disabling the release call alone and rerunning the harness: channel
18 ends showing 597 where the score says 596. With it, 596. `bugs.md` 36's
`tofclicktalk` case still passes on its own terms (`score 196, showing 196`) —
that one changes the member, so both the old rule and the new one fire.

`tools/puppet_persists.gd` covers it, and the check that covers it is the one that
used to print "the score never moved channel 18, so this room does not test the
release" over the room the bug was in. It now asks whether the score *wrote* the
channel, so `exitforest3` is a live case rather than an excused one.

---

## 42. SKIP moved the playhead and left the voice playing, so in piposh it did nothing at all

**Status:** FIXED · **Area:** preview, `skip_to_end` · **not the mis-landing of
32 and 37** · reported from play as "the skip button doesn't work in piposh",
with "nothing at all, ever, from the first press"

Entries 32 and 37 are both about *where* SKIP lands. This is about what it fails
to let go of, and it is why the same button that misbehaves visibly in piposh2
and rating looks completely dead in piposh 1.

**What holds a piposh frame is a sound, not the clock.** Every line of speech in
this title is gated on the voice channel:

```lingo
on exitFrame
  if not soundBusy(1) then go(marker(1)) else go(marker(0) + 1)
end if
```

The `else` is the hold — the segment loops on itself until the voice finishes.
`skip_to_end` released `_clock` (which was holding nothing) and jumped to the
next marker, but never stopped the sound, so the *destination* segment ran the
same test against the same still-playing voice and waited it out again. The
playhead moved and the player heard the identical line to its end. That is the
whole report.

`soundBusy(1)` is the gate 28 times to `soundBusy(2)`'s once in STRTGAME, and 4
to 0 in BRJDAY1; channel 2 is the background song (`songs\strtgame\songa.aif`),
which these movies stop themselves — `sound stop 2` appears in DAY1 six times.
So the fix stops channel 1 and leaves 2 alone.

**The measurement needed the movie's own clock, and the first one that did not
proved nothing.** Driven by `_advance` in a tight loop, score time compresses to
zero while the audio runs on wall-clock, so "jump" and "stop the sound" came out
identical — f105, 28 distinct frames, both — and the comparison decided nothing.
Run in real time from a settled talk in BRJDAY1, the levers separate cleanly:

| lever | leaves the segment | voice still playing |
|---|---|---|
| untouched | 1334 ms | no, it ended |
| jump only (before) | 18 ms | **yes** — so the next segment re-waits |
| stop channel 1 | 35 ms | no, by the movie's own `go(marker(1))` |
| both (after) | 17 ms | no |

**The stop is added to the release and the jump, not put in their place.** Entry
32 argues for dropping the jump entirely; piposh2's EXODUS is why that is still
wrong. It is not gated on a sound at all, and stopping the channel there moves it
7649 ms against a 7793 ms baseline — nothing. The jump alone carries EXODUS, the
stop alone carries BRJDAY1, and neither covers the other.

Reproduce, windowed, with the three-lever probe in the commit that added this:

```
$ godot --path . --script <probe> -- --file PIPDATA/BRJDAY1.dir
  skip   f73  busy=true  -> segment end f82  left after 8 ms  voice still playing: false
```

**One measured side effect, and it is the sweep rather than the engine.**
`tools/skip_state.gd --all` on this root goes from 4 failures to 7: LOLODAY1,
LOLODAY3 and ONBOARD now park. All three end their talk with `if not
soundBusy(1) then play done`, so cutting the voice fires `play done` — and the
sweep enters every movie with `lingo_go_movie`, leaving `_play_stack` empty, so
there is nothing to return to. That is entry 32's DAY1 mechanism, reached sooner.
A player does not reach them that way: DAY1 names `loloday1` and `stimday1` next
to `play frame`, which pushes a return address. Entered as the hub enters them,
all three **return to DAY1** rather than parking, which is what SKIP on an
interlude should do:

```
in the clip  : LOLODAY1.dir f32   play stack depth 1
after SKIP   : LOLODAY1.dir f32 -> DAY1.dir f38   visited 61 distinct place(s)
```

The baseline's pass on those three was the harness compressing score time so the
voice never finished; the park was already there, one second later. Worth fixing
in `skip_state` rather than in `skip_to_end`: the sweep should enter a `play`
clip with a return address, or skip clips it can only open cold.

---

## 34. Film-loop children drew out of the wrong cast file, so Goldolin was Tofi

**Status:** FIXED · **Area:** container decode / film loops ·
`director/director_film_loop.gd`, `director/director_score.gd`,
`director/director_cast_table.gd`, `scenes/preview/film_loop_view.gd` ·
reported from play as "on murder1 and some other places I see assets being
replaced by the wrong asset — there are places where I suppose to see assets from
GOLDOLIN.cst and I see from TOFI.cst"

The fifth instance of the class this port keeps re-learning: **a member number is
per cast, so resolving one in the wrong library returns a stranger rather than
nothing.** Previously `searchfunk` reading names in library 1, the `island2`
members, the film-loop `won`/`wonder` prefix match, and frame scripts found in
whichever cast happened to share the number. None of them raised an error,
because all of them found something.

**The measurement.** MURDER1, the three loops its score actually plays that name
another cast:

| channel | frames | loop | drew from | should draw from |
|---|---|---|---|---|
| 3 | 107-281 | `Internal:10 goldolin left` | `tofi` (4) | `goldolin` (2) |
| 17 | 378-384 | `Internal:9 goldolin right` | `tofi` (4) | `goldolin` (2) |
| 14 | 471-480 | `Internal:15 hezi right + angry` | `goldolin` (2) | `hezi` (3) |

MURDER1's libraries run internal, goldolin, hezi, tofi; its `ccl ` runs tofi,
goldolin, hezi. A child of `goldolin left` carries `ccl ` index 1 — goldolin —
and was read as index 0. Every child was one cast early, so Goldolin walked on
screen wearing Tofi's frames.

**Root cause, in three parts, each silent on its own.**

1. `director_film_loop.gd:children` subtracted one from the index. The index is
   zero-based and `tools/director_film_loops.py:_frame_sprites` — the reading
   validated against 2,145 children — takes it as it stands. The subtraction was
   there to work around (2).
2. `director_score.gd:_snapshot` folds `0xFFFF` to 1, which is right for a
   movie's score and lossy for a loop's, where 1 is a real `ccl ` entry. With
   "my own cast" and "entry 1" arriving as the same value there was nothing left
   to tell them apart. It now also carries `cast_lib_raw`, unfolded, and the
   loop reader uses that.
3. `scenes/preview/movie_session.gd` read one `ccl ` list, from the **movie**,
   and every loop was parsed against it. A film loop is a cast member, so a loop
   in a linked cast indexes *that file's* list — which for a `.cst` in this
   corpus is usually absent, meaning its children name no cast but their own.
   MURDER1's `MASTER:invright` (the inventory hand) and `HEZI:hezr` both drew out
   of `tofi`, because tofi is what MURDER1's own first entry happens to be.
   `DirectorCastTable.cast_list_for` now answers per library, out of the
   container that library lives in.

A fourth defect fell out of the same measurement. `read_cast_list` scanned the
`ccl ` payload for length-prefixed printable strings instead of reading its
offset table, because the table arithmetic had been got wrong once and a scan
looks robust. It is not: the payload holds bytes that scan as entries and are
not. ALLIN's chunk scanned to a spurious `"` ahead of its seven real paths — one
more shift of every index — and lost the eighth; DAY1's scanned to
`...\PIP2DATA\won` where the entry is `C:\...\PIP2DATA\wonder.cst`, which is
what the `won`-as-a-prefix-of-`wonder` incident (entry 15) was actually made of.
The table read (`count+1` big-endian u32 offsets from 6, base searched) recovers
both and agrees with the scan on the other 26 `ccl ` chunks in the corpus.

**Corpus impact.** Over the 12,103 distinct film-loop children reachable from all
61 movies, measured against an oracle from outside the resolution rule — an
unstretched child's recorded rect equals its member's natural size, so at most one
library can hold that member at that size:

| reading | children the oracle decides | agreeing |
|---|---|---|
| before | 9,824 | 6,006 |
| owning container's list, index still decremented | 9,824 | 8,511 |
| and the index taken as it stands | 9,824 | 9,628 |
| and the `ccl ` offset table read properly (shipped) | 9,823 | 9,817 |

The last denominator moves by one because the `ccl ` parse decides which children
survive at all. So **3,818 of 9,824 decidable children were resolving into the
wrong cast**, in 29 of the 61 movies. They were not blank: every one of them drew
a real member of a real cast, which is why this read as an animation glitch
rather than a fault.

The six residual disagreements are all GARDUG's `Internal:57 L`, whose children
are numbered for the `heznigt` library embedded beside the internal one in the
same file while the record says `0xFFFF`, "my own cast". No reading of that
container can reach `heznigt` — GARDUG's `ccl ` is a single zero-length entry —
so this is the data, and GARDUG's score never puts loop 57 on a channel. Entry 20
(WONDER's degenerate `ccl `) is a different case and is still open: there the
children name a cast that is not in the corpus at all.

**Covered by `tools/film_loop_cast.gd`**, which sweeps the whole corpus and is the
gate this class has never had. Its oracle cannot agree with the code by
construction, and reverting any one of the four parts turns it red: the index
(497 of 998 indexed children wrong), the per-container list (147 libraries read
against the wrong file, 1 child wrong), the offset-table read (189 wrong, 2 `ccl `
entries naming no linked cast), and `cast_lib_raw` (the indexed population goes to
zero — which the check asserts against, because "0 wrong" is also what a dead
check prints).

---

## 33. `go to frame X of movie Y` read its own command word as the destination, so the save screen looped for ever

**Status:** FIXED · **Area:** Lingo host, `go` ·
`scenes/preview_lingo_host.gd:_go` ·
reported from play as "save (piposh2) — when I enter it, it gets stuck in a weird
loop, I see black and non-black"

The repeating trace, from `tools/movie_churn.gd` before the fix:

```
SAVELOAD.dir:5 -> HEZSAVE.DIR:27 -> SAVELOAD.dir:0 -> ... -> SAVELOAD.dir:5
  -> HEZSAVE.DIR:27 -> SAVELOAD.dir:0 -> ...
114 movie changes in 400 steps, across 2 movies, 30 in the worst 100-step window
```

**Root cause.** `go` is a command, so the parser puts the command's own bare words
in front of its evaluated arguments (`lingo/compile/lingo_parser.gd:_parse_optional_of_movie`
appends the movie as a plain second argument, with no marker word). `HEZSAVE.DIR`'s
`fillnames` says

```
go to frame "savegame2" of movie cdsavepath & "saveload.dxr"
```

which reached the host as `["to", "frame", "savegame2", "pip2data\saveload.dxr"]`.
`_go` filtered the words one name at a time — it dropped `to` and `movie` and knew
nothing about `frame` — so `frame` stood in the argument position and was read as
the destination *marker*. No movie has a marker called `frame`, and
`director_preview.gd:lingo_go_movie` falls back to frame 0 on a label it cannot
find. `SAVELOAD` frame 0 is five frames ahead of `savegame`, whose `exitFrame`
sends the playhead straight back into `HEZSAVE` — so the two movies changed places
every six steps for ever. `MovieSession.forget_previous` drops the textures on each
hop and `_draw` clears the stage to black before painting, which is the black /
non-black flicker the player saw. Nothing was wrong with the renderer, and nothing
was wrong with the window: `SAVELOAD` **is** a Movie-In-A-Window here, correctly,
and it was the window's own playhead that never settled.

**The general rule applied.** A command's bare words are a *set*, and the set is
the parser's, so `_go` now splits the leading run of `Grammar.COMMAND_WORDS["go"]`
off the front and reads the destination from what is left. The word list is not
restated — it is the same constant the parser emitted them from, so the two cannot
drift apart again, which is exactly how this survived: `lingo/lingo_host.gd:_go`
had already grown its own strip list and the preview's copy had not.

Two more defects fell out of the same rule:

* `MASTER.CST`'s `go to frame item 1 of nextroomdata` — how a room puts the player
  back where they came from — passes a *marker name* as `go`'s frame argument.
  Reading `frame` as the destination made the old code take the "frame with a
  non-numeric argument" branch and **hold** instead of jumping.
* The movie-name test spelled `.dir`/`.dxr`/`.cst` by hand and so did not recognise
  `.dcr`, `.cxt` or `.cct`. It now asks `director_container.gd:is_container`, which
  is the engine's one list.

`go to frame ... of movie ...` appears at seven sites in this corpus: the four
`HEZSAVE` exits (`savegame2`, `loadgame2`, `aftersave`, `afterload`) — that is
every exit from the save/load round trip, so the entire save screen was unreachable
— plus `go to frame "path5" of movie "day1.dir"` twice in `MASTER.CST` and one dead
`mainmenu.dxr` branch.

**Covered by** `tools/movie_churn.gd`, which asserts a *rate*: no more than four
movie changes in any 100 score steps, on the stage and on a Movie-In-A-Window. It
fails with the trace above when `_go`'s word set is put back to `{to, movie}`.

---

## 31. Sprites drew at the score's rect, which is authoring residue unless the author stretched them

**Status:** FIXED · **Area:** preview renderer ·
`scenes/preview/sprite_geometry.gd:drawn_size` ·
reported from play twice — Piposh 1 as "some sprites stretch outward and back in
again, only some elements, only sometimes", Piposh 2 as art with a visibly wrong
aspect for a run of frames around `DAY1` frame 1780

`drawn_size` returned the sprite record's own width and height whenever it stated
any, and fell back to the member's natural size only for a degenerate rect. It now
returns the **member's** natural size unless the author resized the sprite — the
stretch flag, a script write, or a shape or text member, which the reference
excepts by type.

**What the score actually holds.** `PIPDATA/WRESTLE.dir` channel 9 settles it
without reference to anything outside the container. The channel runs a wrestler's
animation, members `a1`..`a4`, natural 369x303, 375x308, 379x312, 379x313. The
frame stream writes the channel a full 48-byte record on two frames out of every
three and four bytes at offset 16 on the third:

```
f2  full record  member a1  loc 372,193  size 556x438
f3  full record  member a1  loc 372,193  size 556x438
f4  4 bytes @16                          size 369x303   <- a1's own size
f5  full record  member a2  loc 372,194  size 556x438
f7  4 bytes @16                          size 375x308   <- a2's own size
```

556x438 is not any of their sizes, it never changes, and the stretch bit is clear
throughout. A rect that is the member's own in the middle of a span and a constant
foreign value at the frames the record is rewritten in full is not a size anybody
authored. Channel 10 shows the same thing carrying *between* members: on the frame
`egozbox2` arrives the rect is 409x323, which is the natural size of the member the
*neighbouring* channel is holding, and on the frame `foedizzy` arrives it is
148x254, which is `egozbox2`'s.

`PIPDATA/INVENTOR.dir` shows the other half of the same symptom, the one nobody
would file as "stretching". Member `dot` is a 1x1 bitmap. Its residue is 1x1, and
channels 10 and 11 — members 92x17 and 78x14 — carry it, so those two sprites drew
as a single pixel each. Frame 0 hands `dot` 640x480, so the same member is also a
full-stage rectangle for one frame.

The Piposh 2 reproduction is `PIP2DATA/DAY1.DIR` channel 2, the walk-in to the
tennis court. It plays four backdrop members in turn at one registration point:
`island2` 25, 26, 27, 28. Three of them carry a rect exactly equal to their own
size; 27 carries 620x150 against a 456x150 member, and drew 1.36x wide for 59
frames. At its natural size it lands flush against the right edge of the stage;
at the score's it runs 115 px off it.

**Why the two hypotheses this was filed with are still disproved and it was still
a bug.** Neither was about the drawn size in the score-playback path. The
disproof recorded against hypothesis 1 — that ScummVM's `sprite.cpp:replaceFrom`
copies the record's width and height with no natural-size reset, and the reset
lives only in `channel.cpp:setCast` — is accurate as far as it goes, and it is why
`_drawn_size` was left alone. What it missed is that `setCast` is not a Lingo-only
path: `Sprite::setCast(memberID, replaceDims)` takes `replaceDims = !_stretch`, and
`Channel::setCast` is what *every* route to putting a member on a channel goes
through. `setCast` excepts exactly two cast types from the reset, `kCastShape` and
`kCastText`, and that exception list is now the port's.

**Why the export comparison that argued the other way is no longer evidence.**
`tools/drawn_size.gd` scored the two rules against
`assets/render_model/<movie>/frames.json` and reported the score's own rect
reproducing the export's top-left on ~100% of records. Two things are wrong with
that, and either alone is fatal:

- `frames.json` carries the **exporter's** `x`/`y`, derived from the same rect by
  the same expression the harness was scoring. Agreement is arithmetic, not a fact
  about Director — the circularity `porting-fidelity-verification` is about.
- the renderer that drew from that export **never used those numbers**.
  `RenderModelLoader._resolve_sprite_rects` rewrites the rect and the top-left of
  every unstretched sprite at load — 22,806 records in Piposh 2 — and that
  rewrite *is* this rule. The picture known to have been right was already the
  corrected one, and closed entry 14 was closed on a screenshot of it.

The export has since been deleted (`e340f212`) and that renderer retired
(`ead3cee2`), so `drawn_size.gd` could no longer run at all. It is gone, replaced
by `tools/drawn_size_stability.gd`, which asks nothing of any export and asserts
instead that **a sprite the author did not mark as stretched must not change size
while its member and its position hold still**.

This also removes the "two populations behave oppositely" note in
`film_loop_view.child_sprite`. They never did — the main score was the odd one out.

Measured before and after, over every container in both corpora:

| | Piposh 1 | Piposh 2 |
|---|---|---|
| sprite records resolving to a member with a size | 1,886,088 | 816,318 |
| unstretched records whose rect is not the member's | 243,522 of 1,779,608 (13.7%) | 21,093 of 729,473 (2.9%) |
| runs that pulse, before | 11,418 | 419 |
| runs that pulse, after | 0 | 0 |

```
$ godot --headless --script tools/drawn_size_stability.gd -- --all
$ godot --headless --script tools/drawn_size_stability.gd -- --file PIPDATA/WRESTLE.dir
```

**Not fixed, and deliberately.** The `stretch`-set population is untouched: 32,126
Piposh 2 records and 87,717 Piposh 1 records still draw at the score's rect,
because that is what the flag is for. Whether *those* rects are all authored is a
separate question nobody has asked. Text and shape members likewise keep the
score's rect, following the reference's own exception list, so a field that
auto-expands is still governed by whatever `text_art.gd` does with it.

---

## 29. The preview resolved cursor member numbers in cast library 1 only

**Status:** FIXED · **Area:** preview cursor ·
`scenes/preview/cursor.gd` · found while fixing the preview's custom cursors

`member_image` read `_table.get_member(1, ...)` and `_table.file_for(1)`, the
movie's own cast and nowhere else, and `compose` took the hotspot from library 1
as well. Cursor art living in a linked cast was therefore never found: the pair
composed to null, `install` fell back to the arrow, and nothing was reported.

**Fixed as the general rule, not for a case.** `Cursor.library_of` walks the
libraries the movie can address in ascending number, and library 1 is always the
movie's own, so the movie's own cast still answers outright whenever it holds art
at that number — this can only add answers where there were none. `compose`
resolves the library once and reads both the picture and the registration point
from it, or a data member found in a linked cast would take its hotspot from
whatever shares its number in the movie's own.

The library cannot come from the value: a cursor pair carries member *numbers*,
and `member("able1").memberNum` has already dropped the library the name was
found in. Resolving the number the way Director resolves a bare `member(N)` is
the only reading available.

`tools/cursor_preview.gd` now prints the library each pair resolved in, so a
future movie that reaches into a linked cast says so rather than being invisible:

```
$ godot --headless --script tools/cursor_preview.gd
measuring AIR1.dir
   [6, 7] -> wlkcur1 of lib 1: 16x16, 126/256 opaque, hotspot (7.0, 9.0)
```

Still library 1 everywhere in this corpus, which is why the entry was open with
no failing case for so long. Measured across all 61 Piposh 2 movies: every movie
that assigns a cursor resolves it inside its own cast, and every assigned pair
composes. The rule is now right regardless.

---

## 22. Finishing the cliff meeting restarted the day, because `go(<marker>, <movie>)` dropped its marker

**Status:** FIXED · **Area:** interpreter host, `_go` · **general, not one movie** ·
the dialogue prompt was never the bug

Kept here rather than moved to Closed, and kept at this number: `AGENTS.md`,
`tools/lib/driver.gd`, `tools/probe.gd` and `tools/cliff_meeting.gd` all cite
"bugs.md 22" for the real-time lesson in 2 below, and the MURDER1 decompilation
gap at the end of the entry is still open.

Reported three times from play. The third report — "when the scene ends it
teleports you back to the beach entrance and you have to do the whole thing
again, in an endless loop" — was accurate, and the two earlier verdicts on this
entry were both wrong about *where* the loop was. It is not at the prompt. It is
at the handover, one frame past where the harness stopped looking.

**Root cause.** `MURDER1 BehaviorScript 45`'s `on exitFrame` marks the meeting
done and hands the player back to the room they left:

```lingo
put "done" into item 1 of meetings
newsyz = 9
nextroomdata = "clif2,91,336"
go("clif2", "day1.dir")
```

`_go` in `lingo/lingo_host.gd` read that first argument as a frame number:
`goto_movie("day1", LingoValue.to_int("clif2"))`, which is `goto_movie("day1", 0)`
— frame 1. DAY1 frame 1 carries `BehaviorScript 56 - init all`, whose `on
exitFrame` resets `meetings` to `"murder1,hatday1,…"` when `globalday = 1`,
empties `objectsfield` line by line, sets `nof = "shore2"` and ends on
`go("shore2")`. So finishing the meeting reset the day's progress, took the
player's inventory and put them at the beach entrance with the murder pending
again — and walking back to the cliff fires `peoplefunk` → MURDER1 once more, for
ever. Authentic behaviour for frame 1, which is where EXODUS starts a new day; the
bug is arriving there.

Measured with the same harness either side of the one-branch change:

| | before | after |
|---|---|---|
| lands at | `DAY1:0` — frame 1, no label | `DAY1:1913`, `clif2go` |
| 30 s later, untouched | `shore2go` | `clif2go` |
| `meetings` | reset to `murder1,…` | `done,…` |
| the item carried in | wiped | still there |
| walking back to `clif2` | MURDER1 again | stays in DAY1 |

**The fix is general, which is the point.** `go`'s first argument is a frame *or* a
marker, and the corpus splits cleanly. Sweeping every `go`/`play` call's argument
shapes in `data/lingo/*/*.json`:

| shape | count | means |
|---|---|---|
| `go(<marker>, "<movie>.dxr")` | **58** | put the player back at that room |
| `go(<frame>, "<movie>.dxr")` | 50 | start that movie from the top |
| `go(<marker>, <expr>)` | 10 | same, with `the moviePath &` prefixed |
| `go(<expr>, <expr>)` | 5 | both computed — `whatodoeveryframe`'s `go(item 2 of ifmovie, item 3 of ifmovie)`, the general walk-into-another-movie handover |

The 58 cover 34 distinct `(marker, movie)` pairs, every one of which resolves in
its destination's `labels`: `HATDAY1 → gate`, `ARCADE1 → arcade`,
`TENNIS → exitforest2b4`, `SLEEP1 → newmorning`. All of them, plus the 10 and the
marker cases among the 5, landed on frame 1 of the destination. Only MURDER1's has
been driven end to end, so the rest are a prediction no harness covers yet — the
`go(item 2 of ifmovie, item 3 of ifmovie)` one especially, since it is not one
scene but the general form. The 50 keep the path they had, EXODUS's
`go(1, "day1.dir")` among them, which is the legitimate day start.
`LingoValue.to_str(first).is_valid_int()` is the discriminator, and the sweep is
cheap to redo.

**Why a passing harness did not see it.** `tools/cliff_meeting.gd` ran with
`until_movie_change: true` and then asserted `movie == DAY1`. Which movie is
loaded is not where the player is standing — DAY1 frame 1 *is* DAY1 — and the
reset happened in the seconds after the assertion. It now asserts the landing
label, that the label still holds 30 s later with nothing clicked, that `meetings`
and the inventory survive, and that walking back into the room does not replay the
meeting. That last check is the loop's closing edge, and nothing had ever driven
it.

**This is entry 23 in reverse, and the pairing is the useful part.** Frame 846's
`frame_script` is that same `BehaviorScript 45`, and the exporter lifted its
destination correctly: `{kind: movie, value: "day1", label: "clif2"}`. So the
export held the right answer, the interpreter ran the script, navigated, and
`game_step`'s `lingo.host.navigated` check handed it the win. Neither source
is authoritative: 23 is the export overriding a script that decided not to move,
this is a script overriding an export that knew where to go. When the two disagree,
the disagreement itself is the bug report.

Reproduce: `godot --headless --script tools/cliff_meeting.gd` (~3 min; real time
is load-bearing, see 2 below).

**Regression check.** `tools/lingo_walk_diff.gd` is byte-identical either side —
`identical outcome: 85/117`, the same 32 differing rows in the same order — so the
change moves nothing in the walk cases. Read that as a regression check and not as
confirmation: the differ clicks a hotspot and runs 260 synthetic ticks, which never
reaches a cross-movie handover, so it cannot see the path that changed. The
pass/fail set also stays green: `smoke`, `puppet_visibility`, `room_names`,
`collectables` (22), `cursors` (44), `sprite_channels`, `sprite_stretch`,
`film_loop_stretch`.

### The prompt itself is authentic — this part of the entry stands

**MURDER1 stalls at frames 489-508, and that span is a dialogue prompt.** Frame
508's exported nav is `{kind: marker, rel: 0, offset: 0}` — Director's
`go to marker(0)` — which resolves to 489, so the last twenty frames cycle. There
is a second one at 676-695. Both are wait-for-click loops and both are authentic:
the score offers three subtitle lines on channels 41/42/43, each carrying its own
`mouseUp` handler (`CastScript 31/32/33` → `go("choose1a")`, `37/38/39` →
`go("choose2a")`), and the playhead waits until one is clicked. The player has to
pick a line. Nothing advances on its own, by design.

**Measured end to end.** Entering DAY1 at `clif2` with `murder1` pending fires
the meeting; clicking one line at each of the two prompts leaves MURDER1 after
146 s and marks the meeting done. So the scene does complete and the prompt is not
a stall: the earlier **PROGRESSION BLOCKER** verdict on the prompt was wrong. What
that measurement then read as "and returns to the cliff" was the *movie* name, not
the frame — see the root cause above.

**The port renders the prompt and the hotspots sit on it.** The three lines draw
in the subtitle panel, `clickable_sprites()` offers all three, and a screenshot
taken with `AppSettings.show_hotspot_hints` on puts the outlines tightly around
the drawn text. `perform_click` on a line reaches frame 549 (`choose1a`), and the
live path — `InputRouter` → `MoviePlayer._on_stage_click` → `runtime.perform_click`
— is the same call. There is no cursor change over the lines, but that is faithful
too: MURDER1's `MovieScript 47` is `on cursorfunk / end`, an empty stub.

**Four claims in earlier versions of this entry were wrong.** They are recorded
because each one cost a session, and the fourth is the expensive one: *"the scene
completes, therefore this is NOT A BUG."* The player's report was about what
happens after the scene completes, and the entry answered a question they had not
asked. "Not a bug" needs more evidence than a bug does, and the evidence offered
here stopped at the movie change.

1. *"The port is missing frame script 119 and that is why nothing breaks the
   loop."* Scripts 119 and 120 are the mouth-flap-while-speaking loops, and their
   semantics are already in the exported nav: `guard_channel 1, guard_when idle`
   plus, on 120, `busy_nav {rel: 0, offset: 1}` to replay the segment while the
   line plays. 116 and 117 are the choice wait loop, also exported. The
   decompilation gap below is real, but it is not what stalls the scene.

2. *"Sampled every 200 ticks the playhead reads 33, 38, 44, 25, 30, 36 — cycling
   forever."* **That measurement is an artifact of the harness, not behaviour.** A
   tight `for i in N: rt.tick(0.016)` loop advances the runtime's clock but not
   the audio server's, so the WAV never progresses, `soundBusy(1)` never goes
   idle, and every speech guard holds for ever. Awaiting `process_frame` between
   ticks walks straight through. **Any guard that reads a real-time subsystem has
   to be exercised in real time**; a synthetic delta makes the engine and the
   subsystem disagree about how much time passed, and the resulting stall is
   indistinguishable from a logic bug.

3. *"Headless has no audio device, so `soundBusy` is always false."* This was in
   the docstring of `tools/_stuck.gd`, since promoted to `tools/probe.gd` with the
   claim corrected and the real-time loop made the default. The Dummy driver does advance
   playback, at roughly 0.35x real time: `TOF1.wav` reports `length 6.68`, and
   `get_playback_position()` climbs 0 → 2.33 over 400 process frames.

**The decompilation gap is real and stays open, but it is not this.** MURDER1's
frame scripts 116, 117, 119, 120 and 424 resolve to nothing, and
`toolcache/chunks/MURDER1/MURDER1/chunks/` holds 33 `Lscr-*.bin` chunks, so the
Lingo is in the binary and the decompiler emitted one cast out of five. What that
costs in practice is entry 23: where a frame script *is* present, the export's
lossy copy of it can still win. Source for a re-run:
`originals/recovery/web-alpha/PIP2DATA/MURDER1.DXR`; ProjectorRays is not
installed here.

---

## 27. `set the volume of sound N` parsed correctly and reached nothing, silently

**Status:** FIXED · **Area:** interpreter host + interpreter ·
**general: every sound property on the game's own host** ·
filed while closing `docs/LINGO_SURFACE.md` §16.4 rows 3–6

The parser built a `sound_prop` designator and `lingo_interpreter.gd` routed it to
`set_sound_prop`. **`lingo/lingo_host.gd` implemented neither that nor
`get_sound_prop`**, so every one of the corpus's volume writes was discarded by
`_host_call`, which returns null when the host has no such method — and null is
what a host that *handled* the call and had nothing to say also returns. Only
`scenes/preview_lingo_host.gd`, the room preview's host, had the pair.

Measured over `reference/lingo/`, so the size of the hole is a number: **67 lines
name `the volume of sound N`, 66 of them writes and 2 reads** (one line is both),
over channels 1 to 4. The earlier figure of 65 counted statements rather than
occurrences and predates the read-modify-write being noticed.

Both halves of the entry are closed together, because either alone leaves the
same class of defect possible.

**1. The binding.** `AudioDirector` now owns per-channel volume
(`channel_volume` / `set_channel_volume`, 0-255 linear, converted to decibels on
the channel's own player) and `the soundLevel` (0-7, driving the master bus).
Both hosts route to it rather than each keeping a copy. That is not tidiness: a
channel's volume outlives the movie that set it, `the soundLevel` is written in
one movie's option screen and read back in another, and the preview host had *no*
`soundLevel` binding at all — the slider handler's `if the soundLevel = N` chain
read 0, took no branch, and left the knob where it was.

**2. The silence.** `_host_call` now reports a missing method as
`host.<method>` under `unbound_name`. Deliberately not for `call_builtin`:
`_read_var` probes that for every bare identifier, so reporting there would
refile every unset variable as a missing binding, and `call_builtin`'s own miss
is already reported by its caller with the real name.

`tools/sound_state.gd` covers both. Case 2 asserts the volume that ends up on
`AudioDirector` and on the channel's player after the real compiler and the real
game host have run the corpus's own two shapes — the literal write and
`set the volume of sound 3 to the volume of sound 3 - 20`, which needs its own
previous write back. Case 5 runs the same statement against a host with the
methods deliberately absent and asserts both that nothing moved *and* that the
interpreter said so, which is the failure this entry was, reproduced on demand.

---

## 26. No walk in the game applied an arrival point, because `walkonby` read one item of three

**Status:** FIXED · **Area:** interpreter host `_walkonby` + puppet ·
**general: every room exit in the game** · the doorway table is now redundant here

Reported from play: *"there's something weird with the animation entering the scene
before the cliff — it moves to the left side while entering from the right side."*
Reproduces. The room is `swing`, reachable from `gate` (ch10) and from `clif2`
(ch12), both navs targeting label `swingup`.

**What is established, all measured this session.**

1. The export stores `walk_to`/`arrive_at` **once per destination label**, so both
   edges into `swing` carry the same pair: `walk_to (140,334)`,
   `arrive_at (33,291)`. This is the case `data/walk_doorways.json` exists for.
2. That table already holds per-edge corrections and they look right:
   `gate|10|swingup` → `walk_to (39,225)`, `arrive_at (326,371)` — arriving on
   swing's **right**, next to swing's own gate door at x=405; `clif2|12|swingup` →
   `walk_to (44,373)`, `arrive_at (30,328)` — arriving on the **left**, next to
   swing's cliff door at x=-1.
3. The lookup works and the override reaches the puppet. Measured at the click:
   `marker=gatego`, `doorway lookup = {walk_to (39,225), arrive_at (326,371)}`,
   `nav handed to puppet = walk_to (39,225) arrive_at (326,371)`. Calling
   `start_walk` with that nav stores `nextroom = {label: swingup, x: 326, y: 371}`.
   **So the data is not the bug and the lookup is not the bug.**
4. A real click-driven walk nonetheless ends at `walk_to`, not `arrive_at`:
   `loc_h = 39` from the gate, `140` from the cliff. Once the room settles it
   becomes **231** from both doors, which is the score's own sprite-30 x in
   `swinggo`.
5. The harness is clicking the doorway, not the floor — this was checked because a
   `walk_here` on channel 2 covers the room and would explain a missing
   `arrive_at`: `click at (35.0,117.5) first hits ch10 kind=walk target=swingup`.
6. The 231 is `sync_from_frame`'s `elif scene != scene_name: loc_h = score_h`. A
   room reached through a transition marker changes `scene_name` **twice** —
   `swingup` → `swing` → `swinggo` — and the `just_arrived` one-shot is consumed by
   the first change, leaving the second to adopt the score.

**A change that was tried, measured and rejected.** Letting the arrival own the
position until the next walk (do not clear `just_arrived` in `sync_from_frame`;
clear it in `start_walk` instead) removes the 231 clobber — `loc_h` 231 → 39 from
the gate, 231 → 140 from the cliff — and the pass/fail set stays green
(`puppet_visibility`, `smoke`, `room_names`, `collectables` 22, `cursors` 44,
`sprite_channels`). It was **not** kept, because the correct arrival is 326 and 231
is accidentally closer to it than 39 is: the change fixes a real defect and makes
the visible symptom worse. It is worth re-applying *after* the primary cause below,
not before.

**Root cause: `walkonby` read `nextroomdata` item 1 of three.** Every room exit in
the game is an **interpreted** `mouseUp` — verified `interpreted mouseUp=true` at
`gate` ch10, `clif2` ch12 and `edge1` ch12 — and an interpreted exit routes through
the native `walkonby` shim rather than the export's walk nav. `_walkonby` read
`item 1 of nextroomdata`, the destination label, and discarded items **2 and 3**,
which are the arrival point the original's own handlers author per hotspot:

```
the gate's exit sets   nextroomdata = "swing,344,375"
MURDER1's return sets  nextroomdata = "clif2,91,336"
```

`whatodoeveryframe` reads all three — `egozh = value(item 2 of nextroomdata)`,
`egozv = value(item 3)` — before its `go`. Reading only item 1 handed the puppet a
`nextroom` of `{label, transition}` with no `x`/`y`, and `PuppetController.step()`
falls back to wherever the walk stopped. So **`arrive_at` was unreachable on every
walk in the game**, on the path the game actually runs, and the destination room's
own score position then claimed him. Two doors into one room always landed on the
same side. Measured, three unrelated edges:

| edge | before | after | the script's own value |
|---|---|---|---|
| `gate` → swing | 231 | **344** (swing's right) | `"swing,344,375"` |
| `clif2` → swing | 231 | **33** (swing's left) | `"swing,33,291"` |
| `edge1` → edge2 | 289 | **300** | `"edge2,300,395"` |

231 is the score's sprite-30 x in `swinggo` and 289 is `edge2go`'s — the giveaway
that the score, not the walk, was placing him.

**It took two changes, and the second alone is a trap.**

1. `_walkonby` carries items 2 and 3 into `nextroom.x/y`. Two-item handovers exist
   and keep the old behaviour: the walk ends where it ends.
2. The arrival keeps ownership of the position until the next walk. A room reached
   through a transition marker changes `scene_name` twice — `swingup` → `swing` →
   `swinggo` — and `sync_from_frame`'s `just_arrived` one-shot was consumed by the
   first change, leaving the second to take `elif scene != scene_name` and overwrite
   the arrival with `score_h`. `start_walk` and `_walkonby` now clear the flag.

Change 2 was tried **first**, on its own, and rejected: it moved the gate arrival
from 231 to 39 when the right answer is 344, so it fixed a real defect and made the
symptom worse. There was no arrival point to protect until change 1 existed. A fix
that improves an invariant while degrading what the player sees is a sign the other
half is missing, not that the fix is wrong.

**`data/walk_doorways.json` is now redundant on this path**, and its premise was
wrong in an instructive way. It reverse-engineered per-edge coordinates from the
score by "reciprocity" because the export stores one pair per destination label —
and it did well: for the `clif2` edge it recovered `(30,328)` against the script's
`(33,291)`, and for `gate` `(326,371)` against `(344,375)`. But the scripts had the
real numbers all along, authored per hotspot. Its own comment says "the durable fix
is the export emitting nav per hotspot"; the durable fix was to read the Lingo. The
table still feeds the export-driven path (`start_walk`), so it is not dead code, but
no interpreted exit consults it any more. Retiring it is a separate change.

**Verification.** Pass/fail set green: `smoke`, `puppet_visibility`, `room_names`,
`collectables` 22, `cursors` 44, `sprite_channels`, `cliff_meeting` 11.
`tools/lingo_walk_diff.gd` is unchanged at `identical outcome: 85/117` with the same
32 differing rows — which says no walk changed *which room it reaches*, and is blind
to what this fixed: the differ records `movie@marker walked/facing`, never a
position. A harness that asserts the arrival position is the gap this entry leaves.

Reproduce: enter DAY1 **at frame 1** (never at a label, or `init all` has not run and
the score owns channel 30 — bugs.md 25), `enter_frame` to `gatego`, click ch10, and
watch `puppet.loc_h` and `puppet.nextroom`. Scratch probes deleted; the numbers above
are the record.

---

## 25. Skipping the opening entered DAY1 past its init region, so Piposh had no walk cycle and no spawn point

**Status:** FIXED for the three skip doors · **Area:** skip routing ·
F6 warp and the save editor can still do it, see the end

Reported from play: *"I pressed skip scene, and when I wanted to step off the
beach Piposh walked to the other side; on the next screen there was no character,
only a background."* One cause for both halves.

DAY1's globals are seeded by `BehaviorScript 56 - init all`, which sits on **frame
1**: `egozh = 600`, `egozv = 325`, `syz = 7`, `whatodo = "stand"`,
`nextroomdata = "000"`, `ifmovie = "0,0"`, and the inventory channels puppeted.
`whatodoeveryframe` then walks Piposh toward `egozh`/`egozv` and builds his member
name as `"walkleft" & syz & x`. Enter DAY1 anywhere past frame 1 and none of that
is set: he walks toward **0,0** — the far corner — and the next room places him
off-stage, which is the missing character.

Three doors entered DAY1 past frame 1, none of which the original has:

| door | landed | `egozh`/`egozv` |
|---|---|---|
| dev bar **Skip scene** in the opening | `DAY1:39` `shore2go` | `0,0` |
| dev bar **Skip scene** at the menu | `DAY1:39` `shore2go` | `0,0` |
| **Esc** during EXODUS | `DAY1:39` `shore2go` | `0,0` |

All three now use the movie's own ending instead of an invented destination, and
every route into a hub passes through the hub's frame 1 again:

* **EXODUS** declares its ending in the score — frame 447 is
  `{kind: movie, value: day1, frame: 1}` — so `skip_current` calls `_on_movie_end()`
  and lets `hub_return` read it. It used to invent `{"label": "shore2"}`: the right
  room, past the init region. Deleting a literal in favour of the export.
* **The title** is the one movie with *no* ending nav anywhere in its export, which
  is why `_on_movie_end` fell through `hub_return` and `go_back` to
  `goto_movie(current_hub())` and the boot frame. Its real endings are its menu,
  and from the menu, New Game — so `dev_skip_scene` now takes them one at a time.

After: the opening skip lands on `mainmenu`; a second press goes to EXODUS; a
third reaches DAY1 with `egozh=600, egozv=325, nextroomdata=000, ifmovie=0,0`.
Reproduce either side with `tools/_devskip_probe.gd` (scratch, deleted — the A/B is
in the commit message).

**Seeding was tried first and is the wrong shape.** Running the hub's frame-1
handler on any cold entry — so a labelled entry could seed itself — broke **9**
green checks: `cursors` ("an occupied slot gets the hand", 4 movies) and `smoke`
("collectable hidden when masor held", "handbag visible before the murder is
done", and two more). `init all` *empties `objectsfield` and resets `meetings`*, so
seeding wipes whatever state the caller had set up. That is entry 22's bug
re-introduced at the other end. **Do not add an init-seeding path; route the entry
through frame 1 instead.**

**Still open, and left open on purpose.** `F6` warp and the save editor's **Apply**
both call `goto_movie(movie, label)`, so from a cold boot they can still drop the
player into a hub at a room marker with the same unset globals. The workaround is
to start a game first, then warp. Whether they should instead auto-start one —
which would mean either a seeding path (rejected above) or a two-step "run the
init region, then jump" — is **an open decision, not a pending task**: deferred
deliberately after the fix above, because both options add a mechanism the
original does not have, and the dev tools' docstrings already say they do not
replay the walk that would normally get you there.

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
- **Not ink coverage** *for this bug* — but the reasoning was wrong, and
  **`bugs.md` 50 is the counterexample.** This read "the only unhandled inks are 0,
  which is Copy and correctly opaque, and 32 at 948 sprites". Ink 0 is **not**
  unconditionally opaque: Director mattes a Copy sprite whose thickness byte
  carries the blend flag, whatever the blend amount
  (`reference/scummvm/channel.cpp:206`), and reading the ink number alone drew
  *Rating*'s dialogue portraits inside opaque white rectangles. Measured on Piposh
  2 — 209 of its 88,095 Copy records carry the flag — the claim was defensible and
  the conclusion for *this* entry still holds; measured on Rating it is 27,914 of
  148,747. Left in place with this correction rather than deleted, because a
  ruled-out list flagged as not worth re-checking is exactly what sends the next
  session past a live defect.
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

## 14. Art draws stretched on one axis. The dropped stretch flag, at three levels.

**Status:** the score-side half is CLOSED — the stretch flag, see the Closed
section. The **film-loop-child** half is CLOSED — the same flag one level down,
also in the Closed section, and it is what the "scratching" on DAY1's `field`,
`edge1` and `veranda` was. The **strtgame flags** half is CLOSED — its score was
being looked for under a directory name nothing is filed under, see the Closed
section, and recovering it is what the opening video's smeared head was. What
remains open is a **suspicion only**, recorded below and no longer supported by
the evidence this entry was arguing from. · **Area:** assets and score

**A loop's children were the third cause and are now fixed.** The report that
reopened this was four screenshots of DAY1 `@field`, `@edge1` and `@veranda` —
rooms whose guests are `wonder` film loops — with a character intermittently
drawn at double size and others smeared on one axis. A loop's children are sprite
records in the same 48-byte format as the movie's score, so the same flag governs
them, and `tools/director_film_loops.py` was masking it off exactly as the
upstream exporter did for the main score. See the Closed entry; the counts below
are unaffected, because they read `frames.json`, which holds main-score records
only.

Reported twice from play: art "scratching over too much". The clearest instance is
the raft in the opening, where the bearded man's head is smeared horizontally
across the sky.

**Read the Closed entry first.** The score's stored width and height are only the
drawn rect when the sprite's stretch flag is set, and that flag was being dropped on
export. The 979 sprites now split **two** ways on it, with the third group gone:
**932** are the residue and are no longer drawn that way (ALLIN 839, DAGI 51,
INVESTIG 34, strtgame 7, MORN3 1) and **47** carry the flag, so Director really
does stretch them and they were never bugs at all (SEA1 32, NIGHT1 6, ARCADE2 5,
CHESS 4). The "flags unread" category is empty. The reproduce block below prints
this.

That head is `strtgame` member 26, channel 15, frames 122-128, and **all 7 of its
records have the stretch flag clear**. Director therefore ignores the score's
135x34 and draws the member at its own size, which is exactly what the port now
does. The smear was the dropped flag, the same cause as the other two halves — not
a member whose geometry is wrong.

**The three signals this entry used to argue the opposite do not survive
measurement.** Recorded because they looked conclusive:

- the registration point (68, 17) on a 45-wide bitmap does sit outside the image,
  with 68 half of 135. This one still has no innocent explanation and is the whole
  of what keeps the suspicion alive;
- `BITD-2774` PackBits-decoding to 13,568 rather than the 1,564 that stride 46 x 34
  implies proves nothing. **Member 25, this entry's own control, does the same** —
  988 declared against 16,536 decoded — and so do **388 of strtgame's 390** 8-bit
  members. Decoding to a target instead shows member 26's image is a clean prefix
  of 194 bytes in a 3,293-byte chunk. The overrun is a payload-boundary problem
  across strtgame's whole dump, not a fact about this member. For contrast, DAY1
  decodes 440 of 452 members exactly and MURDER1 24 of 24;
- "its `CASt` rect nonetheless reads 45x34" is not a disagreement. 45x34 is the
  declared geometry; that it is declared is not evidence against it.

Anyone picking this up should settle strtgame's chunk boundaries first — only
**17 of 195** 8-bit members reach their declared size as a clean prefix — because
no claim about one member's geometry can be made on top of a dump that is wrong
movie-wide. The visible symptom is fixed either way.

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

**`strtgame`'s flags were never blocked on endianness.** This entry claimed both
halves were stuck behind `tools/dump_movie_chunks.py` refusing XFIR containers, so
that "there are no chunks to re-derive from" and "fixing the little-endian reader
unblocks both". Both statements were wrong. `strtgame` has had a complete
ProjectorRays dump the whole time — 1,019 chunks including the score — filed under
`STRT_CHUNKS/strtgame/chunks`, and `dump_movie_chunks.py` says so in the very
comment explaining the refusal. `generate_sprite_stretch.py` simply looked for it
at `<root>/<movie>/<movie>/chunks` and missed it, then recorded the miss as `no
chunk dump for VWSC-3148.bin` — a missing file, which is what the entry read as
"could not be recovered". See the Closed entry.

**Ruled out: endianness as the cause of the other eight movies.** The first theory
was that little-endian containers were being mis-read, because `strtgame.dxr` is
XFIR. Only two files in the whole corpus are — `strtgame.dxr` and `MASTER.CST` —
and every other affected movie is big-endian. Recorded because it is a
plausible-looking dead end. It did not block `strtgame` either, contrary to what
this entry used to say. The XFIR reader's own disagreement with ProjectorRays —
441 of 912 chunks, same offsets, different payload boundaries — is a separate,
still-unretested fact, and is not the same claim as "there are no chunks".

Not the same bug as entry 11. That one is 1-bit members read as 8-bit and is fixed.

Reproduce. Note what this counts: it reads `frames.json`, which still holds the
rect the exporter wrote, so it still reports 979 — the sprites are no longer drawn
that way, and `tools/sprite_stretch.gd` is the check for that. What changed is the
split. Every row now lands in `stretched, correct` or `residue, now ignored`, and
a row in `flags unread` would mean a movie's score has stopped verifying:

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

## 12. One DAY1 film loop still does not parse

**Status:** CLOSED — the guard measured the wrong quantity, see the Closed
section · **Area:** assets / renderer · **See also:** 15

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

The last member was DAY1's 309, `loshuaa`, on channel 19 for 80 sprites. Its
`SCVW-1800` tripped "channel data exceeds D7 limit" in
`tools/director_film_loops.py` and the loop was skipped. **The D7 constants were
not the cause and did not need re-deriving** — the guard compared two different
quantities. See the Closed entry. The registry now carries 498 loops and
`get_film_loop(1, 309)` returns 161 frames on channels 20, 21 and 22.

Reproduce: `goto_movie("MURDER1")` then `loader.get_film_loop(1, 5)` resolves to 7
frames; `goto_movie("DAY1")` then `get_film_loop(1, 309)` gives 161 frames where
it gave `{}`. The "168x279" this line used to quote for the MURDER1 control is
wrong and predates the film-loop child fix: that child's rect is 108x273, which is
what the Closed entry for 15 also records. The control's frame count, 7, is the
part worth checking.

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

## Closed

- **`the castNum of sprite` dropped its cast library, and Piposh 1's ship map lost
  both the walking Piposh and every destination on it.** Reported from play: the
  figure does not appear on the ship and no screen can be reached from the menu.
  One cause, both halves.

  Every deck movie opens with
  `set nof to the name of member the castNum of sprite 1` — channel 1 is the
  backdrop, its member is *named* for the deck position, and that line is how the
  game learns where the player is standing. In `DAY1` channel 1 is `2:1`.
  `sprite_state.read_prop` answered `castNum` with the bare `cast_id`, so `1` came
  back; `members.resolve_ref` resolves a bare number in library 1, which is right
  because a bare number is all Director gives it; and member 1 of library 1 is
  `walkright1`. So `nof` became `"walkright1"` instead of `"dl1"`.

  `MAINMENU.dir`'s `enterFrame` reads `if the number of chars in nof < 4` and takes
  the `else` — `set the visible of sprite 20 to 0` — for anything longer. Ten
  characters, so the figure was hidden. And **every one of the map's destination
  handlers is `on mouseUp … if the visible of sprite 20 = 1 then … walkonby2()`**,
  so the same wrong library that removed the character also swallowed every click
  that would have moved him. Two symptoms, one missing library.

  Neither module was wrong alone, which is why nothing caught it: the fix is to
  stop them disagreeing. `castNum` is now split from `memberNum` and returns the
  `(library, slot)` pair packed into one integer (`members.pack_ref`,
  `LIB_STRIDE` 0x20000), which `resolve_ref` decodes. Library 1 packs to the bare
  number, so the common case is byte-identical. `memberNum` stays bare, because
  every `set the memberNum of sprite N to the number of member (…)` in the corpus
  does arithmetic on a plain number — INVENTOR's money gauge among them.

  The encoding need not match Director's, and that is measured rather than
  assumed: across all six roots every `castNum` site produces and consumes the
  integer inside a single expression. Five titles have only the read idiom
  (`member(the castNum of sprite 1).name`, or Piposh 1's `the name of member …`)
  and `rating` only the write idiom, `set the castNum of sprite 18 to the number of
  member …`, whose right-hand side is a bare number and which stays on the
  unpacked path. Nothing stores, compares or does arithmetic on a read `castNum`.

  Verified end to end through the path the game actually uses, not just the value:
  with the fix, `nof` is `"dl1"` on the stage and `"dl1"` inside the MIAW
  (`_share_movie_state_with` shares the globals dictionary, so it crosses the
  window boundary), channel 20 holds `stand`, `enterFrame` places it at (450, 117),
  `the visible of sprite 20` reads 1, and a synthesised click at (300, 117) runs a
  destination handler — `nof` → `"dr3"`, `egozh` → 300, `stopornot` → `"notok,b,5"`
  — with sprite 20 then walking, locH 450 → 410 and its member swapped into the
  walk cycle. A/B'd with the change stashed: `nof` `"walkright1"`, override
  `{"visible": 0}`, `the visible of sprite 20` → 0.

  `docs/LINGO_SURFACE.md` §1.6 had described this packing for a long time before it
  existed, citing `lingo/lingo_host.gd`, a file that no longer exists. A design
  note is not an implementation.

  Reproduce: `godot --headless --script tools/member_ref_round_trip.gd`, which
  chains `read_prop` into `resolve_ref` against the member the score actually put
  on the channel — 701 of Piposh 1's 1,513 distinct sprite members are outside
  library 1, and every one of them failed before this.

- **A field was laid out in the score's box instead of its member's, so Piposh 1's
  money was never centred.** Reported from play: the amount in the top bar sits
  off-centre. `GlobalMoney` is a 102x19 field with `text_align` 1, and every room's
  score records its sprite as 68x32 — the same 68x32 that three of its neighbours
  on that bar carry, which is what identifies it as residue rather than a size
  somebody authored. `director_text.draw` centres inside the rect it is handed, so
  the amount was centred in a box 34px too narrow and drew 17px left of where
  Director puts it, in **33,686 of that game's 82,323 field sprite records**.
  `GlobalTime` next to it was always right, and that is the tell: its member is 68
  wide, so the residue agreed with it by accident.

  The cause is one entry in `scenes/preview/sprite_geometry.gd`. `KEEPS_ITS_OWN_SIZE`
  held `[3, 8]` — field and shape — on the grounds that `sprite.cpp:setCast` excepts
  both from the dimension reset. It does, but that list is not "types whose score
  rect wins": for text the widget lays out and pushes its size **back onto the
  sprite** (DIRECTOR_ENGINE.md 1.2), clamped to `initialRect` for a fixed field and
  grown for an expanding one. Taking the exception without the push left the score's
  stored rect standing, which is the one value neither clause produces. A shape
  genuinely belongs there — it has no natural size — so the constant is now `[8]`
  and a field resolves to its member's `initialRect` unless stretched or resized by
  a script.

  Measured over all six roots before the change, honouring the stretch flag:
  switching a field's box from the score's to the member's drops a laid-out line in
  **11 sprite records** in the whole corpus, over 4 (member, box) pairs naming just
  two members. One is `save2`, where the line lost is a trailing empty one and
  nothing is visible either way. The other is `CAPROOM.dir`'s `memo21`, whose other
  records carry the stretch flag and keep their authored box.
  `tools/drawn_size_stability.gd` went from 153 exempt runs
  to 8 with the unstable count still 0, so no field run this newly measures pulses.
  The widened rect also feeds the hit test, and that is inert here: `tools/hotspots.gd`
  reports `ch59` as "no behaviour, member script declares none", so it never absorbed
  a click at 68 wide and does not at 102.

  What is **not** fixed is the expanding half of §1.2: a field still clamps to
  `initialRect` and never grows to its laid-out height, so text that overflows its
  authored box clips instead of pushing the box open. The 9 records above are the
  whole cost of that in this corpus.

  Reproduce: `godot --headless --script tools/text_and_shapes.gd -- --file
  PIPDATA/DAY1.dir` with `--root piposh`. The check is "every field's box is its
  member's, not the score's residue"; before the change it asserted the opposite and
  passed.

- **A movie's chunk dump was looked for under the wrong directory name** (part of
  14). `generate_sprite_stretch.py` built its path as `<root>/<movie>/<movie>/
  chunks`, but a dump's outer and inner directory names are not always the same:
  `strtgame`'s is filed under `STRT_CHUNKS/strtgame/chunks`. So the one movie whose
  stretch flags mattered most was the one movie the lookup could not find, and it
  reported the miss as `no chunk dump for VWSC-3148.bin`. Read as "no dump exists",
  that became entry 14's claim that recovering strtgame's flags was blocked on
  little-endian container support. It was blocked on a directory name.

  `dump_movie_chunks.py` already keys dumps by the **inner** directory for exactly
  this reason, and its comment names `STRT_CHUNKS` as the case. That keying is now
  shared: `chunk_dirs()` globs `*/*/chunks` and keys on `parts[-2]`.

  The reading it unblocked verifies as strictly as every other movie, which is why
  it can be trusted rather than merely accepted: 1,375 score frames against 1,375
  exported frames, **11,863 sprite records compared field by field with 0
  mismatches** across `cast_lib`, `cast_id`, `width`, `height`, `loc_h` and
  `loc_v`. 293 records carry the stretch flag. `strtgame` is no longer in
  `sprite_stretch.gd`'s "no recovered flags" list, the verified count went 69 to
  70, and the 7 sprites entry 14 was still chasing moved from "flags unread" to
  "residue, now ignored" — Director ignores those rects, so member 26 draws at its
  own 45x34 and the opening video's smeared head is the flag, not the member.

- **A film loop's size guard measured the whole stream against one frame's buffer**
  (was 12). `parse_scvw` read the third word of the `SCVW` list header as a channel
  data length and refused the resource when it exceeded `MAX_D7_CHANNEL_DATA`, the
  288 + 48 x 200 capacity of a single frame's channel buffer. That word is not a
  buffer size: it is the byte length of the whole frame-data region. It equals
  `len(data) - (index_start + list_size * 4)` for **287 of 287** `SCVW` chunks in
  the corpus, exactly, which is what identifies it.

  So the guard grew with the *length of the loop* and had nothing to do with how
  many channels a frame touches. Only one loop in the corpus was long enough to
  cross the line — DAY1's 309, `loshuaa`, declaring 13,184 against the 9,888
  ceiling. Its deltas in fact reach byte **1,344** of that 9,888 buffer, using 22
  sprite channels of the 200 allowed, so the D7 constants were right the whole
  time and re-deriving them, which this entry previously called for, would have
  found nothing wrong.

  The parse was never in doubt either. Every loop measured, working ones included,
  terminates with the frame-data stream exactly exhausted (`consumed ==
  inner_stream_size`), and `frames != list_size` is normal throughout — DAY1's
  `SCVW-1777` yields 20 frames from a `list_size` of 16, SEA1's `SCVW-5694` yields
  27 from 256. 1800 behaves like all of them: 161 frames, stream exhausted.

  The bound that does matter was already there and is untouched — each channel
  delta is checked against the real buffer before it is written. What replaced the
  guard is the sanity check the header supports: the frame-data region must fit
  inside the resource. The registry went from 497 loops to 498, the diff is pure
  insertion with nothing existing altered, and `verify_film_loops`,
  `sprite_stretch` and `film_loop_stretch` all still pass.

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
  `lingo_walk_diff` differs only in Godot's exit-time leak counters.

  Was covered by `tools/verify_film_loops.gd` in two ways, and the difference
  mattered; that harness is deleted (retired renderer). `tools/film_loop_cast.gd`
  covers the cast half only.
  Its 6 added `CASES` assert which cast a named child comes from and its size
  there — but that check resolves the child itself, so it gates the **exported
  data** and passes with the renderer reverted. Its `COMPOSITIONS` list gates the
  **renderer**: `MoviePlayer.film_loop_draw_commands()` was split out of
  `_draw_film_loop` so a loop's composition can be asserted without a window, and
  the harness runs it on the two frames the cliff was reported on. Revert the child
  cast lookup in the renderer alone and all three go red with the wrong members
  named — `["murder1:4"]` for Tofi's body, `[]` for Goldolin — which is the check
  the data assertion could not make. The split is behaviour-neutral: the five
  MURDER1 frames render byte-identical PNGs across it.

- **A film loop's children drew scaled to a rect Director ignores** (the
  film-loop half of 14). The entry below fixed this for the movie's own score and
  said in passing that film loops were untouched. That was true and it was the
  gap: a loop's children are sprite records in the same 48-byte format, carrying
  the same **stretch** flag at bit `0x80` of the ink byte, and
  `tools/director_film_loops.py` masked the byte to its low 6 bits for the ink and
  dropped the flag with it — the identical loss, one level down, in a second
  reader written months apart from the first. `MoviePlayer.film_loop_draw_commands`
  then scaled every child into its recorded rect.

  Of the corpus's 13,694 children, 13,596 resolve to a member. **2,053 carry the
  flag** and Director really does scale them; 11,308 have it clear with a rect
  already equal to their member, so nothing changes; and **235 have it clear and
  disagree**, which is the bug. By cast: `wonder` 130, `tennis` 55, `master` 16,
  `investig` 10, `endmovi1` 7, `gardug` 6, `samnight` 6, `arcade2` 3, `ishurun` 2.

  **The separation is perfect, which is what identifies the bit.** Of the 2,053
  flagged children, **zero** have a rect equal to their member's natural size —
  the same argument the main-score entry below rests on, run on the child
  population. So bit 0x80 is the stretch flag here too, and the 235 are provably
  the whole of the residue rather than however many happened to be noticed.

  `wonder` holds the worst: member 27 is 101x144 and its record says 203x289, so
  DAY1 `@field` channel 20 drew a guest at double size on 6 of the loop's 24
  frames — the giant black dress in the report — and normally on the other 18.
  The one-axis cases are the "scratching": `wonder` 59 at 84x159 recorded 97x159.

  Per reported room, child records whose drawn rect changed: `@field` **54 of
  242**, `@edge1` **17 of 166**, `@veranda` **16 of 154**. All three move, but
  only `field` carries a blow-up big enough to read as a different bug — its
  worst is 2.01x against 1.16x on `edge1` and 1.15x on `veranda`, which are
  smears rather than giants. `edge1`'s other loop, `wonder` 175, is a zoom with
  every child flagged and is deliberately left alone.

  **This does not touch the opening video.** `strtgame` contributes 0 of the 235,
  so the smeared head there is still 14's member-side half, blocked on the XFIR
  little-endian reader.

  The flag is written on the child as `stretch` and only where set, so its absence
  means "draw the member at its own size". Regenerating `cast_registry.json` over
  the fix leaves the file **identical once `stretch` is stripped**, which is how
  the change was attributed.

  Was covered by `tools/film_loop_stretch.gd`, deleted with the retired renderer —
  **this rule has no harness now.** Its fourth case was a **negative
  control** and is the reason the harness is worth having: `wonder` loop 175 is a
  zoom, every child flagged, its members recorded at ~88% of natural size. A "fix"
  that simply stopped honouring the recorded rect would pass all three positive
  cases and silently un-animate the zoom. Reverting the renderer alone turns the
  three positives red with the stored rect named in each failure and leaves the
  control green.

  Both position and size are asserted. A child is anchored on its registration
  point, so changing the drawn size moves the top-left with it, and size alone is
  the weaker claim: the giant goes from 203x289 at `(362.91, -159.00)` to 101x144
  at `(372.00, -14.00)`, and the guest on the bench from 101x144 at
  `(-12.25, 95.25)` to 142x192 at `(-16.00, 45.00)`.

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
  reading the sprite all see one rect. Was covered by `tools/sprite_stretch.gd`
  (deleted); `tools/drawn_size_stability.gd` covers it now.

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
  Was covered by `tools/collectables.gd`, deleted with the retired renderer —
  **no harness now.**
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
  7 marked all of them collected. Was covered by `tools/room_names.gd`, deleted with
  the retired renderer — **no harness now**, and it had been reporting green over
  0 rooms before it went.

- **Piposh drawn twice across a room transition.** The canned transition animation
  draws him in a low channel while the puppet drew unconditionally. `the visible of
  sprite 30` is now a real property (`PuppetController.visible`), hidden on the
  original's own `ifmovie` condition and restored by `BehaviorScript 207`.
  Was covered by `tools/puppet_visibility.gd`, deleted with the retired renderer —
  **no harness now.**
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

## 69. `liveness_sweep` read a window of states as a set, so a playhead walking through four frames and parking read as a trap

**Status:** fixed · **Area:** `tools/liveness_sweep.gd`

Filed as "the blank exemption should cover `trap` too, because a room idling
behind an open inventory reads as one". **That diagnosis was wrong**, and the
measurements that killed it are worth keeping, because both mistakes in it are
easy to repeat.

`--strict` over Rating's 81 movies returned one finding:

```
trap  sachroom.dir  after clicking ch5 at (218,310): confined to 4 state(s)
      for 60 tick(s) with no hold: SACHROOM.dir:25(7) <-> :26(7) <-> :27(7) <-> :28(9)
```

**First: the Movie-In-A-Window exemption was never involved.** Applying the
proposed fix -- returning `{}` from the `trap` arm when the window flag is set --
did not move the finding. Instrumenting the flag per click shows why, and shows
the flag itself is sound:

```
ch4  (119,383)   0/119 windowed -> healthy, 19 states
ch5  (218,310)   0/120 windowed -> trap
ch45   (7,393) 117/117 windowed -> healthy, parked at f28
```

The finding's own detail line named ch5 all along. `click_trace`, run afterwards
to "re-reach" it, picks its own hotspot and picked ch45 -- so the entry explained
one tool's finding with a different tool's click. `_poke` returns on the first
click that yields a verdict, so the sweep never reached ch45 at all.

**Second: it is not a trap.** The playhead sequence for that click is

```
24 x1  25 x1  26 x1  27 x1  28 x116
```

a walk of four frames and then 116 ticks parked on frame 28, which is exactly
what that frame's behaviour asks for (`set the cursor of sprite 42 ... go(the
frame)`). It spent 57 of the 60 reported ticks on one state.

**Root cause.** `_read_window` asked "how many distinct states are in this
window", and a *set* cannot tell a cycle from a walk that ends in a park. One
sliding position out of the whole watch straddles the walk, and `_judge` keeps
the worst position, so the transition alone is enough. The header made this worse
by claiming `WATCH` being two windows meant a trap "has to be entered and stayed
in rather than passed through"; the sliding-worst rule means window length has
never had that property.

**Fix.** `_read_window` counts *arrivals* -- transitions into a state, a stay
counting once -- and the three cycle verdicts require strictly more arrivals than
states, which is what it means for the playhead to have come back to something.
A walk has exactly as many arrivals as states. Nothing is lost: a walk into a
genuine dead end is read by the later windows, which hold that one state alone
and reach `blank-park`, and anything genuinely confined comes round again.

Covered by a rule test in `_assert_rules` (a walk through `CYCLE_MAX` frames that
parks on the last must read healthy), alongside the existing ones that each
verdict still fires on the shape it is for.

The rule gates all three cycle verdicts, `ping-pong` included: one `play` into a
second movie that parks there is two states and two arrivals, and that is a walk
across a movie boundary rather than two containers trading places. The
`ques.dir` <-> `Saves.dir` bug this file was written from alternates for as long
as the screen is open, so it has a window's worth of arrivals and still reads.

**`sound-park` was checked and deliberately left alone.** It is reached from
`_judge` directly and never passes through `_read_window`, so it never sees the
arrivals count, and its claim is not about cycling: it reports that the
`soundBusy` excuse covered *every* watched tick, which is as true of a
walk-then-park as of a loop and is the blind spot it exists to surface. The
original entry named it alongside `trap` as needing the same treatment; it does
not.

## 71. A film loop squeezed onto a smaller sprite drew its children full-size at their authored coordinates, so DISKSHOT's explosion went off on top of the player

**Status:** fixed · **Area:** `scenes/preview/film_loop_view.gd`

Reported from a snapshot: shoot a clay pigeon in `PIPDATA/DISKSHOT.dir` and the
explosion happens next to Piposh, in the middle of the deck, instead of at the
disk up in the sky.

Everything the report needed was in the container. The disks are one member,
`disknormal`, 72x16, on channels 24-45; every one of those sprites carries the
stretch flag with a rect around 26x7, which is how a disk reads as far away. The
click handler is four lines:

```lingo
set x to the clickOn
puppetSprite(x, 1)
set the memberNum of sprite x to the number of member "diskblow"
```

`diskblow` is film loop member 58. Its `initialRect` is 287x279 at (175,88), and
its one child per frame sits at **(320,240)** — the middle of the stage, which is
exactly where Piposh is standing. `the memberNum` swap keeps the sprite's rect,
because `Sprite::setCast` replaces the dimensions only when the stretch flag is
clear, so the loop was drawn as a 26x7 sprite.

**The root cause is that nothing scaled the loop's contents to the sprite.**
`place_child` was `origin + (childLoc − initialRect.topLeft) − reg`, with no
factor anywhere, and `child_sprite` sized every child at its member's natural
size. So the child was placed 145px right and 152px down from the 26x7 box and
drawn at full size. The measured symptom agrees: predicted centre (637,198)
against roughly (619,190) read off the reported snapshot.

That was already written down as `DIRECTOR_ENGINE.md` §16.8 — the half of the
port that scaled was `movie_player.gd`, and it was the half that got retired. The
entry outlived the file it named.

**The fix** is `child_scale`, `drawn / initialRect` per axis, applied to the
offset inside the loop (`place_child`) and to the child's own size
(`child_sprite`, which carries it into the registration offset through
`Geometry.scaled_reg`). The explosion now grows 5x1, 5x1, 9x2, 17x3, 25x7 centred
on (505.1, 49.8) inside the disk's own rect of (492, 45.5) 26x7.

**ScummVM was not copied here, and the corpus is why.** `getSubChannels` sets
every scaled child's size to the *whole* bbox with stretch forced on. Under that
rule all six frames of `diskblow` draw at 26x7 and the growth — the only thing
the loop exists to show — disappears. §18 had already recorded the suspicion;
this is the evidence.

**Gated by `tools/film_loop_scale.gd`**, which asserts the comparison rather than
plain containment: 248 of piposh's 4,874 children already sit outside their
loop's own rect at natural size, a separate question about the child stretch
flag, so what is asserted is that a child inside its box at natural size is still
inside it when the loop is squeezed. Green on piposh, piposh2, rating and
piposh-dream. Drop the `* scale` from `place_child` and it reports 4,613
regressions on piposh and 47,036 on piposh2; drop the size scaling and it reports
275.
## 72. Three things that look broken in Piposh 1's PIANO.dir and are the original's own

Filed as a ruling rather than a fix: a snapshot of the piano room was reported as
"some bugs around the piano scene". Three of the four things that look wrong in it
are the original's own behaviour, on evidence from the original's own scripts and
containers. Each is written down because it costs a session to re-derive, and the
last one reads as a hard bug.

**The fourth is not closed and is not here.** The mottled line across the left of
the keyboard is `bugs.md` 74: a mechanism was found that would explain it as
authentic art, and that is not the same as proving it, which is the bar
`AGENTS.md` sets for the verdict that stops work. Entry 73 below removed the crude
keying rule in `tools/director_render.gd` that made that seam look like a rendering
bug in the first place -- the tool was deleting the interior of every key and
showing the backdrop's clean line through it -- which narrowed what is left of the
disagreement to eight rows.

Every command below needs `--root piposh`: `director_game.cfg` points at
`piposh2`, and PIANO.dir is Piposh **1**, under `PIPDATA/` rather than
`PIP2DATA/`. `reference/lingo/` is Piposh 2 and has no PIANO in it, so every
question here was answered out of the container itself with
`tools/director_extract.gd`.

**The note names cover only the right half of the keyboard.** The score says so.
Member 139 is a 309x12 strip holding exactly fourteen labels -- two octaves,
`do re mi fa sol la si` in red then in blue -- and sprite 62 places it at
(241,467) on a 640-wide keyboard, so a bit under half the keys are labelled by
construction. Scripts 5, 53 and 141 toggle that one sprite's visibility.

Member 140, a 597x89 keyboard bitmap, carries the same labels baked over its right
half and corroborates the design, but it is **not** what the room draws: at
`playpiano` the keyboard is member 1 (the backdrop) plus 47 individual key
sprites, and member 140 appears in the help screens. Do not cite it as the reason
the labels stop; the reason is member 139's own width and the score's placement
of it.

**There is no hand on the keys.** Scripts 2, 4, 6 and 7 set `the memberNum of
sprite 49` to `the number of member "normhand"` / `"clidhand"`, and **no cast
holds either name.** A byte scan of PIANO.dir finds both strings only inside
script bodies and the Lingo name table, never as a `<len><name>` member name —
unlike `noclid1`, `clid1`, `song1` and `sngfld1`, which each appear once as one —
and MASTER.CST has no `hand` or `clid` member at all. Sprite 49 also sits at locV
489, below the 480 stage. Dead in the original data. The port is right to resolve
the name to 0 and carry on rather than abort the handler: aborting would cost the
key's art swap and its sound, which are the next two statements.

**All five "play piece N" buttons play `nosong.aif` on a fresh game.** This is
the one that reads as a total failure of the room, and the trail is worth keeping.
`sngfld1`, `sngfld4` and `sngfld5` hold 248, 220 and 316 characters of authored
note data (comma-separated note numbers, 0 for a rest) while `field "sngfld1"`
reads back empty, so script 93's `if field ("sngfld" & x) <> EMPTY` takes the
else branch, `go("listensong")` never runs and the pressed button is never
hidden. The override map explains it — five entries, members 44-48 of PIANO.dir,
all empty, present from the first frame after `go to movie` — and the writer is
the original's own: **MASTER.CST script 6**, the piano room's `exitFrame`,
restores each `sngfld` from `pianorecord1..5` and **clears it when the global is
empty**. `DAY1.dir` script 15, the new-game init, sets all five to EMPTY. So the
authored text is authoring-time leftover and the fields are the player's *own*
recordings; empty is correct until something is recorded, which is what the
record and stop buttons are for. `sngfld2` and `sngfld3` being empty in the
container is authentic and moot for the same reason.

**The recording round trip works, and this is how it was checked** — the piano's
core feature, which nothing in `gate.sh` reaches:

```
godot --path . --script tools/scene_probe.gd -- --root piposh --movie PIANO.dir \
    --marker playpiano --clicks "ch59;ch20;ch25;ch40;ch54;ch61;ch10;ch10" \
    --settle 24 --fields sngfld1 --stage 854,640 --out /tmp/piano.png
```

Record, three keys, stop, out to the menu, the listen line, play piece 1: the
field comes back `20,0,0,25,0,0,40,0,0,0` — the channel numbers pressed, which is
exactly the authored format, since a white key's channel *is* its note index
(`piano<channel>.aif` for 2..29, `diez<channel-29>.aif` for 30..48, and
`SONGS/PIANO/` ships exactly those) — and the playhead lands on frame 83, inside
`listensong`.

**`--settle 24` is load-bearing.** Scripts 2, 4, 6 and 7 gate a press on
`pianohand = 0` and walk it 1 -> 2 -> 0 on successive `exitFrame`s, so a second
key inside two score ticks is ignored *by the movie*. At 15fps against a 60fps
process loop, six process frames between presses records only the first key and
looks exactly like a dropped input.

`tools/scene_probe.gd` was written for this pass and is the general probe
`AGENTS.md` names as the repo's most useful missing tool. `liveness_sweep --only
PIANO.dir --click --strict` passes: 25 states over 120 ticks.


## 73. `director_render.gd` carried its own crude keying rule, and its output was quoted against the player as a rendering bug

The frame compositor in `tools/director_render.gd` resolved ink itself: a
`KEYED_INKS` list, and `_key_paper`, which made every pixel whose R, G and B were
all >= 241 transparent **across the whole bitmap**. Its own header documented the
crudeness, which is why this sat for as long as it did -- a documented wrong answer
still gets quoted.

**Matte (ink 8) keys only the paper a flood fill reaches from the border**, and 63
of the 71 sprites on `PIANO.dir` frame 37 are ink 8. Keying paper *everywhere*
instead punches out every enclosed white region, and on this corpus that means the
interior of every piano key: the backdrop then shows through the key bodies, and
the backdrop's own clean dark line appears where the player correctly draws the
key's dithered seam. So the tool drew a clean line, the player drew a dashed one,
and **the tool's output was taken as evidence that the player was wrong.** It is
the reason `bugs.md` 73 was filed claiming the two compositors placed sprites a
pixel apart -- they never did; their rects agree exactly, both printing
`(21,415) 35x72` for ch28. The mismatch was `(255,255,255)` against
`(255,255,204)`, paper dither surviving in one and not the other.

**The fix** is that the tool no longer has an idea of ink. Keying goes through
`director_ink.gd` -- `key_for`, then `key_matte` or `key_paper(back)`, then
`apply_colour` -- in the engine's own key-first-colourise-second order, and
`KEYED_INKS`, `PAPER_MIN_BYTE` and `_key_paper` are deleted rather than
documented. What remains different between the tool and the player is only what
the tool honestly lacks: scripts, puppet state and fields.

**Measured on `PIANO.dir` frame 37, player against tool, at an exact 2x capture:**

| region | before | after |
|---|---|---|
| the book, y270-390 x128-500 | 75.8% differ | **0.00%** |
| everything below the HUD, y90-480 | 17.8% differ | **0.30%** |
| whole stage | 26.6% differ | 12.5% |

The whole-stage figure stays high because of the HUD band, y0-89, unchanged at
64.8%: those are the `GlobalTime`/`GlobalMoney` field members the tool skips
outright and a panel the movie's own scripts hide. That is the tool's documented
limit, not keying.

**Not closed by this**: the eight rows of the keyboard seam, `bugs.md` 74. They
were the original symptom, they are what is left of the 0.30%, and the player
blends there where the tool does not.

**No harness compares the two.** Nothing in `gate.sh`'s `ALL` would notice either
of them drifting; this was found by hand while chasing 74.


---

## 78. `itamar-magichat` parked on frame 0: `baReadIni` was unbound, so an integer 0 reached a script testing `= EMPTY`

**Status:** FIXED · **Area:** `lingo/lingo_buddyapi.gd` (new),
`scenes/preview_lingo_host.gd` (the `ba*` arms and the registry),
`lingo/lingo_fileio.gd` (the folder half of the path index, and `note_file`) ·
covered by `tools/buddyapi_xtra.gd`, in `gate.sh`, which fails 13 checks on the
code before the fix

Three separate faults kept this title on frame 0 with a black stage, no error and
nothing on the clock. Two were fixed earlier and are covered by
`tools/lingo_scope_check.gd` — a `global` declared outside a handler never bound
inside one, and `list.setaProp(…)` reading a property instead of running the
command — and `go(VOID)` no longer coerces to frame 0. This was the third, and it
is the one that stopped the movie.

The chain, from `MovieScript 1 - start movie`'s `on startMovie`:

```lingo
tmp = ReadConfigLine("globals", "startframe")   -- MovieScript 2: baReadIni(...)
if tmp = EMPTY then
  tmp = "intro"
end if
SetGlobalInfo(#startFrame, tmp)
```

and frame 0's behaviour is `JumpFrame = GlobalInfo(#startFrame) / go(JumpFrame)`.

`baReadIni` is **BuddyAPI**, a third-party Xtra this port did not implement. An
unbound builtin is reported and answers the integer `0`
(`lingo_interpreter.gd:_call`), so `tmp` was `0`, `tmp = EMPTY` was false, the
movie's own `"intro"` fallback was skipped, `#startFrame` was set to `0` and the
frame behaviour jumped to the frame it was already on. Measured before:
`builtins unbound : {"bareadini":1}` and `gGlobalInfo = { "IniFile": <null>, …,
"startFrame": 0 }`.

**The type was the defect, not the value.** A `baReadIni` that answered `""`
would have been enough — and that is exactly how it was confirmed to be the last
link, with a one-line stub that was measured and removed. The implementation
therefore returns a *String* unconditionally, and `tools/buddyapi_xtra.gd`
asserts `ilk(baReadIni(...)) = #string` and the movie's own `= EMPTY` test rather
than any particular value: reverted, those two go red with `integer`, which is
the failure a reader can act on.

Measured after, on the same command the entry was filed with:

```
godot --headless --path . --script tools/scratch/walkfwd.gd -- \
    --root res://test-games/itamar-magichat --file magichat.dir --steps 160
```

step 0 is frame 136, and the playhead cycles 124–138 — the intro/retro video
loop, 1 to 22 sprites drawn — instead of printing `magichat.dir:0` every step.
`builtins unbound` is `{"prgotoframe":17}`, which is PrintOMatic, a different
Xtra and reported by name.

**The two questions this entry said an implementation had to answer first**, both
answered:

1. *Which file.* `ReadConfigLine` passes `gIniFileName`, which `InitProgram` sets
   and which `on startMovie` calls only inside `if not Projector()`. `the runMode`
   answers `"Projector"`, so it is VOID. A `baReadIni` whose file argument names
   nothing answers the caller's `Default` — Windows' own rule for a missing file,
   and what unsticks this movie, because the default *is* the movie's `"intro"`
   fallback. So the boot-story question does not block the Xtra. It does still
   block the title's menus, which is `bugs.md` 79.
2. *Writes.* `WriteConfigLine` is `baWriteIni` + `baFlushIni` and both are live.
   `baWriteIni` is a read-modify-write that keeps every other line of the file
   as it stands; `baFlushIni` re-commits anything a failed write left pending and
   drops the parsed document, so the next read comes off the disk. Both obey
   `MovieSave.writes_allowed` and the game-root guard, so a headless run refuses
   them (0, and reported through the diagnostics — BuddyAPI has no `status`
   channel). Measured: seventeen `baWriteIni` calls in a 160-step run and nothing
   written into `test-games/`.

**A second defect fell out of this and is worth more than the first**, because it
was silent and general. `res://` directory listings are a **snapshot taken when
the `.pck` is mounted**: `DirAccess.make_dir_absolute` succeeds, the directory is
on disk, and `DirAccess.open("res://…/newdir")` does not see it for the rest of
the process, however many times a cached index is thrown away and rebuilt. That
made `baCreateFolder` answer 1 and `baFolderExists` answer 0 for the same name
one statement later — both calls correct, the index between them lying. FileIO
had the same hole and nobody had met it: `createFile`, `closeFile`, then
`openFile` on the bare name could not find the file it had just written. The fix
is `FileIO.note_file` / `note_folder`, which record a creation or a removal in
the cached indexes directly, and `FileIO.open_dir`, which lists through
`ProjectSettings.globalize_path` — the OS path sees the live filesystem.


---

## 41. `member (<expr>) of castLib X` drops the library, and with it every joke and every collectable card in Piposh 1

**Status:** FIXED by `66baa6a5` · **Area:** `lingo/compile/lingo_parser.gd` ·
**the fourth instance of one shape**, and the first three each cost a player bug
too · reported from play as *"the binoculars vanish when the deck chair
collapses"*

Reproduce, which is also the check that holds it closed:

```
godot --headless --path . --script tools/parse_residue.gd -- --root piposh
```

Re-measured at HEAD on 4.7.1, 2026-08-10:
`ok    piposh: no compiled statement calls a clause keyword  (0 in 8754 script(s))`,
and `PASS  no designator clause was dropped into a statement of its own`. Before
the fix that line read
`FAIL  piposh: no compiled statement calls a clause keyword (12 in 8754 script(s))`,
all twelve on `MASTER.CST` member 31, lines 4 and 75 — `jokesfunk` and
`cardsfunk`, the two handlers Piposh 1 runs on **every** room entry. Both
localisations report the same two lines; Piposh 2 has the identical line in its
own `MASTER.CST` member 12 and is clean only because it is commented out.

**The mechanism.** `_parse_the`'s `member` arm has two branches and only one of
them looks for the trailing clause:

```gdscript
if _at_op("("):
    var args := _parse_call_args()
    mwhich = args[0] if args.size() > 0 else {"node": "num", "value": 0}
    mcast = args[1] if args.size() > 1 else null        # <-- no fallback
else:
    mwhich = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
    mcast = _parse_optional_castlib()
```

The other three sites that parse the same designator —
`lingo_parser.gd:752` (`field (…)`), `:777` (`member (…)` as a reference) and
`:975` (`the number of member (…)`) — all read
`args[1] if args.size() > 1 else _parse_optional_castlib()`, and each of those
lines was added by a bug report. This one was missed. **The fix is that same
expression, on the `mcast` line of the `the <prop> of member (…)` arm.**

**Why nothing reports it.** The expression is still valid without the clause, so
the statement compiles; the words left over become statements of their own. From
`tools/scratch`, the AST of

```
put the name of member (the membernum of sprite 1) of castlib "decks" into x
```

is a `put_echo` with no target, then a bare `of`, then `castlib("decks")`, then
`into(x)`. `x` is therefore never assigned, and the four later mentions of `x` in
`jokesfunk` compile to calls to a handler named `x` that answers VOID. So `y` is
VOID, `char y of x` is empty, `value("")` is 0, `item 0 of globaljokes` matches
neither `"0"` nor `"on"`, and the handler falls into its final `else`:
`set the visible of sprite 17 to 0`. Every time. `script_compile_check.gd` sees
a script that compiled and says so.

**The player-visible half.** Piposh 1's rooms each hide one gag on channel 17 and
one collectable card on channel 19, revealed by `globaljokes` / `globalcards` and
restored on entry by `jokesfunk` / `cardsfunk`. In DAY1's `dl1` — the deck
outside the cabin door, and the room the report names — channel 17 is member
`1:156`, a pair of binoculars. Clicking the deck chair runs `dl1chair` (frames
66-80), whose frame script at 70 (`BehaviorScript 158`) plays the chair
collapsing, sets `item 1 of globaljokes` to `"on"` and animates the binoculars
falling onto the deck on channel 16. Measured over the whole clip: `globaljokes`
does become `on,0,0,0,0` and channel 16 does draw members 150→156, so the gag
runs. Then the playhead returns to `dl1` (frame 3), `BehaviorScript 21` calls
`jokesfunk()`, the branch above fires, and **channel 17's override stays
`{"visible": 0}` for the rest of the movie.** The binoculars are gone.

`BehaviorScript 158` gets the same value out of the same cast because it spells
the designator *without* the parentheses — `the name of member the memberNum of
sprite 1 of castLib "decks"` — which is why the gag can fire at all and only its
restoration is lost.

Proof that the parse is the whole of it, at `dl1go` with
`globaljokes = "on,0,0,0,0"`:

| handler called | channel 17 after |
|---|---|
| `jokesfunk`, as authored | `{"_member": 156, "visible": 0}` |
| the same body with the parentheses removed | `{"_member": 156, "visible": 1}` |

**Scope.** Every joke and every collectable card in Piposh 1, Piposh 1 English
and Piposh 1 Russian, in every room, on every day — 5 jokes and 5 cards per day
by `globaljokes`/`globalcards`, none of which can ever be seen a second time.
`piposh2`, `piposh-dream` and `rating` report 0.

**Not the same fault as the up-staircase** reported alongside it from the same
room, which was `preview/interaction.gd:script_for_click` handing the click to a
behaviour that declares no mouse handler. Two reports, one room, two causes.

---

## 41 (the second entry filed under this number). `play_suspends` fails about half its runs on one assertion, so the gate's set is not reproducible

**Status:** FIXED by `b8466abb` · **Area:** `tools/play_suspends.gd` · found by
the first full-suite run on macOS, which is also the first one anybody diffed
run-to-run

The fix is the one this entry asked for, in the harness rather than the engine:
`play_suspends.gd:362-369` waits for `gsuspendhop` to read `"after"` under a
600-frame ceiling instead of spending a fixed six frames, and the same commit
tightened the assertion it guards. Line `:351`, which this entry used to name as
the defect, is now the head of the comment explaining its own replacement — so a
reader following the citation lands on the fix rather than the bug. **A green
`play_suspends` is a result, not one sample**, and `AGENTS.md` and `README.md`
both said otherwise for longer than they should have.

`bash gate.sh play_suspends` twice in a row, same binary, same corpus, prints
PASS then FAIL. Four bare runs:

```
for i in 1 2 3 4; do
  godot --headless --path . --script tools/play_suspends.gd -- --root piposh2 \
    2>&1 | grep -E '^(PASS|FAIL)' | tail -1
done
```

```
FAIL  ... (26 checks, 1 failed)
FAIL  ... (26 checks, 1 failed)
PASS  ... (26 checks, 0 failed)
PASS  ... (26 checks, 0 failed)
```

26 checks every time, so this is not a harness that lost its subject and not a
corpus that resolved differently. One assertion moves: **"and the rest of the
handler still ran"**, which reports `before` when it fails and `after` when it
passes.

The case is `a handler frozen by 'go to movie' outlives the interpreter`. It
calls `suspendhop`, whose body hops to another movie mid-handler, and then waits

```gdscript
	for i in 6:
		await process_frame
```

before asserting that the trailing `put "after" into gsuspendhop` ran. Six
frames is a fixed budget spent waiting for a *container to load off disk* and
the suspended handler to be resumed on the new interpreter. When the load takes
longer than six frames the assertion reads the global before the resume writes
it, and the harness reports the engine as broken.

So the fix was in the harness, not the engine: wait for the condition — the
interpreter to have resumed, with a frame ceiling that fails loudly — instead of
counting frames and hoping. While it stood, the gate's recorded set was not
reproducible, and a session that ran the suite twice would attribute the
difference to whatever it changed in between.

Not caused by the corpus pinning moving from `director_game.cfg` to `--root`:
both mechanisms resolve the same root, and the 26-check count is identical
either way.

---

## 16. `the number of member X of castLib Y` drops the library

**Status:** FIXED by `1dab1f68`, which filed the same defect a second time as
**65** — read that entry for the full account, including the cursor pair it was
found on and the A/B that proves the packing · **Area:** interpreter host

The workaround this entry describes did not need removing: it left with the
renderer it lived in. `grep -rn "_run_cursor_funk\|is_hub" --include="*.gd" .`
returns nothing at HEAD, `cb7fe815` having retired the file both names.

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

Reproduce (dead — it names `_run_cursor_funk()`, which is deleted): `goto_movie`
any non-hub movie with an empty channel 103 after removing the `context.is_hub`
gate, and watch for the missing-member warning. The live equivalent is
`tools/cursor_cross_cast.gd`, added by the same commit and in `gate.sh`.

---

## 40. Unnamed markers are dropped, so `marker(n)` cannot count to a `play done` frame

**Status:** FIXED and **gated**, both by `7411d1ed` — the same commit that landed
`director/director_labels.gd` added `tools/label_index.gd` and put it in
`gate.sh`'s `ALL` · **Area:** `director/director_labels.gd` · found while landing
`play`/`go` suspension, and it is the other half of the same dialogue

*(This status line read "fixed in the working tree, not yet gated" for long
enough to be worth recording as its own instance of the cost this file keeps
paying: it was stale on both halves at once, and the commit that made it stale is
the commit the entry itself names.)*

**This entry was open for one commit longer than anybody believed, and that is the
part worth keeping.** It was filed with the diagnosis correct and the fix printed
below. Commit 641d1d47 ("labels: an unnamed marker still counts, so `marker(n)`
stops skipping past it") landed that printed fix, said in its message that the
dialogue was repaired, and **was inert**: it moved `markers.append` above the
`if name == "": continue` and taught `marker_at` to prefer named markers, but left
the range guard four lines higher —

```gdscript
if start < text_base or stop > payload.size() or stop <= start:
    continue
```

— and `stop <= start` is true for a zero-length name, so control never reached the
append that commit had just moved. The file then carried a comment reading "An
unnamed marker is kept, and that is not tidiness" directly beneath a guard that
dropped them, and a class docstring still insisting they "must be dropped, or
every later marker's index shifts", which is exactly backwards. Two independent
readings of the same file disagreed and nothing arbitrated.

**Nothing caught it, because the only harness that could had repaired its own
subject.** `tools/play_suspends.gd:_restore_unnamed_markers` re-parsed the VWLB
chunk, overwrote `labels.markers` with the full list, and early-returned when the
counts already agreed — so `--dialogue` asserted against an array the player never
gets, passed before the fix, and passed identically after it. Its docstring
conceded this ("Put back here rather than fixed here … `bugs.md` carries it"),
which is honest and still useless: a green run proved nothing either way. It is
now `_check_marker_index`, which asserts the count and fails instead of repairing.

The lesson generalises past this bug: a decoder's output size is an *invariant*,
and the only trustworthy witness to it is the container's own header. That is what
`tools/label_index.gd` now checks over every container in every root, and it is
what would have gone red the day 641d1d47 landed.

`DirectorLabels.parse` dropped every VWLB entry whose name is empty. The reference
keeps them: `Score::loadLabels` inserts one `Label` per entry regardless of name,
and `getNextLabelNumber` walks the whole array — so **`marker(1)` counts unnamed
markers and this port's did not.** An unnamed marker is not decoration. It is
how a Director author marks a frame that only the score needs to reach, and it is
not rare: **2,236 of Rating's 4,220 entries**, 59 of `piposh-dream`'s 2,732, and
12 of Piposh 2's 3,019 — so the gate's own corpus carries them too.

Rating's `BATZEGOZ.dir` is the case that found it. Its VWLB has 28 entries and
nine of them are unnamed, one at 0-based frame 214:

```
godot --headless --path . --script tools/label_index.gd -- --file BATZEGOZ.dir --list
```

lists them, and printed 19 of 28 before the fix:

```
    13  frame   207  egozspeak1
    14  frame   214  <unnamed>
    15  frame   216  Batz2A
```

Frame 214 is `BehaviorScript 36`, whose whole body is `on exitFrame / play done /
end`, and it sits between `egozspeak1` (207) and `Batz2A` (216). The talking loop
at 207-213 leaves with `go(marker(1))`. With the unnamed marker kept that is
frame 214, `play done` runs, and the mouseUp that called `play frame
"egozspeak1"` is resumed so that its own trailing `go` picks the room. With it
dropped, `marker(1)` is 216 and **frame 214 is unreachable**: `play done` never
runs anywhere in this movie, and all three of Egoz1's dialogue options arrive at
the first one's destination.

Measured, clicking the three options in turn (`tools/scratch` is gone; the same
walk is what `--dialogue` asserts):

| option | script | markers as parsed | markers with the unnamed ones kept |
|---|---|---|---|
| channel 11 | `go("batz2a")` | Batz2A | Batz2A |
| channel 12 | `go("batz2b")` | Batz2A | Batz2b |
| channel 13 | `go("batz2c")` | Batz2A | batz2c |

so the visible symptom is *a dialogue that answers every option with the same
reply*, and it is one line away.

The fix is not simply to stop dropping them, because `marker_at` is the reason
they were dropped in the first place — a frame inside an unnamed marker's span
must still report the last *named* one, or "which room am I in" answers blank.
**Nor is it `stop < start`**, which is the one-character version and leaves the
sibling clause (`stop > payload.size()`) able to renumber the index space the same
way for the next container that needs it. The rule the loop enforces is now stated
as the rule: *an entry is never dropped; only its name can be unreadable*, so a
bad range costs the name and never the position. Both halves:

```gdscript
        var name := ""
        if stop > start and start >= text_base and stop <= payload.size():
            name = Codepage.decode(payload.slice(start, stop)).strip_edges()
        var zero_based := frame - 1
        markers.append({"frame": zero_based, "name": name})
        if name == "":
            continue
        var key := name.to_lower()
        if not labels.has(key):
            labels[key] = zero_based
```

The earlier revision of this entry printed that block without the guard folded
into it, keeping the `continue` above — which is the shape that shipped inert. The
`continue` has to go, not move.

```gdscript
func marker_at(frame: int) -> String:
    var found := ""
    for marker in markers:
        if int(marker["frame"]) > frame:
            break
        if str(marker["name"]) != "":
            found = str(marker["name"])
    return found
```

**Keeping the entries moves `marker(0)` as well as `marker(1)`, and that is the
risk surface rather than a footnote.** A hold loop inside an unnamed marker's span
now returns to the unnamed marker rather than to the named room. It is
Director-correct — `Score::getCurrentLabelNumber` (`score.cpp:238`) scans every
entry, named or not — but it is a live behaviour change at 2,236 sites in Rating
alone. BATZEGOZ has unnamed markers at 330, 335, 336, 367 and 369 inside
`batz2c`'s span, and members 5, 19, 80, 84 and 123 all call `go(marker(0))`.

Every reader of `markers`, and what the change does to each:

| reader | effect |
|---|---|
| `director_preview.gd:lingo_marker` | the fix. Counts entries, as Director does |
| `lingo_go_next` / `go next` | correct now; `gotoNext` counts unnamed ones too |
| `tools/mouse_poll.gd:133` | **more** correct — its own comment says the handlers it drives end in `go(marker(1))` |
| `tools/click_trace.gd:_where` | already skipped empty names in advance of this |
| `hotspots.gd`, `click_trace.gd:_target_frame` | match by name, so `""` never matches a request |
| `tools/builtin_load.gd:277` | bounds a room's span by "the next marker", which can now be an unnamed one. In the gate — watch it |
| `director_preview.gd:1820` (**SKIP**) | jumps to the next marker ahead, so SKIP now stops on unnamed markers as well. Left alone deliberately: SKIP is a debug affordance with no Director semantics to be correct against, it has its own open entry (32), and "an unnamed marker is not a scene" is the same argument `marker_at` already makes. Wants a decision, not a silent change |

---

## 19 and 28 (the scale half). The cursor never grew with the stage, so it was drawn a third of the size of the artwork it sat on

**Status:** FIXED by `ff066de6`, relocated into a module by `2fbb43f3` ·
**Area:** `scenes/preview/cursor.gd:for_stage`, wired at
`scenes/director_preview.gd:_cursor_for_stage` · **two entries, one defect**,
filed once against each renderer

`Input.set_custom_mouse_cursor` takes real screen pixels. Everything else a movie
draws goes through the stage node's own `scale`, which the window fit sets, so a
16x16 cursor handed over unscaled is drawn against artwork that is half again as
large — at the project's default 1280x720 window and the `native_4_3` aspect,
`min(1280/640, 720/480)` = **1.5**.

**Entry 19** was the retired renderer's half of it: `MoviePlayer._apply_cursor()`
scaled by `maxi(1, int(floor(_stage_scale())))`, and `floor(1.5)` is 1, so the
cursor stayed native until the window was big enough for scale 2. **Entry 28's
Scale paragraph** was the preview's half, one step worse: `lingo_set_cursor`
passed the composed image at its native size and applied no factor at all.

Entry 19 is also a **dead letter**, and that is the part worth keeping. It named
`MoviePlayer._apply_cursor()`, and `cb7fe815` retired that renderer: at HEAD
`grep -rn "MoviePlayer\|_apply_cursor" --include="*.gd" .` returns nothing, so
the entry described no code in the tree for months while still reading as open
work. `bugs.md`'s own preamble had flagged it as a candidate for closing outright
rather than fixing, which is not the same as closing it.

`Cursor.for_stage` is the fix and it is the *rounding* the two entries argued
about, settled: `maxi(1, int(round(stage_scale)))`, nearest-neighbour resize, and
the hotspot multiplied by the same factor because Godot reads it in the texture's
own pixels. Nearest-neighbour is deliberate — this is 1-bit art with hard edges
and smoothing it produces a grey halo around every pixel — and there is a
`MAX_CURSOR_PIXELS` ceiling above which the image is handed over unscaled rather
than refused.

**What is still open is entry 28's other half**, the hotspot rule: whether the
data member's registration point is used, or Windows Director's pre-D5 rule of
always (8,8). That needs a source on what the original build did, not a
preference, and it is still in `bugs.md` under 28.

The retired renderer's text, kept because the measurement in it is the one that
identified the scale:

> **Status:** open, cosmetic · **Area:** renderer
>
> `MoviePlayer._apply_cursor()` scales the cursor with
> `maxi(1, int(floor(_stage_scale())))`. Director cursors here are 13x17 to 17x17,
> authored for a 640x480 screen, so at a stage scale of 1.5 — which is what a
> default window gives — `floor` yields 1 and the cursor is drawn at native size
> against artwork that is half again as large. It only doubles once the window is
> big enough for scale 2.
>
> Flooring is deliberate: rounding 1.5 up would draw the cursor larger than the art
> around it. The result is still that the cursor is visibly small at the size most
> people will play at, and it steps rather than tracking the stage.
>
> Reproduce: run the game at the default window size, hover the floor in DAY1, and
> compare the cursor against the artwork it sits on. `_stage_scale()` reports 1.5.

---

## 79. `itamar-magichat` plays its intro loop and never reaches its menus: `the runMode` is "Projector", so `InitProgram` never runs

**Status:** FIXED by `316b521f`, `a484f1b6` and `31fcae5b` — all three of the
things this entry left open have since been settled, and the entry is kept
because the measurement in it is what settled the first one · **Area:**
`scenes/preview_lingo_host.gd` `get_system_prop("runmode")`

`316b521f` made `the runMode` answer `"Author"`, which is the position this
player is actually in: it opens a `.dir` directly with no projector stub, so a
title that asks whether it must initialise itself has to be told yes. The
concern recorded below — that answering `"Author"` everywhere would stop every
projector-only branch in the corpus from running — was measured before the
change and not after: `the runMode` appears in **0** of the six shipped titles'
scripts, so nothing in Piposh or Rating can see the difference.

The `[ENDINI]` / `[ENDFILE]` disagreement below turned out not to be a choice
between two terminators. The original `magichat.ini` ships *inside* `utils.cst`
as a text member, at offset 43925, and it ends `[ENDFILE]` — the reconstruction
was simply wrong, and `test-games/itamar-magichat/magichat.ini` is now the
original recovered byte for byte.

And the alert it fired was not about the file at all. `put readFile(tmp) into
member FieldName` had no arm in `_assign`, so `LoadFileToField` read the ini and
dropped it; `ReadInifile` then found no `[ENDFILE]` in an empty field. Fixed in
`a484f1b6`, which has the full account in its commit message: the statement
had no arm in `_assign` at all, so it recorded itself into `errors` and
returned normally, and the handler ran on to completion.

What this entry predicted is what happened: at HEAD magichat settles on frame
23, `BehaviorScript 18 - mainmenu loop`, with its menu drawn.

With BuddyAPI live the playhead leaves frame 0 and plays frames 124-138, the
intro/retro video loop, for ever. It never reaches the main menu, and the reason
is not an Xtra:

```lingo
on startMovie
  if not Projector() then          -- on Projector: `the runMode = "Projector"`
    clearGlobals()
    if SingleGameMode() then
      InitProgram("magichat.ini")  -- the only caller of ReadInifile
    end if
  end if
```

`the runMode` answers `"Projector"` (`preview_lingo_host.gd`), matching the
reference's default (`lingo-the.cpp` `kTheRunMode`), so `InitProgram` is skipped,
`gIniFileName` and `gCDpath` stay VOID, and two things follow. `ReadConfigLine`
reads no file, so `#startFrame` takes the movie's `"intro"` fallback rather than
the ini's `startframe`; and `InitMenuData` asks for
`CDpath() & "\" & "mainpanels.txt"`, which the resolver *does* find on its tail,
but `ReadAllMenusFile` builds no menus because nothing else in the chain ran.

That is faithful to a **projector**, where a stub movie has already run
`InitProgram` before branching to `magichat.dir`. This port boots the `.dir`
directly with no stub, which is the authoring case, and whether it should say so
is a decision about the boot story rather than a bug in any one binding.

**Measured, and the reason this is worth an entry rather than a note:** forcing
`"Author"` in that one arm and changing nothing else, magichat runs
`InitProgram`, reads its real `magichat.ini` through `baReadIni` (7 reads, plus 2
`baFileExists`), takes `startframe = mainmenu`, and settles on frames 19-23 with
16 sprites drawn — the menu screen, with `errors : 0` and `builtins unbound :
{}`. So the whole of the rest of the title's startup already works; one string is
between it and the movie's own first screen.

Two things to settle with it, both cheap and neither guessed at here:

- One `alert` fires on that path. `ReadInifile` sets `gEndFileText = "[ENDFILE]"`
  and alerts if `SearchField` cannot find it, and the reconstructed
  `test-games/itamar-magichat/magichat.ini` terminates with `[ENDINI]` — which is
  what the *other* ini-utils movie script scans for. The reconstruction's own
  header explains why it chose `[ENDINI]`; one of the two terminators is wrong and
  the file is reachable only on this path, so it was left alone.
- `the runMode` is read by titles other than this one, and a port that answers
  `"Author"` everywhere makes every projector-only setup branch in the corpus
  stop running. If it moves it should move with a measurement per root.

Reproduce:

```
godot --headless --path . --script tools/scratch/walkfwd.gd -- \
    --root res://test-games/itamar-magichat --file magichat.dir --steps 160
```

Every step prints a frame between 124 and 138. `tools/scratch/globs.gd` with the
same arguments prints the globals; `gIniFileName` is VOID.

---

## 88. Every click on Magic Hat's main menu froze the application for 16 seconds, because a Lingo loop polling `the mouseDown` could never see the button come up

**Status:** fixed · **Area:** `lingo/lingo_interpreter.gd` (`_breathe`,
`BREATHE_MS`), `scenes/director_preview.gd` (`lingo_breathe`,
`_queue_button_changes`, `_flush_deferred_input`), `scenes/preview_lingo_host.gd`
(`breathe`)

**The symptom, and which kind of freeze it was.** A **hang**, not a hold: the
window stopped repainting and Windows reported the process as not responding.
Measured by posting a real `WM_LBUTTONDOWN`/`WM_LBUTTONUP` pair at the album
button of a maximised windowed run started exactly as the owner starts it — main
scene, `res://scenes/director_preview.tscn`, not a `--script` SceneTree — and
sampling `SendMessageTimeout(hwnd, WM_NULL, SMTO_ABORTIFHUNG|SMTO_BLOCK, 2000)`
once a second:

```
CLICK stage=(448,378)
t=  0s pump=False ... cpu=12.16s
t=  1s pump=False ... cpu=15.17s
...
t= 15s pump=False ... cpu=28.44s
t= 16s pump=True  ... cpu=29.42s
```

Sixteen seconds with the message pump dead and one core saturated, then the log
line that ends it:

```
clicked (559,472) frame 23  ch2  sprite script BehaviorScript 20 - screen item script  mouseUp:yes
lingo: repeat while did not terminate  (MovieScript 17 - Screen items functions > ItemMouseDown line 115)
```

The recovery is `MAX_STEPS` aborting the handler after 400,000 steps, which also
loses the `mouseUp` — so the button did nothing either.

**The cause.** `objects.cst`, `Screen items functions`, lines 108-117, is
Director's standard drag loop:

```lingo
t = the ticks
repeat while the mouseDown and ((the ticks - t) < 10)
end repeat
if the mouseDown then
  ItemObj.ItemDrag(X, Y)
  repeat while the mouseDown
    ItemObj.ItemMouseStilldown((the mouseLoc)[1], (the mouseLoc)[2])
  end repeat
  ItemObj.ItemDrop()
end if
```

In Director `the mouseDown` is a read of the hardware — ScummVM answers it from
`g_system->getEventManager()->getButtonState()` at `lingo-the.cpp:865` — so a
click shorter than 10 ticks leaves the first loop by its *first* condition and
the drag loop is never entered. Here the handler runs on Godot's main thread,
inside `_input`, and Godot's `Input` state is written only by the main loop that
the handler is blocking. So `the mouseDown` was frozen true: the first loop
always fell out on its 167 ms timeout instead, `if the mouseDown` was therefore
always true, and the drag loop then spun until the runaway guard fired. **Every
click, not an occasional one** — which is why the owner could reproduce it every
time and a headless harness, which never has an OS button to release, could not
reproduce it at all.

**The fix.** A spinning `repeat` now gives the platform its turn every 8 ms:
`_breathe` in the interpreter calls the host, the host calls
`director_preview.lingo_breathe`, and that calls `DisplayServer.process_events()`.
Two things had to go with it:

- `_input` refuses to *act* on anything that arrives during a breathe. Lingo is
  not re-entrant in Director either, so a press landing while a handler runs
  raises no second handler; it is queued and answered from the top of `_process`.
- **Godot drops a re-entrant dispatch outright**, which is measured rather than
  assumed: with a print at the top of `_input` and another around the pump, the
  click logged `breathe: live button true -> false` — the pump had taken the
  `WM_LBUTTONUP` and updated `Input`'s mask — and logged no `_input` call for it
  at all, and the run's exit report counted `mouseDown: 1` with no `mouseUp`.
  So the button events are rebuilt from the mask
  (`_queue_button_changes`) rather than waited for. A key pressed during a
  spinning loop is still lost; there is no mask to rebuild it from, and that
  divergence is written into `lingo_breathe`'s docstring.

**After, same measurement, same click:**

```
CLICK stage=(448,378)
t=  0s pump=True ... cpu=9.61s
...
t= 19s pump=True ... cpu=14.33s
clicked (447,377) frame 23  ch2  sprite script BehaviorScript 20 - screen item script  mouseUp:yes
  frame 42 script: BehaviorScript 34 - album loop
```

The pump never dies, the CPU cost drops from ~1.0 s/s to ~0.25 s/s, there is no
`repeat while did not terminate`, and the playhead reaches the album screen — the
whole click, press to `mouseUp`, arrives.

**Ruled out along the way, so nobody repeats them:** headless clicks on the same
channel (clean, 23 → 42), windowed runs at 800x600 and 2560x1440, clicks driven
through `Input.parse_input_event`, a 111-move pointer sweep, and `soundBusy(2)`
standing at 1 — which is the menu music looping and is correct. Also ruled out:
the cast-name re-parse fixed in `77f7cf3b`, measured as not the cause
(8.8 → 7.9 ms/move).

---

## 89. `the regPoint of member` was read-only, so every write of a registration point was a statement that returned having done nothing

**Status:** fixed · **Area:** `scenes/preview/members.gd` (`read_prop`'s
`regpoint` arm, and a new `write_prop`), `director/director_cast.gd`
(`set_reg_point`), `scenes/director_preview.gd` (`_set_member_prop_at`'s
fall-through), `lingo/lingo_value.gd` (`components` made public)

Director lets a script move a member's registration point, and that moves every
sprite drawn from that member at once, because `locH`/`locV` position the
*registration point* rather than the top-left corner (`DIRECTOR_ENGINE.md`
§8.10). Titles use it as a layout primitive: Itamar Park's
`setRegPointToCorner(51, 78, 1, #right, #Middle)` re-anchors 28 members to their
right-middle edge in one statement, and `addToRegPoint` nudges a range of them.

This port answered the property and could not store it. `grep -n regpoint
scenes/preview/members.gd` returned one line, the read, and
`_set_member_prop_at`'s `match` fell through to `_note_member_prop` — so the
statement returned, the read answered the authored value, and the layout the
movie asked for silently did not happen.

**The write.** `preview/members.gd:write_prop` is the new half, and it is a
sibling of `read_prop` rather than another arm in `director_preview.gd`'s match
for one reason: the properties already in that match (`editable`, `hilite`,
`text`, the text style) belong to node-owned override stores, and this one
belongs to the **member record**. `director_cast.gd:set_reg_point` writes into
the parsed cache `member()` hands out, so the next reader sees it and the cast
outliving it is the movie's own lifetime — which is Director's, for an internal
cast. The reference's chain is `Lingo::setTheCast` → `CastMember::setField` →
`BitmapCastMember::setField`'s `kTheRegPoint` arm (`castmember/bitmap.cpp` @
ScummVM 805f259a).

**The read had to move with it, and that is the part that is not obvious.** The
arm answered the stored *offset*; the reference answers the member's own
coordinates. `BitmapCastMember::getField` pushes `_regX`/`_regY` unchanged, and
the offset the painter applies is a second quantity, `getRegistrationOffset()` =
`_regX - _initialRect.left`. This port stores only the offset
(`_parse_specific`'s type-1 arm computes `regPoint - left/top`), so the origin is
added back on the way out and taken off again on the way in. Measured with
`tools/scratch/regsurvey.gd`: **97,464 of the 120,869 bitmap members** across the
six shipped titles and the two Itamar corpora have a non-zero `initial_rect`
origin, so the two readings disagree for four members in five — and it is the
round trip that makes the `addToRegPoint` idiom,
`member(i).regPoint = member(i).regPoint + point(dx, dy)`, move a member by
`(dx, dy)` instead of by `(dx, dy)` plus its own rect origin. No script in any of
the eight corpora *reads* the property, so this half is settled against the
reference and asserted by the harness rather than by a title.

**Both spellings of a point.** The reference accepts `POINT` or an `ARRAY` of at
least two elements; this port has both live at once, because `point()` makes a
`Vector2` and `the loc of sprite` answers a two-element `Array`.
`LingoValue.components` was already the single place that flattens either — it
was private and `director_preview.gd`'s `the loc of sprite` writer was already
reaching in for it — so it is public now rather than copied. A scalar is
declined and reported, not coerced: `n` read as `(n, n)` would move every sprite
drawn from the member somewhere no script asked for.

**No cache to invalidate, and that is measured rather than assumed.** The
reference calls `score->invalidateRectsForMember(this)` because it composites
dirty rectangles. This renderer repaints the stage every frame and
`sprite_geometry.stage_rect` recomputes the offset from the member on every
call, so no rect is held anywhere; `_textures` is keyed by member, ink, drawn
size and colours and `_hit_images` by member and size, and a moved anchor
changes the pixels and the size not at all. `queue_redraw()` is the whole of it.

**What it did not fix, which is worth recording because the entry was filed
believing it would.** Itamar Park's arcade objects draw at `locV` 0, and this was
filed as the cause. It is not: `defReg`, the handler that calls
`setRegPointToCorner`, occurs twice in `torfim.dir` — once as `on defReg` and
once in its script's name table — and is called from nowhere, and the 28 members
it would re-anchor are already anchored right-middle in the file, so running it
changes nothing. With the write implemented the objects are still at `locV` 0.
The real cause is `bugs.md` 94: the score *does* carry those channels, with the
row positions 340/210/110, and `director_score.gd:_snapshot` drops the records
because they state a zero size. Park's one live regPoint write is
`GiveNextBonus`, which centres the bonus artwork before placing it at the middle
of the stage.

Covered by `tools/reg_point.gd`, in `gate.sh`'s `ALL`. It asserts the
player-visible invariant rather than setter/getter agreement: it takes whichever
bitmap sprite the booted movie has on the frame it settles on, writes through
Lingo, and measures `_sprite_rect` — the same call the painter, the hit test and
`rollOver` go through. Six checks: the drawn rect moves by exactly minus the
anchor's displacement, the size is untouched, the property reads back what was
written, the list spelling lands where the point spelling did, and a scalar
moves nothing.

Reproduce the original defect on any title:

```bash
godot --headless --audio-driver Dummy --path . --script tools/reg_point.gd -- \
    --root piposh2 --boot strtgame.dir
```

Before the fix the first check fails with the drawn rect unmoved; after it,
`ch1 1:303 (68,49) -> (51,72)` for a written displacement of `(17, -23)`.

---

## 87. `beginSprite` was never sent, so Magic Hat's album screen kept the main menu's screen items and its red X close button did nothing

**Status:** FIXED · **Area:** the frame loop's per-sprite messages
(`scenes/preview/frame_loop.gd`, `scenes/preview/event_chain.gd`) · found while
fixing the click freeze in `test-games/itamar-magichat`

`docs/ENGINE_TODO.md` already records that `beginSprite`/`endSprite` are not sent
and that sending them needs a behaviour to be an **instance** with a lifetime.
This entry is the player-visible consequence of that gap in one title, so that
the cost of the entry is on record beside it rather than only its shape.

Magic Hat drives every screen through a framework in `objects.cst`
(`Screen items functions`, `BasicMenuObject`, `GraphicButtonObject`). One global
property list, `gAllScreenItems`, maps a **sprite channel** to the button object
that answers for it, and the *only* thing that rebuilds that map when a screen
changes is a behaviour's `on beginSprite`. `magichat.dir` member 33,
`BehaviorScript 33 - init album`, is the whole of it:

```lingo
on beginSprite me
  HideToolTip()
  DisableAllMenus()
  EnableMenu(#mnuAlbum)
  SetMusicFile("album_m.mp3")
end
```

`DisableAllMenus` calls `BasicMenuObject.Disable`, which calls
`RemoveScreenItem` for each of the menu's buttons; `EnableMenu` calls
`AddScreenItem` for the new screen's. Neither runs, because the message never
arrives. Measured: after clicking the album button on the main menu, with the
playhead on frame 42 and the album drawn correctly, `gAllScreenItems` still has
the keys `["2","3","4","5","6","7","8","9","10"]` — the nine **main menu**
buttons — and none of the album's.

What the player sees is not a blank screen, which is why this was never noticed.
The album draws correctly, because the score places its sprites. It breaks on the
first mouse move: `screen item script` sends `ItemMouseEnter` for the channel
under the pointer, `GetScreenItem(8)` answers the *main menu's* button 7, and
`GraphicButtonObject.ItemMouseEnter` does `me.SetMember(me.Info(#active))`. So
rolling the pointer over the album's red X close button, channel 8, swaps that
channel's member from `album:89` (the X, 40x52 at 760,34) to the main menu's
`bMain7_on` — measured as `6:13`, 273x233 at (287,0). The X is replaced by a
menu button drawn in the middle of the screen, and the corner the player is
aiming at now hits nothing:

```
before the pointer arrives:  channel_at (779,59) -> 8
after it:                    channel_at (779,59) -> 0
```

The close button therefore cannot be clicked at all, and the album is a screen a
player can enter and not leave. Every other screen in the title is built the same
way (`init magic`, `init tools`, `init login`, `init teuda`, `init credits` are
all `on beginSprite`), so this is not one screen's bug.

Reproduce, headless, in about 40 seconds:

```bash
godot --headless --audio-driver Dummy --path . --script tools/scratch/album_close.gd -- \
  --root res://test-games/itamar-magichat --file magichat.dir
```

It boots to the menu, clicks the album button at stage (448,378), prints the live
channel/member of every sprite, moves the pointer onto the X, and prints them
again. The two `channel_at` lines above are its output. In the real window the
same click sequence is
`bash` + `C:\tmp\drive.ps1 -Stage @(448,378,779,59)`; the click log line reads
`clicked (778,59) frame 42  ch0`, and `ch0` is the whole bug.

**Not a hit-test bug and not a member-name bug.** `tools/hotspots.gd --frame 42`
reports channel 8 eligible with the right rect, and the descent answers 8 for
that point until the rollover fires. `_channel_at` is reading a channel whose
member a script legitimately swapped; the script only got to run because the
engine never told the screen it had changed.

---

### What it was, and the half the entry above did not have

**`init album` is on the *behaviour channel*, not on a sprite channel.** The
entry above reads as a sprite problem and it is not: `tools/scratch/spans.gd`
says `BehaviorScript 33 - init album` is a **frame** interval spanning [34..34] —
Director's score row above the sprite channels, "sprite 0", the one a frame's own
behaviour is attached to. Seven of this title's eight screens are built the same
way: `init magic` [69], `init tools` [84], `init login` [9], `init teuda` [99],
`init credits` [114], `init intro` [124], `init retro` [134], every one of them a
frame interval whose only handler is `on beginSprite`. Sending the message to
sprite channels alone delivered 32 of them on the way into the album and still
ran none of these.

The reference does not send `beginSprite`/`endSprite` to its script channel:
`Score::killScriptInstances` and `Score::createScriptInstances`
(`lingo-events.cpp:845-856`, `:965-978`) manage `_scriptChannelScriptInstance`'s
lifetime and never call `processEvent` for it, where the channel loop in each of
them does. That is a gap in ScummVM rather than in Director, and the evidence is
outside the port: this title shipped, and seven of its screens are dead without
the message.

### The fix

`scenes/preview/frame_loop.gd:sync_sprite_lifetime`, called from
`director_preview.gd:_enter_frame_or_defer` — the one door every frame entry goes
through, and the position the reference sends from (after `prepareFrame`, before
`enterFrame`). It diffs the score's own spans at the current frame against
`_begun_sprites`, ends what left, then begins what arrived.

The lifetime is the **score span** and nothing else, which is
`Channel::_startFrame`/`_endFrame` (`channel.cpp:69-71`, `:685-688`): not a member
swap, not a puppet, not "the channel is occupied". `director_score.gd` already
decodes the spans, and only for sprites that carry a behaviour, so a title's
scriptless sprites cost nothing. Measured on `PIP2DATA/DAY1.dir`, 400 engine
frames: **472 → 525 dispatches**, of which 32 `beginSprite` and 18 `endSprite`
over 24 score steps. `tools/sprite_lifetime.gd` asserts the storm cannot come
back — a frame the playhead is standing on must send none, which is where a
Director title spends most of its time.

`go`, `play` and `updateStage` are ignored inside both messages
(`director_preview.gd:_sprite_message`), which is `Score::_disableGoPlayUpdateStage`
(`lingo-funcs.cpp:54`, `:162`, `lingo-builtins.cpp:3687` — all three warn and
return).

### Two other defects were in the way, and both are closed here

**91**, below: a regression from the same day had taken every main-menu button
off stage, so the album could not be reached at all.

**92**, below: `value()` could not parse a property-list literal containing
`point(-10, 0)`, which is exactly `bAlbum7` — the close button — in
`mainpanels.txt`. With `beginSprite` arriving and the registry correct, clicking
the X ran `AlbumMenuObject.MenuMouseUp` with a VOID button name and fell through
to its page-turning default.

### Verified

`godot --headless --audio-driver Dummy --resolution 800x600 --path . --script
tools/sprite_lifetime.gd -- --root res://test-games/itamar-magichat --file
magichat.dir` — 11 checks, 0 failed. The album opens from the menu (23 → 42), the
red X still answers the hit test *after* the rollover (channel 8, was 0), clicking
it returns to the main menu (frame 23), and the tools button then works (23 → 89).

---


## 91. A channel a script had given a member replaced the score's own record for that channel, so every one of Magic Hat's main-menu buttons went off stage

**Status:** FIXED · **Area:** `scenes/preview/sprite_state.gd:with_puppets` ·
found while verifying 87, and it was a same-day regression from `7a41b29c`

`7a41b29c` fixed the right thing — the reference draws a channel a script has
given a member whether or not anyone said `puppetSprite`, because
`Sprite::setCast` raises the `kAPCast` auto-puppet (`sprite.h:41`,
`channel.cpp:649`) — and applied it in the wrong place. `with_puppets` builds a
`frozen` map and then **drops the frame's own record for every channel in it**,
which is correct for a whole-sprite puppet (`Sprite::replaceFrom` returns early on
`_puppet`, so the score never reconciles it) and wrong for an auto-puppet.

An auto-puppet is a per-field mask: `setClean` copies every field the mask does
not name, so the script's member sits **on top of** the score's position, ink and
size. This port does that merge in `_effective`, which needs the score's record to
merge onto — and the new arm took it away, handing the channel
`channel.gd:_bare_sprite` at loc (0,0) instead.

Measured on `test-games/itamar-magichat` frame 23, where the nine main-menu
buttons are score sprites in channels 2-10 and their behaviour writes
`me.SetMember(...)` on every rollover:

```
ch8   score (287,0) 273x233        with the regression  (-113,-300) 273x233
```

— its own registration point negated, because loc was 0 and `reg(113,300)` was
subtracted. All nine were off stage, `channel_at` answered 0 anywhere on the menu,
and the title could not be clicked past its first screen. `bugs.md` 87's own
headless repro had stopped reproducing: it stayed on frame 23 instead of reaching
the album on 42.

**Fixed** by skipping the auto-puppet arm for any channel the frame's score list
already carries. The whole-sprite arm is untouched, which is the point: the two
halves of the rule are not the same rule.

Reproduce the regression by reverting `sprite_state.gd` and `channel.gd` to
`64594c3b` and running `tools/sprite_lifetime.gd` against magichat; the album case
fails at the first check.

---

## 92. `value()` lost a whole property list when one of its values was a `point()`, so three of Magic Hat's screen buttons had no name and no artwork

**Status:** FIXED · **Area:** `lingo/lingo_builtins.gd:_value_of`,
`_split_top_level`, `_top_colon` · found while verifying 87

Magic Hat describes every screen button as a Lingo property-list literal in
`mainpanels.txt` and reads it back with `value()`. Three of them carry a point:

```
bAlbum7=[#Name:"close",#Active:"bAlbum7_on",#NotActive:"bAlbum7_of",#tooltip:"bAlbum7_tt",#tooltipofs:point(-10,0)]
```

`_split_top_level` tracked brackets and quotes and **not parens**, so the comma
inside `point(-10,0)` split the literal. The trailing fragment `0)` has no
top-level colon, `_parse_container` therefore decided the literal was not keyed,
and a nine-property list came back as a two-element *list*.

Measured, before the fix, in `gAllScreenItems` on the album screen — every button
but three held its authored properties, and those three held nothing:

```
key 7  ... "Name": "schema", "Active": "bAlbum6_on", ... (nine keys)
key 8  ... "": ""
key 9  ... "Name": "magic1", "NotActive": "bAlbum8_of", ...
```

Key 8 is `bAlbum7`, the album's close button; keys 19 and 20 are `bAlbum18` and
`bAlbum19`, its schema arrows, and they carry `point(0,-7)`. So `Info(#Name)`
answered VOID for exactly those three, `AlbumMenuObject.MenuMouseUp`'s `case` fell
through to its page-turning default, and clicking the close button ran
`go(label("album") + 1)` — the album re-entered itself. It also left
`prMemberName` VOID, so those three buttons never got their artwork.

**Fixed** in two parts, both general: `(` and `)` count toward the depth in
`_split_top_level` and `_top_colon`, and `_value_of` now builds a `point(h,v)` and
a `rect(l,t,r,b)`. Director's `value()` evaluates a whole Lingo expression, so
neither is a special case there; these two are the constructors that turn up as
data.

## 97. A film loop re-shown on a channel resumed past its own end, so the first flowerpot in each of Piposh Dream's three lanes fell and every later one arrived already smashed on the ground

**Status:** FIXED · **Area:** `scenes/director_preview.gd:lingo_set_sprite_prop`,
`_assigned_member` · found from a player's report and two screenshots, after two
wrong theories of my own

A film loop's drawn frame is `_ticks - _loop_start[channel]`, and `_loop_start`
was set from exactly one place: `preview/stage_paint.gd`, which calls
`_note_member` for every sprite it **draws**. A hidden sprite is not drawn --
`_effective` answers `{}` for one -- so the painter cannot see a member the
channel held while it was invisible.

COMEIN's pot game is that case, written by an author who had no reason to avoid
it. The drop handler blanks all three pot channels and then dresses one:

```lingo
set the member of sprite 27 to member(87, 1)   -- and 28, and 29, all hidden
...
sprite(26 + x).visible = 1
set the member of sprite (26 + x) to member(83 + x, 1)
```

So a channel goes `84 -> 87 -> 84`. The 87 is never painted, `_last_member` still
reads 84, the re-assignment looks like no change, `note_member` takes its early
return, and the loop is never restarted. The pot is a **14-frame non-looping**
loop, so `director_film_loop.gd:_wrap` clamps every phase past the end to the last
frame -- the pot already smashed.

Measured, the loop frame each pot was on at the moment it became visible:

```
ch29 member 86  frame 0     <- falls
ch29 member 86  frame 28    <- arrives landed
ch28 member 85  frame 0     <- falls
ch28 member 85  frame 28
ch28 member 85  frame 56
ch29 member 86  frame 196
ch27 member 84  frame 0     <- falls
```

**The shape is the diagnosis.** The first drop into each lane puts a genuinely new
member on that channel, so the paint-path reset does fire and that pot falls. Three
lanes, three good falls, then nothing for the rest of the game -- which the player
reported as "at the beginning everything works as expected" and "I see the pots
once they hit the ground but I don't see them falling". A theory that only
explained "pots do not fall" would not have predicted the three.

Fixed by noticing the member where a script **assigns** it as well as where the
painter draws it. Director restarts a loop from `setCast` rather than from the
painter, so the assignment is the honest event; that reading is from the reference
and is not measured against Director running.

**The first attempt was wrong and the gate caught it, which is worth recording.**
It reused `note_member`, which writes `_last_member` -- and `tools/update_stage.gd`
uses that dictionary as its probe for *what the painter drew*, to prove
`updateStage` paints inside a handler. Writing it from the assignment path made the
paint appear to have seen a value assigned after it: 87 PASS, 1 FAIL, and the FAIL
was the harness whose whole subject is that distinction. The assignment now keeps
its own record in `_assigned_member`, `_last_member` keeps meaning what was drawn,
and only the start tick is shared. That field is cleared with the rest of the
per-movie state in `preview/movie_session.gd` and registered in
`preview/save_state.gd`'s manifest, which requires a disposition for every field.

Covered by `tools/film_loop_restart.gd`, in `gate.sh`'s `ALL`. It plays the game
rather than staging it -- rings the doorbell the way a player does, because
arriving at the next marker skips the `puppetSprite` init, and presses the arrows
on the movie's own clock -- and it fails a lane that takes a second drop starting
anywhere but frame one. Verified in both directions: without the fix, 6 of 9 drops
start at frames 27-282 and it exits 1; with it, 9 drops over 3 lanes, all three
repeated, every one at frame 0. It also refuses to pass on a run that produced no
repeat, so a lucky sequence of lanes cannot make it green for nothing.

---

## 98. A film loop whose child is itself a film loop drew nothing, so Piposh Dream's projectile game had no projectiles in it

**Status:** FIXED · **Area:** `scenes/preview/film_loop_view.gd:paint_loop`,
`director/director_film_loop.gd:frame_index` · found from a player-visible report
("there are no projectiles here") and confirmed against the painter's own tallies

`film_loop_view.draw` drew a loop's children by building a sprite record per child
and asking `host._texture_for` for it. That path is **bitmap-and-shape only**
(`preview/sprite_art.gd:texture_for` returns null for every other type), so a
type-2 child — a film loop nested inside a film loop — answered null, was tallied
`"child has no art"`, and the whole inner loop was skipped. No recursion existed.

Director nests: a loop's sub-channels expand inline at the parent's position in the
parent's order (`DIRECTOR_ENGINE.md` §1.6, §6.3). So this was a hole rather than a
limitation, and any title with a loop inside a loop had an invisible element.

`piposh-dream`'s `COMEIN.dir` is the site. Hatuli's projectile game throws one of
three 21-frame `looping=false` ball loops (`1:156`..`1:158`), each of which nests
the 8-frame `looping=true` `stone` (`1:167`), and `stone`'s own eight children
(`1:159`..`1:166`) are the picture on screen. Measured over 30 top-level loop
paints, entered at f720 and bounded on depth-0 `"loop drawn"` rather than on
process frames, because the two states do different work per frame:

```
                                  before   after
loop drawn / children offered      30/30   30/30
nested loop drawn / offered            -   28/28
child drawn                           11      30
child has no art                      19       0
stone's 8 frames in the texture cache  0       8
```

**All 19 misses were member `1:167` itself** — the nested loop, skipped whole —
and the residue after the fix is 0 rather than small. The eight projectile bitmaps
are reachable by no other route: `1:159`..`1:166` appear in no score record and are
nobody's depth-1 child, so before this they could not be drawn at all.

Scope is small and was measured rather than assumed. Over all six roots, every film
loop, every child resolved through `child_lib` and its member type read: **10 nested
sites in 2 titles.** `piposh-dream`'s `comein.dir` (3), `hatul1.dir` (`1:119`
→ `1:71`) and `show.dir` (`1:29` → `1:25`); `rating`'s `blatack1.dir` (`1:77`,
`1:79`..`1:82` → `1:76`). `piposh`, `piposh-en`, `piposh-ru` and `piposh2` have
**none**, which is why no gate entry pinned to `GATE_ROOT` could ever have caught
this. The deepest nesting anywhere is 2 and nothing nests itself.

**Which of the six games it hit, derived from the movie rather than from a table.**
`COMEIN.dir` holds one minigame per character, and `tools/puppet_members.gd` recovers
them structurally: a frame script calling `puppetSprite(N, 1)` claims a channel and
is therefore an init. COMEIN has 15 frame scripts mentioning `puppetSprite` — **6
claim and 9 release** — so counting mentions would have reported fifteen games, the
nine extras all being ending and win screens. The six, with the members their
handlers actually assign:

| scene | init | channels | film loops | nests |
|---|---|---|---|---|
| fritz | `return1` f179 | 27,28,29 | 84,85,86 `plant1..3` 14f | no |
| doc | `return2` f295 | 27,28,29 | 187,188,189 `spear1..3` 18f | no |
| krup | `return3` f450 | 27,28,29 | 84,85,86 | no |
| raf | `return4` f587 | 27,28,29 | 84,85,86 | no |
| **hat** | `return5` f723 | 3,4,27,28,29 | 156,157,158 `ball1..3` 21f | **yes, all three** |
| poz | `return6` f895 | 3,4,27,28,29 | 187,188,189 | no |

So **exactly one of the six games was affected** — Hatuli's. `plantcounter` matches
each game's loop length throughout (14/18/14/14/21/18), which is the movie's own
confirmation that the element loops are the ones tabulated. All six were entered and
played; `hat` is the end-to-end confirmation, with all three ball loops dressed onto
their channels and all 8 of `1:167`'s own children reaching the texture cache
(`nested loop drawn 51`).

Worth recording because it cost a session's worth of confusion: an earlier hand-made
table of this game listed "init member 80, drop 81, collision 88" as the elements.
**Those are the script members, not the elements** — which is why its numbers never
overlapped the census's `1:156`/`1:157`/`1:158`.

### Which frame a nested loop is on

A nested loop has no channel, so it has no entry in `_loop_start` and no counter of
its own. The reading implemented is that **it takes its parent's already-wrapped
frame index and wraps that again by its own `frame_count` and its own `looping`
flag** — not the parent's raw `ticks - loop_start[channel]`.

**The corpus's own `looping` flags decide it, and they decide it the same way at
both sites that have one.** COMEIN's ball loops are `looping=false` over 21 frames
nesting a `looping=true` stone over 8: pass the raw counter down and the stone goes
on spinning for ever after the ball has clamped on its last frame, which is a landed
stone still rotating. `rating/blatack1.dir`'s `grnd2`..`grnd5` are the mirror —
`looping=true` over 16 frames nesting a `looping=false` `explode1` over 17 — and
with the raw counter the explosion freezes on its last frame after one cycle while
the ground animation keeps going. The wrapped reading is right at both; the raw
reading is wrong at both. It also makes "a non-looping loop holds on its last frame"
mean the whole composite holds, which is what holding ought to mean.

**Reference-derived and unverified against real Director, because ScummVM has this
same gap and cannot be asked.** `window.cpp:218` expands sub-channels exactly one
level and blits each without ever asking `hasSubChannels()`; `score.cpp:952`
advances `_filmLoopFrame` only over main-score channels; and `getSubChannels` builds
every sub-channel as a fresh `Channel` whose `_filmLoopFrame` is 0
(`channel.cpp:61`), so a nested loop there would freeze on its own frame 0 even if
it were expanded. What the reference does supply is the *shape*:
`getSubChannels(bbox, frame)` is a pure function of `frame`, so what a loop shows at
frame N is a function of N alone, and extended recursively the frame a nested loop
expands at is the parent's own index.

### Three things the shape of the fix is careful about

**Nothing was added to the preview node.** Everything the recursion needs is a
parameter, because a new `_` field would have to be classified in
`preview/save_state.gd`'s `ACCOUNTED` manifest, cleared in
`preview/movie_session.gd` and asserted by `tools/preview_surface.gd`, and none of
those has anything to say about a value that does not outlive one paint. The one
thing shared is the existing `loops` parse cache, keyed `"lib:id"` — which is also
what makes a self-nesting loop hit the cache instead of re-parsing per level.

**The nested `open_loop` is handed the child's resolved library, never the
parent's.** A nested loop's children index the *nested loop's own container's*
`ccl ` list, and `open_loop` takes that list from the library it is given; handing
it the parent's is exactly the failure `director/director_film_loop.gd`'s docstring
is built around — a real member out of an unrelated cast, drawn, with nothing
reporting it (entry 34).

**The top-left is threaded in rather than re-derived.** The top level computes it
with `stage_origin`; each recursive call computes it with the same `place_child`
expression a bitmap child already gets. One placement path, so a nested loop cannot
drift from its siblings the first time either rule changes. `nested_scale` composes
the squeeze and does **not** go through `Geometry.drawn_size`, which when this landed
was forced rather than chosen: `drawn_size` discarded a scaled child's size, and that
is **entry 99 in this file, now fixed**. So a reader arriving here should not carry
the old reason away — with the marker honoured, `child_scale` on the same record
answers exactly what `nested_scale` answers. The two stay apart because one is a
function of a size and the other of a whole sprite record, and `nested_scale`'s own
docstring carries that.

`MAX_DEPTH` bounds a loop that contains itself, and the cap tallies a key rather
than returning quietly. Depth 0 keeps every tally key it always printed, so figures
quoted in older commits still mean what they said; deeper levels take a `"nested "`
prefix. The two leaf keys are shared at every depth, because `"child drawn"` and
`"child has no art"` are facts about a leaf rather than about a level.

### Coverage

`tools/film_loop_nesting.gd`, in `gate.sh`'s `ALL` as
`film_loop_nesting:--root@piposh-dream`:

```
godot --headless --path . --script tools/film_loop_nesting.gd -- --root piposh-dream
```

It **plays** the game rather than staging it. Landing on `return5` (f723), the
game's own init marker, skips the `puppetSprite` and the globals and produces a
convincing dead screen — so the playhead is put down at f720, inside the speech that
precedes the game, and the movie runs f722, f723 and f724 itself.

What it asserts is that a member reachable **only** through a nested loop appears in
the node's `_textures` cache, which is the painter asking the cast to decode it. Not
that a new tally key exists: a counter reading zero before a fix only because the
key had not been invented yet asserts that the new code ran and nothing about the
engine. The "only through a nested loop" set is derived rather than named — the
container's loops are walked as a graph, a loop that is nobody's child is a root, and
a member is claimed only if every route to it is two levels deep or more *and* the
score never places it directly. For `COMEIN` that recovers exactly
`1:159`..`1:166`. Beside it, and in `tools/film_loop_scale.gd`'s idiom, a population
guard asserts that a loop with a film-loop child really was painted, so a run that
never reached the game fails as a run that proved nothing rather than passing over an
empty set.

Verified in both directions, headless. With only the two engine files reverted and
the same harness in the tree: both guards green, the leaf check red with `no key for
any of ["1:159"..."1:166"] in the texture cache`, exit 1 — an assertion failure and
not a compile error. That control needed the harness to stop reading
`FilmLoopView.MAX_DEPTH`, which does not exist at HEAD and would have made the revert
a parse error before the first assertion, which is the silent-hang failure mode
AGENTS.md warns about; it carries its own `DEPTH_CAP` for exactly that reason.

`tools/film_loop_scale.gd` covers the other half — that the composed placement is
*right*, not merely present. It descends one level and applies its existing
comparison to grandchildren, measured against the nested loop's own rect on stage
rather than against the top-level sprite's box, which would be stronger than that
file's own reasoning allows and would fail on the 248-of-4,901 children its header
defends. 4,044 grandchildren over 5 nested sites in `piposh-dream` and 1,394 over 5
in `rating`, 0 regressed; `piposh2` nests nothing, so its population guard is
conditional and its detail line says which of the two cases a run is. Negative
control measured: replacing `nested_scale` with `Vector2.ONE` regresses **3,764 of
4,044**, and 280 of those fail at natural size too.

**One gap in that coverage, stated rather than left to be found: nothing notices a
nested loop going one registration offset sideways.** Dropping the nested
`Geometry.scaled_reg` does not turn `film_loop_scale` red — it pushes 1,689 of 4,044
grandchildren outside their box *at natural size*, and the comparison discipline then
excludes exactly those, leaving the remaining 2,355 inside both. Asserting
natural-size containment outright would close it (measured 0 of 4,044 and 0 of 1,394)
and was declined on AGENTS.md's rule about asserting what the port controls rather
than what a 1990s cast got right: that count is a property of those casts' authoring,
and a third title may legitimately carry a loop whose rect is not the union of its
contents. It is printed as a number instead.

**`film_loop_cast` passed throughout this bug and that is not a defect in it.** It
asks whether a child resolves to the right *cast* — a question about the `ccl ` list,
answered off the disc — and a child that resolved perfectly and then drew nothing
answers it correctly. A green gate is not coverage of a question nobody asked, which
is why this needed a new entry rather than an extra check in an old one.

---

## 99. A squeezed film loop scaled where its children go and not how big they are, so Hatuli's thrown stones flew in perspective at a constant size

**Status:** FIXED · **Area:** `scenes/preview/sprite_geometry.gd:drawn_size`,
`scenes/preview/film_loop_view.gd:child_sprite` · found at the unit level while
implementing nested film loops (entry 98) and **reported from play** as "the balls
in Hatuli's game aren't shrinking when moving", which is what got it fixed

A loop drawn at a size other than its `initialRect` scales everything inside it by
`drawn / natural` — the child positions **and the children themselves** (§1.6).
`child_sprite` did the second half: it resolved the child's size and multiplied it
by `child_scale`'s factor. `Geometry.drawn_size` then threw that away, because with
the stretch flag clear it returned the member's **natural** size.

```
stretch=false   child_sprite -> 18x18, drawn_size -> (72.0, 72.0)
stretch=true    child_sprite -> 10x10, drawn_size -> (10.0, 10.0)
```

So the flag that decides whether a rect is authoring residue was being asked about
a rect that cannot be residue: a film-loop child's record is built in `child_sprite`
a moment before it is drawn. Net effect, the contents were placed by scaled
coordinates and drawn at full size — and the anchor went with the artwork, because
`film_loop_view.draw`'s leaf branch takes the child's registration offset from
`Geometry.scaled_reg(cm, texture.get_size())` and that texture came back unscaled.

**The player's half, measured off the disc.** In `games/piposh-dream/COMEIN.dir`,
Hatuli's projectile game throws the ball loops `1:156`..`1:158` (21 frames each),
which nest the `stone` loop `1:167` (8 frames), whose own frames are the bitmaps
`1:159`..`1:166`:

```
member 1:156 "ball1(21)" 539x481 type=2
  f0   child 1:167  rect  72x72  stretch=false loc( 645,-116)
  f8   child 1:167  rect  69x69  stretch=true  loc( 442, 256)
  f14  child 1:167  rect  52x53  stretch=true  loc( 267, 303)
  f20  child 1:167  rect  20x21  stretch=true  loc( 152, 292)
member 1:167 "stone" 72x72 type=2
  f0..f7  children 1:159..1:166, 69x64 .. 72x71, all stretch=false
```

The ball loop *authors* the shrink and the engine read it — the shrinking frames
carry `stretch=true`, and `nested_scale` turned it into a shrinking factor for the
nested loop correctly. The failure was one level further down: the stone's eight
grandchild bitmaps all carry `stretch=false`, so `child_sprite` scaled them and
`drawn_size` discarded it. The stone's position scaled and its pixels never did.

**Why it looked correct.** `child_sprite`'s docstring separated the two populations
on the flag — of the 2,053 children in this corpus carrying it, zero have a rect
equal to their member's natural size, so with the flag clear the *recorded* rect
really is residue. That argument is true and it is about which rect to start from.
It was silently doing a second job it cannot do, because the size in question after
a squeeze is not on the disc at all.

### The fix, and the two fixes refused

`child_sprite` now marks the record with `Geometry.SIZE_COMPUTED` when the scale is
not `Vector2.ONE`, and `drawn_size` honours that marker alongside `stretch` and
`size_from_script`.

**Refused: making `drawn_size` trust a bare non-stretch record's size.** That is
entry 31 reintroduced for score sprites, and reading residue is exactly what 31
closed — `WRESTLE.dir` channel 9's constant foreign 556x438, `INVENTOR.dir`'s 1x1
`dot` on two channels of 92x17 and 78x14.

**Refused: carrying it on `size_from_script`.** Justified by grep rather than by
taste: that key has exactly **one writer** (`preview/channel.gd:429`, the `size`
kind, which is `the width of sprite N` and its `height` twin) and **one reader**
(`drawn_size`), and it means "a Lingo write set this" — a claim with a release rule
and an auto-puppet story attached. `bugs.md` 80 turns the same key down for a third
cause, a field grown by its own laid-out text, on the same grounds. A `drawn_size`
that cannot tell the three apart cannot be reasoned about later, and nothing else in
the port — `channel.gd`'s `FIELDS`, `sprite_props`, `save_state`, `tools/` — reads
either key at all.

**The marker is tested above the shape and field branches**, which is load-bearing
rather than tidy: a squeezed loop's field child must be drawn at `natural * scale`
like everything else inside the loop, and `_field_size`'s
`MAX(bbox, initialRect, maxHeight)` would take it straight back to the member's own
size. The degenerate-rect guards above it cannot swallow a marked record either,
because `child_sprite` clamps a scaled size to `maxi(1, …)` in the same branch that
sets the marker.

### The blast radius is the population that was wrong

At natural size `child_scale` returns `Vector2.ONE` exactly, so `child_sprite`
scales nothing, marks nothing, and produces the record it always did. Confirmed by
measurement rather than by argument: every natural-size control in
`tools/film_loop_scale.gd` is unchanged to the child — 96 of 48,846 children in
`piposh2`, 463 of 28,213 in `piposh-dream`, 214 of 2,792 in `rating`, before and
after.

The registration offset now scales with the artwork, which is intended and is what
`place_child`'s docstring already described: scaling both is what makes either
correct. The nested branch is unaffected — it passes `Geometry.scaled_reg(cm, size)`
from `child_sprite`'s record, and with the marker set `drawn_size` returns that same
size.

### Before and after

`tools/film_loop_scale.gd` asserted this rule and could not see the failure, because
it read `child_sprite`'s own answer as the drawn size instead of asking `drawn_size`
the way the painter does — a harness green over the wrong noun. Its `_case` now
reads both, one per painter branch, so it is a permanent reading rather than a
temporary experiment. With that reading and the fix reverted:

| root | before | after | natural-size control | nested |
|---|---|---|---|---|
| `piposh2` | 41,816 regressed, 6,934 held | **0 regressed, 48,750 held** | 96 / 48,846 both ways | 0 over 0 sites |
| `piposh-dream` | 26,746 regressed, 1,004 held | **0 regressed, 27,750 held** | 463 / 28,213 both ways | 0 over 4,044 both ways |
| `rating` | 2,077 regressed, 501 held | **0 regressed, 2,578 held** | 214 / 2,792 both ways | 0 over 1,394 both ways |

over 1,400 of 1,400 loops that really scale in `piposh2` (86 containers), 1,502 of
1,502 in `piposh-dream` (79) and 230 of 230 in `rating` (118). "Regressed" is that
harness's own noun: a child inside its box at natural size and outside it once the
loop is squeezed to a quarter. So 85.8%, 96.4% and 80.6% of the children that had
anything to prove failed, and now none does — the held column absorbs exactly the
regressed one.

**The tolerance was deliberately left derived from `child_sprite`'s scaled answer.**
Recomputing it against the new reading makes the allowance `0.75 × natural` at that
squeeze and reports 0 regressed by cancelling the bug rather than by its absence.
That is the one edit in the file that would read as tidying and would disarm it,
and `_case` now says so at the site.

### What covers the player's report

`tools/film_loop_nesting.gd` asserted that a nested loop's leaf artwork reaches the
painter and said nothing about its size, which is this bug. It now also asserts that
one leaf member is decoded at **more than one size** across the throw, read off the
node's `_textures` cache — keyed by `Geometry.texture_key`, whose fourth field is
the drawn size, so several keys for one member is the observable and nothing here
recomputes an expected size. Measured on `--root piposh-dream`:

```
after   1:159 69x64 -> 66x61,  1,343 of 12,000 process frames, 33 score frames f721..f753
before  every one of the eight leaves at a single size,
        12,000 of 12,000 process frames, 49 score frames f722..f771
```

The control fails on that check alone with the two above it green, which is the
useful shape — the artwork was arriving all along and only its size was wrong — and
it is not a budget failure: the failing run got *more* score frames than the passing
one and still saw one size per leaf.

### Still not measured on screen

`PIPDATA/DISKSHOT.dir` is the other site — clay pigeons of about 26x7 swapping to
the 287x279 `diskblow` loop whose child sits at (320,240) — and the open entry's
claim that the explosion "now draws full-size on the disk" was inferred from the
mechanism rather than seen. It should be right now for the same reason the stone is,
and nobody has taken the screenshot.

### Left behind

`nested_scale` and `child_scale` are now the same rule twice: with the marker
honoured, `child_scale(record, member)` would answer exactly what `nested_scale`
answers for every record `paint_loop` hands it. They are not merged because
`nested_scale` is a function of a size, which is what the recursion has, while
`child_scale` wants a sprite record with a `loc_h`, a channel and a member
reference — folding them would mean synthesising a fake record per level. The
equivalence is written into `nested_scale`'s docstring so that a third branch on
either side is noticed.

---

## 101. A right click reported itself as a failed `mouseUp`, and the label sent a diagnosis into the wrong half of the engine

**Status:** FIXED · **Area:** `scenes/preview/snapshot.gd:click_line`,
`scenes/preview/interaction.gd:press` · found from a player's snapshot, and from
the wrong theory it produced

`interaction.gd:press` decides whether a handler exists by asking against the
**pair being sent** — `click_events(right)` answers `rightmouseup` for the right
button — while `snapshot.gd:click_line` printed the word `mouseUp`
unconditionally. So a player's snapshot of a right click on
`piposh-dream/eat.dir` frame 22 read:

```
clicked (135,376) frame 22  ch19  frame script BehaviorScript 115  mouseUp:NO HANDLER
```

about a sprite whose behaviour `1:121` — shared by all nine characters in that
scene — declares `mouseUp` and runs it correctly on a left click. Same point, same
frame, same run:

```
clicked (135,376) frame 22  ch19  sprite script BehaviorScript 121  mouseUp:yes
   ran mouseUp@sprite: 0 -> 1
```

**The routing was never wrong.** `script_for_click` resolves the chain against the
pair being dispatched, `1:121` declares only `mouseUp`, so no tier answers
`rightMouseUp` and the message correctly falls through to the frame script — which
`BehaviorScript 115` genuinely is on that one frame (`frame ch0 frames 22..22`;
120 covers 4..21). And `interaction.gd:2229` already records **0**
`rightMouseDown`/`rightMouseUp` handlers across all six titles, so a right click on
any authored hotspot in this corpus does nothing, everywhere, by authoring.

**What this entry is really about is the cost of the label.** `tools/hotspots.gd`
was run on the frame and reported the truth — ch19 eligible, `[1:121 mouseUp]`
attached — and the two facts together were read as "a behaviour that declares
`mouseUp` was skipped", which sent a session into `scripts.gd`'s message hierarchy
looking for a dispatch bug that does not exist. Four hypotheses were built on a
word. The engine's own report is not a neutral observation when it hardcodes the
question it claims to have asked.

Fixed by carrying the tested message in the record, so a right click reports
`rightMouseUp:`. Reproduce the old reading with `route_right_button(at, true)` /
`(at, false)`.

Asserted now in three places, all in entries already in `gate.sh`'s `ALL`, so the
count did not move: `tools/snapshot_check.gd` (15 → 19 checks) that a right click is
reported as the right pair; `tools/mouse_events.gd` (50 → 56) that a click on a
sprite whose behaviour declares `mouseUp` reaches it, with the subject **found**
rather than named — 270 such (frame, channel) pairs in `strtgame.dir` and 216 in
`eat.dir` — plus the right-click half of the same rule.

**`tools/click_chain.gd` was measured blind to this whole path**, which is why the
new checks went where they did: with the sprite tier skipped in `script_for_click`,
`mouse_events` fails 3 and reproduces the player's snapshot line exactly, while
`click_chain` passes 30 of 30. Break the *delivery* path instead and `click_chain`
does fail — so it gates what a behaviour receives and never what the record says
answered.

---

## 102. A numeric field designator resolved to nothing in both directions, so Piposh Dream's plate game could be neither won nor lost

**Status:** FIXED · **Area:** `lingo/lingo_interpreter.gd:_field_designator` and
the host surface it calls · found while chasing 101, from a player's "the
characters are not clickable"

`field 122` and `field "122"` are different references: the first is member number
122, the second a member *named* `122`, which no cast here has. The interpreter
stringified the subscript of every `field` designator, and the whole host surface
then typed it `String` — so `preview/members.gd:resolve_ref`, where INT means a
member number and String means a member name, searched for a member called `122`.
Reads answered `""` and writes were dropped.

Measured in isolation:

```
named read before                              : 6
named read after `put "3" into field 122`      : 6      <- write dropped
named read after `put "7" into field "chara5"` : 7      <- same member, works
`the text of field 122`      ->
`the text of field "chara5"` -> 7
```

**`eat.dir`'s plate game is the measured cost.** `BehaviorScript 120` (frames
4..21) counts nine countdown fields down with

```lingo
repeat with i = 122 to 130
  put value(the text of field i) - 1 into field i
```

and `BehaviorScript 121`, the behaviour on all nine characters, gates the pass on
`value(the text of field ("chara" & n)) <= 4`. Members 122–130 are the fields named
`chara5`…`chara21`. Frozen at 10 on every frame, the gate never opened **and** the
`< 0 → go("gameover")` arm never fired: nine characters that answer every click by
doing nothing, in a scene with no win and no loss, playhead pinned to frames 4..22.
Exactly the report.

Fixed by keeping the subscript's type: int and float stay numbers (a float because
`field (i + 1)` after a division is still a number Director resolves by number),
everything else stringifies. The type is destroyed in the interpreter and
re-destroyed by the host signatures, so the fix spans both — `_field_designator` at
all four sites, `Variant` through `preview_lingo_host.gd`'s four field methods and
`director_preview.gd`'s five, and `str(name)` in `text_art.gd:resolve`'s name walk.

It names no movie, member or channel: it is one type-preservation rule in the
language surface, and it fixes every numeric field reference in every title
identically. **Before: 0 of 8 plates delivered over 4,000 frames. After: 8 of 8,
`chara5` counts 10 → 0, and the movie leaves the loop and reaches `win`.**

Reach, so nobody reads "0 uses" off a literal search: there are **0** literal
`field <digits>` anywhere in the corpus, which is why this survived — the corpus
spells it with a variable. `field <var>` occurrences are 81 / 17 / 6 / 15 / 15 / 0
for piposh2 / piposh / piposh-dream / piposh-en / piposh-ru / rating (upper bounds;
a linked cast's scripts appear in both the movie and the standalone export).

Bounded and asserted rather than argued: a numeric designator naming a **non-field**
member still resolves to nothing, because `text_art.gd:resolve` accepts the
by-number answer only when the type is `TYPE_FIELD` and otherwise walks names.

Gated by `tools/field_designator.gd` (13 → 19 checks), already in `ALL`. With the
interpreter arm reverted it fails 4, naming `a write by number lands on the member
the name names`. Click routing is untouched, which matters because widening
eligibility makes sprites absorb clicks that used to fall through:
`tools/click_eligibility.gd` run before and after over 61 movies, 61,371 frames and
816,344 sprite records is **identical** on all four measured lines — 155,432 records
answer a click, 12,153 frames have at least one, 2,401 sprite intervals resolve to a
script and 281 do not.

---

## 104. A bitmap whose named palette does not resolve fell back to the stage table instead of system Mac, so Piposh's face drew grey in Piposh Dream

**Status:** FIXED · **Area:** `scenes/preview/palette_view.gd:table_for_member` ·
found from a player's "piposh color is wrong from time to time, its blue instead
of the right one", with `.snapshots/2026-08-13T23-02-08.png`

`piposh-dream/dinner1.dir` #87 is the 738x439 close-up of Piposh pointing. It names
palette member **154**, and 154 in that cast is a **type-2 film loop** named `fds` —
no cast the movie can reach holds a palette member at all. So the palette does not
resolve, and `table_for_member` handed the decoder the **stage** table.

Six of that title's 52 movies declare the **Windows D5** table as their default
(`config.default_palette` = -102; the other 46 declare system Mac), and
`director_palette_state.reset` starts the stage on the movie default with
`cached_id` cleared. `dinner1.dir` writes -1 to the palette channel on frames 0,
1405, 1830 and 1845 only, so a linear play from frame 0 puts the stage on system Mac
and the art is right — and entering the movie anywhere between 1406 and 1811, which
is where the reported frame 1776 and its `New Marker` sit, leaves the stage on Win
D5. **That is the "from time to time": the same member, two entry paths, two
palettes.**

The fingerprint that identified it before any code was read. Skin is index 8:

```
index 8   system Mac #ffcc99      Win D5 #a0a0a4
```

`#a0a0a4` is not in the system Mac table at any index — it is not a multiple of 51
and not on any of the four ramps — and the player's screenshot carries **214,739
pixels of it**, its third most common colour. Decoding #87 under each table and
looking at the two images settled it in one step: system Mac gives peach skin, pink
eyelids and a blue shirt; Win D5 gives grey skin, magenta eyebrows and a green
mouth, which is the screenshot.

**The reference falls back to system Mac, not to the stage** —
`castmember/bitmap.cpp:484`, `getDitherImg` case 8:

```cpp
CastMemberID palIndex = pals.contains(castPaletteId)
    ? castPaletteId : CastMemberID(kClutSystemMac, -1);
```

`srcPal` is what turns indices into RGB, and on a true-colour stage
(`targetBpp != 1`) that branch runs for every 8-bit bitmap. The 4-bit case at `:461`
is the same line again.

**The competing fix is ruled out by the reference too.** "-102 is misread, the stage
should be system Mac" would also have whitened the screenshot, and it is wrong:
`movie.cpp:287` substitutes system Mac for the movie default only when it does
**not** have that palette, and it has -102. The port's config read matches
`cast.cpp:592` byte for byte, including the `member -= 1` offset. So the reference's
stage is Win D5 for `dinner1.dir` as well, and it *still* draws #87 through system
Mac. Only the member fallback was wrong.

Fixed in one expression: `table_for_member` returns
`Palette.builtin(Palette.SYSTEM_MAC)` rather than `stage` when the member's own
palette does not build. The `id == stage_id` short-circuit above it is untouched,
which is what still carries §11's fades and cycles to every member naming the
palette the stage is actually on.

Measured through `SpriteArt.texture_for`, on `dinner1.dir` #87 with the stage on the
movie's own declared default, before and after:

```
stage id -102 in both runs, table[8] = #a0a0a4

           before      after     what it is
#a0a0a4 -> #ffcc99     18,374 px  skin
#cc00ff -> #ff9999      1,020 px  eyebrows
#008000 -> #222222        443 px  mouth patch
#f0f0f0 -> #eeeeee      1,512 px  highlight
unchanged: #66ccff 52,833  #000000 22,774  #3399ff 11,516  #cc9900 5,739  #666699 456
```

Five of the nine colours are the same RGB at the same index in both tables, which is
why the picture read as "mostly plausible, wrong in places" rather than as a corrupt
decode.

Corpus-wide the change reaches **167 members, all in `piposh-dream`**: the 81 in a
Windows-default movie change colour, the other 86 do not, because their stage was
already system Mac. Nothing in the other five titles moves — `piposh`, `piposh-en`,
`rating` have no dangling-palette bitmaps at all, and `piposh-ru`/`piposh2` have
none either.

**Covered by `tools/palette_corpus.gd`, which had this check and could not fail
it.** It asserted the fallback while passing `system` in as the stage, so
"fall back to the stage" and "fall back to system Mac" returned the same bytes and
the check agreed with itself over 651 containers. It now passes each movie its own
`config.default_palette` and floors the population the rule is observable on
(`MIN_DANGLING_OFF_MAC`, measured 81), so it cannot go vacuous again. Verified both
ways, headless: **FAIL at 81 of 167 without the fix, PASS with it**, 15 checks where
there were 14. `ALL` is unchanged at 89 entries.

---

**The twenty entries below were closed on 2026-08-14, in one sweep of the whole
queue rather than one at a time.** Each was re-checked against the code, tool or
data path it names at `85b06dd3`, and re-confirmed at `ecc6d070`; none was closed
on a commit subject, because in this repository a commit titled
`bugs.md <n>: <restatement>` *files* an entry and does not fix it. The evidence is
the `**Closed 2026-08-14**` note under each heading.

**Every `**Status:**` line below is the one the entry was filed with**, kept
unedited, because most of the value in these entries is what was measured and
ruled out on the way. Read the closing note first; the status line is history.

---


## 77. Director's two Windows system palettes have no table, so 1,126 bitmap members draw in the wrong colours

**Closed 2026-08-14.** Fixed by `36cdad22` (2026-08-10).
`data/director_palettes.json` is in the tree and carries seven tables — Rainbow,
Pastels, Vivid, NTSC, Metallic, System Win (-101) and System Win D5 (-102) — at
1,536 hex characters each, which is what this entry asked for. Only -8 VGA is
still absent, and no title in reach names it.

**Status:** OPEN. Data, not engine — the dispatch, the resolution order and the
per-member choice are all built and asserted (`tools/palette_members.gd`); what
is missing is 768 bytes per table.

`director/director_palette.gd` generates System Mac and Grayscale because their
structure *is* their definition, and loads the rest from
`data/director_palettes.json`, which this tree does not ship. Anything naming one
of the others is warned about by name and substituted with system Mac. That was
theoretical until a title asked for one:

| root | movies stating -102 as their default | bitmap members naming -102 |
|---|---|---|
| `test-games/itamar-magichat` | 16 of 16 | 881 of 1,054 |
| `test-games/itamar-park` | 2 of 3 | 1 |
| `games/piposh-ru` | 0 | 129 |
| `games/piposh-en` | 0 | 108 |
| `games/piposh-dream` | 0 | 7 |

-102 is the Windows D5 system palette. `itamar-magichat` is the bad case by a
distance: five sixths of its artwork is indexed against a table nobody has, and
every pixel of it comes out of the 6x6x6 web cube instead. The Piposh members are
a handful of odds and ends and the six titles were pixel-identical before and
after the substitution either way, so nothing there regressed — but nothing there
is right either.

**Reproduce:**

```
godot --headless --script tools/palette_members.gd -- --root res://test-games/itamar-magichat
godot --headless --script tools/palette_survey.gd -- --root res://test-games/itamar-park --all
```

The survey's one failing check is `ChapTrfm.dir member 65 -> -102`.

**Fix:** lift both Windows tables (and Rainbow, Pastels, Vivid, NTSC, Metallic
while there) out of a Director installation or an implementation that carries
them, into `data/director_palettes.json` — the format is documented on
`DirectorPalette.PALETTE_DATA`, 1,536 hex characters per id. Do not reconstruct
them by eye: a palette that is nearly right is indistinguishable from artwork
that is nearly right, and the two get confused for weeks.

---

## 57. A whole-sprite puppet does not stop the score, so CHESS's second wheel plays one name and shows another

**Closed 2026-08-14.** Fixed. The hunk this entry writes out is in the tree at
`scenes/preview/sprite_state.gd:with_puppets`: a whole-sprite puppet now
replaces the frame's record instead of adopting it, and `Channel.note_score` has
no caller there. `tools/puppet_freeze.gd` is in `gate.sh`'s `ALL` with the CHESS
wheels as its fixture, which is the condition this entry set for its own
closure.

**Status:** OPEN in the tree, **root cause found and the fix measured**; the one
hunk that closes it is in a file two other sessions were live in tonight and is
written out below rather than applied. · **Area:**
`scenes/preview/sprite_state.gd:with_puppets`. · Reported from play as *"the
wheel, when I press it, plays the wrong sound on what lands there — the first
spin is right, the second is wrong, every time I tried."*

**Reproduce:**

```bash
godot --headless --path . --script tools/puppet_freeze.gd -- --root piposh2 --boot strtgame.dir
```

### The rule

`docs/DIRECTOR_ENGINE.md` §5.2. `Sprite::replaceFrom` copies the script
attachment and **returns** while `_puppet` is set, so from the claim onward the
score never writes that channel again — not its member, not its position, not its
size, and not its emptiness.

This port implements the *emptiness* half and only that half. `with_puppets`
carries a puppeted channel through frames whose score record for it is empty, and
on every frame where the score *does* carry a record it takes it:

```gdscript
		if not here.is_empty():
			channel.note_score(here)
			continue
```

So a puppeted channel is frozen exactly where the score was going to leave it
alone anyway, and follows the score everywhere else — which is the opposite of the
rule. `tools/puppet_persists.gd` is green throughout, because the only frames it
looks at are the frames where the score has let go.

### What the player hears

CHESS spins a name-wheel twice. Both runs are the same seven members on channel 8
put there by the score, and the same frame script over them
(`reference/lingo/CHESS/master/BehaviorScript 82.ls`, and 81, 86, 87):

```lingo
on exitFrame
  global soundspath, ches1
  if the mouseDown then
    repeat with i = 8 to 15
      puppetSprite(i, 1)
    end repeat
    sound playFile 1, soundspath & "art" & member(the memberNum of sprite 8).name & ".aif"
    ches1 = member(the memberNum of sprite 8).name
    go(marker(1))
  end if
end
```

The click freezes the wheel and names the sound from the member it froze, so **the
sound and the picture are one claim read twice**. Frames 138-144 are the first run
and 175-181 the second, identical but for where `marker(1)` lands: 145 carries no
channel 8 in the score, and 182 carries `jos`.

Every landing of both runs, clicked one frame at a time:

```
   f138: click froze pat    stage kept pat    sound artpat.aif
   ...                                                                  7 of 7 agree
   f175: click froze pat    stage kept jos    sound artpat.aif   <-- DIVERGED
   f176: click froze suz    stage kept jos    sound artsuz.aif   <-- DIVERGED
   f177: click froze map    stage kept jos    sound artmap.aif   <-- DIVERGED
   f178: click froze mrf    stage kept jos    sound artmrf.aif   <-- DIVERGED
   f179: click froze rin    stage kept jos    sound artrin.aif   <-- DIVERGED
   f180: click froze hez    stage kept jos    sound arthez.aif   <-- DIVERGED
   f181: click froze jos    stage kept jos    sound artjos.aif           1 of 7 agree
```

Six of the second run's seven landings show `jos` whatever was clicked, and the
seventh agrees only because `jos` is what the score writes. `the memberNum of
sprite 8` diverges with the stage, so `ches2` — which places the piece on the
board and picks its info card at `strtgame` — is the *sound's* answer while the
player saw the other one.

The timer, `random()`, the sound channels and marker arithmetic were all ruled out
by this trace: the `playFile` request is correct on every landing of both runs.

### The fix, measured but not applied

Two hunks, and **neither works without the other** — measured both ways. The claim
side is in `scenes/director_preview.gd:lingo_puppet_sprite` and is in the tree: it
takes a copy of the channel as the puppet claims it, because a port that rebuilds
channels from the score has nothing else to freeze. The score side is
`with_puppets`, below, and drops the score's record for a claimed channel instead
of adopting it.

```gdscript
static func with_puppets(sprites: Array, overrides: Dictionary) -> Array:
	var frozen: Dictionary = {}
	for number in overrides:
		var channel: Channel = Channel.at(int(number), overrides)
		if channel.is_puppet():
			frozen[channel.number] = channel.carried()
	if frozen.is_empty():
		return sprites
	# Channel order is depth order, and every caller relies on it: the hit test
	# descends from the end of this array and the painter walks it forwards.
	var out: Array[Dictionary] = []
	for value in sprites:
		var sprite: Dictionary = value
		if not frozen.has(int(sprite["channel"])):
			out.append(sprite)
	for number in frozen:
		var kept: Dictionary = frozen[number]
		if not kept.is_empty():
			out.append(kept)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["channel"]) < int(b["channel"]))
	return out
```

`Channel.note_score` has no caller left afterwards; the key it writes is written
once, at the claim.

With both hunks in, `tools/puppet_freeze.gd` is 14 of 14 landings green, and
`check.sh` plus `sound_wait sound_paths movie_tempo frame_events play_suspends
playhead_escape mouse_poll puppet_persists hilite trails sprite_drag
click_eligibility click_chain hotspots skip_state` are 15 of 15 PASS, unchanged
from the same list measured before it. `save_state` fails either way on an
unrelated unclassified field (`_member_hilite`).

### What this leaves

`docs/DIRECTOR_ENGINE.md` §5.2 still says the port's half-rule *is* the rule —
"a puppeted channel stays on the frame when the score's record for it is empty,
which is what the reconcile is skipped means for a port that draws from the
score's per-frame sprite list". It is not what it means, and that sentence is why
the other half was never written. Correct it with the hunk.

`tools/puppet_freeze.gd` is not in `gate.sh`'s `ALL`; add it when the hunk lands.

---

## 44. The ship map's figure vanishes whenever `nof` is empty or four characters long

**Closed 2026-08-14.** Fixed, and the write-up is already in this file's `##
Closed` section: `the castNum of sprite` dropped its cast library, so channel
1's bare `1` resolved to `walkright1` and `nof` came out ten characters long.
`castNum` is now split from `memberNum` and returns a packed `(library, slot)`
(`scenes/preview/channel.gd`'s `member_ref` arm, `Members.pack_ref`). Verified
end to end: `nof` → `dl1`, `the visible of sprite 20` → 1, and a synthesised
click runs a destination handler. `tools/member_ref_round_trip.gd` gates it.

**Status:** OPEN, and **not** the `intersects` question it was briefly filed as.
Reported from play as "the Piposh figure on the ship in the menu vanished".

`PIPDATA/MAINMENU.dir` member 43 is the map's `enterFrame`, and its whole body is
inside one test:

```lingo
if the number of chars in nof < 4 then
  ...place the figure on a deck zone, leave it visible...
else
  set the visible of sprite 20 to 0
end if
```

Every legitimate value of `nof` is two or three characters -- `dl1`, `ul5`, `t4`,
`df`, `db`, `uf`, `ub`. So the figure disappearing means `nof` arrived **empty or
long**, and the map is behaving correctly about a value someone else got wrong.
`nof` is set in the deck movies by `set nof to the name of member the castNum of
sprite 1`, which is exactly what entry 39 was: a dropped cast library made `nof`
read `walkright1` (ten characters) instead of `dl1`, and the figure went with it.

**Also load-bearing: `enterFrame` reads `nof` once, on entry, and never re-runs.**
Setting `nof` after the map has opened does nothing at all -- measured, and it is
what made this look unreproducible at first. Any harness for this must set the
global *before* `lingo_go_movie`.

Reproduce, both directions:

```
nof set before the map opens        figure visible=1, placed on the right zone
nof unset / four or more chars      figure visible=0, and no placement runs
```

**What to find out:** which path into the map leaves `nof` bad. Entry 39's fix
covers `the castNum of sprite`; something else is still reaching the map with an
empty or long `nof`, and the deck movie that does it has not been identified. A
`play`-and-return that skips the deck movie's own `enterFrame` is the first
suspect, since that handler is where `nof` is set.

---

## 32. The SKIP button parks the playhead on a frame the movie can never leave, and that is the cursor "never coming back"

**Closed 2026-08-14.** Fixed by `6109b5f0`, together with 37 and 96.
**`skip_to_end` is deleted.** SKIP is now `skip_release`: it cuts the voice,
drops the holds and moves the playhead nowhere, so the mis-landing this entry
describes cannot happen. `tools/skip_state.gd` is rewritten to assert that per
press, plus that nothing is left holding, so a do-nothing button cannot satisfy
it.

**Status:** open · **Area:** preview, `skip_to_end` · **not the cursor path** ·
**see also `docs/bugs-closed.md` 42**, which is the same button failing for a
third reason — it left the voice playing, so piposh's `soundBusy(1)` talk gate
re-armed at the destination. That half is fixed; the mis-landing below is not,
and 42's fix does not change where SKIP lands ·
reported from play as "after MURDER1 the cursor reverts to the arrow and never
returns"; reproduced once the missing step arrived — **the player presses SKIP**

The cursor is not broken. `docs/bugs-closed.md` 29 and the cursor harness cover
that path end to end, and it is correct: measured across all 61 movies, every
assigned pair composes; `MovieSession.forget_previous` clears `_channel_cursors`
on a movie change; and playing MURDER1 to its own `go("clif2", "day1.dir")` lands
in DAY1 with nine channels armed and all three on-stage sprites arbitrating
correctly. None of that is what the player does. They press SKIP.

**A Director movie's last frame is not its ending.** A movie is a strip of
independently labelled segments and the last frame is only the last segment's
last frame. `skip_to_end` moves the playhead there and nothing else, on the
premise that the end of the file is the end of the scene. Measured, that premise
is false in both of the movies this report touches, in two different ways:

| movie | last frame | its `exitFrame` | effect |
|---|---|---|---|
| MURDER1 | 883 | `go("conect2")`, and `conect2` is frame **790** | jumps *backwards* into the tail being skipped |
| MAP | 80 | — | next frame entered is **45** |
| DAY1 | 2783 | `play "done"` | subroutine return with nothing on the stack |

So: SKIP during MURDER1 lands on 883, which immediately sends the playhead back
to 790 and replays the last 94 frames. From the player's chair SKIP did nothing,
so they press it again — and whichever press lands after MURDER1 has already
handed off to DAY1 skips **DAY1**, the hub movie that holds every room of day one
in 2,784 frames. Its last frame is the tail of one of the `play`-called talk
clips at 2595-2783, and its `exitFrame` is `play done`. `lingo_play_done`
(`scenes/director_preview.gd:1621`) finds `_play_stack` empty and returns without
moving anything; it is also the last frame, so the score's own advance has nowhere
to go either. **The playhead never moves again.**

The cursor then behaves exactly as it should and looks broken:
`_channel_cursors` still holds all nine pairs the room assigned, but none of
those channels has a sprite on frame 2783, so the descent correctly falls through
to the global cursor — 0, the arrow — at every point on the stage, for ever.
Moving the mouse does recompute (`input_router.gd:mouse_motion` ->
`_resolve_cursor`); it recomputes to the arrow.

**The stale-window lead from the previous pass is dead.** `Windows.at` skips any
window whose `_window_shown` is false and `lingo_forget_window` erases destroyed
ones, so a hidden or freed window cannot capture the stage's recompute. `_windows`
was empty at every sampled step of both reproductions. Windows surviving a
`go to movie` is correct Director behaviour and is not this.

Reproduce, and note that MAP loops back too but keeps its cursor, because MAP's
cursor-bearing channels *are* on the frames it lands among — which is the whole
mechanism in one contrast:

```
$ godot --headless --script tools/skip_state.gd -- --file PIP2DATA/DAY1.DIR
   DAY1.dir  f46 -> skip -> f2783 -> f2783 -> f2783
   cursor at the stage centre: [16, 17] -> 0, 9 channel(s) still recorded
FAIL  DAY1.dir: the movie can still move after SKIP  (parked on DAY1.dir f2783)

$ godot --headless --script tools/skip_state.gd -- --file PIP2DATA/MURDER1.DIR
   MURDER1.dir  f34 -> skip -> f883 -> f790 -> f828
FAIL  MURDER1.dir: the last frame is an ending, not a jump back

$ godot --headless --script tools/skip_state.gd -- --file PIP2DATA/MAP.DIR
   MAP.dir  f34 -> skip -> f80 -> f45 -> f47
   cursor at the stage centre: [14, 15] -> [14, 15], 12 channel(s) still recorded
```

`tools/skip_state.gd` is title-agnostic and not in `gate.sh`: it is red on this
corpus by design, because it asserts the property SKIP needs and does not have.
`--all` sweeps every container under the game root.

**What to change, and what not to.** Director has no skip, so there is nothing to
be faithful to and this is a judgement about a debug affordance rather than an
engine gap. Two candidate shapes, and the obvious one is wrong:

- **Wrong: run the intervening frame scripts instead of jumping over them.** For a
  linear cutscene that is what is wanted; for DAY1 it would run the whole rest of
  the movie — dozens of unrelated rooms, every `go`, every sound — because the
  frames between here and the end are not "the rest of this scene".
- **Right: stop jumping the playhead at all.** What the player means by SKIP is
  "stop waiting", not "go to the end of the file". Releasing whatever the current
  frame is holding on — the wait, the sound — and letting the movie's own scripts
  drive to their own exit walks MURDER1 to its `go("clif2", "day1.dir")` and does
  nothing harmful in DAY1. `_clock.release()` already exists and is what the jump
  currently does *in addition to* the damage.

Both live in `skip_to_end` (`scenes/director_preview.gd:1035`), and the SKIP
hit-test is in `input_router.gd:mouse_button`. Neither is in this change.

---

## 33. `gate.sh`'s `editable_text` entry asserts nothing, and reports PASS

**Closed 2026-08-14.** Fixed. `gate.sh`'s `ALL` carries
`editable_text:--file@PIP2DATA/SAVELOAD.dir`, which is the 43-check invocation
this entry names. The gate grew per-entry arguments, which was one of the two
repairs offered here.

`tools/editable_text.gd` finds its own subject: the first frame carrying a field
sprite. Run with no arguments it opens the configured boot movie, and this
title's boot movie is `strtgame.dir`, which has no field sprite anywhere. The
harness says so and exits **passing with zero checks**:

```
$ godot --headless --path . --script tools/editable_text.gd
strtgame.dir has no field sprite anywhere; nothing to type into

PASS  editable text in strtgame.dir (0 checks, 0 failed)
```

`gate.sh` runs every harness with no arguments, so the gate entry that covers
§8.4 has never asserted anything on this corpus. Pointed at the movie the feature
is *for* it asserts 43:

```
$ godot --path . --script tools/editable_text.gd -- --file PIP2DATA/SAVELOAD.dir
PASS  editable text, focus, caret and selection in SAVELOAD.dir (43 checks, 0 failed)
```

This is the exact failure mode `scenes/preview/README.md` warns about in another
context — a harness that reads nothing reports zero rather than failing, and the
safety net goes dark without going red. It is filed rather than fixed because the
fix is a choice: either the harness scans for a container with an editable field
the way `tools/save_movie.gd` does, or `gate.sh` grows per-harness arguments, and
`gate.sh` is not this change's to edit.

---

## 34. `the visible of sprite N` answers FALSE for an empty channel, and that is why the main menu's Load button does nothing

**Closed 2026-08-14.** Fixed by `f6e998de` (2026-08-08), **one day after this
entry was filed**. `Channel.EMPTY_CHANNEL` carries `visible: 1` and
`Channel.read` answers 1 for a channel the score has no record for, which is the
rule this entry states.

The reference confirms it from the other end, and that answer is what `bugs.md`
100 was waiting for: `the visible of sprite N` reads `channel->_visible`
(`lingo-the.cpp:1809`), a `Channel` field set `true` in the constructor
(`channel.cpp:63`) and written in exactly two other places — the copy
constructor (`:99`) and the Lingo setter (`lingo-the.cpp:2135`). **No score path
touches it**, so Director answers TRUE for an *occupied, unpuppeted* channel as
well as an empty one. This entry only argued the empty case; the occupied case
is the one 100 turns on.

**Symptom, from the player's chair:** on the main menu, clicking Load does
nothing at all — no window, no sound, no cursor change. It looks like "there is
no save to load". It is not: the button never runs.

`ROOT/strtgame/BehaviorScript 369.ls` is the menu's Load button, and its entire
body is inside one guard:

```lingo
on mouseUp
  global soundspath, effectspath, movienamekeeper, stopornot, cdsavepath
  if sprite(30).visible = 1 then
    ...
    open(window(cdsavepath & "saveload.dxr"))
    ...
  end if
end
```

The guard is a copy of the in-game menu handlers (`DAY1/wonder/BehaviorScript
312.ls` and its siblings), where channel 30 is the walking player character and
the test means "not mid-cutscene". On the *main menu* there is no player:

```
strtgame.dir: channel 30 occupied in 0 of 1375 frames
engine answers sprite(30).visible = 0 on frame 0
```

**In Director a sprite channel's `visible` is a channel property that defaults to
TRUE**, whether or not the channel holds a member — an empty channel is a visible
channel with nothing in it. The guard therefore passed in 1997 and the button
worked. This port answers 0 for a channel with no sprite record, so the guard
fails and the handler returns having done nothing.

Reproduce:

```gdscript
# any harness, after booting strtgame
preview.call("lingo_sprite_prop", 30, "visible")   # -> 0, wants 1
```

**Where the fix goes:** `scenes/preview/sprite_props.gd`, the `visible` read. It
has to distinguish "the channel is empty" from "a script set `visible` to 0", and
answer TRUE for the first. Worth checking the same question for the other channel
properties that have a meaningful default on an empty channel (`locH`/`locV`,
`ink`, `blend`) rather than fixing one and leaving the class.

Not fixed here because `sprite_props.gd` was being edited by another change at the
time. The three observations it explains — Load doing nothing on the menu, and
the two save-related ones — are otherwise unrelated: the save half was
`saveMovie` bound inert and is fixed.

---

## 37. SKIP walks off the end of `rating`'s main menu into a subroutine region, and the movie restarts its own opening

**Closed 2026-08-14.** Fixed by `6109b5f0`, together with 32 and 96 — one
affordance, three filed failure modes, all of them properties of the marker
walk. The walk is gone: `skip_release` releases what the frame is holding and
navigates nowhere, which is the shape 32 argued for and this entry seconded.

**Status:** open · **Area:** preview, `skip_to_end` · a second failure mode of
the same affordance as entry 32, through the marker walk rather than the
last-frame fallback · reported from play as "when the game starts, if I press
different places it jumps back and forth — just on this game"

`skip_to_end` walks to the **next marker** and falls back to the last frame only
when there is none. Entry 32 is about that fallback. This is about the walk
itself: **a marker is not a scene.** A Director movie routinely parks
subroutine segments after its playable strip, entered by name with `go("x")` and
left with a jump back to the top, and the marker list cannot tell those apart
from the next scene.

`rating`'s boot movie is `MAINMENU.dir`, not `strtgame.dir`. Its markers are

```
    3 hedartzi   14 guilotine   46 oliver   504 mainscreen
  587 option1   594 option2   601 option3   609 option4   614 option5   621 option6
```

The playable strip is 0-521: a 449-frame opening (`53..501`, frame script member
7, `on exitFrame / if the mouseDown then go("mainscreen")`) and then the menu,
which idles on 504-521 because frame 521 runs `go(marker(0))`. `option1`..
`option6` are **not scenes**. They are the CD drive-letter probe — six frames
that each set `the searchPath` to one drive, `playFile` a known clip, and either
record the letter or `go` to the next option — and every one of them ends on a
frame whose script (member 88) is `on exitFrame / go(2)`. Nothing in the movie
ever enters them; they are reachable only by jumping into them.

So SKIP pressed on the menu lands on `option1`, the probe runs, `go(2)` fires,
and the playhead is back at **frame 2 — the start of the opening the player was
trying to skip.** Pressing SKIP again walks 14 → 46 → 504 → 587 → 2 again. That
is the reported "jumps back and forth", and it is a closed cycle:

```
$ godot --path . --script <a harness that presses SKIP and traces>
SKIP 0: MAINMENU.dir f10  -> landed f14  -> f25   trail [14 … 25]
SKIP 1: MAINMENU.dir f25  -> landed f46  -> f47   trail [46, 47]
SKIP 2: MAINMENU.dir f47  -> landed f504 -> f511  trail [504 … 511]
SKIP 3: MAINMENU.dir f511 -> landed f587 -> f3    trail [587, 588, 589, 590, 2, 3]
SKIP 4: MAINMENU.dir f3   -> landed f14  -> f26   ... and round again
```

Reproduce the shape without a harness — this is the score, and it is enough:

```
$ godot --headless --path . --script tools/director_frames.gd -- \
      --root rating --file MAINMENU.dir
markers    : 10, labels 10
     504  mainscreen
     587  option1        <- SKIP's next marker from the menu
```

`tools/skip_state.gd` passes on this movie and is not wrong to: it skips from
f250, which is inside the opening, so the next marker is `mainscreen` and that is
a real destination. The trap is only reachable from the *last* playable segment,
which is exactly where a player who wants to skip is standing. Extending
`skip_state` to press SKIP repeatedly until the marker list is exhausted would
catch it, and would also catch entry 32's cases; that is the check this entry
wants and does not have.

**Why it is filed and not fixed.** Entry 32 already argues the shape of the
answer — SKIP should stop teleporting the playhead and instead release what the
current frame is holding on and let the movie's own scripts drive — and this
movie is the strongest case for it yet, because *the movie has its own skip*:
`if the mouseDown then go("mainscreen")` covers all 449 frames of the opening.
That one works now (see the commit that added `tools/mouse_poll.gd`), so a player
on this title no longer needs the button. There is no title-agnostic rule that
can tell `option1` from `mainscreen` by looking at the marker list, which is the
whole reason the marker walk cannot be patched into correctness.

Two things found alongside, both only reachable through this trap and both real:

- The probe concludes the CD is on **D:**. `sound playFile 1, "d:\sounds\start\egozcold.aif"`
  resolves — the last-resort bare-filename lookup finds
  `games/rating/sounds/start/EGOZCOLD.AIF` — so `soundBusy(1)` is true and the
  movie sets `gWinDriveLetter` to `d` and `soundspathstart` to `d:\sounds\`. An
  absolute path naming a drive that does not exist should not resolve to a file
  beside the movie.
- `soundspathstart` reads empty in `ARRIVEL` after the menu's Play button, so its
  sounds are requested as `start\story.aif` rather than under the game root,
  while the same global was correct in `MAINMENU` a moment earlier. Not
  investigated; `tools/globals_survive.gd` is the tool for it.

---

## 51. `gate.sh` pinned the root and not the boot movie, so most of the suite booted nothing and asserted over it

**Closed 2026-08-14.** Already declared FIXED (tooling) in its own status line;
it had simply never been moved. Re-checked: `gate.sh` passes `GATE_BOOT`
alongside `--root` and `director_paths.gd:_override_boot` honours `--boot`.

**Status:** FIXED (tooling) · **Area:** `director/director_paths.gd:load_config`,
`gate.sh:36-44`, and the three child-spawning harnesses · found while trying to
verify `bugs.md` 40 and 50 against the recorded baseline, which turned out not to
be reachable from the tracked config

`gate.sh` pins the corpus so that a run against another title does not read as
regressions that are really different movies. It passed `--root piposh2` and
nothing else. **The boot movie still came from `director_game.cfg`**, and
`399feaaa` pointed that at `rating`'s `mainmenu.dir` — a working config, per its
own commit message. So every `ALL` entry that does not name its own `--file`
resolved a `rating` container under `piposh2`, found nothing, and ran on:

```
$ godot --headless --path . --script tools/text_and_shapes.gd -- --root piposh2
ERROR: no such container: mainmenu.dir in res://games/piposh2
        try --file with one of: strtgame.dir, HEZSAVE.DIR
no score loaded
```

**They do not fail — they load no score and assert over nothing.** That is the
dark-harness failure `gate.sh` warns about in its own EMPTY guard, arriving
through the corpus pin rather than through an empty result set.

The fix is the rule the file already argued for one question at a time: an
override belongs in the one place the value is read, or the parts disagree about
which title they are running. `_override_root` had that argument written out and
`boot_movie` had no override at all, so pinning a root was half a pin.
`_override_boot` honours `--boot`, `gate.sh` passes `GATE_BOOT` (default
`strtgame.dir`, the boot movie of both roots the list names) alongside `--root`.

**The same hole a second time, in the child processes.** `save_state`,
`save_movie` and `text_codepage` each spawn a second Godot and each forwarded
`--root` under a comment reading "a parent pinned to one corpus and a child told
nothing are two different games". The boot movie has exactly that property, and
`save_state` was the proof: its child died on `mainmenu.dir`, and the harness
reported it as `the saving process exits cleanly (exit 1)` — 89 checks with one
failure that named the parent. Forwarding `--boot` too takes it to 132 checks, 0
failed. **The check count is the tell**: a harness whose child booted nothing
still reported 89 checks, so the number to watch is not pass-versus-fail but how
much a green run actually asserted.

Reproduce (before the fix): `godot --headless --path . --script
tools/text_and_shapes.gd -- --root piposh2` → `no score loaded`, no verdict.
After: `--root piposh2 --boot strtgame.dir` → PASS, 10 checks.

---

## 50. Egoz's face draws inside a white rectangle: Copy ink with the blend flag never gets its matte

**Closed 2026-08-14.** Already declared FIXED (engine) in its own status line
and covered by `tools/ink_blend_matte.gd`; it had simply never been moved.
Re-checked: `director_ink.gd:key_for` is the reference's predicate rather than a
lookup on the ink.

**Status:** FIXED (engine) · **Area:** `director/director_ink.gd` keying predicate ·
reported from play as "when egoz speaks his image has the white background, it
should be ignored" · found from a snapshot, root-caused from the container bytes,
covered by `tools/ink_blend_matte.gd`

**Director does not decide a sprite's keying from its ink number.**
`Channel::getMask` (`reference/scummvm/channel.cpp:188-226`) reads the ink, the
thickness byte's blend flag and the member's bit depth together. `key_for` read
the ink alone, so the one combination where those disagree fell through to "draw
every pixel":

```cpp
// reference/scummvm/channel.cpp:206
if (!_sprite->isQDShape() && _sprite->_ink == kInkTypeCopy && _sprite->_thickness & kTHasBlend)
    needsMatte = true;
```

Note what that clause does *not* test: the blend **amount**. A Copy sprite with
the flag set and an amount of 0 — fully opaque — still gets a matte, and the mask
reaches the blit at `window.cpp:465` → `graphics.cpp:797`, where a pixel is drawn
only where `msk && (*msk++)`.

The sprite, from the score rather than from the screenshot. `BATZEGOZ.dir` frame
209, marker `egozspeak1`, **channel 41**, `Panel.cst` member 23 — an 8-bit bitmap
101x135, reg (50,67). Its record, and the resting member two frames earlier:

```
f205 ch41: 10 08 ff 00  00 04 00 03  00 00 00 18  01 a3 02 43  00 87 00 65  00 00 80 00
f209 ch41: 10 00 ff 00  00 04 00 17  00 00 04 fb  01 a3 02 43  00 87 00 65  00 00 10 00
                ^^                ^^                                            ^^
              ink byte         member                                      thickness byte
```

Ink byte `0x00`, thickness byte `0x10` = `kTHasBlend` (`sprite.h:61`), blend
amount `0x00`. The decoder was right about every byte; the keying rule was wrong
about what they mean together. Channel 41 is Egoz — it draws from the shared
`Panel.cst` while the central figure is channels 2-5 from `Batz.cst`, and it
changes member in exactly one of the movie's 19 segments, stepping `Panel.cst`
22-28 one frame each through `egozspeak1` and parking on member 3 at ink 8
everywhere else.

**Ink dispatch was working in the same frame**, which is what ruled out the two
likelier-sounding causes. Frame 209 carries 4 sprites at ink 8 (channels 3, 4, 5,
40) and 5 at ink 36 (channels 2, 45, 46, 47, 48), and all nine key correctly:
Batz's head, eyes and mouth matte over his body, and the gold picture frame
`4:1` mattes around its own tilted outline on the channel *behind* the portrait.
So this was neither `backColor` resolution nor the wrong member being drawn.

### Why it surfaced on the second title

| root | scores | sprite records | ink 0 + `kTHasBlend` | share of that root's Copy records |
|---|---|---|---|---|
| `games/rating` | 81 | 847,431 | **27,914** | 18.8% of 148,747 |
| `games/piposh2` | 61 | 816,318 | 209 | 0.2% of 88,095 |
| `games/piposh` | 99 | 1,886,362 | 1,143 | 0.5% of 222,506 |

Two orders of magnitude more common in the title the port was not built on. In
Rating that is 883 distinct (container, member) pairs, every one a multi-bit
bitmap. This is the general defect surfacing the first time another title loads,
which is the failure `AGENTS.md`'s "build Director, not this game" describes.

### The fix

`key_for(sprite, member)` is now the reference's predicate rather than a lookup on
the ink: all twelve `needsMatte` inks (`channel.cpp:192-203`), the blended-and-
non-zero clause, the Copy-with-flag clause, bitmap-only, and the 1-bit exception
(`channel.cpp:218-223` — a 1-bit member gets a matte only under Matte ink proper,
and under Copy its blend amount is additionally forced to 0). Mask (9) moved
*off* matte keying: `getMask`'s `else if` arm takes the next cast member as a
separate 1-bit mask, which is a different mechanism, and the old code answering
`KEY_MATTE` for it was wrong in kind.

`texture_key` gained the has-blend flag (`sprite_geometry.gd`). Not housekeeping:
the flag now changes which pixels survive the decode, and `BATZEGOZ.dir` holds a
live collision — members `1:20` and `1:23` carry the flag while `1:21` and `1:22`
do not, all four are baked lines of the same dialogue balloon, and all four are
drawn Copy at one size.

**`hits_per_pixel` deliberately still answers false for these sprites.**
`BitmapCastMember::isWithin` (`castmember/bitmap.cpp:920-928`) tests per pixel for
`kInkTypeMatte` and nothing else, off the ink alone, so Director mattes this
sprite for drawing and still hits it across its whole box. Run the F1 outlines
over Egoz's portrait and it reads as a bug — a green "whole rect" box around art
with keyed-out corners. It is not one, and the comment at `hits_per_pixel` says
so; routing both decisions through one predicate is the tidy-up to refuse.

### Reproduce

```bash
godot --headless --path . --script tools/ink_blend_matte.gd -- --file BATZEGOZ.dir
godot --headless --path . --script tools/matte_survey.gd -- --file BATZEGOZ.dir
```

The first steps into `egozspeak1`, finds the Copy-with-blend sprite without being
told which channel it is on, and asserts the corners are keyed, the face is not,
the 190 pixels of enclosed white — the whites of the eyes — survive where paper
keying would eat them, clearing the flag brings the white rectangle back, and
`hits_per_pixel` still answers false. The second's third census, "records ScummVM
mattes and this port does not", reads 0.

### What no data proves

The ten arithmetic and Not- inks, and both halves of the 1-bit exception. Across
all three roots the only inks that appear are 0, 1, 8, 32 and 36, and **0 records
pair a 1-bit member with any matte-needing ink** — 0 under Matte and 0 under the
other eleven paths. Implemented from the reference and marked unverified at each
site. The blend-amount half of the 1-bit rule is in `blend_alpha` behind an
optional `member` argument that **no caller passes yet**: the four sites that ask
for an alpha (`stage_paint.gd`, `film_loop_view.gd` twice, `text_art.gd`) were
outside this change's file set, so they still get the member-blind answer. One
line each to wire up, and 0 corpus records reach it either way.

---

## 54. `play done` returns to the frame the `play` was on; the reference returns to the one after it when the `play` came from a frame script

**Closed 2026-08-14.** Already declared fixed in its own status line; it had
simply never been moved. Re-checked: `lingo_play_push` records `_index if
from_sprite else _index + 1`, which is the reference's `currentChannelId == 0`
branch.

**Status:** fixed · `lingo_play_push` records `_index + 1` when `current_sprite_num` is 0 -- the channel of the running chain element, which is the reference's `currentChannelId`. The latch it replaces is gone: taking `frameI++` means taking it instead of, not beside. Re-measured on the screen the latch was measured on (`piposh-dream` `fritz_room.json`, click 25,12): no ping-pong, 23 sprites, all six save slots clickable, and the panel reached one step sooner, which is what landing past the caller's frame looks like.

`Lingo::func_play` records where to come back to as

```
ref.frameI = getScore()->getCurrentFrameNum();
// if we are issuing play command from script channel script. then play done should return to next frame
if (_state->currentChannelId == 0)
    ref.frameI++;
```

`currentChannelId == 0` is "this script is not attached to a sprite channel" — a
frame script or a movie script. So in the reference a `play` written in a frame's
`on exitFrame` returns the playhead to **frame + 1**, and only a `play` from a
sprite behaviour returns to the frame itself. `lingo_play_push` records `_index`
in both cases.

That single line is why the reference never has to re-enter the caller's frame:
it lands past it, `Score::update` clears `_exitFrameCalled` beside the
`enterFrame` it then sends (`score.cpp:827-828`), and the caller's `exitFrame` —
the handler that wrote the `play` — is never dispatched a second time.

This port arrives at the same *outcome* by a different mechanism: `play done`
re-enters the caller's frame and carries `_exit_frame_called` across the entry so
that frame's `exitFrame` is suppressed once (commit 70c88e83, and now
`_pop_play_stack`). Both stop the interlude from restarting its caller. They are
not the same behaviour, and where they differ is visible:

* the port re-runs the caller frame's `on enterFrame`, and re-arms that frame's
  score sound, its palette and its transition through `sync_frame_entry`; the
  reference does none of those because it never returns to the frame;
* the port then leaves the frame *without* an `exitFrame`, so anything a room does
  on the way out of that frame is skipped once per interlude.

**Not fixed here, deliberately.** Taking `frameI++` means taking it *instead of*
the latch, not beside it — with both, the entry on frame + 1 would swallow a real
`exitFrame`. That unpicks a recent, measured fix (Piposh Dream's `ques.dir` 803
save panel) and the case cannot be re-measured without driving that screen, which
needs `--root piposh-dream` and a click.

**There is a way to drive it now**, which is what that sentence was waiting for:

```
godot --headless --path . --script tools/liveness_sweep.gd -- \
    --root piposh-dream --boot STRTGAME.dir --only ques.dir --click --verbose
```

`--click` presses every eligible sprite of the frame the watch ended on and
watches where each one leads, and the sweep's `ping-pong` verdict is that exact
symptom: two containers trading places, nothing on the clock, one of them drawing
nothing. So a change to `lingo_play_push` has a detector to be measured with
rather than only reasoned about.

**It is a detector and not yet the reproduction, and the difference is measured
rather than assumed.** Run as written, the sweep opens `ques.dir` at its start,
the watch settles around frame 13, and the click phase never reaches 803 — 20
states, no finding, one click deep from wherever the opening left it. Frame 803
is a save panel several steps into the movie, so getting there wants a marker
jump or a click chain the sweep does not have. What the command above *does* give
is a rule that fires on the shape the moment a run reaches it, and
`tools/liveness_sweep.gd:_assert_rules` asserts that on a synthetic
`ques.dir:803(4) <-> Saves.dir:27(0)` window every time it runs.

Whoever picks this up: the port also has
no `currentChannelId`, and `exitFrame` is dispatched only to the frame script
(`frame_loop.gd:advance` passes `_frame_script(_index)`), so today every `play`
reached from an `exitFrame` is the channel-0 case.

**Reproduce:** read `lingo-funcs.cpp:207-213` beside `director_preview.gd`'s
`lingo_play_push` / `_pop_play_stack`. The behavioural difference shows on any
frame whose `exitFrame` calls `play` and which also has an `on enterFrame` or a
sound in its score sound channels.

---

## 55. A queued `go` cancels the tempo wait as well; the reference cancels only the sound, click and video waits

**Closed 2026-08-14.** Already declared fixed in its own status line; it had
simply never been moved. Re-checked: `FrameClock.release` clears the sound,
click and video waits and leaves the clock alone, and `release_all` has one
caller.

**Status:** fixed · `FrameClock.release` now clears the sound, click and video waits and leaves the clock alone; `release_all` is the everything version and `skip_to_end` is its one caller, because the SKIP button is a player abandoning the scene rather than a script navigating inside it. §9.2 and `tools/frame_events.gd` both asserted the old reading and are corrected.

`Score::isWaitingForNextFrame` computes `goingTo = _nextFrame && _nextFrame !=
_curFrameNumber` and consults it in **three** of its four arms:

```
if (_waitForChannel)           { if (active && !goingTo) keepWaiting = true; else _waitForChannel = 0; }
else if (_waitForClick)        { if (!goingTo) { ...; keepWaiting = true; } }
else if (_waitForVideoChannel) { if (active && rate && !goingTo) keepWaiting = true; else _waitForVideoChannel = 0; }
else if (millis < _nextFrameTime) keepWaiting = true;      // <- no goingTo
```

The last arm is the ordinary frame clock: the tempo channel's frame rate, and its
`256 - tempo` seconds delay. A pending jump does not shorten it. `the delay`'s own
timer is the same (`score.cpp:681-692`): a jump skips the frozen-script processing
inside the delay branch and does not end the delay.

This port releases all four together. `lingo_go_frame` calls `_clock.release()`
with the comment "a pending `go to` cancels every wait — sound, click and delay
alike (§9.2)", and `tools/frame_events.gd` asserts it as a rule
("a queued `go to` cancels every wait").

Only reachable from a `go` issued *outside* the step loop — a click, a key, an
`idle` handler — because a `go` from `exitFrame` runs after the wait has already
expired. On a frame carrying a two-second tempo delay, this port jumps on the
click and the reference serves out the delay first. This corpus spends 74.0 s in
tempo delays across thirty-six frames (`tools/transition_survey.gd`), so the
window is not narrow.

Not changed here because it is a documented rule with a harness behind it, and
flipping it is the owner's call rather than an audit's: §9.2 would have to be
rewritten and `frame_events`, `playhead_escape` and `sound_wait` re-measured.

**Also unfixed, same family, smaller:** `Score::step` refuses to dispatch queued
input events while a jump is pending or while any Lingo state is frozen
(`score.cpp:332-335`, `!_movie->_inputEventQueue.empty() &&
!_window->frozenLingoStateCount()`). This port delivers input from Godot's
`_input` the moment it arrives, with no such gate, so a click landing between a
`go` and the step that honours it is delivered where Director would have dropped
it.

**Reproduce:** read `score.cpp:400-441` beside `director/director_frame_clock.gd`
and `director_preview.gd:lingo_go_frame`.

---

## 67. A bitmap member's palette is read from the D4 offset, so every clut id in the corpus is measured as the field next to it

**Closed 2026-08-14.** Fixed. `director_cast.gd:_parse_clut` reads `clutCastLib`
at offset 24 and `clutId` at 26 for a 28-byte specific block, falls back to 24
for a 26-byte one, and applies the reference's `id - 1` adjustment for `id <=
0`. Both halves of the double error this entry describes are gone, so the port
no longer draws the right palette for the wrong reason.

**Status:** open · **Area:** `director/director_cast.gd:356`, `tools/palette_survey.gd`,
`scenes/preview/members.gd:243` · found while ruling the palette out of
`docs/bugs-closed.md` 66

`_parse_specific` reads a bitmap's palette from the specific block at **offset 24**:

```gdscript
out["palette_id"] = _be_i16(spec, 24) if spec.size() >= 26 else -1
```

That is the D4 layout. `castmember/bitmap.cpp` puts a second field in front of the
id from D5 on:

```cpp
int clutCastLib = -1;
if (version >= kFileVer500) {
    clutCastLib = stream.readSint16();   // offset 24
}
int clutId = stream.readSint16();        // offset 26 on D5+, 24 on D4
if (clutId <= 0)                         // builtin palette
    _clut = CastMemberID(clutId - 1, -1);
```

Every container in both corpora is D5 or later — `rating`'s config word is `0x073a`
— so the port has been reading `clutCastLib`. Measured over `MANAEGOZ.dir`,
`MANAGER.cst`, `HOTEL.cst`, `HOTEL2.cst` and `Panel.cst`, offset 24 is `-1` in all
941 bitmap members with a 28-byte specific block and offset 26 is `0` in all 941.

**Two errors, and they cancel.** The offset is wrong, and the `clutId - 1`
adjustment the reference applies is missing — Director stores the first built-in at
0 and counts down, while a *frame's* palette channel uses 0 for "no change" and
starts the built-ins at -1. Read correctly, `0` at offset 26 becomes
`kClutSystemMac`; read as it is now, `-1` at offset 24 is *labelled* system Mac by
`BUILTIN_NAMES` and happens to be the same answer. So the port draws the right
palette for the wrong reason, and would keep drawing it for a title that named a
different one.

**What this invalidates.** `tools/palette_survey.gd` reports "0 members name a
palette other than system Mac" across 86 containers and 11,520 bitmaps, and
`director/director_palette.gd`'s header cites that number as the reason system Mac
is the only verified table. The *conclusion* survives — offset 26 also reads system
Mac everywhere it was checked — but the measurement behind it does not, and the
sweep has to be re-run against the corrected offset before the header can go on
claiming it. `the palette of member` (`preview/members.gd:243`) answers from the
same field and is wrong by the same two steps.

Nothing in either corpus renders differently once this is fixed, which is exactly
why it is filed rather than folded into another change: it is a decode bug with no
symptom, and the first title that ships a Windows or custom palette is where it
stops being free.

**Reproduce:** for any bitmap member, slice the `CASt` specific block and print the
`i16` at 24 and at 26 beside `castmember/bitmap.cpp`'s D5 branch.

---

## 81. Cast type 12 (`richText`) has no arm in `_parse_cast`, so a rich-text member has no size and its sprite is drawn at the score's residue

**Closed 2026-08-14.** Fixed. `director_cast.gd:_parse_specific` has an arm for
12. It is still unverified against real data and says so at the site:
`tools/member_type_census.gd` finds **0 type-12 members in 160,932** across all
eight corpora, so the arm is written from the reference and the thing that would
check it is one container nobody has.

**Status:** open, latent · **Area:** `director/director_cast.gd:_parse_cast` ·
**another agent is working on this right now**, so read the tree before starting

`_parse_cast`'s `match type_code` has arms for 1 (bitmap), 3 (field), 2 (film
loop), 8 (shape), 11 (script) and 14 (transition), and stops there. There is no
12. Every other field of the member dictionary is initialised before the match —
`width` and `height` at **0** — so a `richText` member is decoded as a member
with no dimensions and no registration point.

Two things downstream already have opinions about that, and neither is a guess:

- `TYPE_NAMES` *does* name 12 `richText` and `DRAWING_TYPES` *does* include it,
  so the cast layer marks the member as art the renderer is expected to draw
  (`"drawing": true`) and then hands over no geometry to draw it with. That
  combination exists for no other type.
- `scenes/preview/sprite_geometry.gd:drawn_size` reads a natural size of 0 on
  either axis as "a member this cast does not describe, or one whose geometry did
  not decode", and returns the sprite's own rect. That rect is the *score's*
  stored one, which this file and `docs/bugs-closed.md` both record as authoring
  residue rather than a size anybody authored — it is what put Piposh 1's money
  17px off-centre in 33,686 sprite records. So the one member type with no
  natural size to check the residue against is the one that gets handed it.

`scenes/preview/sprite_art.gd:texture_for` returns null for anything that is not
a bitmap or a shape, so nothing is drawn either way today; the geometry is what
will be wrong first when something is.

**Latent, and filed anyway.** `docs/DIRECTOR_ENGINE.md` records that buttons
(type 7) and rich text (type 12) "do not occur in this corpus at all", and no
member of `test-games/itamar-magichat`'s eight containers is one either — the
types found there are bitmap, field, sound, shape, script, palette, transition
and 15. Per `AGENTS.md`, 0 uses is not a reason for the arm to be missing; it is
the reason nothing has noticed.

Reproduce (there is nothing in the tree to point it at, which is the entry):
read `director_cast.gd`'s match, then `sprite_geometry.gd:drawn_size`, and follow
a `width` of 0 through both.

---

## 84. Digital video (cast type 10) is unimplemented, so Magic Hat's logo movie plays nothing and then skips itself on its first tick

**Closed 2026-08-14.** Fixed. `director/director_avi.gd` is the MS-RLE reader
this entry's own correction costed as the good-ratio option (`56a34ee3`);
`a938a7f3` added a transcoded sidecar for the MPEG content and `5f0bd756` a
plugin backend that does nothing until one is installed. `gate.sh` carries
`avi_decode`, `video_fallback`, `video_plugin` and `media_surface`.

**Status:** open · **Area:** `scenes/preview/media.gd`,
`director/director_cast.gd`

`media.gd` states the gap plainly and correctly — there is no QuickTime or AVI
decoder in this port and Godot supplies none, so a `#digitalVideo` member answers
`the mediaReady` FALSE, a duration of 0, no cue points and no tracks, "which is
exactly what Director answers for a digital video whose file is missing or whose
codec is not installed". Nothing about that reasoning is wrong. What is now wrong
is the sentence beside it: "**no member in any of the six titles is a digital
video**, so there is nothing to measure a layout against". There is a seventh
title in the tree and it is built around two of them.

`test-games/itamar-magichat/logo/logo.dir`, all six members:

```
   1  script       start movie + quit logo
   2  script       run movie
   3  script       compedia logo
   4  script       Check avi
  27  digitalVideo prelogo
  28  digitalVideo logo
```

and the two scripts that are only about them:

```lingo
on enterFrame                      -- "compedia logo"
  global FilmLen
  FilmLen = member("logo").duration
  sprite(3).movieTime = 0
  sprite(3).movieRate = 1
end

on exitFrame                       -- "Check avi"
  global FilmLen
  if sprite(3).movieTime >= FilmLen then
    QuitFilm()                     -- go(the frame + 1)
  else
    go(the frame)
  end if
end
```

`the duration of member` is 0 for a member with no media, and `the movieTime` of
a sprite that is not playing stays where it was put — so `0 >= 0` is true on the
**first** `exitFrame`, `QuitFilm` runs, and the logo is left behind before a
frame of it could have been shown. The failure is not a hang and not an error; it
is the movie's own guard being satisfied by two zeroes.

The media is on disk beside the movie (`logo/logo.avi`, `prelogo.avi`) and
`startMovie` points the member at it explicitly —
`member("prelogo").fileName = "prelogo.avi"` — so nothing is missing here except
a decoder. `docs/ENGINE_TODO.md` carries the member's specific block as an open
item on the grounds that no member in the corpus is a digital video; these two
are the sample that argument was waiting for.

Reproduce:

```
godot --headless --path . --script tools/director_extract.gd -- \
    --root res://test-games/itamar-magichat --file logo/logo.dir --out <dir>
```

`members.txt` names both, and `scripts/` holds the four handlers above.

### Two corrections and the costed answer — 2026-08-12

**`prelogo.avi` is not on disk.** `ls test-games/itamar-magichat/logo` is
`logo.avi`, `logo.dir`, and nothing else; `tools/video_census.gd` classifies every
media file under all eight roots and finds exactly one AVI in the tree. The
sentence above that says both files are there was wrong. `startMovie` still names
it, so `prelogo` is a member with no decoder **and** no media, and no decoder
decision reaches it. `logo` — the one that is scored, on channel 3 from frame 3 —
is the only type-10 member in the tree with a file behind it.

**And that file is far more decodable than "no QuickTime or AVI decoder" implies.**
Read from its own headers rather than from its extension:

```
RIFF AVI, 640x480 at 11.11 fps, video 'mrle', 8-bit, audio tag 1 (PCM), 22050 Hz, 1 ch
112 frames -> 10.1 seconds, 1.7 MB
```

`mrle` with `biCompression = BI_RLE8` is Microsoft RLE — a run-length encoding, not
a transform codec. ScummVM decodes exactly this pair with no external dependency
(`video/avi_decoder.cpp` over `image/codecs/msrle.cpp`), and this port already
turns raw PCM into an `AudioStreamWAV` in `director/director_sound.gd`. **Both
digital-video members in eight corpora are AVI**, so an MS-RLE reader closes the
whole of type 10 in this tree, and it needs no MPEG-1 work and no native
dependency. `docs/DIGITAL_VIDEO.md` §4 costs it as option C1 and recommends it as
the one piece of decoder work with a good ratio.

**The skip is correct and is now asserted.** `tools/video_fallback.gd` reads both
members through the real Lingo seam and checks that `the mediaReady of member`
answers FALSE and `the duration of member` answers 0 — the two values `Check avi`
actually branches on — and then drives the playhead onto frame 3 and watches it
leave. It does, in six states. That assertion is the guard worth having: a future
`media.gd` that answered a confident duration here would turn this clean skip into
a hang, and `Check avi`'s other arm is `go(the frame)`.

**`logo.dir` is not on the boot path in this port today.** The title's own
`magichat.ini` has `startfile=CD$\logo\logo`, so the logo movie is where the
original starts; `run-itamar-magichat.bat` boots `magichat.dir` directly, so
nothing reaches `logo.dir` unless a harness sends it there. Worth knowing before
measuring "what the player sees" from a normal launch.

`docs/DIGITAL_VIDEO.md` carries the full census, the per-title verdict and the
four costed options.

---

## 85. A channel the score does not carry never draws, however much a script writes to it — so Itamar Park's arcade runs with no food, no animals and no enemies

**Closed 2026-08-14.** Closed with 94. The draw half was fixed by `7a41b29c` — a
script that gives a channel a member makes that channel live — and the
vertical-position half this entry left open *is* 94, which `a72ddc5a` fixed.
Nothing is left over.

**Status:** FIXED for the draw, and the objects are on screen; **their vertical
position is a second gap and it is 94, not 89** · **Area:**
`preview/channel.gd:carried`, `preview/sprite_state.gd:with_puppets`

**Correction, and it undoes this entry's central measurement.** The claim below
that channels 20-23 are "never carried by the score" is an artifact of the tool
that measured it: `tools/scratch/chanscan.gd` reads `Score.frame()`, and
`_snapshot` drops any record that names a member and states a zero size. All
eighteen object channels *are* recorded, for 178 frames each, naming `ObjBlnk`
at `locH` -1000 and at the three row `locV` values 340, 210 and 110 — which is
the vertical position this entry left missing. See 90 for the bytes. The fix
below is still right and still needed, because a script may give a channel a
member the score never gave it; what is wrong is the reasoning that no record
existed to retain. `tools/scratch/rawchan.gd` prints the records `frame()` hides.

A script that gives a channel a member now makes that channel live, which is the
reference's rule and not a special case there: `_channels` holds one `Channel`
for every channel however few the frame carries, `Sprite::setCast` raises the
`kAPCast` auto-puppet (`sprite.h:41`, `channel.cpp:649`), and `setClean` then
refuses to replace the sprite from the score (`channel.cpp:534`). This port draws
the score's per-frame sprite list, so "keeps being" had to be spelled out, and it
had been spelled `is_puppet()` alone — the explicit half only.

**A member is what makes a channel live, not any write at all.** A script that
writes only a position to an empty channel has said nothing about what to draw
there, and inventing something would put a sprite on stage no title asked for. So
the test is the cast group of `FIELDS`, the same three rows the merge treats as
the cast swap.

Measured at `torfim.dir` frame 24 (`AntPlay`), the four sampled object channels
now appear in `frame_sprites()` with real rects where they previously appeared
only in `_overrides`:

```
ch20 1:60@(93,0)   ch21 1:60@(-341,0)   ch22 1:177@(-1003,-12)   ch23 1:175@(-1565,-12)
```

`tools/scratch/chanscan.gd` confirms why a synthesised base was needed rather
than a remembered record: channels 20-23 are **never carried by the score** in
that movie, so there is nothing to retain. The base is `Sprite`'s own constructed
state in the reference — no cast, ink 0, default colours, and a zero size that
the cast swap replaces with the member's natural one.

---

## 86. `play frame the frame` re-enters its frame four times per rendered tick, and the play stack grows by four entries a tick for as long as the movie runs

**Closed 2026-08-14.** Closed by `6109b5f0`, which measured it and found the
attribution wrong. `FrameClock` banked time Director throws away and drained up
to four steps in one rendered tick, so the four re-entries counted here were the
accumulator and not the `play` path. Re-arming by assignment took Itamar Park's
arcade from 2.27 steps per paint at 34.7 Hz to 0.97 at 57.7 Hz. The unbounded
stack, which was the movie's own design, is bounded at `MAX_PLAY_STACK = 64` by
`038b79a4` so that a save cannot carry a quarter of a million identical return
addresses.

Itamar Park's arcade loop is `BehaviorScript 24 - play frame`:

```lingo
on exitFrame
  idle()
  KeepBackSoundGoing()
  play frame the frame
end
```

Director grows a stack here too — `Lingo::func_play` pushes one entry per call
(`lingo-funcs.cpp:212`) and nothing pops it until `play done` — so unbounded
growth is the movie's own design and not the finding. The finding is the **rate**:
`_play_stack` gains four entries per `process_frame`, so the frame's `exitFrame`
runs four times per rendered tick. Measured at `torfim.dir` frame 24 (`AntPlay`),
one entry per step:

```
step 470  play_stack=319
step 471  play_stack=323
step 472  play_stack=327
step 473  play_stack=331
```

The movie's tempo there is 80 fps against a 60 fps display, so at most two score
steps per rendered frame can be owed. The other two are the port re-entering the
frame within one step, and the arcade therefore runs at roughly twice the speed
the score asks for — which the title partly hides, because `calcStep` regulates
its scroll against `the ticks` rather than against the frame rate.

Not diagnosed further. The suspects are `lingo_go_frame`'s `_in_exit_frame`
branch, which writes `_index` directly and queues no jump, and
`frame_loop.advance`, which then does not know the frame was re-entered.

Reproduce: the command in entry 85, and read the `play_stack=` column.

---

## 94. A score sprite record that names a member and states a zero size is dropped, so eighteen of Itamar Park's arcade channels lose the only vertical position they ever get

**Closed 2026-08-14.** Fixed by `a72ddc5a` (2026-08-12).
`director_score.gd:_snapshot`'s occupancy test is `cast_id <= 0` alone; the size
half is deleted. This entry's own measurement — Itamar Park's three ice rows at
`locV` 340/210/110 — is quoted in the code comment beside it, together with a
consequence nobody had noticed: with the record dropped the obstacles took
`_bare_sprite`'s ink 0 and drew their paper as a white box.

**Status:** open · **Area:** `director/director_score.gd:_snapshot`, the
occupancy test · found while closing 89, and **it is what 85 and 89 both
misattributed**

`_snapshot` decides whether a channel is occupied with

```gdscript
if cast_id <= 0 or width <= 0 or height <= 0:
    continue
```

The size half has no counterpart in the reference. `Frame` reads every channel's
record into `_sprites[]` and `Score` builds one `Channel` per channel whatever
the record says; the only emptiness test anywhere near the render walk is on the
**cast id** (`score.cpp`, `channel.cpp` @ ScummVM 805f259a). A record that names
a member and states a zero size is a sprite there, and it is a sprite that
carries a position.

**Itamar Park's arcade is built on exactly that record.** Channels 20-37 are
recorded in `torfim.dir` for 178 frames each, all naming member `1:60`
`ObjBlnk` — a deliberately 0x0 bitmap, the title's own device for "occupy this
channel and draw nothing" — at `locH` -1000 and at three `locV` values that
repeat down the channels:

```
ch20 10 24 ff 00 0001 003c 0000 07f4 0154 fc18 0000 0000 ...
                       ^cast 60   locV 0x0154=340  locH 0xfc18=-1000  w=h=0
ch21 ... locV 0x00d2 = 210
ch22 ... locV 0x006e = 110
ch23 340   ch24 210   ch25 110   ...  through ch37
```

340, 210 and 110 are the arcade's three ice rows, and they are the **only**
place the objects' vertical position exists. Nothing downstream needs changing to
use them: `docs/bugs-closed.md` 91 already made the auto-puppet merge prefer the
frame's own record over a synthesised one, so admitting the record is enough for
the script's `locH` to land on top of the score's `locV`. `MovieScript 6 - play handlers1`
writes `sprite(i + j).locH` and nothing else; `MovieScript 7`'s `ChangePlayer`
sets the *player's* `locV` from `gPlayerLocVList` and `MovieScript 10`'s
`setSubLevelNum` reads an object's `locV` back
(`sprite(kSubNumSpNum).locV = sprite(getFlag(#FlagOnStage)).locV - 55`), so the
score is where the rows are authored and a script consumes them. With the record
dropped, `sprite_state.with_puppets` synthesises a base at `locV` 0 and every
object draws straddling the top edge of the stage.

Measured, by removing the size half of the test and playing the level in
(`tools/scratch/parkarcade.gd`, same command as below). Before:

```
ch20 1:51  AntAnimA1 loc(-226,0)   rect(-349,-46 123x93)
ch21 1:60  ObjBlnk   loc(-480,0)   rect(-480,0 0x0)
ch22 1:174 AntFood4  loc(-1091,0)  rect(-1139,-15 48x30)
```

After:

```
ch20 1:173 AntFood3  loc(-139,340) rect(-189,328 50x25)
ch21 1:52  AntAnimA2 loc(-644,210) rect(-760,167 116x87)
ch22 1:177 AntFood7  loc(-1087,110) rect(-1137,98 50x25)
```

Channels 44, 53, 54, 55, 59 and 60 — `kBonus3SpNum`, `kCollisionSpNum`,
`kSubNumSpNum` and `kBonusScoreSpNum`, all of them script-driven and all of them
recorded as `ObjBlnk` — arrive with their authored positions in the same run.

**Why it is filed rather than fixed.** Removing the size half admits 4,506
records in `itamar-park` and **370 across the six shipped titles**
(`tools/scratch/zerosize.gd`, out of 8,057,628 member-bearing records), and
three of those groups name a member with real pixels, where `drawn_size` would
then draw the member's natural size on a channel that draws nothing today
(`tools/scratch/zerosize2.gd`):

```
piposh / -en / -ru  Hezroom.dir ch6   1:245  d6          0x0      x10 each
piposh-dream        hatul2/3 ch10,27,32  1:86            1x1      x3
piposh-dream        meet7.dir ch15    12:5               48x31    x135
piposh2             GOLDDEAD.dir ch1  1:3 a1             640x400  x26
rating              11 movies ch48    2:33 GlobalTime    79x24 field  x176
itamar-park         torfim.dir 25 channels  1:60 ObjBlnk 0x0      x4506
```

`GOLDDEAD.dir` ch1 is a full-stage bitmap on 26 frames and `rating`'s ch48 is
the `GlobalTime` field on 176 — both would newly appear, and whether they should
is a question about `sprite_geometry.drawn_size`'s fallback rather than about
this test. Nobody has looked at those three on screen. That is the work this
entry is asking for; the diagnosis above is complete and the blast radius is
measured.

**This corrects two earlier entries.** 85 says channels 20-23 are "never carried
by the score", and 89 says Park's objects sit at `locV` 0 because
`the regPoint of member` was read-only. Both are wrong and both were measured
through `Score.frame()`, which is the post-filter view — `tools/scratch/chanscan.gd`
reads it, so "NEVER carried by the score" is what it prints for any channel whose
records are all zero-sized. `tools/scratch/rawchan.gd` prints the bytes instead.
`defReg`, the handler 89 blamed, occurs **twice** in `torfim.dir` — once as
`on defReg` and once in its script's name table — and is called from nowhere;
its 28 members are already anchored right-middle in the file, so running it would
change nothing. `the regPoint of member` was a real gap and is fixed (89, now in
`docs/bugs-closed.md`), and fixing it moves none of these objects.

Reproduce:

```bash
godot --headless --audio-driver Dummy --path . --script tools/scratch/rawchan.gd -- \
    --root res://test-games/itamar-park --file torfim/torfim.dir --frame 24 --from 18 --to 40

godot --headless --audio-driver Dummy --path . --script tools/scratch/parkarcade.gd -- \
    --root res://test-games/itamar-park --file torfim/torfim.dir \
    --steps 3000 --clicks "play+10:11" --until antplay --from 18 --to 60
```

The first prints the records above. The second plays the level select in, clicks
level 1, and prints every object channel's member, `loc` and drawn rect once the
arcade is running; the `loc(...,0)` column is the bug.

---

## 93. A behaviour gets its instance from `beginSprite` and from a click, and from nothing else: `exitFrame`, `enterFrame` and `prepareFrame` still run against a bare script

**Closed 2026-08-14.** Fixed by `038b79a4` (2026-08-12). `live_behaviour(script,
channel)` looks an instance up for every dispatch and never makes one, which is
the reference's shape (`Score::createScriptInstances` is the only constructor).
`tools/behaviour_me.gd` is in `gate.sh`'s `ALL` and writes `me` into a global
from inside the handlers themselves: DAY1 went from 7 of 9 checks failing to 0
of 10, magichat from 9 of 18 to 0 of 19.

**Status:** open · **Area:** `scenes/preview/scripts.gd:dispatch`,
`lingo/lingo_interpreter.gd:call_handler` · found while closing 87

`bugs.md` 87 made a behaviour an instance for the two messages it added, and
`scenes/preview/event_chain.gd` already did it for the mouse and key chain. The
frame events did not join in. `Scripts.dispatch` calls
`interpreter.call_handler(handler, [], script)` with the default channel 0, and
`call_handler` reads that as "not a behaviour" — so `on exitFrame me` in a
behaviour-channel script binds `me` to VOID, while `on beginSprite me` in the
script attached to the *same* score row binds it to a real object.

Director has no such split. A behaviour-channel script is one instance for the
life of its span and every message it receives arrives on that instance, which is
what makes the standard idiom work:

```lingo
property pSomething
on beginSprite me
  pSomething = ...
on exitFrame me
  if pSomething then ...
```

Here the property written in `beginSprite` is on an object `exitFrame` never sees.
Nothing in the six shipped titles is known to depend on it yet — this was found by
reading, not by a symptom — but it is the same defect `87` was, one message along,
and it is why `docs/ENGINE_TODO.md` still lists `the scriptInstanceList of sprite`
as `inert`.

**The fix is not "pass channel 0"**, and that is the whole difficulty.
`call_handler`'s channel-0 default is what stops a *movie* script and an ordinary
frame script from acquiring a `me` they have never had; `behaviour_instance` takes
an explicit `script_channel` flag for exactly that reason. What the dispatcher
needs is to know whether the script it is about to message is a behaviour-channel
script or a plain frame script, which `frame_loop.gd:sprite_behaviours_at` already
computes and `_begun_sprites` already records — so the join is available, and this
entry is the decision to make it deliberately rather than as a side effect of 87.

The same gap covers `sendSprite`/`sendAllSprites`, which still message a
behaviour's script directly (`docs/ENGINE_TODO.md`); after 87 those two and the
frame loop now disagree about what `me` is for the same sprite.

Reproduce by adding a case to `tools/sprite_lifetime.gd`: on any movie, run a
frame whose behaviour-channel script declares both `beginSprite` and `exitFrame`
and compare the object identity `me` binds to in each. `magichat.dir` frame 42's
`BehaviorScript 34 - album loop` declares `enterFrame`, `exitFrame`, `mouseUp` and
`endSprite`, which is four of the five doors in one script.

---

## 95. `logo.dir` restarts itself instead of entering the title, because `GetMoviePath(CDpath() & DirChar() & "magichat")` resolves back to the container it is already in

**Closed 2026-08-14.** Fixed by `6109b5f0`, **and this entry's diagnosis was
wrong**: `director_paths.resolve` was never reached and answers correctly when
it is. `preview_lingo_host:_go` recognised the movie argument only by a
container extension or the literal word `movie`, so an extension-less argument
degraded the statement to `go(1)`. The reference pops the last argument and
branches on its **type** (`lingo-builtins.cpp:b_go`), which is what the port
does now. `logo.dir` plays its logo and hands over to `magichat.dir` frame 23.
`tools/go_movie_arg.gd` is twice in `ALL`.

**Status:** open · **Area:** `scenes/director_preview.gd:lingo_go_movie` /
`director/director_paths.gd:resolve` · found while implementing digital video,
and **only visible because the logo now plays**

`logo/logo.dir` frame 6 is `run movie`'s `on exitFrame / QuitLogo`, which is

```lingo
go(1, GetMoviePath(CDpath() & DirChar() & "magichat"))
```

Measured: the playhead reaches frame 5, then 6, then **frame 1 of `logo.dir`**,
and plays the ten-second logo again, indefinitely. `CDpath()` is one of
`utils.cst`'s 93 movie handlers and answers empty here, so the argument reduces
to something `resolve` matches back to the container it is already in rather than
to `magichat.dir` at the corpus root.

**This is a path fault, not a video one, and it predates the decoder.** It was
invisible while the movie skipped the logo in one tick, because the same loop ran
then too — a two-tick cycle reads as "nothing happened" and a ten-second cycle
reads as a bug. That is the whole reason it is filed today rather than earlier:
making a thing work is how you find what was wrong behind it.

`magichat.ini` has `startfile=CD$\logo\logo`, so in the original this **is** the
boot path — the logo plays once and hands over to the title. A player is not
affected today: `run-itamar-magichat.bat` boots `magichat.dir` directly, so a
normal launch never enters `logo.dir` at all.

Reproduce:

```
godot --headless --audio-driver Dummy --path . --script tools/liveness_sweep.gd -- \
    --root res://test-games/itamar-magichat --boot magichat.dir --only logo/logo.dir --verbose
```

Worth checking together with it: whether `GetMoviePath` should be consulted at
all when the argument already names a container this engine can resolve, and what
`CDpath()` answers when the ini's `CDPATH` is blank — the recovered
`magichat.ini` blanks it deliberately so paths resolve against the tree wherever
it sits, which is the condition this reduces under.

---

## 96. SKIP walks marker to marker, so pressing it inside a gameplay segment jumps past that segment's own initialiser and on into its ending

**Closed 2026-08-14.** Fixed by `6109b5f0`, together with 32 and 37. The commit
says it: with the playhead no longer moved, 96's invariant — SKIP cannot land on
a frame whose initialiser has not run — holds by construction. The
linear-cutscene case the jump was retained for is served by the fast-forward
toggle, which runs the movie out *through* its own scripts.

**Status:** open · **Area:** `scenes/director_preview.gd:skip_to_end` · found
while chasing a "the fritz game does not start" report that turned out to be the
movie's own click gate, not a fault

`skip_to_end` takes "the marker after the playhead" as the start of the next
scene. That holds for a cutscene and does not hold for a segment a player *plays*:
Director markers label positions, not scenes, and the function's own comment
already concedes that nothing in `VWLB` distinguishes the two.

Measured on `piposh-dream`'s `COMEIN.dir`, standing in the idle loop the pot game
waits in, calling `skip_to_end` five times:

```
standing on f173
press 1 -> f179   return1   (the game's init: plantcounter, puppetSprite 27-29, keyUpScript)
press 2 -> f180   f1        (the pot drop -- the init above is now SKIPPED)
press 3 -> f192   f2        (the you-were-hit animation)
press 4 -> f209   fritzend  (the lose scene)
press 5 -> f226   fritzwin  (the win scene)
```

Press 1 is right and every press after it is not. Landing on `f1` without `return1`
gives the pot game with no `plantcounter`, no puppeted pot channels and no
`keyUpScript` — a screen where the arrows do nothing and no pot is ever cleared,
which reads as "the game is broken" rather than as "SKIP was pressed twice". Two
more presses and the player is in the lose scene. Every character's segment in
that movie has the same layout (`enterdoc`/`y1`/`y2`/`docend`/`docwin`,
`enterkrupnik`/`y4`/`y5`/`krupend`/`krupwin`), so this is not one room.

**`_skip_sent` bounds it and does not fix it.** `e3a78651` stopped SKIP revisiting
a marker, which is what closed the Rating `MAINMENU` cycle; the diff shows the
forward walk above is unchanged by it. What it adds is that `179` is burned after
press 1, so a player who has walked past the init can never SKIP back to it and
gets `skip: nothing further to skip to` instead.

Reproduce: drive `skip_to_end` directly, because **no existing harness can press
SKIP** — `route_press` is the movie's path and the hotspot is tested in `_input`
(`InputRouter.mouse_button`'s `skip_rect` argument), so `scene_probe --clicks`
falls through to the movie and reports `ch0 / mouseUp:NO HANDLER` whatever
`--debug-ui` says. Stand a preview on `COMEIN.dir` f173 and call
`skip_to_end` in a loop, printing `current_frame()` and `_skip_sent` after each.

Two fixes were considered and both trade away a case already fixed. "Do not cross
a frame whose script has not run" refuses the legitimate EXODUS skip, where every
frame of a fresh cutscene is unrun. "Re-arm `_skip_sent` when the movie itself
moves the playhead back" reintroduces the Rating cycle, which is the movie moving
back over burned markers by design. Anything attempted here should be measured
with `tools/skip_state.gd`, which already covers the EXODUS and MURDER1
mis-landings, before and after.

---

---

**The eighteen entries below were closed on 2026-08-14 because the code they are
about no longer exists.** They are not fixed. The retired renderer took a whole
native runtime with it, and every one of these entries is written against a symbol
or a data file that returns nothing at `ecc6d070`: `MoviePlayer`,
`PuppetController`, `DirectorRuntime`, `goto_movie`, `resolve_label` / `prefer_go`,
`use_lingo_frames`, `use_lingo_clicks`, `start_walk`, `_mark_movie_loaded`,
`movie_context.json`, `walk_doorways.json`, `assets/render_model/`, `data/lingo/`.
An entry that cannot be re-measured cannot be worked on, and leaving it filed as
open is what made two thirds of this queue unreadable.

**A deleted cause is not a fixed symptom**, and that distinction is the reason
these are a separate section rather than folded in above. Where the question
outlives the entry the closing note says so and says where to re-ask it. Entry 19
was closed on this same ground and its account is above.

They are kept in full for the same reason as everything else here: re-deriving
what was ruled out costs a session each.

---


## 21. Every wandering character is on screen twice, because only half of `peoplefunk` is ported

**Closed 2026-08-14.** Closed with 2, and by the same deletion:
`GameState.people_funk` has no callers and `DirectorRuntime._try_people_funk` no
longer exists, so the half-port this entry blames is not what runs. **This is
not evidence that the symptom is gone.** Whether a guest still draws twice in
`field`, `edge1` and `veranda` is a live question about the interpreter and
needs re-filing from a screenshot or a sweep.

**Status:** open · **Area:** interpreter host / score runner

Reported from play as "bugs in the scenes of characters that appear multiple
times", with screenshots of DAY1 `@field`, `@edge1` and `@veranda`. It was first
mistaken for authentic crowd art — the two loops in `@veranda` really do name the
same member — and that reading was wrong. The **member names** settle it:

| room | channels | loops | names |
|---|---|---|---|
| `field` | 18 / 21 | wonder 98 / 94 | `arinlop1` / `brinlop1` |
| `field` | 19 / 20 | wonder 22 / 47 | `apatlop1` / `bpatlop1` |
| `edge1` | 18 / 20 | wonder 150 / 175 | `amoglop1` / `bmoglop1` |
| `veranda` | 18 / 20 | wonder 196 / 201 | `atoflop1` / `btoflop1` |

Each room carries an `a` and a `b` loop of **one** character — Rinati, Pat,
Mogul, Tofi — at two positions. The original shows one of each pair; the port
draws both, so every one of these characters appears twice.

**The original picks with a counter.** `WONDER/MovieScript 246` is `peoplefunk`,
and after its meeting-routing chain it does:

```
repeat with i = 18 to 21
  puppetSprite(i, 0)
end repeat
if item 1 of nextroomdata = "field" then peoplecont(1)
  else if ... "tennis" then peoplecont(2)
  else if ... "edge1"  then peoplecont(3)   -- but on day 3, hide 18 and 20 outright
  else if ... "veranda" then peoplecont(4)
  else if ... "dwarfs" then dwarfscont(8) / dwarfscont(9)
  else if ... "exitforest3" then dwarfscont2(10)
```

and `peoplecont(i)` advances `item i of inexits` 1..10, wrapping, then shows one
pair and hides the other:

```
if x > 5 then  18,19 invisible; 20,21 visible
else           18,19 visible;   20,21 invisible
```

So the guests move around the estate as you re-enter rooms. The talk behaviours
read that state back — `BehaviorScript 290` and `291` both branch on
`if sprite(18).visible = 1`, and `BehaviorScript 249` picks `xxx = "a"` or `"b"`
with the channel numbers to match — so with nothing hidden they also take the
wrong branch and drive the wrong sprite.

**Two things are missing, and the second is an old friend.**

1. `DirectorRuntime._try_people_funk` calls `GameState.people_funk`, which is a
   `meeting_triggers` table lookup and nothing else. It reproduces only the
   routing chain at the top of the original handler; the `puppetSprite` /
   `peoplecont` half below it has no port at all.
2. `inexits` is never set. `init all` seeds it as `"0,0,0,0,0,0,0,0,0,0"` and
   `init all` never runs — that is entries 9 and 13, biting a third time. Even if
   `peoplecont` were called, `value(item i of inexits)` has nothing to read.

Not a rendering bug: the interpreter has both handlers loaded and sprite writes
do reach the stage (`docs/bugs-closed.md` 1 is closed, `tools/sprite_channels.gd`
covers it).

Reproduce — all four channels present and none hidden, with both globals unset:

```
godot --headless --script - <<'EOF'
extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
    var r: RefCounted = load("res://director/director_runtime.gd").new()
    r.boot(); r.goto_movie("DAY1", null, {"label": "field"}); r.running = false
    print("peoplefunk=%s peoplecont=%s inexits=%s" % [
        r.lingo.interpreter.has_handler("peoplefunk"),
        r.lingo.interpreter.has_handler("peoplecont"),
        str(r.lingo.interpreter.globals.get("inexits", "<unset>"))])
    for c in [18, 19, 20, 21]:
        print("ch%d hidden=%s" % [c, r.is_channel_hidden(c)])
    quit(0)
EOF
```

Observed: `peoplefunk=true peoplecont=true inexits=<unset>`, and all four
`hidden=false`.

`tools/wandering_characters.gd` is the pass/fail form of the same question and
asserts the player-visible invariant, how many of each pair are drawn, rather than
that `inexits` and a getter agree. It is **uncommitted and unverified** at the time
of writing: run it before trusting either its red or its green.

Not the same bug as `docs/bugs-closed.md` 14's film-loop half, found in the same rooms in the
same pass. That one drew these characters at the wrong size; this one draws twice
as many of them as there should be.

**Attempted and not finished — the handlers resolve but invoking them does
nothing.** This is the next thing to chase, and it is narrower than where this
entry started. Booting DAY1, seeding the globals `init all` would have left, and
calling the handlers straight off the interpreter changes no observable state:

| call | `inexits` after | channels 18-21 |
|---|---|---|
| `call_handler("peoplefunk")` | `0,0,0,0,0,0,0,0,0,0` | all shown |
| `call_handler("peoplecont", [1])` | `0,0,0,0,0,0,0,0,0,0` | all shown |
| `call_handler("whatodoeveryframe")` | `0,0,0,0,0,0,0,0,0,0` | all shown |

`peoplecont(1)` on `inexits = "0,0,…"` must leave `1,0,0,…` and hide 20 and 21.
It leaves both untouched, so the body is not running — the handler is not merely
taking a branch that skips the writes.

Ruled out on the way, so they do not get re-checked:

- **The handler is missing.** `has_handler` is true for `whatodoeveryframe`,
  `peoplefunk`, `peoplecont`, `cursorfunk` and `displayobject`.
- **Chunk assignment is unimplemented.** `put x into item i of inexits` has a
  path: `_assign_chunk` at `lingo_interpreter.gd:408`.
- **The `global` declaration wipes the seeded value.** It is guarded by
  `if not globals.has(key)` at `lingo_interpreter.gd:234`, and keys are
  lowercased, which is what the probe wrote.
- **Sprite writes cannot reach the stage.** Entry 1 is closed and
  `tools/sprite_channels.gd` passes.

Two candidates not yet separated: `call_handler` outside a frame dispatch may not
establish whatever scope the body needs, or `sprite(N).visible` for a channel
other than 30 may not land where `is_channel_hidden` reads. Test the second
first — it is one assertion — because if it is true then the body may have been
running all along and `inexits` is a separate defect.

**The fix is entry 2, not a patch here.** The original calls `peoplefunk()` from
`whatodoeveryframe` and nowhere else, so there is no engine-level place to put
this that does not amount to teaching the engine that `field` is slot 1 and that
channels 18-21 hold guests — which is the standing rule in `AGENTS.md` broken in
the same shape that caused the bug. `whatodoeveryframe` is runnable now that
`docs/bugs-closed.md` 1 is closed; running it fixes this one for free and retires
`GameState.people_funk` at the same time. Deliberately **not** patched natively.

---

## 2. `whatodoeveryframe` is reimplemented natively, not run

**Closed 2026-08-14.** `PuppetController` is deleted — the two remaining
mentions in `lingo_interpreter.gd` are comments. `GameState.people_funk`, the
substitute this entry is about, survives with **zero callers**. There is no
hand-written walk state machine left to replace.

The question outlives the entry: the port now runs the movie's own scripts, so
whether `whatodoeveryframe` actually drives channel 30 is a measurement against
`scenes/preview/frame_loop.gd` and wants re-filing from a run, not from here.

**Status:** open · **Area:** puppet

`PuppetController` is a hand-written version of the original's walk state machine.
It reads the original's globals (`ifmovie`, `nextroomdata`, `egozh`, `egozv`,
`whatodo`, `syz`) but decides everything itself, so each of the original's lines
that the port needs has to be copied across by hand. The room-transition hide
(`sprite(30).visible = 0`) is the most recent example, and every one of these is a
place the copy can drift from the script.

~~Blocked on 1~~ — **no longer blocked, and this is now the highest-value open
entry.** The blocker was that `whatodoeveryframe` drives Piposh entirely through
`the memberNum of sprite 30` and `the locH / locV of sprite 30`, which the
renderer ignored. Entry 1 is closed, so those writes land: booting DAY1 `@field`
and writing `loc_h` / `loc_v` on channel 30 reads back through
`effective_sprite(30)`, and `has_handler("whatodoeveryframe")` is true, as it is
for `peoplefunk`, `peoplecont`, `cursorfunk` and `displayobject`.

**What it now also costs to leave open.** `whatodoeveryframe` is where the
original calls `peoplefunk()` — three times, once per transition shape. The port
never runs it, so it substitutes `GameState.people_funk`, which reproduces only
the meeting-routing half of that handler. The dropped half places the wandering
characters, and its absence is entry 21: every guest in `field`, `tennis`,
`edge1`, `veranda`, `dwarfs` and `exitforest3` is on screen twice. Running this
script fixes 21 as a side effect and retires `meeting_triggers` with it.

Doing it needs `init all`'s globals to exist first — `inexits` at minimum, see
entries 9 and 13 — and needs the 117-hotspot walk diff measured before and after,
because this replaces the walk state machine wholesale. Read
`porting-fidelity-verification` before reading those numbers.

**Baseline for that comparison, measured 2026-08-06 at `176f08ca`**, so the next
attempt can attribute rather than re-derive: `tools/lingo_walk_diff.gd` reports
117 walk cases across 3 movies, **identical outcome 85/117**, 19 of the
differences `[wrong-room]`. All nine pass/fail harnesses green at that commit:
`smoke`, `puppet_visibility`, `sprite_channels`, `room_names`, `collectables`,
`cursors`, `sprite_stretch`, `film_loop_stretch`, `verify_film_loops`. Do not
copy these numbers forward without re-running them — stale figures pasted into
prose have already cost this project a session.

An attempt was made and stopped short; what it established, and what it ruled
out, is in entry 21 rather than here, because the block is in invoking the
handlers at all.

---

## 23. An interpreted `exitFrame` that decides *not* to navigate is overridden by the export

**Closed 2026-08-14.** There is no export. `use_lingo_frames`,
`use_lingo_clicks` and `assets/render_model/` are all deleted, so "the exported
nav overrides the script" names no mechanism. The blast-radius counts in this
entry were computed from `data/lingo/*/[cast].json` against
`assets/render_model/*/frames.json`, neither of which exists.

`MAX_GUARD_HOLD_MS`, the dead code this entry also records, went with the same
function.

**Status:** open · **Area:** interpreter host / score runner · **general, not one movie**

`game_step` dispatches the frame's own `on exitFrame`, and honours it only when it
navigated or held:

```gdscript
if lingo.dispatch_frame_event("exitFrame", frame_index):
    if lingo.host.navigated or lingo.host.held:
        return
```

Everything else falls through to the exported nav. But **"the script ran and chose
to go nowhere" is a decision, not an absence of one**, and the exported nav is a
lossy summary of that same script with its conditions stripped. So when a handler
navigates conditionally, the port runs the condition, gets `false`, and then jumps
anyway.

MURDER1 frame 789 is the measured case. `BehaviorScript 41` is present and
decompiled:

```lingo
on exitFrame
  global pptcount, tlkpath
  if pptcount = "1" then
    go("moreof")
    sound playFile 1, tlkpath & "tof11.aif"
  end if
end
```

`pptcount` is set to 1 by exactly one script — `CastScript 38`, the middle option
at the *later* `choose2` prompt — so on any other path the handler must fall
through to frame 790 and the scene skips the "more of" branch. The export wrote
frame 789's nav as an unconditional `{kind: label, value: "moreof"}`.

Measured with `tools/_ppt_probe.gd` (scratch, deleted; the transcript is the
evidence):

```
frame 789 script resolves to: BehaviorScript 41
  handlers: ["exitFrame"]
dispatch_frame_event('exitFrame', 789) handled=true  navigated=false  held=false
after one step -> frame 850 label=moreof
```

`handled=true, navigated=false` is the script correctly declining, and the port
went to 850 regardless. Every player therefore sees the optional branch, on every
path through the scene.

**Do not just suppress the export when a script ran — the blast radius is
measured and it is large.** Counting every frame that carries both a
`frame_script` resolving to a movie-local script with an `on exitFrame` and a
non-null exported nav:

| frame's `on exitFrame` | frames |
|---|---|
| navigates **conditionally** (`if` … `go`) | **2,441** |
| navigates unconditionally | 984 |
| never navigates | 4,426 |
| no script resolves at all (export is the only source) | 33,307 |

The 2,441 are the frames this rule change would alter, across **156** distinct
`(movie, script)` pairs — among them `DAY1 BehaviorScript 56 - init all`, every
`gameover` / `end` branch in ARCADE1 and ARCADE2, and the marker-0 hold scripts.
The failure mode is a frame whose handler the interpreter runs but whose `go` it
cannot execute: today the export catches it, and after the change that frame stops
dead. With 33,307 frames having no script at all, the export is load-bearing and
cannot simply lose to the interpreter.

So the fix is not one condition. It needs `tools/lingo_walk_diff.gd` and
`tools/lingo_frames.gd` run either side of it, and the conditional cases read
rather than counted. The count above comes from a static sweep of the handler ASTs
in `data/lingo/*/[cast].json` against the `frame_script` and `nav` fields in
`assets/render_model/*/frames.json` — cheap to redo, and worth redoing before
acting on the figure.

**`MAX_GUARD_HOLD_MS` is dead code in the same function.** `held` is
`_time_ms - frame_entered_ms`, and every branch out of the soundBusy guard —
`busy_nav`'s `enter_frame`, and `_advance_or_hold` — calls `enter_frame`, which
resets `frame_entered_ms`. `held` can never exceed one frame, so the 20-second
timeout has never fired. It matters if a guard ever waits on a sound that does not
start; today `AudioDirector.sound_busy` returns false for a failed channel, so
nothing reaches it.

---

## 20. `wonder.cst` has a degenerate `ccl `, so 98 film-loop children draw nothing

**Closed 2026-08-14.** Measured through `tools/generate_cast_registry.py` into
`assets/render_model/cast_registry.json`, and both are dead. Film-loop children
now resolve against **their own container's** `ccl ` list
(`scenes/preview/film_loop_view.gd`, `table.cast_list_for(lib)`) rather than
through a generated registry, and `tools/film_loop_cast.gd` gates that in `ALL`.

Whether WONDER's degenerate `ccl ` still costs anything is a question for the
live path and needs a live command; the two members this entry names are the
fixture for it.

**Status:** open · **Area:** assets / cast registry

`tools/generate_cast_registry.py` prints `2145 resolved, 98 dropped as
unresolvable`, and **all 98 are WONDER's**. Every other cast in the corpus
resolves every child.

The cause is in the container. `ccl -3333.bin` is 18 bytes — header, `count = 1`,
offsets `[0, 4]`, then `00 01 00 00` — so its single entry is a **zero-length
path**. Compare MURDER1's, which is 131 bytes and holds three real paths
(`macintosh hd:pip2 full:tofi.cst` and so on). `parse_ccl` therefore answers
`['']`, `resolve_cast('')` answers `""`, and `_frame_sprites` refuses every child
whose `cast_index` is 0 rather than let it fall back on the owning cast — that
refusal is deliberate and correct, because the fallback draws a stranger's bitmap
(see `docs/bugs-closed.md` 15). The children are simply invisible instead.

They are only two distinct members, but neither is small and one is on screen a
lot:

| member | size | channel | records |
|---|---|---|---|
| 983 | 153x197 | 10 | 74 |
| 222 | 70x51 | 17 | 24 |

**Which cast they belong to is not yet known, and the usual method fails here.**
Sizing the children against every registered cast is what identified `tofi` and
`goldolin` for MURDER1; it finds nothing this time. Member 983 exists in **no**
registered cast at any size — only `sea1` even reaches that far, at 1033 — and no
member anywhere in the corpus is 153x197 or 70x51. So the referenced cast is
plausibly one that was never exported, which would make this an extraction gap
rather than a parsing one. WONDER is the crowd cast for DAY1, NIGHT1 and SEA1, so
whatever is missing is missing from the three biggest hubs.

Not the same bug as `docs/bugs-closed.md` 14's film-loop half. That one drew children at the wrong
size; this one does not draw them at all, and the two were found in the same pass
over the same rooms.

Reproduce:

```
python3 tools/generate_cast_registry.py    # "98 dropped as unresolvable"
python3 -c "
import sys; sys.path.insert(0,'tools')
from pathlib import Path
import director_film_loops as dfl
root = Path.home()/'Projects/_private_projects/piposh2-toolcache/chunks'
print(dfl.parse_ccl(root/'WONDER/WONDER/chunks'))    # ['']
"
```

---

## 6. SEA1 and AIR1 stall under interpreted frames

**Closed 2026-08-14.** Closed with 4 and 7. `use_lingo_frames` does not exist
and `tools/lingo_frames.gd` is deleted.

**Status:** open · **Area:** interpreter / frames

With `use_lingo_frames` off, SEA1 visits 24 distinct frames over 220 ticks and
AIR1 visits 34. With it on, SEA1 sits on frame 3 for the whole run and AIR1 stays
between 3 and 29. Agreement with the score runner is 0/220 ticks for both, against
220/220 for DAY1, NIGHT1 and HOTEL1.

**Reproduce:** `godot --headless --script tools/lingo_frames.gd`.

---

## 4. Two exits stop working when clicks are interpreted

**Closed 2026-08-14.** The flag and the oracle are both deleted: there is no
`use_lingo_clicks`, and `tools/lingo_walk_diff.gd` went with the retired
renderer. The export it diffed against is gone for good — see the coverage-debt
table in `bugs.md`, which records these three harnesses as **unportable** rather
than as work.

**Status:** open · **Area:** interpreter / walk

`DAY1 @edge2go ch10` and `NIGHT1 @edge2go ch10` walk to `edge1go` with
`use_lingo_clicks` off and do not walk at all with it on. Present before the
current session's changes; confirmed by running the harness against a clean
checkout.

**Reproduce:** `godot --headless --script tools/lingo_walk_diff.gd`, rows tagged
`[no-walk]`.

---

## 7. Two clicks produce no navigation or sound under the interpreter

**Closed 2026-08-14.** Closed with 4 and 5. `tools/lingo_converge.gd` is deleted
and its oracle was the export.

**Status:** open · **Area:** interpreter / clicks

`SEA1 ch9 frame 1234` and `AIR1 ch8 frame 707`: the export carries a destination
and a sound list, the interpreted handler produces neither. These are the only two
outright disagreements in the convergence run, so they are small and specific
enough to read end to end.

**Reproduce:** `godot --headless --script tools/lingo_converge.gd`, lines tagged
`differ`.

---

## 5. Nineteen walks reach a different room than the export

**Closed 2026-08-14.** Closed with 4 and 7. `tools/lingo_walk_diff.gd` is
deleted and so is `movie_context.json`, which this entry names as the weaker of
its two references. There is nothing left to disagree with.

**Status:** open · **Area:** interpreter / walk · **Related:** 9

Most are HOTEL1, where the export is the weaker of the two references:
`movie_context.json` has 23 unmapped transitions there and no verified ones, and
its destinations repeat per channel across unrelated rooms. Some of the 19 are
likely the interpreter being right and the export wrong. Each row needs reading
against the original handler before it is called a bug.

**Reproduce:** `tools/lingo_walk_diff.gd`, rows tagged `[wrong-room]`.

---

## 13. `init all` never runs on movie entry

**Closed 2026-08-14.** `goto_movie` is deleted, and with it the
jump-straight-to-a-room's-`*go`-frame path this entry describes. Whether a movie
entry still misses `init all` is now a question about `scenes/preview/boot.gd`
and `frame_loop.gd`; `tools/boot_state.gd` is the live harness that asks it, and
`bugs.md` 25 and 36 carry the cold-entry half.

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

## 9. `init all`'s puppeting is lost on every movie change

**Closed 2026-08-14.** `_mark_movie_loaded` is deleted. The clear-on-load this
entry is about no longer exists, and neither does the `goto_movie` return path
it was measured through.

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

## 24. Every room entry skips the room's own entry frames

**Closed 2026-08-14.** `resolve_label` and `prefer_go` both return nothing at
HEAD. The `<room>` → `<room>go` swap this entry is about is not in the tree.

The finding underneath it is still true of Director and worth keeping: a room's
entry frames carry work — `nof`, `whereami`, the ambience — that entering at
`<room>go` skips. Re-file it if a measurement shows the live path doing the same
thing.

**Status:** open, deliberately not fixed · **Area:** label resolution ·
found while fixing 22, not caused by it

`resolve_label(name, prefer_go)` swaps `<room>` for `<room>go` whenever the "go"
variant exists, and both `goto_movie`'s `label` option and `_on_puppet_arrived`
pass `true`. **The original does not do that.** `whatodoeveryframe` ends a walk
with `go(item 1 of nextroomdata)` — the bare marker — and `go("clif2","day1.dir")`
likewise names `clif2`. In DAY1, `clif2` is frame 1911 and `clif2go` is 1913, and
the two frames between them are the room's own entry work:

* `BehaviorScript 83 - b4 bk's` (`on enterFrame`) sets `nof` from channel 1's
  member name, sets `whereami = label(0)`, and places sprite 30 at `egozh`/`egozv`
* `BehaviorScript 359` (`on exitFrame`) starts the room's ambience —
  `sound playFile 2, effectspath & "clif1.aif"`

Entering at `<room>go` runs neither, in every room, on every arrival.

**It appears to cost nothing, and the reason is the score's own repair.** The
handover scripts also set `nextroomdata`, and the idle script the port *does* run —
`BehaviorScript 55` → `whatodoeveryframe` — reacts to a `nextroomdata` other than
`"000"` by doing `go(item 1 of nextroomdata)` itself, walking into the entry frames
a step late. Measured: `tools/room_names.gd` enters every room through exactly this
path and reports **0 rooms without a `nof` and 0 wrong** across DAY1 (32), NIGHT1
(35) and HOTEL1 (10) — and `nof` is set in the skipped handler, so it is being set
somewhere. That figure was taken *before* 25's skip routing was investigated and does not
depend on it: 25's fix changed skip routing only, not `goto_movie`, so
`room_names.gd` still enters rooms the same way. Re-read it if `goto_movie` ever
gains an init-seeding path — the abandoned attempt in 25 would have made this
number measure `init all` instead of the score's repair.

What is not established is the case where `nextroomdata` is already `"000"` on
arrival, when nothing re-enters the entry frames: `whereami` then stays whatever
the last room set it to, and stale `whereami` is the failure 640285b9 describes,
with 114 scripts gating a hotspot on it. Left open rather than fixed because a
change to `prefer_go` touches every room entry in the game and needs the
row-by-row read of `tools/lingo_walk_diff.gd` that entry 23 also asks for — not
because the mismatch with the original is in doubt.

**Unrelated trap found the same way:** `godot --headless --script` **exits 0 on a
parse error**. A harness that fails to compile looks like a harness that passed if
you read `$?` instead of the output.

---

## 11. The upstream exporter decodes every 1-bit member as 8-bit

**Closed 2026-08-14.** The exporter this entry is about no longer feeds the
port. `director/director_cast.gd` reads the `CASt` pitch word itself —
`STRIDE_MASK` `0x7FFF` and the depth byte at offset 23 — so the 1-bit decode is
the engine's own, and `assets/render_model/`, which
`tools/repair_1bit_members.py` repaired in place, is deleted. The warning this
entry ends on (a re-export silently undoing the repair) has no re-export to
worry about.

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

## 14. `strtgame`'s chunk dump does not reach its members' declared sizes

**Closed 2026-08-14.** The dump this entry measures is `assets/render_model`'s,
deleted with the renderer. The port reads containers directly and
`tools/container_equality_check.gd` gates that reader against the ProjectorRays
chunks, in `gate.sh`'s `ALL`.

If `strtgame`'s members still fall short of their declared sizes that is a
finding about the live reader and belongs in a new entry with a live command.
The half of this number that was fixed is in this file already, under 14.

**Status:** open, suspicion only · **Area:** assets ·
all three drawing defects this entry carried are fixed, see `docs/bugs-closed.md` 14

The visible symptom this entry was filed for, the bearded man's head smeared
horizontally across the sky in the opening raft video, is fixed and was the dropped
stretch flag. What is left is a measurement about the dump underneath it that has
no innocent explanation yet.

Only **17 of `strtgame`'s 195** 8-bit members reach their declared size as a clean
prefix of their chunk. Member 26, the head, decodes to a clean prefix of 194 bytes
in a 3,293-byte chunk against a declared 46 x 34. For contrast, DAY1 decodes 440 of
452 members exactly and MURDER1 24 of 24. That is a payload-boundary problem across
the whole of `strtgame`'s dump, not a fact about one member.

One signal keeps the member-side suspicion alive on its own: member 26's
registration point is **(68, 17) on a 45-wide bitmap**, so it sits outside the
image, and 68 is half of 135, the width the score stored and Director ignores.

Two readings were tried and do not survive measurement, so they do not get
re-checked. `BITD-2774` decoding past its declared size proves nothing: member 25,
this entry's own control, does the same, and so do 388 of `strtgame`'s 390 8-bit
members. And the `CASt` rect reading 45x34 is not a disagreement; that a geometry
is declared is not evidence against it.

Anyone picking this up settles the chunk boundaries first. No claim about one
member's geometry can be made on top of a dump that is wrong movie-wide.
The XFIR reader's own disagreement with ProjectorRays, 441 of 912 chunks at the same
offsets with different payload boundaries, is a separate and still-untested fact,
and is not the same claim as "there are no chunks": `strtgame` has had a complete
1,019-chunk ProjectorRays dump the whole time.

---

## 22. MURDER1's Lingo is in the binary and the decompiler emitted one cast of five

**Closed 2026-08-14.** The decompiler's output is no longer the port's source of
Lingo: scripts compile from the container's own `CASt` records
(`lingo/compile/`), which is why `e1ca332b` could census the corpus's sourceless
scripts at all. `tools/script_compile_check.gd` is the live measurement and its
remaining debt is `bugs.md` 39. The navigation defect this number carried is in
this file already, under 22.

**Status:** open · **Area:** assets / decompilation ·
the navigation defect this number carried is fixed, see `docs/bugs-closed.md` 22

MURDER1's frame scripts 116, 117, 119, 120 and 424 resolve to nothing, while
`toolcache/chunks/MURDER1/MURDER1/chunks/` holds 33 `Lscr-*.bin` chunks. The Lingo
is in the container; the decompiler emitted one cast out of five.

What the gap costs is entry 23. Where a frame script is present, the export's lossy
copy of it can still win; where no script resolves at all, the export decides alone
and there is nothing to disagree with it. 116 and 117 are the choice wait loop and
119 and 120 the mouth-flap-while-speaking loops, and those four happen to have
their semantics in the exported nav already, which is why the scene plays. Nothing
establishes that the other chunks are as harmless.

Source for a re-run: `originals/recovery/web-alpha/PIP2DATA/MURDER1.DXR`.
ProjectorRays is not installed on this machine, which is the whole of what blocks
this.

**Why the number is still cited.** `AGENTS.md`, `tools/lib/driver.gd`,
`tools/probe.gd`, `tools/cliff_meeting.gd` and `autoload/app_settings.gd` all point
at "bugs.md 22" for the real-time lesson: a synthetic `for i in N: tick()` loop
advances the runtime's clock and not the audio server's, so every `soundBusy` guard
holds for ever and any scene with speech in it looks stuck. That account is in
`docs/bugs-closed.md` 22.

---

## 10. Convergence is measured on 5 of 61 movies

**Closed 2026-08-14.** The two harnesses this entry counts coverage in —
`lingo_converge.gd` and `lingo_frames.gd` — are deleted, so "5 of 61" is a
fraction of nothing. The live answer to the same worry is `gate.sh`'s 78 entries
and `tools/liveness_sweep.gd`, which walks a corpus rather than five named
movies.

**Status:** open · **Area:** verification

`lingo_converge.gd` and `lingo_frames.gd` cover DAY1, NIGHT1, HOTEL1, SEA1 and
AIR1. Nothing measures the other 56, including every minigame and meeting movie.
An engine change can only be checked against the five.

---

## 17. 478 of the registry's 497 film loops are unverified

**Closed 2026-08-14.** `tools/verify_film_loops.gd` is deleted and
`assets/render_model/cast_registry.json` with it, so both sides of this entry's
ratio are gone. Film loops now have four gate entries rather than one hardcoded
`CASES` list: `film_loop_cast` (the child's cast), `film_loop_scale` (its size —
the half the coverage table recorded as uncovered), `film_loop_restart` and
`film_loop_nesting`.

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

## 8. Both `movie_context.json` and `walk_doorways.json` paths are still live

**Closed 2026-08-14.** Both files are gone. `data/` holds
`director_palettes.json` and nothing else, no `walk_doorways.json` or
`movie_context.json` exists anywhere in the tree, and the only survivors are two
stale comments in `autoload/game_state.gd`. The retirement this entry asked for
has happened; delete those comments when something else touches that file.

**Status:** open · **Area:** scaffolding retirement · **Related:** 5

The transition destinations now have a Lingo answer: `BehaviorScript 207` reads
`item 1 of nextroomdata`, and the native redirect only runs when that script does
not. The rest of the tables have no Lingo answer yet: hub membership, meeting
triggers, phase transitions, day advance, per-hotspot walk doorways. Every one is
a guess that will eventually contradict the scripts, and the HOTEL1 and NIGHT1
rows are marked inferred rather than verified in the data file itself.

Retire in the order they become redundant, and delete rather than leave both
paths live.

**`walk_doorways.json` is next and is now redundant on the path the game runs.**
Fixing `walkonby` to read all three items of `nextroomdata` gave every interpreted
room exit the arrival point its own hotspot script authors, so no interpreted exit
consults the table any more; only the export-driven `start_walk` still does. See
`docs/bugs-closed.md` 26, which also records why the table's premise was wrong in a
useful way: it reverse-engineered per-edge coordinates from the score by reciprocity
and got close, `(30,328)` against the script's `(33,291)` and `(326,371)` against
`(344,375)`, while the real numbers were in the Lingo the whole time.

---

## 18. The gamepad cursor is drawn by code that has never run

**Closed 2026-08-14.** `MoviePlayer` and `_apply_cursor` are both deleted. `grep
-rn "MoviePlayer\|_apply_cursor" --include="*.gd" .` returns nothing at HEAD, so
this entry names no code — which is exactly the ground entry 19 was closed on.
The question underneath it, whether a drawn gamepad pointer lands on its own
hotspot, has nothing to ask it of until a gamepad path is written again.

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

## 107. `the memberNum of sprite` answered a packed reference once a script had written one, so Piposh Dream's platformer and duel could not move at all

**Status:** FIXED · **Area:** `scenes/preview/channel.gd:read` · found from a
player's "he doesn't move, at all", after four wrong hypotheses about the keyboard

`channel.gd:read` answered from the override entry **before** consulting the row's
`kind`:

```gdscript
func read(prop: String, sprite: Dictionary) -> Variant:
	if entry.has(prop):
		return entry[prop]        # raw -- no `kind` conversion
	...
	match str(row["kind"]):
		"member":     return int(sprite["cast_id"])   # bare
		"member_ref": return Members.pack_ref(...)    # packed
```

So the `membernum`/`castnum` split held only while the **score** owned the channel
and collapsed the moment Lingo wrote one. `member(3, 2)` evaluates to a *packed*
reference, so `set the member of sprite 15 to member(3, 2)` stored **131,075** and
`the memberNum of sprite 15` answered 131,075 instead of 3.

**`preview/members.gd:pack_ref` predicted this in its own docstring and nobody
re-measured it** — "reusing it anywhere the integer might be *stored* would need
that claim re-measured". The override entry is precisely where it is stored. That
is the reusable half of this entry: a docstring that names the condition under
which a claim stops holding is a test nobody wrote.

### Why it presented as a keyboard bug, and why the screen looked fine

`_merge_one` has always unpacked correctly, so the **artwork** was right throughout
— the character stood there, correctly drawn, refusing to move. Four hypotheses
were spent on the keyboard before the property was measured: the `keyUp` arm not
stamping `the keyCode` (which turned out to match the reference exactly and was
correctly left alone), `Keys.code_for` returning -1 on an unmapped keycode, primary
`keyDown`/`keyUp` **pairs**, and **linked casts**.

The last two are the instructive ones: they correlated *perfectly* with the failing
set, and a fix aimed at either would have looked right for the wrong reason. The
discriminator that actually explains it is whether a scene reads `the memberNum of
sprite`:

| scene | reads `the memberNum of sprite`? | moved |
|---|---|---|
| `COMEIN.dir` `return5` — `hatkeys` | **no**, gates on `sprite(N).visible` | yes |
| `hatul1.dir` — `hatulidown`/`hatuliup` | **yes**, against 2, 18, 29, 40 | no |
| `fritz1.dir` — member 10 `on exitFrame` | **yes**, against 18, 46 | no |

And it explains "**at all**" rather than "erratically", which was the shape that
kept the keyboard hypotheses alive: at 131,075 both `< 29` and `> 18` are wrong at
once, so no branch moves him and no branch restores him. Kick and jump read
`the keyCode = 49` in `foedecide`, bypassing the member gate entirely — which is
exactly the player's "S and space work, arrows do not".

Fixed by routing `read`'s override answer through `_merge_one`, which already owns
the split, rather than unpacking a second time here. Two places agreeing by both
saying the same thing is the shape this file's own comments keep warning about.

Blast radius, measured — `set the member/memberNum/castNum of sprite` writes
against `the memberNum/castNum of sprite` reads:

```
piposh-dream  1750 writes  1373 reads
rating         536         671
piposh2         50          78
piposh/-en/-ru   5 each      7 each
total         2351        2143
```

Negative control, whole files swapped and hashed:

```
channel.gd 3f9a8d17 (HEAD)   FAIL  wrote member(1, 3) -> memberNum 262145, wanted 1   rc=1
channel.gd 29554372 (fixed)  ok    wrote member(1, 3) -> memberNum 1                  rc=0
```

Covered by `tools/member_ref_round_trip.gd`, already in `ALL`, **3 → 6 checks**, so
the entry count did not move. Everything it asserted before passed `{}` for the
overrides — the score path only, structurally unable to see this.

**The new case's first version also passed against the bug**, and that is worth
recording: it wrote through `SpriteState.write_prop`, one seam *below* `ALIASES`, so
`"member"` was stored under a key the `membernum` read never looks at. It now goes
through `SpriteProps`, the pair the Lingo host actually calls. That is the third
blind assertion found in one session, after this same harness's `{}` and
`key_polling`'s window-gated `_input` section (`85b06dd3`).

### Confirmed by the player; still not covered by a harness

**Both scenes were played after the fix and both move** — reported by the player who
filed the original "he doesn't move, at all". So the player-visible end is
*observed*, and this entry no longer rests on the gates alone.

**The harness gap is separate and remains open.** `hatul1.dir` never reached its
armed state headlessly: the installer is the frame script at frame **174**
(`stage1`), and two landings went past it, leaving `the keyDownScript` on `cutsnd`
so every press correctly did nothing — a dead screen indistinguishable from the
reported bug, which is the marker-jump trap in another costume. So what gates this
fix is `member_ref_round_trip`'s property-level check, not a played one. Closing
that wants a harness which lands before 174 and **waits on `key_up_compiled`
becoming non-empty** before pressing, probably entering from `mainmenu.dir` rather
than landing at all. Worth keeping distinct: the *bug* is confirmed fixed by
observation, the *regression risk* is covered only at the property level.

`hatul3.dir` — the platformer's third screen — was reported as having problems in
the same play session, suspected by the player to be original-game behaviour. That
is **not established** and is a separate question from this entry; `bugs.md` is where
it belongs once somebody has a symptom and a frame number, and "not a bug" needs
more evidence than a bug does.

Two of the investigation's own instruments produced fabricated results before being
caught by hashing, and both are worth avoiding by name: `git stash -q push --
<path>` is not valid in this git and silently left an A/B pair identical, and an
`EXIT` trap running `git checkout HEAD -- channel.gd` destroyed the fix mid-session
so several "with the fix" runs were really at HEAD. Whole-file `cp` aside and back,
verified with `shasum`, is the only method this entry would trust.

---

## 106. `tools/preview_surface.gd` matched `p.call(` inside any identifier, so a harness with a local named `interp` turned the safety net red about a method that was never on the node

**Status:** FIXED · **Area:** `tools/preview_surface.gd:_method_names`,
`_receiver_starts_here` · found while diagnosing 105, by two agents disagreeing
about a red

The tool derives its method list by scraping every `.gd` under `tools/` rather
than maintaining a copy, and it matched by plain substring over
`RECEIVERS := ["preview", "p", "node", "w"]`. So `p` matched inside `interp`,
`temp` and `heap`, and `node` and `w` matched the tails of other identifiers —
`w` matches inside `preview` itself. A scratch harness holding
`interp.call("call_in_script", …)` reported `call_in_script`, which lives on
`lingo/lingo_interpreter.gd` and has never been on the preview node.

**Fixed by requiring a word boundary before the receiver**, in a new
`_receiver_starts_here`: a match counts only at the start of a line or where the
preceding character is not `[A-Za-z0-9_]`. A rejected match advances one
character rather than past the string literal, so a real receiver later on the
same line is still found. `RECEIVERS` is untouched.

**Leading underscores are boundary, not name**, and this is the half that a
literal reading of the filed fix would have got wrong. `tools/update_stage.gd`
and `tools/lingo_movie_surface.gd` hold the preview in `_preview`, and a strict
boundary drops `_paint` and `_field_key` — which are scraped from nowhere else,
so the gate would have gone quietly blind to two methods while looking greener.
Measured by replaying both matching rules over `tools/*.gd` outside the engine:
73 names at HEAD, 71 under a strict boundary, 73 under the shipped one, with an
empty diff against HEAD in both directions.

Evidence, one entry, four runs:

```
clean tree            preview_surface  PASS   rc=0
+ tools/_scratch_106_probe.gd
                      preview_surface  FAIL   rc=1
                      FAIL  no method name has moved  (no_such_method_xyz)
+ fix                 preview_surface  PASS   rc=0
- probe               preview_surface  PASS   rc=0
```

The probe was one line, `interp.call("no_such_method_xyz")` behind a null guard,
and the baseline run is what makes the red attributable to it.

**Four green runs would also be what a scrape returning nothing looks like**, so
they are not on their own evidence that the boundary accepts anything:
`h.check("no method name has moved", absent.is_empty(), …)` passes vacuously on an
empty list, which is this file's own "a check whose two readings cannot disagree"
shape. The positive control is a fifth run, one probe with three call sites at
three boundary classes:

```
interp.call(   identifier tail       not scraped
preview.call(  bare, after `(`       scraped
_preview.call( leading underscore    scraped

FAIL  no method name has moved  (no_such_method_abc, no_such_method_und)
```

Two names and not three, and the missing one is `interp`'s. That is the shipped
GDScript exercising all three branches, rather than a Python model of it.

The second scrape block has the same unbounded flaw and is a no-op today:
`line.find("preview.")` over `scenes/preview_lingo_host.gd` matches inside
`director_preview.` too, but every such hit is in a comment and none of them clear
the `lingo_`/`stage_` prefix filter that follows. Left alone rather than fixed
blind.

**The first draft of the fix failed the gate about its own comment.** The new
docstring spelled the needles out in full, so the scrape read them out of this
very file and reported two method names made of comment fragments. The needles
are written without their opening quote there now. `gate.sh`'s header records the
same shape one layer up, where `grep -o 'ALL="…"'` matched its own occurrence in
a comment; a tool that reads the tree it lives in is inside its own input.

**Two of the three things the entry proposed were deliberately not done.**
Dropping the one-letter receivers `p` and `w` was out of scope for this change —
`RECEIVERS` was to be left as filed — and the boundary makes them safe rather
than merely narrow. The in-harness fixture check (a line containing
`interp.call(` that must not be scraped) is **not** built: the regression is
guarded by nothing but this entry, and anyone who wants it has the probe above
written out in full.

---

## 90. `soundBusy` is paced by the audio device and not by the sound, so every speech wait in the corpus stretches by whatever the device is slow by

**Status:** FIXED in `02844f93` (the ceiling) and `a9081c79` (the replay guard the ceiling broke) · **Area:** `autoload/audio_director.gd`

`sound_busy` is one line — `return player.playing` — and `playing` is retired by
the **audio server**, when its mix thread has consumed the stream. So the flag
measures the output device's throughput, not the sound's length. On hardware the
two are the same number to within a fraction of a percent, which is why this can
sit unnoticed: it looks like an identity rather than like a choice.

They come apart where there is no hardware. Measured on one 0.63s file
(`fx/bang`), by `tools/sound_rate.gd`:

```
   Windows runner    <= 1.00x real time   (passes a 1.0x tolerance)
   developer Mac        1.12x             (0.71s for 0.63s)
   macOS runner         2.09x             (1.32s for 0.63s, over 67 polls)
```

A movie cannot observe this as a sound that is slow, because it never asks how
long a sound is. It asks `soundBusy`, and this corpus's speech is built on
`BehaviorScript 250`'s shape:

```lingo
on exitFrame
  if soundBusy(1) then go(marker(0))
end
```

The talking animation loops back to its own marker for as long as the channel is
busy. So a `soundBusy` that runs at half speed does not make the speech slow — it
makes the **playhead** loop twice as many times, and the player watches a mouth
move for twice as long as the line it is speaking. Every frame budget downstream
of a speech wait is wrong by the same factor.

This is what `puppet_persists` had been failing on, on every macOS runner, while
passing on Windows and on a developer Mac. `exitforest3`'s `dnzclicktalk` returns
in 295 score ticks here and needs more than 400 there; with `--ticks 700` the
macOS runner passes. The harness was right and its budget was right: the two
machines' score-tick *rate* is identical (7.7/sec vs 7.8/sec), and the clip's
pacing per marker jump is 14 ticks on both. What differs is how many jumps the
wait takes — 27 markers in 400 ticks and still inside the clip, against 19 in the
295 it takes here.

Three things this was mistaken for first, each measured and none of them it:

- **a wall-clock guard.** The watch's `--watch-ms` was blamed and doubled; the
  failing run spent 52s of 480,000ms.
- **machine speed.** Score ticks are tempo-gated, so the rate is the same on any
  machine. The engine's *frame* rate is not the same — 11.3 process frames per
  score tick on the runner against 23.7 here — but nothing in the clip is paced
  by frames, and the `idle` tally that shows it is a red herring.
- **a missing audio device.** `--audio-driver Dummy` on the runner fails too, and
  Dummy passes here, so the driver is not the variable. The runner is slow with
  both.

The audio index is identical on both machines — 3142 files, 315 ambiguous tails —
so this is not a data gap and not a case-sensitivity difference in path
resolution.

`tools/sound_wait.gd` cannot catch it and is not wrong for that: it asserts that a
channel is busy if and only if a sound the script asked for is playing on it,
which is the *logic* of `soundBusy` and is correct on every machine. The clock is
a separate rule, and `tools/sound_rate.gd` is what asserts it.

The fix is a ceiling rather than a replacement: record the stream's own length
when `_start` plays it, and answer `player.playing and now < that`. Nothing
changes where the device is honest; a device that lags can no longer hold a
movie. Two details make it cheap here — nothing in this engine's audio path loops
a stream or touches `stream_paused`, and `_start` is the single funnel both
`play_file` and `play_stream` go through. `take_cues_passed` reads
`get_playback_position`, so on a slow device it would still lag behind a
wall-clock `soundBusy`; no script in the corpus names a cue point, so that is
recorded rather than solved.

Reproduce:

```
godot --headless --path . --script tools/sound_rate.gd -- --tolerance 1.0
gh workflow run nightly.yml --ref main \
    -f entries='sound_rate:--tolerance@1.0 puppet_persists:--label@exitforest3'
```

**Closed.** `sound_busy` is now `player.playing` **and** `now < _channel_until`,
the ceiling being the stream's own length recorded at `_start`. It is an `and`
and not an `or` on purpose: the ceiling can only ever end a wait *early*, never
extend one, so a `stop`, a replacement sound, or a channel that genuinely
finished before its stated length are all still answered by `playing` alone. The
only case the new arm decides is the one the flag gets wrong.

`sound_rate --tolerance 1.0` measures 0.96x, 90 polls, 0.61 s for a 0.63 s file,
and `puppet_persists` -- the entry this was red on -- passes.

**And fixing it broke something else, which is the part worth remembering.**
`play_file`'s "it is already playing, leave it alone" guard still asked
`player.playing` alone, so the two guards stopped agreeing the moment the ceiling
existed. Where they disagree a channel goes silent for the rest of the movie:
free to the movie, already-playing to the guard, so the replay is skipped,
`_start` never runs, the ceiling is never re-armed, and `soundBusy` answers false
for ever. Magic Hat then busy-waits three seconds and raises
`alert("Sound file X is missing !")` for a file that is present, with
`lingo_alert` pausing the movie behind it -- a hang and a lie about the player's
install, from a fix to a timing flag. `tools/sound_replay_guard.gd` is the entry
that exists so the two guards can never drift apart again.

The cue-point caveat above stands and is still unsolved: `is_past_cue_point` is
paced by `get_playback_position` and would still lag on a slow device. No script
in the corpus names a cue point.

---

# The 2026-08-14 second sweep

Ten entries resolved in one pass by four agents working disjoint file sets, plus
one new bug found twice from opposite directions and fixed. Three of the ten are
**not bugs**, and each says what the evidence was rather than that somebody looked
again.

The pattern worth carrying forward: **five of the ten were instruments lying, not
engines misbehaving.** 105 was a tool reporting a cold score as a live one; 110
was one bucket holding "this member type has no renderer" and "the artwork failed
to decode"; 112 does not reproduce at all; 113 was a probe asking a mouse-polled
movie for hotspots; 114 was a survey resolving a member reference against every
cast library instead of the one its record names. `porting-fidelity-verification`
says to distrust the harness before the code, and this sweep is the strongest
evidence for that rule the project has produced.

The entries below are kept as they were written, because what was believed at the
time is the record. The verdicts are here:

| # | Verdict | What settled it |
|---|---|---|
| 105 | **Fixed** | `tools/hotspots.gd` takes `--do`, plays in with the movie's own `go`, prints how it reached the frame on **every** run, and fails a check when a `--do` step never fires. `--at` and `--opaque` were added in the same pass and are what root-caused 108. |
| 107 | **Fixed** | `moveToFront`/`moveToBack` bound, with the stage in the window stack (Director §14). `tools/window_order.gd` drives two real windows through compiled Lingo: 25 checks, 12 fail with the binding removed. |
| 108 | **Fixed, and the entry's premise was wrong** | Channel 94 *is* eligible. The descent walks past it because its Matte artwork has no opaque pixel anywhere — because the artwork never decoded. `0 of 1950 sampled points opaque, texture: NONE`. That is 116 below. |
| 109 | **Fixed, and it is not 116** | An `MCsL` library's *name* and its *file path* need not agree. `meet5.dir` links `psyco2.cst` under the name `psyco` (and `chor2.cst` as `chor`), and two separate copies of the resolver matched the `ccl` stem against names only. One copy now, `DirectorCastTable.lib_for_cast_entry`: path, then resolved path, then name, exact stem equality. `psyco`'s path is non-empty, so 116's embedded arm was never involved. |
| 110 | **Not a bug, and the report was the bug** | All eight are `vectorShape` Xtras — Director 7 vector art that neither this port nor the reference draws, correctly. `"child has no art"` was one bucket holding an undrawable member type and a decode failure. `sprite_art.gd:decline_reason` splits them; `tools/film_loop_children.gd` holds the painter to a census derived off the cast. |
| 111 | **Fixed at the source and at the symptom** | `--root <name>` now takes its boot movie from `[root.<name>] boot`, the mapping the launcher already read. And `lingo_go_movie` refuses a null `_movie` instead of dereferencing it — the raw `Invalid access to property 'path'` was a sentence about GDScript that sent two sessions after five Rating minigames that were not broken. |
| 112 | **Does not reproduce** | Four runs of the exact gate entry: 0 occurrences, 49-line log. 0 again with `_key_overlay` deliberately left armed through `quit()`. No speculative guard was added for a symptom that cannot be produced; if it returns, the platform needs recording. |
| 113 | **Not a bug. The chess board works.** | `ches1` has no hotspots *by construction* — `BehaviorScript 81` is `if the mouseDown then go(marker(1)) else go(marker(0))` with channel 8 cycling seven members. It is a slot machine, polled, not clicked. Driven with `--await ches1 --poll-mouse` it sets `ches1 = suz` and `ches2 = pat` and runs on to `talkonches1`/`choosemore`. The 0-of-900 was the instrument asking a mouse-polled movie for hotspots. |
| 114 | **Not a bug. Reading 3.** | `sound_survey` resolved every 16-bit slot against *every* cast library and preferred any `sound` answer. The port never does that — the main channel is six 48-byte records with `castLib` at +0 and member at +2. In the declared library all 29 frames resolve to `script`. The assertion was made **stronger**, not relaxed, and is now controlled by perturbing `director_score.gd`'s own offsets. |
| 115 | **Fixed** | `tools/sound_tempo_wait.gd` finds a real 255/254 cell (276 in 48 of `rating`'s containers, matching the filed figure), lands on it, plays a real sound into it, and asserts the hold and the release — with the control that a **silent** channel does not hold the same frame. |

---

## 116. A cast library embedded in the movie's own container can hand out no payload at all

**Status:** FIXED · **Area:** `director/director_cast_table.gd:file_for` · found
2026-08-14 by two agents from opposite directions, and never open for a day

`MCsL` may name a library with an **empty path** — a second cast living inside
this `.dir`. `_cast_for` opens it correctly, matching its `castID` against the
`KEY*` owner of each `CAS*`, and sets `resolved_path` to the movie's own file.
`file_for` then resolved through `_by_path`, and `_by_path` is only ever written
by the *external* `.cst` arm — so the lookup missed and the function fell through
to `return _movie if cast_lib == 1 else null`.

Every payload in the engine is fetched through `file_for`: `sprite_art.gd:89` for
a bitmap's `BITD`, `palette_view.gd:80` for a `CLUT`, `film_loop_view.gd:66` for a
loop's `SCVW`, `preview/sound.gd` and `preview/media.gd` for samples,
`member_payload_size` for `the size of member`. **Each has a quiet
`if f == null: return null` beside it**, so a member of an embedded library
resolves, reports its name and type and rect, and draws or plays nothing.

Measured over all eight roots: **18 libraries, 969 members with a payload chunk,
all 969 unreadable.** Not a test-corpus problem — `GATE_ROOT`'s own
`piposh2 PIP2DATA/GARDUG.dir` lib 2 `heznigt` hid 294, `piposh PIPDATA/ENDDAYS.dir`
lib 2 `master` 43, `piposh-dream dinner2.dir` lib 13 `Hafaka` 23,
`itamar-magichat hats.dir` libs 2/3/5 (81 + 39 + 25, the last of them sound),
`itamar-park torfim.dir` lib 3 `Panel` 92.

**Found twice, independently, neither agent looking for it.** One was chasing
Magic Hat's "48 sound chunks no cast walk addresses" — which turned out to be 48
the walk addresses perfectly and cannot read the bytes of. The other was chasing
Itamar Park's dead book hotspot, which is member 3:1 of exactly such a library.

Fixed by answering `_movie` for a library whose declared path is empty, before
the `_by_path` lookup. **Returned rather than registered**: `close()` closes every
file in `_by_path`, and the movie's container belongs to the caller, so
registering it would close the movie out from under the preview. The dead
`cast_lib == 1` tail is now `return null` — an external cast that did not resolve
must not be handed the movie's container, which holds none of the chunks asked
for.

`tools/embedded_cast_payload.gd` is the harness and went into `ALL` in the same
commit as the fix, never before it: a standing red teaches everyone to read past
reds. `18 of 18 answer null, hiding 969 member payload(s)` → `0 of 18`.

## 105. `tools/hotspots.gd` reports the score's members on a frame only the movie's init reaches, and says nothing about it

**Status:** OPEN · **Area:** `tools/hotspots.gd` · found while diagnosing the hex
board, after the tool's false reading had already cost a session

The tool `_advance`s from frame 0 and pins `_index`, and it warns only when it
**fails** to arrive. On `piposh-dream/hex1.dir` frame 216 it arrives, prints no
caveat, and reports all 58 board channels as `1:56` /
`no behaviour, member script declares none  [1:104 unresolved]`, concluding
"4 of 71 sprites can answer a click". Played into the same board, six of those
channels hold members 2 and 3 and three are eligible through
`member script declares mouseDown/mouseUp`:

```
cold:  36    1:56   (278,412) 77x43   8  pixel  no   no behaviour, member script declares none  [1:104 unresolved]
live:  ch36  score 1:56  live 1:3  (284,412) 65x42  why='member script declares mouseDown/mouseUp'
```

So **the instrument said the board was dead about a board with three clickable
pieces on it**, and that reading was the starting point for the absorption
hypothesis and four wrong turns in one session — after `tools/hotspots.gd` had
already, correctly, been cited as the authority on the `eat.dir` question that
became `docs/bugs-closed.md` 101. A tool that is right about a cold score and
silent about the difference is worse than one that refuses, because its output is
quoted as the state of the frame.

`_effective` **is** applied per sprite, so this is not the score-versus-effective
split fixed in `interaction.gd:script_for_click`. It is that arriving at a frame
through `_advance` is not the same as reaching it by playing: the init that swaps
member 56 for member 3 on 58 channels never ran.

Reproduce, and compare the two:

```
godot --headless --path . --script tools/hotspots.gd -- --root piposh-dream --file hex1.dir --frame 216
godot --headless --path . --script tools/cast_script_sprite.gd -- --root piposh-dream
```

Minimum honest fix: print the caveat whenever the walk cannot show that the
frame's own initialisers ran, not only when the playhead stops short. The wider
version is a `--play` mode, which `tools/puppet_members.gd` already has and which
is what made the difference visible here.

**Measured and explicitly not a bug, so nobody re-opens it:** the 58 tiles each
carry sprite behaviour `1:104`, a script member named `spriteClicked` with
`script_id = 0`, `data_chunk_id = -1`, no source and no `Lscr` chunk — empty in
the container, identically in all three hex movies. The tiles are therefore
correctly not click targets in their unlit state, and
`behaviour_scripts`'s decision to drop unresolved attachments is right here.
`e1ca332b`'s sourceless-script census is **not** contradicted: it counted
`script_id != 0`, and this member is 0, so it was never in that population.

---

## 107. `moveToFront` and `moveToBack` are unbound, so a title with two windows cannot order them

**Status:** OPEN · **Area:** `scenes/preview_lingo_host.gd`, `scenes/preview/windows.gd`

`docs/LINGO_SURFACE.md` §7.4 lists both among the window methods. Nothing binds
either. Every Itamar Park boot prints them in `builtins unbound`:

```
builtins unbound : {"movetofront":2, ...}
```

Park calls `moveToFront` four times and `moveToBack` twice.

**Currently masked, and that is the reason to file it rather than to shrug.**
`windows.gd` parents a window above the stage unconditionally, so the one
arrangement Park asks for is the one it already gets. A title that opens *two*
windows has no way to say which is in front, and the symptom then is not an error
but a window drawn behind the one it was raised over — which reads as a drawing
bug and is a binding that was never written.

Reproduce:

```
godot --headless --audio-driver Dummy --path . --script tools/scratch/deepplay.gd -- --root res://test-games/itamar-park --file torfim/torfim.dir --settle 12
```

---

## 108. Itamar Park's study section is unreachable: the book hotspot is drawn, visible and answers no click

**Status:** OPEN · **Area:** `scenes/preview/interaction.gd` or the hit test

Channel 94 at `AntPlay` holds `bookpas-NRM`, member 3:1, rect (266,416) 50x39.
It draws, it is visible, and three separate points inside it all resolve to
channel 0:

```
godot --headless --audio-driver Dummy --path . --script tools/scratch/deepplay.gd -- \
  --root res://test-games/itamar-park --file torfim/torfim.dir --settle 12 --steps 560 \
  --do "play+10=ch11;Ant+30=code:49;AntPlay+50=xy:280,430"
# clicked (280,430) frame 24  ch0  frame script BehaviorScript 24 - play frame  mouseUp:NO HANDLER
```

**The discriminator is that its neighbours work.** Channels 71 (telephone) and 72
(ball) are hotspots on the same frame, behind the same `frameLabel contains
"play"` guard, and both resolve correctly in the same run — 71 reaches `AntTele`
and 72 reaches `AntLevels`. So this is not the guard, and not the frame: it is
the hit test or the eligibility rule, for one channel that differs from its
neighbours in some way nobody has named yet.

Everything behind it is unreachable — `AntStudy` and the whole of `study/`.

**What the next session needs first is an instrument, not a hypothesis.**
`tools/hotspots.gd` is what would say whether channel 94 is eligible at all, and
it cannot reach `AntPlay`: getting there needs the space key, because
`BehaviorScript 23` holds the world-explanation frame with `play frame the frame`
until its own `on keyDown` matches keyCode 123-126 or 49. A mouse-only walk sits
there for ever — measured at 596 ticks with every later step unfired. Either
`hotspots.gd` gains a way to press a key on the way in, or this is answered by
`deepplay.gd` alone, which is a driver and not an instrument.

---

## 109. `film_loop_cast` is red on `piposh-dream`, and the gate only ever runs it pinned to `piposh2`

**Status:** OPEN · **Area:** `director/director_film_loop.gd`, `gate.sh`

2 of 4 checks fail. `meet5.dir Internal:37`, children 89-93: *wants `psyco(2)`,
resolved `Internal(1)`*, plus one `ccl` entry naming no library.

```
godot --headless --path . --script tools/film_loop_cast.gd -- --root piposh-dream --verbose
```

`ALL` carries `film_loop_cast` bare, which is `GATE_ROOT` — `piposh2`, where it
passes. `film_loop_restart`, `film_loop_nesting` and `cast_script_sprite` are all
already pinned to `piposh-dream` for exactly this reason, so the pattern for
fixing the coverage half is established and beside it. **Both halves are the
entry**: the resolution bug, and a suite that could not see it.

---

## 110. `plane1.dir`: 8 of 37 film-loop children draw nothing, and it is not the closed nested-loop cause

**Status:** OPEN · **Area:** `scenes/preview/film_loop_view.gd` or `director/director_film_loop.gd`

Reproduced in two independent runs of `tools/minigame_probe.gd`:

```
{"child drawn":29,"child has no art":8,"children offered":37}
```

The flyer plays — it initialises `vertnum`, `horznum`, `hellfire` and `borderx`
and its HUD fields update — so this is art and not logic. It is the **only**
movie in the minigame corpus with a non-zero miss, which is what makes it worth a
number rather than a sweep.

**Explicitly not the Hatuli projectile bug.** `plane1.dir` is not one of the ten
nested-loop sites `docs/bugs-closed.md` enumerates, so whatever this is, it is a
second cause and closing it against that entry would be wrong.

---

## 111. `--root <name>` alone raises a raw Nil error on `rating` instead of refusing

**Status:** OPEN · **Area:** `scenes/director_preview.gd:860`, `lingo_go_movie`

`--root rating` without `--boot` leaves the boot movie coming from the config
(`strtgame.dir`, which is not rating's), the preview holds no movie, and the next
`go to movie` raises:

```
Invalid access to property 'path' on a base object of type 'Nil'
```

Five of rating's minigames read as `no-open` through that route and **none of
them is broken** — `--boot MAINMENU.dir` reaches all five. So the cost is not the
five, it is that a tool reports "cannot open" for a configuration error and a
session spends its time on the wrong question.

Two things are wrong and only one of them is this entry's: rating needs its own
boot movie named, which is documentation; and `lingo_go_movie` dereferences a
null movie rather than refusing with a sentence, which is the engine. A `go to
movie` with no movie loaded is a state the engine can be in, and it should say so.

---

## 112. A roulette teardown prints ~1,200 `Nonexistent function 'draw'` lines after the run has passed

**Status:** OPEN · **Area:** `scenes/preview/sprite_art.gd`, `film_loop_view.gd`, via `StagePaint.paint_frame`

Seen at the end of `key_overlay:--root@piposh@--boot@PIPDATA/ROULLETE.dir`,
*after* it prints PASS. The reported site is `scenes/director_preview.gd:2002`,
which is `StagePaint.paint_frame` — reached through `SpriteArt.draw` /
`FilmLoopView.draw` while the tree is being torn down and the callee is already
freed.

Harmless to the assertion and not harmless to the suite: 1,200 lines of engine
error after a green verdict is how a real error stops being read. It is a
teardown ordering fault — the painter runs one more time on a frame whose
children have gone — rather than anything about roulette.

---

## 113. Piposh 2's chess board is reached and offers no click in 900 ticks, and nobody has separated "dead" from "the intro had not finished"

**Status:** OPEN · **Area:** unknown; needs an instrument before a diagnosis

`ches1` frames 138-144 draw the board — 16 pieces, 5 of 17 channels swapping
member — and across 900 ticks **0 offered a hotspot** (`tools/minigame_probe.gd`).
Piposh Dream's `hex1` is the same shape from the other side: its intro cycles to
frame 148 and the board is at 216, so 900 ticks never arrived at all.

**Both are measured at a tick budget, and a tick budget cannot tell a dead board
from a long intro.** `bugs.md` 105 already records that the hex board *does* have
three eligible tiles when it is played into properly, which is the reason to
distrust the chess reading rather than to file it as a fault.

What is missing is a probe that waits on a **marker** rather than on a tick
count. That is the entry: until it exists neither of these is diagnosable, and
both will keep being re-reported.

---

## 114. The frame-script slot resolves to a *sound* member in 29 frames of the two recovered corpora, and nobody has separated the three things that could mean

**Status:** OPEN · **Area:** `director/director_score.gd` main-channel decode, or `tools/sound_survey.gd`'s resolution · found 2026-08-14, the first time that harness was pointed at `test-games/`

`tools/sound_survey.gd` asserts that **no slot the port reads as a member
reference resolves to a sound member**, because a hit there would mean an offset
is wrong. It has passed on `piposh2` and `piposh` since it was written. Pointed
at the two recovered corpora it fails on both, at the same offset:

```
godot --headless --audio-driver Dummy --path . --script tools/sound_survey.gd -- --root res://test-games/itamar-magichat --all
godot --headless --audio-driver Dummy --path . --script tools/sound_survey.gd -- --root res://test-games/itamar-park --all
```

```
itamar-magichat  FAIL  and no slot the port reads as a member reference names a sound  (offset 2 in 16 frame(s))
itamar-park      FAIL  and no slot the port reads as a member reference names a sound  (offset 2 in 13 frame(s))
```

Offsets 2-3 are the **frame script member** (`KNOWN` in that tool, and
`MEMBER_REFERENCE_SLOTS`). Both corpora have the sound members to collide with —
39 reachable in Magic Hat, 66 in Park — and neither had ever been surveyed,
because a bare `--root <name>` resolves under `games/` and nobody had passed the
whole path.

**Three readings, and this entry exists because no evidence yet separates them:**

1. **The decode is wrong for these movies** and offset 2 is not the frame script
   member here — in which case every frame script in both titles is being read
   from the wrong bytes, and the symptom would be frame scripts silently not
   running rather than anything visible.
2. **The value is right and names a sound**, so the port resolves a frame script
   to a sound member and dispatches nothing. Silent, and indistinguishable from a
   frame with no script.
3. **The tool is over-sensitive.** It resolves each slot *against every cast
   library*, so a hit only proves that some library has a sound at that number.
   A frame script naming script member 12 in library 1 would report a hit if
   library 3 happens to hold a sound at 12.

Reading 3 is the cheapest to test and should go first: resolve the slot in the
frame's **own** library only and see whether the failures survive. If they do,
the discriminator between 1 and 2 is whether those 29 frames have a frame script
that runs — `tools/primary_scripts.gd` and the `lingo:` runtime errors say so
directly.

**Do not close this by relaxing the assertion.** It is the only check in the
suite that would catch a main-channel offset being wrong in the direction that
yields *more* member reference than there is, and it fired the first time it was
shown data it had not seen. That is the check working.

---

## 115. Rating has 276 real wait-for-sound tempo cells and every harness that exercises one uses synthesised bytes

**Status:** OPEN · **Area:** `gate.sh` coverage, `tools/frame_events.gd` · **not a defect in the engine** — the path is implemented and wired

A tempo cell of 255 or 254 holds the playhead until sound channel 1 or 2 is
finished. `director_score.gd:tempo_waits` decodes it,
`director_frame_clock.gd:_arm_waits` sets `_waiting_sound` from it, and
`holding()` counts it. So the feature is built.

**What is not built is a single test that drives one out of a real movie.**
`tools/frame_events.gd:366` synthesises the cell —
`mixed.enter_frame({"tempo": 255, "tempo_cue": -1})` — and `movie_tempo.gd`
tests the *decode* of 255 in isolation. `tools/sound_wait.gd` does not mention
tempo at all. Every one of those was written against `GATE_ROOT`, and `piposh2`
has **zero** such frames in its 61,371.

`rating` has **276**: tempo 255 in 259 frames and tempo 254 in 17
(`tools/sound_survey.gd --root rating --all`). `piposh`, `piposh-en`,
`piposh-ru` and `piposh-dream` have none, so `rating` is the only corpus that
can exercise this and it is not in any entry that would.

This matters more than a coverage number because **those 276 frames just changed
timing.** `docs/bugs-closed.md` 90 gave `soundBusy` a ceiling and `a9081c79`
fixed the replay guard that ceiling broke; both move when a sound is considered
finished, and a wait-for-sound tempo cell is the score-side consumer of exactly
that question. Nothing asserted the frame-level path before or after.

What the entry needs is a harness that plays a `rating` movie into one of those
frames and asserts the playhead is held until the sound ends and then released —
the same shape `pause_holds` has for a click. Adding `sound_wait:--root rating`
is **not** it: that harness tests `soundBusy`'s logic and never reads a tempo
cell, so it would pass having asserted nothing about this, which is the dark
harness `gate.sh` warns about.

Found by pointing `sound_survey` at every root instead of the configured one.
That tool used to *assert* "no frame's tempo cell is a wait-for-sound", so it
answered FAIL to the news that a title uses the feature; it prints the count as a
finding now.
---

## 117. On a machine with a screen, a transition composes the wrong two pictures

**Status:** OPEN · **Area:** `scenes/director_preview.gd:_grab_stage`, the
framebuffer arm · found 2026-08-14 while building the offscreen surface, and
**predates it** — the surface is only what made it visible

Headless is unaffected: `35e9cac5` gave the painter a CPU rasteriser and
`_grab_stage` reads the last completed paint off it, already in Director's
pixels. A build **with a screen** still takes the other arm, reading the frame
back out of the framebuffer and cropping it to the stage — and the crop is wrong.

The same frame captured both ways: the surface is the whole frame (room,
television, three lines of Hebrew, HUD); the framebuffer answer is the
**top-left corner of the stage with the letterbox still in it**, magnified to
640x480. Mean channel drift 107 of 255, blurred to about 64x48 of real detail.
Not a settling artifact — 200 awaited frames give the same picture as 30.

**The arithmetic is not what is wrong.** `get_global_transform_with_canvas()`
answers `scale 1.5646, origin (139,0)` and the crop follows it faithfully. The
drawing is not at that scale: 1001x751 is far short of the 2880x1690 window. So
the node's transform and the transform the frame was actually rendered with
disagree, and the crop is derived from the wrong one of the two.

Every transition on a desktop has therefore been blending two wrong pictures for
as long as transitions have drawn. Nobody saw it because until `35e9cac5` they
did not draw at all.

Reported by `tools/transition_render.gd`'s `_two_backends_agree` case, which is
**green in the gate** (headless says it needs a screen and asserts nothing) and
**red on a by-hand desktop run**, with the cause in the failure message so nobody
closes it by loosening the threshold:

```
godot --path . --script tools/transition_render.gd -- --root rating --boot EGOZROO1.dir
```

Two ways out, and the choice is not obvious:

1. **Find why the transforms disagree** and fix the crop. Cheapest if the cause
   is a stale transform on the node, which is what the numbers suggest.
2. **Make the surface the source on every display server**, deleting the
   framebuffer arm. Correct by construction and removes a whole class of
   divergence, at a measured **+13.8 ms per paint** on the most text-heavy frame
   in the corpus. These are 4-15 fps movies, so that is affordable — but it is a
   real cost paid on every machine to fix a bug on one path, and it should be a
   decision rather than a default.
**Resolved 2026-08-14 — the diagnosis, not the fallback. The framebuffer arm
stays and costs nothing.**

`get_global_transform_with_canvas()` was never stale and the node was on no stray
canvas layer. It is **one transform short of the framebuffer by definition**.
`project.godot` sets `window/stretch/mode="canvas_items"`, which splits a
viewport's render target from its 2D coordinate space and puts a stretch
transform between them, applied by the renderer. That function is
`viewport canvas transform * global transform` and nothing else, so it answers in
the pre-stretch space; `Snapshot.grab` reads the render target.

Measured on 4.7.1 on Windows, `rating`/`EGOZROO1.dir`, maximised: the render
target and window are 2880x1690 while `get_visible_rect()` is 1280x751.
`2880/1280 = 2.25` and `1690/751 = 2.250333` — that ratio is the stretch, the
viewport carries it as `get_final_transform()`, and it was missing from the crop.
So the crop was `(139, 0, 1001, 751)` of a 2880x1690 image, the top-left ninth.
Through the stretch it is `(312, 0, 2252, 1690)`. `CanvasItem.get_screen_transform()`
is **not** the answer and was tried: it returns exactly
`get_global_transform_with_canvas()`.

`_two_backends_agree` on a by-hand desktop run: mean channel drift
**106.9/255 → 0.2/255**, 67,027 → 580 of 76,800 samples differing exactly. The
residue is the `INTERPOLATE_NEAREST` downscale and three approximated text
primitives, which that case was always going to carry.

**The knowledge already existed in `tools/` and had never crossed into the
engine.** `hilite.gd:_to_screen` composes exactly this pair and its own comment
calls the stretch "the half that is easy to leave out"; `mouse_events.gd`,
`sprite_drag.gd`, `touch_input.gd` and `editable_text.gd` compose it too, and
`stage_clip.gd` derives the same factor from image size over visible rect. Six
harnesses had it. The one place in the engine that paints did not.

`stage_paint.gd:framebuffer_region` is now the single copy, identity where there
is no stretch — so headless, a base-resolution window and `stretch=disabled` get
the old rectangle byte for byte. Guarded on both sides:
`transition_render.gd:_crop_follows_the_stretch` asks the transform question
**headless**, through a `SubViewport` with `size_2d_override_stretch`, so the gate
can see this defect without a screen; `_two_backends_agree` remains the
end-to-end statement for a desktop run. Reverted to the pre-fix arithmetic, the
headless case fails 3 checks.

---

# The 2026-08-14 re-verification pass

Eleven old entries re-checked against the engine as it stands. **Six close, two
close in part, three stay open**, and one of the closes *reverses* a "not a bug"
that was wrong — which is the direction this pass was most at risk of never
going.

Verdicts below; the entries follow, kept as written.

| # | Verdict | What settled it |
|---|---|---|
| 49 | **Closed with a number** | The whole entry was "nobody has measured where they disagree". Measured: **65,883,235 channel records** over 491 scores in all eight roots, **0 disagreements either way**. The type byte takes exactly two values — 16 on all 8,079,420 records naming a member, 0 on all 57,803,815 naming none — so the two tests are the *same partition* of this corpus, not merely compatible. `tools/channel_occupancy.gd`, now in `ALL`. |
| 100 | **Closed, and its stated conclusion was wrong** | "The original ends this minigame early too" is **false**. It was the instrument: `dockeys` is the only one of `COMEIN.dir`'s six handlers reading keyCode 125/126, and the harness drove every scene with 123/124 (`8e9a3a5d`). Re-run verbatim, the scene throws spears over 1,778 frames, 166 children drawn, and never reaches `y2`. The reference finding about `the visible of sprite N` stands; the conclusion drawn from it does not. |
| 70 | **Closed on two independent grounds** | A recursive byte search of `games/rating` for `mainmenu-old` — and for `-old` at all — returns nothing, so it is unreachable. And the observation itself was the instrument: `liveness_sweep --only MAINMENU-old.dir --click` reports 82 states over 120 ticks and ends drawing. It is not parked. |
| 88 | **Closed from outside the pipeline** | Recursive byte grep of the whole title: `getlng` occurs in one file, at its two call sites; `on getlng` / `on setlng` occurs in **no file**, including the subdirectories the original container walk never opened. `builtins unbound : {"getlng":1}` is accurate reporting of absent game data. |
| 48 | **Closed** | The reference chain re-read and still right; `puppet_persists --label exitforest3` green at 20 checks. |
| 38 | **Closed** | Nothing parks: `movie_churn --root piposh-en --window-off --steps 600` walks f0 → f1181 → f86 → f618 → f632 with 224 `rollOver` calls and a held tempo delay, and passes. The entry survived only because a player report is not a fixed bug — bookkeeping, not a measurement. |
| 36 | **Closed** | The `hatday` trap is *unreachable cut content*: the only script that enters the clip, `WONDER/External/BehaviorScript 645`, is **attached to nothing on any of 2,784 frames**, while its sibling members 639/640/642/643/644/646 all carry spans. `hotspots --marker tennis` agrees from the other side. And the cold route is one the original could not take — `globalday` is written in exactly five places in `reference/lingo/`, every one on the game's own path in, and a projector has no jump-into-a-movie affordance. **Left unmeasured and worth knowing**: the second family (`<room>talk` via `objecttalktime`/`talkproc`), whose three answer fields exist in `MASTER.CST` but whose tables were not read. |
| 25 | **Closed — the entry no longer describes the tree** | Every mechanism it names is gone. `goto_movie` does not exist anywhere in the repo; F6 is `step_forward` and Shift+F6 is `quick_load`, neither a warp; there is no save editor and no Apply; and `SaveState.restore` deliberately runs *after* `startMovie` and the frame entry, which is the opposite of the described defect. The F12 picker goes through `lingo_go_movie` and `MovieSession.adopt` sets `_index = 0`, so it enters at frame 1 with `init all` behind it. What survives is `--label` / `--frame` on the command line: a harness flag doing exactly what it says. |

**Staying open, with the re-check recorded so nobody repeats it:** 46 and 68 are
untouched by the sound-member work, because neither is about a sound *member* —
`piposh`'s 17 are all room effects and a piano key, and **`rating` has 0**, its
three missing sounds all being `sound playFile` of basenames still absent from
the tree. 83 loses two of its three claims (the `me` half and the dropped
`property` line are both closed and measured) and keeps only the
`initializerIndex` half, so it is retitled rather than closed.

## 49. The port's "is this channel occupied" test is not the reference's, and nobody has measured where they disagree

**Status:** open, **unmeasured** · **Area:** `director/director_score.gd:_snapshot`
· found while answering entry 48, not the cause of it

**Narrowed 2026-08-14 by 94's fix.** The size half of the divergence is gone:
`_snapshot`'s test is now `cast_id <= 0` alone, so "a record with a live sprite
type, a member and a zero rect" — the case that cost Itamar Park its arcade — is a
sprite here as it is in the reference. What is left is the one real disagreement,
and it is narrower and easier to survey than when this was filed: the port asks
about the **cast id** and `Channel::isEmpty()` asks about the **sprite-type byte**
at offset 0. The two still differ on a record with a type of 0 and a nonzero
member. The survey below is still unwritten.

The paragraph that follows is as filed, and its first sentence is now history:

`_snapshot` treats a channel as occupied when `cast_id > 0 and width > 0 and
height > 0`, with a comment recording why: hundreds of thousands of records carry
a sprite-type byte and no member.

The reference asks a different question. `Channel::isEmpty()` is
`_spriteType == kInactiveSprite` — offset 0 of the record, and *only* that byte —
and it is what the render loop tests (`Window`'s two `!channel->isEmpty()`
guards). A record with a live sprite type, a member and a zero rect is a sprite
there and is not one here; a record with a type of 0 and a nonzero member is the
reverse.

**Not the cause of entry 48**, and that is measured rather than assumed: at DAY1
2510-2520 the two channels in question read `type=0 0:0 0x0`, so both tests agree
that they are empty and the answer there does not turn on this.

It is worth measuring before it is worth changing, because the port's test was
chosen against the corpus and the reference's was not. The survey nobody has
written: across all six titles, count the records where the two disagree, split by
which way. A count near zero closes this; a large one in either direction means
some channel somewhere is drawn that should not be, or the reverse, and neither
would look like a decode bug from the player's chair.

---

## 100. Piposh Dream's `doc` minigame ends before it throws anything, because a hit registers on the first pass against a channel its own init never claimed

**Status:** **not an engine bug — concluded 2026-08-14 from the reference**, and
kept here for the same reason as 48 and 70: it will be re-reported by every future
`--play` of that movie. · **Area:** `COMEIN.dir` script `1:193` versus
`1:147`/`1:181` · found by `tools/puppet_members.gd --play doc`

**The question this entry refused to answer without the reference has an answer,
and it kills the engine reading.** In ScummVM `the visible of sprite N` reads
`channel->_visible` (`lingo/lingo-the.cpp:1809`), which is a `Channel` field set
`true` in the constructor (`channel.cpp:63`) and written in exactly two other
places: the copy constructor (`:99`) and the Lingo setter (`lingo-the.cpp:2135`).
**No score path touches it** — neither `setClean` nor `replaceFrom` writes
`_visible`. So Director answers TRUE for a channel the score placed and no script
puppeted, which is what this port answers. The two readings below collapse to one:
`1:193` omits the `puppetSprite(3, 1)` and `sprite(3).visible = 0` that its five
siblings carry, and the original ends this minigame early too.

**Do not close it by citing `bugs.md` 34.** This entry cites 34's "open half" and
that citation is doubly wrong: 34 was already fixed when this was filed (08-08,
five days before), and 34 argues only the **empty**-channel case while channel 3
here is *occupied*. Those are different arms of `Channel.read`. The reference above
is what settles the occupied case, and it is the evidence `AGENTS.md` wants before
a "not a bug" verdict stops work.

**What would reopen it:** a measurement that the *click* should never have reached
`return2` in the first place, or a Director projector run of `COMEIN.dir` showing
`doc` playing to its end. Neither has been done.

`COMEIN.dir` holds one minigame per character and five of the six play. `doc`
(`return2`, f295) is entered correctly — walked into, not jumped to; its init runs,
`puppetSprite` is reached 8 times and `keyUpScript:dockeys` fires — and then channels
27, 28 and 29 are **never dressed** with `187`/`188`/`189` over 20,000 process
frames. Nothing is ever thrown.

The playhead says why. It walks f293..f308 and jumps straight to **f315 `y2`**, which
is the branch `1:195` takes only on

```lingo
((sprite(27).visible = 1) or (sprite(3).visible = 1)) and (sprite(5).visible = 1)
```

Channel 27 was never dressed, so the term that read true is `sprite(3)`: a hit
registers at `plantcounter = 7` on the very first pass and the scene leaves for
`docend` before a spear exists.

**Two anomalies sit under it, both unique to `1:193` among the six inits**, which is
what makes it a lead rather than a coincidence. It omits the `puppetSprite(3, 1)`,
`puppetSprite(4, 1)` and `sprite(3).visible = 0` that `1:147` (hat) and `1:181` (poz)
all carry — while its own handlers go on to dress channels 3 and 4 exactly as theirs
do — and it is the only one of the six written `on enterFrame` rather than
`on exitFrame`.

**Not concluded, on the rule that "not a bug" needs more evidence than a bug does,
which cuts the same way in reverse.** Two readings are live: an authoring slip in a
1997 container, or this port answering `the visible of sprite 3` where Director
answered otherwise for a channel no `puppetSprite` claimed. The score does place
member 187 on channel 3 from f295, so the sprite is *there* — but a score record
carries no visible bit at all (visibility is `preview/channel.gd`'s runtime concept),
so the score cannot settle it. Settling it needs the reference: what Director returns
for `the visible of sprite N` on a channel the score placed and no script puppeted.
`bugs.md` 34's open half is the same question from the other end.

Reproduce:

```
godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --file COMEIN.dir --play doc
```

The survey's static half flags it mechanically without playing anything: `doc`'s line
reads `handlers also dress [3, 4], unclaimed`, uniquely among the six scenes. That
comparison of claimed-versus-dressed channels was added to keep a docstring honest
and surfaced this as a side effect, which is the argument for printing both numbers
rather than the one the tool was written for.

---

## 70. `MAINMENU-old.dir` parks blank at `option1`, and nothing in Rating can reach it

**Status:** not a bug, recorded so the next sweep does not chase it ·
**Area:** `games/rating/MAINMENU-old.dir`

`tools/qa_walk.gd --sweep` reports one stage that stays empty once transient
opening frames are excluded: `MAINMENU-old.dir` frame 651-652, inside marker
`option1`, nothing drawn and no hold to explain it, for as long as it is watched.

It is unreachable. Rating boots `MAINMENU.dir`; a byte search for the string
`mainmenu-old` over every `.dir` and `.cst` in `games/rating` -- the Lingo source
lives in the `CASt` records, so a `go to movie` naming it would be found -- has
**no hits**. Nothing navigates to this container, and `DirectorPaths.containers()`
only lists it because it is a file in the folder.

So it is authoring residue shipped beside the movie that replaced it, and its
dead region is not a state a player can be in.

**Why this is written down rather than dropped:** `AGENTS.md` requires more
evidence for "not a bug" than for a bug, because it is the verdict that stops
work -- and this one will be re-reported by every future `--sweep` of Rating.
Without the entry the next session re-runs the same investigation.

Reproduce:

```
godot --headless --path . --script tools/qa_walk.gd -- --root rating --sweep --ticks 150
for f in games/rating/*.dir games/rating/*.cst; do LC_ALL=C grep -qai "mainmenu-old" "$f" && echo "$f"; done
```

---

## 88. `GetLng()` / `SetLng()` are absent game data in Magic Hat, not a cast that failed to load — nothing to fix in the engine

**Status:** not a bug, recorded so the next reader does not re-derive it ·
**Area:** none · found while fixing 87

`test-games/itamar-magichat` reports `builtins unbound : {"getlng":1}` on every
boot, and `lng.cst` sitting unopened in the folder is the obvious suspect. It is
not the cause, and the arithmetic that made it look like one — "only 4 of its 7
casts load" — is counting two different things.

**Every cast library the movie declares opens.** `magichat.dir`'s `MCsL` names
eight, and all eight resolve and index:

```
lib 1  Internal  (embedded)   135 members
lib 2  utils     utils.cst     51
lib 3  objects   objects.cst   23
lib 4  cards     cards.cst     98
lib 5  album     album.cst    935
lib 6  same      same.cst     195
lib 7  code      code.cst      22
lib 8  lng       lng.cst      211
```

`tools/director_containers.gd --root res://test-games/itamar-magichat` opens all
sixteen containers in the title, and its one FAIL is only that the tracked
config's `strtgame.dir` is not this title's boot movie.

**Four of the eight carry Lingo, and that is the "4 of 7".** `cards`, `album`,
`same` and `lng` hold no `Lscr` chunks at all — `lng.cst`'s 211 members are
tooltip *bitmaps* (`bmain1_tt`, `blogin1_tt`, `balbum1_tt` …), which is what a
localisation cast in this title is. So `lingo: 77 script(s) across 4 cast(s)` is
the complete and correct count, not a shortfall.

**`GetLng` is defined in none of the sixteen containers.** Extracted every one of
them with `tools/director_extract.gd` and searched the lot:

```
grep -rn 'on GetLng\|on SetLng' <every extracted scripts/ dir>   # no matches
grep -rn 'GetLng\|SetLng'       <the same>                        # one file
```

The one file is `magichat.dir` member 87, `LogInMenuObject`, which calls
`GetLng()` once in `on new` and `SetLng(prDefaultLng)` once on the way out. Both
are on the login screen and nowhere else. `utils.cst`'s `language` script has
`Language()` and `ChangeLanguage()`, which are the handlers the rest of the title
actually uses, so `GetLng`/`SetLng` are a third spelling with no implementation
behind them — supplied by an Xtra or by a shell movie that this copy of the title
does not carry, or simply left dangling by the authors.

Director would have raised "Handler not defined" at the same call. The engine's
`builtins unbound` line is therefore accurate reporting and not a port fault, and
there is nothing here to bind.

---

## 48. Hezi is drawn in front of the foreground layer that hides him, and the original does this too

**Status:** **not a bug — measured, and closed as authentic.** Written down so it
is not reported a third time. · **Area:** whole-sprite puppets vs. score
occupancy · reported from play against `saves/piposh2/shlomit_hezi_gone.json`
with "it might be from the original but i really don't think so"

**The report.** In `dwarfs` the player character stands behind a foreground
layer that covers him from the knee down. Click through to the clip and he is
drawn in front of it instead.

**What the score holds.** In the room (DAY1 frames 1485-1487) channel 30 carries
Hezi (`1:30 standleft9`) and channel 31 carries a 613x158 foreground band
(`4:99`, rect `0,243 613x158`). 31 is the higher channel, so it paints over him.
At the clip the playhead reaches — 2514 onward — **both records are zero**:
`type=0 0:0 0x0` on each, which is `kInactiveSprite` and an empty member. So the
movie did not merely stop mentioning those channels, it **wrote them empty** —
the score is a delta stream, `director_score.gd:writes_between` is what says
which frame wrote what, and both channels are written to zero on the way in.

DAY1's `init all` does `puppetSprite` on `[93, 30, 23, 15, 33, 6, 100, 17,
103-110]`. **31 is not in that list.** So the clear reaches channel 31 and is
blocked on channel 30, and the layer goes while Hezi stays.

**The engine is right, and this is which function says so.** The question is
whether Director skips the *whole* channel update for a puppet — leaving what it
held, drawn — or only the property copy, with occupancy still following the
score. It is the whole update, along a chain with no branch in it:

- `Score::updateSprites` is the only thing that reconciles a live channel from
  the score, and it has **no clear path**: the single write is
  `channel->setClean(nextSprite)`, where `nextSprite` is the frame's decoded
  record and "empty" is expressed as a zero member inside it.
- `Channel::setClean` takes the `_sprite->_puppet || _sprite->_autoPuppet` branch
  and copies **only** the script id. `replaceSprite` is not called.
- `Sprite::replaceFrom` returns immediately while `_puppet` is set, after copying
  the script id, the behaviours and the sprite-list index.
- Occupancy lives in the *live* sprite's `_spriteType`/`_castId`, and the only
  code that ever changes them is inside the region `_puppet` returns before.
  `Channel::isEmpty()` — the render loop's own test — reads `_spriteType` off
  that live sprite, never off the frame record.

So a clear cannot reach a puppeted channel, in the reference or in Director. The
rule is applied identically to all 48 channels here; **the asymmetry is the
movie's**, and 1997 drew this frame the same way. `tools/puppet_persists.gd`
holds both halves of it at `exitforest3`: the score drops `[30]` and keeps it,
and `[2, 8, 9, 12, 13, 15, 31]` go with the score.

**What would make this a real report.** Not "he is in front of the tree" — that
follows from the data. It would have to be that the *clip* is not the frame the
game means to be on, i.e. that the click should never have got there. Nothing in
the trace suggests that: the clip runs, plays its line and returns.

Reproduce, and read the line beginning "the score dropped", which prints both
halves side by side:

```bash
godot --headless --path . --script tools/puppet_persists.gd -- \
    --root piposh2 --label exitforest3
```

That check is in `gate.sh` deliberately. A survey nobody runs rots, and "an
un-puppeted channel the score dropped is gone" is the invariant that would break
first if somebody tried to answer this report by making the puppet carry more.

---

## 38. Piposh 1 English "stuck on the logo" does not reproduce, and the CD-drive probe it points at was dead for a different reason

**Narrowed 2026-08-14.** The half of this entry that was a fix is a fix: the
`set the searchpath = […]` spelling compiles, and the 27 dead probe scripts run.
What is left is a player report that **does not reproduce and never has** — which
is not the same as fixed, and is why this stays here rather than moving to the
closed file. `piposh-en` still fails 14 of 9,422 scripts, but they are not
`strtgame.dir`'s probe frames; that residue is entry 39's. Nothing to do until
somebody reproduces it and captures the F3 report this entry asks for.

**Status:** open (the symptom), partly closed (what was found underneath) ·
**Area:** `games/piposh-en` boot, `strtgame.dir` · reported from play as "the
game gets stuck on the logo; pressing SKIP moves on to a disc message, and from
there the right-hand button reaches the main menu"

**The symptom does not reproduce on this commit**, headless or windowed. Boot
`piposh-en` and the playhead runs f0 → the CD probe at `option1` → f2 (the
guillotine logo) → f86 `oliver` → the intro comic → `mainscreen` at f608, and
idles on the menu. It takes **95 s** to get there, against **68 s** for the
Hebrew build of the same title, and both are authentic: the intro is a long
comic with music under it and the movie states 8 fps. A player who does not sit
through it reads that as stuck, and that is the most likely reading of the
report, but it is a reading and not a measurement.

```
godot --headless --path . --script tools/movie_churn.gd -- --root piposh-en --window-off --steps 600
```

**The other two thirds of the report are fully explained, and place the
reporter.** SKIP is the *preview's* affordance, not a button the movie has:
`skip_to_end` walked to the next marker (`docs/bugs-closed.md` 32 and 37;
SKIP no longer navigates at all). `strtgame.dir`'s
marker list ends with `option1`..`option26`, `maybondisk`, `inserta` and `cont`
— the CD-drive probe — and frame 1347 `inserta` renders as **"Please Insert CD
and click OK"** with `Quit` on the left and a yellow `Ooooooooooo K !` on the
right, whose script goes to `cont` and from there back to f2. So "SKIP → a disc
message → the right-hand button → the main menu" is SKIP walking into the probe
region, exactly as `docs/bugs-closed.md` 37 describes it doing on `rating`. It says the reporter
was on an early frame of `strtgame.dir`; it does not say why.

**What was found underneath, and is fixed.** Every one of those probe frames ran
a script that did not compile. `set the searchpath = [...]` — Director accepts
`=` where the parser demanded `to` — killed **27 of `strtgame.dir`'s 75
scripts**, which is the whole of `option1`..`option26`. A script that does not
compile is a handler that never runs and nothing at run time says so: the probe
frames fell through on the score's own step and the movie carried on with
`cdsavepath`, `soundspathstart`, `gWinDriveLetter` and `whichins` never set. The
Hebrew and Russian builds spell every `set` with `to`, so no amount of playing
the corpus this port was built on would have shown it.
`tools/script_compile_check.gd` is the harness that does, and it is what to run
first the next time a localisation misbehaves.

**What to capture if it still reproduces.** The F3 report on the stuck frame:
which movie, which frame, and what the clock says is holding it. Everything
above is consistent with the playhead being parked somewhere in f0-f5 or in the
probe region, and nothing measured here parks it in either.

---

## 36. Every one of DAY1's nine talk clips is an inescapable two-frame loop when the movie was entered without `globalday`

**Status:** open · **Area:** movie entry / cold globals · **not the film loop and
not `play`/`play done`** · reported from play twice, as two different symptoms

Two reports, one fault:

| snapshot | click | parked on | what the player saw |
|---|---|---|---|
| DAY1 f2686 of 2783 | f959 ch18 `BehaviorScript 644` | 2685 ↔ 2686 (`tofclicktalk`) | "the mouth loop keeps going and never stops" |
| DAY1 f2614 of 2783 | f1562 ch18 `BehaviorScript 642` | 2613 ↔ 2614 (`dnzclicktalk`) | "my click makes my character disappear" |

**The mechanism.** DAY1's tail holds nine `<character>clicktalk` clips, from
`bonclicktalk` to `hezfldclicktalk`, ending at the last frame 2783. Each is one
preamble frame followed by a `soundBusy` loop whose body is `BehaviorScript 250`:

```
on exitFrame
  if not soundBusy(1) then
    go(marker(0))
  end if
end
```

Its only exit is the preamble frame having started a sound. That frame —
`BehaviorScript 291` for `tofclicktalk`, `281` for `dnzclicktalk`, and one for
each of the rest — looks its line up in the `master` cast's `clickoncharacter`
field by the key `usfulobject = "tofday" & globalday`. With `globalday` VOID the
key is `"tofday"`, no line of the field matches, `r` stays `"not"`, and the
handler falls out without reaching `sound playFile`. So `soundBusy(1)` is never
true, `250` bounces the playhead back to the marker every step, the preamble runs
and does nothing every step, and the two frames trade places until the player
quits.

**Both symptoms follow from the park, and neither is a second bug.** The mouth
keeps moving because a film loop advances on the *movie's* clock and not the
playhead's — deliberate, `film_loop_view.gd:draw`, and the reason a character can
keep talking while the score holds still. Traced at `tofclicktalk`, channels 18
and 20 hold `atofspk1`/`btofspk1`; at `dnzclicktalk`, `adnzlop1`/`bdnzlop1`. The
character disappears in the second case and not the first because the *score*
differs: DAY1 f2686 carries a channel 30 (`standright9`), and f2613 carries no
channel 30 at all. The clip's own restore —
`set the memberNum of sprite 30 to the number of member ("standleft" & syz)`,
then `go(lastmark)` — is on the exit path that is never reached.

**Ruled out, with the trace rather than by argument.** `_play_stack` is empty for
the whole park *and no `play` is executed on this path at all*. DAY1's tail is
two different mechanisms and only one of them is `play`: the `*mov*` segments
(`chocomov` 2739, `fuelmov` 2756, and the last frame 2783) are entered by
`play frame who` and end on `play done`, which is `docs/bugs-closed.md` 32's
subject; the nine `clicktalk` clips are entered by `go("<char>clicktalk")` from
the sprite behaviour and end on `go(lastmark)`. Both of the reports here are in
the second half. The `play frame who` inside `291`/`281` is on the
`who contains "mov"` branch, which is downstream of the field lookup that failed,
so it is never reached either. The clock names no hold for a single tick of it —
`hold_reason()` is `""` throughout, so it is not a tempo delay, a transition, a
wait-for-click or a wait-for-sound, and `sound.gd:pump` has nothing to release.
`Scripts.for_frame` resolves correctly: 250 and 291 are the scripts that run.
The engine is reproducing the movie faithfully; Director parks here too.

**`globalday` is VOID exactly when DAY1 was not entered through `EXODUS`.**
`EXODUS/master/BehaviorScript 46` sets `globalday = 1`; DAY1's own
`BehaviorScript 56 - init all` reads it and never writes it, and its
`if globalday = 1` block is where `meetings` and `soundspath` come from. So the
F12 container picker, `--file`, and F6 warp all open DAY1 into a state where
every character in the game is a trap. This is the player-visible half of
entry 25 and of `tools/boot_state.gd`'s standing red check "every global the next
room reads is set" — the safety net was already on the floor, reporting the
cause, and nothing connected it to the symptom.

Reproduce, and the one-line proof of the cause:

```bash
# parks: 2685 <-> 2686 for ever, no sound, no hold
godot --headless --path . --script tools/playhead_escape.gd -- --cold
# passes: the same click through the boot chain plays the clip and returns
godot --headless --path . --script tools/playhead_escape.gd
```

**What to change.** Not the clip, not the loop and not the film loop. The engine
may not invent a movie's globals — Director does not, and entry 25 records that
seeding `init all` on a cold entry was tried and broke nine green checks. The
decision is the one entry 25 leaves open, now with a second, worse consequence
attached: a debug entry point that drops the player into a hub mid-game either
routes through the chain that establishes the day, or says that it has not.

### Correction: everything above was measured on a cold entry, and only there

The heading and the `--cold` reproduction stand. The sentence **"every character
in the game is a trap"** does not, and neither does any reading of this entry
that expects the trap in normal play. Driven through the real chain — the same
click, the same clip, `EXODUS -> DAY1` and `EXODUS -> MURDER1 -> DAY1` — every
one of them *works*, and here is a clip finishing:

```
== click 1 at f965                          usfultalking=null usfulline=null
   -> f2685                                 (tofclicktalk)
  t85   f2685  busy=false                   usfultalking=1
  t87   f2686  busy=true  days\d1prom1.aif  usfultalking=2 usfulline=17
  t138  f2685  busy=false days\d1prom1.aif  usfultalking=2
  t139  f2686  busy=true  days\d1prom2.aif  usfultalking=3
  t173  f2685  busy=false days\d1prom2.aif  usfultalking=3
  t174  LEFT the clip at f942               (veranda)
```

`globalday` is 1 the whole way, the key is `tofday1`, and line 17 of
`clickoncharacter` is `tofday1,0,pip,tofspk1`. Measured the same way at `field`
(rin, `a1prom1`), `edge1` (mog, `mogday12`) and `exitforest3` (dnz, `j1prom1`
through `j1prom6`, seven passes): all four exit to their `lastmark`.

**Two things this entry made it easy to believe, and both are wrong.**

**`tofspk1` is not a sound file, and no engine ever asks for one.** The third
item of a talk-order line is a *cast member name*: `BehaviorScript 291` line 74
is `set the memberNum of sprite rin to the number of member (xxx & who) of
castLib "wonder"`, with `xxx` "a" or "b" — so `tofspk1` becomes `atofspk1` /
`btofspk1`, the talking loop, which `docs/bugs-closed.md` 21 names from the other side. The
sound is a separate concatenation two branches earlier,
`soundspath & "d" & globalday & "prom" & usfultalking & ".aif"` and
`soundspath & "tofsay" & random(3) + vcv & ".aif"`. `find games/piposh2 -iname
"*tofspk*"` returning nothing is therefore not evidence of anything. The talk
order says *who animates*, not *what plays*.

**The loop is not open-ended.** Every branch of the preamble that plays a sound
also does `usfultalking = usfultalking + 1`, and the `else` arm exits as soon as
`the number of items in line usfulline - 2` is below it. So the clip terminates
after one pass per talk-order item *whatever the sounds do* — a `playFile` that
finds nothing simply makes it silent and quick. **The only way in is
`r = "not"`**: the day key absent from the table. Nothing else traps.

**Which leaves exactly two ways to get `r = "not"`, and the second is new.**

1. `globalday` VOID — the cold entry above, unchanged and still open.
2. **`hatday<n>` is not in the table for any day.** `clickoncharacter` holds 21
   lines, `bon`/`lil`/`dnz`/`mog`/`rin`/`tof`/`ish` × days 1–3, and no `hatday`
   line at all — while `BehaviorScript 289` (`lastmark = "tennis"`, clip
   `hatclicktalk` at 2649) keys on `"hatday" & globalday`. That trap needs no
   cold entry and no missing global; it is in the shipped data. **Not proved
   reachable**: at `tennis` the sprite is on channels 18 and 20 (both
   `ahatlop1` — `docs/bugs-closed.md` 21 again) and the click was not answered on the frame the
   harness clicks, so Hat's talk may simply be cut content that no behaviour
   dispatches to. Worth ten minutes with `tools/playhead_escape.gd --label
   tennis` before anyone chases the tof/dnz clips again.

**And there is a second family with the identical shape**, which this entry never
mentioned and which any detector has to cover too. Alongside the nine
`<char>clicktalk` clips there are six `<room>talk` clips — `fieldtalk` 2067,
`tennistalk` 2085, `edge1talk` 2103, `verandatalk` 2121, `exitforest3talk` 2139,
`dwarfs1talk`/`dwarfs2talk` — reached from `objecttalktime` (showing an object to
a character) rather than from a click, and driven by `talkproc init, fieldname,
lastmark` in `DAY1/wonder/MovieScript 248`. It is the same handler written once:
look `usfulobject` up in a `master` field, play, increment, and `go(lastmark)`
when the items run out. It reads a *different* field per character (`tof-ans`,
`hat-ans`, `pat-rin-ans`) and a different sound global (`objtlkpath`, the same
one segment short), and it has the same single trap condition — the key absent
from the table. Whatever answers this entry must answer both.

**Ruled out with measurement, so it does not get re-derived.** The sound path was
never the fault. `days\d1prom1.aif` resolves, plays, and holds `soundBusy(1)` for
about fifty score ticks. `soundspath` *is* one segment short —
`MASTER/External/MovieScript 130` builds it as `soundspathstart & "days" & "\"`
and `soundspathstart` is written only by `strtgame`'s CD-drive probe
(`ROOT/strtgame/BehaviorScript 110`), which no entry short of a full boot passes
through — but that is a **wrong-take** bug, not a hang, and it is fixed:
`autoload/audio_director.gd` now matches a request as a *tail* of a path on disc,
which takes this corpus from 315 ambiguous filenames to 0. `tools/sound_wait.gd`
covers it, together with the rule underneath this whole entry: a `playFile` that
cannot start must leave the channel **not busy**, or a `soundBusy` poll is a wait
for something that can never happen.

### Second correction: the two player reports were never this entry at all

The correction above proved the clips *finish* in normal play and then stopped,
leaving the two symptoms attributed to a park that the same measurement had just
ruled out. Four save states taken from real play — `saves/piposh2/tofi_bug.json`,
`shlomit_hezi_gone.json`, `shlomit_hezi_gone_2.json`, `dward_hezi_gone.json`, all
with `globalday = 1` and every lookup resolving — say what they actually were.
**One fault, in the puppet model, with nothing to do with `play`, the film loop,
`marker(n)`, the clock or the sound.** Fixed; see `preview/sprite_state.gd`.

Director has **two** kinds of puppet (`docs/DIRECTOR_ENGINE.md` §5.2, §5.3, §5.5)
and this port had one, so it was simultaneously too sticky and not sticky enough.

**"His mouth keeps moving even after everything is done playing."** Traced from
`tofi_bug.json`, clicking Tofi at (498,171): the clip runs correctly — Hezi's
line, then Tofi's, `usfultalking` 1→2→3 — and exits to `veranda` on tick 89,
exactly as it should. What was left behind is channel 18. `BehaviorScript 291`
does `set the memberNum of sprite rin to (xxx & who)`, which auto-puppets *that
one property*; the score's channel 18 is `atofspk1` inside the clip and
`atoflop1` at the veranda, so the write is released the moment the playhead
leaves. `sprite_state.gd:effective` exempted `membernum` from that release, so
Tofi went on standing in the veranda animating `btofspk1` — his talking loop —
for the rest of the movie. The film loop was doing exactly what it should with
the member it had been given, which is why every earlier reading of this looked
at `film_loop_view.gd` and found nothing wrong.

**"Hezi is disappearing during the animation, then appearing again."** All three
saves, one cause, and it is not three: the score of `lilout1` (2514-2522),
`lilclicktalk` (2595-2611) and `dnzclicktalk` (2613-2629) **carries no channel 30
on any of those frames**, and DAY1's `init all` does `puppetSprite(30, 1)`. In
Director a whole-sprite puppet is not reconciled from the score at all, so the
player stays put; this port drew from `_score.frame(_index).sprites`, so the
channel simply was not on the frame. The sentence above — "the clip's own restore
is on the exit path that is never reached" — is wrong twice over: the exit path
*is* reached, and the restore is not what puts Hezi back. `tofclicktalk` carries
a channel 30 and that is the whole reason the same fault was filed as two
unrelated bugs. It is also why "sound is playing well" was the decisive clue.

**A third fault, found on the way and fixed with them.** `director_preloader.gd`
walks 24 frames ahead of the playhead every step and was calling `_effective` on
those frames' records — a read that *mutates*, because the auto-puppet release is
recorded there. Any later frame holding a different member on a channel released
that channel's live puppet, so a member a script had just written survived
exactly one tick: measured on channel 18 at `tofclicktalk`, `atofspk1` ↔ the
script's write, alternating every step. `effective` now takes `peek`, which
answers the same question without recording, and the preloader asks that.

**What is still open here is the heading**, unchanged: a cold entry that skips
`EXODUS` leaves `globalday` VOID, `r` stays `"not"`, and the clip parks. So does
the `hatday<n>` gap in the shipped table, still unproved reachable. Neither was
what the player was reporting.

Covered by `tools/puppet_persists.gd` (`gate.sh puppet_persists`). It drives the
boot chain to two rooms, writes a state at each, reloads it into a *fresh*
preview and clicks: `exitforest3` into `dnzclicktalk`, where the score drops the
puppeted channel, and `veranda` into `tofclicktalk`, where it moves the
un-puppeted one. Each room prints which of the two halves it actually proved
rather than passing on the one it cannot see. The states are built rather than
committed — `saves/` is gitignored because a save carries the movie's own field
text — and going through one is also the only check that the puppet claim
survives `capture`/`restore`, since it lives *inside* `_overrides` and
`tools/save_state.gd` only asserts that `_overrides` itself is carried.

Reproduce either report from the user's own states, once they are re-taken on a
build that records the claim:

```bash
godot --path . -- --save saves/piposh2/tofi_bug.json          # click Tofi
godot --path . -- --save saves/piposh2/dward_hezi_gone.json   # click Dnz
```

**The four saves in the report predate the fix and will not show it.** They were
written before `puppetSprite` recorded anything a save could carry, so their
`_overrides` name no puppet at all and channel 30 still vanishes when they are
loaded. That is a property of those files, not of the engine; a state taken now
carries the claim, which is what `puppet_persists` asserts.

---

## 25. A cold F6 warp or save-editor Apply still drops the player into a hub with unset globals

**Status:** open decision, not a pending task · **Area:** dev tools / skip routing ·
the three skip doors are fixed, see `docs/bugs-closed.md` 25

DAY1's globals are seeded by `BehaviorScript 56 - init all` on **frame 1**:
`egozh = 600`, `egozv = 325`, `syz = 7`, `whatodo = "stand"`,
`nextroomdata = "000"`, `ifmovie = "0,0"`, and the inventory channels puppeted.
Enter a hub past frame 1 and none of it is set, so Piposh walks toward 0,0 and the
next room places him off-stage.

`F6` warp and the save editor's **Apply** both call `goto_movie(movie, label)`, so
from a cold boot they can still do exactly that. The workaround is to start a game
first and then warp, and both tools' docstrings already say they do not replay the
walk that would normally get you there.

Left open deliberately rather than filed as work. The two ways to close it are a
seeding path or a two-step "run the init region, then jump", and both add a
mechanism the original does not have. **Seeding was tried and is the wrong shape:**
running the hub's frame-1 handler on any cold entry broke 9 green checks, because
`init all` empties `objectsfield` and resets `meetings`, so it wipes whatever state
the caller had set up. Do not add an init-seeding path; route the entry through
frame 1 instead. The decision to make is whether these two dev tools should
auto-start a game, not how to seed.
---

# The 2026-08-14 language-and-clock pass

Seven entries closed, one narrowed by taking the measurement it asked for. Two of
the seven had been open for a long time because they needed an **answer from the
grammar or the event loop**, not a patch, and nobody had gone and got it.

| # | Verdict | What settled it |
|---|---|---|
| 39 | **Fixed — answered from `lingo-gr.y`, not guessed** | Whether Director closes an unterminated final handler at EOF was the open question. The `handler` non-terminal has four productions and **two of them are `tON ID idlist '\n' stmtlist` with no `tENDCLAUSE`**, commented `// D4. No 'end' clause` — no version guard, and no `error` action, unlike the malformed-but-tolerated productions beside them. `LingoArchive::addCode` hands the member's whole text to one `compileLingo` call with nothing appended that could stand in for the terminator. So Director closes it, and so does this port now — **only at EOF, deliberately**: `lingo-gr.y:397` puts `tON` in `CMDID`, so `on mouseUp` is also a legal command-form call, and a parser resolving that ambiguity by shifting would swallow the next handler. That ambiguity is *why* the entry stayed open; EOF has none of it. `piposh-en` 9420 → **9422 of 9422**, `piposh-ru` 9724 → **9726 of 9726**. The day-4 doctor click is alive in both localisations. |
| 61 | **Fixed, and the entry overstated the fault** | `events.cpp:249-297` is one `if`/`else`: the wait arm ends the wait and returns, so no `mouseDown`, no `the clickOn`, no `clickLoc`, no `lastClick`, no hilite, no drag. **But the mouse-*up* is not consumed** — `EVENT_LBUTTONUP` has no `_waitForClick` arm and `queueEvent` resolves `mouseUp` from the position, not from anything the press latched. So "one click both releases the wait and fires whatever it landed on" is half right, and **suppressing the whole click would have been a second bug**. One residue left and named: the timeout stamp still fires, where the reference stamps `_lastTimeOut` inside the else-arm. |
| 60 | **Fixed — the port's recorded reasoning was wrong** | `Score::update` calls `updateCurrentFrame()` then `updateNextFrameTime()` on **every** cycle; on `go to the frame` the first does nothing and the second re-reads the same cell. The port's note said re-arming "would hold it for ever rather than for two seconds" — but a re-arm *re-delays*, with a step between every pair. The entry's three feared blockers dissolve: sounds, palette and transition stay behind the reference's own `if (_curFrameNumber != nextFrameNumberToLoad)`, and re-arming a **wait** is correct, because a self-holding `tempo 248` frame waiting for a click again after each click *is* the click-to-advance idiom. `strtgame.dir` frame 5, 1000 ms delay at 8 fps: **30 steps in 5.0 s before, 4 after.** |
| 62 | **Fixed** | `score.cpp:417-423` flips the cursor every 1000 ms while the wait stands and `:1454-1457` answers it *before* walking the channels — so precedence and rhythm are both part of the rule. Director's own 16x16 bitmaps are art that was not copied; the two states map to the arrow and the pointing hand, **declared rather than hidden**, the same honesty the file's existing built-in mapping uses. |
| 59 | **Fixed** | `error_total` is incremented in `_fail` **before** the 50-entry cap, so a frame script failing fifteen times a second is not reported as one fault, and `session_faults()` exposes the set that already survived `reset_steps`. |
| 76 | **Fixed** | The `dot` arms of `_eval` and `_assign` **synthesise the `field_prop` node and delegate** rather than duplicating the arm, so the two spellings cannot drift. The control showed the reported fault exactly: `.textSize` answered 12 — a property of a member named after the field's *text*. |
| 103 | **Fixed, with an honest "no symptom today"** | `start_lingo` now clears `_lib_keys` beside `_script_casts`. Measured before fixing: the interpreter is replaced three lines above, so a stale key names a bundle the new interpreter never loaded and the lookup answers `{}` — indistinguishable from the key being absent. What the line buys is that the two cannot come apart the moment anything carries a bundle across a movie boundary. The evidence the *state* was wrong is that two harnesses were clearing it by hand. |

**A correction that applies to the three clock entries above**, re-measured today
with `tools/transition_survey.gd --root piposh2`: Piposh 2 has **19**
wait-for-click frames and **23** delay frames totalling **46.0 s**. The entries as
written say 24, 36 and 74.0 s. Their arguments do not turn on the figures, but the
figures were wrong.

## 39. One script in two roots still does not compile, and it may be malformed rather than unparsed

**Status:** open · **Area:** `lingo/compile/lingo_parser.gd` · found by
`tools/script_compile_check.gd`, which is why it is a number and not an
impression

**Re-measured 2026-08-14 at `02844f93`, after the two parser fixes that commit
carries. Four roots are green and the remainder is one script**, so the table and
the diagnosis below are both replaced rather than annotated:

| root | compiled | before the fix | before that |
|---|---|---|---|
| `piposh2` | **3,307 of 3,307** | 3,307 | 3,307 |
| `piposh` | **8,754 of 8,754** | 8,742 | 8,738 |
| `piposh-dream` | **1,746 of 1,746** | 1,746 | 1,725 |
| `rating` | **5,441 of 5,441** | 5,440 | 5,437 |
| `piposh-en` | 9,420 of 9,422 | 9,408 | 9,406 |
| `piposh-ru` | 9,724 of 9,726 | 9,712 | 9,710 |

The two defects that closed the rest were both in `end`-swallowing. A one-line
`if x then <stmt>` consumed a following `end if` that belonged to an enclosing
block, so the handler ran off the end of its own source and reported `expected
end` at the last line -- pointing nowhere near the cause, which is why the five
CLOCK SCRIPTs stayed undiagnosed through several passes. And `end` only swallowed
a trailing word when it matched the handler name, so `on idle / ClockScript1 /
end if` was dropped. Both are in `02844f93`; the visible consequence was Piposh
1's in-game clock never advancing, which had been reported as an Android bug.

The recovered Itamar corpora move with them: `magichat.dir` is 124 of 124, and
what is left there is `hats.dir` 111 of 112 and `torfim.dir` 64 of 65, neither
re-read since the numbers moved.

**What remains is one script, in two roots, and it may not be a parser bug at
all.** `Texts.cst CastScript 98 - day4doc2` in `piposh-en` and `piposh-ru`, "line
5: expected end", counted twice in each because the cast is reached twice. It is
an `on mouseUp` with **no `end` at all** -- the member's source stops after
`go to frame "doc1b"`. So the question is not how to parse it but whether
Director closes an unterminated final handler at EOF, and nobody has measured
that. Guessing either way silently changes what every malformed script in the
corpus does, so it stays open until it is answered from the reference.

The Hebrew build is unaffected. The cost of the remaining two is that one click
in the day-4 doctor dialogue is dead in both localisations.

```
godot --headless --path . --script tools/script_compile_check.gd -- --root piposh-en --verbose
```

---

## 59. A Lingo runtime error survives only until the next dispatch, so nothing can observe one during play

**Status:** open · **Area:** `lingo/lingo_interpreter.gd`

`LingoInterpreter._fail` is where every runtime fault the interpreter can name
lands: "step budget exhausted", "repeat while did not terminate", "handler
recursion too deep at X", "unknown statement", "cannot assign to X". They go into
`errors`, a `PackedStringArray` capped at 50.

`reset_steps()` clears it, and `reset_steps` is called at the **start of every
dispatch** — `preview/scripts.gd:dispatch`, `preview/event_chain.gd:run` and the
thaw. One score step dispatches `idle`, `exitFrame`, `prepareFrame` and
`enterFrame` back to back, all inside one process frame, so an error raised in
any of them but the last is gone before anything outside the interpreter can read
it. The only reader in the whole port is `preview/debug_report.gd`, which prints
whatever happens to be there when the report key is pressed.

So the port has no way to answer "did any script fault while that room ran". A
handler cut off half-way by the step budget leaves the room in a state nobody can
attribute later, which is the same class of failure as a harness that reads null
and reports zero.

`tools/liveness_sweep.gd` polls `errors` once per process frame and accumulates
what it finds, which is the best that can be done from outside: a `lingo` finding
from it is real, and **a clean sweep is not evidence that nothing faulted.**

The fix is a sink that outlives a dispatch — the shape `LingoDiagnostics` already
has for unbound names, which deliberately survives `reset_steps` and accumulates
over a session. `errors` wants the same treatment, or a counter beside it, so
that "42 runtime faults this session" is a number a harness can assert on.

**Narrowed 2026-08-14: half of that sink exists.** `reset_steps` now calls
`_drain_errors()` before `errors.clear()`, and `_drain_errors` prints each *unique*
message once per session against a `_reported` dictionary that survives the
dispatch. So a fault two dispatches ago is no longer silent — it is in the run's
output. What is still missing is the assertable half: nothing counts them, so a
harness cannot say "this room ran clean" and `tools/liveness_sweep.gd` is still
polling `errors` once a process frame and still cannot promise it caught them all.

**Reproduce:** read `lingo/lingo_interpreter.gd:698-708` (`reset_steps`) beside
`:1634` (`_fail`) and `scenes/preview/scripts.gd:75`. Then run any movie and note
that no tool in `tools/` can report a fault that happened two dispatches ago.

---

## 60. A tempo delay on a self-holding frame is armed once; the reference re-arms it on every step

**Status:** open · **Area:** `scenes/preview/frame_loop.gd:sync_frame_entry`, `director/director_frame_clock.gd:enter_frame`, `score.cpp:640-712`

`Score::update` calls `updateCurrentFrame()` and then `updateNextFrameTime()`
**every update cycle**, not only when the frame number changes. A room holding
itself with `go to the frame` sets `_nextFrame` to the frame it is already on, so
`updateCurrentFrame` takes its else-arm and does nothing -- and
`updateNextFrameTime` still runs, reads the same tempo cell, and re-arms the same
delay. A frame carrying a two-second delay and holding itself therefore steps
once every two seconds, for ever, in Director.

This port arms the tempo on a genuine frame *change* only: `sync_frame_entry`
returns early when `_index == _entered_index`, so the delay is armed once, runs
out, and the room then steps at the movie's frame rate -- 15 or 8 times a second
against Director's once every two seconds. The frames are there: Piposh 2 carries
36 delay frames totalling 74.0 s and 23 of them carry a frame script; *Rating*
carries 160 totalling 439.0 s.

The early return is deliberate and its comment says why -- "re-arming a two-second
delay from there would hold it for ever rather than for two seconds" -- and that
reasoning is wrong in a way worth recording: re-arming does not hold the frame for
ever, it *re-delays* it, which is exactly the behaviour above. What the comment
describes would only happen if the delay were re-armed without the playhead ever
being allowed to step, which is not what the reference does.

Not changed here because it is not a one-line move. Arming the tempo per step
means the transition must **not** move with it (a wipe re-armed every step never
finishes), so the two would have to be split out of `sync_frame_entry`, and
`enter_frame` would have to become idempotent for the click and sound waits or a
frame released by a click would re-arm its own wait on the next step. That is a
change to the tick's shape and wants measuring against `idle_clock`,
`pause_holds`, `playhead_escape` and `frame_events` together.

**Reproduce:** read `reference/scummvm/score.cpp:640-712` beside
`scenes/preview/frame_loop.gd:sync_frame_entry`. For the exposure,
`godot --headless --path . --script tools/transition_survey.gd -- --root piposh2`
prints the delay frames and their total.

---

## 61. The click that releases a wait-for-click is delivered to the movie as well; the reference consumes it

**Status:** open · **Area:** `scenes/director_preview.gd:route_press`, `scenes/preview/interaction.gd`, `events.cpp:250-262`

`Movie::processEvent` handles the mouse-down in one `if`/`else`:

```
if (sc->_waitForClick) { sc->_waitForClick = false; sc->renderCursor(pos, true); }
else                   { ...latch the press, build the chain, dispatch mouseDown... }
```

So on a wait-for-click frame the press does one thing and one thing only: it ends
the wait. No `mouseDown` is dispatched, `the clickOn` is not rewritten, no drag
starts, and no sprite is hilited. This port releases the wait in `route_press` and
then carries straight on into `latch_press` and the mouse-down chain, so the click
that ends the wait is also a click on whatever sprite was under it.

Piposh 2 has 24 wait-for-click frames and *Rating* has 214, so the divergence is
reachable; whether it is *visible* depends on whether those frames also carry a
clickable sprite, which is not measured here.

Not changed here because it is a change to the input path rather than to the
clock, and it inverts the order two other rules depend on: §15's latch block is
documented as running for either button and on every press, and
`preview/interaction.gd` is where that decision lives.

**Reproduce:** read `reference/scummvm/events.cpp:250-262` beside
`scenes/director_preview.gd:route_press`.

---

## 62. A wait-for-click frame shows no alternating cursor, so a waiting movie looks like a stopped one

**Status:** open · **Area:** `scenes/preview/cursor.gd`, `director/director_frame_clock.gd:waiting_click`, `score.cpp:400-424` and `:1444-1458`

§9.2: while `_waitForClick` is set, `Score::isWaitingForNextFrame` flips
`_waitForClickCursor` once a second and re-renders the cursor, and
`Score::renderCursor` returns the built-in mouse-up or mouse-down arrow for that
flag *before* it consults any sprite. It is the only feedback a wait-for-click
frame gives, and without it the movie is indistinguishable from one that has
hung -- which is what a player sees on 24 frames of Piposh 2 and 214 of *Rating*.

The clock half is there: `FrameClock.waiting_click()` answers the question and was
added for this. What is missing is the cursor path taking it, with the 1000 ms
alternation and the precedence over the sprite cursor (§7.4).

**Reproduce:** read `reference/scummvm/score.cpp:400-424` and `:1444-1458` beside
`scenes/preview/cursor.gd`.

---

## 76. `field("x").prop` — the dot spelling of a field property — resolves a member named after the field's *text*

**Status:** open, unexercised · **Area:** `lingo/lingo_interpreter.gd`'s `dot`
arms · found while closing `docs/bugs-closed.md` 53/35, and **not** fixed with it

The designator spelling `the <prop> of field "x"` now reaches
`get_field_prop`/`set_field_prop`. The dot spelling does not: `_eval`'s `dot` arm
tests the owner node for `sprite_ref` and `member_ref` and has no `field` case, so
`field("x").textSize` evaluates the owner — which yields the field's **text** —
and then asks `get_member_prop` for a member of that name. `field("x").text = y`
takes the same route through `_assign`.

0 sites in any of the six titles use it, which is why it is filed rather than
fixed in the same change: the fix is one more arm beside the two that are there,
and it wants the same harness case as the designator spelling
(`tools/field_designator.gd`) rather than a new file.

---

## 103. `start_lingo` clears the script casts but not the library keys, so a movie inherits the previous movie's cast-library names

**Status:** OPEN, no symptom measured · **Area:** `scenes/preview/boot.gd:start_lingo`
· found while tracing entry 102's cast resolution

`boot.gd:start_lingo` clears `_script_casts` (`:282`) and does not clear
`_lib_keys` (`:321`). So entering `eat.dir` from `dinner1.dir` leaves
`{2: "DINNER1/doc", 3: "DINNER1/hezi", 5, 7, 8, 10, 13: …}` alive under a movie
whose only library is 1. A script naming `castLib 7` there would resolve into the
movie the playhead has left.

**The evidence that this is real rather than theoretical is that two harnesses work
around it**: `tools/click_eligibility.gd:127` and `tools/click_chain.gd:469` both
call `_lib_keys.clear()` themselves before measuring. A tool clearing engine state
by hand is a statement that the engine did not.

No player-visible symptom has been measured, and that is why it is filed rather
than fixed: library 1 *is* re-keyed on every movie load (verified live —
`lib_keys={1: "EAT/internal", 2: "DINNER1/doc", …}` after the real
`dinner1.dir → eat.dir` handover), and library 1 is what this corpus's scripts
actually name. So the stale entries are unreachable in the six titles as authored,
and the bug is a loaded gun rather than a wound. It is one line beside the existing
`clear()`, and the reason to do it deliberately rather than casually is that
`bugs.md` 34's whole family — a member number resolving in the wrong library returns
a stranger rather than nothing — is what stale keys would produce.

Reproduce the state:

```
godot --headless --path . --script tools/click_chain.gd -- --root piposh-dream --file dinner1.dir
```

and read `_lib_keys` after the handover to `eat.dir`, with that tool's own
`_lib_keys.clear()` at `:469` removed.
---

## 30. Sprite colours that D7 stores as true RGB are read as palette indices

**Status:** open · **Area:** score decoder / renderer ·
found while measuring the sprite record byte by byte

Bits 0x10 and 0x20 of the sprite record's colour-code byte (offset 20) say that
the sprite's fore or back colour is a **true colour** carried in bytes 24-27 —
byte 2 and byte 3 being the red components, 24/26 the green and blue of the fore
colour, 25/27 of the back — rather than an index into the movie's palette. The
port reads bytes 2 and 3 as indices unconditionally, so those sprites take
whatever the palette happens to hold at that index.

Measured, on the corpora as they stand:

```
$ godot --headless --script tools/sprite_record_bytes.gd -- --all   # Piposh 2
  20         9    0x00:746048 0x01:7470 0x02:51929 0x03:2830 0x04:2149
                  0x05:4753 0x10:15 0x20:635 0x30:489
  24        20    0x00..0xff
  25        35    0x00..0xff
  26        16    0x00..0xff
  27        24    0x00..0xff
```

So **1,124 of Piposh 2's 816,318 records** carry the back-colour bit and **504**
the fore-colour bit, and bytes 24-27 genuinely vary. Piposh 1 sets neither bit
and leaves 24-27 zero across all 1,886,362 of its records, so it cannot be used
to check a fix.

It matters more than a wrong tint would suggest: the back colour is what
Background Transparent keys against (§2.1), so a record whose paper is an RGB
that the port resolves as index 255 keys out the wrong pixels entirely.

The reference is no help and no excuse. `frame.cpp:readSpriteDataD7` parses all
four bytes and `sprite.cpp:replaceFrom` copies them, and **nothing in ScummVM
ever reads them again** — the same shape as flip before §1.8 was implemented.

Not fixed here because it needs the colour to stop being an index all the way
through `director_ink.gd` and the texture cache key, and because the only corpus
that exercises it is the one this port already renders acceptably — which makes
it exactly the kind of change that wants its own before-and-after measurement.
**Resolved 2026-08-14. The entry's own cost estimate was a measurement of Piposh
2 and was low by two orders of magnitude.**

`tools/sprite_rgb_colour.gd` over all eight roots, 8,074,544 occupied sprite
records: **`piposh-dream` states a true colour on 55,134 of its 766,010 records —
7.2% — and had never been measured.** Piposh 2 states 504/1,124, `piposh` and
`rating` none at all.

**What it states is not an exotic tint, which is why this mattered so much more
than the count suggests.** Every one of the corpus's 57,152 back colours is
`(255,255,255)` and the commonest fore is `(0,0,0)` — Director's *default* pair,
written the D7 way. Read as palette **indices** those same bytes are 255 and 0,
which in Director's inverted 8-bit convention are the same pair **backwards**. So
`applies_colour` concluded "not the defaults, colourise" and `apply_colour`
swapped the artwork's black and white; on the 23,343 Background-Transparent
records `key_paper` keyed the black pixels instead of the white ones. **33,514
records were repainted by that reading, every one of them a default pair that
should have been left alone.**

The outside witness that the byte assignment is right, rather than a plausible
re-reading: the 8 distinct fore colours are recognisable web-safe triples —
`(238,238,238)`, `(204,255,0)`, `(102,255,255)`. Random bytes do not do that.

`director_score.gd` emits `fore_rgb`/`back_rgb` only on records that set the bits;
`director_ink.gd` owns the decision; `sprite_geometry.gd:texture_key` gained a
term because a true colour's red *is* the index byte, so `(0,0,0)` and index 0
collided in the cache. `channel.gd`'s `forecolor`/`backcolor` became
`colour_index` and retired the record's colour, because the Lingo property is an
index and the record's field is not. Reverted, the harness fails 10 of 17.

---

# 74 and 80, closed 2026-08-15

**74 is the sharpest instance this project has produced of the rule it keeps
relearning: subtract the harness from the difference before believing anything
about the port.** Two sessions and three theories went into the artwork, the
palettes and the blend path. The first thing to check — whether anything of *ours*
was in the picture — was never checked.

| # | Verdict | What settled it |
|---|---|---|
| 74 | **Not a bug in either compositor. The diagnostic was the faulty side.** | `tools/stage_compare.gd` was photographing the player with the **debug layer on**. The "eight rows" are `scenes/preview/stage_paint.gd:295` drawing `frame 37/206  playpiano  fps 15  hit:art  cur:0` at `Vector2(8, stage.y - 8)` = (8,472) in white at alpha 0.75 whenever `DebugKeys.enabled()` — which is `auto`, and `auto` on a run from source is **on**. |
| 80 | **Fixed** | An adjust-to-fit or limit field now takes the member's width and `MAX(member height, laid-out text height)`, and the vehicle that lets a *static* sizing function see *runtime* text is a stamp in `_effective`. |

## Every figure entry 74 carried was that one string

The band it names, `(8,466) 252x9`, is the string's own bounding box. "243 distinct
values where the diagnostic produces 23 exact palette entries" is **antialiased
glyph coverage**: `Surface.glyphs` composes atlas cells carrying partial alpha and
`Image.blend_rect` blends rather than replaces, so the results land *between*
palette entries. It showed only on the dark seam under the keys because white text
over a white key changes nothing — which is exactly what made it read as a fault in
the artwork's dither. It was stable across frames 37 and 39 because the HUD is.

So the second of the two candidates named the right **mechanism** and the wrong
**subject**: partial alpha really was reaching `blend_rect`, and the alpha was ours.
The first candidate dies by the same measurement — with `--debug-ui off` the two
compositors agree on **0 of 268,800 px below y60**, band included, on frames 37 and
39 alike. Two compositors resolving different palettes cannot come out exact on
every pixel of 67 sprites.

The entry's recorded 13.3% was also wrong: it sampled one pixel of each 2x2 block.
The real figure is 31.7%.

`stage_compare.gd` now **refuses to run with the debug layer on**, naming the flag;
composes its reference through `director_render.gd:compose` **in the same process**
at the frame the player turned out to be standing on (removing the two-invocation
PNG handoff that made it ungateable); and **asserts** the difference instead of
printing it — every previous version printed a percentage and exited 0, which is
why it passed for as long as the bug was open. It also fails when handed neither a
reference nor a rendering, because a run that compares nothing is dark rather than
clean and `gate.sh`'s EMPTY guard cannot see it: 5 checks is not 0 checks.

A contrast case is recorded in the tool so the signature is legible next time:
`piposh2 CHESS.dir` at `ches1` differs on 7,005 px with **both sides exact palette
entries**. That is the ordinary "the movie dressed itself with Lingo" asymmetry.
The signature to be suspicious of is the other one — one side holding values no
palette entry holds.

## 80: the rule, and two deliberate departures from the reference's literal `dims`

`castmember/text.cpp:createWidget` builds MacText from a box it "can expand now,
but can't shrink"; `createWindowOrWidget` hands it a `maxWidth` of the member's
`initialRect`; `channel.cpp:774-779` copies the widget's dimensions onto the
sprite and `:585-591` re-pushes them every frame for exactly the box types
`getFixDims()` does not cover. So fixed and scrolling take
`MAX(bbox, MAX(initialRect, maxHeight))` once; adjust and limit take the member's
width and grow vertically.

Both departures were **measured** by the new `tools/field_box_survey.gd` over all
eight roots and are in the docstring:

* **Width is the member's, not `MIN(bbox, initialRect)`.** Taking `dims` literally
  narrows 33,767 records in `piposh`, 33,764 each in `piposh-en` and `piposh-ru`,
  1,679 in `rating` and 1,603 in `piposh2` — that is `GlobalMoney` again, the
  regression `9d1b23d2` fixed. Adjust to Fit grows a field *vertically*; the width
  is the wrapping width.
* **The height floor is the member's rect, not the score's bbox.** A floor that
  follows residue makes the drawn height change mid-run — the pulse
  `drawn_size_stability` exists to catch. Cost: 52 records sit taller than the
  reference would start them, and none clips either way.

**No oscillation, by construction**: the size is *derived* on demand and never
stored. Storing it is what diverges — `limit` leaves the bbox alone so a stored
height would be re-laid-out and grow without bound, and `adjust`'s MIN would
ratchet down to residue. `drawn_size_stability` still reports 0 unstable runs over
816,344 records.

**And the entry's own motivating example is the wrong box type.** `CAPROOM.dir`'s
`memowrite` is *fixed*, and `createWidget` passes `fixDims` for fixed and
scrolling — so Director clips it too when typed past. The typing case the entry
wanted is an adjust/limit editable field, which is what `SAVELOAD.dir`'s `points`
is and what the new harness drives.

## 74. Eight rows of Piposh 1's piano keyboard draw differently in the player and in `director_render.gd`

> **Re-measured 2026-08-14: it reproduces, and the likeliest innocent explanation
> is eliminated.** The expectation was a window-capture artifact — the stage is a
> `Node2D` whose float32 scale composes with the viewport stretch
> (`stage_paint.gd:framebuffer_region`, `bugs.md` 117). It is not.
> `tools/stage_compare.gd` photographs the player **headlessly** through
> `director_paint.gd:Surface`, stage-sized and 1:1, with no scale anywhere in the
> path, and the difference survives.
>
> The whole-stage figure reproduces exactly (833 of 268,800 px, 0.31%). **The band
> is 31.7%, not the 13.3% recorded here** — that number came from sampling one
> pixel of each 2x2 block. The player produces 243 distinct values where the
> diagnostic produces 23 exact palette entries, so the characterisation stands.
>
> Two live candidates, both testable: the two compositors resolving **different
> palettes** for these members (`PaletteView.table_for_member` against
> `director_render`'s own — the `bugs.md` 104 shape), or **partial alpha** reaching
> `Image.blend_rect` in `Surface._compose`. `director_render.gd` remains a valid
> oracle: it shares `director_ink.gd` and `director_bitmap.gd` with the player.
>
> **A trap for anyone repeating this**: setting `_index` and settling leaves the
> playhead elsewhere on a movie that does not hold itself. The first run reported
> "frame 37" while standing on **41**, comparing it against a render of 37. The
> tool re-seats, pauses, and asserts it is standing where it was asked.

`docs/bugs-closed.md` 73 removed the diagnostic's own crude keying rule, and with
that gone the player and `tools/director_render.gd` agree on **0.30% of the stage
below the HUD** on `PIANO.dir` frame 37, and on **0.00%** of the book. What did
not close is the eight rows the original report was about: **y466-474, x8-259,
where 13.3% of the pixels still differ.** Stable across frames 37 and 39, so it is
not a frame mismatch.

This is the mottled line under the left half of the keyboard. Where they differ,
the renderer produces exact palette entries -- `(170,170,170)`, `(153,153,102)`,
`(102,102,102)` -- and the player produces values that are in the palette's gaps,
`(181,181,181)`, `(217,217,217)`, `(209,209,187)`. A value no palette entry holds
came from combining two, so **the player is blending where the renderer is not**,
and 0.3% of the sampled 2x blocks have two different columns inside one stage
pixel, which under nearest filtering at an exact 2.000 scale should be none.
Nearest is configured twice over -- `project.godot`
`textures/canvas_textures/default_texture_filter=0` and `boot.gd` setting
`TEXTURE_FILTER_NEAREST` on the host -- so the blend is coming from somewhere
those two do not cover. That is the thread to pull.

**What is already ruled out.** `key_matte` on member 2 (`noclid1`) is clean: 79.6%
opaque, border removed, interior paper correctly kept, so it is not a matte leak.
Dashing is genuinely *present in the inputs* -- member 2 has a solid dark row at
its own local y55, a part-toned row at y54 and a dashed row at y56 -- and the key
sprites overlap about 12px with each sitting one pixel lower going left, so some
of the appearance is authentic whatever this turns out to be. Which is why this is
still open rather than filed as authentic: an explanation of how it *could* be
authentic is not the evidence `AGENTS.md` wants for the verdict that stops work.

**Measuring this at all needs care, and getting it wrong cost a session.** A
window capture is only comparable at an *integer* stage scale, and the window size
that gives one is not the stage size: the stage takes 75% of the window's width,
so `--stage 854,640` yields 641x480, a fractional 1.0016, and comparing that
against a 640x480 render reports 38% of the stage differing -- all of it the
capture, none of it the renderer. `--stage 1707,1280` yields exactly 1280x960;
sample the top-left of each 2x2 block. Always check the content bounding box
first.

Reproduce:

```
godot --path . --script tools/scene_probe.gd -- --root piposh --movie PIANO.dir \
    --frame 37 --settle 2 --ticks 0 --hold --stage 1707,1280 --quiet --out /tmp/prev.png
godot --headless --path . --script tools/director_render.gd -- --root piposh \
    --file PIPDATA/PIANO.dir --frame 37 --out /tmp/rend.png
```

`/tmp/prev.png`'s stage sits at (213,160) at scale 2. The three rulings about this
room that *are* closed are `docs/bugs-closed.md` 72.

---

## 80. An expanding field still clips, because no path pushes its laid-out height back onto the sprite

> **Re-verified 2026-08-14: unchanged, and the entry is accurate in every
> particular.** `text_and_shapes --root piposh --file PIPDATA/CAPROOM.dir` still
> prints `memowrite  1 lines, 14pt, box (7,383) 277x85` verbatim, with `memo21` at
> `290x134` showing the fixed/scroll arm working. `_field_size` still returns
> `natural` for `BOX_ADJUST` and `BOX_LIMIT`, `director_text.gd:layout` still
> returns on the first line past the box bottom, and `size_from_script` is still
> the only path that sticks a size.
>
> **The blocker is confirmed real and is the reason this is still open**:
> `drawn_size(sprite, member)` is static and has no access to the runtime text,
> which lives in the host's `_field_text` overrides. The write-back vehicle has to
> be stamped onto the effective sprite in `director_preview.gd:_effective`, and it
> should land in one commit with the layout change for the reason the entry gives.

**Status:** open, and it is the **remaining half** of `DIRECTOR_ENGINE.md` §1.2 ·
**Area:** `scenes/preview/sprite_geometry.gd:_field_size`,
`director/director_text.gd:152`, `scenes/preview/text_art.gd:paint` · found
verifying monday 12752286416

`castmember/text.cpp:createWidget` sizes a field's widget from the score's rect —
`sprite.cpp:627-632` skips `kCastText` when it resets a sprite's dimensions, so
that rect survives as the bbox — and then `channel.cpp:774-779` writes the widget's
size back onto the sprite. Three box types, three rules:

```
adjust(0)           MIN(bbox, initialRect), then the widget may expand
fixed(2)/scroll(1)  MAX(bbox, MAX(initialRect, maxHeight)), never expands
limit(3)            bbox unchanged, then the widget may expand
```

**The fixed and scrolling arm is implemented** (this entry's commit); the two arms
that expand are not, because the port has nowhere to push a laid-out height back
to. `director_text.gd:152` returns on the first line whose top reaches the box
bottom, so overflow clips, and `text_art.paint` draws into the rect it is handed
without reporting what it laid out.

**The two halves cannot land separately, and that is the finding.** `createWidget`'s
own comment is "for mactext, we can expand now, but we can't shrink", and
`createWindowOrWidget` hands it a `maxWidth` of the member's width plus borders to
expand into — so the MIN is a *starting* size, not an answer. Implementing it alone
clamps every expanding field to whatever the score last left on the channel:
measured over `piposh`, **5,677 of 12,622 `adjust` records would draw smaller than
they do today**, and the clearest one is `GlobalMoney`, the 102x19 member every room
records as 68x32 residue — which is exactly the regression `9d1b23d2` fixed.

What is actually lost today: **16 sprite records over two members**, `save2`
(`limit`, where the line dropped is a trailing empty one) and `memo21`. So the
player-visible cost is small; the reason to do it is that `text_focus.gd` now makes
fields editable, and typing past the box in `CAPROOM.dir`'s `memowrite` (`fixed`,
277x85) clips with no growth. **Unverified:** no probe measures text Lingo writes at
runtime.

The vehicle would need to be a new one. `size_from_script`
(`scenes/preview/channel.gd:429`) is the only existing path that makes a size stick,
and it means "a script resized this" — a field growing because its text got longer
is a different cause and conflating them would make `drawn_size` unable to tell them
apart.

Reproduce:

```
godot --headless --path . --script tools/text_and_shapes.gd -- --root piposh --file PIPDATA/CAPROOM.dir
godot --headless --path . --script tools/text_and_shapes.gd -- --root piposh --file PIPDATA/MAINMENU.dir
```

`memowrite` reports `1 lines, 14pt, box (7,383) 277x85`; a `save2` box reads 19px
tall against a member whose stored `text_height` is 38.