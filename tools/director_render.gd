extends SceneTree
## Composite one frame of one movie onto the stage and write it out.
##
##   godot --headless --script tools/director_render.gd -- --file PIP2DATA/DAY1.DIR --label shore2 --out C:/tmp/shore2.png
##   godot --headless --script tools/director_render.gd -- --file PIP2DATA/DAY1.DIR --frame 37 --out C:/tmp/f37.png
##
## Everything on the stage here came out of the original containers: the score
## says which member sits in which channel and where, the cast libraries say
## which file each member lives in, and the bitmaps come from that file's own
## chunks. Nothing is read from the exported render_model.
##
## This is a diagnostic, not the renderer -- it has no scripts, no puppet state
## and no fields, so a frame that a movie's own Lingo dresses on arrival comes out
## undressed. What it no longer has is **its own idea of ink.** Keying goes through
## `director_ink.gd`, the same `key_for` / `key_matte` / `key_paper` /
## `apply_colour` the player calls, so the two agree about what a sprite's pixels
## are and disagree only about the state a running movie would have applied.
##
## It used to key the paper colour across the *whole* bitmap for every keyed ink,
## Matte included, at a brightness threshold. Matte keys only the paper a flood
## fill reaches from the border, so the crude rule punched every enclosed white
## region out of every sprite -- and on this corpus that means the interior of
## every piano key, which let the backdrop show through the keys and drew the seam
## under them as a clean line where the player correctly draws the key's own
## dithered row. That output was then quoted *against* the player as evidence of a
## rendering bug. A diagnostic that is wrong in a way nobody can see from its own
## output is worse than no diagnostic, so the parallel rule is gone rather than
## documented -- `docs/bugs-closed.md` 73 has the before-and-after numbers, and
## `bugs.md` 74 was the eight rows this did not account for.
##
## **74 closed on 2026-08-15, and it was never this file's fault nor the
## player's.** The eight rows were `stage_paint.gd:295` -- the *debug HUD*, the
## line reading `frame 37/206  playpiano  fps 15  hit:art  cur:0`, drawn at
## `Vector2(8, stage.y - 8)` = (8,472) in white at alpha 0.75. `stage_compare.gd`
## photographed the player with the debug layer on, so it photographed our own
## overlay and reported it as a compositor disagreement. Everything the entry
## recorded follows from that and from nothing else: the band it names,
## `(8,466) 252x9`, is that string's own bounding box; "243 distinct values where
## the diagnostic produces 23 exact palette entries" is antialiased glyph
## coverage reaching `Image.blend_rect`; and the difference showed *only* on the
## dark seam under the keys because white text over a white key changes nothing.
## With `--debug-ui off` the two agree on **0 of 268,800 px below y60**, on frames
## 37 and 39 alike. `stage_compare.gd` refuses to run with the layer on now.
##
## ## `compose` is public so that the comparison can be one process
##
## The reference picture used to have to be written to a PNG by one run and read
## back by another, which is a large part of why `bugs.md` 74 sat for two
## sessions with no gate entry: a harness cannot depend on a file some earlier
## command left in `/tmp`, and two runs can disagree about the frame.
## `stage_compare.gd` calls `compose()` directly now, so the whole comparison is
## one `gate.sh` entry with no temporary files.
##
## **Both halves of that sharing are on the diagnostic's side of the
## comparison**, which is the property that has to be preserved: the player
## reaches none of this file. What this *does* share with the player is
## `director_ink.gd` and `director_bitmap.gd`, deliberately, so that a
## disagreement is between the two composition paths and never between two
## decoders.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const PaletteView := preload("res://scenes/preview/palette_view.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const Ink := preload("res://director/director_ink.gd")
const Config := preload("res://director/director_config.gd")

## What a movie that states no stage size gets. The size itself comes from the
## movie's own config chunk below, the way `director_preview.gd:stage_size` reads
## it -- rendering an 800x600 title into a 640x480 image crops a third of it and
## the PNG looks like a renderer fault.
const STAGE := Vector2i(640, 480)


func _init() -> void:
	var args := Args.parse()
	var lines: Array[String] = []
	var stage := compose(Args.text(args, "file"), Args.number(args, "frame", -1),
		Args.text(args, "label"), lines)
	for line in lines:
		print(line)
	if stage == null:
		quit(1)
		return
	# Named for whichever of the two the caller gave, rather than for the resolved
	# index: `compose` does not hand one back, and `user://frame_-1.png` is what a
	# `--label` run used to get once the resolution moved inside it.
	var label := Args.text(args, "label")
	var out := Args.text(args, "out", "user://frame_%s.png" % [
		label if label != "" else str(Args.number(args, "frame", -1))])
	var err := stage.save_png(out)
	print("wrote %s" % out if err == OK else "could not write %s (%s)" % [out, error_string(err)])
	quit(0)


## One composited frame, or null with the reason appended to `lines`.
##
## **Public because `stage_compare.gd` is the other half of this diagnostic and
## has to run in the same process as the player it photographs.** Handing the
## reference picture over as a PNG on disc means two invocations, and two
## invocations can be of two different frames, two different corpora or two
## different commits -- which is exactly the class of mistake `bugs.md` 74's
## "reported frame 37 while standing on 41" note is about, one level up. Nothing
## here is a second decision about pixels: `_init` above is now only argument
## parsing and a `save_png` around this call, so the picture a comparison sees
## and the picture a person looks at are the same bytes.
##
## `lines` collects what the command-line form prints, rather than printing,
## because a harness that wants the image does not want 70 lines of sprite table
## in the middle of its own output and cannot suppress a `print`.
static func compose(file: String, index: int, label: String,
		lines: Array[String]) -> Image:
	var paths := Paths.new()
	if not paths.load_config():
		lines.append("no game configured: %s must set [game] root and boot_movie"
			% Paths.CONFIG_PATH)
		return null

	var path = paths.resolve(file if file != "" else paths.boot_movie)
	if path == "":
		lines.append("no such container: %s" % file)
		return null

	var movie := ContainerFile.new()
	if not movie.open(path):
		lines.append("%s: %s" % [path, movie.error])
		return null
	var vwsc: Array = movie.ids_of("VWSC")
	if vwsc.is_empty():
		lines.append("%s has no score" % path)
		return null

	var score := Score.new()
	if not score.parse(movie.read_chunk(vwsc[0])):
		lines.append("%s: %s" % [path, score.error])
		return null
	var labels := Labels.new()
	var vwlb: Array = movie.ids_of("VWLB")
	if not vwlb.is_empty():
		labels.parse(movie.read_chunk(vwlb[0]))

	if label != "":
		index = int(labels.labels.get(label.to_lower(), -1))
		if index < 0:
			lines.append("no label %s" % label)
			return null
	if index < 0 or index >= score.frame_count:
		lines.append("frame %d is outside 0..%d" % [index, score.frame_count - 1])
		return null

	var table := CastTable.new()
	if not table.open(movie, paths):
		lines.append("cast libraries: %s" % table.error)
		return null

	lines.append("%s frame %d (%s)" % [path.get_file(), index, labels.marker_at(index)])
	lines.append("libraries:")
	for lib in table.cast_libs:
		var entry: Dictionary = table.cast_libs[lib]
		lines.append("  %d  %-10s %s" % [lib, entry["name"], entry["path"]])

	var config = Config.new()
	var size: Vector2i = config.rect.size if config.read(movie) else STAGE
	lines.append("stage: %dx%d" % [size.x, size.y])
	var stage := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	stage.fill(Color.BLACK)
	var palette: PackedByteArray = Palette.system_mac()
	var drawn := 0
	var skipped := 0
	var started := Time.get_ticks_usec()

	lines.append("")
	for sprite in score.frame(index)["sprites"]:
		var lib := int(sprite["cast_lib"])
		var id := int(sprite["cast_id"])
		var m: Dictionary = table.get_member(lib, id)
		var name := str(m.get("name", ""))
		if m.is_empty() or int(m.get("type", 0)) != 1:
			# A shape or a script member draws nothing by design.
			skipped += 1
			lines.append("  ch %3d  %d:%-5d  %-16s skipped (%s)" % [
				sprite["channel"], lib, id, name, _why_skipped(m),
			])
			continue
		var f = table.file_for(lib)
		if f == null:
			skipped += 1
			continue
		var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
		var error: Array = []
		# The member's own palette, exactly as the player resolves it. This has no
		# playhead and so no stage palette, which `NO_STAGE_ID` says out loud: a
		# member that names a buildable palette gets it, and one that does not
		# falls back to the system Mac table above.
		var member_palette: PackedByteArray = PaletteView.table_for_member(
			m, table, palette, PaletteView.NO_STAGE_ID
		)
		var image: Image = Bitmap.decode(m, chunk, member_palette, error)
		if image == null:
			skipped += 1
			lines.append("  ch %3d  %d:%-5d  %-16s decode failed: %s" % [
				sprite["channel"], lib, id, name, "; ".join(error),
			])
			continue

		# The score's rect is the drawn size only when the stretch flag is set;
		# otherwise it is authoring residue and the member's own size wins.
		var w := int(m["width"])
		var hgt := int(m["height"])
		if bool(sprite["stretch"]):
			w = int(sprite["width"])
			hgt = int(sprite["height"])
			if w > 0 and hgt > 0 and (w != image.get_width() or hgt != image.get_height()):
				image.resize(w, hgt, Image.INTERPOLATE_NEAREST)

		# Ink through the engine's own rules, in the engine's own order: key first,
		# colourise second. `sprite_art.gd` explains why that order is
		# load-bearing -- a matte floods *white* in from the border, so repainting
		# the whites first leaves the flood nothing to match.
		var ink := int(sprite["ink"])
		# Through the record rather than through two indices, for the same reason
		# and by the same two calls the player uses: a D7 record may state the
		# colour itself instead of an index (`bugs.md` 30). A diagnostic that read
		# the index where the player read the colour would disagree with it on
		# every one of `piposh-dream`'s 55,134 such records, and that disagreement
		# is precisely what this tool exists not to invent.
		var fore := Ink.fore_colour(sprite, member_palette)
		var back := Ink.back_colour(sprite, member_palette)
		match Ink.key_for(sprite, m):
			Ink.KEY_MATTE:
				Ink.key_matte(image)
			Ink.KEY_PAPER:
				Ink.key_paper(image, back)
		if Ink.applies_colour_to(sprite, ink):
			Ink.apply_colour(image, fore, back)

		# loc is the registration point, not the top-left corner.
		var reg_x := int(m["reg_offset_x"])
		var reg_y := int(m["reg_offset_y"])
		if bool(sprite["stretch"]) and int(m["width"]) > 0:
			reg_x = int(round(float(reg_x) * w / float(m["width"])))
			reg_y = int(round(float(reg_y) * hgt / float(m["height"])))
		var at := Vector2i(int(sprite["loc_h"]) - reg_x, int(sprite["loc_v"]) - reg_y)
		stage.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		drawn += 1
		lines.append("  ch %3d  %d:%-5d  %-16s %4dx%-4d at (%4d,%4d) ink %d%s" % [
			sprite["channel"], lib, id, name, image.get_width(), image.get_height(),
			at.x, at.y, sprite["ink"], "  stretched" if sprite["stretch"] else "",
		])

	lines.append("")
	lines.append("drawn %d, skipped %d, %.0f ms" % [
		drawn, skipped, (Time.get_ticks_usec() - started) / 1000.0,
	])
	table.close()
	movie.close()
	return stage


## Why a sprite was not drawn, in enough detail to tell a decision from a gap.
##
## This printed `skipped (type15)` for Magic Hat's `yes` and `no` buttons, and a
## bare type number says only that something is missing. **Nothing is missing.**
## An Xtra cast member's picture is produced by a native Xtra DLL; this port hosts
## two Xtras (FileIO and BuddyAPI) and neither draws. The reference does the same:
## `castmember/xtra.cpp:promote` leaves an Xtra whose symbol is not in
## `xtraCastMemberProtos` as the base `XtraCastMember`, which inherits
## `CastMember::createWidget` returning `nullptr` (`castmember/castmember.h:70`,
## ScummVM 805f259a). So drawing nothing for one is correct, and the only defect
## was that the line did not say *which* Xtra was not drawn -- `flash` and
## `animGif` read as a decision, `type15` reads as a decoder that fell over.
static func _why_skipped(m: Dictionary) -> String:
	if m.is_empty():
		return "unresolved"
	var why := str(m.get("type_name", "?"))
	if bool(m.get("xtra_external", false)):
		return why + " (external): its Xtra is linked, not embedded"
	if not m.has("xtra_symbol"):
		return why
	var display := str(m.get("xtra_display_name", ""))
	return "%s '%s'%s: no native Xtra hosted, so Director draws nothing either" % [
		why, str(m["xtra_symbol"]), (" -- %s" % display) if display != "" else "",
	]

