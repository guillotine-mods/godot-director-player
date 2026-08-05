# Director version of Piposh 2 (task 2.1)

Read-only investigation. Source data: `~/Downloads/piposh2extracted/piposh2-data/`
(86 RIFX files, verified byte-correct against the installer manifest). Probe script
was throwaway Python in the session scratchpad; nothing was added to `tools/`.

## Answer

**The game's movies and casts are Director 7.0.** Every file the game actually plays
reports config version `0x57E` -> `humanVersion()` 700, and a `VERS` chunk of 7.0.

**The score is *not* encoded in an older format.** `frames_version: 13` and
`sprite_record_size: 48` are exactly what a D7 movie writes. ScummVM dispatches
sprite-record layout on the *config* version, never on `framesVersion`, and 48 is
`kSprChannelSizeD7`. The three sources do not disagree about the score format.

**ScummVM's 850 is not wrong either — it describes a different thing.** It is the
projector version, and two genuine Director 8.5 files ship at the install root
alongside `piposh2.exe`. They are not part of the game's movie set.

So the honest one-line answer is: **the movies are D7 (0x57E) and the score is D7
(48-byte sprite records); the 850 belongs to the D8.5 projector and the two
D8.5 files at the install root, not to any movie under `PIP2DATA/`.**

There is one real defect found, and it is not any of the three claimed conflicts:
**ScummVM hard-codes 120 displayed channels for these files, but 21 of the 60
movies declare 150, and `ENDMOVI1.DXR` actually writes sprite channel 150.**
See "The displayed-channel count is wrong" below — this is what blocks 5.6/6.6/8.4,
not the version number.

## How the version was read

`Cast::loadConfig` (`reference/scummvm/cast.cpp:363`):

- `cast.cpp:397-401` — if the config chunk is longer than 36 bytes, seek to **offset 36**
  and read an `int16`; that is `_version`.
- `cast.cpp:403-404` — `_len` at offset 0, `_fileVersion` at offset 2.
- `cast.cpp:406-407` — only if the chunk is <= 36 bytes does `_fileVersion` become `_version`.
- `cast.cpp:411` — `humanVersion(_version)`.

`humanVersion` (`reference/scummvm/util.cpp:1316-1346`) with the thresholds from
`reference/scummvm/types.h:362-378`: `kFileVer700 = 0x4C8`, `kFileVer800 = 0x582`,
`kFileVer850 = 0x6A4`, `kFileVer1000 = 0x73B`. So `0x57E` -> 700 and `0x73A` -> 850.
The two values are 442 apart; there is no ambiguity.

### Endianness — the trap, and how it was resolved

Two different endiannesses are in play *per file*, and they are not the same one:

| layer | rule |
|---|---|
| RIFX container (`imap`, `mmap`, chunk table) | `RIFX` magic = big-endian, `XFIR` = little-endian |
| movie-resource chunk payloads (`DRCF`, `VWSC`, `VERS`) | **always big-endian**, in both container kinds |

`reference/scummvm/archive.cpp` is not vendored in this repo, so the second rule was
established empirically rather than by citation. It is not a guess:
`configLenSanityCheck` (`cast.cpp:339-361`) requires `len` at offset 0 to be **84**
for a D6-D9 config chunk. Reading the `XFIR` files' `DRCF` payload little-endian
gives `len = 21504` (`0x5400`, i.e. 84 byte-swapped) and a nonsense movie rect of
`(15360, 4096, 7170, -28670)`. Reading the same bytes big-endian gives `len = 84`
and `strtgame.dxr`'s rect as `(60, 16, 540, 656)` — the game's real 640x480 stage,
matching `assets/render_model/AIR1/summary.json`. All 86 files yield `len = 84`
under the big-endian reading and only under it.

The repo already assumed this: `tools/dump_sprite_scripts.py:115-116` unpacks the
VWSC header with `">3i"` / `">4h"` unconditionally.

### Raw offsets

Example, `PIP2DATA/AIR1.DXR` (`RIFX`/`MV93`, big-endian container), `DRCF` chunk id
2619 at file offset `0x1251C`, chunk size 84. Payload starts at `0x12524`:

| payload offset | file offset | field | value |
|---|---|---|---|
| 0 | 0x12524 | `_len` | 84 |
| 2 | 0x12526 | `_fileVersion` | 0x163C (protected-file marker) |
| 4..11 | 0x12528 | movie rect (t,l,b,r) | 60, 16, 540, 656 |
| **36** | **0x12548** | **`_version`** | **0x057E -> v700** |

`_fileVersion` at offset 2 is `0x163C` in every `.DXR`/`.CXT`, which is the
"very high fileVersion means protected" case flagged at `cast.cpp:404`. Offset 36
is the only usable field in these files, which is exactly why `loadConfig` reads it.
In the two unprotected root files, offset 2 and offset 36 agree (`0x073A`).

## Per-file probe results (all 86 files)

| group | count | container | config @36 | `VERS` | `framesVersion` | `spriteRecordSize` | `numChannels` | channel-count field |
|---|---|---|---|---|---|---|---|---|
| `PIP2DATA/*.DXR` (59) + `strtgame.dxr` | 39 | BE (LE for strtgame) | `0x57E` v700 | 7.0 | 13 | 48 | 1006 | **120** |
| same set | 21 | BE | `0x57E` v700 | 7.0 | 13 | 48 | 1006 | **150** |
| `PIP2DATA/*.CXT` (23) + `PIP2DATA/MASTER.CST` | 24 | BE | `0x57E` v700 | 7.0 | (no `VWSC`) | - | - | - |
| root `MASTER.CST` | 1 | **LE** | **`0x73A` v850** | **8.5** | (no `VWSC`) | - | - | - |
| root `HEZSAVE.DIR` | 1 | **LE** | **`0x73A` v850** | **8.5** | 13 | 48 | 1006 | 120 |

Individually named probes:

| file | container | config @36 | `VERS` | `framesVersion` / `recSize` / `numChannels` | ch-count field | max byte written |
|---|---|---|---|---|---|---|
| `PIP2DATA/DAGI.DXR` | BE | 0x57E v700 | 7.0 | 13 / 48 / 1006 | 120 | 2400 |
| `PIP2DATA/BLACK.CXT` | BE | 0x57E v700 | 7.0 | no score | - | - |
| `PIP2DATA/AIR1.DXR` | BE | 0x57E v700 | 7.0 | 13 / 48 / 1006 | 120 | 5592 |
| `PIP2DATA/ENDMOVI1.DXR` | BE | 0x57E v700 | 7.0 | 13 / 48 / 1006 | **150** | **7464** |
| `PIP2DATA/MASTER.CST` | BE | 0x57E v700 | 7.0 | no score | - | - |
| `strtgame.dxr` | **LE** | 0x57E v700 | 7.0 | 13 / 48 / 1006 | 120 | 1320 |
| `MASTER.CST` (root) | **LE** | **0x73A v850** | **8.5** | no score | - | - |
| `HEZSAVE.DIR` (root) | **LE** | **0x73A v850** | **8.5** | 13 / 48 / 1006 | 120 | 336 |

`VERS` layout was inferred (`uint16` major at payload offset 4, minor at offset 6),
not read from a ScummVM function — `VERS` is not parsed in the vendored subset. It
is trustworthy here because it partitions the 86 files into exactly the same two
groups as `DRCF@36`, with 7.0 <-> `0x57E` and 8.5 <-> `0x73A`, with no crossover.

**No movie disagrees with any other movie.** The version is uniform across all 60
movies and all 24 casts under `PIP2DATA/`.

### The two D8.5 files are duplicates/companions, not game movies

`MASTER.CST` exists twice, and the copies are not identical:

| | `PIP2DATA/MASTER.CST` | `MASTER.CST` (root) |
|---|---|---|
| md5 | `babe4de26d32376b05b6b79ca7a0f04c` | `7bf151816ed2689e8299170e8db1397a` |
| size | 471.8K | 470.5K |
| container | `RIFX` big-endian (Mac) | `XFIR` little-endian (Windows) |
| version | 0x57E / v700 / `VERS` 7.0 | 0x73A / v850 / `VERS` 8.5 |
| mmap entries | 816 | 816 |

Same chunk count, different byte order and version: the root copy is a Windows
Director 8.5 re-save of the Mac D7 cast. All 60 movies name their shared cast as
`macintosh hd:pip2 full:master.cst` (from `assets/render_model/*/summary.json`
`cast_libs`), a Mac path, so the movies were authored on Mac against the D7 copy.
`HEZSAVE.DIR` is a 32-frame D8.5 movie (`framesStreamSize` 496, max byte written 336).

That the D8.5 artefacts sit at the install root next to the projector, while nothing
under `PIP2DATA/` is D8.5, is consistent with a D8.5 Windows launcher/save layer
wrapped around a D7 Mac-authored game. That last sentence is interpretation; the
version numbers and md5s above are measured.

## Reconciling the three sources

### 1. ScummVM detection table: 850 — refers to the projector

`reference/scummvm/detection_tables.h:10440` fingerprints `piposh2.exe` and passes
`850` as the last macro argument. Following the macro:

- `detection_tables.h:2025` — `WINGAME2_l(t,e,f1,m1,s1,f2,m2,s2,l,v)` -> `GENGAME2_(..., v)`
- `detection_tables.h:1973` — `GENGAME2_` expands to `{ { ...ADGameDescription... }, GID_GENERIC, v }`,
  so `v` is the third member of `DirectorGameDescription`.
- `reference/scummvm/director.cpp:61` — `_version = getDescriptionVersion();`
- `reference/scummvm/debugger.cpp:265` — prints it as "Expected Director version".

The fingerprinted file is the **executable**, so 850 describes the projector, not
the movies. This is directly corroborated by the two real D8.5 files at the install
root — ScummVM's 850 is *correct*, it just isn't a statement about `PIP2DATA/`.

**Correction to the task premise:** the claim that the same `t:` hash appears on
piposh1, piposh2 *and* piposh3d is half wrong.

| entry | line | file | `t:` hash | size |
|---|---|---|---|---|
| piposh1 | `detection_tables.h:10437` | `piposh.exe` | `9d33c0d6a4cfb70c33f87f6e8a1f23fd` | 5665996 |
| piposh2 | `detection_tables.h:10440` | `piposh2.exe` | `9d33c0d6a4cfb70c33f87f6e8a1f23fd` | 5665996 |
| piposh3d | `detection_tables.h:10444` | `piposh3d.exe` | `4dfd8c52d8cff6d1b7a9435a966f4e78` | 5427592 |
| piposhdream | `detection_tables.h:10446` | `dream.exe` | `786558a29a117ff446a2419df3fa6756` | 5120988 |

Only piposh1 and piposh2 share it — identical hash and identical size under two
different filenames, which is strong evidence of one shared projector build.
piposh3d has a different hash and is annotated "Only launcher is Director. Actual
game uses 3D GameStudio / A5 engine". The underlying point stands and is
strengthened: the 850 describes a shared launcher/projector, and Hed Arzi reused
one D8.5 projector across at least two titles whose content is older.

**Consequence for the runtime, and it is not cosmetic.** ScummVM keeps *both*
numbers live at once, and they never converge:

- `cast.cpp:630-633` — `if (humanVer > _vm->getVersion()) _vm->setVersion(humanVer);`
  This only ever **raises** the engine version. Seeded at 850 from the detection
  table, loading a v700 movie never lowers it.
- So `g_director->getVersion()` stays **850** for the whole session and gates Lingo
  builtins, `the` properties, and auto-puppet.
- Meanwhile `Cast::_version` -> `Movie::_version` (`movie.cpp:266`) ->
  `Score::loadFrames(*r, _version)` (`movie.cpp:338`) -> `Score::_version` is
  **700**, and gates score/sprite binary layout and tempo decoding.

A port must model this as two separate numbers. Using 700 everywhere or 850
everywhere both diverge from ScummVM.

### 2. The `director-data-recovery` skill: "Director 7" — correct

`.claude/skills/director-data-recovery/SKILL.md:13` says every offset is Director 7
and Piposh 2's `VERS` reports 7. Confirmed: `VERS` is 7.0 in all 84 game files, and
`DRCF@36` is `0x57E` -> v700. The pinned constants check out against ScummVM
`reference/scummvm/frame.h:61-62`:

- `MAIN_CHANNEL_SIZE = 288` == `kMainChannelSizeD7 = 288` ✓
- `SPRITE_CHANNEL_SIZE = 48` == `kSprChannelSizeD7 = 48` ✓
- `MAX_D7_SPRITE_CHANNELS = 200` — not a format constant, an over-allocation cap.
  It is safe (200 > the real 150) but it is not the displayed-channel count and
  must not be used as one. See below.

The skill is right. Its only weakness is that it says "Piposh 2 is D7" without
saying "the projector is D8.5", which is what makes ScummVM's table look wrong.

### 3. `frames_version: 13` / `sprite_record_size: 48` — consistent with D7, not a conflict

Both values were read from the file, not invented by the exporter:
`tools/dump_sprite_scripts.py:116` does `struct.unpack(">4h", stream[12:20])` on the
VWSC header. This probe re-read them independently from raw bytes and got the same
values, so they are genuine data.

In ScummVM's frame loader:

- `score.cpp:1971-1975` — after the D6+ prelude, the VWSC header is
  `framesStreamSize` u32, `frame1Offset` u32, `numOfFrames` u32, then
  `framesVersion` u16, `spriteRecordSize` u16, `numChannels` u16.
- `frame.cpp:115-129` — `Frame::readChannel` dispatches on the **`version` argument**,
  which is `Score::_version` (the config version, traced above), **never on
  `_framesVersion`**. v700 lands in `readChannelD7` (`frame.cpp:126`,
  `frame.cpp:1568`), which uses a 288-byte main-channel block and 48-byte sprite
  records.
- The file's `spriteRecordSize` of 48 therefore *agrees* with the config version:
  48 == `kSprChannelSizeD7` (`frame.h:62`). A D6 movie would have written 24
  (`kSprChannelSizeD6`).
- `numChannels` = 1006 in every file = 1000 sprite channels + 6 main channels,
  which is the D7+ maximum. D6 capped at 120.

`framesVersion` is used for exactly one thing: choosing the displayed-channel count
(`score.cpp:1977-1986`). It is **not** a format selector. `HEZSAVE.DIR`, which is a
genuine Director **8.5** file, also reports `framesVersion` 13 / `spriteRecordSize`
48 — so 13 is simply what D7 through D8.5 write. It carries no information that
contradicts 700.

So the "score written in an older format than the header claims" hypothesis is
**not** what is happening here. Header and score agree.

## The displayed-channel count is wrong in ScummVM — and this is the real finding

`score.cpp:1976-1986`:

```
if (_framesVersion > 13) {
    _numChannelsDisplayed = _framesStream->readUint16(); // Up to 500
} else {
    if (_framesVersion <= 7)    // Director5
        _numChannelsDisplayed = 48;
    else
        _numChannelsDisplayed = 120;    // D6
    _framesStream->readUint16(); // Skip
}
```

Because `framesVersion` is 13, ScummVM takes the else branch and hard-codes 120,
**skipping** the `uint16` that immediately follows `numChannels`. That skipped field
was read here for all 60 movies:

- 39 movies declare **120**
- 21 movies declare **150**

Walking every frame's channel deltas (each frame: `uint16 frameSize`, then
`(uint16 channelSize, uint16 channelOffset)` pairs, per `score.cpp:2262-2285`) and
taking the maximum `channelOffset + channelSize` gives the highest byte the score
actually touches. The 1-based sprite channel that byte falls in is
`floor((maxByte - 1 - 288) / 48) + 1`.

| file | declared field | max byte written | `(maxByte-288)/48` | top sprite channel | fits in ScummVM's 120? |
|---|---|---|---|---|---|
| `ENDMOVI1.DXR` | 150 | 7464 | 149.5 | **150** | **no** (limit 288 + 120*48 = 6048) |
| `HOTEL1.DXR` | 120 | 6024 | 119.5 | 120 | yes, exactly |
| `DAY1.DXR` | 120 | 6024 | 119.5 | 120 | yes, exactly |
| `MURDER1.DXR` | 120 | 5976 | 118.5 | 119 | yes |
| `SHUFFLE.DXR` | 120 | 5736 | 113.5 | 114 | yes |
| `TOFIRCPT.DXR` | 150 | 5640 | 111.5 | 112 | yes |

This was then checked exhaustively rather than by inspecting the top few. Grouping
all 61 score-bearing files (60 movies + `HEZSAVE.DIR`) by their declared field and
taking the maximum byte written *within each group*:

| declared field | files | max byte written in group | top sprite channel in group |
|---|---|---|---|
| 120 | 40 (39 movies + `HEZSAVE.DIR`) | 6024 | **120** |
| 150 | 21 | 7464 | **150** |

`ENDMOVI1.DXR` is the **only** file in the whole set whose score exceeds byte 6048.

Two things follow:

1. The skipped `uint16` **is** the displayed-channel count. Across all 40
   `120`-declaring files the highest byte written is 6024, landing exactly on
   channel 120 and never past it; across the 21 `150`-declaring files the highest is
   7464, landing exactly on channel 150. Each group saturates its declared value and
   neither overruns it. The field predicts the data exactly; ScummVM's constant does
   not.
2. **The port must read the field, not copy ScummVM's 120 and not copy the skill's
   200.** 120 truncates `ENDMOVI1.DXR`; 200 over-allocates and would make any
   "channel N is off the end of the score" check useless. The correct value is
   per-movie: `uint16` at VWSC-header offset 18.

`MAX_D7_SPRITE_CHANNELS = 200` in `tools/director_film_loops.py:12` is fine as a
buffer size (200 >= 150) but must not be reused as the channel count.

## Answers to the three downstream questions

- **Tempo encoding** — `Score::_version` is 700, so `score.cpp:541` (`_version < kFileVer600`)
  is false and the **D6+ sentinel path** (`score.cpp:586-622`) applies:
  255 = wait for sound channel 1, 254 = wait for sound channel 2, 248 = wait for
  click, 247 = delay of `tempoCuePoint` seconds, 246 = set FPS to `tempoCuePoint`.
  `_mainChannels.tempoCuePoint` is the operand for 255/254 (-1 next, -2 end, else a
  specific cue point) and for 247/246.
  **Note for 5.6:** in this branch there is no FPS-by-value case. The final `else`
  (`score.cpp:617-621`) treats *every* other tempo value as "wait for the digital
  video in channel `tempo`" — a plain `tempo` of, say, 12 becomes a video wait on
  channel 12, not 12 fps. Only 246 sets the frame rate. That is what the vendored
  ScummVM does; it was not cross-checked against Director's documented behaviour, so
  validate it against a real movie before porting it verbatim. The pre-D6 scheme
  (`tempo >= 256 - maxDelay` for delay, `tempo == 128` wait-for-click, `135`/`134`
  sound waits, `136..135+n` video waits) does **not** apply. Both 700 and 850 give
  the same answer here, so the projector/movie split does not matter for tempo.
- **Displayed channels** — per-movie, from the VWSC header: 120 for 39 movies,
  150 for 21. Not a single constant. See the section above.
- **Auto-puppet on property assignment** — `sprite.cpp:465-468`:
  `if (_puppet || g_director->getVersion() < 600) return;`. This reads the **engine**
  version, which is 850 here (seeded from the detection table, never lowered), so
  auto-puppet applies. It would also apply under 700. The gate passes either way;
  no ambiguity blocks this.

## Confidence

**High** on the version numbers. `DRCF@36`, the `VERS` chunk, and
`configLenSanityCheck`'s `len == 84` all agree across all 86 files, under a byte
order that is forced by the sanity check rather than chosen. The `0x57E`/`0x73A`
split is far from any `humanVersion` boundary.

**High** on "the score is D7-encoded, not older": `spriteRecordSize` 48 and
`numChannels` 1006 are read from the file and are D7 values, and `Frame::readChannel`
demonstrably dispatches on the config version.

**High** on the 120-vs-150 channel finding: it is backed by walking the actual frame
deltas of all 61 score-bearing files, not a sample. Each declared-value group
saturates its own value exactly (120 -> byte 6024, 150 -> byte 7464) and no file
overruns its declaration.

**Medium** on the interpretation of the two root D8.5 files as a Windows
launcher/save layer. The md5s, versions and endianness are measured; the *role* is
inferred from their location and from the shared piposh1/piposh2 projector hash.

What would change the conclusion:

- Vendoring `reference/scummvm/archive.cpp` and finding that movie-resource chunks
  are **not** unconditionally big-endian would invalidate the LE-file readings
  (`strtgame.dxr`, root `MASTER.CST`, `HEZSAVE.DIR`). It would not touch the 84
  big-endian `PIP2DATA` files, so the D7 answer would survive.
- A `VERS` layout other than `u16 major @4, u16 minor @6` would remove the
  independent corroboration, leaving `DRCF@36` alone — still decisive, just
  single-sourced.
- Finding that `piposh2.exe` embeds a Director movie whose config version is 700
  would mean the 850 is a ScummVM cataloguing choice rather than the projector's own
  version. That was not checked; the executable was not probed.
