extends SceneTree
## Everything the engine opens at runtime is inside some preset's include filter.
##
##   godot --headless --path . --script tools/export_presets_check.gd
##
## `export_filter="all_resources"` sweeps in imported resources, and this project
## has none for its corpora: `**/*.import` is gitignored on purpose, so the
## containers, the AIFFs and the generated pack all arrive as plain files that
## only `include_filter` can carry. A path the engine opens and the filter does
## not name is not a build error -- the export succeeds, the artifact ships, and
## the title is simply absent. `scenes/launcher/title_list.gd` hides an embed
## whose scene does not resolve, so the symptom is a missing tile rather than a
## crash, which is the quietest kind of wrong.
##
## Derives its expectations rather than listing them. The roots come from
## `KeySites`, and the pack path is read off the autoload's own constant, so
## adding a title does not silently leave this file behind.
##
## Title-agnostic: it names no game.

const Harness := preload("res://tools/lib/harness.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")

const PRESETS := "res://export_presets.cfg"
const PACK_SCRIPT := "res://autoload/piposh3d_pack.gd"


func _init() -> void:
	var h := Harness.new()

	var case := "the presets file parses"
	h.begin(case)
	var cfg := ConfigFile.new()
	var err := cfg.load(PRESETS)
	if not h.check("export_presets.cfg loads", err == OK, error_string(err)):
		h.complete(case)
		quit(h.finish("the export presets"))
		return
	var presets := _preset_sections(cfg)
	# The subject has to exist, or every assertion below passes over nothing.
	if not h.check("there are presets to check", not presets.is_empty(),
			"%d preset(s)" % presets.size()):
		h.complete(case)
		quit(h.finish("the export presets"))
		return
	h.complete(case)

	case = "the runtime paths can be derived"
	h.begin(case)
	var required: Array[String] = ["director_game.cfg"]
	var roots := KeySites.roots()
	h.check("there are game roots on disc", not roots.is_empty(),
		"%d root(s)" % roots.size())
	for root in roots:
		required.append(str(root).trim_prefix("res://"))
	# Read the constant off the script resource, never through the autoload
	# name: naming an autoload is a compile-time reference, autoloads register a
	# frame into a `--script` run, and this is such a run. `title_list.gd`
	# carries the same note for the same reason.
	var script: Script = load(PACK_SCRIPT)
	var pack := ""
	if script != null:
		pack = str(script.get_script_constant_map().get("PACK_PATH", ""))
	h.check("the pack autoload still declares PACK_PATH", pack != "", PACK_SCRIPT)
	if pack != "":
		required.append(pack.trim_prefix("res://"))
	h.complete(case)

	for section in presets:
		var name := str(cfg.get_value(section, "name", section))
		case = "%s carries every runtime path" % name
		h.begin(case)
		var filters := _filters(str(cfg.get_value(section, "include_filter", "")))
		var missing: Array[String] = []
		for path in required:
			if not _covered(path, filters):
				missing.append(path)
		h.check("include_filter covers every path the engine opens",
			missing.is_empty(), ", ".join(missing))
		h.complete(case)

	print("")
	for path in required:
		print("  %s" % path)
	quit(h.finish("the export presets"))


## The `[preset.N]` sections, skipping their `.options` siblings.
static func _preset_sections(cfg: ConfigFile) -> Array[String]:
	var out: Array[String] = []
	for section in cfg.get_sections():
		var s := str(section)
		if s.begins_with("preset.") and not s.ends_with(".options"):
			out.append(s)
	return out


static func _filters(raw: String) -> Array[String]:
	var out: Array[String] = []
	for part in raw.split(",", false):
		var trimmed := str(part).strip_edges()
		if trimmed != "":
			out.append(trimmed)
	return out


## Godot matches an include entry against the project-relative path, with `*`
## standing for any run of characters. `games/*` is what carries everything
## beneath it, and `titles/*.pck` the generated pack.
static func _covered(path: String, filters: Array[String]) -> bool:
	for f in filters:
		if path == f or path.match(f):
			return true
	return false
