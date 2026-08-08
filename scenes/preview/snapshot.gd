extends RefCounted
## "Here is what the player was looking at", copied to the clipboard.
##
## Every bug report against this port arrives as a sentence -- "clicking the
## thing on the beach does nothing" -- and the four facts that turn it into
## something reproducible are the ones nobody thinks to write down: which
## container is playing, which frame it is on, which game is configured, and what
## the last click actually resolved to. All four are already on screen or in the
## log; none of them survives being retyped.
##
## The click line is *captured*, not recomputed. `_click` already builds it --
## the channel from the hit test, the tier and the script from
## `interaction.gd:script_for_click`, and whether a `mouseUp` handler exists at
## all -- and recomputing it here would answer for the frame the snapshot was
## taken on rather than the frame that was clicked. Those differ constantly: the
## score keeps running, and the click that "did nothing" is usually several
## frames back by the time anybody reaches for a key.
##
## The distinction the click line exists to make is between "clicked nothing" and
## "clicked something with no `mouseUp`". They look identical on screen and are
## entirely different faults.

const DebugKeys := preload("res://scenes/preview/debug_keys.gd")

## Where the images go. Gitignored: they are screenshots of somebody's session,
## the tree already keeps `.traces/` for the same kind of local output, and a
## screenshot of a game we do not own is not ours to commit either.
const DIRECTORY := "res://.snapshots"


## The record `_click` hands over, and the one line it prints. Built here so the
## printed line and the copied line cannot drift: they are the same string.
static func note_click(at: Vector2, frame: int, channel: int, tier: String,
		script: Dictionary, has_handler: bool) -> Dictionary:
	return {
		"at": at,
		"frame": frame,
		"channel": channel,
		"tier": tier,
		"script": str(script.get("script", "none")),
		"handler": has_handler,
	}


static func click_line(click: Dictionary) -> String:
	if click.is_empty():
		return "no click yet this session"
	var at: Vector2 = click["at"]
	return "clicked (%d,%d) frame %d  ch%d  %s script %s  mouseUp:%s" % [
		int(at.x), int(at.y), int(click["frame"]), int(click["channel"]),
		str(click["tier"]), str(click["script"]),
		"yes" if bool(click["handler"]) else "NO HANDLER",
	]


## Take one: write the image, build the text, put it on the clipboard.
##
## Returns the text, which is also what the toast is built from. The image is
## whatever was last presented -- the caller is `_input`, which runs between
## frames, so this is the frame the player was looking at when they pressed the
## key rather than one drawn afterwards.
static func take(host) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var image_path := "%s/%s.png" % [DIRECTORY, stamp]
	var saved := _save_image(host, image_path)
	var lines := [
		"godot-director-player snapshot  %s" % stamp,
		"game      : %s" % _game_root(host),
		"container : %s" % _container(host),
		"frame     : %s" % _frame(host),
		"last click: %s" % click_line(host._last_click),
		"image     : %s" % (ProjectSettings.globalize_path(image_path) if saved
			else "not saved (see the log)"),
	]
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	print(text)
	return text


## The frame the player would quote, which is the one on the status line: the
## HUD counts from `_index` and so does this, or the number in the report and the
## number in the corner would disagree.
static func _frame(host) -> String:
	if host._score == null:
		return "no score"
	return "%d of %d" % [host._index, host._score.frame_count - 1]


static func _container(host) -> String:
	var name: String = host.movie_name()
	return name if name != "" else "none loaded"


## The configured game, not the directory the current movie happens to sit in. A
## report that says `DAY1.dir` without saying which title's DAY1 is a report
## against the wrong corpus half the time -- both games here ship one.
static func _game_root(host) -> String:
	if host._paths == null:
		return "unconfigured"
	return str(host._paths.root)


## What was last presented, as an Image, or null when nothing has been.
##
## Split out from `_save_image` because the save state needs the *picture* at one
## moment and the *filename* at another: `save_as` opens a dialog, and by the
## time a name has been typed the framebuffer holds a different frame. Grabbing
## and writing therefore have to be two calls. `preview/save_files.gd` is the
## other caller.
static func grab(host) -> Image:
	# Annotated rather than inferred: a call through `host` is untyped, so `:=`
	# has nothing to infer from. See `preview/README.md`.
	var viewport: Viewport = host.get_viewport()
	if viewport == null:
		return null
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		# Headless Godot never paints, so there is nothing to save and saying so
		# is better than writing a black rectangle that looks like a rendering
		# bug the next time somebody opens it.
		return null
	return image


static func _save_image(host, path: String) -> bool:
	var image: Image = grab(host)
	if image == null:
		push_warning("snapshot: nothing has been rendered to capture")
		return false
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIRECTORY)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	return image.save_png(path) == OK


## What the toast says. Short enough to read at a glance and specific enough to
## tell a snapshot that worked from one that found nothing to capture.
static func toast_text(host) -> String:
	return "copied: %s frame %s  (%s)" % [
		_container(host), _frame(host), DebugKeys.key_name("snapshot"),
	]
