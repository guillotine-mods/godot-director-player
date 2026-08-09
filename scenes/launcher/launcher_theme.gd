extends RefCounted
## What the launcher looks like: one palette, one type scale, one `Theme`.
##
## **Built in code rather than saved as a `.tres`**, and that is a decision
## rather than the shortest path. Two thirds of the styleboxes below are the
## same four colours in different arrangements, and a resource file states each
## of them as its own `[sub_resource]` block with the relationship between them
## recorded nowhere -- moving the accent would be a hunt through a diff no
## reviewer can read, and the compiler could not tell you when you missed one.
## Here the accent is `GOLD`, once. It is also how the rest of this port works:
## there is no `.tres` in the repository, because every resource here is built
## from the data it comes from.
##
## The palette is the app icon's. `icon.svg` is the only brand mark this project
## has and it carries four colours; `BG`, `RAISED` and `MUTED` are steps derived
## off those so that a panel can sit on a page and a caption can sit under a
## heading, and nothing else was invented.
##
## **No font is bundled, deliberately.** The built-in `Open Sans SemiBold` was
## measured on 4.7.1 to carry Hebrew (U+05D0..U+05EA) and Cyrillic
## (U+0410..U+044F) as well as Latin, and the titles this screen names are
## Hebrew games with a Russian localisation -- so a display face chosen for its
## Latin would go blank on the one screen that has to spell them. The three type
## roles are `FontVariation`s over that one face: tracking and size, not
## families. `launcher.gd`'s `EMOJI_FONTS` chain is separate and still needed,
## because the same face carries no emoji block at all and the flags are emoji.

## The icon's own four, and three steps derived from them.
const BG := Color("0e1626")
const SURFACE := Color("1a2740")
const RAISED := Color("223353")
const LINE := Color("2d4a6f")
const GOLD := Color("e8c547")
const GOLD_DEEP := Color("8d7328")
const TEXT := Color("eaf3ff")
const MUTED := Color("8ea3c4")
## A field that will not be accepted. Warm rather than red: a saturated red on
## this navy vibrates, and the only other warm colour on screen is the accent,
## so nothing else can be mistaken for it.
const WARN := Color("ff9276")

const SIZE_DISPLAY := 30
const SIZE_HEAD := 22
const SIZE_SECTION := 18
const SIZE_BODY := 16
const SIZE_SMALL := 14
const SIZE_EYEBROW := 12

const RADIUS := 4
## **Gold says "this is the one", near-white says "this is where you are".**
## The ring is the second of those and never the first, which is why it is not
## the accent: a focused tile already carries a gold border for being the
## selected one, and a gold ring around a gold border is one picture for two
## different facts. The ring is also drawn *outside* its control, so the two
## never sit on the same pixels.
const RING_WIDTH := 2
const RING_GAP := 3

static var _theme: Theme
static var _display: FontVariation
static var _body: FontVariation
static var _eyebrow: FontVariation


## Tight tracking, for type large enough that the default spacing reads loose.
static func display_font() -> FontVariation:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = ThemeDB.fallback_font
		_display.spacing_glyph = -1
	return _display


static func body_font() -> FontVariation:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = ThemeDB.fallback_font
	return _body


## Wide tracking, for the small capitals that label a group. This is the whole
## of the "second typeface": one family, two spacings, and the size doing the
## rest of the work.
static func eyebrow_font() -> FontVariation:
	if _eyebrow == null:
		_eyebrow = FontVariation.new()
		_eyebrow.base_font = ThemeDB.fallback_font
		_eyebrow.spacing_glyph = 2
	return _eyebrow


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = SIZE_BODY
	_panels(t)
	_labels(t)
	_buttons(t)
	_tiles(t)
	_fields(t)
	_checks(t)
	_slider(t)
	_tabs(t)
	_scrolling(t)
	_popup(t)
	_theme = t
	return t


## The ring, exposed because `HSlider` cannot take one from the theme -- 4.7's
## `Slider` has styleboxes for its track and its grabber and none for focus --
## so `launcher.gd` puts a panel behind the slider and swaps this onto it.
static func focus_ring() -> StyleBoxFlat:
	return _ring(TEXT)


static func blank() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## A `LineEdit` that will not be accepted, and the same box focused. Both are
## here rather than in `launcher.gd` so that "wrong" is one colour in one file;
## the launcher decides *which* field is wrong and this decides what that looks
## like.
static func field_wrong(focused: bool) -> StyleBoxFlat:
	var box := _flat(SURFACE, WARN, 2)
	box.set_content_margin_all(10)
	box.content_margin_left = 14
	box.content_margin_right = 14
	if focused:
		box.bg_color = RAISED
	return box


static func _flat(bg: Color, border := Color.TRANSPARENT, width := 0, radius := RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box


static func _ring(color := TEXT) -> StyleBoxFlat:
	var box := _flat(Color.TRANSPARENT, color, RING_WIDTH, RADIUS + RING_GAP)
	box.set_expand_margin_all(RING_GAP)
	return box


static func _pad(box: StyleBoxFlat, horizontal: int, vertical: int) -> StyleBoxFlat:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box


static func _panels(t: Theme) -> void:
	# The page itself. A bare `Panel` is the background and nothing else uses
	# that type, which is why the colour lives here and not as a `ColorRect`
	# with a hex in the scene file where it could drift from this one.
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Panel", _flat(BG, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("panel", "PanelContainer", _flat(SURFACE, LINE, 1, RADIUS + 2))
	t.set_stylebox("panel", "Card", _flat(SURFACE, LINE, 1, RADIUS + 2))


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	for variation in ["Display", "Head", "Section", "Hint", "Eyebrow", "Note"]:
		t.set_type_variation(variation, "Label")

	t.set_font("font", "Display", display_font())
	t.set_font_size("font_size", "Display", SIZE_DISPLAY)
	t.set_color("font_color", "Display", TEXT)

	t.set_font("font", "Head", display_font())
	t.set_font_size("font_size", "Head", SIZE_HEAD)
	t.set_color("font_color", "Head", TEXT)

	t.set_font_size("font_size", "Section", SIZE_SECTION)
	t.set_color("font_color", "Section", TEXT)

	t.set_font_size("font_size", "Hint", SIZE_SMALL)
	t.set_color("font_color", "Hint", MUTED)

	t.set_font("font", "Eyebrow", eyebrow_font())
	t.set_font_size("font_size", "Eyebrow", SIZE_EYEBROW)
	t.set_color("font_color", "Eyebrow", MUTED)

	t.set_font_size("font_size", "Note", SIZE_SMALL)
	t.set_color("font_color", "Note", WARN)


static func _buttons(t: Theme) -> void:
	_button_set(t, "Button", _flat(RAISED, LINE, 1), _flat(LINE, LINE, 1),
		_flat(LINE.lightened(0.08), LINE, 1), TEXT)
	t.set_constant("h_separation", "Button", 8)

	# The one filled control on the screen, and the only place the accent is a
	# background rather than an edge. Spending it here is what makes "Play" read
	# as the thing to press without a single arrow or shadow.
	t.set_type_variation("Primary", "Button")
	_button_set(t, "Primary", _flat(GOLD), _flat(GOLD.lightened(0.12)),
		_flat(GOLD.darkened(0.15)), BG)
	# Gold on gold is not a ring. The primary button is the one control whose
	# focus has to be drawn in the text colour instead.
	t.set_stylebox("focus", "Primary", _ring())
	t.set_stylebox("disabled", "Primary", _flat(SURFACE, LINE, 1))
	t.set_color("font_disabled_color", "Primary", MUTED)
	t.set_font_size("font_size", "Primary", SIZE_BODY)

	t.set_type_variation("Quiet", "Button")
	_button_set(t, "Quiet", _flat(Color.TRANSPARENT, LINE, 1), _flat(RAISED, LINE, 1),
		_flat(RAISED, MUTED, 1), MUTED)
	t.set_color("font_hover_color", "Quiet", TEXT)

	# The edition flags. Square, because the glyph inside is a flag and a
	# rounded button around a rounded flag is two radii arguing.
	t.set_type_variation("Flag", "Button")
	_button_set(t, "Flag", _flat(SURFACE, LINE, 1, 2), _flat(RAISED, LINE, 1, 2),
		_flat(RAISED, GOLD, 2, 2), TEXT)

	_button_set(t, "OptionButton", _flat(SURFACE, LINE, 1), _flat(RAISED, LINE, 1),
		_flat(RAISED, MUTED, 1), TEXT)
	t.set_constant("arrow_margin", "OptionButton", 10)
	t.set_color("font_disabled_color", "OptionButton", MUTED)
	# The arrow is an icon, so it takes the icon colours rather than the font
	# ones; left alone it stays the default theme's pale grey.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_focus_color"]:
		t.set_color(state, "OptionButton", MUTED)


static func _button_set(t: Theme, type: String, normal: StyleBoxFlat, hover: StyleBoxFlat,
		pressed: StyleBoxFlat, text: Color) -> void:
	t.set_stylebox("normal", type, _pad(normal, 18, 10))
	t.set_stylebox("hover", type, _pad(hover, 18, 10))
	t.set_stylebox("pressed", type, _pad(pressed, 18, 10))
	t.set_stylebox("disabled", type, _pad(_flat(SURFACE, LINE, 1), 18, 10))
	t.set_stylebox("focus", type, _ring())
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, type, text)
	t.set_color("font_disabled_color", type, MUTED.darkened(0.25))


## The picker. A tile carries its own type inside it, so the button's padding is
## zero and its styleboxes are only the plate: flat, a hairline, and the accent
## on the bottom edge of whichever one will play.
static func _tiles(t: Theme) -> void:
	t.set_type_variation("GameTile", "Button")
	var normal := _flat(SURFACE, LINE, 1, RADIUS + 2)
	var hover := _flat(RAISED, LINE, 1, RADIUS + 2)
	var selected := _flat(RAISED, GOLD, 1, RADIUS + 2)
	selected.border_width_bottom = 4
	t.set_stylebox("normal", "GameTile", normal)
	t.set_stylebox("hover", "GameTile", hover)
	t.set_stylebox("pressed", "GameTile", selected)
	t.set_stylebox("disabled", "GameTile", normal)
	t.set_stylebox("focus", "GameTile", _ring())


static func _fields(t: Theme) -> void:
	var normal := _pad(_flat(SURFACE, LINE, 1), 14, 10)
	var focused := _pad(_flat(RAISED, TEXT, 2), 14, 10)
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focused)
	t.set_stylebox("read_only", "LineEdit", _pad(_flat(BG, LINE, 1), 14, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.15))
	t.set_color("font_uneditable_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", LINE)
	t.set_constant("caret_width", "LineEdit", 2)
	t.set_constant("minimum_character_width", "LineEdit", 4)


## `CheckBox` draws a texture, not a stylebox, so a check that is not the
## default theme's pale grey tick has to be drawn here. Two 22px squares: an
## empty one with a hairline, and a filled one with the mark cut out of it in
## the page colour.
static func _checks(t: Theme) -> void:
	t.set_icon("checked", "CheckBox", _check_icon(GOLD, GOLD, BG))
	t.set_icon("unchecked", "CheckBox", _check_icon(Color.TRANSPARENT, LINE, Color.TRANSPARENT))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(LINE, LINE, BG))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(Color.TRANSPARENT, LINE, Color.TRANSPARENT))
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", _pad(_flat(Color.TRANSPARENT), 4, 6))
	t.set_stylebox("focus", "CheckBox", _ring())
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "CheckBox", TEXT)
	t.set_constant("h_separation", "CheckBox", 12)


static func _slider(t: Theme) -> void:
	# The page colour and not the card's: the track is a groove cut into the card
	# it sits on, and a track the same colour as its background is a grabber
	# floating on nothing.
	var track := _flat(BG, LINE, 1, 4)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _flat(GOLD_DEEP, Color.TRANSPARENT, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(GOLD, Color.TRANSPARENT, 0, 4))
	t.set_icon("grabber", "HSlider", _disc(GOLD, 18))
	t.set_icon("grabber_highlight", "HSlider", _disc(TEXT, 18))
	t.set_icon("grabber_disabled", "HSlider", _disc(LINE, 18))


## Folder tabs, not underlines: the selected tab is the same surface as the
## panel below it and merges into it, which is the one thing a tab shape is
## actually saying.
static func _tabs(t: Theme) -> void:
	var panel := _flat(SURFACE, LINE, 1, RADIUS + 2)
	panel.set_content_margin_all(0)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_stylebox("tabbar_background", "TabContainer", _flat(Color.TRANSPARENT))

	var selected := _flat(SURFACE, LINE, 1, RADIUS)
	selected.border_width_bottom = 0
	selected.corner_radius_bottom_left = 0
	selected.corner_radius_bottom_right = 0
	selected.border_width_top = 3
	selected.border_color = GOLD
	t.set_stylebox("tab_selected", "TabContainer", _pad(selected, 20, 9))
	t.set_stylebox("tab_unselected", "TabContainer", _pad(_flat(Color.TRANSPARENT), 20, 9))
	t.set_stylebox("tab_hovered", "TabContainer", _pad(_flat(RAISED, Color.TRANSPARENT, 0, RADIUS), 20, 9))
	t.set_stylebox("tab_focus", "TabContainer", _ring())
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 0)


static func _scrolling(t: Theme) -> void:
	t.set_stylebox("panel", "ScrollContainer", blank())
	t.set_stylebox("focus", "ScrollContainer", blank())
	# The bar's own width is the `scroll` stylebox's minimum size, so the padding
	# below is what makes it wide enough to see and to hit -- the default theme's
	# is thinner than the panel border it sits against here.
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _pad(_flat(BG, Color.TRANSPARENT, 0, 4), 3, 3))
		t.set_stylebox("grabber", bar, _flat(LINE, Color.TRANSPARENT, 0, 4))
		t.set_stylebox("grabber_highlight", bar, _flat(MUTED, Color.TRANSPARENT, 0, 4))
		t.set_stylebox("grabber_pressed", bar, _flat(MUTED, Color.TRANSPARENT, 0, 4))


static func _popup(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", _pad(_flat(SURFACE, LINE, 1), 0, 6))
	t.set_stylebox("hover", "PopupMenu", _flat(LINE, Color.TRANSPARENT, 0, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 12)


static func _check_icon(fill: Color, border: Color, mark: Color, size := 22) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in size:
		for x in size:
			var edge := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			image.set_pixel(x, y, border if edge else fill)
	if mark.a > 0.0:
		_stroke(image, Vector2i(6, 11), Vector2i(9, 15), mark, 3)
		_stroke(image, Vector2i(9, 15), Vector2i(16, 7), mark, 3)
	return ImageTexture.create_from_image(image)


static func _stroke(image: Image, from: Vector2i, to: Vector2i, color: Color, thickness: int) -> void:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	var half := thickness / 2
	for i in steps + 1:
		var point := Vector2(from).lerp(Vector2(to), float(i) / float(maxi(steps, 1)))
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				var x := int(roundf(point.x)) + dx
				var y := int(roundf(point.y)) + dy
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, color)


## The slider's grabber, antialiased by hand: the alpha is how far inside the
## radius a pixel's centre falls, which is one line and looks like a circle
## instead of like a staircase.
static func _disc(color: Color, size: int) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var centre := Vector2(size - 1, size - 1) * 0.5
	var radius := size * 0.5 - 0.5
	for y in size:
		for x in size:
			var alpha := clampf(radius - Vector2(x, y).distance_to(centre) + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(image)
