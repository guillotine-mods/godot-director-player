extends RefCounted
## The cursor: which one applies where, and how a custom one is composed.
##
## Two independent questions live here and conflating them is the mistake this
## module is arranged to prevent. **Arbitration** -- `at()` -- asks which cursor
## a stage point is under, and is pure logic over the sprite stack. **Composition**
## -- `compose`, `for_stage`, `install` -- turns a `[data, mask]` member pair into
## something the OS will accept. A bug in the first looks exactly like a bug in
## the second from the player's chair, and they were previously interleaved.
##
## The cadence is Director's and is not per-frame: the cursor is recomputed on
## mouse movement, on mouse-up and when a script writes one. A sprite that swaps
## to a member with a different cursor under a stationary mouse keeps the old one
## until something moves.

const Bitmap := preload("res://director/director_bitmap.gd")
const Members := preload("res://scenes/preview/members.gd")

## Fixed 16x16, cropped from the members' top-left: larger members are cropped,
## smaller ones padded transparent.
const CURSOR_SIZE := 16

## Largest a member may be and still be treated as cursor art. The corpus clears
## a channel's cursor with `set the cursor of sprite N to [1, 1]` 208 times, and
## member 1 is not cursor art -- measured in MAP's internal cast it is `a1`, a
## 640x400 backdrop. Cropping that to 16x16 puts a patch of scenery under the
## pointer, which reads as a corrupt cursor rather than as the arrow the author
## asked for. The biggest real cursor in this corpus is 17x17.
const MAX_CURSOR_SIZE := 32

## Godot refuses a custom cursor above this, and a cursor that large would be
## absurd anyway. 16x16 art at a 4x stage is 64, so the ceiling only bites on
## genuinely enormous windows, where the cursor stops growing rather than
## disappearing.
const MAX_CURSOR_PIXELS := 128


## Is this channel one to fall through rather than stop on?
##
## "Empty" is a distinct state in Director: a cursor counts as empty when its
## resource id is the integer 0 and *not* a list. So a list always stops the
## descent, even one that will not compose -- which is why the corpus's
## `set the cursor of sprite N to [1, 1]` reads as "arrow here", not as "ask the
## channel underneath".
static func is_empty(value: Variant) -> bool:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).is_empty()
	return int(value) == 0


## What the cursor should be at a stage point: a channel's pair, or the global.
##
## Descend channels highest first, rect-test, and take the first channel whose
## cursor is non-empty; if none supplies one, the global cursor stands. The
## descent deliberately does NOT filter on responds-to-mouse: cursor eligibility
## and click eligibility are different tests over the same stack, so a sprite
## that cannot be clicked can still change the cursor over it. The score builds
## its sprite array in ascending channel order, so walking it backwards is
## highest-first.
##
## Separated from the recompute so the arbitration can be asked a question
## without a real pointer. Headless there is no mouse, so a check that drove the
## recompute alone could only ever observe the global cursor and would pass while
## every channel was mis-resolved -- which is exactly the state this whole path
## was in.
static func at(host, point: Vector2, sprites: Array, channel_cursors: Dictionary,
		global_cursor: Variant) -> Variant:
	for i in range(sprites.size() - 1, -1, -1):
		# `effective`, not the raw score record, and for the same reason the draw
		# path uses it: a script that hid a channel or moved it returns `{}` or a
		# different rect, and a cursor arbitrated off the score's copy would
		# answer for a sprite that is not where the player sees it -- or is not
		# there at all. MAP's own frame script does both
		# (`the locH of sprite 15 to 1000`, `sprite(20).visible = 0`), so this is
		# not a hypothetical shape.
		var sprite: Dictionary = host._effective(sprites[i])
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		if not channel_cursors.has(channel):
			continue
		var candidate: Variant = channel_cursors[channel]
		if is_empty(candidate):
			continue
		var rect: Rect2 = host._sprite_rect(sprite)
		if not rect.has_point(point):
			continue
		return candidate
	return global_cursor


## A cursor is stage art and has to grow with the stage.
##
## Everything else the movie draws goes through the node's own `scale`, which the
## window fit sets -- 1.5x at the default window. The OS cursor does not:
## `Input.set_custom_mouse_cursor` takes real screen pixels, so a 16x16 cursor
## handed over unscaled is drawn at a third of the size of the artwork it is
## supposed to belong to, which is what "the cursor is tiny" is.
##
## Nearest-neighbour on purpose: this is 1-bit art from 1997 with hard edges, and
## smoothing it produces a grey halo around every pixel. The hotspot scales with
## the image, because Godot reads it in the texture's own pixels.
static func for_stage(image: Image, hotspot: Vector2, stage_scale: float) -> Dictionary:
	var factor := maxi(1, int(round(stage_scale)))
	if factor <= 1:
		return {"image": image, "hotspot": hotspot}
	var width := image.get_width() * factor
	var height := image.get_height() * factor
	if width > MAX_CURSOR_PIXELS or height > MAX_CURSOR_PIXELS:
		return {"image": image, "hotspot": hotspot}
	var grown := Image.new()
	grown.copy_from(image)
	grown.resize(width, height, Image.INTERPOLATE_NEAREST)
	return {"image": grown, "hotspot": hotspot * float(factor)}


## `[library, slot]` for one half of a cursor pair.
##
## A pair may carry either spelling of a member number and they are answered
## differently, which is the whole of this function. A **packed** reference --
## `Members.pack_ref`, what `the number of member "cutcursor" of castLib
## "panel.cst"` produces -- names its library outright, and that library wins with
## no search at all. A **bare** number named no library, so it is resolved the way
## Director resolves a bare `member(N)` and `library_of` walks for it.
##
## Guessing at a number that was never ambiguous is what drew the white card. The
## pair on Rating's שיחה button is Panel.cst's `cutcursor`/`cutcursor2`, library 7,
## and asking `library_of` for 166 and 167 answered library 1 (`leftcursor2`) and
## library 2 (`aa`) -- a silhouette from one cast masked by an unrelated bitmap
## from another. Both halves of one authored pair, resolved into two different
## wrong casts.
static func where(value: int, table) -> Array:
	if value >= Members.LIB_STRIDE:
		return [value / Members.LIB_STRIDE + 1, value % Members.LIB_STRIDE]
	return [library_of(value, table), value]


## Which library holds cursor art at this bare member number, or -1.
##
## Only for a number that named no library. The movie's own cast first, then the
## other libraries the movie can address, in library order; library numbers start
## at 1 and 1 is always the movie's own, so an ascending walk is that rule.
##
## This used to be hard-coded to 1, which meant a cursor member living in a
## linked cast was never found -- it composed to nothing and read as the arrow,
## the same silent shape as every other lookup that stopped at library 1
## (docs/bugs-closed.md 29). The movie's own library still answers whenever it
## holds art at that number, so this can only add answers where there were none.
static func library_of(cast_id: int, table) -> int:
	if table == null:
		return -1
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for lib in libs:
		var m: Dictionary = table.get_member(int(lib), cast_id)
		if m.is_empty() or int(m.get("data_chunk_id", -1)) < 0:
			continue
		if table.file_for(int(lib)) == null:
			continue
		return int(lib)
	return -1


## One 1-bit member, decoded, from whichever library `library_of` names.
static func member_image(cast_id: int, table, palette: PackedByteArray) -> Image:
	return image_in(library_of(cast_id, table), cast_id, table, palette)


## The same, when the caller has already resolved the library and must not let a
## second lookup pick a different one -- the hotspot has to come from the member
## the picture came from.
static func image_in(cast_lib: int, cast_id: int, table,
		palette: PackedByteArray) -> Image:
	if cast_lib < 1 or table == null:
		return null
	var m: Dictionary = table.get_member(cast_lib, cast_id)
	if m.is_empty() or int(m.get("data_chunk_id", -1)) < 0:
		return null
	var f = table.file_for(cast_lib)
	if f == null:
		return null
	var error: Array = []
	return Bitmap.decode(m, f.read_chunk(int(m["data_chunk_id"])), palette, error)


## Compose a 1-bit data/mask pair into a cursor image: `{image, hotspot}`, or
## null when nothing visible came out.
##
## The mask's BLACK region is the visible silhouette -- where the mask is white
## the pixel is transparent, and where it is black the colour comes from the data
## member. Reading only the data gives a black rectangle; inverting the mask
## gives an invisible cursor.
##
## **A pair may name no mask, and then the data member is its own mask** -- black
## pixels draw black, white pixels are transparent. This is a deliberate departure
## from the reference implementation, which is why it is argued rather than cited:
## ScummVM's `Cursor::readFromCast` writes `(!mask || *mask) ? ... : 3`, so its
## *intent* is that a missing mask is fully opaque, exactly what this function used
## to do -- and then the bounds guard above that line, `x >= cursorSurface->w ||
## (!maskSurface || x >= maskSurface->w)`, nulls every pixel of a maskless cursor
## and it *delivers* a fully transparent one. Neither of those is what the artwork
## was drawn for, and the artwork is the evidence. Rating names one member three
## times -- `talkcursor`, `WalkLeftCursor`, `weaponCursor` -- and where it does
## supply a mask (`leftcursor`/`leftcursor2`, `casecursor`/`casecursor2`,
## `takecursor`/`takecursor2`) the mask is a filled, dilated silhouette whose whole
## job is to make the drawing's white interior opaque. `WalkLeftCursor` settles it:
## a solid black arrow with no outline and no white anywhere it wants kept, which
## opaque composition can only render as a white card with an arrow on it. That
## card is `docs/bugs-closed.md` 64.
##
## Null on a fully transparent result, so the caller can fall back to the arrow
## rather than installing a cursor the player cannot see. A maskless member that is
## entirely white reaches that fallback, which is the honest answer for art with
## nothing to show once it is its own mask.
static func compose(data_id: int, mask_id: int, table, palette: PackedByteArray):
	# Resolved once and remembered, so the hotspot read below comes from the same
	# member as the picture. Resolving twice would let a data member found in a
	# linked cast take its registration point from an unrelated member of the
	# movie's own cast that happens to share the number.
	var data_at: Array = where(data_id, table)
	var data_lib := int(data_at[0])
	var data_slot := int(data_at[1])
	var data := image_in(data_lib, data_slot, table, palette)
	if data == null:
		return null
	if data.get_width() > MAX_CURSOR_SIZE or data.get_height() > MAX_CURSOR_SIZE:
		return null
	# Only the *absent* mask defaults to the data. A mask that was named and did not
	# resolve keeps falling through to the opaque path: substituting the data there
	# would compose a plausible cursor out of a library lookup that failed, which is
	# the silent shape `docs/bugs-closed.md` 29 was.
	var mask := data
	if mask_id > 0:
		var mask_at: Array = where(mask_id, table)
		mask = image_in(int(mask_at[0]), int(mask_at[1]), table, palette)
	var out := Image.create(CURSOR_SIZE, CURSOR_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var visible := 0
	for y in CURSOR_SIZE:
		for x in CURSOR_SIZE:
			if x >= data.get_width() or y >= data.get_height():
				continue
			var shown := true
			if mask != null:
				if x >= mask.get_width() or y >= mask.get_height():
					shown = false
				else:
					shown = mask.get_pixel(x, y).r < 0.5
			if not shown:
				continue
			visible += 1
			out.set_pixel(x, y, Color.BLACK if data.get_pixel(x, y).r < 0.5 else Color.WHITE)
	if visible == 0:
		return null

	# The hotspot is the data member's registration point, and it is recentred
	# when it falls outside the 16x16 crop -- an out-of-range hotspot would put
	# the click somewhere the cursor is not drawn.
	var m: Dictionary = table.get_member(data_lib, data_slot)
	var hotspot := Vector2i(
		int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0))
	)
	if hotspot.x < 0 or hotspot.y < 0 \
			or hotspot.x >= CURSOR_SIZE or hotspot.y >= CURSOR_SIZE:
		hotspot = Vector2i(CURSOR_SIZE / 2, CURSOR_SIZE / 2)
	return {"image": out, "hotspot": Vector2(hotspot)}


## Install a cursor: a `[data, mask]` member pair, or a built-in number. Returns
## the description to record as the current cursor.
static func install(value: Variant, table, palette: PackedByteArray,
		stage_scale: float) -> String:
	if typeof(value) == TYPE_ARRAY:
		var pair: Array = value
		if not pair.is_empty():
			var mask_id := int(pair[1]) if pair.size() > 1 else 0
			var composed = compose(int(pair[0]), mask_id, table, palette)
			if composed != null:
				var scaled := for_stage(
					composed["image"] as Image, composed["hotspot"] as Vector2,
					stage_scale
				)
				Input.set_custom_mouse_cursor(
					ImageTexture.create_from_image(scaled["image"]),
					Input.CURSOR_ARROW, scaled["hotspot"]
				)
				# Reported as `library:slot`, not as the raw pair. The raw pair is
				# what the HUD showed when this file resolved 166 and 167 into two
				# different wrong casts, and `custom 166/167` looked entirely
				# reasonable -- the library is the half that was wrong, so the
				# library is the half worth printing.
				var at: Array = where(int(pair[0]), table)
				var mask_at: Array = where(mask_id, table) if mask_id > 0 else [0, 0]
				return "custom %s:%s/%s:%s" % [
					str(at[0]), str(at[1]), str(mask_at[0]), str(mask_at[1])]
		# A pair that composes to nothing visible would hand Godot a fully
		# transparent image, and the cursor disappears rather than falling back.
		# An invisible cursor and a broken one look the same to the player.
		Input.set_custom_mouse_cursor(null)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return "arrow (pair empty)"
	var which := int(value)
	Input.set_custom_mouse_cursor(null)
	# Director's built-in numbers. -1 and 0 are the arrow; the rest map onto the
	# nearest shape Godot offers, which is a translation rather than the real
	# artwork and is noted as such.
	match which:
		1:
			Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
		2, 3:
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		4:
			Input.set_default_cursor_shape(Input.CURSOR_WAIT)
		200:
			# Director's blank cursor: a transparent 1x1 image, since Godot has
			# no "hidden" shape that survives a custom-cursor reset.
			var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			blank.fill(Color(0, 0, 0, 0))
			Input.set_custom_mouse_cursor(ImageTexture.create_from_image(blank))
		_:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	return str(which)
