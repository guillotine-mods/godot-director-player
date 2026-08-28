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
## The write/read pair the Lingo host actually calls. `SpriteState` is one seam
## deeper and does **not** apply `ALIASES`, so writing "member" through it stores
## a key the `membernum` read never looks at -- which is how the first version of
## the override case below passed against the bug it was written for.
const SpriteProps := preload("res://scenes/preview/sprite_props.gd")
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
	## One real sprite outside library 1, kept for the override case at the end.
	var probe: Dictionary = {}
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
				# Keep one real sprite outside library 1 for the override case
				# below. A real one rather than a synthetic dictionary, because the
				# bare-value arm falls back to *the sprite's own* library and a
				# fabricated record would not test that.
				if lib > 1 and probe.is_empty():
					probe = {
						"channel": int(sprite["channel"]), "lib": lib, "id": id,
						"sprites": sprites, "where": path.get_file(), "other": 0,
					}
				# A second channel, in library 1, for the channel-to-channel hop
				# below. It has to be a different channel of the *same* frame, so
				# the value really crosses between two sprite records.
				if lib == 1 and not probe.is_empty() and int(probe["other"]) == 0 \
						and int(sprite["channel"]) != int(probe["channel"]):
					probe["other"] = int(sprite["channel"])
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

	# ------------------------------------------------- and after a script writes
	# **Everything above passes `{}` for the overrides, so all of it is the score
	# path.** That is exactly half the property, and the missing half is the half
	# the corpus actually uses: `piposh-dream` writes `the member of sprite N` at
	# 1,453 sites and reads the number back afterwards. `channel.gd:read` returned
	# a script's stored value *raw*, with no `kind` conversion, so the
	# `membernum`/`castnum` split held only while the score owned the channel and
	# collapsed the moment Lingo wrote one -- and `member(3, 2)` evaluates to a
	# **packed** reference, so `the memberNum of sprite` answered 131,075.
	#
	# Measured cost: `hatuli.cst`'s `hatulidown`/`hatuliup` gate every movement
	# branch on `the memberNum of sprite 15` against 2, 18, 29 and 40. At 131,075
	# `< 29` is false *and* `> 18` is true, so the branches fail in both
	# directions at once and the player cannot move. The Fritz duel reads the same
	# property against 18 and 46.
	#
	# A write-then-read in one module would be the unit test this file's own header
	# refuses, so the write goes in as Lingo's own value -- `pack_ref`, which is
	# what `member()` produces -- and the read comes back out through both
	# spellings and then through `resolve_ref`, the same chain as above.
	if probe.is_empty():
		print("  note: no sprite outside library 1, so the override case is skipped")
	else:
		h.begin("and it survives a script having written it")
		var channel := int(probe["channel"])
		var lib := int(probe["lib"])
		var id := int(probe["id"])
		var sprites: Array = probe["sprites"]
		var overrides: Dictionary = {}
		SpriteProps.write(channel, "member", Members.pack_ref(lib, id),
			overrides, sprites, {})
		var bare_after = SpriteProps.read(channel, "membernum", overrides, sprites, {})
		h.check("the memberNum of sprite is still bare after a script wrote member()",
			typeof(bare_after) == TYPE_INT and int(bare_after) == id,
			"%s ch%d wrote member(%d, %d) -> memberNum %s, wanted %d" % [
				str(probe["where"]), channel, id, lib, str(bare_after), id])
		var ref_after = SpriteProps.read(channel, "castnum", overrides, sprites, {})
		var table_for_ref := CastTable.new()
		var back_after: Array = Members.resolve_ref(ref_after, "", table_for_ref)
		h.check("the castNum of sprite still resolves to the member that was written",
			int(back_after[0]) == lib and int(back_after[1]) == id,
			"castNum %s -> %d:%d, wanted %d:%d" % [
				str(ref_after), int(back_after[0]), int(back_after[1]), lib, id])
		# The bare direction too: `rating` writes a plain number, and it has to
		# keep the library the sprite is already in rather than falling to 1.
		var bare_overrides: Dictionary = {}
		SpriteProps.write(channel, "membernum", id, bare_overrides, sprites, {})
		var ref_from_bare = SpriteProps.read(channel, "castnum", bare_overrides, sprites, {})
		var back_bare: Array = Members.resolve_ref(ref_from_bare, "", table_for_ref)
		h.check("a bare memberNum write keeps the sprite's own library",
			int(back_bare[0]) == lib and int(back_bare[1]) == id,
			"wrote memberNum %d -> castNum %s -> %d:%d, wanted %d:%d" % [
				id, str(ref_from_bare), int(back_bare[0]), int(back_bare[1]), lib, id])

		# ------------------------------------ the third spelling, and the hop
		# **`the member of sprite` is a reference too**, and it is the spelling a
		# script swaps *between two channels* through a Lingo variable. Its row
		# carried `memberNum`'s bare-slot kind on the reasoning that only the
		# release rule separates them, so this read handed back a slot with no
		# library and the write took a packed reference: a value that crossed
		# channels lost its library on the way.
		#
		# `piposh-dream`'s `strata2` (`1:136`) is the site. It depth-sorts four
		# fighters by exchanging the contents of their channels --
		# `x = the member of sprite ppl[i]`, then the two writes -- so a fighter
		# whose frame is in library 2 was re-seated as library 1's member of the
		# same number. The sort runs when two fighters cross in depth, which is
		# what a hit does, so it read as enemies turning into something else
		# *sometimes*, on being hit.
		var ref_member = SpriteProps.read(channel, "member", overrides, sprites, {})
		var back_member: Array = Members.resolve_ref(ref_member, "", table_for_ref)
		h.check("the member of sprite resolves to the member that was written",
			int(back_member[0]) == lib and int(back_member[1]) == id,
			"member %s -> %d:%d, wanted %d:%d" % [
				str(ref_member), int(back_member[0]), int(back_member[1]), lib, id])
		# The library half of the same write, which is a gate and not a display:
		# `chkhit` in the Fritz duel branches on `the castLibNum of sprite = 2`.
		var lib_after = SpriteProps.read(channel, "castlibnum", overrides, sprites, {})
		h.check("the castLibNum of sprite follows a script's member write",
			int(lib_after) == lib,
			"wrote member(%d, %d) -> castLibNum %s, wanted %d" % [
				id, lib, str(lib_after), lib])
		if int(probe["other"]) == 0:
			print("  note: this frame has no second library-1 channel, so the "
				+ "channel-to-channel hop is skipped")
		else:
			var other := int(probe["other"])
			var hop: Dictionary = {}
			SpriteProps.write(other, "member", ref_member, hop, sprites, {})
			var landed = SpriteProps.read(other, "castnum", hop, sprites, {})
			var back_hop: Array = Members.resolve_ref(landed, "", table_for_ref)
			h.check("a member read off one channel keeps its library when written to another",
				int(back_hop[0]) == lib and int(back_hop[1]) == id,
				"ch%d -> ch%d carried %s -> %d:%d, wanted %d:%d" % [
					channel, other, str(ref_member),
					int(back_hop[0]), int(back_hop[1]), lib, id])
		h.complete("and it survives a script having written it")

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
