# Shared Cast Registry Design

## Problem

Director movies reference character artwork through linked cast libraries. The
exported score preserves each sprite's cast-library ID and member ID, but some
movie-local `members.json` files omit the linked library's member metadata.
Godot therefore cannot resolve those textures and silently skips the sprites.

For example, `MURDER1` references Goldolin through cast library 2 and Tofi
through cast library 4, while its member data contains neither library. Their
complete member metadata and bitmaps are available in the standalone
`GOLDOLIN` and `TOFI` exports. This mismatch affects linked NPCs project-wide;
Piposh remains visible because his artwork is available locally.

## Solution

Generate one shared cast registry from the existing standalone render-model
exports. The registry maps a normalized cast name to its canonical export
directory and member metadata. Runtime texture resolution continues to prefer
movie-local data, then consults the shared registry when a referenced member is
missing.

The implementation must not contain character-specific mappings for Tofi,
Goldolin, or any other NPC.

## Generated Registry

Add a generator under `tools/` that scans render-model exports and writes:

`assets/render_model/cast_registry.json`

Each registry entry contains:

- A normalized, lowercase cast name.
- The canonical export directory containing the cast's bitmap files.
- Member metadata keyed by cast member ID.

The generator first collects linked cast names from every movie's `cast_libs`.
For each name, it finds a render-model directory with the same name
case-insensitively and indexes that export's internal (`cast_lib == 1`) members
as the canonical form of the linked cast. Names without a matching standalone
export are omitted and reported. The generator produces stable ordering so
regenerating unchanged inputs produces an unchanged file.

## Runtime Resolution

`RenderModelLoader` loads the registry once alongside the render-model index.
Member resolution follows this order:

1. Resolve `cast_lib:cast_id` from the current movie's `members.json`.
2. If missing, read the linked cast name from the current movie's `cast_libs`.
3. Normalize the cast name and resolve that member ID from the shared registry.
4. Resolve the bitmap relative to the registry entry's canonical export
   directory.
5. Cache resolved member metadata and textures using the current cast-library
   ID and member ID.

Local members always win, preserving movie-specific artwork and overrides.

## Failure Handling

Missing registry entries, missing member IDs, malformed metadata, or absent
bitmap files remain nonfatal. The sprite is skipped as it is today, with a
warning that identifies the movie, linked cast name, and member ID. Repeated
lookups use a negative cache so the same missing asset does not emit warnings
every frame.

## Scope

This change covers linked bitmap cast members across every exported movie. It
does not implement Director behaviors that dynamically change sprite members
or visibility, and it does not alter navigation, gameplay state, transparency,
or bitmap decoding.

## Validation

Per project direction, no automated tests will be added or run. Validation will
consist of:

- Regenerating the registry twice and confirming deterministic output.
- Confirming representative missing members, including Tofi and Goldolin in
  `MURDER1`, resolve to existing bitmap files.
- Running Godot editor parsing and a short headless project startup.
- User visual verification of the cliff encounter and other NPC scenes.
