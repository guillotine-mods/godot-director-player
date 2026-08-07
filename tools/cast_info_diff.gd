extends SceneTree
## What a converter changed inside a cast member's info block.
##
##   godot --headless --script tools/cast_info_diff.gd -- --a ORIG.DXR --b CONV.DIR
##
## A `CASt` chunk is `type(4) infoLen(4) specLen(4)` then the info block then the
## spec. The spec is the member's own data — for a script member that is its
## kind and flags — and comparing it is easy. The *info* block is the awkward
## one: it is a header followed by a little offset table, and the entries are
## per-type. Entry 0 is a script member's source text and entry 1 is its name,
## which is why a decompiler that restores source only has to touch entry 0.
##
## This exists because on DAY1 the info block is the only thing that changed and
## the movie stopped working. Everything else — score, all 118 compiled scripts
## byte-identical at the same resource ids, every bitmap, the cast linkage, the
## spec blocks — is provably untouched. So whatever went wrong is in here, and
## the question is whether the converter changed anything *besides* the text.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")


func _be32(d: PackedByteArray, o: int) -> int:
	if o + 3 >= d.size():
		return -1
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


## The info block's own header, then its offset table. Returns the header fields
## and the length of every entry, which is what a comparison actually needs.
func _info_shape(info: PackedByteArray) -> Dictionary:
	if info.size() < 4:
		return {}
	var header_len := _be32(info, 0)
	if header_len < 0 or header_len + 8 > info.size():
		return {}
	var offsets_at := header_len
	var count := _be32(info, offsets_at + 4)
	var lengths: Array[int] = []
	var table := offsets_at + 8
	if count < 0 or count > 64 or table + (count + 1) * 4 > info.size():
		return {"header_len": header_len, "count": count, "lengths": lengths}
	for i in count:
		var lo := _be32(info, table + i * 4)
		var hi := _be32(info, table + (i + 1) * 4)
		lengths.append(hi - lo)
	return {
		"header_len": header_len,
		"count": count,
		"lengths": lengths,
		"header": info.slice(0, mini(header_len, 64)),
	}


func _casts(path: String) -> Array:
	var f := ContainerFile.new()
	if not f.open(path):
		print("cannot open %s" % path)
		return []
	var out: Array = []
	for id in f.ids_of("CASt"):
		var c: PackedByteArray = f.read_chunk(int(id))
		if c.size() < 12:
			continue
		var info_len := _be32(c, 4)
		out.append({
			"id": int(id),
			"type": _be32(c, 0),
			"info": c.slice(12, 12 + info_len),
		})
	f.close()
	return out


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var a := _casts(Args.text(args, "a", ""))
	var b := _casts(Args.text(args, "b", ""))
	if a.is_empty() or b.is_empty():
		quit(1)
		return
	print("CASt chunks: A %d, B %d" % [a.size(), b.size()])

	var header_diff := 0
	var count_diff := 0
	var nontext_diff := 0
	var shown := 0
	for i in mini(a.size(), b.size()):
		var ea: Dictionary = a[i]
		var eb: Dictionary = b[i]
		var sa := _info_shape(ea["info"])
		var sb := _info_shape(eb["info"])
		if sa.is_empty() or sb.is_empty():
			continue
		if str(sa.get("header", PackedByteArray())) != str(sb.get("header", PackedByteArray())):
			header_diff += 1
		if int(sa["count"]) != int(sb["count"]):
			count_diff += 1
			if shown < 10:
				shown += 1
				print("  id %-5d type %d  entry count %d -> %d" % [
					int(ea["id"]), int(ea["type"]), int(sa["count"]), int(sb["count"])
				])
			continue
		# Entry 0 is the source text; every other entry should be untouched.
		var la: Array = sa["lengths"]
		var lb: Array = sb["lengths"]
		var others_changed := false
		for k in range(1, mini(la.size(), lb.size())):
			if int(la[k]) != int(lb[k]):
				others_changed = true
		if others_changed:
			nontext_diff += 1
			if shown < 10:
				shown += 1
				print("  id %-5d type %d  lengths A %s" % [int(ea["id"]), int(ea["type"]), str(la)])
				print("                        B %s" % str(lb))

	print("")
	print("info header differs        : %d" % header_diff)
	print("entry COUNT differs        : %d" % count_diff)
	print("a non-text entry's length  : %d" % nontext_diff)

	h.begin("only the source text entry changed")
	h.check("the info header is untouched", header_diff == 0, "%d differ" % header_diff)
	h.check("the entry count is untouched", count_diff == 0, "%d differ" % count_diff)
	h.check("no entry other than the text changed length", nontext_diff == 0,
		"%d differ" % nontext_diff)
	h.complete("only the source text entry changed")
	quit(h.finish("cast info blocks across the conversion"))
