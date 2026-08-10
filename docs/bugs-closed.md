# Resolved bugs and closed engine gaps

Nothing here is open. `bugs.md` is the live list; this file is where an entry goes
once its defect is fixed, so that the numbers keep resolving. Around twenty source
comments cite `bugs.md <n>` by number, and several of those numbers are here.

Entries keep the number they were filed under. Where an entry was only partly
resolved, the fixed half is here and the remainder is still in `bugs.md` under the
same number.

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

**`bugs.md` 16 was dodged here, not avoided.** `the number of member "bagopen" of
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

