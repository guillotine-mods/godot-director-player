# Director Film Loops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export Director film-loop mini-scores into the shared cast registry and render their animated child sprites in Godot.

**Architecture:** A focused Python parser reads CASt, CAS, KEY, and SCVW resources from the available Director chunk dumps and attaches deterministic film-loop records to each canonical shared cast. `RenderModelLoader` exposes registry film loops and their bitmap children, while `DirectorRuntime` maintains a frame cursor per score channel and `MoviePlayer` expands each parent film-loop sprite into positioned child bitmap draws.

**Tech Stack:** Python 3, Director 7 chunk data, generated JSON, Godot 4.7 GDScript.

**Validation constraint:** Do not add or run automated tests. Use deterministic generation checks, static data probes, GDScript parsing, short Godot startup, and user visual verification.

---

### Task 1: Parse and generate film-loop registry data

**Files:**
- Create: `tools/director_film_loops.py`
- Modify: `tools/generate_cast_registry.py`
- Modify: `assets/render_model/cast_registry.json`

- [ ] **Step 1: Add the Director resource parser**

Implement `tools/director_film_loops.py` with:

- Big-endian helpers for Director integer fields.
- CAS parsing from `CAS_-*.bin`, mapping one-based member IDs to CASt resource IDs.
- KEY parsing with endian detection, mapping each CASt owner to its `SCVW` child resource.
- CASt type-2 parsing for the initial rectangle and flags.
- Director 7 SCVW score parsing using the persistent 288-byte main channel and 48-byte sprite-channel records.
- One exported record per valid film loop:

```json
{
  "cast_id": 98,
  "initial_rect": {"top": 13, "left": 62, "bottom": 172, "right": 146},
  "width": 84,
  "height": 159,
  "looping": true,
  "frames": [
    {
      "sprites": [
        {
          "channel": 6,
          "cast_id": 78,
          "start_x": 82,
          "start_y": 171,
          "width": 84,
          "height": 159,
          "ink": 8
        }
      ]
    }
  ]
}
```

Malformed resources must be skipped with a warning rather than aborting the complete registry generation.

- [ ] **Step 2: Integrate film loops with registry generation**

Add `--chunks-root`, defaulting to the sibling research tree’s
`../Piposh2-Web-Alpha/decompiled_chunks`, and discover canonical cast chunks at
`<root>/<DIRECTORY>/<DIRECTORY>/chunks`. For each shared cast, keep its existing
`directory` and `members` fields and add `film_loops` when matching Director
resources are available.

The JSON write must retain the current atomic replacement and stable ordering.
Running without a chunks root must still generate a usable bitmap-only registry
and report that film-loop data was unavailable.

- [ ] **Step 3: Generate and inspect the assets**

Run:

```bash
python3 tools/generate_cast_registry.py
shasum -a 256 assets/render_model/cast_registry.json
python3 tools/generate_cast_registry.py
shasum -a 256 assets/render_model/cast_registry.json
```

Expected: both hashes match. A static Python probe must confirm that `wonder`
member 98 has 31 frames and that its first child is bitmap member 78.

- [ ] **Step 4: Commit the generated-data change**

```bash
git add tools/director_film_loops.py tools/generate_cast_registry.py assets/render_model/cast_registry.json
git commit -m "feat: export Director film loops"
```

Do not add a `Co-Authored-By` line.

### Task 2: Resolve shared film loops and child textures

**Files:**
- Modify: `director/render_model_loader.gd`

- [ ] **Step 1: Add registry lookup APIs**

Add:

```gdscript
func get_film_loop(cast_lib: int, cast_id: int) -> Dictionary
func get_registry_member(cast_name: String, cast_id: int) -> Dictionary
func get_registry_texture(cast_name: String, cast_id: int, use_matte: bool) -> Texture2D
```

`get_film_loop` resolves the current movie’s linked cast name, validates the
registry cast and film-loop dictionaries, and returns a deep copy carrying the
normalized registry cast name. Internal or movie-local non-loop members remain
unchanged.

`get_registry_member` resolves canonical bitmap metadata by normalized cast
name and validates the directory with the existing safe-path rules.
`get_registry_texture` loads the bitmap through `_resolve_bitmap_path` and uses
cache keys that include the registry cast name so two casts cannot collide.

All missing and malformed loop/member resources are nonfatal and negatively
cached without emitting warnings once per draw.

- [ ] **Step 2: Parse the project without running tests**

Run the Godot editor parse/startup command already used by this project. Confirm
there are no GDScript parse errors. Do not run anything under `tests/`.

- [ ] **Step 3: Commit the loader change**

```bash
git add director/render_model_loader.gd
git commit -m "feat: load shared Director film loops"
```

Do not add a `Co-Authored-By` line.

### Task 3: Advance film-loop channel state

**Files:**
- Modify: `director/director_runtime.gd`

- [ ] **Step 1: Track loop cursors by score channel**

Add a dictionary keyed by score channel. Each value stores the parent
`cast_lib`, `cast_id`, and zero-based film-loop frame.

On `enter_frame`:

- Resolve active film-loop sprites in the entered score frame.
- Reset a channel to frame zero when its film-loop member changes or first
  appears.
- Advance the cursor once when the same loop remains on the next score frame.
- Wrap when `looping` is true.
- Clamp at the final frame when `looping` is false.
- Remove state for channels no longer containing a film loop.

Clear all loop cursors whenever a new movie is loaded. Expose:

```gdscript
func film_loop_frame(channel: int) -> int
```

This follows Director’s score-driven film-loop stepping: held score frames do
not independently advance their loops.

- [ ] **Step 2: Parse the project without running tests**

Confirm GDScript parsing succeeds and no automated tests are run.

- [ ] **Step 3: Commit runtime state**

```bash
git add director/director_runtime.gd
git commit -m "feat: advance Director film loops"
```

Do not add a `Co-Authored-By` line.

### Task 4: Render film-loop child sprites

**Files:**
- Modify: `director/movie_player.gd`

- [ ] **Step 1: Detect film-loop parent sprites**

Before the existing bitmap path, call `get_film_loop(draw_lib, cast_id)`.
If present, draw the loop’s selected frame and skip the ordinary parent bitmap
lookup.

- [ ] **Step 2: Expand and position child sprites**

For each child, in channel order:

- Compute the parent bounding box by placing the film loop’s center
  registration point at the parent sprite’s `loc_h`/`loc_v`.
- Translate the child registration point from the loop’s `initial_rect` into
  that parent box.
- Scale the translation when the parent sprite is stretched.
- Resolve the child bitmap from the same normalized registry cast.
- Subtract the child bitmap’s scaled registration offset to obtain its
  top-left draw position.
- Apply the child ink’s matte behavior and draw it at the child sprite size.

This must be generic and contain no character, room, movie, or cast-member
special cases.

- [ ] **Step 3: Parse and start Godot without running tests**

Run a parse and short headless startup. Confirm there are no parse errors or
new film-loop warnings. Existing ObjectDB/resource-leak shutdown warnings may
be reported separately but are not part of this change.

- [ ] **Step 4: Commit rendering**

```bash
git add director/movie_player.gd
git commit -m "feat: render Director film loops"
```

Do not add a `Co-Authored-By` line.

### Task 5: Document and verify the complete pipeline

**Files:**
- Modify: `docs/ENGINE.md`

- [ ] **Step 1: Document film-loop support**

Document that `cast_registry.json` now contains generated SCVW mini-scores when
raw Director chunks are available, how to supply `--chunks-root`, and that the
runtime expands and advances their child bitmap sprites.

- [ ] **Step 2: Run non-test verification**

Run:

```bash
python3 tools/generate_cast_registry.py
git diff --exit-code -- assets/render_model/cast_registry.json
git diff --check
```

Use a static Python probe to report:

- Number of casts with film loops.
- Total exported film loops.
- DAY1 referenced `wonder` loop IDs that resolve.
- Any film-loop child bitmap IDs missing from their canonical registry cast.

Parse and briefly start Godot. Do not add or run automated tests.

- [ ] **Step 3: Commit documentation**

```bash
git add docs/ENGINE.md
git commit -m "docs: document Director film loops"
```

Do not add a `Co-Authored-By` line.

- [ ] **Step 4: Request user visual verification**

Ask the user to run the project and inspect representative Day 1 rooms:
`field`, `veranda`, `edge1`, `tennis`, `dwarfs`, and `exitforest3`.
