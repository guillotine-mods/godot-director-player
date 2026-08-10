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
`project.godot` — and a pack additionally carries `res://project.binary`. With
`false`, the parent's own files win every one of them.

## The rename the child cannot avoid

Both projects register an autoload called `GameState`, at their own
`res://autoload/game_state.gd`. The child names it in 81 of its 115 scripts; the
parent in 84 of its own. GDScript resolves autoload identifiers at parse time,
so this cannot be shadowed away at runtime, and under `replace_files=false` the
child's script is the one dropped — leaving its 81 scripts silently bound to the
Director engine's state object.

The child renames its singleton to something unique. Mechanical, and standalone
is unaffected.

## Keeping the parent out of 564 MB

`.gdignore` inside `titles/piposh-3d/`. Verified on a scratch project: without
it the subdirectory's assets import, with it they do not.

It cannot be committed at the child's root — that would stop the child's own
editor importing, which is exactly what standalone development needs. So it
exists in embedded checkouts only, created by the parent's setup step.

Left alone it shows as untracked content in the submodule, measured:

```
A? titles/piposh-3d
?? .gdignore
```

Two ways to silence that, and the cheaper one is not obviously the better one:

- **One line in the child's `.gitignore`.** Precise — hides `.gdignore` and
  nothing else. Costs a commit in another repo.
- **`ignore = untracked` on the submodule in `.gitmodules`.** Entirely
  parent-side, no coordination. But it hides *every* untracked file in the
  child, including assets somebody forgot to add — a real loss while the child
  is under active development.

Taking the first, on the grounds that the child is the repo being actively
worked in and a blanket ignore there is a trap. Revisit if coordinating the
commit proves awkward.

## Building the pack

```
godot --path titles/piposh-3d --export-pack <preset> titles/piposh3d.pck
```

Verified to need no export templates installed — the Godot binary alone
produces a pack. The child needs a committed export preset; its
`export_presets.cfg` is currently gitignored.

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

## Open: the renderer

The parent runs `rendering_method="mobile"` with
`textures/canvas_textures/default_texture_filter=0` — nearest, correct for 1995
pixel art. The child is Forward Plus with `msaa_3d=1`. One app has one of each.

To be settled by building it and looking at both, not by argument. The 3D
title's `pause_menu` and the parent's `skip_minigame` are also both Escape;
a double-bind, not a merge conflict.

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
