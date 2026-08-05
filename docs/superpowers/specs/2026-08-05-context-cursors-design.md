# Context-sensitive cursors

The original changes the mouse cursor by what is under it: walking legs over the
floor, a magnifier over searchable scenery, arrows over exits, a hand over a held
inventory item. None of that reaches the port. This restores it from the original
scripts and the original art.

## What the original does

`MASTER/External/MovieScript 13 - cursor funk.ls` assigns cursors per *channel*,
not per hotspot:

| channel | cursor | meaning |
|---------|--------|---------|
| 2 | `wlkcur` | the floor, walkable |
| 7, 8, 9 | `magni` | searchable scenery |
| 10, 11, 12, 13 | `leftcur`, `rightcur`, `downcur`, `upcur` | exits |
| 14 | `trgcur` | target |
| 103-110 | `hand` | occupied inventory slots, set by each room's init |

It gates on `the movieName contains hotel / day1 / sea / night1 / air`, so this is
the walking game. The minigames set their own (`cc1`/`cc2`/`cc3` in CHESS, `trgcur`
on the joke targets in `MASTER/External/MovieScript 12 - jokes funk.ls`).

`set the cursor of sprite N to [1, 1]` appears 104 times and is the author's idiom
for "back to the default arrow". The `.lasm` confirms a literal two-element list, so
it is not a decompiler artifact. Member 1 is not a valid cursor in any of these
casts, so Director falls back to the arrow. The port reads `[1, 1]` as "no cursor"
and lets arbitration fall through to the channel below.

## Three blockers

1. `cursorfunk` is stubbed as a no-op in `lingo/lingo_host.gd:568`, alongside
   `alert` and `beep`. The real handler never runs.
2. The interpreter already records `set the cursor of sprite N` into
   `SpriteChannel.cursor` (`lingo/lingo_host.gd:288`). Nothing reads it.
3. The art is wrong in `assets/render_model/`. `cast_0010.bmp`, which is `wlkcur1`,
   is 5x6 pixels of colour noise.

Only the third is a data problem, and it is the one that decides the shape of this
work.

## The decode bug

Director's CASt chunk for a bitmap member carries, after the
`(type, common_size, specific_size)` header and the common block, a `u16` pitch
followed by a **signed** `i16` rect as top, left, bottom, right. The pitch's 0x8000
bit is the depth flag: set means 8 bits per pixel, clear means 1. The low 15 bits
are the row stride in bytes.

The upstream exporter recorded that high byte as `bpp_marker` and then ignored it,
reading every member as 8-bit and inferring geometry from the decoded byte count.
It is right for 8-bit members and wrong for every 1-bit member. Measured over the
26 movies with a local chunk dump: 5,751 members correct, 176 wrong.

| member | true rect | stride | chunk | exporter said |
|--------|-----------|--------|-------|---------------|
| `wlkcur1` | 13 x 17 | 2 | 34 = 17 x 2 | 5 x 6 |
| `upcur1` | 15 x 16 | 2 | 32 = 16 x 2 | 12 x 13 |
| `upcur2` | 15 x 16 | 2 | 32 = 16 x 2 | 21 x 22 |
| `trgcur1` | 17 x 17 | 4 | 68 = 17 x 4 | 24 x 26 |
| `standright9` | 80 x 256 | 80 | PackBits | 80 x 256, correct |

1-bit members here are stored raw, not PackBits: the chunk length equals
`stride * height` exactly. 8-bit members are PackBits unless the chunk already
matches `stride * height`.

Three format facts are already established by measurement in
`Piposh2-Port/spike/bitd-export/src/main.rs:15-22` and are not re-derived here:
BITD is PackBits with a residue of small 1-bit rasters stored raw; the CASt
`(type, common_size, specific_size)` header accounts for all 16,799 payloads, type
1 being bitmap; and rect coordinates are signed, nonsense if read unsigned.

## Where the fix goes

The exporter that produced `assets/render_model/` is not on this machine.
`assets/SOURCE.txt` records it as a robocopy from `E:\games\piposh2\reports\` on a
Windows box. `Piposh2-Port` is a separate migration effort whose `bitd-export` is a
declared disposable spike, emits a different format, and has no palette;
`~/Projects/_private_projects/piposh2/` is a third repo and not it either.

So the general fix lands here, as a repair pass over the exported assets, driven by
the raw chunks which *are* local. The upstream exporter stays wrong, which is
recorded in `bugs.md` so a future re-export from Windows does not silently clobber
the repair.

### Tier one: the 26 dumped movies

`tools/repair_1bit_members.py` walks every `assets/render_model/*/members.json`,
reads the matching `CASt-<cast_resource_id>.bin` and `BITD-<bitd_resource_id>.bin`
from `Piposh2-Port/originals/recovery/web-alpha/decompiled_chunks/`, and for every
member whose pitch flag says 1-bit, rewrites the BMP at the true rect and corrects
the geometry and registration point in `members.json`.

Of the six movies carrying cursor members, AIR1, DAY1, HOTEL1 and SEA1 are dumped.
NIGHT1 and ENDMOVI4 are not. Every cursor member is byte-identical across all four
dumped movies, verified by SHA over the raw chunks, so those two resolve by member
name against a dumped movie. That is a fallback with a check behind it, not a
guess, and the tool refuses the substitution if the four sources ever disagree.

### Tier two: deferred

The remaining 62 movies have their `.DXR` originals under
`Piposh2-Port/originals/recovery/web-alpha/PIP2DATA/` but no pre-dumped chunks.
Reaching them needs imap/mmap container traversal. Not required for cursors, and
scoped as follow-up work rather than done here.

## The engine

`DirectorRuntime.cursor_at(stage_pt)` walks visible channels from highest to
lowest, returning the first whose `SpriteChannel.cursor` is set and whose
`sprite_contains` covers the point. Two deliberate choices:

It iterates **all** visible channels, not `clickable_sprites()`. That filter keeps
only sprites with lifted `on_click` data or a Lingo `mouseUp` handler, and channels
7 to 9, the searchable scenery, mostly have neither: what they do lives in MASTER's
`searchfunk`. Filtering would kill the magnifier outright.

It reuses the existing `sprite_contains` rect rather than per-pixel matte testing.
Director's own rollover respects ink, so this is marginally less faithful at the
edges of irregular sprites. It is the right trade anyway: a cursor that promises a
click the click handler will not honour is a worse bug than a generous hitbox, and
sharing one hit test guarantees the cursor and the click agree.

`cursorfunk` comes out of the ignored-builtin list so the original handler runs and
makes the assignments itself. No cursor table anywhere in the port.

## Presentation

`RenderModelLoader.cursor_texture(data_member, mask_member)` composes the pair into
RGBA: mask bit clear is transparent, otherwise the data bit selects black or white.
The pair order in Lingo is `[data, mask]`, confirmed by `wlkcur2` being the filled
silhouette of `wlkcur1`. Hotspot is the data member's registration point from CASt.
Textures are cached per pair and re-scaled nearest-neighbour when the upscale
factor changes.

Mouse uses `Input.set_custom_mouse_cursor` with the scaled texture, applied when
the arbitrated pair changes. Gamepad hands the same texture to the existing
`%VirtualCursor` in `director/movie_player.gd:19`. One arbitration, two
presentations, each right for its input.

The `hand1`/`hand2` substitution in `director/movie_player.gd:103-116`, which
stands in `Control.CURSOR_POINTING_HAND` because the cast pair would not decode, is
removed. Its comment describing the decode failure is what this spec fixes, and the
comment's own premise needs correcting with it: it asserts "a Director cursor cast
pair is 1-bit 16x16", which is what makes the observed 5x6 and 8x8 look like a
decode failure with no recoverable geometry. `hand1` and `hand2` are both 15 x 17.
Director cursor members here are arbitrary rects at a byte-aligned even stride, not
the classic 16 x 16 Mac cursor.

## Verification

`tools/verify_1bit_members.py`, pass/fail: every repaired member's chunk length
equals `stride * height` derived from its own CASt rect, and every named cursor
member's rewritten `members.json` geometry equals that same CASt rect.

`tools/cursors.gd`, pass/fail, asserting the player-visible invariant rather than
that a setter and a getter agree: in DAY1, a point over channel 11 arbitrates to
`rightcur1`/`rightcur2`, a point over channel 8 to `magni1`/`magni2`, and a point
over an empty inventory slot to no cursor.

Unstubbing `cursorfunk` is the risk in this change, not the cursors. The handler
also puppets sprite 93, sets its member to `day<N>`/`night<N>`, calls `tlkpath` and
`soundspath`, and sets sound 2's volume to 130, all of which go live. So `smoke.gd`,
`collectables.gd`, `puppet_visibility.gd`, `room_names.gd` and `sprite_channels.gd`
run before and after, stashed, and `lingo_walk_diff.gd` is compared row by row
rather than by total. Read `porting-fidelity-verification` before believing any of
those numbers: agreement with the lifted export falls as the port becomes more
faithful, so a number moving down is not by itself a regression.

## Assumptions

`[1, 1]` means "no cursor". Consistent with its use next to `sprite(N).visible = 0`
and with member 1 being invalid cursor art in every cast, but not confirmed against
a running original.

Cursor art is identical across movies, so NIGHT1 and ENDMOVI4 may borrow. Verified
by SHA across the four dumped movies; the tool fails rather than substitutes if
that ever stops holding.
