# Original Director source reference

Decompiled Lingo for every Piposh 2 movie and cast, plus the Director text-member
chunks. This is the **source of truth** the port is reconstructing. The exported
`assets/render_model/*/frames.json` (deleted) carried only what `lingo_nav.py` lifted out of
these scripts (nav, sounds, unconditional inventory add/remove); everything
conditional lives here and nowhere else.

Read this before inferring behaviour. Several entries in `data/movie_context.json`
carry a `confidence` field because they were guessed before this material was
available; prefer the Lingo over the guess.

## Layout

```
reference/lingo/<MOVIE>/<cast>/<ScriptType> <id>[ - name].ls     decompiled Lingo
reference/lingo/<MOVIE>/<cast>/<ScriptType> <id>[ - name].lasm   bytecode assembly
reference/chunks/<MOVIE>/STXT-<id>.bin                           Director text members
```

3349 scripts (`.ls` plus matching `.lasm`), 73 movies/casts, 321 text chunks.
Line endings normalised to LF. The `.lasm` files are kept as ground truth for when
a decompile reads oddly: ProjectorRays is a decompiler, not an oracle.

`MASTER` is the shared cast that owns the globals (`objectsfield`, `Dprocess`,
`points`) and the inventory HUD, so its 40 scripts matter far beyond their count.

## Provenance

Merged from two independent ProjectorRays runs over the same originals:

1. `guillotine-mods/Piposh2-Web-Alpha` (private, archived), trees
   `decompiled_true/`, `decompiled_chunks/` and `PIP2DATA/`. 6594 of the files here.
2. A fresh Windows run delivered as `piposh2-projectorrays.zip`, following
   `docs/EXTRACT_FROM_INSTALLER.md` step 3. Supplied the remaining 104 files,
   including all of `MASTER` and `HEZSAVE`, which run 1 had never dumped.

The two agree exactly: of 6432 files present in both, zero differ once CRLF is
normalised. Neither is a superset, which is why both were needed.

## Not here

- The original `.DXR` / `.CXT` / `.CST` binaries (141 MB). Committed privately in
  `Piposh2-Web-Alpha` under `PIP2DATA/`, and re-derivable from
  `~/Downloads/piposh2.exe` per `docs/EXTRACT_FROM_INSTALLER.md`.
- The non-text chunk dumps (139 MB of `BITD`, `CASt`, `VWSC`, …). Already
  processed into `assets/render_model/`.
- 13 shared casts (`DETECTIV`, `HOTEL`, `ISLAND`, `NIGHT`, `TOFI`, …) have no
  scripts. Verified: zero `Lscr` chunks. They are pure asset casts, not a gap.

## Regenerating

Needs ProjectorRays, a Windows binary (`tools/projectorrays-0.2.0.exe` in the web
repo, Wine on macOS), pointed at a `.DXR`/`.CST` with `--dump-chunks
--dump-scripts`. See `scripts/dump_movie_chunks.py` there. Note that run 1 dumped
`MASTER`'s chunks but not its scripts, so verify `casts/` is non-empty afterward.

## Key findings so far

Relevant to issue #1 (inventory selection and item-based puzzles):

- `lingo/MASTER/External/MovieScript 80 - displayobject.ls` — the HUD. Sprites
  103-110 map to `objectsfield` lines 1-8 (`line i - 102`). Occupied slots get
  `moveableSprite = 1` and a `hand1`/`hand2` cursor, so **items are dragged, not
  selected**. There is no selection state in the original.
- `lingo/MASTER/External/BehaviorScript 108.ls` (and 52, 93, 94, 97, 110, 111,
  128, 129, 135) — the drop handling. `mouseDown` stores the slot's home position
  in `objectxx`/`objectyy`; `mouseUp` tests `sprite the clickOn intersects
  <target>` (sprite 100 is Piposh's head and plays `pi<item>.aif`; 18-21, 36, 37
  are characters and route to `objecttalktime`; other per-room sprites are world
  objects, usually gated on `.visible = 1`), then always snaps the icon home.
  A wrong target therefore needs no failure branch: nothing intersects, the icon
  springs back, silence.
- `lingo/MASTER/External/CastScript 57 - invright.ls` / `59 - invleft.ls` — scroll
  the 30-line field through the 8 visible slots (`moveinv.aif`, `stukinv.aif` at
  the end). Neither this port nor the web one exposes items past line 8.
- `lingo/MASTER/External/MovieScript 78.ls` — `searchfunk`, table-driven off
  `field "searchinfo"` (name, x, y, action, sound family). This is the real
  version of the `click_flags` / `sprite_gates` guesses in `movie_context.json`.
- `lingo/DAY1/wonder/CastScript 218.ls` — canonical conditional: scan
  `objectsfield` for `sciser`, reveal sprites 15 and 17 with `found.aif` if
  absent, play `pbag.aif` if already held.
