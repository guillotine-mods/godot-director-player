extends RefCounted
## Editable fields: who has focus, where the caret is, and what a key does to it.
##
## §8.4 and §7.7. Title-agnostic -- nothing here knows what game is loaded.
##
## **Effective editability is `sprite editable OR member editable`, and in this
## corpus the sprite half is always false.** Not one of Piposh 2's 816,318 sprite
## records sets the score's editable bit, nor one of Piposh 1's 1,886,362, nor
## one of Rating's 847,431. Every editable field in all three titles is editable
## because its *member* says so (`director_cast.gd`, byte 25 bit 0) or because a
## script wrote `member("x").editable = 1`. A port that read only the score's
## half -- which is the half this repo already decoded -- would measure zero and
## conclude the feature is unexercised. It is not: `SAVELOAD.dir` is built on it.
##
## **Focus is claimed, not assigned.** §7.7: the *first* editable text sprite in
## channel order becomes the active widget **unless one already holds it**, and
## the holder keeps it across a frame change while its channel still shows the
## same cast member. That "unless" is the whole rule -- without it every frame
## would drag focus back to the lowest channel and the player could never type
## into the second box. `arbitrate` is the only place it is decided.
##
## **`the selStart` and `the selEnd` are movie-level, not per-field** (§8.4).
## One range, pushed into whichever widget currently has focus. That is why they
## live on the preview node beside `_focus_channel` rather than in a per-member
## dictionary, and it is also why setting `the selStart` before focusing a
## different field behaves oddly in real Director -- the oddity is the design.
##
## What is deliberately **not** here: auto-expanding boxes pushing their laid-out
## size back onto the sprite (§7.7's last sentence). That needs the dimension
## change to reach `sprite_geometry.gd`, and the current gate asserts the
## opposite -- `tools/text_and_shapes.gd` checks every field's box is the size the
## score gave the sprite. Closing it is a separate change with its own evidence.

const Ink := preload("res://director/director_ink.gd")
const Text := preload("res://director/director_text.gd")
const TextArt := preload("res://scenes/preview/text_art.gd")

## How long the caret spends visible, and then hidden. The Mac's own rate, which
## is what Director's widget used; there is no system setting here to ask.
const CARET_BLINK_MS := 530


## Is this sprite's field editable right now?
##
## Three sources, OR'd, and each one exists because something real sets it:
##
##   the score's own bit      `director_score.gd:EDITABLE_FLAG` -- 0 records here
##   the member's own bit     `director_cast.gd:TEXT_EDITABLE_FLAG` -- the corpus
##   a Lingo write            `member("save1").editable = 1` -- 5 sites, all in
##                            `SAVELOAD.dir`, choosing which save slot is typeable
##
## `editabletext` is read beside `editable` on the sprite because the two
## vocabularies have not been joined: Lingo's property is `the editableText of
## sprite N` and the score record's flag is `editable`, and the table that
## translates one to the other (`preview/sprite_props.gd:ALIASES`) carries only
## `moveableSprite` today. Reading both keys here is correct whether or not the
## alias is added later; adding it is still the right fix, because without it the
## *read* back of `the editableText of sprite N` cannot see the score's bit --
## exactly the half-a-property bug that file was written to prevent.
static func editable(host, sprite: Dictionary, member: Dictionary) -> bool:
	if member.is_empty() or int(member.get("type", 0)) != Ink.TYPE_FIELD:
		return false
	if bool(sprite.get("editable", false)) or bool(sprite.get("editabletext", false)):
		return true
	return member_editable(host, member)


## The member's half alone: its authored flag, or whatever Lingo last wrote.
##
## Keyed by `TextArt.key_for` -- the cast's *file* and the member number, never
## the library number -- for the same reason the text overrides are, and it
## matters more here than there: `SAVELOAD.dir` is opened as a window over a
## stage that has the same casts open under different library numbers, and an
## `editable` keyed by number would make the window and the stage disagree about
## which member was typeable.
static func member_editable(host, member: Dictionary) -> bool:
	var key: String = TextArt.key_for(
		int(member.get("cast_lib", 1)), int(member.get("cast_id", 0)), host._table)
	if host._member_editable.has(key):
		return bool(host._member_editable[key])
	return bool(member.get("editable", false))


## `member("x").editable = 1`. Re-arbitrates immediately, because this is how a
## movie moves focus: `SAVELOAD`'s slot buttons clear the flag on seven fields
## and set it on the eighth inside one `mouseUp`, and focus has to follow within
## the same handler or the player types into the box they just stopped choosing.
static func set_member_editable(host, member: Dictionary, on: bool) -> void:
	if member.is_empty():
		return
	var key: String = TextArt.key_for(
		int(member.get("cast_lib", 1)), int(member.get("cast_id", 0)), host._table)
	host._member_editable[key] = on
	arbitrate(host)
	host.queue_redraw()


## Drop the editability overrides belonging to one container's own cast, exactly
## as the text overrides are dropped and at the same call site. A movie that is
## left and re-entered must show its authored flags again.
static func forget(container_path: String, member_editable: Dictionary) -> void:
	if container_path == "":
		return
	var prefix := container_path.to_lower() + ":"
	for key in member_editable.keys():
		if str(key).begins_with(prefix):
			member_editable.erase(key)


## Every editable field sprite on the current frame, in ascending channel order.
##
## Ascending because §7.7 says the *first* editable sprite claims focus and
## Director means the lowest channel number, which is the back of the stacking
## order -- the opposite end from the hit test's descent.
static func editable_sprites(host) -> Array:
	var out: Array = []
	if host._score == null or host._table == null:
		return out
	for raw in host._score.frame(host._index).get("sprites", []):
		var sprite: Dictionary = host._effective(raw)
		if sprite.is_empty():
			continue
		var member: Dictionary = host._table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		if editable(host, sprite, member):
			out.append(sprite)
	out.sort_custom(func(a, b): return int(a["channel"]) < int(b["channel"]))
	return out


## Decide who holds focus, and answer the channel. 0 for "nobody".
##
## The holder keeps it while its channel is still an editable field showing the
## same cast member -- §7.7's "preserved across a frame when the cast id is
## unchanged". Otherwise the first editable sprite claims it. Cheap enough to
## call on every paint and every key, which is what §8.4's "pushed into the
## widget every frame" asks for and what makes a paused harness and a running
## player agree without a second code path.
static func arbitrate(host) -> int:
	var candidates: Array = editable_sprites(host)
	if candidates.is_empty():
		if host._focus_channel != 0:
			host._focus_channel = 0
			host._focus_member = 0
		return 0
	for sprite_value in candidates:
		var sprite: Dictionary = sprite_value
		if int(sprite["channel"]) == host._focus_channel \
				and int(sprite["cast_id"]) == host._focus_member:
			return host._focus_channel
	var first: Dictionary = candidates[0]
	focus_on(host, int(first["channel"]), int(first["cast_id"]))
	return host._focus_channel


## Give focus to a channel and put the caret at the end of what is already there.
##
## At the end rather than at 0 because a field arrives holding a value -- every
## one of `SAVELOAD`'s slots reads back `untitled` or a previous save's name --
## and a caret at the start means the first character typed lands in front of it.
static func focus_on(host, channel: int, member_number: int) -> void:
	host._focus_channel = channel
	host._focus_member = member_number
	var length := focused_text(host).length()
	host._sel_start = length
	host._sel_end = length
	host._caret_since = Time.get_ticks_msec()


## The sprite that holds focus, or `{}`.
static func focused_sprite(host) -> Dictionary:
	if host._focus_channel <= 0 or host._score == null:
		return {}
	for raw in host._score.frame(host._index).get("sprites", []):
		if int(raw["channel"]) != host._focus_channel:
			continue
		var sprite: Dictionary = host._effective(raw)
		return {} if sprite.is_empty() else sprite
	return {}


static func focused_member(host) -> Dictionary:
	var sprite: Dictionary = focused_sprite(host)
	if sprite.is_empty() or host._table == null:
		return {}
	return host._table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))


static func focused_text(host) -> String:
	var member: Dictionary = focused_member(host)
	return "" if member.is_empty() else str(host._field_text_of(member))


## `the selStart` / `the selEnd`, clamped to the focused field's length.
##
## Clamped on read rather than only on write because the text can shrink under a
## selection that was legal when it was made -- a script putting a shorter value
## into the field the player is typing in does exactly that -- and a selection
## past the end would delete characters that are not there.
static func selection(host) -> Array:
	var length := focused_text(host).length()
	var start: int = clampi(int(host._sel_start), 0, length)
	var end: int = clampi(int(host._sel_end), 0, length)
	return [mini(start, end), maxi(start, end)]


static func set_selection(host, start: int, end: int) -> void:
	host._sel_start = maxi(0, start)
	host._sel_end = maxi(0, end)
	host._caret_since = Time.get_ticks_msec()
	host.queue_redraw()


## Is the caret in its visible half of the blink right now?
##
## Restarted from the last edit, so the caret is solid at the moment a key lands
## instead of possibly blinking out on the character just typed.
static func caret_on(host) -> bool:
	return int((Time.get_ticks_msec() - int(host._caret_since)) / CARET_BLINK_MS) % 2 == 0


## What the painter needs to know about one channel, in one call.
static func paint_state(host, channel: int) -> Dictionary:
	if channel != host._focus_channel or channel <= 0:
		return {}
	var range_ := selection(host)
	return {
		"sel_start": int(range_[0]),
		"sel_end": int(range_[1]),
		"caret_on": caret_on(host),
	}


## A mouse-down inside an editable field: claim focus and put the caret where the
## player pointed.
##
## **Returns whether it hit one, and the caller does not stop there.** The widget
## layer sees a press before the sprite hit test does -- that is what makes
## clicking into a field work at all, since §4.3's eligibility says nothing about
## editability and a field with no script is not a click target. Consuming the
## press instead would break `SAVELOAD`: its slot buttons sit in the channels
## *above* the eight name boxes, and the `mouseUp` that chooses a slot has to
## reach them.
##
## Highest channel first, because two editable fields may overlap and the one in
## front is the one the player aimed at.
static func press(host, at: Vector2) -> bool:
	var candidates: Array = editable_sprites(host)
	for i in range(candidates.size() - 1, -1, -1):
		var sprite: Dictionary = candidates[i]
		var rect: Rect2 = host._stage_rect(sprite)
		if not rect.has_point(at):
			continue
		var member: Dictionary = host._table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		host._focus_channel = int(sprite["channel"])
		host._focus_member = int(sprite["cast_id"])
		var index: int = Text.index_at(
			rect, str(host._field_text_of(member)), Text.style_of(member), at)
		set_selection(host, index, index)
		return true
	return false


## A key aimed at the focused widget. True when the widget took it.
##
## Called **after** the movie has had the key, never instead of it: §8.3 routes
## `keyDown` to the sprite that owns the active widget, and Director's own rule
## is that a `keyDown` handler which does not `pass` suppresses the character. So
## the caller dispatches first and only reaches here when nothing claimed it.
## `director_preview.gd:_dispatch_key` holds that order and the caveat about what
## "claimed" currently means for a `keyDownScript`.
static func key(host, event: InputEventKey) -> bool:
	if host._focus_channel <= 0:
		return false
	var member: Dictionary = focused_member(host)
	if member.is_empty():
		return false
	var text: String = str(host._field_text_of(member))
	var range_ := selection(host)
	var start: int = int(range_[0])
	var end: int = int(range_[1])
	var shift: bool = event.shift_pressed
	# Modifier-only presses never reach here (§8.3), and a modified key is a
	# command rather than a character: control-C must not type a `c`.
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return false

	# The moving end of the selection, clamped -- `_sel_end` is what a shifted
	# arrow drags and what an unshifted one collapses onto.
	var caret: int = clampi(int(host._sel_end), 0, text.length())
	match event.keycode:
		KEY_LEFT:
			# An unshifted arrow against a *selection* collapses it to that edge
			# rather than stepping past it, which is what every text widget does
			# and what makes shift-select then left-arrow land where the player
			# expects.
			_move(host, start if start != end and not shift else maxi(0, caret - 1), shift)
			return true
		KEY_RIGHT:
			_move(host, end if start != end and not shift
				else mini(text.length(), caret + 1), shift)
			return true
		KEY_UP, KEY_HOME:
			_move(host, 0, shift)
			return true
		KEY_DOWN, KEY_END:
			_move(host, text.length(), shift)
			return true
		KEY_BACKSPACE:
			if start == end:
				if start == 0:
					return true
				start -= 1
			_replace(host, member, text, start, end, "")
			return true
		KEY_DELETE:
			if start == end:
				if end >= text.length():
					return true
				end += 1
			_replace(host, member, text, start, end, "")
			return true
		KEY_TAB:
			# §5.1's `the autoTab of member`, decoded from the same flag byte as
			# `editable`. With it off, Tab is swallowed rather than typed -- a tab
			# character in a field is not what the key means on this platform.
			if bool(member.get("auto_tab", false)):
				_tab(host)
			return true
		KEY_ESCAPE:
			# Not the widget's. Leave it for the movie and the preview.
			return false
		KEY_ENTER, KEY_KP_ENTER:
			_replace(host, member, text, start, end, "\n")
			return true
	var unicode := event.unicode
	if unicode >= 32 and unicode != 127:
		_replace(host, member, text, start, end, char(unicode))
		return true
	return false


## Move the caret, extending the selection when shift is held.
##
## `_sel_end` is the moving end and `_sel_start` the anchor, which is why an
## unshifted move collapses both: a selection has a direction and a caret does
## not.
static func _move(host, to: int, extend: bool) -> void:
	if extend:
		set_selection(host, int(host._sel_start), to)
	else:
		set_selection(host, to, to)


## Replace `[start, end)` with `insert`, and push the result back to the member.
##
## Through `lingo_set_field`, which is the same path a script's `put x into
## field "y"` takes -- so what the player types is readable by `field("save1")`
## and lands in the same override table, keyed by the cast's file. That is not a
## detail: `SAVELOAD`'s save button is `put field("save" & x, 1) into item x of
## SaveNames`, so if typing wrote anywhere else the slot would save the authored
## placeholder instead of the name.
static func _replace(host, member: Dictionary, text: String, start: int, end: int,
		insert: String) -> void:
	var name := str(member.get("name", ""))
	var updated: String = text.substr(0, start) + insert + text.substr(end)
	if name != "":
		host.lingo_set_field(name, "", updated)
	else:
		# A nameless field can still be typed into: write the override directly,
		# by the same key `lingo_set_field` would have used.
		host._field_text[host._field_key(
			int(member.get("cast_lib", 1)), int(member.get("cast_id", 0)))] = updated
		host.queue_redraw()
	var caret := start + insert.length()
	set_selection(host, caret, caret)


## Tab to the next editable field, wrapping. Unverified: no member in any corpus
## here sets the auto-tab bit, so this is written from the reference.
static func _tab(host) -> void:
	var candidates: Array = editable_sprites(host)
	if candidates.size() < 2:
		return
	for i in candidates.size():
		if int((candidates[i] as Dictionary)["channel"]) != host._focus_channel:
			continue
		var next: Dictionary = candidates[(i + 1) % candidates.size()]
		focus_on(host, int(next["channel"]), int(next["cast_id"]))
		host.queue_redraw()
		return
