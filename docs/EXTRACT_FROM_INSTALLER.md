# Recovering the game data from the Windows installer

The Piposh 2 Windows release (`piposh2.exe`, 328 MB) is a MindVision VISE
self-installer holding every Director movie and cast library the port needs. Its
directory is readable — `tools/list_vise_archive.py` decodes all 3235 records —
but the payloads use VISE's own compression, so the only practical way to get
the files out is to run the installer on Windows.

> **This recovery is done. Nothing here is outstanding work.**
>
> **It is also now reproducible without Windows.** `tools/extract_piposh2_data/`
> runs the installer under Wine in a container and copies the casts and movies
> out, so the manual Windows steps below are history rather than instructions:
>
> ```
> tools/extract_piposh2_data/run.sh ~/Downloads/piposh2.exe ~/Downloads/piposh2extracted/piposh2-data
> ```
>
> - The Lingo is committed at `reference/lingo/` (3349 scripts, 73 casts), with
>   the Director text members at `reference/chunks/`. See `reference/README.md`.
> - The extracted movies and casts, and the ProjectorRays chunk dump they were
>   decompiled from, are at `~/Downloads/piposh2extracted/` on the development
>   machine:
>
>   ```
>   piposh2extracted/piposh2-data/          90 files, 180 MB — see below
>   piposh2extracted/piposh2-projectorrays/ 420 MB chunk dump, layout <root>/<NAME>/<NAME>/chunks
>   ```
>
>   `piposh2-data/` holds:
>
>   ```
>   PIP2DATA/        83 — 59 .DXR, 23 .CXT, MASTER.CST
>   PIPOSH2.EXE      the game projector, 5665996 bytes; ScummVM needs it to detect the game
>   strtgame.dxr     the boot movie
>   MASTER.CST       a *different* file from PIP2DATA/MASTER.CST — see below
>   HEZSAVE.DIR
>   old_exe/         three superseded projector builds, kept only so nothing is silently dropped
>   ```
>
>   That dump is not in the repository, and is a generation-time input only. Pass
>   its `PIP2DATA` subdirectory as `--chunks-root`; it contains `MASTER` too, so
>   one root covers every cast.
>
> What follows is how the recovery was done, kept so it can be reproduced.

## What the installer holds

| Type | Files | Size | Why |
|------|------:|-----:|-----|
| `.CXT` / `.CST` cast libraries | 25 | 61 MB | Bitmaps and film loops for the linked casts. |
| `.DXR` / `.DIR` movies | 61 | 86 MB | Carry the original Lingo, which drives room conditions and day-to-day progression. |
| `.AIF` audio | 3141 | 432 MB | **Not needed** — already converted in `assets/audio`. |

Roughly **147 MB** to recover, not 593 MB.

## Step 1 — run the installer

Double-click `piposh2.exe` and let it install. Any destination is fine; note
where it goes. If Windows SmartScreen objects, it's a 1990s installer with no
modern signature — "More info" then "Run anyway".

When it finishes, the destination folder holds the game. The files we want are
the `.DXR` and `.CXT` ones, probably inside a `PIP2DATA` folder, with a few
loose in the root.

## Step 2 — send the files back

Zip **only** the casts and movies. In the installed folder, PowerShell:

```powershell
$dest = "$HOME\Desktop\piposh2-data"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Get-ChildItem -Recurse -Include *.CXT,*.CST,*.DXR,*.DIR |
    Copy-Item -Destination $dest
Compress-Archive -Path "$dest\*" -DestinationPath "$HOME\Desktop\piposh2-data.zip"
```

That produces one zip of about 147 MB. Send it back and stop here — everything
else happens on the Mac.

If PowerShell is awkward, sorting the installed folder by file type in Explorer
and dragging the `.CXT`, `.CST`, `.DXR` and `.DIR` files into one folder does the
same job.

`ISLAND2.CXT` (5,135,530 bytes) was once described as the single most valuable
file, on the grounds that 137 of 222 missing cast members were in it. That was
wrong: all 137 are Director shapes, the game's invisible hotspots, and they draw
nothing by design. See "What the 222 were" below.

## Step 3 (already done) — ProjectorRays

**This step has been completed and its output is in the repository at
`reference/`.** What follows is the recipe, kept for reproducing the dump.

If whoever is helping is comfortable with a command line, this step is worth
more than everything above, because it recovers the original Lingo.

ProjectorRays is an open-source Director decompiler; get a Windows build from
its GitHub releases. Point it at each extracted `.DXR` and `.CXT` so it writes a
chunk dump and decompiled `.ls` scripts:

```
projectorrays.exe <file>
```

Check `--help` for how it names output — the layout we consume is
`<root>/<NAME>/<NAME>/chunks`. Zip the whole output tree and send that too.

Without this step we still fix the missing characters. With it we also get
`peoplefunk` and the room-condition logic, which is the difference between
patching conditions one at a time and porting them wholesale.

Note that the first run dumped `MASTER`'s chunks but not its scripts, so verify
`casts/` is non-empty afterward. `MASTER` owns `objectsfield`, `Dprocess`,
`points` and the inventory HUD, so missing it hides the whole inventory system.

## Step 4 — verification, on the Mac

```
python3 tools/list_vise_archive.py ~/Downloads/piposh2.exe \
    --ext DXR CXT CST DIR --verify <unzipped dir>
```

Compares every recovered file against the size recorded in the installer
directory and exits non-zero if anything is missing or truncated, so a partial
extraction is caught rather than assumed good. `data/installer_manifest.txt`
holds the same expected list for reference.

**Pass `--ext`.** Without it the check demands all 3141 `.AIF` files, which are
deliberately not recovered per the table above, and reports ~3150 missing on a
perfectly good extraction. The remaining non-audio entries are `PIPOSH2.EXE`,
three superseded projector builds, an icon, a `.url` and a readme; only the
projector matters, and only for ScummVM, which needs it to detect the game.

### The two MASTER.CST files are genuinely different

The installer ships `MASTER.CST` twice and they are not copies: `PIP2DATA/MASTER.CST`
is 483,150 bytes and `MASTER.CST` at the root is 481,764. Reading their config
chunks settles it beyond doubt — the `PIP2DATA` copy is **Director 7** (config
`0x57E` at `DRCF` payload offset 36, big-endian RIFX container), the root copy is
**Director 8.5** (`0x73A`, little-endian XFIR). Same for `HEZSAVE.DIR`. The root
pair belongs with the D8.5 projector; the game's own cast is the one under
`PIP2DATA/`.

This mattered practically: `list_vise_archive.py --verify` used to resolve both
manifest entries to whichever copy `rglob` returned first, so one of them was
always checked against the wrong file. Fixed to accept any copy at the expected
size.

### Verifying against ScummVM's hashes

ScummVM's detection entry keys on two files, and **neither hash is over the whole
file**. Each is 5000 bytes, but *which* 5000 depends on the prefix in the table,
which is easy to miss:

| prefix | hashes | file here |
|--------|--------|-----------|
| `f:` | the **first** 5000 bytes | `PIP2DATA/AIR1.DXR` |
| `t:` | the **last** 5000 bytes | `PIPOSH2.EXE` |

```
head -c 5000 PIP2DATA/AIR1.DXR | md5     # cc6c9bb1acf76a0697a30d626e89543c, size 2119111
tail -c 5000 PIPOSH2.EXE       | md5     # 9d33c0d6a4cfb70c33f87f6e8a1f23fd, size 5665996
```

Get either one wrong and a correct extraction reports as a failure. For the
record: `AIR1.DXR` full-file is `909a55d5…` and its *tail* is `5187c5fb…`;
`PIPOSH2.EXE` full-file is `ccc1faae…` and its *head* is `c163f361…`. None of
those four match anything and none of them mean anything.

The projector's `t:` hash is shared with Piposh 1 (`detection_tables.h:10437`,
same hash and same 5665996 bytes), so it is a common launcher stub and cannot
identify the game on its own — disambiguation comes from the filename and from
`PIP2DATA/AIR1.DXR`. Piposh 3D does **not** share it; it has its own
`t:4dfd8c52…` at 5427592.

Then regenerate the cast registry and confirm the gaps closed:

```
python3 tools/generate_cast_registry.py --chunks-root <chunk dumps>
python3 tools/check_cast_coverage.py
```

`check_cast_coverage.py` exits 0 only when every referenced cast member resolves,
and reports the split so that classifying a member as non-drawing cannot quietly
stand in for resolving it.

## What the 222 were

The coverage tool once reported "222 referenced cast ids resolve to neither a
bitmap nor a film loop", and this document read that as 222 missing characters.
Decoding the `CASt` type field for each of them:

| | Count | |
|---|---:|---|
| Shape members | 149 | Not missing. Director shapes are this game's invisible hotspots: `island2` member 30 is a 63x402 rect, which is `DAY1` channel 10, the left-edge walk hotspot. Drawing nothing is correct, and shape rendering is deliberately not implemented. |
| `hezi1` | 59 | Not missing. `ISHDAY1` links `hezi.cst` twice, as `hezi` and as `hezi1`, and the registry lookup was by name. |
| Film loops | 13 | Genuinely missing, now recovered from the chunk dump. |
| Field member | 1 | `MASTER` member 10 is text. |

Only the 13 film loops were a content gap. They are in black, detectiv, hatuli,
heznigt, jokers and sabmon, and before recovery the characters they animate did
not appear at all: `DIVEFIGT` drew no divers.

The lesson worth keeping is that "member absent" and "member deliberately
non-drawing" looked identical to the tool. The registry now records the
difference in a `non_drawing` map.
