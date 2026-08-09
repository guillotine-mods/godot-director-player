extends SceneTree
## Every bitmap member's row stride is long enough to hold its own row.
##
##   godot --headless --path . --script tools/bitmap_geometry.gd
##   godot --headless --path . --script tools/bitmap_geometry.gd -- --root rating
##   godot --headless --path . --script tools/bitmap_geometry.gd -- --root piposh --verbose
##
## A bitmap cast member states its width, its height, its bit depth and the byte
## length of one stored row, and the last of those has to be at least as long as
## the first three imply. When it is not, the member record has been misread, and
## the way that shows up is the worst one available: `director_bitmap.gd`'s blits
## index `y * stride + x` into a buffer of exactly `stride * height`, so a short
## stride runs off the end **on the first row**, and a GDScript out-of-bounds read
## aborts the function it happens in. The blit stops half-written, the image is
## built from whatever was in the buffer, and the only trace is an engine error in
## a log nobody reads. The sprite draws wrong, on every repaint, silently.
##
## ## What this is a regression guard for
##
## `director_cast.gd:STRIDE_MASK` was `0x0FFF`, which is the identity for every
## stride below 4,096 and a truncation for every one above. Three members in six
## titles are above it -- the panoramic backdrops of `piposh-dream`'s three cat
## rooms, 4943 x 400 at 8 bits, pitch word `0x9350`, handed to the decoder as 848.
## Two of the six titles have no member wider than 4,095 pixels at all, so the
## fault was invisible in the corpus the gate is pinned to and lived in a title
## nothing had ever swept.
##
## The mask is `0x7FFF` now, and this is the measurement that settled it rather
## than a document: over all six roots, **119,013 bitmap members**, the pitch word
## with bit 15 removed equals the member's own width times its own depth rounded
## up to an even byte count -- every one of them, no exceptions in either
## direction. Bit 15 is `DEPTH_FLAG`, and it is the only bit of that word that is
## ever anything but stride in any file here.
##
## ## Why the check is the *inequality* and not the equality
##
## Equality is what the corpus shows and it is not what the format promises: a
## row may legitimately be padded to any alignment an authoring tool chose, and a
## check that demanded exactly-even-width would fail the first title that padded
## to four. The engine's requirement is one-sided -- the buffer must be big enough
## -- so that is what is asserted, and the *distribution* of the slack is printed
## beside it. A file that starts padding differently shows up as a new row in that
## distribution rather than as a failure, which is the difference between a gate
## that reports what changed and one that has to be edited before it will run.
##
## Cheap and corpus-wide on purpose: it reads cast records only, decodes no
## pixels, and takes a couple of seconds per title -- which is what makes it
## affordable as a gate entry, where `tools/liveness_sweep.gd`, the tool that
## surfaced the bug by tripping over it, is not.
##
## Title-agnostic: it knows widths, depths and byte counts, and no movie.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
## Preloaded rather than reached by `class_name`, for the reason
## `tools/director_containers.gd` gives: a headless `--script` run resolves global
## classes out of the editor's script cache and a class added since the last
## editor session is "not declared in the current scope" in a file nobody touched.
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")

## `director_cast.gd:TYPE_NAMES` -- a bitmap member.
const TYPE_BITMAP := 1


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie"
			% Paths.CONFIG_PATH)
		quit(1)
		return

	var case := "%s: every bitmap member's row fits its stride" % paths.root.get_file()
	h.begin(case)

	var total := 0
	var short: Array[String] = []
	var slack: Dictionary = {}
	for relative in paths.containers():
		var file = ContainerFile.new()
		if not file.open(paths.resolve(relative)):
			continue
		var cast = Cast.new()
		if not cast.open(file):
			file.close()
			continue
		for number in cast.member_numbers():
			var member: Dictionary = cast.member(number)
			if int(member.get("type", 0)) != TYPE_BITMAP:
				continue
			var width := int(member.get("width", 0))
			var height := int(member.get("height", 0))
			# A zero-area member is a legitimate empty slot rather than a geometry
			# fault, and `director_bitmap.gd:decode` refuses it by name.
			if width <= 0 or height <= 0:
				continue
			total += 1
			var depth := int(member.get("bits_per_pixel", 8))
			var stride := int(member.get("row_stride", 0))
			var row := int(ceili(float(width) * float(depth) / 8.0))
			slack[stride - row] = int(slack.get(stride - row, 0)) + 1
			if stride < row:
				short.append("%s #%d %s %dx%d at %d bit(s): stride %d, row needs %d" % [
					relative, number, str(member.get("name", "")), width, height,
					depth, stride, row])
		file.close()

	# The subject has to exist. A root with no bitmap member would pass every
	# assertion below over nothing, which is the dark-harness failure `gate.sh`
	# warns about and the one this ordering prevents.
	if not h.check("the corpus holds bitmap members to check", total > 0,
			"%d member(s)" % total):
		h.complete(case)
		quit(h.finish("bitmap member geometry"))
		return

	h.check("all %d bitmap member(s) have a stride at least one row long" % total,
		short.is_empty(),
		"%d short" % short.size() if not short.is_empty() else "")
	for line in short.slice(0, 20):
		print("     %s" % line)
	if short.size() > 20:
		print("     ... and %d more" % (short.size() - 20))

	# Reported, never asserted: see the header on why the padding is not the rule.
	print("")
	print("stride minus the bytes one row needs:")
	var amounts: Array = slack.keys()
	amounts.sort()
	for amount in amounts:
		print("  %+5d byte(s) : %d member(s)" % [int(amount), int(slack[amount])])
	if Args.flag(args, "verbose"):
		print("")
		print("root: %s" % paths.root)
	h.complete(case)
	quit(h.finish("bitmap member geometry"))
