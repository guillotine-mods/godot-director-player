# Asset recovery: film loops, cast-lib aliases, non-drawing members

Sub-project 1 of three, from the import-gap audit. Fixes what
`tools/check_cast_coverage.py` reports as "222 referenced cast ids resolve to
neither a bitmap nor a film loop".

## What the 222 actually are

The audit number was mostly noise. Decoding the `CASt` type field for every
reported id, against the ProjectorRays dump:

| Category | Count | Real gap |
|---|---:|---|
| `hezi1` | 59 | No. `ISHDAY1` links `hezi.cst` twice, as `hezi` and as `hezi1`. The cast is exported with 948 members; the registry lookup is by name, so the alias misses. |
| Shape members | 149 | No. Director shapes, all `filled=0`. `island2` member 30 is a 63x402 rect, which is `DAY1` channel 10, the left-edge walk hotspot. These are the game's invisible hotspots and drawing nothing is correct. |
| Film loops | 13 | **Yes.** Across hatuli, heznigt, detectiv, jokers, sabmon, black, master. |
| Field member | 1 | No. `MASTER` member 10 is text. |

So the content gap is 13 film loops. The other 209 are a name-alias bug and a
coverage tool that treats every non-bitmap member as a failure.

`docs/EXTRACT_FROM_INSTALLER.md` claims "222 characters and objects don't
render" and presents recovery as outstanding work. Both are false, and the
recovered data is on this machine.

## Source data

`~/Downloads/piposh2extracted/`:

- `piposh2-data/` — all 83 `.DXR`/`.CXT` plus `MASTER.CST`, `HEZSAVE.DIR`, `strtgame.dxr`
- `piposh2-projectorrays/` — 420 MB ProjectorRays dump, layout `<root>/<NAME>/<NAME>/chunks`

`SCVW` chunk counts: master 4, heznigt 4, hatuli 3, detectiv 2, jokers 2,
sabmon 2, black 1. Eighteen total, thirteen referenced.

## Design

Approach: the generator owns the truth, the coverage tool stays a thin checker.
The chunk dump is a generation-time input only, so the committed
`cast_registry.json` remains the single artifact the runtime and the check read,
and the check keeps running offline.

### 1. Cast-lib alias resolution

`tools/generate_cast_registry.py` keys casts by `cast_libs[n].name` and warns
"no standalone export" when that misses. Add a fallback deriving a stem from
`cast_libs[n].path` (split on `:`, `/`, `\`, drop `.cst`/`.cxt`) and retry.

The same fallback goes in `director/render_model_loader.gd` `_linked_cast_name`,
which does the identical name-only lookup at load time. Fixing only the tool
would make `ISHDAY1` pass the check and still render nothing in game.

`hezi1` is the only failing name in the corpus, and its path stem resolves, so
this is a general fallback rather than a special case.

### 2. Film loops

The generator builds its chunk path as `<root>/<name>/<name>/chunks`. That works
for `island2` under `PIP2DATA` but not for `master`, which sits at the dump root.
`--chunks-root` becomes repeatable, or the generator searches one level of
subdirectory. Master is the most-linked cast in the game.

Film loop child bitmaps are already in the standalone exports, so only the
mini-scores need extracting and they land inside `cast_registry.json`. No chunk
vendoring is required.

### 3. Non-drawing member classification

The generator emits a third per-cast map, `non_drawing`, mapping member id to its
Director type read from the `CASt` header. `check_cast_coverage.py` treats
`members ∪ film_loops ∪ non_drawing` as resolved.

The runtime ignores this map. It already draws nothing for these members and that
stays correct. The map exists so that "member is absent" and "member is
deliberately non-drawing" stop looking identical, which is the ambiguity that
produced the wrong 222 claim.

Shape rendering is deliberately not implemented. Recorded here so the decision is
not rediscovered as a bug.

## Verification

1. `python3 tools/check_cast_coverage.py` exits 0.
2. Boot the game and confirm each of the 13 film loops animates, rather than
   drawing nothing or freezing on its first frame. This is the real bar: the
   runtime film-loop renderer described in `docs/ENGINE.md` has also never run
   against real data.

## Risk

`extract_film_loops` has never produced output, so it may be broken rather than
merely unrun. If so this becomes SCVW decode debugging and the sub-project grows.

## Docs to correct

- `docs/EXTRACT_FROM_INSTALLER.md` — rewrite: data is recovered and local
- `docs/ENGINE.md` "Still open" — replace the 222 line with the real number
- `docs/PROJECT.md` — if it repeats the claim

## Out of scope

Sub-projects 2 (the Lingo spine) and 3 (transitions, palette, talk trees,
lip-sync) get their own specs.
