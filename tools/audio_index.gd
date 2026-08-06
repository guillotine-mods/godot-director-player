extends SceneTree
## The sounds the game names actually resolve, and actually load.
##
##   godot --headless --script tools/audio_index.gd
##   godot --headless --script tools/audio_index.gd -- --stem hez1
##
## `AudioDirector.resolve_path` matches on stem and discards the extension,
## which is why `play_file(1, "pi%s.aif" % item)` has been resolving to `.wav`
## all along. That tolerance is what lets the backing format change without a
## single call site moving — and it is also why a missing sound is invisible:
## an unresolved stem plays nothing and reports nothing.
##
## So this asserts two separate things. Resolving is not loading: a stem can
## resolve to a path that then decodes to silence, which sounds exactly like a
## sound that was never wired up.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Names the game asks for by hand, from `director/director_runtime.gd` and the
## original Lingo. Chosen because each is a different kind: a per-item voice
## line, a UI effect, and an inventory sound.
const WANTED := ["found", "moveinv", "stukinv", "pbag", "action", "bang"]


## `_initialize`, not `_init`: the script is constructed before the tree is
## populated, so an autoload looked up in `_init` is reliably absent.
func _initialize() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var audio := root.get_node_or_null("AudioDirector")
	if audio == null:
		print("AudioDirector autoload is not present")
		quit(1)
		return

	var one := Args.text(args, "stem")
	var wanted: Array = [one] if one != "" else WANTED

	h.begin("the game's sounds resolve and load")
	var resolved := 0
	var loaded := 0
	var missing: Array[String] = []
	var silent: Array[String] = []
	for stem in wanted:
		var path: String = audio.resolve_path(str(stem))
		if path == "":
			missing.append(str(stem))
			continue
		resolved += 1
		# Reaching through to the loader on purpose: `play_file` would need a
		# running tree and would swallow the answer.
		var stream: AudioStream = audio.call("_load_stream", path)
		var length := stream.get_length() if stream != null else 0.0
		if stream == null or length <= 0.0:
			silent.append("%s -> %s" % [stem, path])
			continue
		loaded += 1
		print("  %-10s %5.2fs  %s" % [stem, length, path])

	h.check("%d of %d stem(s) resolved" % [resolved, wanted.size()],
		missing.is_empty(), "" if missing.is_empty() else "missing: %s" % ", ".join(missing))
	h.check("%d of %d loaded to a stream with audio in it" % [loaded, resolved],
		silent.is_empty(), "" if silent.is_empty() else "silent: %s" % "; ".join(silent))
	h.complete("the game's sounds resolve and load")

	quit(h.finish("the game's own sounds are reachable through AudioDirector"))
