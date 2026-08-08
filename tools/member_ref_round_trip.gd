extends SceneTree
## `the castNum of sprite` has to survive being handed back to `member()`.
##
##   godot --headless --script tools/member_ref_round_trip.gd
##   godot --headless --script tools/member_ref_round_trip.gd -- --root rating
##
## Title-agnostic: it names no movie, channel or member, and sweeps whatever
## corpus `--root` selects.
##
## **The defect this guards was two modules each being reasonable alone.**
## `sprite_state.read_prop` answered `the castNum of sprite` with the bare
## `cast_id`, and `members.resolve_ref` resolves a bare number in library 1 --
## which is right, because a bare number is all Director gives it. Neither is
## wrong on its own; the pair loses the library, and a member number without its
## library is not an address. So the assertion below is deliberately a *chain*
## through both, not a unit test of either: pack-then-unpack inside one module
## would pass while the port was broken.
##
## What it cost: every Piposh 1 deck movie opens with
## `set nof to the name of member the castNum of sprite 1`, reading the deck
## position off the backdrop's member name. Channel 1 is in library 2 there, so
## `nof` came back as an unrelated library-1 member and the ship map -- which
## hides the walking figure for any `nof` of four characters or more, and gates
## every one of its destination handlers on that figure being visible -- lost
## both the character and every way off it.
##
## The corpus reaches this through two spellings and both directions:
## `member(the castNum of sprite 1).name` in five titles, Piposh 1's
## `the name of member the castNum of sprite 1`, and `rating`'s
## `set the castNum of sprite 18 to the number of member ...`, whose right-hand
## side is a bare number. The second assertion below is that write direction's
## guard: `the memberNum of sprite` must stay bare, or the arithmetic every
## `set the memberNum of sprite N to the number of member (...)` does breaks.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const SpriteState := preload("res://scenes/preview/sprite_state.gd")
const Members := preload("res://scenes/preview/members.gd")


func _init() -> void:
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie"
			% Paths.CONFIG_PATH)
		quit(1)
		return
	var args := Args.parse()

	var checked := 0
	var outside := 0
	var movies := 0
	var wrong: Array[String] = []
	var bare_wrong: Array[String] = []
	for path in _containers(paths.root, Args.text(args, "file")):
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var vwsc: Array = f.ids_of("VWSC")
		if vwsc.is_empty():
			f.close()
			continue
		var score := Score.new()
		if not score.parse(f.read_chunk(vwsc[0])):
			f.close()
			continue
		var table := CastTable.new()
		table.open(f, paths)
		movies += 1
		var seen := {}
		# One frame is enough and the whole score is not: the property is a
		# function of the sprite record, and sweeping 4,625 frames of every movie
		# re-asks the same question about the same handful of members.
		for index in mini(score.frame_count, int(Args.number(args, "frames", 4))):
			var frame: Dictionary = score.frame(index)
			var sprites: Array = frame.get("sprites", [])
			for sprite in sprites:
				var lib := int(sprite.get("cast_lib", 1))
				var id := int(sprite["cast_id"])
				var key := "%d:%d" % [lib, id]
				if seen.has(key) or id <= 0:
					continue
				seen[key] = true
				var member: Dictionary = table.get_member(lib, id)
				if member.is_empty():
					continue
				checked += 1
				if lib > 1:
					outside += 1
				# The chain: what a script reads, handed to what `member()` does
				# with it, against the member the score actually put there.
				var got = SpriteState.read_prop(
					int(sprite["channel"]), "castnum", {}, sprites)
				var back: Array = Members.resolve_ref(got, "", table)
				if int(back[0]) != lib or int(back[1]) != id:
					wrong.append("%s ch%d %s -> castNum %s -> %d:%d" % [
						path.get_file(), int(sprite["channel"]), key,
						str(got), int(back[0]), int(back[1])])
				# And the other spelling stays a plain number, because every
				# `set the memberNum of sprite N to the number of member (...)`
				# in the corpus does arithmetic on one.
				var bare = SpriteState.read_prop(
					int(sprite["channel"]), "membernum", {}, sprites)
				if typeof(bare) != TYPE_INT or int(bare) != id:
					bare_wrong.append("%s ch%d %s -> memberNum %s" % [
						path.get_file(), int(sprite["channel"]), key, str(bare)])
		f.close()

	print("%s: %d movie(s), %d distinct sprite member(s), %d outside library 1"
		% [paths.root, movies, checked, outside])
	h.begin("a sprite's member reference survives a round trip through Lingo")
	h.check("the corpus was read", checked > 0, "%d member(s)" % checked)
	# Not a hard failure: a corpus whose every sprite is in library 1 cannot
	# exercise the bug, and saying so is more useful than passing quietly.
	if outside == 0:
		print("  note: nothing outside library 1 here, so the round trip is "
			+ "exercised only on the identity case")
	h.check("the castNum of sprite resolves back to its own member",
		wrong.is_empty(), ", ".join(PackedStringArray(wrong.slice(0, 6))))
	h.check("the memberNum of sprite stays a bare member number",
		bare_wrong.is_empty(), ", ".join(PackedStringArray(bare_wrong.slice(0, 6))))
	h.complete("a sprite's member reference survives a round trip through Lingo")
	quit(h.finish("member references across the corpus"))


func _containers(root: String, only: String) -> Array:
	if only != "":
		var paths := Paths.new()
		paths.load_config()
		var one = paths.resolve(only)
		return [one] if one != "" else []
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full := dir_path.path_join(name)
			if d.current_is_dir():
				stack.append(full)
			elif name.to_lower().ends_with(".dir") or name.to_lower().ends_with(".dxr"):
				out.append(full)
			name = d.get_next()
		d.list_dir_end()
	out.sort()
	return out
