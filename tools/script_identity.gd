extends SceneTree
## Is each compiled script still attached to the same cast member?
##
##   godot --headless --script tools/script_identity.gd -- --a ORIG.DXR --b CONV.DIR
##
## `tools/chunk_digest.gd` sorts the per-chunk digests before combining them, so
## it proves the two files hold the *same set* of compiled scripts. It cannot see
## a permutation — and a permutation is the failure that matters, because
## `Lctx` references scripts by resource id while `mmap` (which assigns those
## ids) is rebuilt by the converter. Identical Lctx plus renumbered mmap would
## hand every script to the wrong owner: the movie loads, the art is right, and
## every behaviour fires on the wrong object.
##
## So this compares in resource-id order rather than as a set.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")


func _fnv(data: PackedByteArray) -> String:
	var h := 1469598103934665603
	for b in data:
		h = (h ^ int(b)) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	return "%016x" % h


func _scripts(path: String) -> Array:
	var f := ContainerFile.new()
	if not f.open(path):
		print("cannot open %s" % path)
		return []
	var out: Array = []
	for id in f.ids_of("Lscr"):
		var data: PackedByteArray = f.read_chunk(int(id))
		out.append({"id": int(id), "size": data.size(), "digest": _fnv(data)})
	f.close()
	return out


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var a := _scripts(Args.text(args, "a", ""))
	var b := _scripts(Args.text(args, "b", ""))
	if a.is_empty() or b.is_empty():
		quit(1)
		return

	print("Lscr chunks: A %d, B %d" % [a.size(), b.size()])
	print("")

	# 1. Same resource ids at all?
	var ids_a: Array = a.map(func(e): return int(e["id"]))
	var ids_b: Array = b.map(func(e): return int(e["id"]))
	print("resource ids identical: %s" % str(ids_a == ids_b))
	if ids_a != ids_b:
		print("  A first 12: %s" % str(ids_a.slice(0, 12)))
		print("  B first 12: %s" % str(ids_b.slice(0, 12)))

	# 2. Walking both in id order, does the same id carry the same bytecode?
	var by_id_b: Dictionary = {}
	for e in b:
		by_id_b[int(e["id"])] = e
	var moved := 0
	var absent := 0
	var shown := 0
	for e in a:
		var id := int(e["id"])
		if not by_id_b.has(id):
			absent += 1
			continue
		var other: Dictionary = by_id_b[id]
		if str(other["digest"]) != str(e["digest"]):
			moved += 1
			if shown < 12:
				shown += 1
				print("  id %-5d A %5d bytes %s   B %5d bytes %s" % [
					id, int(e["size"]), str(e["digest"]).substr(0, 8),
					int(other["size"]), str(other["digest"]).substr(0, 8),
				])
	print("")
	print("ids present in A but not B : %d" % absent)
	print("ids whose bytecode changed : %d  <-- a permutation shows up here" % moved)

	h.begin("each compiled script kept its resource id")
	h.check("the same resource ids exist in both", absent == 0, "%d absent" % absent)
	h.check("each id still carries the same bytecode", moved == 0, "%d moved" % moved)
	h.complete("each compiled script kept its resource id")
	quit(h.finish("script identity across the conversion"))
