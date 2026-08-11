extends SceneTree
## The palette machinery: tables, `CLUT` reading, cycling, fades, and §11's
## resolution order.
##
##   godot --headless --script tools/palette_cycle.gd
##   godot --headless --script tools/palette_cycle.gd -- --file strtgame.dir
##
## **Why this is mostly synthetic, said plainly.** `tools/palette_survey.gd`
## measures that this corpus switches colour cycling on **0** times in 61,371
## frames and names no palette but system Mac, so there is no real data to assert
## cycling against. That is a reason to write the cases by hand, not a reason to
## leave the feature out: the engine has to run Piposh 1 and *Rating* too, and a
## synthetic case labelled as synthetic is an honest test where a missing feature
## is a hole nobody remembers choosing.
##
## So the assertions below are of two kinds and are kept apart:
##
##   synthetic   a hand-built palette record or table, exercising a rule taken
##               from the reference. Proves the code does what §11 describes.
##   corpus      the one frame in the game that carries a palette effect,
##               `strtgame` f38. Proves the decode and the arming agree with real
##               authored data.
##
## What none of it proves is that Director's own fade looks like this on screen,
## because nothing here has been run against the original. §18 records that.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const PaletteState := preload("res://director/director_palette_state.gd")


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()

	_tables(h)
	_clut(h)
	_cycling(h)
	_fading(h)
	_resolution(h)
	_corpus(h, Args.text(args, "file", "strtgame.dir"))
	await _preview(h, Args.text(args, "file", "strtgame.dir"))

	quit(h.finish("the palette tables, transforms and resolution order"))


# --------------------------------------------------------- wired into the paint
## That the renderer actually uses the state machine.
##
## Everything above proves the machine; none of it proves it is connected, and
## that is the exact shape of the bug `tools/stage_clip.gd` found in the stage
## clip — every check passing over a mechanism that reached no pixels. The
## observable here is that **the same cast member decodes to different colours**
## once the palette changes, which cannot happen unless the table reached the
## bitmap decoder and the artwork baked against the old one was thrown away.
##
## **Which palette change, though.** This used to drive the observable with
## `puppetPalette grayscale` and assert the artwork came back grey, and that
## assertion is no longer one the engine makes: `palette_view.gd:table_for_member`
## decodes a bitmap through the palette its *own member* names, because on a
## 16-bit-or-deeper stage — `movieDepth` 32, which every movie in reach declares —
## Director converts each bitmap through the member's CLUT rather than blitting
## indices into one screen CLUT. Over `itamar-park` the stage holds the palette a
## bitmap names for 22 of 5,692 (frame, sprite) pairs, so the other reading makes
## 99.6% of that title's artwork the wrong colour. That rule is right and
## `tools/palette_members.gd` guards it.
##
## What it costs is this case's driver, because a puppet changes the *id*: the
## member still names system Mac, the stage is now on grayscale, the two no
## longer match and the member keeps its own table. So the drive here is a **fade
## under an unchanged id**, which is the one thing that must still reach the
## artwork and is what `strtgame` f38 actually does — §11's fades and cycles
## mutate the current table in place, so a member naming the palette the stage is
## already on sees the mutation. Every bitmap in this corpus names system Mac and
## the stage is on system Mac from the first frame to the last, so the coupling is
## exercised here by the same mechanism the game ships.
##
## **What this no longer covers, and is a real gap rather than a rewrite.** The
## reference has one exception to the member-palette rule and this port does not
## implement it: `castmember/bitmap.cpp:BitmapCastMember::getDitherImg`, case 8,
## takes the *score's* palette as the source whenever `targetBpp != 1 &&
## score->_puppetPalette && !_external` — "we're in true colour mode, rendering a
## paletted image, and the puppet palette has been set". `table_for_member` never
## sees whether a puppet is set (`director_palette_state.gd:puppet_id`), so on
## this engine `puppetPalette` currently recolours nothing on screen. The two
## checks below that are about the puppet assert the *state* half — the table is
## installed and the caches are dropped — which is all of it that works.
func _preview(h: Harness, movie: String) -> void:
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	preview.set("_paused", true)
	var score = preview.get("_score")
	if score == null:
		print("no preview score for %s" % movie)
		return

	# A bitmap sprite whose artwork can be decoded twice and compared.
	var probe: Dictionary = {}
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var m: Dictionary = preview.get("_table").get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"])
			)
			if m.is_empty() or int(m.get("type", 0)) != 1:
				continue
			if preview.call("_texture_for", sprite) != null:
				probe = sprite
				break
		if not probe.is_empty():
			break
	if probe.is_empty():
		print("no bitmap sprite in %s to decode" % movie)
		return

	h.begin("%s: the palette reaches the artwork" % movie)
	var member: Dictionary = preview.get("_table").get_member(
		int(probe["cast_lib"]), int(probe["cast_id"])
	)
	var key: String = preview.call(
		"_texture_key", probe, preview.call("_drawn_size", probe, member)
	)
	var state = preview.get("_palette_state")
	h.check("the movie opens on system Mac",
		preview.get("_palette") == Palette.system_mac())
	h.check("and something is decoded against it",
		not preview.get("_textures").is_empty(),
		"%d cached texture(s)" % preview.get("_textures").size())
	# The precondition the fade below rests on, asserted rather than assumed: a
	# member naming some *other* palette would keep its own table through a stage
	# fade, and the case would be measuring nothing while looking identical.
	h.check("the probe names the palette the stage is on",
		int(member.get("palette_id", Palette.SYSTEM_MAC)) == int(state.current_id),
		"member %d, stage %d" % [
			int(member.get("palette_id", Palette.SYSTEM_MAC)), int(state.current_id)])

	# The puppet, through the Lingo builtin, which is the route a movie has. Only
	# the state half: see the note above about `getDitherImg`'s puppet exception.
	preview.call("lingo_puppet_palette", Palette.GRAYSCALE)
	h.check("puppetPalette installs the table it names",
		preview.get("_palette") == Palette.grayscale())
	# Artwork decoded through a palette is artwork baked against it, so a switch
	# has to invalidate the cache or the new frame draws in the old colours.
	h.check("and everything baked against the old one was dropped",
		preview.get("_textures").is_empty() and preview.get("_hit_images").is_empty())
	preview.call("lingo_puppet_palette", 0)
	h.check("puppetPalette 0 hands the palette back to the score",
		preview.get("_palette") == Palette.system_mac())

	# ---- the fade, which is the half that has to reach pixels
	preview.call("_texture_for", probe)
	var before: Image = preview.get("_hit_images")[key]
	var before_pixels := before.get_data()
	# `enter_frame` then `step` then `_palette_applied` is exactly the pair the
	# frame loop runs (`scenes/preview/frame_loop.gd:139` and `:213-214`); the
	# harness drives it directly because `_paused` is set and `_process` is not.
	state.enter_frame(_record({
		"fade_to_black": true, "fade": true, "speed": 10, "frame_count": 4,
	}))
	h.check("a fade-to-black frame arms without moving the palette id",
		state.effect_running() and int(state.current_id) == Palette.SYSTEM_MAC,
		"id %d, %.0f ms" % [int(state.current_id), state.hold_ms()])
	# Half the fade rather than all of it, on purpose. At the end every entry is
	# black, so the sprite's own backColor resolves to black too and Background
	# Transparent would key the whole image out -- the case would then be sampling
	# zero pixels and reporting it as a pass. Halfway the table has moved by a
	# measurable amount and the keying is unchanged, which is the stronger
	# observable anyway: the *same* pixels, darker.
	var moved: bool = state.step(state.hold_ms() * 0.5)
	if moved:
		preview.call("_palette_applied")
	h.check("stepping it moves the table and drops the baked artwork",
		moved and preview.get("_textures").is_empty()
		and preview.get("_hit_images").is_empty())

	preview.call("_texture_for", probe)
	var after: Image = preview.get("_hit_images")[key]
	h.check("the same member now decodes to different pixels",
		after.get_data() != before_pixels,
		"half-faded against system Mac, %d bytes each" % after.get_data().size())
	# The direction, not just the difference: a fade towards black can only make
	# every surviving pixel darker, and this is the check that would catch the
	# table being installed but not consulted.
	var sampled := 0
	var darker := 0
	var strictly := 0
	var keyed := 0
	for y in range(0, after.get_height(), 4):
		for x in range(0, after.get_width(), 4):
			var was := before.get_pixel(x, y)
			var now := after.get_pixel(x, y)
			if (was.a > 0.5) != (now.a > 0.5):
				keyed += 1
			if was.a <= 0.5 or now.a <= 0.5:
				continue
			sampled += 1
			if now.r8 <= was.r8 and now.g8 <= was.g8 and now.b8 <= was.b8:
				darker += 1
			if now.r8 < was.r8 or now.g8 < was.g8 or now.b8 < was.b8:
				strictly += 1
	h.check("and every one of them is darker, because the palette is",
		sampled > 0 and darker == sampled and strictly > 0,
		"%d of %d sampled pixels darker, %d strictly" % [darker, sampled, strictly])
	# The keying is decided from the *palette-resolved* paper colour, so a fade
	# that moved the artwork and the paper by the same amount must key the same
	# pixels. A run where this moves is a run where the matte followed the fade.
	h.check("and the same pixels are keyed out as before", keyed == 0,
		"%d pixel(s) changed transparency" % keyed)

	# Put it back, so nothing after this case inherits a half-faded stage.
	state.abort()
	preview.call("_palette_applied")
	h.check("aborting the fade puts the artwork back",
		preview.get("_palette") == Palette.system_mac())
	h.complete("%s: the palette reaches the artwork" % movie)


# ------------------------------------------------------------------ the tables
func _tables(h: Harness) -> void:
	h.begin("the built-in tables")
	var mac := Palette.system_mac()
	h.check("system Mac is 768 bytes", mac.size() == Palette.TABLE_BYTES, "%d" % mac.size())
	# The two indices both ink passes depend on. Looked up, never assumed — the
	# cube's shape puts black at 215 if you trust it, which painted every
	# repaired cursor red.
	h.check("index 0 is exactly white", Palette.index_of_white(mac) == Palette.PAPER_INDEX,
		"white at %d" % Palette.index_of_white(mac))
	h.check("index 255 is exactly black", Palette.index_of_black(mac) == Palette.INK_INDEX,
		"black at %d" % Palette.index_of_black(mac))
	h.check("exactly one index is full white",
		Palette.indices_at_least(mac, 255).size() == 1,
		"%d" % Palette.indices_at_least(mac, 255).size())

	var grey := Palette.grayscale()
	h.check("grayscale is 768 bytes", grey.size() == Palette.TABLE_BYTES, "%d" % grey.size())
	h.check("grayscale runs white to black, and is grey throughout",
		grey[0] == 255 and grey[1] == 255 and grey[2] == 255
		and grey[255 * 3] == 0 and grey[255 * 3 + 1] == 0 and grey[255 * 3 + 2] == 0
		and _all_grey(grey))
	# Both conventions agree: entry 0 is the light end. A palette that disagreed
	# with system Mac here would key artwork against the wrong end of the ramp.
	h.check("grayscale agrees with system Mac about which end is white",
		Palette.index_of_white(grey) == Palette.index_of_white(mac))

	h.check("can_build answers for what builtin() can actually produce",
		Palette.can_build(Palette.SYSTEM_MAC) and Palette.can_build(Palette.GRAYSCALE)
		and Palette.can_build(0))
	# **This check used to assert the opposite**, and its own message said "add
	# them to PALETTE_DATA to close this". They have been added, so the invariant
	# it was holding open is now the one worth holding: each data-only id
	# resolves, is a full table, and is *not* system Mac. That last clause is the
	# one that matters -- `builtin()` substitutes system Mac for anything it
	# cannot produce, so an id that resolved to system Mac would pass a size test
	# while still being the substitution this file exists to detect.
	var data_only := [
		Palette.RAINBOW, Palette.PASTELS, Palette.VIVID, Palette.NTSC,
		Palette.METALLIC, Palette.SYSTEM_WIN, Palette.SYSTEM_WIN_D5,
	]
	var missing: Array = []
	var substituted: Array = []
	for id in data_only:
		if not Palette.can_build(id):
			missing.append(id)
			continue
		var table := Palette.builtin(id)
		if table.size() != Palette.TABLE_BYTES or table == mac:
			substituted.append(id)
	h.check("every data-supplied built-in resolves to its own table",
		missing.is_empty() and substituted.is_empty(),
		"missing %s, substituted %s" % [str(missing), str(substituted)])
	# The substitution path itself still has to be asserted, or it becomes silent
	# the day a table is dropped. VGA is the id no source in reach carries, so it
	# is the one that keeps this honest.
	h.check("an id with no table still reports itself unbuildable",
		not Palette.can_build(Palette.VGA))
	h.check("and still returns a usable table",
		Palette.builtin(Palette.VGA).size() == Palette.TABLE_BYTES)
	h.complete("the built-in tables")


func _all_grey(table: PackedByteArray) -> bool:
	for i in Palette.ENTRIES:
		if table[i * 3] != table[i * 3 + 1] or table[i * 3 + 1] != table[i * 3 + 2]:
			return false
	return true


# ------------------------------------------------------------- the CLUT reader
func _clut(h: Harness) -> void:
	h.begin("the CLUT reader")
	# Three entries as Director stores them: 16 bits per channel, high byte
	# significant, **entry 0 first**. Built by hand because `GATE_ROOT` ships no
	# CLUT chunk at all to read; `tools/palette_members.gd` reads 162 real ones.
	#
	# **These three assertions used to be written upside down**, and said so in
	# their own comment: "Reversed on purpose: the chunk's last entry is index 0.
	# Read forwards, a custom palette comes out inverted and reads as an ink bug."
	# That was the theory `from_clut` was built on and it was wrong in both
	# halves. A chunk already opens with white and ends with black, so reversing
	# it moves *black* to index 0 -- which is paper, the one index both ink passes
	# key out and the one that has to be exactly white. `torfim.dir` #601
	# `Antark_back` opens `ffffff ffffff e4e4ececf4f4` and ends in twelve zero
	# bytes; its 616x390 backdrop decodes forwards to 61,600 white pixels over a
	# pale blue sky and backwards to 84,255 black ones with an orange sea.
	# `director_palette.gd:from_clut` was corrected then and these three were not,
	# because nothing ran this file -- it was never in `gate.sh`'s `ALL`. The
	# reference agrees with the corrected reader: `Cast::loadPalette` walks a
	# colour index up from zero and takes the high byte of each 16-bit channel,
	# with no reversal anywhere.
	var payload := PackedByteArray()
	for entry in [[0, 0, 0], [0x40, 0x80, 0xc0], [255, 255, 255]]:
		for channel in entry:
			payload.append(channel)
			# The low byte, which Director writes and the reader must skip. 0x11
			# rather than 0 so a reader that took the *low* byte, or averaged the
			# two, cannot pass: no channel below may legitimately come out 0x11.
			payload.append(0x11)
	var table := Palette.from_clut(payload)
	h.check("a CLUT decodes to a full-size table",
		table.size() == Palette.TABLE_BYTES, "%d" % table.size())
	h.check("the chunk's first entry lands at index 0",
		table[0] == 0 and table[1] == 0 and table[2] == 0,
		"got %d,%d,%d" % [table[0], table[1], table[2]])
	h.check("the middle entry keeps its high bytes",
		table[3] == 0x40 and table[4] == 0x80 and table[5] == 0xc0,
		"got %d,%d,%d" % [table[3], table[4], table[5]])
	h.check("the chunk's last entry lands last of those read",
		table[6] == 255 and table[7] == 255 and table[8] == 255,
		"got %d,%d,%d" % [table[6], table[7], table[8]])
	# The low byte is dropped rather than blended: 0x11 in any channel means the
	# reader read the wrong half of a 16-bit `RGBColor`.
	var low_bytes := 0
	for i in 9:
		if table[i] == 0x11:
			low_bytes += 1
	h.check("and the low byte of every 16-bit channel is dropped", low_bytes == 0,
		"%d channel(s) came back as the low byte" % low_bytes)
	# Entries the chunk did not carry stay black rather than being invented.
	h.check("entries past the end of a short chunk are left black",
		table[9] == 0 and table[10] == 0 and table[11] == 0
		and table[255 * 3] == 0 and table[255 * 3 + 2] == 0)
	h.check("a short chunk fills what it has rather than failing",
		Palette.from_clut(PackedByteArray([1, 0, 2, 0, 3, 0])).size() == Palette.TABLE_BYTES)
	h.complete("the CLUT reader")


# ------------------------------------------------------------------ cycling
func _cycling(h: Harness) -> void:
	h.begin("colour cycling rotates a range and leaves the rest")
	var table := Palette.system_mac()
	var first := 10
	var last := 13
	var one := Palette.cycled(table, first, last, 1)
	h.check("an entry moved down by one step",
		one[first * 3] == table[(first + 1) * 3]
		and one[first * 3 + 1] == table[(first + 1) * 3 + 1])
	h.check("the range wraps inside itself",
		one[last * 3] == table[first * 3] and one[last * 3 + 2] == table[first * 3 + 2])
	h.check("everything outside the range is untouched",
		_same_outside(table, one, first, last))
	h.check("a full turn is the identity",
		Palette.cycled(table, first, last, last - first + 1) == table)
	# Auto-reverse steps backwards through the same offsets, so a negative shift
	# has to land inside the range. GDScript's `%` keeps the dividend's sign,
	# which would index before `first` without the correction in `cycled`.
	h.check("a negative offset is the inverse of the positive one",
		Palette.cycled(one, first, last, -1) == table)
	h.check("a degenerate range changes nothing",
		Palette.cycled(table, 20, 20, 3) == table
		and Palette.cycled(table, 30, 10, 3) == table)

	# Speed is a rate in fps below 30 and unbounded at 30 (§11).
	h.check("speed 30 is the 10 ms floor", PaletteState.step_ms(30) == 10.0,
		"%.1f ms" % PaletteState.step_ms(30))
	h.check("speed 10 is 100 ms a step", PaletteState.step_ms(10) == 100.0,
		"%.1f ms" % PaletteState.step_ms(10))
	h.complete("colour cycling rotates a range and leaves the rest")

	# ---- the state machine, over a synthetic record
	h.begin("a cycling frame runs to completion and keeps its offset")
	var state := PaletteState.new()
	state.reset(Palette.SYSTEM_MAC)
	var record := _record({
		"cycling": true, "speed": 10, "first": 10, "last": 13, "cycle_count": 1,
	})
	state.enter_frame(record)
	h.check("the frame is held for the cycle's whole length",
		state.hold_ms() == 400.0, "%.0f ms for 4 steps at 100 ms" % state.hold_ms())
	h.check("and the cycle is running", state.effect_running())
	var before := state.table.duplicate()
	state.step(100.0)
	h.check("one step in, the palette has moved", state.table != before)
	state.step(400.0)
	h.check("past the end, the cycle has stopped", not state.effect_running())
	# Keyed by palette id only, so a second cycle on the same palette resumes.
	var after_first := state.table.duplicate()
	state.enter_frame(record)
	state.step(100.0)
	h.check("a second cycle resumes from the offset the first left",
		state.table != after_first
		and state.table == Palette.cycled(after_first, 10, 13, 1),
		"the offset is keyed by palette id and survives re-arming")
	h.complete("a cycling frame runs to completion and keeps its offset")

	h.begin("a click aborts a cycle and puts the palette back")
	var aborting := PaletteState.new()
	aborting.reset(Palette.SYSTEM_MAC)
	var pristine := aborting.table.duplicate()
	aborting.enter_frame(_record({
		"cycling": true, "speed": 10, "first": 10, "last": 20, "cycle_count": 4,
	}))
	aborting.step(300.0)
	h.check("the cycle moved the palette", aborting.table != pristine)
	aborting.abort()
	h.check("the abort restored exactly what was there before", aborting.table == pristine)
	h.check("and nothing is running", not aborting.effect_running())
	h.complete("a click aborts a cycle and puts the palette back")

	h.begin("over time spreads a cycle across frames instead of holding one")
	var over := PaletteState.new()
	over.reset(Palette.SYSTEM_MAC)
	over.enter_frame(_record({
		"cycling": true, "speed": 10, "first": 10, "last": 13, "cycle_count": 1,
		"over_time": true,
	}))
	h.check("the playhead is not held", over.hold_ms() == 0.0, "%.0f ms" % over.hold_ms())
	h.check("but the cycle is still armed", over.effect_running())
	h.complete("over time spreads a cycle across frames instead of holding one")


func _same_outside(a: PackedByteArray, b: PackedByteArray, first: int, last: int) -> bool:
	for i in Palette.ENTRIES:
		if i >= first and i <= last:
			continue
		for c in 3:
			if a[i * 3 + c] != b[i * 3 + c]:
				return false
	return true


# -------------------------------------------------------------------- fading
func _fading(h: Harness) -> void:
	h.begin("a fade moves the whole table to one colour")
	var table := Palette.system_mac()
	var half := Palette.faded(table, Color.BLACK, 0.5)
	h.check("halfway to black is half the value", half[3] == int(round(table[3] * 0.5)),
		"%d from %d" % [half[3], table[3]])
	h.check("all the way to black is black", _all_equal(Palette.faded(table, Color.BLACK, 1.0), 0))
	h.check("all the way to white is white",
		_all_equal(Palette.faded(table, Color.WHITE, 1.0), 255))
	h.check("no fade at all is the palette itself", Palette.faded(table, Color.BLACK, 0.0) == table)
	# The fade is over the whole table, not the cycling range: a fade is a
	# transition of the screen, and fading a range would leave the rest up.
	h.check("the fade reaches entries outside any cycling range",
		Palette.faded(table, Color.BLACK, 1.0)[200 * 3] == 0)
	h.check("a cross-fade at zero and one is each end",
		Palette.blended(table, Palette.grayscale(), 0.0) == table
		and Palette.blended(table, Palette.grayscale(), 1.0) == Palette.grayscale())
	h.complete("a fade moves the whole table to one colour")

	h.begin("a fading frame reaches its target and stops")
	var state := PaletteState.new()
	state.reset(Palette.SYSTEM_MAC)
	state.enter_frame(_record({
		"fade_to_black": true, "fade": true, "speed": 10, "frame_count": 4,
	}))
	h.check("the frame is held for the fade", state.hold_ms() == 400.0, "%.0f ms" % state.hold_ms())
	state.step(200.0)
	h.check("halfway through, the palette is neither end",
		not _all_equal(state.table, 0) and state.table != Palette.system_mac())
	state.step(400.0)
	h.check("at the end it is black", _all_equal(state.table, 0))
	h.check("and the fade has stopped", not state.effect_running())
	h.complete("a fading frame reaches its target and stops")


func _all_equal(table: PackedByteArray, value: int) -> bool:
	for b in table:
		if b != value:
			return false
	return true


# -------------------------------------------------------- the resolution order
func _resolution(h: Harness) -> void:
	h.begin("the resolution order, and what re-checks existence")
	var state := PaletteState.new()
	# A host that has two palettes loaded and nothing else, which is what lets
	# the "actually loaded" half of §11 be exercised without a cast.
	var loaded := {5: Palette.grayscale(), 9: Palette.system_mac()}
	state.table_for = func(id: int) -> PackedByteArray:
		var got: PackedByteArray = loaded.get(id, PackedByteArray())
		return got
	state.reset(Palette.SYSTEM_MAC)

	h.check("a frame naming nothing keeps the movie default",
		state.resolve_id(_record({})) == Palette.SYSTEM_MAC)
	h.check("a frame naming a loaded palette gets it",
		state.resolve_id(_record({"member": 5})) == 5)
	# The cache is filled by resolving through the score, and §11 puts it ahead
	# of the movie default from then on.
	state.enter_frame(_record({"member": 5}))
	h.check("resolving through the score fills the cache", state.cached_id == 5)
	h.check("a later frame naming nothing falls back to the cache, not the default",
		state.resolve_id(_record({})) == 5)
	# Director tolerates references to palettes of deleted members, which is why
	# every step re-checks rather than trusting the id it stored.
	loaded.erase(5)
	h.check("a cached palette that has gone away falls through to the default",
		state.resolve_id(_record({})) == Palette.SYSTEM_MAC)
	h.check("a frame naming a palette that is not loaded falls through too",
		state.resolve_id(_record({"member": 77})) == Palette.SYSTEM_MAC)

	# The puppet short-circuits all of it, and 0 is "off" rather than "system Mac".
	state.set_puppet(9)
	h.check("a puppet palette wins over the frame's own",
		state.resolve_id(_record({"member": 9999})) == 9)
	state.set_puppet(0)
	h.check("puppetPalette 0 hands the palette back to the score",
		state.resolve_id(_record({"member": 9})) == 9)
	h.complete("the resolution order, and what re-checks existence")


# ------------------------------------------------------ the one real frame
func _corpus(h: Harness, movie: String) -> void:
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		return
	var path: String = paths.resolve(movie)
	if path == "":
		print("no such container: %s" % movie)
		return
	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		return
	var vwsc: Array = f.ids_of("VWSC")
	if vwsc.is_empty():
		f.close()
		return
	var score := Score.new()
	if not score.parse(f.read_chunk(int(vwsc[0]))):
		f.close()
		return

	# Every frame this movie writes an effect into the palette channel on. In
	# this game there is exactly one, in strtgame; other movies have none and the
	# case says so rather than pretending to have checked something.
	var effects: Array[Dictionary] = []
	for i in score.frame_count:
		var record: Dictionary = score.frame(i).get("palette", {})
		if int(record.get("flags", 0)) != 0:
			record = record.duplicate()
			record["frame_index"] = i
			effects.append(record)
	f.close()

	print("")
	print("%s: %d frame(s) carry a palette effect" % [path.get_file(), effects.size()])
	if effects.is_empty():
		print("  nothing to assert here; run with --file strtgame.dir for the one that does")
		return

	h.begin("%s: the corpus's own palette effect arms correctly" % path.get_file())
	for record in effects:
		print("  f%d  flags 0x%02x  speed %d  frame count %d" % [
			int(record["frame_index"]), int(record["flags"]),
			int(record["speed"]), int(record["frame_count"]),
		])
	var one: Dictionary = effects[0]
	h.check("it decodes as a fade and not as cycling",
		bool(one.get("fade", false)) and not bool(one.get("cycling", false)),
		"flags 0x%02x" % int(one["flags"]))
	h.check("to black rather than to white",
		bool(one.get("fade_to_black", false)) and not bool(one.get("fade_to_white", false)))
	var state := PaletteState.new()
	state.reset(Palette.SYSTEM_MAC)
	state.enter_frame(one)
	h.check("it arms, and holds the frame for a real length of time",
		state.effect_running() and state.hold_ms() > 0.0,
		"%.0f ms" % state.hold_ms())
	state.step(state.hold_ms() + 1.0)
	h.check("running it out leaves the stage black",
		_all_equal(state.table, 0))
	h.check("and the effect has finished", not state.effect_running())
	h.complete("%s: the corpus's own palette effect arms correctly" % path.get_file())


## A palette channel record with the fields a case cares about and defaults for
## the rest, so a case reads as the thing it is testing.
func _record(fields: Dictionary) -> Dictionary:
	var out := {
		"cast_lib": 1, "member": 0, "speed": 0, "flags": 0,
		"cycling": false, "fade": false, "fade_to_black": false, "fade_to_white": false,
		"auto_reverse": false, "over_time": false,
		"first_color_raw": 0, "last_color_raw": 0,
		"frame_count": 0, "cycle_count": 0,
	}
	for key in fields:
		out[key] = fields[key]
	# The channel stores colours offset by 0x80; a case names plain indices.
	if fields.has("first"):
		out["first_color_raw"] = int(fields["first"]) ^ 0x80
	if fields.has("last"):
		out["last_color_raw"] = int(fields["last"]) ^ 0x80
	return out
