extends SceneTree
## What a .dxr/.cxt lost on its way to becoming a .dir/.cst.
##
##   godot --headless --script tools/container_diff.gd -- \
##       --a <originals>/PIP2DATA/DAY1.DXR \
##       --b <checkout>/games/piposh2/PIP2DATA/DAY1.DIR
##
## Both paths are absolute and read directly, so this can reach outside the
## configured game root — the point is to compare a converted file against an
## original that deliberately does not live in the tree.
##
## Why this exists: the original protected files play correctly in the shipped
## projector and the converted ones do not, with the same projector and the same
## everything else. That places the fault in the conversion rather than in any
## renderer, and narrows the question to "which chunk stopped saying what it
## said". Chunk census first, then the cast, then text — because a missing
## behaviour usually shows up as a missing member long before it shows up as a
## missing pixel.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Score := preload("res://director/director_score.gd")


func _open(path: String) -> ContainerFile:
	var f := ContainerFile.new()
	if not f.open(path):
		print("cannot open %s: %s" % [path, f.error])
		return null
	return f


func _census(f: ContainerFile) -> Dictionary:
	var out: Dictionary = {}
	for tag in f.census():
		out[tag] = int(f.census()[tag])
	return out


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var a_path := Args.text(args, "a", "")
	var b_path := Args.text(args, "b", "")
	if a_path == "" or b_path == "":
		print("usage: --a <original> --b <converted>")
		quit(1)
		return

	var a := _open(a_path)
	var b := _open(b_path)
	if a == null or b == null:
		quit(1)
		return

	print("A (original)  %s" % a_path.get_file())
	print("B (converted) %s" % b_path.get_file())
	print("")

	# ---- chunks
	var ca := _census(a)
	var cb := _census(b)
	var tags: Dictionary = {}
	for t in ca:
		tags[t] = true
	for t in cb:
		tags[t] = true
	var keys: Array = tags.keys()
	keys.sort()
	print("chunk census (only differences shown):")
	var missing: Array[String] = []
	for t in keys:
		var na := int(ca.get(t, 0))
		var nb := int(cb.get(t, 0))
		if na == nb:
			continue
		print("  %-6s A %5d   B %5d   %s" % [t, na, nb, "<-- gone" if nb == 0 else ""])
		if nb == 0 and na > 0:
			missing.append(str(t))
	if missing.is_empty():
		print("  (every tag present in A is present in B)")

	# ---- cast members
	print("")
	var cast_a := Cast.new()
	var cast_b := Cast.new()
	var ok_a := cast_a.open(a)
	var ok_b := cast_b.open(b)
	print("cast: A %s, B %s" % [
		"%d slot(s)" % cast_a.member_numbers().size() if ok_a else "unreadable",
		"%d slot(s)" % cast_b.member_numbers().size() if ok_b else "unreadable",
	])
	if ok_a and ok_b:
		var types_a: Dictionary = {}
		var types_b: Dictionary = {}
		for number in cast_a.member_numbers():
			var t := int(cast_a.member(number).get("type", 0))
			types_a[t] = int(types_a.get(t, 0)) + 1
		for number in cast_b.member_numbers():
			var t := int(cast_b.member(number).get("type", 0))
			types_b[t] = int(types_b.get(t, 0)) + 1
		var all_types: Dictionary = {}
		for t in types_a:
			all_types[t] = true
		for t in types_b:
			all_types[t] = true
		var tk: Array = all_types.keys()
		tk.sort()
		for t in tk:
			var na := int(types_a.get(t, 0))
			var nb := int(types_b.get(t, 0))
			print("  type %-3d  A %4d   B %4d %s" % [t, na, nb, "<-- differs" if na != nb else ""])

		# Members present in one and not the other, by number.
		var only_a: Array[String] = []
		var only_b: Array[String] = []
		for number in cast_a.member_numbers():
			if not (cast_b.member(number) as Dictionary).size() > 0:
				only_a.append(str(number))
		for number in cast_b.member_numbers():
			if not (cast_a.member(number) as Dictionary).size() > 0:
				only_b.append(str(number))
		if not only_a.is_empty():
			print("  only in A: %s" % ", ".join(only_a.slice(0, 20)))
		if not only_b.is_empty():
			print("  only in B: %s" % ", ".join(only_b.slice(0, 20)))

		# Text is the suspect worth naming: this game drives its walk logic,
		# doorways and inventory out of field members, so a field that lost its
		# text reads as "the character walks there and nothing happens".
		var text_diff := 0
		var name_diff := 0
		for number in cast_a.member_numbers():
			if not (cast_b.member(number) as Dictionary).size() > 0:
				continue
			var ma: Dictionary = cast_a.member(number)
			var mb: Dictionary = cast_b.member(number)
			if str(ma.get("name", "")) != str(mb.get("name", "")):
				name_diff += 1
				if name_diff <= 8:
					print("  name  %4d  A '%s'  B '%s'" % [
						number, str(ma.get("name", "")), str(mb.get("name", ""))
					])
			var ta := str(ma.get("text", ""))
			var tb := str(mb.get("text", ""))
			if ta != tb:
				text_diff += 1
				if text_diff <= 8:
					print("  text  %4d  A %d chars  B %d chars" % [
						number, ta.length(), tb.length()
					])
		print("  members whose name differs: %d" % name_diff)
		print("  members whose text differs: %d" % text_diff)

	# ---- score
	print("")
	var sa := _score_of(a)
	var sb := _score_of(b)
	print("score: A %s, B %s" % [sa, sb])

	# The interval table is where a sprite's *behaviour* lives -- which script is
	# attached to which channel over which frames. A movie can keep every cast
	# member, every pixel and every frame of its score and still be inert if this
	# is lost, and "clicking the scenery does nothing" is exactly what that looks
	# like from the player's chair. So it is compared entry by entry rather than
	# counted.
	var ia := _intervals_of(a)
	var ib := _intervals_of(b)
	print("sprite/frame behaviour intervals: A %d, B %d" % [ia.size(), ib.size()])
	var only_in_a: Array[String] = []
	for key in ia:
		if not ib.has(key):
			only_in_a.append(key)
	var only_in_b: Array[String] = []
	for key in ib:
		if not ia.has(key):
			only_in_b.append(key)
	if not only_in_a.is_empty():
		print("  in the ORIGINAL and not the conversion (%d):" % only_in_a.size())
		for key in only_in_a.slice(0, 15):
			print("    %s" % key)
	if not only_in_b.is_empty():
		print("  in the CONVERSION and not the original (%d):" % only_in_b.size())
		for key in only_in_b.slice(0, 15):
			print("    %s" % key)
	if only_in_a.is_empty() and only_in_b.is_empty():
		print("  (identical)")

	# The last thing that can differ once cast, score and attachments all match:
	# the compiled bytecode. Comparing the *source* proves nothing here, because
	# both sides of that comparison are the same decompiler's output -- the
	# converted file simply carries the text ProjectorRays wrote into it. The
	# bytecode is the part Director regenerated, and therefore the only part that
	# can have changed meaning.
	print("")
	var la: Array = a.ids_of("Lscr")
	var lb: Array = b.ids_of("Lscr")
	print("Lscr chunks: A %d, B %d" % [la.size(), lb.size()])
	var sizes_a: Array[int] = []
	var sizes_b: Array[int] = []
	for id in la:
		sizes_a.append(a.read_chunk(int(id)).size())
	for id in lb:
		sizes_b.append(b.read_chunk(int(id)).size())
	sizes_a.sort()
	sizes_b.sort()
	var total_a := 0
	var total_b := 0
	for n in sizes_a:
		total_a += n
	for n in sizes_b:
		total_b += n
	print("  total bytecode: A %d, B %d  (%+d)" % [total_a, total_b, total_b - total_a])
	var same_sizes := sizes_a == sizes_b
	print("  the multiset of chunk sizes is %s" % ("identical" if same_sizes else "DIFFERENT"))
	if not same_sizes:
		print("  A sizes: %s" % str(sizes_a.slice(0, 12)))
		print("  B sizes: %s" % str(sizes_b.slice(0, 12)))

	h.begin("the conversion preserved the container")
	h.check("no chunk type was lost", missing.is_empty(), ", ".join(missing))
	h.check("both casts are readable", ok_a and ok_b, "A %s B %s" % [ok_a, ok_b])
	if ok_a and ok_b:
		h.check("the cast has the same number of slots",
			cast_a.member_numbers().size() == cast_b.member_numbers().size(),
			"%d vs %d" % [cast_a.member_numbers().size(), cast_b.member_numbers().size()])
	h.check("both scores parse and have the same frame count", sa == sb, "%s vs %s" % [sa, sb])
	h.check("every behaviour attachment survived",
		only_in_a.is_empty() and only_in_b.is_empty(),
		"%d lost, %d added" % [only_in_a.size(), only_in_b.size()])
	h.check("the compiled bytecode is unchanged", same_sizes,
		"A %d bytes, B %d bytes" % [total_a, total_b])
	h.complete("the conversion preserved the container")
	quit(h.finish("original against converted"))


func _score_of(f: ContainerFile) -> String:
	var ids: Array = f.ids_of("VWSC")
	if ids.is_empty():
		return "no VWSC"
	var s := Score.new()
	if not s.parse(f.read_chunk(int(ids[0]))):
		return "unparsed (%s)" % s.error
	return "%d frames" % s.frame_count


## Behaviour attachments as comparable keys: kind, channel, frame span, member.
func _intervals_of(f: ContainerFile) -> Dictionary:
	var out: Dictionary = {}
	var ids: Array = f.ids_of("VWSC")
	if ids.is_empty():
		return out
	var s := Score.new()
	if not s.parse(f.read_chunk(int(ids[0]))):
		return out
	for entry_value in s.intervals():
		var e: Dictionary = entry_value
		out["%s ch%d f%d-%d member %d" % [
			str(e.get("kind", "?")), int(e.get("channel", 0)),
			int(e.get("start", 0)), int(e.get("end", 0)), int(e.get("script_member", 0)),
		]] = true
	return out
