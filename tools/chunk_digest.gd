extends SceneTree
## Every chunk of two containers, hashed by type, so "what actually changed"
## stops being a guess.
##
##   godot --headless --script tools/chunk_digest.gd -- --a ORIG.DXR --b CONV.DIR
##
## Written to answer one question: a converted .dir broke a game that its
## original .dxr plays correctly, in the shipped projector, with everything else
## untouched. Counting chunks is not enough -- a chunk can keep its tag, its
## count and its size and still say something different -- so this digests the
## payload of every chunk of every type and reports which types disagree.
##
## On DAY1 the answer was: nothing that carries content. The score, all 118
## compiled scripts, every bitmap, the film loops, the name and context tables,
## the cast linkage and the labels are byte-identical. Only DRCF (7 bytes: a
## protection marker, one unidentified field, and a checksum) and the CASt info
## blocks (which gained the decompiled source text) differ.
##
## Title-agnostic, and deliberately not limited to tags this engine knows -- the
## chunk that matters is the one nobody thought to look at.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")


func _profile(path: String) -> Dictionary:
	var f := ContainerFile.new()
	if not f.open(path):
		print("cannot open %s: %s" % [path, f.error])
		return {}
	var out: Dictionary = {}
	for tag in f.census():
		var total := 0
		var digests: Array[String] = []
		for id in f.ids_of(tag):
			var data: PackedByteArray = f.read_chunk(int(id))
			total += data.size()
			digests.append(_fnv(data))
		digests.sort()
		out[tag] = {
			"count": f.ids_of(tag).size(),
			"bytes": total,
			"digest": _fnv_str("".join(digests)),
		}
	f.close()
	return out


func _init() -> void:
	var args := Args.parse()
	var a := _profile(Args.text(args, "a", ""))
	var b := _profile(Args.text(args, "b", ""))
	if a.is_empty() or b.is_empty():
		quit(1)
		return
	var tags: Dictionary = {}
	for t in a:
		tags[t] = true
	for t in b:
		tags[t] = true
	var keys: Array = tags.keys()
	keys.sort()
	print("%-6s %-26s %-26s" % ["tag", "A (original)", "B (converted)"])
	for t in keys:
		var ea: Dictionary = a.get(t, {"count": 0, "bytes": 0, "digest": "-"})
		var eb: Dictionary = b.get(t, {"count": 0, "bytes": 0, "digest": "-"})
		var same: bool = str(ea.get("digest", "")) == str(eb.get("digest", ""))
		print("%-6s %5d x %10d  %-14s %5d x %10d  %-14s  %s" % [
			t, int(ea["count"]), int(ea["bytes"]), str(ea["digest"]),
			int(eb["count"]), int(eb["bytes"]), str(eb["digest"]),
			"" if same else "<-- DIFFERS",
		])
	quit(0)


func _fnv(data: PackedByteArray) -> String:
	var h := 1469598103934665603
	for b in data:
		h = (h ^ int(b)) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	return "%016x" % h


func _fnv_str(text: String) -> String:
	return _fnv(text.to_utf8_buffer())
