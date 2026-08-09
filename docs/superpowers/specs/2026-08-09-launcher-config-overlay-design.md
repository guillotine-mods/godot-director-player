# A launcher screen, and the untracked overlay that makes it worth having

`director_game.cfg` is tracked, and it is a working file: `root` and `boot_movie`
are pointed at whichever title is being looked at, and every session that does so
carries a diff nobody wants to commit. The working tree at the time of writing
holds exactly that — `root = "res://games/rating"` against a `piposh2` HEAD.

This gives the port a main screen that sets those options, and — the part that
actually removes the conflicts — an untracked per-machine overlay for the screen
to write into.

## Why the screen alone is not the fix

`res://director_game.cfg` is inside the PCK in an export and cannot be written.
Running from source it *can*, so a screen that edits it in place produces the
same merge conflicts as hand-editing, plus a UI. The deliverable is the overlay;
the screen is its front end.

The tracked file stays, as documented defaults, and that is load-bearing rather
than tidy: `[debug] enabled = "auto"` is deliberately what an export ships, and
`director_game.cfg:138-143` gives the argument. Nothing in this design changes
what the tracked file means to a build.

## The overlay

`user://director_game.local.cfg`, mirroring the tracked file's schema key for
key. Untracked by construction — `user://` is outside the checkout — so there is
nothing to gitignore and nothing to accidentally `git add`.

`user://` rather than a gitignored file beside the repo, **because Android is the
only export preset in `export_presets.cfg`.** On Android `res://` is inside the
APK; a res://-local overlay does not degrade there, it simply cannot be written.
A both-locations scheme would need a four-deep precedence chain to say the same
thing `user://` says with one location.

Precedence, unchanged at the top:

    CLI flag  >  user://director_game.local.cfg  >  res://director_game.cfg

`gate.sh` pins the corpus with `--root piposh2 --boot strtgame.dir`, and that
must keep beating everything below it.

## One merge point, because there are four readers

Today four separate sites do their own `ConfigFile.load` on the tracked file:

| site | reads |
| --- | --- |
| `director/director_paths.gd:43` `load_config` | `[game] root`, `[game] boot_movie` |
| `director/director_codepage.gd:377` | `[game] codepage` |
| `scenes/preview/boot.gd:146-148` | `[display] aspect` |
| `scenes/preview/debug_keys.gd:252` `load_config` | all of `[debug]` |

An overlay taught to four readers is four chances for them to disagree, and this
repo has already paid that bill: `director_paths.gd:54-62` records that applying
`--root` in `preview/boot.gd` alone moved the movies and left `AudioDirector` —
which calls `load_config()` itself — indexing sounds against the old root, so the
game ran silent. The same shape, with a different override.

So: **`director/game_config.gd`**, a static loader that reads the tracked file,
overlays the local file on top, and answers
`get_value(section, key, default) -> Variant`. The four sites ask it instead of
loading a `ConfigFile` themselves. CLI flags stay exactly where they are today,
resolved inside the reader that owns them, on top of the merged answer.

It lives in `director/` because `AudioDirector` and `DirectorCodepage` reach it
and `director/` must not depend on the preview. `DebugKeys` is in `scenes/` and
may depend on `director/`; the arrow does not reverse.

`load(tracked_path, overlay_path)` takes both paths explicitly, so a harness can
point at files it just wrote — the seam `debug_bindings.gd:209` already uses
against `DebugKeys.load_config(written)`.

## Gate isolation: the overlay is off when headless

The overlay applies only when `DisplayServer.get_name() != "headless"`.

This costs the gate nothing to adopt. All 62 `gate.sh` entries run
`--headless --script tools/<name>.gd`; `check.sh` runs `--script
tools/preview_surface.gd`; the three child processes spawned from inside
harnesses (`save_state.gd:466`, `save_movie.gd:232`, `text_codepage.gd:461`) each
pass `--headless --script`. **Nothing in the repo boots `main_scene`,** which is
also what makes the `main_scene` change below free.

An explicit `--no-local` flag on `gate.sh:156` was considered and rejected: a run
that forgets the flag silently reads a human's overlay, and mutating-shared-state
-under-concurrent-runs is precisely the failure `gate.sh:44-56` removed when it
stopped rewriting the `root` line. Keying on the display server also covers the
ad-hoc `godot --headless --script tools/x.gd` an agent fires off by hand, which
no flag in `gate.sh` could.

The one assertion that must keep reading the tracked file directly already does:
`tools/debug_bindings.gd:283-287` constructs its own `ConfigFile` and loads
`DebugKeys.CONFIG_PATH` to assert the shipped value is `auto`. That stays
correct either way, and the spec does not change it.

**The cost, stated rather than discovered:** the gate now enforces nothing about
what the launcher writes. See *Validation* below, which is where that cost is
paid.

## The launcher

`scenes/launcher/launcher.tscn` becomes `main_scene`. Play loads
`res://scenes/director_preview.tscn`.

**A run that names a game on the command line plays straight through.** If
`--root`, `--boot` or `--save` is present the launcher hands off without
rendering. `director_paths.gd:69-78` documents

    godot --path . -- --save saves/piposh2/beach_bug.json

as meant to be sufficient on its own; a menu in front of it breaks that. A bare
run shows the menu, and an Android run — which has no argv — always does.

Controls are sized for touch throughout, since Android is the export target.

### Player tab

* **Game** — one entry per *title*, built from the directories actually present
  under `res://games/`, read with `DirAccess` (which works inside an exported
  PCK). Writes `[game] root`. Shown only when more than one root is found;
  with a single root it collapses away, so a one-game Android build needs no
  decision about whether to carry the list.
* **Language** — a row of flags, shown only for a title whose entry covers more
  than one root. Selecting Piposh offers IL / US / RU, IL preselected. See *The
  title mapping* below.
* **Boot movie** — not a control here. It follows from the chosen root through a
  mapping, not a probe. The dev tab can override it. See *The title mapping*
  below.
* **Aspect** — the four values of `[display] aspect`.

### Developer tab

Boot movie override, `[game] codepage`, `[debug] enabled`, the fifteen bindings
and `fast_forward_fps`, and the QoL keys (below).

**Visibility is decided by the tracked file's `[debug] enabled` plus
`--debug-ui`, never by the merged value.** Reading the merged value creates a
door that closes behind itself: set `enabled = false` in the launcher and the
control that would set it back is gone. `--debug-ui on` recovers that on desktop;
**Android has no command line**, and it is the only export preset, so the
recovery there is clear-app-data.

This is a deliberate exception to `debug_keys.gd`'s one-answer-per-process rule
(`debug_keys.gd:296-299`) — tab *visibility* and debug-layer *state* come from
different precedence chains — and it gets a comment saying so, or the next reader
will "fix" it.

## The title mapping

One section per directory under `games/` in the tracked `director_game.cfg`,
carrying every fact the launcher needs about that root:

    [root.piposh]
    title = "Piposh"
    boot  = "strtgame.dir"
    flag  = "il"
    default = true

    [root.piposh-en]
    title = "Piposh"
    boot  = "strtgame.dir"
    flag  = "us"

    [root.piposh-ru]
    title = "Piposh"
    boot  = "strtgame.dir"
    flag  = "ru"

    [root.piposh2]
    title = "Piposh 2"
    boot  = "strtgame.dir"

    [root.piposh-dream]
    title = "Piposh Dream"
    boot  = "strtgame.dir"

    [root.rating]
    title = "Rating"
    boot  = "mainmenu.dir"

Roots sharing a `title` collapse into one entry in the game list with a flag row
under it; `default = true` is the flag preselected. A title with one root gets no
flag row and no second control. One section per directory, one fact per line — so
there is no second parallel list to drift out of step with the first, and the
gate check below reads the same sections the launcher does.

Boot names are lower-cased throughout; the on-disk names are mixed case
(`STRTGAME.dir`, `MAINMENU.dir`) and `DirectorPaths.resolve` already matches
case-insensitively — the tracked config carries `boot_movie = "mainmenu.dir"`
against `rating`'s `MAINMENU.dir` today and finds it.

**The flags are emoji — 🇮🇱 🇺🇸 🇷🇺 — with a `SystemFont` fallback, and no image
assets.** `flag = "il"` names the country code; the launcher composes the two
regional-indicator code points from it.

Measured on 4.7.1 rather than assumed. The project sets no theme font, so the
default is `Open Sans SemiBold`, and `has_char` over it answers:

    regional indicator U+1F1EE   false
    Hebrew alef U+05D0            true
    Cyrillic zhe U+0416           true

So the bundled font is missing only the emoji block. A `SystemFont` whose
`font_names` are `["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"]`,
installed as a `fallbacks` entry on the flag labels, covers it: that chain
answers `true` for the regional indicator on macOS here. Android resolves the
same chain to Noto Color Emoji; that is not verified in this repo, because the
font is not installed on the machine the measurement was taken on and a `false`
from `has_char` there is the font's absence rather than a fact about the
platform.

**The failure mode needs no second code path.** A platform whose emoji font
declines regional-indicator pairs — Windows does — draws the two letters
instead, which is `IL`, `US`, `RU`. That is the label a text-only design would
have chosen, so the degradation is legible and the launcher does nothing special
to produce it.

Hebrew and Cyrillic being present is worth recording separately: it means a
future language label in native script (`עברית`, `Русский`) also needs no asset,
which is not what an earlier draft of this document claimed.

**Recorded because it was argued the other way:** a flat list of six named roots
was recommended and declined. The costs it was meant to avoid are real and are
accepted here — a second grouping model on top of the engine's root-is-a-game
rule, and a control that is inert for three of the four distinct titles. The
third cost, image assets, turned out not to exist. The engine is untouched by
any of it: what the launcher writes is
still `[game] root = "res://games/piposh-ru"`, the same string `--root` names.

**A mapping rather than a probe, because the probe is measurably wrong.** The
obvious rule — `mainmenu.dir` if present, else `strtgame.dir` — picks the wrong
container for `piposh-dream`, which ships *both* at its root and boots
`strtgame.dir`. Three more (`piposh`, `piposh-en`, `piposh-ru`) carry a
`MAINMENU.dir` one directory down, which any looser search would find. Six games,
one heuristic, at least one wrong answer.

In the tracked config rather than a GDScript `const` for the reason `gate.sh:9-12`
gives about the F10 collision — that was "config not code", and this is the same
shape: data about which titles exist, kept where a person adding a title will see
it.

**These roots are three installs, not a base plus patches.** `piposh` is 2688
files / 636M, `piposh-en` 2314 / 637M, `piposh-ru` 2358 / 616M. The grouping is a
presentation of three independent corpora and nothing shares anything at runtime.
`piposh-ru` carries **0** of the 126 FX sounds the other two have, which is a
known data gap (`bugs.md`, "Audio miss") and not something the launcher changes —
worth naming, because presenting the three under one title implies a parity that
does not hold for audio.

**A root with no entry is not guessed at.** It appears in the list under its
directory name, with no flag, reporting that its boot container is unset and
must be named in the dev tab. Silent fallback is what produces the dark-harness
failure `gate.sh` warns about: a boot movie that does not exist under the pinned
root loads no score and asserts over nothing. The gate below means this state
only ever exists for the few minutes between adding a title and describing it.

`[game] boot_movie` stays exactly as it is — the explicit override, in the
overlay or on the command line via `--boot`, beating the mapping. The mapping
only answers "what does this root boot by default".

**Gated.** A new `tools/title_mapping.gd` asserts that every directory under
`games/` has a `[root.<name>]` section, that its `boot` resolves under that root,
that every `flag` is a two-letter code that composes to a regional-indicator
pair, and that a `title` covering more than one root has exactly one
`default = true`. Adding a title then fails as a named regression rather than as
a menu entry that boots nothing, or a flag row with no preselection. It is a
`resolve` and two range checks per root — cheap enough for `ALL`.

## Validation, in the UI, because the gate cannot see it

`DebugKeys.load_config` today answers a bad binding with `push_warning`
(`debug_keys.gd:276`, `:282`, `:290`). A warning in a log is not a UI, and with
the overlay off under `--headless` the gate never sees the value at all. So the
keybinding editor carries the checks inline and refuses to store a binding that
fails one:

1. **A real key name** — `OS.find_keycode_from_string(name) != KEY_NONE`.
2. **No two commands on one key** — the collision `debug_keys.gd:282` warns about,
   where which command survives depends on iteration order.
3. **Not a key any title's scripts test.** `tools/lib/key_sites.gd` answers this
   already: `KeySites.for_root(root).codes`, run over every directory under
   `games/`, which is exactly what `tools/debug_bindings.gd` does.

Check 3 is re-derived at runtime, not copied into a constant in the UI. The
enumerated set at `director_game.cfg:100` is a transcript of a measurement, and
`key_sites.gd:10-14` records what happened the last time that measurement lived
in a constant: the list was swept from `reference/lingo/`, which holds Piposh 2
alone, so it was right about one title in six and put the pause on F10, which
Rating tests at 48 sites.

The measurement is a cast parse per container — seconds per title, six titles —
so it is computed **once, when the keybinding section is first opened**, and
cached for the process. A spinner on first open is acceptable on a screen that
only exists in a debug build.

Checks 1 and 2 are per-keystroke and free.

## AppSettings

`autoload/app_settings.gd` has exactly one live consumer in the repository:
`controller_cursor_speed`, at `autoload/input_router.gd:40`. `grep` for
`AppSettings.` across every `.gd` outside the file itself returns that one line.

Three groups, three different fates:

**Dead duplicates of live keys — deleted.** `aspect_mode` / `target_aspect()` /
`aspect_mode_name()` duplicate `[display] aspect`, which is the one that reaches
the screen via `boot.gd:148`. `dev_mode` and `show_debug_overlays` duplicate
`[debug] enabled`. Carrying a second name for the same question into a new schema
is how the duplication got here.

**Documented orphans — deleted.** `use_lingo_clicks` and `use_lingo_frames`
choose between the interpreter and a lifted export that no longer exists; the
file says so at `app_settings.gd:33-44`.

**The rest — moved into the schema, plumbing only.** `upscale_mode`,
`test_mode_enhanced_graphics`, `expand_edge_hotspots`, `show_hotspot_hints`,
`allow_minigame_skip`, `controller_cursor_speed`, `dev_warp_movie`,
`dev_warp_label`. AppSettings stops owning `user://player_settings.cfg` and reads
them through `GameConfig`; the launcher writes them.

**Their behaviour stays unimplemented, and that is the agreed scope.** Wiring
hotspot hints, upscaling, minigame skip and edge-hotspot expansion to the
renderer and input is a separate feature per control, not launcher work. The
controls therefore appear in the dev tab under a heading that says they are not
yet wired, so the first report is not "hotspot hints is broken".

**Migration.** `controller_cursor_speed` is the one value a live consumer reads
and existing installs have it in `user://player_settings.cfg`. On first load, if
that file exists and the overlay does not carry the key, copy the value across;
after that the old file is not read again. It is not deleted — leaving it costs
nothing and deleting a file the user did not ask us to touch is not ours to do.

## Sequencing

The merge layer is the only piece that can break the 62 harnesses, and everything
else depends on it, so it lands first and alone.

1. **`director/game_config.gd` + the four reader refactors.** No behaviour
   change: with no overlay file present, every reader answers exactly what it
   answers today. Gate must be 62/0 at this step before anything else starts.
2. **The `[root.*]` sections + `tools/title_mapping.gd`.** Data and its gate,
   before anything reads them. Lands independently of the UI.
3. **Launcher scene + Player tab + `main_scene`.** Game, language flags, aspect.
   The flag-bypass path. Overlay writing.
4. **Dev tab.** Boot override, codepage, `[debug] enabled`, the tracked-file
   visibility gate.
5. **Keybinding editor + the three validators.**
6. **AppSettings deletions, schema move, and the `controller_cursor_speed`
   migration.**

## Testing

Step 1 is covered by the existing suite: `bash gate.sh` unchanged, 62 pass / 0
fail, is the assertion that the refactor moved nothing. That is the point of
doing it alone.

New harnesses, in `tools/`, run headless like every other entry and therefore
must pass their paths explicitly:

* **`game_config.gd`** — precedence. Write a tracked file and an overlay to
  scratch paths, and assert: overlay beats tracked per key; a key absent from the
  overlay falls through; an absent overlay file leaves the tracked answers
  untouched; a malformed overlay is ignored rather than fatal. Then assert the
  headless rule itself — under `--headless`, a real overlay at the real
  `user://` path is not consulted.
* **`title_mapping.gd`** — the `[root.*]` sections against what is on disk, as
  described above. Joins `ALL` in `gate.sh`.
* **`launcher_keys.gd`** — the three validators, as predicates rather than
  through the UI: a bad key name is refused, a duplicate is refused, and a code
  in `KeySites.for_root` over every root under `games/` is refused. The third
  shares its source of truth with `tools/debug_bindings.gd`, so a change to the
  corpus moves both.

Three new entries join `ALL`, so **the recorded set becomes 65 pass / 0 fail and
`gate.sh`'s header has to say so.** That header already carries the warning:
"Count `ALL` when you change it: this line said 54 entries for as long as it took
the list to reach 61". Not updating it is the same defect it describes.

The launcher's own layout is not gate material — it needs a display server and
there is no harness in this repo that opens a window.

## What this does not do

* No behaviour is wired behind the QoL toggles (above, deliberately).
* The launcher is not reachable from inside a running movie. It runs before boot
  and Play is one way. An in-game panel was considered and dropped: `root`,
  `boot_movie` and `codepage` cannot take effect without restarting the movie
  session, and the F-key band has no room for another binding
  (`debug_keys.gd:43-56`).
* `res://director_game.cfg` is never written by the port, from source or
  otherwise. It is edited by hand, by whoever is changing the shipped default.
