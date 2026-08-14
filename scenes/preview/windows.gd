extends RefCounted
## Movie-In-A-Window: where a window sits, what it is called, and who gets the
## click.
##
## A window in this port is another `director_preview` node playing another
## movie, parented to the stage. So the lifecycle -- create, open, forget -- is
## node manipulation and stays on the node. What lives here is everything that
## is *about* a window rather than *done to* one: the type constants, the
## geometry, the property vocabulary, the chrome, and the routing that decides
## which movie a stage point belongs to.
##
## **Almost all of it is unverified.** Every window in this corpus is
## `windowType` 2 -- a one-pixel border and nothing else -- and no site sets
## `the modal of window` or reads `the windowList`. The titled types, the modal
## blocking and the drawRect scaling are built because Director has them.

const LingoValue := preload("res://lingo/lingo_value.gd")
const Paint := preload("res://director/director_paint.gd")

const NO_BORDER := -1
const DOCUMENT := 0
const ALERT := 1
const PLAIN := 2
const PLAIN_SHADOW := 3
const DOCUMENT_NO_SIZE := 4
const DOCUMENT_ZOOM := 8
const ROUNDED := 12
const ROUNDED_NO_TITLE := 16
const PALETTE := 49

const TITLED := [DOCUMENT, DOCUMENT_NO_SIZE, DOCUMENT_ZOOM, ROUNDED, PALETTE]
const BORDERED := [
	DOCUMENT, ALERT, PLAIN, PLAIN_SHADOW, DOCUMENT_NO_SIZE, DOCUMENT_ZOOM,
	ROUNDED, ROUNDED_NO_TITLE, PALETTE,
]

const TITLE_BAR := 18


## `[l, t, r, b]` as Lingo writes a rect, or null. Director also accepts a rect
## value; both arrive here as a four-element list.
static func rect_of(value: Variant):
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 4:
		return null
	var v: Array = value
	var left := LingoValue.to_int(v[0])
	var top := LingoValue.to_int(v[1])
	var right := LingoValue.to_int(v[2])
	var bottom := LingoValue.to_int(v[3])
	if right <= left or bottom <= top:
		return null
	return Rect2(left, top, right - left, bottom - top)


static func border_width(window_type: int) -> int:
	return 1 if BORDERED.has(window_type) else 0


static func has_title_bar(window_type: int, title_visible: bool) -> bool:
	return title_visible and TITLED.has(window_type)


## How far the movie's own top-left is pushed in by the chrome: the title bar and
## the border. Zero for `windowType` 2, which is what this corpus uses.
static func chrome_inset(window_type: int, title_visible: bool) -> Vector2:
	var edge := float(border_width(window_type))
	var top := edge
	if has_title_bar(window_type, title_visible):
		top += TITLE_BAR
	return Vector2(edge, top)


## The window's whole frame on the stage, chrome included. The movie sits inside
## it, below the title bar when there is one.
static func frame_of(origin: Vector2, drawn: Vector2, inset: Vector2,
		edge: int) -> Rect2:
	return Rect2(origin - inset, drawn + inset + Vector2(edge, edge))


## How much the movie is stretched inside its window: `the drawRect of window`
## against the movie's natural size. 1:1 unless a script set one. Unverified.
static func scale_of(draw_rect, natural: Vector2) -> Vector2:
	if draw_rect == null:
		return Vector2.ONE
	if natural.x <= 0.0 or natural.y <= 0.0:
		return Vector2.ONE
	return (draw_rect as Rect2).size / natural


## The frame around a window's movie: a border, a title bar and a drop shadow, as
## `the windowType` and `the titleVisible` ask for them.
##
## Schematic rather than period-accurate, and that is the honest trade: the point
## is that a titled window is visibly titled and that its movie is inset by the
## bar, not that it looks like System 7.
##
## Drawn in the window's own local space, where the movie's top-left is the
## origin and the chrome is at negative coordinates above and to the left.
static func draw_chrome(host, size: Vector2, window_type: int,
		title_visible: bool, title: String) -> void:
	var edge := float(border_width(window_type))
	if window_type == PLAIN_SHADOW:
		# The shadow is under the window and offset, so it is drawn first and
		# outside the frame on the far two sides.
		Paint.rect(host, Rect2(Vector2(4, 4), size + Vector2(edge, edge)),
			Color(0, 0, 0, 0.4), true)
	if has_title_bar(window_type, title_visible):
		var bar := Rect2(Vector2(-edge, -edge - TITLE_BAR),
			Vector2(size.x + edge * 2.0, TITLE_BAR))
		Paint.rect(host, bar, Color(0.82, 0.82, 0.82), true)
		Paint.rect(host, bar, Color(0.25, 0.25, 0.25), false, 1.0)
		if title != "":
			Paint.text(
				host, ThemeDB.fallback_font, bar.position + Vector2(6, TITLE_BAR - 5),
				title, HORIZONTAL_ALIGNMENT_LEFT, bar.size.x - 12, 12,
				Color(0.1, 0.1, 0.1)
			)
	if edge > 0.0:
		var inset := chrome_inset(window_type, title_visible)
		Paint.rect(host, Rect2(-inset, size + inset + Vector2(edge, edge)),
			Color(0.25, 0.25, 0.25), false, edge)


# ------------------------------------------------------------- the stack

## **The stage's own place in the stacking order.**
##
## Director does not have a stage and a separate list of windows on top of it:
## the stage *is* a window (§14), it sits in the same window list as every
## Movie-In-A-Window, and `moveToFront(the stage)` raises it over them exactly as
## `moveToFront(window "x")` raises a window over the stage. That is the whole
## reason `moveToFront` was a gap worth closing rather than a name to bind to a
## no-op: without a place for the stage in the order there is nothing for the
## call to mean.
##
## `""` is the key `window("")` and `the stage` already resolve to
## (`preview_lingo_host.gd:stage_handle`), so this is that same name rather than
## a new sentinel, and `_windows` never holds it -- the stage is the node the
## windows are parented to.
##
## **Absent from `_window_order` means the stage is at the bottom**, which is both
## the state every title starts in and the truth about this port's node tree: a
## window here is a child of the stage node, and a child draws over its parent.
## So a movie that never moves the stage has a `_window_order` byte-for-byte
## identical to what it had before any of this existed, and the code below walks
## it identically.
const STAGE_KEY := ""


## Where the stage sits, or -1 for "at the bottom, implicitly".
static func stage_index(owner) -> int:
	return owner._window_order.find(STAGE_KEY)


## Put the stage into the order at the place it already implicitly occupies, so
## that a move can be expressed as a list operation. Idempotent.
static func _materialise_stage(owner) -> void:
	if owner._window_order.find(STAGE_KEY) < 0:
		owner._window_order.insert(0, STAGE_KEY)


## Make the node tree say what `_window_order` says.
##
## Godot draws a `CanvasItem`'s children over the item itself, in child order, so
## "in front of the stage" is a later child and "behind the stage" is
## `show_behind_parent` -- the one flag that puts a child under its parent's own
## drawing. There is no other way round it: the stage paints into its *own*
## canvas item, and a parent's item is always beneath its children unless the
## child says otherwise.
##
## Idempotent, and cheap enough to call from every read of the stack: it is a
## walk of a list this corpus never grows past two entries. It is called from the
## readers rather than only from the movers because **`lingo_open_window` reorders
## `_window_order` without going through here** -- it does its own
## erase/append/`move_child` triple -- so a window that was sent behind the stage
## and later reopened would keep a stale `show_behind_parent` until something
## asked about the stack. The real fix for that is one line in
## `director_preview.gd:lingo_open_window`: call `Windows.move_to_front(self, key)`
## instead of the triple, which is the same three operations plus this.
static func restack(owner) -> void:
	var stage_at: int = owner._window_order.find(STAGE_KEY)
	var above: Array[Node] = []
	var below: Array[Node] = []
	for i in owner._window_order.size():
		var key := str(owner._window_order[i])
		if key == STAGE_KEY:
			continue
		var node: Node = owner._windows.get(key)
		if node == null:
			continue
		# Annotated rather than inferred: `owner` is untyped, so the loop variable
		# over its list has no type for `:=` to infer through and the whole module
		# fails to compile.
		var behind: bool = stage_at >= 0 and int(i) < stage_at
		node.show_behind_parent = behind
		if behind:
			below.append(node)
		else:
			above.append(node)
	# Front-most last for the above group, because `move_child` to the final index
	# in list order leaves the last one on top; and reversed for the below group,
	# because repeatedly moving to index 0 in list order would invert it.
	for i in range(below.size() - 1, -1, -1):
		owner.move_child(below[i], 0)
	for node in above:
		owner.move_child(node, owner.get_child_count() - 1)


## `moveToFront` (§7.4). Raise a window -- or the stage -- over everything else.
##
## The reference's `m_moveToFront` (`lingo/lingo-object.cpp:1027`) does three
## things: make sure the window's movie is loaded, make it the window manager's
## active window, and send it `openWindow` if it was not already active.
## The first two are here. **The third is deliberately not**, and the reason is
## consistency rather than laziness: this port dispatches no window event at all
## -- `openWindow`, `closeWindow`, `activateWindow` and `deactivateWindow` are
## listed in `docs/LINGO_SURFACE.md` §6 and bound nowhere, and `lingo_open_window`
## itself does not send one either. Sending it from *this* call alone would mean
## `moveToFront` raised an event that `open` does not, which is a stranger state
## than not having the event.
##
## Returns false for a name that is not a window, so a caller can tell "raised"
## from "there was nothing to raise" -- `moveToFront(window "jokes.dxr")` on a
## disc with no such file must not silently read as success.
static func move_to_front(owner, key: String) -> bool:
	if key != STAGE_KEY and not owner._windows.has(key):
		return false
	_materialise_stage(owner)
	owner._window_order.erase(key)
	owner._window_order.append(key)
	restack(owner)
	owner.queue_redraw()
	return true


## `moveToBack` (§7.4). Send a window -- or the stage -- behind everything else.
##
## **The reference stubs this** (`lingo/lingo-object.cpp:1022`,
## `printSTUBWithArglist`), so it is built from what the window list means rather
## than copied: the back of the list is the back of the list, and with the stage
## in that list a window sent to the back goes *behind the stage* and is no longer
## visible. That reading is what the corpus's only use asks for --
## `torfim.dir on stopMovie` says `moveToBack(StudyWindow)` and then
## `forget(StudyWindow)`, which is "hide it, then destroy it" and is pointless if
## `moveToBack` only reorders windows among themselves when there is one window.
##
## Unverified against Director running, for the reason above: there is no
## reference implementation to check it against and no title here opens two
## windows at once.
static func move_to_back(owner, key: String) -> bool:
	if key != STAGE_KEY and not owner._windows.has(key):
		return false
	_materialise_stage(owner)
	owner._window_order.erase(key)
	owner._window_order.insert(0, key)
	restack(owner)
	owner.queue_redraw()
	return true


## The open windows, back to front. `the windowList`.
##
## Director's list holds window references and a script may add to or remove from
## it; here it is read-only, because a window in this port exists only as the
## movie behind it and there is nothing to put in the list that `window(...)` has
## not already created. Unverified: no site in this corpus reads it.
##
## The stage's entry is not one of them -- `the windowList` is the *windows*, and
## `_windows` has no node under `STAGE_KEY` anyway, so this skips it by
## construction rather than by a test.
static func keys(owner) -> Array:
	restack(owner)
	var out: Array = []
	for key in owner._window_order:
		var node: Node = owner._windows.get(key)
		if node != null and node._window_shown:
			out.append(str(key))
	return out


## The front-most open window, or null. Director's active window, which is where
## a keypress goes when the pointer is not over anything.
##
## **Null also means "the stage is in front"**, which is a new answer and the same
## answer: every caller already reads null as "there is no window, so the stage
## has it". Walking down from the top and stopping at the stage's entry is what
## makes `moveToFront(the stage)` mean anything -- without it the keypress would
## still go to a window the script just put underneath.
static func front(owner) -> Node:
	restack(owner)
	for i in range(owner._window_order.size() - 1, -1, -1):
		var key := str(owner._window_order[i])
		if key == STAGE_KEY:
			return null
		var node: Node = owner._windows.get(key)
		if node != null and node._window_shown:
			return node
	return null


## The front-most open *modal* window, or null.
##
## A modal window blocks its parent. Input only -- the movie underneath keeps
## running, which is why this gates the click and key routing and not `_process`.
## Unverified: nothing in this corpus sets `the modal of window`.
##
## **Deliberately does not stop at the stage**, unlike `front` and `at`. Modality
## is a lock on input, not a fact about drawing, and there is no reference
## behaviour to copy for "a modal window that was sent behind the stage": D5's
## own documentation describes the modal flag as blocking the movie underneath
## with no reference to the stacking order. Answering the narrower question here
## would silently unblock a movie a script has locked, which is the direction
## that breaks a title rather than the direction that draws one wrongly.
static func modal(owner) -> Node:
	for i in range(owner._window_order.size() - 1, -1, -1):
		var key := str(owner._window_order[i])
		if key == STAGE_KEY:
			continue
		var node: Node = owner._windows.get(key)
		if node != null and node._window_shown and node._modal:
			return node
	return null


## The window a stage point lands in, front-most first, or null.
##
## Director hit-tests windows before sprites, and the front window takes the
## click whether or not anything in it answers. The whole frame counts, chrome
## included -- a click on a title bar belongs to the window it titles.
##
## Stops at the stage's entry for the same reason `front` does: a window the
## script put behind the stage is behind it for the mouse as well as for the eye,
## and a click that lands where it used to be belongs to the stage.
static func at(owner, point: Vector2) -> Node:
	restack(owner)
	for i in range(owner._window_order.size() - 1, -1, -1):
		var key := str(owner._window_order[i])
		if key == STAGE_KEY:
			return null
		var node: Node = owner._windows.get(key)
		if node == null or not node._window_shown:
			continue
		var frame: Rect2 = node.window_frame()
		if frame.has_point(point):
			return node
	return null

# ------------------------------------------------------- the vocabulary

## The window property vocabulary, write side.
##
## Everything is stored on the window it names rather than on whoever set it,
## which is the correction the whole Movie-In-A-Window change was about: before
## it, `set the windowType of window "joke.dxr" to 2` went to the *stage's*
## system properties.

static func write_prop(host, prop: String, value: Variant) -> void:
	match prop:
		"windowtype":
			host._window_type = LingoValue.to_int(value)
		"centerstage":
			host._center_stage = LingoValue.to_int(value) != 0
		"visible":
			if LingoValue.to_int(value) != 0:
				host.window_shown()
			else:
				host.window_hidden()
			return
		"modal":
			host._modal = LingoValue.to_int(value) != 0
		"title", "name":
			host._window_title = LingoValue.to_str(value)
		"titlevisible":
			host._title_visible = LingoValue.to_int(value) != 0
		"rect":
			host._window_rect = rect_of(value)
		"drawrect":
			host._draw_rect = rect_of(value)
		"filename":
			## Director lets one window play a succession of movies. Reached as a
			## `go to movie` inside the window rather than as a reload, so the
			## window keeps its identity, its rect and its place in the stacking
			## order — which is what the property means.
			host.lingo_go_movie(LingoValue.to_str(value), null)
		_:
			return
	host._apply_window_geometry()
	host.queue_redraw()


## The window property vocabulary, read side.
static func read_prop(host, prop: String) -> Variant:
	match prop:
		"windowtype":
			return host._window_type
		"centerstage":
			return 1 if host._center_stage else 0
		"visible":
			return 1 if host._window_shown else 0
		"modal":
			return 1 if host._modal else 0
		"title":
			return title_of(host)
		"name":
			return host._window_key
		"titlevisible":
			return 1 if host._title_visible else 0
		"rect":
			var frame: Rect2 = host.window_frame()
			return [int(frame.position.x), int(frame.position.y),
				int(frame.end.x), int(frame.end.y)]
		"drawrect":
			var drawn := Rect2(origin_of(host), size_of(host) * host.window_scale())
			return [int(drawn.position.x), int(drawn.position.y),
				int(drawn.end.x), int(drawn.end.y)]
		"sourcerect":
			## The movie's own authored rect, read-only. The one window property
			## that is not a placement decision but a fact about the file.
			# Typed explicitly: `:=` cannot infer through a ternary, and this file
			# does not compile at all without it.
			var source: Rect2i = host._config.rect if host._config != null \
				else Rect2i(Vector2i.ZERO, host.stage_size())
			return [int(source.position.x), int(source.position.y),
				int(source.end.x), int(source.end.y)]
		"moviename", "filename":
			return host.movie_name()
		"picture":
			## Deliberately unimplemented: it is the window's composited pixels,
			## and this renderer never holds a surface to read back (§6.3, gap
			## 16.25). Answering VOID rather than a wrong image.
			return null
	return 0


## How big the window is: what a script set, or the size the window's own movie
## declares.
##
## `stage_size()` is that second answer, and it is the *window's* stage size --
## a window runs a whole movie, so the same question one level down. It falls
## back to `STAGE` for a movie with no readable config, which is the only reason
## this is not simply the config rect.
static func size_of(host) -> Vector2:
	if host._window_rect != null:
		return (host._window_rect as Rect2).size
	return Vector2(host.stage_size())


static func origin_of(host) -> Vector2:
	if host._window_rect != null:
		return (host._window_rect as Rect2).position
	var mine: Vector2 = size_of(host)
	if host._center_stage:
		# Centred in the **stage's** rectangle, which is the stage movie's size and
		# not this window's. The two are the same in every title of this corpus,
		# because every movie in it declares 640x480 -- so a hardcoded constant here
		# was indistinguishable from the right answer until a movie of another size
		# was loaded, at which point a centred window is offset by half the
		# difference.
		return ((Vector2(host.stage_preview().stage_size()) - mine) * 0.5).floor()
	# The *stage's* rect, not this window's. Director puts a window at the rect
	# its movie was authored with -- a screen coordinate -- so it is taken
	# relative to the stage movie's own rect, the only other thing here in that
	# space. The two configs must stay distinct: reading one for both places
	# every window at the origin.
	var stage = host.stage_preview()
	if host._config != null and stage != null and stage._config != null:
		return Vector2(host._config.rect.position - stage._config.rect.position)
	return Vector2.ZERO


static func title_of(host) -> String:
	return host._window_title if host._window_title != "" else host._window_key
