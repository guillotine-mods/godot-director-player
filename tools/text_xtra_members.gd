extends SceneTree
## The `text` Xtra members: what they are, what uses them, and what promoting one
## would collide with.
##
##   godot --headless --path . --script tools/text_xtra_members.gd -- --all
##   godot --headless --path . --script tools/text_xtra_members.gd -- --root piposh
##   godot --headless --path . --script tools/text_xtra_members.gd -- --all --verbose
##
## `bugs.md` 82's remainder. Of 566 Xtra members across the tree, five symbols,
## and the reference registers four names (`cursor`, `quickTimeMedia`, `text`,
## `font`) in `castmember/xtra.cpp:xtraCastMemberProtos`; everything else falls
## through `XtraCastMember::promote` to `CastMember::createWidget` returning
## `nullptr`, so drawing nothing for it is correct. **`text` is the one symbol in
## this corpus that the reference does promote**, to `TextXtra`, and the entry
## asked for a measurement before anybody promotes it here.
##
## This is that measurement. Four questions, and each one is answered from the
## container rather than reasoned about:
##
## 1. **Is there anything behind the member?** The reference's `TextXtra` gets its
##    text from an `XMED` child chunk and nothing else
##    (`lingo/xtras-cast/textxtra.cpp:TextXtraCastMember::load`, ScummVM
##    805f259a). A member with no `XMED` has no text to draw, whatever it is
##    promoted to, so this is the question that decides whether promotion buys
##    anything at all. **All eleven have one, all eleven decode**, and the decode
##    is re-derived here from the chunk bytes rather than read off the member --
##    `_decode_xmed` below is this tool's own copy of the reference's algorithm,
##    so it and `director_cast.gd:decode_xmed` are two readings that can disagree.
##
## 2. **Why is the `xtraRect` 0x0?** Because the geometry of *this* Xtra is not
##    in the info block at all: `TextXtra::parseXtraData` reads a big-endian
##    int32 height at offset 36 of the Xtra's own payload and a width at 40, and
##    the constructor assigns that to `_initialRect`. So a 0x0 `xtraRect` on a
##    `text` member is not a decode gap, it is the wrong place to look, and this
##    prints both numbers side by side.
##
## 3. **Is it drawn, or only read?** Every score record in the container is
##    walked and matched against the member, so "no sprite anywhere names it" is
##    a measurement over the whole score and not over the frames somebody looked
##    at.
##
## 4. **What would the name lookup do with it?** This is the expensive half and
##    the reason `bugs.md` 82 said promotion is not free: `director_cast.gd:232`
##    records `SLOTMACH.dir` #83 `credit`, an Xtra, sharing its name with the
##    *field* #97 `credit` that the slot machine's score draws -- the collision
##    fixed in `02844f93` by making the typed lookup type-aware. For every one of
##    these members this prints every other member of the same cast with the same
##    name and its type, and what `number_of` and `number_of_type(name, 3)`
##    answer today.
##
## ## What is asserted
##
## Only things this port controls, and the fourth question is the one that
## matters:
##
##   * **the typed name lookup never answers an Xtra member.** This is the
##     invariant that keeps the slot machine fixed, and it holds under promotion
##     *for the same reason the reference holds it*: `TextXtraCastMember` sets
##     `_type = kCastXtra`, so `Cast::rebuildCastNameCache` keys it `credit:15`
##     and `field "credit"` -- which asks for `credit:3` -- still cannot see it.
##     A port that promoted these into type-3 members would break that; a port
##     that promotes them the way the reference does cannot.
##   * **and the same collision from the other side**: where a `text` Xtra shares
##     its name with a *field*, `number_of_type(name, field)` answers the field's
##     own number and `number_of_type(name, xtra)` answers the Xtra's. Asserting
##     only the first is asserting that the typed lookup finds nothing, which a
##     lookup that answered nothing at all would also pass. In `piposh` the pair
##     is `SLOTMACH.dir` #83 (Xtra) and #97 (field), so this is
##     `number_of('credit') = 83` and `number_of_type('credit', field) = 97`
##     stated as a rule rather than as two numbers about one disc.
##   * **promotion keeps the type.** The member's `type` is still 15 and its
##     `type_name` still `xtra` after `_promote_text_xtra` has run, which is the
##     mechanical reason the two rows above hold rather than a restatement of
##     them: they are properties of the name cache, this is a property of the
##     record the name cache is built from.
##   * every `text` Xtra's payload is long enough to carry the rect the reference
##     reads out of it, so the answer to question 2 is a fact about the bytes;
##   * every `XMED` decodes, and the member's text is the bytes this tool decodes
##     for itself out of the same chunk;
##   * the untyped lookup obeys lowest-number-wins where a name is shared, which
##     is the rule `_build_names` implements and the rule the collision is under.
##
## Reported and not asserted: how many there are, where they are, and whether
## anything draws them. Those are properties of six 1997 discs.
##
## Title-agnostic: it names no movie and finds its members by symbol.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")
const Codepage := preload("res://director/director_codepage.gd")

const XTRA := 15
const FIELD := 3
## `TextXtra::parseXtraData` refuses a payload shorter than this and reads the
## height at 36 and the width at 40, both big-endian int32.
const XTRA_DATA_MIN := 44
const RECT_H_AT := 36
const RECT_W_AT := 40
## The same sanity bounds the reference applies to what it reads there.
const RECT_MAX := 0x4000


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var verbose := Args.flag(args, "verbose")

	var roots: Array[String] = []
	if Args.flag(args, "all"):
		for parent in ["res://games", "res://test-games"]:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	else:
		var paths := Paths.new()
		paths.load_config()
		roots.append(str(paths.root))
	roots.sort()

	var found := 0
	var with_xmed := 0
	var payload_rect_ok := 0
	var payload_too_short: Array[String] = []
	var sized_wrong: Array[String] = []
	var scored := 0
	var name_shared := 0
	var typed_hits_xtra: Array[String] = []
	var untyped_out_of_order: Array[String] = []
	var seen_casts: Dictionary = {}
	var decoded := 0
	var not_decoded: Array[String] = []
	var text_disagrees: Array[String] = []
	var type_moved: Array[String] = []
	var field_twins := 0
	var field_twin_lost: Array[String] = []

	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		var member_paths := Paths.new()
		member_paths.root = root
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var table := CastTable.new()
			if not table.open(f, member_paths):
				table.close()
				f.close()
				continue

			# The score, once, so "is it drawn" is answered over every frame.
			var placed: Dictionary = {}
			var vwsc: Array = f.ids_of("VWSC")
			if not vwsc.is_empty():
				var config = Config.new()
				var version := int(config.version) if config.read(f) else 0
				var score := Score.new()
				if score.parse(f.read_chunk(int(vwsc[0])), version):
					for i in score.frame_count:
						for sprite_value in score.frame(i).get("sprites", []):
							var sprite: Dictionary = sprite_value
							var key := "%d:%d" % [
								int(sprite["cast_lib"]), int(sprite["cast_id"])]
							placed[key] = int(placed.get(key, 0)) + 1

			for lib in table.cast_libs.keys():
				var cast = table.cast_for(int(lib))
				if cast == null:
					continue
				var cast_key := "%s#%d" % [
					str(table.cast_libs[lib].get("resolved_path", "")),
					int(cast.cas_chunk_id),
				]
				var fresh_cast := not seen_casts.has(cast_key)
				seen_casts[cast_key] = true
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if m.is_empty() or int(m.get("type", 0)) != XTRA:
						continue
					if str(m.get("xtra_symbol", "")).to_lower() != "text":
						continue
					# A shared cast reached through a second movie is the same
					# member; only its score placement is per-movie, and the
					# report below is keyed on the movie that placed it.
					var key := "%d:%d" % [int(lib), number]
					var placements := int(placed.get(key, 0))
					if placements > 0:
						scored += 1
					if not fresh_cast and placements == 0:
						continue
					found += 1

					var name := str(m.get("name", ""))
					var rect: Dictionary = m.get("xtra_rect", {})
					var info_rect := "none (0x0)"
					if not rect.is_empty():
						info_rect = "%dx%d" % [
							int(rect["right"]) - int(rect["left"]),
							int(rect["bottom"]) - int(rect["top"])]

					# The payload, out of the CASt chunk the member came from,
					# because `_parse_specific` keeps only its length.
					var payload := _xtra_payload(cast, m)
					var payload_rect := "payload %d bytes: too short" % payload.size()
					if payload.size() >= XTRA_DATA_MIN:
						var ph := _be_i32(payload, RECT_H_AT)
						var pw := _be_i32(payload, RECT_W_AT)
						if pw > 0 and ph > 0 and pw <= RECT_MAX and ph <= RECT_MAX:
							payload_rect_ok += 1
							payload_rect = "payload rect %dx%d" % [pw, ph]
							# The engine's own answer against the bytes this
							# tool read for itself. A member sized 0x0 here is
							# `director_cast.gd:_apply_text_xtra_rect` not
							# running, which is the state before it existed and
							# the state `the width of member` was wrong in.
							if int(m.get("width", 0)) != pw \
									or int(m.get("height", 0)) != ph:
								sized_wrong.append(
									"%s #%d '%s': member reports %dx%d, payload says %dx%d"
									% [path.get_file(), number, name,
									int(m.get("width", 0)), int(m.get("height", 0)),
									pw, ph])
						else:
							payload_rect = "payload rect refused (%dx%d)" % [pw, ph]
					else:
						payload_too_short.append("%s #%d '%s': %d bytes" % [
							path.get_file(), number, name, payload.size()])

					var children: Dictionary = cast.owned_chunks(
						int(m.get("cast_chunk_id", -1)))
					var tags: Array = children.keys()
					tags.sort()
					var has_xmed := children.has("XMED")
					if has_xmed:
						with_xmed += 1

					# Question 1, answered from the bytes: what the `XMED`
					# decodes to, re-derived here rather than read off the
					# member. `_decode_xmed` is this tool's own copy of
					# `TextXtra::decodeXMED`, so the two can disagree -- which is
					# what makes the comparison below an assertion.
					var decoded_text := ""
					if has_xmed:
						var raw := _decode_xmed(
							cast.file.read_chunk(int(children["XMED"])))
						if raw.is_empty():
							not_decoded.append("%s #%d '%s': XMED %d, %d bytes in" % [
								path.get_file(), number, name,
								int(children["XMED"]),
								cast.file.read_chunk(int(children["XMED"])).size()])
						else:
							decoded += 1
							decoded_text = _as_text(raw)
							if str(m.get("text", "")) != decoded_text:
								text_disagrees.append(
									"%s #%d '%s': member has %d chars, XMED decodes to %d"
									% [path.get_file(), number, name,
									str(m.get("text", "")).length(),
									decoded_text.length()])
						print("%18s XMED %d decodes to %d char(s): %s" % [
							"", int(children["XMED"]), decoded_text.length(),
							_printable(decoded_text)])

					# Promotion must not move the member's type. This is the
					# mechanical half of the collision assertion below: the name
					# cache keys on `type`, so a promotion that changed it is the
					# one way `field "credit"` could start seeing the Xtra again.
					if int(m.get("type", 0)) != XTRA \
							or str(m.get("type_name", "")) != "xtra":
						type_moved.append("%s #%d '%s': type %d '%s'" % [
							path.get_file(), number, name,
							int(m.get("type", 0)), str(m.get("type_name", ""))])

					# Question 4: what else in this cast wears the name.
					var twins: Array[String] = []
					# The lowest-numbered *field* of the same name: the other
					# half of the collision, and the member `field "credit"` has
					# to keep resolving to.
					var field_twin := 0
					if name != "":
						for other in cast.member_numbers():
							if other == number:
								continue
							var om: Dictionary = cast.member(other)
							if str(om.get("name", "")).to_lower() == name.to_lower():
								twins.append("#%d %s" % [
									other, str(om.get("type_name", ""))])
								if int(om.get("type", 0)) == FIELD \
										and (field_twin == 0 or other < field_twin):
									field_twin = other
						if not twins.is_empty():
							name_shared += 1
						var untyped: int = cast.number_of(name)
						var as_field: int = cast.number_of_type(name, FIELD)
						var as_xtra: int = cast.number_of_type(name, XTRA)
						if as_field == number:
							typed_hits_xtra.append(
								"%s #%d '%s': number_of_type(...,3) answers the Xtra"
								% [path.get_file(), number, name])
						# Both directions, and only where there is a field to
						# collide with -- a name with no field twin cannot say
						# anything about which of the two the typed lookup picks.
						if field_twin > 0:
							field_twins += 1
							if as_field != field_twin:
								field_twin_lost.append(
									"%s '%s': the field is #%d, number_of_type(...,field) answers %d"
									% [path.get_file(), name, field_twin, as_field])
							if as_xtra != number:
								field_twin_lost.append(
									"%s '%s': the Xtra is #%d, number_of_type(...,xtra) answers %d"
									% [path.get_file(), name, number, as_xtra])
							print("%18s number_of_type('%s', xtra) = %d (this member), field = %d" % [
								"", name, as_xtra, field_twin])
						# Lowest number wins, untyped, which is the rule the
						# collision sits under.
						var lowest: int = number
						for other in cast.member_numbers():
							if str(cast.member(other).get("name", "")).to_lower() \
									== name.to_lower():
								lowest = mini(lowest, other)
						if untyped != lowest:
							untyped_out_of_order.append(
								"%s '%s': number_of answers %d, lowest is %d"
								% [path.get_file(), name, untyped, lowest])
						print("%-14s %-18s lib %d #%-4d %-12s  %-11s  %-22s  XMED %s  children [%s]" % [
							str(root).get_file(), path.get_file(), int(lib), number,
							"'" + name + "'", info_rect, payload_rect,
							"yes" if has_xmed else "NO ", ", ".join(tags)])
						print("%18s scored on %d sprite record(s); name shared with: %s" % [
							"", placements,
							", ".join(twins) if not twins.is_empty() else "nothing"])
						print("%18s number_of('%s') = %d, number_of_type('%s', field) = %d" % [
							"", name, untyped, name, as_field])
					else:
						print("%-14s %-18s lib %d #%-4d %-12s  %-11s  %-22s  XMED %s" % [
							str(root).get_file(), path.get_file(), int(lib), number,
							"(unnamed)", info_rect, payload_rect,
							"yes" if has_xmed else "NO "])

					# What the movie's own scripts say about it. Every member in
					# reach carries its source in info item 0, so this is the
					# movie's Lingo and not a decompile.
					if name != "":
						var uses := _script_uses(table, name)
						if uses.is_empty():
							print("%18s no script in this movie's casts names it" % "")
						else:
							for line in uses.slice(0, 6 if not verbose else 40):
								print("%18s %s" % ["", line])
							if uses.size() > 6 and not verbose:
								print("%18s ... and %d more (--verbose)" % [
									"", uses.size() - 6])
			table.close()
			f.close()

	print("")
	print("%d `text` Xtra member(s) over %d root(s)" % [found, roots.size()])
	print("  with an XMED child (the only place the reference reads text from): %d" % with_xmed)
	print("  whose payload carries a rect the reference would accept: %d" % payload_rect_ok)
	print("  placed on at least one sprite record: %d" % scored)
	print("  sharing a name with another member of the same cast: %d" % name_shared)
	print("  sharing a name with a *field* in the same cast: %d" % field_twins)
	print("  whose XMED decodes to text: %d" % decoded)

	h.begin("the `text` Xtras are found and read")
	h.check("found some", found > 0, "%d" % found)
	h.check(
		"every payload is long enough for the rect the reference reads out of it",
		payload_too_short.is_empty(),
		"%d too short" % payload_too_short.size(),
	)
	for line in payload_too_short.slice(0, 6):
		print("    " + line)
	# The engine's answer, not this tool's re-derivation of it. The two are
	# independent readings of the same bytes -- `_xtra_payload` re-splits the
	# `CASt` record here rather than asking the parsed member -- so they can
	# disagree, which is what makes this an assertion rather than a tautology.
	h.check(
		"the member reports the size its payload states",
		sized_wrong.is_empty(),
		"%d do not" % sized_wrong.size(),
	)
	for line in sized_wrong.slice(0, 6):
		print("    " + line)
	# `TextXtraCastMember::load()` reads the `XMED` and warns when it cannot
	# decode one, so a member with a chunk and no text is the reference's own
	# failure case and is reported here as this port's.
	h.check(
		"every XMED chunk decodes to a run of text",
		not_decoded.is_empty(),
		"%d do not" % not_decoded.size(),
	)
	for line in not_decoded.slice(0, 6):
		print("    " + line)
	# Two readings again: `_decode_xmed` below is this file's own implementation
	# of the reference's algorithm and never consults the member, so agreement is
	# evidence that `the text of member` is answering the chunk rather than a
	# leftover.
	h.check(
		"the member's text is what the XMED decodes to",
		text_disagrees.is_empty(),
		"%d disagree" % text_disagrees.size(),
	)
	for line in text_disagrees.slice(0, 6):
		print("    " + line)
	h.complete("the `text` Xtras are found and read")

	# The invariant `02844f93` bought and the one promotion must not spend.
	h.begin("promoting one cannot re-open the slot-machine collision")
	h.check(
		"no typed field lookup answers an Xtra member",
		typed_hits_xtra.is_empty(),
		"%d do" % typed_hits_xtra.size(),
	)
	for line in typed_hits_xtra.slice(0, 6):
		print("    " + line)
	h.check(
		"the untyped lookup answers the lowest-numbered member of the name",
		untyped_out_of_order.is_empty(),
		"%d do not" % untyped_out_of_order.size(),
	)
	for line in untyped_out_of_order.slice(0, 6):
		print("    " + line)
	# The other direction. Without this the check above is satisfied by a typed
	# lookup that answers nothing at all, which is the state `02844f93` fixed and
	# not a state anybody would notice from a green run.
	h.check(
		"where a field wears the same name, each typed lookup answers its own member",
		field_twin_lost.is_empty(),
		"%d do not" % field_twin_lost.size(),
	)
	for line in field_twin_lost.slice(0, 6):
		print("    " + line)
	# And the reason both of the above hold: the record the name cache is built
	# from still says 15.
	h.check(
		"promotion leaves the member's type where it was",
		type_moved.is_empty(),
		"%d moved" % type_moved.size(),
	)
	for line in type_moved.slice(0, 6):
		print("    " + line)
	h.complete("promoting one cannot re-open the slot-machine collision")
	quit(h.finish("the eleven `text` Xtra members, bugs.md 82"))


## The text inside an `XMED` chunk: this file's own reading of
## `TextXtra::decodeXMED` (`lingo/xtras-cast/textxtra.cpp`, ScummVM 805f259a).
##
## Deliberately a second implementation rather than a call to
## `director_cast.gd:decode_xmed`. The assertion this feeds is "the member's text
## is what the chunk says", and a harness that asked the engine to decode the
## chunk and then compared the answer to the engine's own member would be
## comparing a value to itself -- the shape `AGENTS.md` names as a check whose
## two readings cannot disagree.
##
## `FFFF` header; then the first `0x00 <up to six ASCII hex digits> , <that many
## bytes>` run whose content is at least four-fifths printable, where printable is
## ASCII 0x20..0x7e, anything >= 0x80, and CR/LF/TAB.
func _decode_xmed(data: PackedByteArray) -> PackedByteArray:
	var size := data.size()
	if size < 4 or data[0] != 0x46 or data[1] != 0x46 \
			or data[2] != 0x46 or data[3] != 0x46:
		return PackedByteArray()
	for i in size:
		if i + 2 >= size:
			break
		if data[i] != 0x00:
			continue
		var j := i + 1
		var length := 0
		var digits := 0
		while j < size and _is_hex(data[j]) and digits < 6:
			length = length * 16 + _hex_of(data[j])
			j += 1
			digits += 1
		if digits == 0 or length == 0 or j >= size or data[j] != 0x2C:
			continue
		j += 1
		if j + length > size:
			continue
		var printable := 0
		for k in length:
			var c := data[j + k]
			if (c >= 0x20 and c <= 0x7E) or c >= 0x80 \
					or c == 0x0D or c == 0x0A or c == 0x09:
				printable += 1
		if printable * 5 < length * 4:
			continue
		return data.slice(j, j + length)
	return PackedByteArray()


static func _is_hex(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x46) \
		or (c >= 0x61 and c <= 0x66)


static func _hex_of(c: int) -> int:
	if c <= 0x39:
		return c - 0x30
	if c <= 0x46:
		return c - 0x41 + 10
	return c - 0x61 + 10


## The decoded run as the engine would present it: the title's codepage, and the
## `\r` line separator these 1997 files use folded to `\n`. The same two steps
## `director_cast.gd:_text` takes, spelled out here rather than borrowed, for the
## same independence reason as `_decode_xmed`.
func _as_text(raw: PackedByteArray) -> String:
	return Codepage.decode(raw).replace("\r\n", "\n").replace("\r", "\n")


## One line of it, for the report. Hebrew survives; the control codes that make a
## terminal useless do not.
func _printable(text: String) -> String:
	var one_line := text.replace("\n", "\\n").replace("\t", "\\t")
	if one_line.length() <= 96:
		return "'%s'" % one_line
	return "'%s' ... (+%d)" % [one_line.substr(0, 96), one_line.length() - 96]


## The Xtra's own payload bytes, re-read from the member's `CASt` chunk.
##
## `_parse_specific`'s type-15 arm keeps only `xtra_data_size`, deliberately --
## the payload is the Xtra's private serialisation and the engine cannot
## interpret one it has not implemented. A survey deciding whether it *should*
## needs the bytes, so it re-reads the record and re-splits it the same way:
## a big-endian uint32 symbol length at 0, the symbol, a second length, the rest.
func _xtra_payload(cast, m: Dictionary) -> PackedByteArray:
	var chunk_id := int(m.get("cast_chunk_id", -1))
	if chunk_id < 0 or cast.file == null:
		return PackedByteArray()
	var data: PackedByteArray = cast.file.read_chunk(chunk_id)
	if data.size() < 12:
		return PackedByteArray()
	var info_len := _be_u32(data, 4)
	var specific_len := _be_u32(data, 8)
	var at := 12 + info_len
	if at + specific_len > data.size():
		return PackedByteArray()
	var spec := data.slice(at, at + specific_len)
	if spec.size() < 8:
		return PackedByteArray()
	var symbol_len := _be_u32(spec, 0)
	if 4 + symbol_len + 4 > spec.size():
		return PackedByteArray()
	var data_len := _be_u32(spec, 4 + symbol_len)
	var start := 8 + symbol_len
	return spec.slice(start, mini(start + data_len, spec.size()))


## Every line of Lingo in reach of this movie that names the member.
##
## The source is the member's own info item 0, which these containers keep, so
## this is the shipped script text rather than a decompile -- and it covers movie
## scripts, cast scripts and behaviours alike, because in Director all three are
## members.
func _script_uses(table, name: String) -> Array[String]:
	var out: Array[String] = []
	var needle := name.to_lower()
	for lib in table.cast_libs.keys():
		var cast = table.cast_for(int(lib))
		if cast == null:
			continue
		for number in cast.member_numbers():
			var m: Dictionary = cast.member(number)
			var source := str(m.get("source", ""))
			if source == "" or not source.to_lower().contains(needle):
				continue
			for raw in source.split("\n"):
				var line := str(raw).strip_edges()
				if line.to_lower().contains(needle):
					out.append("uses: %s #%d: %s" % [
						str(table.cast_libs[lib].get("name", "")), number, line])
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	var subs := dir.get_directories()
	subs.sort()
	for sub in subs:
		_walk(dir_path.path_join(sub), out)


static func _be_u32(d: PackedByteArray, o: int) -> int:
	if o + 4 > d.size():
		return 0
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _be_i32(d: PackedByteArray, o: int) -> int:
	var raw := _be_u32(d, o)
	return raw - 0x100000000 if raw >= 0x80000000 else raw
