# Shared Cast Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Generate a deterministic shared cast registry and resolve missing linked bitmap members without character-specific mappings.

**Architecture:** A Python generator indexes internal members of standalone exports named by linked cast_libs. The loader resolves exact scoped local keys first, then registry metadata and canonical bitmap paths. The current member_key() is the root cause: it tries an unscoped bare ID for every cast library, so an external 4:1 can incorrectly resolve local bare 1; bare fallback must be internal-only.

**Tech Stack:** Python 3 standard library, Godot 4.7 GDScript, decoded Director JSON/BMP assets.

---

## Files

- Create: tools/generate_cast_registry.py
- Create: assets/render_model/cast_registry.json
- Modify: director/render_model_loader.gd
- Modify: docs/ENGINE.md

No automated tests are added or run. Validation is deterministic generation, static probes, Godot parse/startup, and user visual confirmation.

### Task 1: Generate the registry

**Files:**
- Create: tools/generate_cast_registry.py
- Create: assets/render_model/cast_registry.json

- [ ] **Step 1: Create the executable generator**

Create tools/generate_cast_registry.py with this complete implementation:

~~~python
#!/usr/bin/env python3
from __future__ import annotations
import argparse
import json
from pathlib import Path

def read_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"warning: cannot read {path}: {error}")
        return {}
    if not isinstance(value, dict):
        print(f"warning: expected object in {path}")
        return {}
    return value

def norm(value: object) -> str:
    return str(value).strip().lower()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", type=Path, default=Path("assets/render_model"))
    parser.add_argument("--output", type=Path, default=Path("assets/render_model/cast_registry.json"))
    args = parser.parse_args()
    linked: set[str] = set()
    directories: dict[str, Path] = {}
    for frames_path in sorted(args.model_root.glob("*/frames.json"), key=lambda p: p.parent.name.lower()):
        cast_libs = read_object(frames_path).get("cast_libs", {})
        if not isinstance(cast_libs, dict):
            print(f"warning: invalid cast_libs in {frames_path}")
            continue
        for library in cast_libs.values():
            if isinstance(library, dict):
                name = norm(library.get("name", ""))
                if name and name != "internal":
                    linked.add(name)
    for members_path in sorted(args.model_root.glob("*/members.json"), key=lambda p: p.parent.name.lower()):
        directories.setdefault(norm(members_path.parent.name), members_path.parent)
    casts: dict[str, dict] = {}
    for name in sorted(linked):
        directory = directories.get(name)
        if directory is None:
            print(f"warning: no standalone export for linked cast {name}")
            continue
        source = read_object(directory / "members.json").get("members", {})
        if not isinstance(source, dict):
            print(f"warning: invalid members in {directory / 'members.json'}")
            continue
        members: dict[str, dict] = {}
        for member in source.values():
            if not isinstance(member, dict) or int(member.get("cast_lib", 0)) != 1:
                continue
            cast_id = int(member.get("cast_id", 0))
            if cast_id > 0:
                members.setdefault(str(cast_id), member)
        if not members:
            print(f"warning: no internal members for linked cast {name} in {directory}")
            continue
        casts[name] = {"directory": directory.name, "members": {key: members[key] for key in sorted(members, key=int)}}
    args.output.write_text(json.dumps({"casts": casts}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output}: {len(casts)} casts")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
~~~

The JSON schema is {"casts": {"goldolin": {"directory": "GOLDOLIN", "members": {"1": <complete original member dict>}}}}. Preserve complete source metadata; do not hard-code character names.

- [ ] **Step 2: Generate and verify determinism**

~~~bash
python3 tools/generate_cast_registry.py
shasum -a 256 assets/render_model/cast_registry.json
python3 tools/generate_cast_registry.py
shasum -a 256 assets/render_model/cast_registry.json
~~~

Expected: same SHA-256 on both runs; unmatched linked libraries print warnings and are omitted.

- [ ] **Step 3: Commit generator and generated data**

~~~bash
git add tools/generate_cast_registry.py assets/render_model/cast_registry.json
git commit -m "feat: generate shared cast registry"
~~~

Expected: one commit with no Co-Authored-By trailer.

### Task 2: Implement scoped local lookup and registry fallback

**Files:**
- Modify: director/render_model_loader.gd:5-36,84-90,141-201

- [ ] **Step 1: Add registry and cache state**

Add CAST_REGISTRY_PATH = "res://assets/render_model/cast_registry.json"; cast_registry: Dictionary = {}; and per-movie _resolved_member_cache, _missing_member_keys, and _missing_texture_keys dictionaries. Extend load_index() to require and parse both index and registry files; require registry casts to be a dictionary; return ERR_FILE_NOT_FOUND or ERR_INVALID_DATA before assignment on failure. Clear all three new caches with the existing texture/matte caches in load_movie().

- [ ] **Step 2: Replace unsafe member_key() and implement consistent helpers**

Replace member_key() and get_member() with these helpers (all dictionary guards are mandatory):

~~~gdscript
func member_key(cast_lib: int, cast_id: int) -> String:
    var scoped := "%d:%d" % [cast_lib, cast_id]
    if members.has(scoped):
        return scoped
    if cast_lib == 1:
        var bare := str(cast_id)
        if members.has(bare):
            return bare
    return scoped

func _linked_cast_name(cast_lib: int) -> String:
    var library: Variant = cast_libs.get(str(cast_lib), {})
    if typeof(library) != TYPE_DICTIONARY:
        return ""
    return str(library.get("name", "")).strip_edges().to_lower()

func get_member(cast_lib: int, cast_id: int) -> Dictionary:
    var cache_key := "%d:%d" % [cast_lib, cast_id]
    if _resolved_member_cache.has(cache_key):
        return _resolved_member_cache[cache_key]
    if _missing_member_keys.has(cache_key):
        return {}
    var local: Variant = members.get(member_key(cast_lib, cast_id), {})
    if typeof(local) == TYPE_DICTIONARY and not local.is_empty():
        _resolved_member_cache[cache_key] = local
        return local
    var linked_name := _linked_cast_name(cast_lib)
    var entry: Variant = cast_registry.get(linked_name, {})
    if typeof(entry) == TYPE_DICTIONARY:
        var registry_members: Variant = entry.get("members", {})
        if typeof(registry_members) == TYPE_DICTIONARY:
            var external: Variant = registry_members.get(str(cast_id), {})
            if typeof(external) == TYPE_DICTIONARY and not external.is_empty():
                var resolved: Dictionary = external.duplicate(true)
                resolved["_registry_directory"] = str(entry.get("directory", ""))
                resolved["_registry_cast_name"] = linked_name
                _resolved_member_cache[cache_key] = resolved
                return resolved
    _missing_member_keys[cache_key] = true
    push_warning("Missing cast member: movie=%s linked_cast=%s member=%d" % [movie_name, linked_name, cast_id])
    return {}
~~~

This explicitly prevents 4:1 from returning movie-local bare 1; only cast_lib == 1 may use bare legacy aliases.

- [ ] **Step 3: Canonically resolve registry bitmaps and cache bitmap failures**

At the start of _resolve_bitmap_path(member), after non-empty rel, add:

~~~gdscript
var directory := str(member.get("_registry_directory", ""))
if not directory.is_empty():
    var texture_key := "%s:%d" % [str(member.get("_registry_cast_name", "")), int(member.get("cast_id", 0))]
    var path := "%s/%s/%s" % [MODEL_ROOT, directory, rel]
    if FileAccess.file_exists(path):
        return path
    if not _missing_texture_keys.has(texture_key):
        _missing_texture_keys[texture_key] = true
        push_warning("Missing registry bitmap: movie=%s linked_cast=%s member=%d path=%s" % [movie_name, str(member.get("_registry_cast_name", "")), int(member.get("cast_id", 0)), path])
    return ""
~~~

Leave existing local candidate resolution unchanged below it. The separate negative texture cache prevents absent registry bitmaps from warning every rendered frame and is cleared on each movie load.

- [ ] **Step 4: Commit runtime support**

~~~bash
git add director/render_model_loader.gd
git commit -m "fix: resolve linked cast members from registry"
~~~

Expected: runtime-only commit with no Co-Authored-By trailer.

### Task 3: Document and validate

**Files:**
- Modify: docs/ENGINE.md

- [ ] **Step 1: Document generated registry ownership**

Update the RenderModelLoader row to mention local-first shared linked-cast lookup. Under Graphics, add that assets/render_model/cast_registry.json is generated; movie-local members.json wins; missing linked members use cast_libs and canonical export bitmaps; regenerate after exports change with python3 tools/generate_cast_registry.py.

- [ ] **Step 2: Run deterministic and static probes, not automated tests**

~~~bash
python3 tools/generate_cast_registry.py
git diff --exit-code -- assets/render_model/cast_registry.json
python3 - <<'PY'
import json
from pathlib import Path
root = Path("assets/render_model")
registry = json.loads((root / "cast_registry.json").read_text())["casts"]
movie = json.loads((root / "MURDER1" / "frames.json").read_text())
wanted = {(2, 1), (4, 1)}
for frame in movie["frames"]:
    for sprite in frame.get("sprites", []):
        pair = (int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)))
        if pair[0] in (2, 4) and pair[1] == 199:
            wanted.add(pair)
for library_id, member_id in sorted(wanted):
    cast_name = str(movie["cast_libs"][str(library_id)]["name"]).strip().lower()
    entry = registry[cast_name]
    bitmap = root / entry["directory"] / entry["members"][str(member_id)]["path"].removeprefix("./")
    assert bitmap.is_file(), bitmap
print("MURDER1 referenced Goldolin/Tofi registry bitmaps resolve")
PY
godot --headless --path . --editor --quit
godot --headless --path . --quit
~~~

Expected: no registry diff; static probe prints MURDER1 referenced Goldolin/Tofi registry bitmaps resolve; both Godot commands exit 0 without parser/registry/startup errors. Do not run tests/*.gd.

- [ ] **Step 3: Obtain visual confirmation**

Run godot --path ., open MURDER1 using existing debug/movie navigation, and confirm Goldolin 2:1 and Tofi 4:1 are visible, positioned correctly, and retain matte/transparent backgrounds; inspect one other linked-NPC scene. Ask the user to confirm before completion.

- [ ] **Step 4: Commit docs and hygiene**

~~~bash
git add docs/ENGINE.md
git commit -m "docs: document shared cast registry"
git diff --check
~~~

Expected: no Co-Authored-By trailer and no git diff --check output.

## Self-review

- [ ] Spec coverage: generator discovery, case-insensitive export matching, internal member indexing, stable output, scoped local-first fallback, canonical bitmaps, nonfatal missing behavior, both negative caches, and required validation are covered.
- [ ] Scope: no Director behavior, navigation, transparency algorithm, README modification, or automated-test work is included.
- [ ] Type consistency: registry uses casts[name].directory and casts[name].members[cast_id] consistently in generator, loader, and static probe.
