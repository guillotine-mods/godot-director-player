---
name: director-data-recovery
description: Use when extracting playable data from a Macromedia Director game - VISE installers, ProjectorRays chunk dumps, cast members, bitmaps, film loops, text fields, member names, or the score's sprite-to-behaviour mapping. Read before parsing any Director binary, and read the version warning before copying an offset.
---

# Recovering data from a Director game

The Piposh 2 pipeline, and the traps that cost the most time. Written to be reused
for another Director title.

## Version first, before anything else

**Every binary offset here is Director 7.** Read the `VERS` chunk of one file
before trusting a byte:

    xxd -l 32 <dump>/<NAME>/<NAME>/chunks/VERS-*.bin

Piposh 2 reports 7. An older title will differ, and the score format in particular
changed across versions. These D7 constants must be re-derived, not copied:

    MAIN_CHANNEL_SIZE   = 288    # tools/director_film_loops.py
    SPRITE_CHANNEL_SIZE = 48
    MAX_D7_SPRITE_CHANNELS = 200
    CHANNEL_BIAS = 5             # tools/dump_sprite_scripts.py

Re-derive by validating against something already known. The Piposh 2 sprite-script
extractor does this: ten known inventory-drop behaviours must land on the eight
inventory slot channels, which pins the channel bias. Find an equivalent anchor
before believing a parse.

## Getting the files

The Windows release is a MindVision VISE self-installer. The directory is
readable (`tools/list_vise_archive.py` decodes it) but payloads use VISE's own
compression, so the practical route is running the installer on Windows and
copying out the `.DXR` / `.DIR` movies and `.CXT` / `.CST` casts. Audio is usually
a large fraction of the archive and often already converted — check before asking
anyone to ship hundreds of megabytes.

Then run ProjectorRays over each file for a chunk dump plus decompiled Lingo.
Expect the layout `<root>/<NAME>/<NAME>/chunks`, with casts under `casts/`.

## Chunk map

| chunk | holds | notes |
|---|---|---|
| `CAS_` | int32[] of CASt resource ids | index = member number − 1 |
| `CASt` | int32 type, infoLen, specificLen, then info | type at offset 0 |
| `BITD` | bitmap image data | decode to BMP |
| `SCVW` | a film loop's mini-score | one per film-loop member |
| `STXT` | text member contents | fields: inventory, task lists, data tables |
| `KEY_` | (section, owner, fourCC) triples | joins a member to its chunks |
| `VWSC` | the score | frame deltas, then frame intervals |
| `Lscr` | compiled Lingo | ProjectorRays decompiles these |

`CASt` member types: 1 bitmap, 2 filmLoop, 3 field, 4 palette, 5 picture,
6 sound, 7 button, 8 shape, 9 movie, 10 digitalVideo, 11 script, 12 richText,
13 OLE, 14 transition.

## Traps, each of which cost real time

**Endianness varies per file.** One movie is big-endian, its shared cast
little-endian. Try both and keep whichever yields sane values.

**A `CASt` info block yields script source for members that carry a script.**
Sixteen Piposh 2 master members parsed as `"  global soun"` or `"on mou"` instead
of names. That matters because generic handlers identify what was clicked by
member name, so a wrong name silently disables a whole mechanism.

Take names from ProjectorRays filenames instead — but **only `CastScript N - name`**.
A `CastScript` is named after the member that owns it; a `BehaviorScript` is named
after the behaviour. Trusting all script filenames renamed master member 54 from
`piphead1` to `ex_tx`. See `tools/add_cast_script_names.py`, which is additive and
only replaces a stored name that is unmistakably source text.

**Text members join to their `STXT` by resource id, and a dump can hold more than
one copy of a cast whose ids disagree.** Widening a cast scan to pick up more
member names silently emptied the shared cast's fields. Keep name extraction and
text extraction on separate paths — `dump_fields.py` has `chunk_dirs()` for text
and `name_only_dirs()` for names, deliberately.

**Shapes are not missing art.** Director shape members are how this game does
invisible hotspots, all with `filled=0`. A coverage checker that treats every
non-bitmap as unresolvable reported 222 missing members when 13 were real: 149
shapes, 59 behind a cast-name alias, one text member. Classify member types before
counting anything as missing.

**Cast-library names are not unique and not stable.** One movie links the same
cast file twice under two names. Resolve by path stem, not by name.

## What the score gives you that sprite records do not

Sprite records do not say which script is attached. `VWSC` carries frame intervals
after the delta stream, and each interval names its behaviour script. That mapping
is the whole attachment mechanism — see `tools/dump_sprite_scripts.py`. Without it
a port has to guess which script a hotspot runs.

## Validate, then trust

Piposh 2's checks, worth reproducing in shape:

- every decompiled script parses (3349/3349)
- known member names come out right (`piphead1`, `object0`, `sciser`, `sulam`)
- known field contents look right (an inventory of `empty` lines, a numeric score)
- every referenced linked cast member resolves to a bitmap, film loop or a
  classified non-drawing type, with counts printed per category

Exit non-zero while anything is unresolved so it can gate a build.
