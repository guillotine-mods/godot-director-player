extends RefCounted
## One title, as something you can see before you press it.
##
## The picker used to be an `OptionButton`: six words behind a chevron, which
## tells you the name of a thing and nothing about it. A tile says the title,
## which editions of it are on disc, and the folder under `games/` the engine
## will read -- and that last line is the one a bug report needs and the one no
## menu here has ever shown.
##
## **The plate is the seam where cover art drops in, and it is deliberately
## still empty.** `Art` is a `TextureRect` with nothing in it and
## `visible = false`; make `art_for()` return a texture and the picture lands
## behind the type with nothing else to change. The tile is drawn to read
## without one -- the title set large *is* the artwork -- so this is somewhere
## to put a picture rather than a hole waiting for one.
##
## What filling it would cost, so that the next person can decide rather than
## discover: pulling a bitmap out of a title needs the member *number*, because
## asking for one by name goes through `director_cast.gd:_build_names`, which
## parses every member in the library to build the index. So it wants a
## per-root `(container, member number)` table -- which is a per-title mapping,
## and the standing rule in `AGENTS.md` is that those do not belong in engine
## code -- and `DirectorPaths.resolve` walking 79 to 124 containers per root,
## six roots deep, on the one screen that has to appear instantly. And the
## result could not be committed either way: `games/` and `.snapshots/` are both
## gitignored because the discs are not ours to redistribute, so anything
## extracted has to be a `user://` cache built on first run.

const TitleList := preload("res://scenes/launcher/title_list.gd")

const MIN_WIDTH := 250
## The comfortable height: what a tile takes when the window is not arguing.
const MIN_HEIGHT := 152
## What a tile is allowed to grow to when the window has height to spare.
## Unbounded, a single row of four in a maximized window becomes four 700px
## panels with a word in the corner of each.
const MAX_HEIGHT := 196
## How far a tile may be squeezed before the grid gives up and scrolls.
##
## A second row arrives at five titles, and on a short window two rows of
## `MIN_HEIGHT` do not fit -- so the grid scrolled, and what it scrolled out of
## sight was everything below it. Scrolling to reach Stage Fit is a worse outcome
## than a shorter tile, so the tile yields first.
##
## The number is what the contents actually need rather than a guess: the title
## is set in `Display`, the root line in `Eyebrow`, and `PADDING` is applied
## twice. Below this they start to crowd, and at that point scrolling genuinely
## is the better answer.
const FLOOR_HEIGHT := 112
const PADDING := 16


## A `Button` in the `GameTile` variation, with the title's own text laid into
## it. The caller owns the signals: this returns a control and connects nothing,
## because which press means "select" and which means "play" is the launcher's
## question and not the tile's.
##
## `flag_font` is passed in rather than built here so that the emoji fallback
## chain stays stated once, in `launcher.gd`, where its comment explains what
## Windows does with a regional-indicator pair it cannot draw. Two copies of a
## font list is two places to fix the day a platform is added.
static func make(entry: Dictionary, flag_font: Font) -> Button:
	var tile := Button.new()
	tile.theme_type_variation = "GameTile"
	tile.toggle_mode = true
	tile.custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = roots_line(entry)
	# Named after the folder it opens rather than left as `@Button@56`, because
	# the focus map is a graph of node names and a harness reporting on it is
	# unreadable without them.
	tile.name = "Tile_%s" % str(TitleList.default_root(entry).get("root", "")).get_file()

	var art := TextureRect.new()
	art.name = "Art"
	art.texture = art_for(entry)
	art.visible = art.texture != null
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(art)

	# A `Button` is not a container, so its contents are anchored rather than
	# laid out, and every one of them has to decline the mouse or the button
	# under them never sees a click.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PADDING)
	tile.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	# Everything sits on the bottom edge and the empty space pools above it, so
	# that a tile stretched by a tall window grows a margin rather than drifting
	# its title into the middle of a box.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(_title_label(entry))

	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override("separation", 8)
	var roots := _roots_label(entry)
	roots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(roots)
	footer.add_child(_flags_label(entry, flag_font))
	column.add_child(footer)
	return tile


## Nothing yet, and the signature is the point: give this a `Texture2D` keyed off
## `entry["roots"]` -- a file beside the game, a member decoded out of its own
## container -- and every tile grows a cover.
static func art_for(_entry: Dictionary) -> Texture2D:
	return null


## The editions this title ships in, as flags, on the same line as the folder
## they live in -- the two answer the same question and the row is the answer.
## A title with one edition draws nothing here and keeps the line height, so the
## titles beside it still sit on one baseline.
static func _flags_label(entry: Dictionary, flag_font: Font) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", flag_font)
	label.add_theme_font_size_override("font_size", 17)
	var flags := ""
	for row in entry.get("roots", []) as Array:
		flags += TitleList.flag_emoji(str((row as Dictionary).get("flag", "")))
	label.text = flags
	label.custom_minimum_size = Vector2(0, 22)
	return label


static func _title_label(entry: Dictionary) -> Label:
	var label := Label.new()
	label.theme_type_variation = "Display"
	label.text = str(entry.get("title", ""))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## What the engine will actually open, as `root/container` -- the pair every
## path in this port is resolved against, and the pair a bug report has to
## carry. A title with three editions still shows one of them: the flags beside
## this line already say there are three, and listing all their folders is the
## same fact twice in the space of one.
static func _roots_label(entry: Dictionary) -> Label:
	var label := Label.new()
	label.theme_type_variation = "Eyebrow"
	label.text = roots_line(entry)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## Public, because the launcher shows the same line without a tile around it
## when there is only one title and therefore nothing to pick between.
static func roots_line(entry: Dictionary) -> String:
	var row := TitleList.default_root(entry)
	var name := str(row.get("root", "")).get_file()
	var boot := str(row.get("boot", ""))
	return "%s / %s" % [name, boot] if boot != "" else name
