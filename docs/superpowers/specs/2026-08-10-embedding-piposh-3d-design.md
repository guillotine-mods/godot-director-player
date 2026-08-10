# A title made of code, in a player built for titles made of data

The six titles under `games/` are corpora. `.dir` and `.cst` are not Godot
resources and Godot has no idea what they are; `director_file.gd` opens them as
bytes and interprets them at runtime, which is why a game can be dropped into
`games/` and appear in the launcher without the engine being told anything in
advance.

`piposh-3d` breaks that shape. It is a complete second Godot 4.7 project — its
own `project.godot`, 115 `.gd`, 3 `.tscn`, 4,879 committed `.import` files and
564 MB of assets — a port of a 3D GameStudio A5 game. Its content is native
Godot content, so it has to be *imported* before anything can reference it, and
importing is an editor-only operation that an exported build cannot perform.

This describes how it becomes a launcher tile without either project giving up
being itself.

## The constraint that picks the mechanism

Every title stays independently distributable, because they will ship
individually to mobile; `piposh-3d` in particular keeps opening standalone,
since it is under active development behind `rewrite_skill/PORTING_MANUAL.md`
and a Python conversion pipeline. For now everything bundles into one app, and
what happens after alpha is deliberately undecided — so nothing here may harden
a distribution choice.

Standalone and embedded cannot both be satisfied by nesting. The child carries
257 absolute `res://scenes|assets|scripts|tools` references, and a project's
`res://` root is wherever its `project.godot` sits. Nested under the player,
every one of those paths is wrong; rewritten, standalone is. No layout makes
both true.

Nesting has a second cost that would outlive the decision: the child commits
4,879 `.import` files. Imported at a different path the parent's editor rewrites
all of them, leaving the submodule permanently dirty.

So the child's own `res://` namespace has to survive intact, which means a
resource pack. `docs/MOBILE.md` already reaches for the same mechanism for the
containers, and for the same class of reason.

## Where it lives

`titles/piposh-3d`, not `games/`. `games/` is load-bearing: `KeySites.roots()`
returns *every* directory under it, and seven tools carry `ROOTS` constants
meaning "Director data root". Added there, the submodule was a launcher row
pointing at a root with zero containers, and `title_mapping` went red on
`every root under games/ has a [root.<name>] section` before anything else was
touched. A code-bearing title in `games/` poisons that word permanently.

The submodule section is named `titles/piposh-3d` so `name == path`, matching
the other six.

## Mounting

A `Piposh3DPack` autoload, **listed first** in the parent's `project.godot`,
calls `ProjectSettings.load_resource_pack(pack, false)`. The child's three other
autoloads — `LevelRouter`, `AudioChannels`, `PiposhDebug` — are declared after
it and resolve out of the pack.

Measured, not assumed. With the pack present:

```
[mounter] mounting …/p3.pck -> true
[main] P3Router says: router alive, from the pack
```

An autoload whose script exists only inside a mounted pack instantiates
correctly, and a script naming it as a global identifier compiles and runs.

With the pack absent the app still boots and reaches the launcher, but logs
three lines per missing autoload:

```
ERROR: Failed to instantiate an autoload, can't load from path: res://p3/autoload/p3_router.gd.
[main] launcher reached; P3Router present: false
```

Non-fatal, and `gate.sh` counts errors, so a build without the pack goes noisy.
Building the pack is therefore a gate prerequisite rather than an optional step.

`replace_files=false` is not a detail. The two `res://` namespaces collide on
exactly four paths — `autoload/game_state.gd` (+`.uid`), `icon.svg`,
`project.godot` — and a pack additionally carries `res://project.binary`.
Measured on a pack and host that both hold `res://collide.txt`:

```
load_resource_pack(replace_files=false) -> true    res://collide.txt reads: PARENT VERSION
load_resource_pack(replace_files=true)  -> true    res://collide.txt reads: CHILD VERSION
```

So with `false` the parent's file wins and the child's is genuinely
unreachable at that path — not merely shadowed.

## The rename the child cannot avoid

Both projects register an autoload called `GameState`, at their own
`res://autoload/game_state.gd`. The child names it in 81 of its 115 scripts; the
parent in 84 of its own. GDScript resolves autoload identifiers at parse time,
so this cannot be shadowed away at runtime, and by the measurement above the
child's script is the one that becomes unreachable under `replace_files=false`
— leaving its 81 scripts silently bound to the Director engine's state object.

This makes the rename **required**, not merely tidy. It also dissolves one of
the four path collisions on its own.

The child renames its singleton to something unique. Mechanical, and standalone
is unaffected.

## Keeping the parent out of 564 MB

`.gdignore` inside `titles/piposh-3d/`. Verified on a scratch project: without
it the subdirectory's assets import, with it they do not.

**No file is needed. There was never a problem here.** Godot skips any
directory containing a nested `project.godot` outright:

| subdirectory | class registered in parent's cache |
| --- | --- |
| plain, with a `class_name` script | yes (1) |
| same, plus a `project.godot` | no (0) |

`titles/piposh-3d` has a `project.godot`, so the parent's editor never
descended into it in the first place. The observable proof was there the whole
time and was misread as the `.gdignore` working: the parent's `.godot` is 88 K
with 564 MB of PNGs and GLBs sitting in the tree.

This is worth stating plainly because two earlier revisions of this document
built machinery on the assumption — first a parent setup step plus a line in
the child's `.gitignore`, then a single committed file. Both were solving
nothing.

## Building the pack

```
godot --path titles/piposh-3d --export-pack <preset> titles/piposh3d.pck
```

Verified to need no export templates installed — the Godot binary alone
produces a pack. Scope of that check: a trivial project with
`export_filter="all_resources"`, not the child's 4,879 `.import` files and
564 MB. Building the real pack is a step for the implementation plan to prove,
not a design claim already settled here.

The child needs a committed export preset; its `export_presets.cfg` is
currently gitignored.

The output is gitignored on the parent side. It is not new data: the same bytes
already arrive with the submodule, and this is only the import saved ahead of
time. `.pck` is on Android's no-compress list, which is the property
`docs/MOBILE.md` measured the containers against.

The parent's `include_filter` names the pack alongside `games/*` and
`director_game.cfg`.

## The launcher

A config section carrying a scene and a pack in place of a `boot` container;
`title_list.build()` carries it into the row; one branch at `launcher.gd:759`
chooses between `PREVIEW_SCENE` and the 3D scene. `tools/title_mapping.gd`
learns that a title need not be a `games/` root.

Play-enable validation and `binding_rules.gd` must not mark a boot-less row
invalid — the `_invalid`/`_mark_field` site, not `modulate`.

**No exit to the launcher.** Deliberate, and consistent rather than missing: the
only scene change in the whole player is `launcher.gd:759`, and
`director_preview.gd` only ever `quit()`s. No Director title returns to the
launcher either.

## Settled: `class_name` globals do not cross a pack boundary

**This blocked the work and was then removed by taking option 1 below.** It is
the same mechanism that hangs a fresh worktree — global classes resolve from
`.godot/global_script_class_cache.cfg`, which belongs to the *host* project —
and mounting a pack does not merge into it:

```
[cls] mount -> true
SCRIPT ERROR: Parse Error: Identifier "PackClass" not declared in the current scope.
```

The child declares nine: `SettingsPanel`, `MdlAnimator`, `WdlInterpreter`,
`TouchControls`, `GameHud`, `WmbLevelLoader`, `AcknexSky`, `CameraAuthority`,
`WdlDirector` — about 200 references across ~40 files, concentrated in
`wdl_interpreter.gd` (49) and `wdl_director.gd` (24).

Two escape routes were tested and both are closed:

- **Register the autoloads at runtime instead**, so the parent need not declare
  them. With the singleton node present at `/root` *and* the `autoload/` key set
  in `ProjectSettings`, the compiler still refuses:
  `Compile Error: Identifier not found: P3Router`.
- **Let the parent scan the child's scripts from disk**, so the globals land in
  the parent's own cache. Impossible for the same reason the `.gdignore` was
  unnecessary — the nested `project.godot` makes the directory invisible, and
  autoloads pointed at paths inside it fail with
  `Failed to create an autoload, can't load from UID or path`.

Three options were put to the owner, who took the first:

1. **Drop `class_name` in the child**, replacing each with a `const X =
   preload(...)` at its use sites. **Taken.** 16 files, not the ~40 first
   estimated — the estimate counted class names appearing in comments and in
   node-name strings.
2. Patch the parent's class cache at build time. Zero change to the child, and a
   hand-maintained cache the editor may regenerate underneath.
3. Ship the 3D title as its own app and not offer it in the launcher.

**A const preload is not free, and that is the lasting lesson.** It pulls the
target into compilation early, and in a `--script` run that happens before
autoloads register — so `smoke_anim.gd` preloading `mdl_animator.gd`, which
merely *mentions* `PiposhDebug`, failed with `Identifier not found`. A preload
added for tidiness can break a harness that never touches the preloaded type.
Detection has to ignore strings as well as comments.

No cycle stood in the way: `wdl_interpreter` names `WdlDirector` only in
comments, so the dependency runs one way and `preload` accepts it.

## What shipped

The tile exists, boots and plays. Beyond the design above, four things the design
did not anticipate, each found by running it rather than reading it:

- **`_refresh_play` refused the tile.** Every Godot-project title has an empty
  `boot` by construction. The complaint still fires for a Director title whose
  `[root.*]` names none — that remains a real misconfiguration.
- **Every input was missing.** The InputMap lives in `project.godot`, which is
  exactly what `replace_files=false` shadows, so `move_forward` and its five
  siblings had to be carried across explicitly. This is the general shape of the
  remaining risk: *anything* the title declared in `project.godot` is absent
  inside the player. `[rendering]` and `[display]` are still unported.
- **`title_list.gd` named an autoload and hung the gate**, by asking
  `Piposh3DPack.mounted`. `ResourceLoader.exists()` on an in-pack path says the
  same thing without a compile-time reference.
- **A mounted pack made `res://` read-only and no movie could save.** Not a
  piposh-3d bug at all: `director_writer.gd` handed `res://` paths to
  `remove_absolute`/`rename_absolute`, and any mounted pack routes `res://`
  directory access through the read-only `DirAccessPack`. `docs/MOBILE.md`
  already proposes mounting a pack for the containers, so this was waiting
  regardless. Fixed with `globalize_path`.

## Open: the renderer

The parent runs `rendering_method="mobile"` with
`textures/canvas_textures/default_texture_filter=0` — nearest, correct for 1995
pixel art. The child is Forward Plus with `msaa_3d=1`. One app has one of each.

To be settled by building it and looking at both, not by argument — and it is now
buildable, so this is answerable rather than hypothetical. The title currently
runs on the player's settings: `mobile`, nearest filtering, and `canvas_items`
stretch with the window forced maximized, none of which it was built for.

`pause_menu` and `skip_minigame` are both Escape. They live in different scenes,
so it is a double-bind rather than a conflict, and worth knowing about before
somebody adds a third.

## Rejected

**Nest and rewrite the child's paths.** Breaks standalone, and rewrites 4,879
committed `.import` files on every parent import.

**Separate binaries with a hand-off.** No engine coupling at all, and no mobile
story, so it cannot serve one bundled app.

**Commit the pack.** ~500 MB of bytes already in the checkout, and GitHub
refuses files over 100 MB without LFS.

**Unpack the 3D assets at first run, the way the containers are read.** The
containers work that way because the reader is ours. Native Godot content has no
runtime importer to unpack it with; the pack *is* the unpacked form.
