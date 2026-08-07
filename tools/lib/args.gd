extends RefCounted
## `--key value`, `--key=value` and `--flag`, parsed once instead of four times.
##
##   const Args := preload("res://tools/lib/args.gd")
##   var a := Args.parse()
##   var movie := Args.text(a, "movie", "<default>")
##
## Godot swallows its own arguments, so a tool's arguments go after `--`:
##
##   godot --headless --script tools/hotspots.gd -- --file PIP2DATA/DAY1.dir --marker shore2
##
## Title-agnostic.

## Values are String; a bare `--flag` is the String "true".
static func parse(argv: PackedStringArray = PackedStringArray()) -> Dictionary:
	var source := argv if argv.size() > 0 else OS.get_cmdline_user_args()
	var out: Dictionary = {}
	var i := 0
	while i < source.size():
		var token := str(source[i])
		i += 1
		if not token.begins_with("--"):
			continue
		var key := token.substr(2)
		if key.contains("="):
			var cut := key.split("=", true, 1)
			out[cut[0]] = cut[1]
			continue
		if i < source.size() and not str(source[i]).begins_with("--"):
			out[key] = str(source[i])
			i += 1
		else:
			out[key] = "true"
	return out


static func text(args: Dictionary, key: String, fallback: String = "") -> String:
	return str(args.get(key, fallback))


static func number(args: Dictionary, key: String, fallback: int = 0) -> int:
	return int(str(args.get(key, fallback)))


static func flag(args: Dictionary, key: String) -> bool:
	if not args.has(key):
		return false
	var value := str(args[key]).to_lower()
	return value != "false" and value != "0"
