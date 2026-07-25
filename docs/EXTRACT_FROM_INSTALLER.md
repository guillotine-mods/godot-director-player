# Recovering the game data from the Windows installer

The Piposh 2 Windows release (`piposh2.exe`, 328 MB) is a MindVision VISE
self-installer holding every Director movie and cast library the port needs. Its
directory is readable — `tools/list_vise_archive.py` decodes all 3235 records —
but the payloads use VISE's own compression, so the only practical way to get
the files out is to run the installer on Windows.

This is written so someone with a Windows machine can do it without knowing
anything about the project. **Nothing needs installing, no Python, no build
tools.** Steps 1 and 2 are the whole job.

## What we need and why

| Type | Files | Size | Why |
|------|------:|-----:|-----|
| `.CXT` / `.CST` cast libraries | 25 | 61 MB | 222 characters and objects don't render because their cast members were never exported. They live here. |
| `.DXR` / `.DIR` movies | 61 | 86 MB | Carry the original Lingo, which drives room conditions and day-to-day progression. |
| `.AIF` audio | 3141 | 432 MB | **Not needed** — already converted in `assets/audio`. |

Roughly **147 MB** to send back, not 593 MB.

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

`ISLAND2.CXT` (5,135,530 bytes) is the single most valuable file: 137 of the
222 missing cast members are in it. If something goes wrong and only one file
can be recovered, make it that one.

## Step 3 (optional, and worth a lot) — ProjectorRays

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

## Step 4 — verification, on the Mac

```
python3 tools/list_vise_archive.py ~/Downloads/piposh2.exe --verify <unzipped dir>
```

Compares every recovered file against the size recorded in the installer
directory and exits non-zero if anything is missing or truncated, so a partial
extraction is caught rather than assumed good. `data/installer_manifest.txt`
holds the same expected list for reference.

Then regenerate the cast registry and confirm the gaps closed:

```
python3 tools/generate_cast_registry.py --chunks-root <chunk dumps>
python3 tools/check_cast_coverage.py
```

`check_cast_coverage.py` exits 0 only when every referenced cast member
resolves to a bitmap or a film loop.
