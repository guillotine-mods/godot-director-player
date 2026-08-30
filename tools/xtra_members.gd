extends SceneTree
## Xtra cast members: what they name, how big they are, and whether the two
## numbers the container stores about their size agree.
##
##   godot --headless --script tools/xtra_members.gd
##   godot --headless --script tools/xtra_members.gd -- --roots res://test-games/itamar-magichat --list
##
## An Xtra member's visual is produced by a native DLL, so this port cannot draw
## an arbitrary one and never will -- and the reference does not either: an
## `XtraCastMember` whose symbol is not in `xtraCastMemberProtos` is left as a
## plain `XtraCastMember`, which inherits `CastMember::createWidget` returning
## `nullptr` (`castmember/xtra.cpp:promote`, `castmember/castmember.h:70`, ScummVM
## 805f259a). **Drawing nothing for an unregistered Xtra is correct behaviour,
## not a missing feature.** What is *not* correct is not knowing what the member
## is, and that is what this measures.
##
## **One symbol turned out not to be an arbitrary Xtra**, and knowing what the
## member was is what showed it: `vectorShape` is Director 7's own vector art,
## built into the authoring tool rather than supplied by a DLL, and this engine
## now draws all 94 of them (`director/director_vector_shape.gd`,
## `tools/vector_shape.gd`). The rule above is unchanged for `flash`, `animGif`,
## `text` and `VisibleLightOnStageMedia`. Worth noticing that this tool's own
## census is what made the difference: the symbol had been sitting in its output
## for weeks, filed under a rule that did not apply to it.
##
## Three things are asserted, and all three are self-checks against the container
## rather than against a number written here:
##
## 1. **The envelope reads exactly.** `4 + len(symbol) + 4 + len(payload)` must be
##    the specific block's own length. Any other split of those bytes leaves a
##    remainder, so a run where every member closes to its own declared size is a
##    layout that cannot be off by a byte.
##
## 2. **The `xtraRect` is the member's size.** It is stored in the *info* block,
##    at item 12, which is a strange place for geometry and is the reason it needs
##    an outside witness. The witness is the score: a sprite record carries its
##    own width and height, written by a different part of the authoring tool, and
##    for an unstretched sprite Director resets that pair to the member's own rect
##    (`sprite.cpp:Sprite::setCast`). So the two agreeing across the corpus is
##    evidence about the *rect*, not arithmetic -- nothing in this port derives
##    one from the other.
##
## 3. **The rect's origin is a registration point**, so it lies on or inside the
##    member's own box. The centre/corner split printed above that check is the
##    descriptive half and is deliberately not asserted -- it is not uniform, and
##    an assertion that it were would have been written from the first corpus
##    looked at and falsified by the second.
##
## **A whole-corpus run is expensive** -- it opens a cast table on every one of
## the 677 containers under `games/` and `test-games/` and walks every score --
## and only two roots place Xtra sprites at all, so `--roots` is the usual way to
## run it. `itamar-magichat` and `piposh-dream` are the two that carry the
## evidence, and they are independent of each other: different titles, and
## `flash`/`animGif`/`VisibleLightOnStageMedia` against `vectorShape`/`text`.
##
## Title-agnostic: it names no game and discovers its roots by listing them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]
const XTRA := 15

## A sprite rect within this many pixels of the member's rect on both axes is the
## member's rect. Same slack, and the same reason, as
## `tools/drawn_size_stability.gd:NATURAL_SLACK`.
const SLACK := 1


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	if explicit != "":
		for part in explicit.split(",", false):
			roots.append(str(part).strip_edges())
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	roots.sort()

	# --- every Xtra member every cast in reach can address --------------------
	var members := 0
	var with_symbol := 0
	var external := 0
	var with_rect := 0
	var envelope_closes := 0
	var by_symbol: Dictionary = {}
	var by_display: Dictionary = {}
	var origins: Dictionary = {}
	var odd_origins: Array[String] = []
	var outside_origins: Array[String] = []
	var listed: Array[String] = []
	var bad: Array[String] = []

	# Every distinct cast library, addressed the way the engine addresses one.
	#
	# `Cast.open(container)` alone is not enough and the gap is large: it takes the
	# *first* `CAS*` in the file, and `itamar-magichat`'s `witch.dir` carries a
	# second library beside its own. Counted against the raw `CASt` chunks by
	# `tools/member_type_census.gd`, a first-`CAS*` walk of that corpus reaches
	# **42 of its 454 Xtra members**. `DirectorCastTable` is what the player uses
	# and it resolves all three shapes -- the internal cast, a library embedded in
	# the same container under its own `castID`, and a linked `.cst` -- so the
	# survey and the engine see the same members.
	#
	# Keyed by (resolved path, `CAS*` chunk id) so a shared cast that ninety movies
	# link is walked once. Counting it per movie would multiply this game's whole
	# cast by the number of rooms.
	var seen_casts: Dictionary = {}

	# --- the outside witness: what the score says those sprites are ----------
	# Counted in the same pass, because both halves need the same container open
	# with the same cast table on it and opening each of the 677 containers twice
	# doubles the only expensive thing here.
	var records := 0
	var agree := 0
	var differ := 0
	var stretched := 0
	var worst: Array[String] = []

	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		# One `Paths` per root, not per movie. It builds its container index on
		# first use by walking the whole tree, so a fresh one inside the loop turns
		# the sweep into an O(movies x files) directory scan -- measured as a run
		# that had not finished a corpus in ten minutes when this was per-movie.
		var member_paths := Paths.new()
		member_paths.root = root
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var member_table := CastTable.new()
			if not member_table.open(f, member_paths):
				member_table.close()
				f.close()
				continue
			for lib in member_table.cast_libs.keys():
				var cast = member_table.cast_for(int(lib))
				if cast == null:
					continue
				var cast_key := "%s#%d" % [
					str(member_table.cast_libs[lib].get("resolved_path", "")),
					int(cast.cas_chunk_id),
				]
				if seen_casts.has(cast_key):
					continue
				seen_casts[cast_key] = true
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if m.is_empty() or int(m.get("type", 0)) != XTRA:
						continue
					members += 1
					if bool(m.get("xtra_external", false)):
						external += 1
					var symbol := str(m.get("xtra_symbol", ""))
					if symbol != "":
						with_symbol += 1
						by_symbol[symbol] = int(by_symbol.get(symbol, 0)) + 1
					var display := str(m.get("xtra_display_name", ""))
					if display != "":
						by_display[display] = int(by_display.get(display, 0)) + 1
					var rect: Dictionary = m.get("xtra_rect", {})
					if not rect.is_empty():
						with_rect += 1
						var left := int(rect["left"])
						var top := int(rect["top"])
						var w := int(rect["right"]) - left
						var hgt := int(rect["bottom"]) - top
						# Where the rect's origin sits inside it. Half a pixel of
						# slack on the centre because an odd dimension cannot be
						# halved exactly and the authoring tool rounds one way.
						if left == 0 and top == 0:
							origins["top-left (0,0)"] = int(
								origins.get("top-left (0,0)", 0)) + 1
						elif absi(-left * 2 - w) <= 1 and absi(-top * 2 - hgt) <= 1:
							origins["centre"] = int(origins.get("centre", 0)) + 1
						else:
							origins["somewhere else"] = int(
								origins.get("somewhere else", 0)) + 1
							odd_origins.append("%s #%d '%s': %dx%d at origin (%d,%d)" % [
								path.get_file(), number, str(m.get("name", "")),
								w, hgt, left, top])
						# The invariant that says it is a registration *point* at
						# all: a point in the member, so it lies on or inside the
						# member's own box. An arbitrary rect would not.
						if left > 0 or top > 0 or -left > w or -top > hgt:
							outside_origins.append(
								"%s #%d '%s': %dx%d at origin (%d,%d)" % [
								path.get_file(), number, str(m.get("name", "")),
								w, hgt, left, top])
					if int(m.get("xtra_envelope_len", -1)) == int(m.get("xtra_specific_len", -2)):
						envelope_closes += 1
					elif not bool(m.get("xtra_external", false)):
						bad.append("%s #%d '%s': envelope %d of %d bytes" % [
							path.get_file(), number, str(m.get("name", "")),
							int(m.get("xtra_envelope_len", -1)),
							int(m.get("xtra_specific_len", -1)),
						])
					if Args.flag(args, "list"):
						listed.append("%-16s %-20s #%-4d %-16s %4dx%-4d @(%d,%d)  %-10s %s" % [
							str(root).get_file(), path.get_file(), number,
							str(m.get("name", "")), int(m.get("width", 0)),
							int(m.get("height", 0)),
							int(rect.get("left", 0)), int(rect.get("top", 0)),
							symbol, display,
						])
			var vwsc: Array = f.ids_of("VWSC")
			if not vwsc.is_empty():
				var config = Config.new()
				var version := int(config.version) if config.read(f) else 0
				var score := Score.new()
				if score.parse(f.read_chunk(int(vwsc[0])), version):
					for i in score.frame_count:
						for sprite_value in score.frame(i).get("sprites", []):
							var sprite: Dictionary = sprite_value
							var m: Dictionary = member_table.get_member(
								int(sprite["cast_lib"]), int(sprite["cast_id"]))
							if m.is_empty() or int(m.get("type", 0)) != XTRA:
								continue
							var mw := int(m.get("width", 0))
							var mh := int(m.get("height", 0))
							if mw <= 0 or mh <= 0:
								continue
							records += 1
							if bool(sprite.get("stretch", false)):
								stretched += 1
								continue
							var sw := int(sprite["width"])
							var sh := int(sprite["height"])
							if absi(sw - mw) <= SLACK and absi(sh - mh) <= SLACK:
								agree += 1
							else:
								differ += 1
								if worst.size() < 12:
									worst.append(
										"%s ch%d #%d '%s': member %dx%d, score %dx%d" % [
										path.get_file(), int(sprite["channel"]),
										int(sprite["cast_id"]), str(m.get("name", "")),
										mw, mh, sw, sh])
			member_table.close()
			f.close()

	# ------------------------------------------------------------------ report
	print("%d Xtra cast member(s) over %d corpus root(s)" % [members, roots.size()])
	print("  with a symbol       : %d" % with_symbol)
	print("  external (no envelope): %d" % external)
	print("  envelope closes exactly: %d" % envelope_closes)
	print("")
	print("by Xtra symbol:")
	var syms: Array = by_symbol.keys()
	syms.sort()
	for s in syms:
		print("  %-24s %d" % [s, int(by_symbol[s])])
	print("")
	print("by display name:")
	var disp: Array = by_display.keys()
	disp.sort()
	for s in disp:
		print("  %-24s %d" % [s, int(by_display[s])])
	print("")
	print("where the rect's origin sits inside the rect. The split is descriptive;")
	print("what is asserted below is only that the origin is a point in the member,")
	print("which is what reading it as a registration point requires.")
	var orig: Array = origins.keys()
	orig.sort()
	for s in orig:
		print("  %-16s %d" % [s, int(origins[s])])
	for line in odd_origins.slice(0, 12):
		print("      %s" % line)
	if not outside_origins.is_empty():
		print("  origins outside their own box (these break the reading):")
		for line in outside_origins.slice(0, 12):
			print("      %s" % line)
	print("")
	print("sprite records naming an Xtra member with a decoded size: %d" % records)
	print("  stretch set (exempt): %d" % stretched)
	print("  score rect agrees with the member's xtraRect (+/-%d px): %d" % [SLACK, agree])
	print("  differs                                               : %d" % differ)
	for line in worst:
		print("      %s" % line)
	if not listed.is_empty():
		print("")
		for line in listed:
			print("  " + line)
	if not bad.is_empty():
		print("")
		print("envelopes that do not close:")
		for line in bad:
			print("  " + line)

	h.begin("every Xtra member says what it is")
	h.check("found Xtra members", members > 0, "%d" % members)
	h.check(
		"every non-external Xtra names its Xtra",
		with_symbol + external == members,
		"%d named, %d external, %d total" % [with_symbol, external, members],
	)
	h.check(
		"every envelope closes to its own declared length",
		bad.is_empty(),
		"%d do not" % bad.size(),
	)
	# **Carrying a rect is not an invariant and asserting it was wrong.** Measured:
	# 400 of `itamar-magichat`'s 454 have one, 94 of `piposh-dream`'s 97, and
	# **0 of `piposh2`'s 4** -- that title's Xtra members are all `text` Xtras and
	# none records a rect. A member without one keeps a width of zero and falls
	# back to the score's own rect, which is what any member with no natural size
	# has always done. So this is a number, not a claim.
	print("")
	print("xtraRect present on %d of %d member(s)" % [with_rect, members])
	# The claim `director_cast.gd:_apply_xtra_rect` rests on: the origin is a
	# registration *point*, so it is a point in the member. The centre/corner split
	# printed above is the descriptive evidence; this is the falsifiable part. A
	# rect whose origin fell outside its own box would not be a registration point
	# and that function would be reading it as one.
	h.check(
		"every rect's origin lies on or inside its own box",
		outside_origins.is_empty(),
		"%d of %d rect(s) do not" % [outside_origins.size(), with_rect],
	)
	h.complete("every Xtra member says what it is")

	h.begin("the xtraRect is the size the score records for the sprite")
	# **Only two roots in reach place Xtra sprites at all**, so this case is
	# conditional on the corpus rather than universal -- and it says so out loud
	# instead of passing quietly, which is the dark-harness failure `gate.sh`
	# warns about. `piposh2`, `piposh`, `piposh-en`, `piposh-ru`, `rating` and
	# `itamar-park` between them hold 15 Xtra members and score not one of them.
	if records == 0:
		h.check(
			"this corpus places no Xtra sprite, so the size witness is not exercised",
			true,
			"run --roots res://test-games/itamar-magichat,res://games/piposh-dream",
		)
	else:
		# Not "all", because an author may legitimately have resized a channel and
		# left the residue behind exactly as they do for a bitmap -- the claim is
		# that the rect is the size, not that no record ever disagrees.
		h.check(
			"the two agree on the overwhelming majority of records",
			agree > 0 and float(agree) / maxf(agree + differ, 1) > 0.9,
			"%d agree, %d differ, of %d record(s)" % [agree, differ, records],
		)
	h.complete("the xtraRect is the size the score records for the sprite")
	quit(h.finish("Xtra cast members across every corpus in reach"))


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
