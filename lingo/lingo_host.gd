class_name LingoHost
extends RefCounted
## Binds the Lingo interpreter to the live engine.
##
## Everything Director-specific lands here: sprite properties read and write
## `DirectorRuntime.channels`, the live channel array that the renderer and
## hit-testing also read, fields become a text table with `objectsfield` aliased onto
## `GameState` so saves keep working, and navigation and sound go straight to the
## existing runtime and `AudioDirector`.

const FIELDS_PATH := "res://data/lingo/fields.json"
const MEMBER_NAMES_PATH := "res://data/lingo/member_names.json"
## Field whose text is the inventory. Aliased rather than copied: GameState owns
## it, the Save Editor edits it, and to_dict/from_dict round-trip it.
const INVENTORY_FIELD := "objectsfield"
## Globals the port already owns. PuppetController is a native implementation of
## Director's walk state machine and carries these exact names, so the interpreter
## must read and write through to it or the two drift apart.
const PUPPET_GLOBALS := {
	"egozh": "egozh", "egozv": "egozv", "whatodo": "whatodo", "syz": "syz",
}
## Adventure state GameState owns. The original gates conditional content on it:
## DAY1 BehaviorScript 226 hides Gondolin's corpse and her handbag while
## `item 1 of meetings <> "done"`, and shows them once the murder has happened.
## Read as a plain interpreter global it is always empty, so that test never
## flips and the bag stays hidden forever, which means the scissors inside it can
## never be found.
const STATE_GLOBALS := {"meetings": true, "globalday": true}
## Handlers the port implements natively, which therefore win even over the
## original Lingo definition.
const NATIVE_HANDLERS := ["walkonby"]

# ---------------------------------------------------------------- property tables
#
# The bound surface, as tables rather than as the fall-through of a match, so a
# name the port does not answer is a lookup miss instead of a zero that looks
# like an answer. Names are lowercased, which is how the interpreter hands them
# over.
#
# The enumeration they are checked against is data/lingo_vocabulary.json,
# generated from ScummVM's kTheEntity tables at the pinned revision.
# tools/lingo_compile.py closes nothing — its SYSTEM_PROPS table is referenced
# by no code and parse_the gates only on RESERVED_AFTER_PROP, so any word parses
# as a property. An arbitrary identifier can therefore still reach dispatch,
# which is why binding everything cannot mean never raising: a name the
# vocabulary enumerates and the port refuses is a decision, a name it does not
# enumerate is a hole, and the two must stay apart.
#
# Read and write are separate tables. They used to be one surface by accident:
# set_sprite_prop wrote any key into `puppet` while get_sprite_prop fell through
# to 0, so every write was trivially bound and every unbound read lied.
#
# Every name below is in the vocabulary, so a reader can take the tables at face
# value: nothing here is a port invention. Four names that were bound are gone,
# and are recorded here so they are not defensively added back.
#
#   `stagewidth`, `stageheight` — read the stage size off the loader. Neither
#     exists in Director or in ScummVM; someone invented them. No script asks
#     for either and nothing in the port referenced them.
#   `castlib` — bound in get_sprite_prop's `"castlibnum", "castlib"` arm, which
#     is a category error twice over. Lingo's `castLib` is a cast qualifier, not
#     a sprite property: all 4600-odd corpus uses are `field "objectsfield" of
#     castLib "master"` or `member (…) of castLib 1`, which the compiler takes
#     as a reserved word and the interpreter resolves through _cast_of. The
#     sprite arm could never have fired.
#   `movablesprite` — a misspelling aliased onto `moveablesprite` in the same
#     arm. The corpus contains it zero times against 30 for Director's own
#     spelling, so nothing relied on the alias.
#
# WINDOW_FIELDS is the one table of real Director names that the movie
# vocabulary does not enumerate, because ScummVM keeps them on kTheWindow.

## Marks a reported name the vocabulary enumerates and the port deliberately
## does not bind, so a log tells a decision from a hole. Stripped by the
## coverage check.
const UNSUPPORTED_MARK := " (unsupported)"

## Answerable from score data or channel state. A value the script itself wrote
## reads back ahead of this table — see get_sprite_prop — so a write-only
## property is still readable by the handler that set it.
## `castlib` and `movablesprite` are aliases the host answers alongside the
## canonical spelling. Neither appears in the corpus — `castLib` is a cast
## qualifier there (`member N of castLib 1`), not a sprite property, and
## `movablesprite` is a misspelling of `moveableSprite` with zero uses. They stay
## because `_sprite_prop_value` matches them, and a gate that rejects a name the
## match arm below handles would report a diagnostic instead of doing the work.
const SPRITE_READS := {
	"bottom": true, "castlib": true, "castlibnum": true, "castnum": true,
	"constraint": true, "cursor": true, "height": true, "ink": true, "left": true,
	"loch": true, "locv": true, "member": true, "membernum": true,
	"movablesprite": true, "moveablesprite": true, "puppet": true, "right": true,
	"top": true, "visible": true, "width": true,
}
## left/top/right/bottom are absent on purpose: Director derives them from the
## location and the size, so writing one has to move the sprite, and the port's
## override table has no way to say that.
const SPRITE_WRITES := {
	"castlib": true, "castlibnum": true, "castnum": true, "constraint": true,
	"cursor": true, "height": true, "ink": true, "loch": true, "locv": true,
	"member": true, "membernum": true, "movablesprite": true, "moveablesprite": true,
	"puppet": true, "visible": true, "volume": true, "width": true,
}
## In the vocabulary, deliberately unbound. Every one of them is a Director
## drawing or media feature the port's renderer has no counterpart for —
## palettes, blends, trails, QuickTime tracks — and none is used by the corpus.
const SPRITE_UNSUPPORTED := {
	"backcolor": true, "blend": true, "currenttime": true, "editabletext": true, "fliph": true,
	"flipv": true, "forecolor": true, "immediate": true, "linesize": true, "loc": true,
	"mostrecentcuepoint": true, "movierate": true, "movietime": true, "name": true,
	"pattern": true, "rect": true, "scorecolor": true, "scriptinstancelist": true,
	"scriptnum": true, "settrackenabled": true, "starttime": true, "stoptime": true,
	"stretch": true, "trackenabled": true, "tracknextkeytime": true,
	"tracknextsampletime": true, "trackpreviouskeytime": true, "trackprevioussampletime": true,
	"tracktext": true, "trails": true, "tweened": true, "type": true, "visibility": true,
}

const MOVIE_READS := {
	"centerstage": true, "clickon": true, "commanddown": true, "controldown": true,
	"doubleclick": true, "exitlock": true, "frame": true, "freeblock": true, "key": true,
	"keycode": true, "keydownscript": true, "machinetype": true, "milliseconds": true,
	"mousedown": true, "mouseh": true, "mousev": true, "moviename": true, "moviepath": true,
	"optiondown": true, "searchpath": true, "shiftdown": true, "soundlevel": true,
	"ticks": true, "timer": true,
}
const MOVIE_WRITES := {
	"centerstage": true, "exitlock": true, "keydownscript": true, "searchpath": true,
	"soundlevel": true,
}
## Owned by the interpreter, which answers `the itemDelimiter` before the call
## reaches here. Listed so the coverage check counts it bound rather than as a
## gap the host could never close.
const MOVIE_BOUND_ELSEWHERE := {"itemdelimiter": true}
## Window trimmings. `tell window("map.dxr") / set the windowType to 2` runs its
## body on the one stage this port has, so these arrive here as plain movie
## properties. Accepted and dropped: there is nothing to place, title or resize.
## Kept apart from MOVIE_WRITES because ScummVM has them on kTheWindow, not on
## the movie, so the coverage check must not look for them in the movie
## vocabulary.
const WINDOW_FIELDS := {
	"drawrect": true, "rect": true, "titlevisible": true, "windowtype": true,
}
## In the vocabulary, deliberately unbound. Three groups: things about a
## desktop Director never had here (windows, menus, Xtras, the trace log),
## things about a machine that no longer exists (memory budgets, colour depth,
## the serial number), and score and selection state the port keeps in
## DirectorRuntime rather than exposing through Lingo.
const MOVIE_UNSUPPORTED := {
	"abbreviated": true, "activewindow": true, "actorlist": true, "alerthook": true,
	"applicationpath": true, "beepon": true, "buttonstyle": true, "castlibs": true,
	"castmembers": true, "checkboxaccess": true, "checkboxtype": true, "clickloc": true,
	"colordepth": true, "colorqd": true, "cpuhogticks": true, "currentspritenum": true,
	"cursor": true, "date": true, "desktoprectlist": true, "digitalvideotimescale": true,
	"emulatemultibuttonmouse": true, "environment": true, "fixstagesize": true,
	"floatprecision": true, "framelabel": true, "framepalette": true, "framescript": true,
	"framesound1": true, "framesound2": true, "frametempo": true, "frametransition": true,
	"freebytes": true, "frontwindow": true, "fullcolorpermit": true, "idlehandlerperiod": true,
	"idleloadmode": true, "idleloadperiod": true, "idleloadtag": true,
	"idlereadchunksize": true, "imagedirect": true, "keypressed": true,
	"keyupscript": true, "labellist": true, "lastclick": true, "lastevent": true,
	"lastframe": true, "lastkey": true, "lastroll": true, "long": true, "maxinteger": true,
	"memorysize": true, "menuitems": true, "mousecast": true, "mousechar": true,
	"mousedownscript": true, "mouseitem": true, "mouseline": true, "mousemember": true,
	"mouseup": true, "mouseupscript": true, "mouseword": true, "movie": true,
	"moviefilefreesize": true, "moviefilesize": true, "movierate": true, "multisound": true,
	"netthrottleticks": true, "number": true, "objectlist": true, "organizationname": true,
	"palettemapping": true, "paramcount": true, "pathname": true, "pausestate": true,
	"perframehook": true, "pi": true, "platform": true, "preloadeventabort": true,
	"preloadram": true, "productname": true, "productversion": true, "puppet": true,
	"quicktimepresent": true, "randomseed": true, "result": true, "rightmousedown": true,
	"rightmouseup": true, "rollover": true, "romanlingo": true, "runmode": true,
	"safeplayer": true, "score": true, "scoreselection": true, "scummvmversion": true,
	"searchcurrentfolder": true, "searchpaths": true, "selection": true, "selend": true,
	"selstart": true, "serialnumber": true, "short": true, "sounddevice": true,
	"soundenabled": true, "soundkeepdevice": true, "stage": true, "stagebottom": true,
	"stagecolor": true, "stageleft": true, "stageright": true, "stagetop": true,
	"stilldown": true, "switchcolordepth": true, "time": true, "timeoutkeydown": true,
	"timeoutlapsed": true, "timeoutlength": true, "timeoutmouse": true, "timeoutplay": true,
	"timeoutscript": true, "trace": true, "traceload": true, "tracelogfile": true,
	"tracescript": true, "updatelock": true, "updatemovieenabled": true, "username": true,
	"videoforwindowspresent": true, "visible": true, "volume": true, "windowlist": true,
	"xtras": true,
}

const MEMBER_READS := {"membernum": true, "name": true, "number": true, "text": true}
const MEMBER_WRITES := {"editable": true, "text": true}
## In the vocabulary, deliberately unbound. The port's cast is a bitmap and a
## text dump, not a live Director cast: type, font, palette, registration point
## and media state have no store behind them to read or change.
const MEMBER_UNSUPPORTED := {
	"alignment": true, "antialias": true, "autotab": true, "backcolor": true, "border": true,
	"boxdropshadow": true, "boxtype": true, "buttontype": true, "castlibnum": true,
	"casttype": true, "center": true, "changearea": true, "channelcount": true,
	"chunksize": true, "controller": true, "crop": true, "cuepointnames": true,
	"cuepointtimes": true, "depth": true, "digitalvideotype": true, "directtostage": true,
	"dropshadow": true, "duration": true, "filename": true, "filled": true, "font": true,
	"fontsize": true, "fontstyle": true, "forecolor": true, "framerate": true, "height": true,
	"hilite": true, "interface": true, "linecount": true, "lineheight": true, "linesize": true,
	"loaded": true, "loop": true, "margin": true, "media": true, "mediabusy": true,
	"mediaready": true, "modified": true, "pageheight": true, "palette": true,
	"paletteref": true, "pattern": true, "pausedatstart": true, "picture": true,
	"preload": true, "purgepriority": true, "rect": true, "regpoint": true, "samplerate": true,
	"samplesize": true, "scale": true, "scriptsenabled": true, "scripttext": true,
	"scripttype": true, "scrolltop": true, "shapetype": true, "size": true, "sound": true,
	"spritenum": true, "textalign": true, "textfont": true, "textheight": true,
	"textsize": true, "textstyle": true, "timescale": true, "transitiontype": true,
	"type": true, "video": true, "width": true, "wordwrap": true,
}

var runtime: Object = null
## Set by LingoEngine. The native handlers read globals through it.
var interpreter: Object = null
## Null unless PIPOSH2_TRACE asked for property records. Null rather than a bool
## so a hook is one compare and an off trace allocates nothing — see
## lingo/lingo_trace.gd.
var trace: LingoTrace = null

## cast (lower) -> field name (lower) -> text
var fields: Dictionary = {}
## cast (lower) -> member number (int) -> name (lower)
var member_names: Dictionary = {}
var _member_numbers: Dictionary = {}
## The channel that received the current mouse event, for `the clickOn`.
var click_on: int = 0
var mouse_stage: Vector2 = Vector2.ZERO
## Director's `the keyCode`, valid only while a key handler is running.
var key_code: int = 0
## Handler name from `set the keyDownScript to ...`, run on every keypress.
var key_down_script: String = ""
## `the searchPath`, a list. One empty element rather than none, because every
## read is `getAt(the searchPath, 1)` and an empty list would answer 0.
var search_path: Array = [""]
## `the soundLevel`, 0-7. 7 is Director's default and the level the game starts
## every movie at.
var sound_level: int = 7
## `the exitLock` and `the centerStage`: written by the scripts, kept only so a
## read agrees with the write.
var exit_lock: int = 0
var center_stage: int = 1
## Builtins that were called but are not implemented, counted once each so a
## missing binding is visible without spamming the log.
var unhandled: Dictionary = {}
var stage_dirty: bool = false
## Set when a script opened a window, so the runtime can tell a real navigation
## from a click that merely did nothing.
var acted_on_window: bool = false
## When true, navigation and sound are captured instead of performed, so a script
## can be compared against the exported on_click without touching the game.
## Set when a script navigated during the current dispatch, so the runtime knows
## not to also apply the exported nav for this frame.
var navigated: bool = false
## `go to the frame` / `go(marker(0))`: Director's idle hold. Distinguished from a
## real navigation so the runtime holds instead of re-entering the frame, which
## would restart its sounds and delay timer every step.
var held: bool = false
var record: bool = false
var recorded_navs: PackedStringArray = PackedStringArray()
var recorded_sounds: PackedStringArray = PackedStringArray()


func _init(director_runtime: Object = null) -> void:
	runtime = director_runtime
	_load_tables()


func _load_tables() -> void:
	fields = _load_lowered(FIELDS_PATH)
	var raw_names: Dictionary = _load_json(MEMBER_NAMES_PATH)
	for cast in raw_names.keys():
		var per_cast: Dictionary = raw_names[cast]
		var by_number: Dictionary = {}
		var by_name: Dictionary = {}
		for number in per_cast.keys():
			var name := str(per_cast[number]).to_lower()
			by_number[int(number)] = name
			if not by_name.has(name):
				by_name[name] = int(number)
		member_names[str(cast).to_lower()] = by_number
		_member_numbers[str(cast).to_lower()] = by_name


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_lowered(path: String) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = _load_json(path)
	for cast in raw.keys():
		var per_cast: Dictionary = raw[cast]
		var lowered: Dictionary = {}
		for name in per_cast.keys():
			lowered[str(name).to_lower()] = str(per_cast[name])
		out[str(cast).to_lower()] = lowered
	return out


# ---------------------------------------------------------------- fields


func _default_cast() -> String:
	## Unqualified `field "x"` means the movie's own cast first, then master,
	## which is where the shared game state lives.
	return "master"


func get_field(name: String, cast: String) -> String:
	var key := name.to_lower()
	if key == INVENTORY_FIELD:
		return "\n".join(Array(GameState.objects_field))
	for candidate in _cast_search_order(cast):
		var per_cast: Variant = fields.get(candidate, {})
		if typeof(per_cast) == TYPE_DICTIONARY and (per_cast as Dictionary).has(key):
			return str((per_cast as Dictionary)[key])
	return ""


func set_field(name: String, cast: String, text: String) -> void:
	var key := name.to_lower()
	if key == INVENTORY_FIELD:
		var lines := LingoValue.split_lines(text)
		# Keep the field's declared length: the scripts index up to line 30 and
		# GameState, the Save Editor and the HUD all assume a fixed size.
		var wanted: int = GameState.objects_field.size()
		var next := PackedStringArray()
		next.resize(wanted)
		for i in wanted:
			var value := str(lines[i]) if i < lines.size() else ""
			next[i] = value if value.strip_edges() != "" else "empty"
		GameState.objects_field = next
		GameState.state_changed.emit()
		return
	for candidate in _cast_search_order(cast):
		var per_cast: Variant = fields.get(candidate, {})
		if typeof(per_cast) == TYPE_DICTIONARY and (per_cast as Dictionary).has(key):
			(per_cast as Dictionary)[key] = text
			return
	# A field the dump did not carry still has to hold what a script writes.
	var owner := _cast_search_order(cast)[0]
	if not fields.has(owner):
		fields[owner] = {}
	(fields[owner] as Dictionary)[key] = text


func _cast_search_order(cast: String) -> PackedStringArray:
	var order := PackedStringArray()
	if cast.strip_edges() != "":
		order.append(cast.to_lower())
	if runtime != null and runtime.get("loader") != null:
		var movie := str(runtime.loader.movie_name).to_lower()
		if movie != "" and order.find(movie) < 0:
			order.append(movie)
	if order.find(_default_cast()) < 0:
		order.append(_default_cast())
	return order


# ---------------------------------------------------------------- sprites


func _channel_sprite(channel: int) -> Dictionary:
	## What the channel holds now: the score's sprite with Lingo's writes applied.
	## Reading the score frame here is what made every write invisible.
	if runtime == null:
		return {}
	return runtime.effective_sprite(channel)


func get_sprite_prop(channel: int, prop: String) -> Variant:
	## The trace wraps the read rather than sitting inside it: the value is only
	## known at the return, and the arms below carry the reasoning for what each
	## property answers, which is not worth restructuring for a hook.
	if trace == null:
		return _sprite_prop_value(channel, prop)
	var value: Variant = _sprite_prop_value(channel, prop)
	trace.property("sprite", channel, prop.to_lower(), "read", value, interpreter)
	return value


func _sprite_prop_value(channel: int, prop: String) -> Variant:
	var key := prop.to_lower()
	if not SPRITE_READS.has(key):
		return _unbound_read(LingoDiagnostics.SPRITE_PROP, key, SPRITE_UNSUPPORTED)
	# The override-table read this used to do is gone with the table itself: the
	# channel now holds what the script wrote, so there is one place to read from.
	var sprite := _channel_sprite(channel)
	var entry: SpriteChannel = null
	if runtime != null:
		entry = runtime.channel_for(channel)
	match key:
		"membernum":
			# Per cast library, and paired with `the castLibNum`. `whatodoeveryframe`
			# reads it back through `member(the memberNum of sprite 30).name`, which
			# works because sprite 30 is cast library 1 and there the two numberings
			# coincide — so this must stay unpacked.
			return int(sprite.get("cast_id", 0))
		"castnum", "member":
			# Library-spanning, because that is what one-argument `member()` expects.
			return _pack_member(int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)))
		"castlibnum", "castlib":
			return int(sprite.get("cast_lib", 1))
		"loch":
			return int(sprite.get("loc_h", sprite.get("x", 0)))
		"locv":
			return int(sprite.get("loc_v", sprite.get("y", 0)))
		"width":
			return int(sprite.get("width", 0))
		"height":
			return int(sprite.get("height", 0))
		"ink":
			return int(sprite.get("ink", 0))
		"visible":
			if sprite.is_empty():
				return 0
			return 0 if runtime != null and runtime.is_channel_hidden(channel) else 1
		"puppet":
			return 1 if entry != null and entry.puppet else 0
		"left":
			return int(sprite.get("x", 0))
		"top":
			return int(sprite.get("y", 0))
		"right":
			return int(sprite.get("x", 0)) + int(sprite.get("width", 0))
		"bottom":
			return int(sprite.get("y", 0)) + int(sprite.get("height", 0))
		"movablesprite", "moveablesprite":
			return 1 if entry != null and entry.moveable else 0
		"constraint":
			return 0 if entry == null else entry.constraint
		"cursor":
			return 0 if entry == null else entry.cursor
		_:
			## Unreachable: SPRITE_READS gates entry.
			return 0


func set_sprite_prop(channel: int, prop: String, value: Variant) -> void:
	var key := prop.to_lower()
	if trace != null:
		trace.property("sprite", channel, key, "write", value, interpreter)
	if not SPRITE_WRITES.has(key):
		_unbound_write(LingoDiagnostics.SPRITE_PROP, key, SPRITE_UNSUPPORTED)
		return
	if runtime == null:
		return
	var entry: SpriteChannel = runtime.channel_for(channel)
	match key:
		"membernum", "castnum", "member":
			# Director resizes the sprite to the new member and re-anchors it on that
			# member's registration point. `whatodoeveryframe` depends on it: the walk
			# cycle members are not all the same size, and without the re-anchor
			# Piposh jitters as he walks.
			#
			# A written reference may carry its own library, in which case it moves the
			# sprite to that cast rather than keeping the one it had. Nothing in the
			# corpus writes `the castNum` today; this is here so the property round
			# trips rather than silently losing half of what it was handed.
			var cast_lib := int(entry.sprite.get("cast_lib", 1))
			var member := LingoValue.to_int(value)
			var packed := _unpack_member(value)
			if not packed.is_empty():
				cast_lib = int(packed.cast_lib)
				member = int(packed.member)
			entry.set_member(cast_lib, member, runtime.loader.get_member(cast_lib, member))
			stage_dirty = true
			return
		"castlibnum", "castlib":
			entry.sprite["cast_lib"] = LingoValue.to_int(value)
			stage_dirty = true
			return
		"loch":
			entry.set_loc(float(LingoValue.to_num(value)), entry.loc().y)
			stage_dirty = true
			return
		"locv":
			entry.set_loc(entry.loc().x, float(LingoValue.to_num(value)))
			stage_dirty = true
			return
		"width":
			entry.set_size(LingoValue.to_num(value), null)
			stage_dirty = true
			return
		"height":
			entry.set_size(null, LingoValue.to_num(value))
			stage_dirty = true
			return
		"ink":
			entry.sprite["ink"] = LingoValue.to_int(value)
			stage_dirty = true
			return
		"movablesprite", "moveablesprite":
			entry.moveable = LingoValue.truthy(value)
			return
		"constraint":
			entry.constraint = LingoValue.to_int(value)
			return
		"cursor":
			# `[the number of member "hand1", the number of member "hand2"]` on the
			# inventory slots. Recorded; the port stands in a system cursor because
			# the cast pair does not decode to a 1-bit 16x16 Director cursor.
			entry.cursor = value
			return
	if key == "visible" and runtime != null:
		# Visibility is the one property the existing renderer already gates, so
		# keep the two in step rather than introducing a second mechanism.
		#
		# Every write is honoured, in both directions. Visibility is game state
		# here, not decoration: the room's frame handler decides it from the
		# inventory on each step. DAY1 BehaviorScript 245 and 286 scan
		# `objectsfield` for "masor" and set sprite 17 hidden when the player has
		# it and visible when they do not, and MASTER BehaviorScript 111 reads
		# `sprite(15).visible` back to decide whether a drop can land.
		#
		# Filtering these writes was the wrong instinct twice over: suppressing
		# them made every collectable permanent, and honouring only puppeted ones
		# stopped picked-up items clearing. The blanking an entry script does is
		# undone by the conditional handler on the next entry frame, so both have
		# to run — see DirectorRuntime._run_skipped_entry_scripts.
		runtime.set_channel_visible(channel, LingoValue.truthy(value))
	stage_dirty = true


func sprite_rect(channel: int) -> Rect2:
	## `intersects`, `within` and `rollOver` measure where the sprite is *now*. The
	## channel already carries the script's writes, so there is no override pass to
	## apply on top and no assumption that the registration point is the centre.
	if runtime == null:
		return Rect2()
	var sprite := _channel_sprite(channel)
	if sprite.is_empty():
		return Rect2()
	return runtime.sprite_stage_rect(sprite)


# ---------------------------------------------------------------- members


## Multiplier that carries a cast library alongside a member number in the single
## integer `the castNum` evaluates to. A movie links at most a handful of casts and
## the largest here has 1349 members, so nothing real can reach this.
##
## Director packs the pair too, because from D5 a movie can link several casts and a
## sprite records its member as (castLib, memberNum); `the castNum` collapses that
## into one integer and one-argument `member()` expands it again. This is *not* a
## claim to reproduce Director's own packing: the export carries no per-library slot
## offsets, so that encoding cannot be recovered from anything here. It does not have
## to be. All 18 `castNum` sites in the corpus are the same line —
## `nof = member(the castNum of sprite 1).name` — so the integer is produced and
## consumed inside one expression by this file, and never stored, compared or
## arithmetic'd. Only the round trip has to hold.
const CAST_MULTIPLEX := 0x20000


func _pack_member(cast_lib: int, member: int) -> int:
	return maxi(cast_lib, 1) * CAST_MULTIPLEX + member


func _unpack_member(which: Variant) -> Dictionary:
	## {} when this is a plain member number rather than a packed reference.
	if typeof(which) == TYPE_STRING:
		return {}
	var value := LingoValue.to_int(which)
	if value < CAST_MULTIPLEX:
		return {}
	return {"cast_lib": value / CAST_MULTIPLEX, "member": value % CAST_MULTIPLEX}


func _cast_name_for_lib(cast_lib: int) -> String:
	if runtime == null or runtime.get("loader") == null:
		return ""
	var entry: Variant = runtime.loader.cast_libs.get(str(cast_lib), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var name := str((entry as Dictionary).get("name", "")).strip_edges().to_lower()
	# Cast library 1 is the movie's own, which member_names keys by movie name.
	return _default_cast() if name == "" or name == "internal" else name


func member_number(which: Variant, cast: String) -> int:
	## `the number of member "sciser"` and `member(30, "master")` both land here.
	if typeof(which) != TYPE_STRING:
		var packed := _unpack_member(which)
		return int(packed.member) if not packed.is_empty() else LingoValue.to_int(which)
	var wanted := (which as String).to_lower()
	for candidate in _cast_search_order(cast):
		var by_name: Variant = _member_numbers.get(candidate, {})
		if typeof(by_name) == TYPE_DICTIONARY and (by_name as Dictionary).has(wanted):
			return int((by_name as Dictionary)[wanted])
	return 0


func get_member_prop(which: Variant, cast: String, prop: String) -> Variant:
	if trace == null:
		return _member_prop_value(which, cast, prop)
	var value: Variant = _member_prop_value(which, cast, prop)
	trace.property("member", _member_id(which, cast), prop.to_lower(), "read", value, interpreter)
	return value


func _member_prop_value(which: Variant, cast: String, prop: String) -> Variant:
	var key := prop.to_lower()
	if not MEMBER_READS.has(key):
		return _unbound_read(LingoDiagnostics.MEMBER_PROP, key, MEMBER_UNSUPPORTED)
	if key == "name":
		if typeof(which) == TYPE_STRING:
			return which
		var number := LingoValue.to_int(which)
		# A reference that carries its own library resolves there and nowhere else.
		# `nof = member(the castNum of sprite 1).name` is the room's background, and
		# in DAY1 that sprite is island:10 while DAY1's own member 10 is the cursor
		# `wlkcur1`. Searching the movie's cast first answered every room with a
		# cursor name, and left 7 of 32 rooms sharing the empty string, which is what
		# made `shellfield` and `jokefield` mark rooms collected that were not.
		var packed := _unpack_member(which)
		if not packed.is_empty():
			number = int(packed.member)
			var owner := _cast_name_for_lib(int(packed.cast_lib))
			var owned: Variant = member_names.get(owner, {})
			if typeof(owned) == TYPE_DICTIONARY and (owned as Dictionary).has(number):
				return str((owned as Dictionary)[number])
			return ""
		for candidate in _cast_search_order(cast):
			var by_number: Variant = member_names.get(candidate, {})
			if typeof(by_number) == TYPE_DICTIONARY and (by_number as Dictionary).has(number):
				return str((by_number as Dictionary)[number])
		return ""
	if key == "number" or key == "membernum":
		## `the memberNum of member x` is the same question as `the number of
		## member x`. Read 85 times by the corpus and answered with 0 until now,
		## because only `number` had an arm.
		return member_number(which, cast)
	if key == "text":
		return get_field(LingoValue.to_str(which), cast)
	## Unreachable: MEMBER_READS gates entry.
	return 0


func _member_id(which: Variant, cast: String) -> String:
	## `member "sciser" of castLib "master"` and `member(30, "master")` name the
	## same thing two ways, so the trace records the cast alongside whichever
	## spelling the script used and leaves resolving them to the diff. "<cast>:<which>",
	## and an empty cast is an unqualified reference, not a missing one — the
	## search order that resolves it is _cast_search_order's, not the record's.
	return "%s:%s" % [cast.to_lower(), LingoValue.to_str(which).to_lower()]


func set_member_prop(which: Variant, cast: String, prop: String, value: Variant) -> void:
	var key := prop.to_lower()
	if trace != null:
		trace.property("member", _member_id(which, cast), key, "write", value, interpreter)
	if not MEMBER_WRITES.has(key):
		_unbound_write(LingoDiagnostics.MEMBER_PROP, key, MEMBER_UNSUPPORTED)
		return
	if key == "text":
		set_field(LingoValue.to_str(which), cast, LingoValue.to_str(value))
		return
	## `editable`: written 5 times to let the player type into a field. The port
	## has no in-game text entry, so the write is accepted and dropped rather
	## than reported — the scripts are not asking for anything the port owes.


# ---------------------------------------------------------------- system


func get_system_prop(prop: String) -> Variant:
	if trace == null:
		return _system_prop_value(prop)
	var value: Variant = _system_prop_value(prop)
	trace.property("movie", _movie_id(), prop.to_lower(), "read", value, interpreter)
	return value


func _movie_id() -> String:
	## A movie property hangs off the movie, so the target is the movie itself.
	return str(runtime.loader.movie_name).to_lower() if runtime != null else ""


func _system_prop_value(prop: String) -> Variant:
	var key := prop.to_lower()
	if not MOVIE_READS.has(key):
		if WINDOW_FIELDS.has(key):
			## A window field read back inside a `tell window(...)` body. Nothing
			## reads one in this corpus, and there is no window to ask.
			return 0
		return _unbound_read(LingoDiagnostics.MOVIE_PROP, key, MOVIE_UNSUPPORTED)
	match key:
		"clickon":
			return click_on
		"moviename":
			if runtime == null:
				return ""
			return "%s.dxr" % str(runtime.loader.movie_name).to_lower()
		"machinetype":
			# 256 is Windows, which is what the shipped game ran on. The scripts
			# only use it to choose a path separator.
			return 256
		"mouseh":
			return int(mouse_stage.x)
		"mousev":
			return int(mouse_stage.y)
		"frame":
			return (runtime.frame_index + 1) if runtime else 0
		"timer", "ticks":
			return int(Time.get_ticks_msec() / 16.667)
		"milliseconds":
			return Time.get_ticks_msec()
		"keycode", "key":
			return key_code
		"shiftdown", "optiondown", "commanddown", "controldown", "doubleclick":
			## Modifiers and double-click, which the port's input path does not
			## carry into a dispatch. 0 is Director's "not held", and no script
			## in the corpus asks.
			return 0
		"searchpath":
			## Director's folder list for external media. Read 52 times, always
			## as `getAt(the searchPath, 1)` concatenated into a file name, so it
			## has to be a list with a readable first element. Divergence: the
			## element stays empty because AudioDirector resolves by stem across
			## every audio root, so a path never finds anything here — and until
			## now this answered 0, which made those names "0voice5.aif".
			return search_path
		"moviepath":
			## The folder the movie was loaded from, prefixed onto save paths and
			## onto `go(1, the moviePath & "day1.dxr")`. Divergence: empty,
			## because movies here are resolved by stem and _go strips any
			## prefix before it looks one up.
			return ""
		"soundlevel":
			return sound_level
		"mousedown":
			## `if the mouseDown then`, in four handlers polling for a click that
			## is still held.
			return 1 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
		"exitlock":
			return exit_lock
		"freeblock":
			## Largest free memory block, in bytes. GOLDDEAD BehaviorScript 23
			## unloads DAY1 below 100K and DAY1 wonder/BehaviorScript 310 refuses
			## to open the map below 12K. Both guards protect a 1997 Mac's heap;
			## answering "plenty" takes the branch the player wants in each.
			return 16 * 1024 * 1024
		"keydownscript":
			return key_down_script
		"centerstage":
			return center_stage
		_:
			## Unreachable: MOVIE_READS gates entry.
			return 0


func set_system_prop(prop: String, value: Variant) -> void:
	var key := prop.to_lower()
	if trace != null:
		trace.property("movie", _movie_id(), key, "write", value, interpreter)
	if WINDOW_FIELDS.has(key):
		## One stage here, so nothing to place, title or resize.
		return
	if not MOVIE_WRITES.has(key):
		unhandled["the %s (write)" % key] = true
		_unbound_write(LingoDiagnostics.MOVIE_PROP, key, MOVIE_UNSUPPORTED)
		return
	match key:
		"centerstage":
			## Written 20 times, always inside `tell window(...)`. Stored so a
			## read agrees with the write; there is nothing to centre.
			center_stage = LingoValue.to_int(value)
		"keydownscript":
			## The game's only use of key input. `on startMovie` sets this to
			## "fromnow", which stops sound channel 1 when a key is pressed, so
			## a keypress cuts the line of speech that is playing.
			key_down_script = LingoValue.to_str(value).strip_edges()
		"searchpath":
			## `the searchPath = ["z:\sounds\strtgame\"]` — always a one-element
			## list of a CD path.
			search_path = (value as Array) if typeof(value) == TYPE_ARRAY else [
				LingoValue.to_str(value)]
		"soundlevel":
			## SAVELOAD BehaviorScript 69-75 are the volume slider: each button
			## sets a level and plays a sample voice. Nothing else in the port
			## owns bus volume, so this drives the master bus directly.
			sound_level = clampi(LingoValue.to_int(value), 0, 7)
			AudioServer.set_bus_volume_db(0,
				-80.0 if sound_level == 0 else linear_to_db(float(sound_level) / 7.0))
		"exitlock":
			## `set the exitLock to 1`, twice, to stop Director quitting on a
			## keystroke. Nothing to lock here; stored so a read agrees.
			exit_lock = LingoValue.to_int(value)


func _report(category: String, name: String) -> void:
	## The interpreter owns the sink and knows which script and handler is
	## running; the host only knows the name.
	if interpreter != null:
		interpreter.report(category, name)


func _unbound_read(category: String, key: String, unsupported: Dictionary) -> Variant:
	## VOID, not 0. A default is the failure this surface exists to delete: the
	## old fall-through made `the freeBlock` answer 0 and every memory guard in
	## the game take the low-memory branch, silently, for years. VOID is the same
	## answer the interpreter already gives an unknown identifier, so it flows
	## through comparison and concatenation the way the rest of the port expects.
	_report(category, _reported_name(key, unsupported))
	return null


func _unbound_write(category: String, key: String, unsupported: Dictionary) -> void:
	_report(category, _reported_name(key, unsupported))


func _reported_name(key: String, unsupported: Dictionary) -> String:
	return (key + UNSUPPORTED_MARK) if unsupported.has(key) else key


# ---------------------------------------------------------------- builtins


func call_builtin(name: String, args: Array) -> Variant:
	match name.to_lower():
		"go", "goto":
			return _go(args)
		"play":
			# `play frame "x"` is a subroutine jump in Director. The port has no
			# play stack, so treat it as a plain go, which is how every use in
			# this game behaves.
			return _go(args)
		"walkonby":
			return _walkonby()
		"puppetsprite":
			if args.size() >= 1 and runtime != null:
				var entry: SpriteChannel = runtime.channel_for(LingoValue.to_int(args[0]))
				if args.size() >= 2 and not LingoValue.truthy(args[1]):
					entry.release_puppet()
				else:
					entry.puppet = true
			stage_dirty = true
			return 0
		"updatestage":
			stage_dirty = true
			return 0
		"sound":
			return _sound(args)
		"soundbusy":
			return 1 if AudioDirector.sound_busy(LingoValue.to_int(args[0] if args.size() > 0 else 1)) else 0
		"random":
			var top := LingoValue.to_int(args[0] if args.size() > 0 else 1)
			return randi_range(1, maxi(1, top))
		"marker":
			return _marker(args)
		"label":
			if runtime == null or args.is_empty():
				return 0
			# `label(0)` is not a lookup of a marker named "0": with a number it
			# means the current marker, the same as `marker(0)`. The rooms record
			# themselves with `whereami = label(0)` and every hotspot compares
			# that against `label("<room>")`, so both spellings must agree.
			if typeof(args[0]) != TYPE_STRING:
				return _marker(args)
			var index: int = int(runtime.loader.lookup_label(LingoValue.to_str(args[0])))
			return index + 1 if index >= 0 else 0
		"rollover":
			if runtime == null or args.is_empty():
				return 0
			return 1 if sprite_rect(LingoValue.to_int(args[0])).has_point(mouse_stage) else 0
		"intersects":
			if args.size() < 2:
				return 0
			var a := sprite_rect(LingoValue.to_int(args[0]))
			var b := sprite_rect(LingoValue.to_int(args[1]))
			if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
				return 0
			return 1 if a.intersects(b) else 0
		"within":
			if args.size() < 2:
				return 0
			return 1 if sprite_rect(LingoValue.to_int(args[1])).encloses(
				sprite_rect(LingoValue.to_int(args[0]))) else 0
		"window":
			## A Movie In A Window, reduced to the movie it names. Director shows
			## it floating over the stage; this port has one stage, so it becomes
			## an overlay on the route stack and `forget` returns the way SAVELOAD
			## already does. The handle is just the stem, which is all `open` and
			## `forget` need.
			if args.is_empty():
				return ""
			return LingoValue.to_str(args[0]).strip_edges().get_file().get_basename()
		"open":
			## `open(window("joke.dxr"))` is how the joke bottle shows its joke.
			if runtime == null or args.is_empty():
				return 0
			var stem := LingoValue.to_str(args[0]).strip_edges().get_file().get_basename()
			if stem == "":
				return 0
			acted_on_window = true
			# Opening a window is a navigation, so `record` has to capture it like
			# any other. Without this the convergence sweep wandered out of DAY1
			# into SAVELOAD on the first save button it dispatched, and
			# _run_skipped_entry_scripts — which replays under record precisely so
			# a `go` cannot hijack the arrival — could be hijacked by an `open`.
			if record:
				recorded_navs.append(stem.to_lower())
				return 0
			runtime.goto_movie(stem)
			return 0
		"forget", "close":
			## The window closing itself: JOKE frame 5 runs
			## `forget(window("joke.dxr"))` once its wait-for-click frame is past.
			if runtime == null or record:
				return 0
			runtime.go_back()
			return 0
		## `cursorfunk` is not here on purpose. It is one of the game's own
		## handlers, called 68 times, and a host no-op swallowed every call the
		## movie's own script did not answer first — a missing handler looked
		## exactly like a handled one. Unbound, so the miss is reported.
		"cursor", "preloadmember", "unloadmember", "alert", "beep", "nothing", "updatelock":
			## Bound and deliberately inert. `preloadMember`/`unloadMember` manage
			## a heap the port does not have, `cursor` and `alert` and `beep` are
			## desktop Director talking to the OS, and `nothing` is Lingo's own
			## no-op. Each answers 0 because it succeeded in doing nothing, which
			## is not the same as not being bound.
			return 0
		_:
			## Deliberately silent: returning VOID is how the interpreter is told
			## the host binds no builtin by this name, and it reports the miss
			## with the location. Reporting here as well would double-count, and
			## would misfile every unset variable — _read_var probes call_builtin
			## for any bare identifier before it decides what the name was.
			unhandled[name.to_lower()] = true
			return null


func owns_global(name: String) -> bool:
	var key := name.to_lower()
	if STATE_GLOBALS.has(key):
		return true
	return runtime != null and PUPPET_GLOBALS.has(key)


func get_global(name: String) -> Variant:
	var key := name.to_lower()
	if STATE_GLOBALS.has(key):
		return _get_state_global(key)
	var field := str(PUPPET_GLOBALS.get(key, ""))
	if field == "" or runtime == null:
		return null
	return runtime.puppet.get(field)


func _get_state_global(key: String) -> Variant:
	match key:
		"meetings":
			# Lingo reads this as `item N of meetings`, so it has to be one
			# comma-separated string rather than the array GameState keeps.
			return ",".join(Array(GameState.meetings))
		"globalday":
			return GameState.globalday
	return null


func _set_state_global(key: String, value: Variant) -> void:
	match key:
		"meetings":
			var next := PackedStringArray()
			for item in LingoValue.to_str(value).split(","):
				next.append(str(item).strip_edges())
			GameState.meetings = next
			GameState.state_changed.emit()
		"globalday":
			var day := LingoValue.to_int(value)
			if day != GameState.globalday:
				GameState.advance_day(day)


func set_global(name: String, value: Variant) -> void:
	var key := name.to_lower()
	if STATE_GLOBALS.has(key):
		_set_state_global(key, value)
		return
	var field := str(PUPPET_GLOBALS.get(key, ""))
	if field == "" or runtime == null:
		return
	if field == "whatodo":
		runtime.puppet.whatodo = LingoValue.to_str(value)
	elif field == "syz":
		runtime.puppet.syz = LingoValue.to_int(value)
	else:
		runtime.puppet.set(field, float(LingoValue.to_num(value)))


func is_native_handler(name: String) -> bool:
	return NATIVE_HANDLERS.has(name.to_lower())


func _walkonby() -> Variant:
	## The original sets sprite 30's walk-cycle member and flips whatodo. The port
	## does all of that in PuppetController, so the native version only has to
	## start it moving toward egozh/egozv, which the caller has already set.
	if runtime == null:
		return 0
	var puppet: Object = runtime.puppet
	if not bool(puppet.active):
		puppet.bootstrap(Vector2(float(puppet.loc_h), float(puppet.loc_v)),
			runtime.loader.stage_size,
			str(runtime.marker_name_for_frame(runtime.frame_index)))
	var target_h := float(puppet.egozh)
	if target_h < float(puppet.loc_h) - 10.0:
		puppet.facing = "left"
	elif target_h > float(puppet.loc_h) + 10.0:
		puppet.facing = "right"
	# `nextroomdata` is the original's room handover and item 1 is the destination
	# label; "000" means stay in this room.
	var destination := ""
	var transition := false
	if interpreter != null:
		var raw := LingoValue.to_str((interpreter.globals as Dictionary).get("nextroomdata", ""))
		var first := LingoValue.get_chunk(raw, "item", 1, 1)
		if first != "" and first != "000":
			destination = first
		# `ifmovie` outranks it. 130 scripts set this global, and it is the
		# original's answer to "where does the walk actually land", which is not
		# always the room named in `nextroomdata`. ISLAND2's `arcade1` handler
		# walks Piposh to "arcade" and sets `ifmovie = "1,goarcade1"`, and
		# goarcade1 is the label that launches ARCADE1. Reading only
		# `nextroomdata` left him standing in the arcade, which is what made both
		# HOTEL1 machines and the DAY1/NIGHT1 forest exits dead clicks.
		var after := _ifmovie_label()
		if after != "":
			destination = after
			# `ifmovie` item 1 = "1" is the original's own answer to "does this walk
			# end on a canned animation", and it is the condition
			# `whatodoeveryframe` hides sprite 30 on. Recorded rather than acted on
			# here: the hide belongs at arrival, and _ifmovie_label() consumes the
			# global the way the original clears it, so there is nothing left to
			# read by then.
			transition = true
	puppet.nextroom = (
		{"label": destination, "transition": transition} if destination != "" else {}
	)
	puppet.whatodo = "walktime"
	puppet.walk_tick = 0
	puppet.apply_walk_frame()
	stage_dirty = true
	return 0


func _ifmovie_label() -> String:
	## `ifmovie` is written as "<flag>,<label>". The flag is 1 when the walk ends
	## somewhere other than the room it started in, and "0,0" is the idle value
	## every room resets it to. A few handlers write the bare label with no flag.
	##
	## Consumed here rather than merely read: the original clears it once the
	## handover happens, and leaving it set would redirect the next walk too.
	if interpreter == null:
		return ""
	var globals: Dictionary = interpreter.globals
	var raw := LingoValue.to_str(globals.get("ifmovie", "")).strip_edges()
	if raw == "":
		return ""
	var parts := raw.split(",")
	var label := ""
	if parts.size() >= 2:
		if parts[0].strip_edges() != "1":
			return ""
		label = parts[1].strip_edges()
	else:
		label = parts[0].strip_edges()
	if label == "" or label == "0" or label == "000":
		return ""
	globals["ifmovie"] = "0,0"
	return label


func begin_dispatch() -> void:
	navigated = false
	held = false


func begin_record() -> void:
	record = true
	recorded_navs = PackedStringArray()
	recorded_sounds = PackedStringArray()


func _go(args: Array) -> Variant:
	if runtime == null or args.is_empty():
		return 0
	# `go to frame 5` and `play frame "x"` carry their command words as leading
	# string arguments; `go to movie "x"` keeps "movie" because it changes meaning.
	var trimmed: Array = []
	for arg in args:
		var word := LingoValue.to_str(arg).to_lower()
		if trimmed.is_empty() and word in ["to", "frame", "the", "loop", "done"]:
			continue
		trimmed.append(arg)
	args = trimmed
	if args.is_empty():
		return 0
	if record:
		for arg in args:
			var text := LingoValue.to_str(arg).to_lower()
			if text != "" and text != "movie" and text != "frame":
				recorded_navs.append(text.get_basename())
		return 0
	var first: Variant = args[0]
	# `go to movie "x"` arrives as two arguments in command form.
	if args.size() >= 2 and LingoValue.to_str(first).to_lower() == "movie":
		runtime.goto_movie(LingoValue.to_str(args[1]))
		navigated = true
		return 0
	# `go(1, "exodus.dir")` is "frame 1 of that movie". Without this the second
	# argument was dropped and the first read as a frame in the *current* movie,
	# so New Game jumped strtgame to its own frame 0, replayed the title
	# sequence and came back to the menu: the intro appeared to loop forever.
	# Used 64 times across the corpus, including every `peoplefunk` meeting.
	# The path is stripped because the originals prefix `the moviePath` or
	# `cdsavepath`, neither of which means anything here.
	if args.size() >= 2:
		var target := LingoValue.to_str(args[1]).strip_edges()
		var lowered := target.to_lower()
		if lowered.ends_with(".dxr") or lowered.ends_with(".dir"):
			runtime.goto_movie(target.get_file().get_basename(), LingoValue.to_int(first))
			navigated = true
			return 0
	if typeof(first) == TYPE_STRING:
		var text := (first as String)
		if text.to_lower().ends_with(".dxr") or text.to_lower().ends_with(".dir"):
			runtime.goto_movie(text.get_basename())
			navigated = true
			return 0
		var index: int = int(runtime.loader.resolve_label(text, false))
		if index >= 0:
			_enter(index)
		else:
			## `go` is bound; this label is not in the movie. Worth a located
			## report all the same — a jump that goes nowhere is how a dead click
			## looks from the inside, and the old counter said which label but
			## never which handler asked for it.
			navigated = false
			unhandled['go "%s"' % text] = true
			_report(LingoDiagnostics.BUILTIN, 'go "%s"' % text)
		return 0
	var frame := LingoValue.to_int(first)
	if frame > 0:
		_enter(frame - 1)
	else:
		navigated = false
	return 0


func _enter(index: int) -> void:
	if runtime == null:
		return
	if index == runtime.frame_index:
		# `go to the frame`: hold here rather than re-entering, which would
		# restart the frame's sounds and delay timer on every step. A hold is not
		# a navigation, so the two flags stay distinct.
		held = true
		return
	runtime.enter_frame(index)
	# Set after the call, not before: enter_frame dispatches the destination's
	# entry scripts and its begin_dispatch() clears this.
	navigated = true


func _sound(args: Array) -> Variant:
	if args.is_empty():
		return 0
	var verb := LingoValue.to_str(args[0]).to_lower()
	match verb:
		"playfile":
			if args.size() >= 3:
				if record:
					recorded_sounds.append(
						LingoValue.to_str(args[2]).to_lower().get_file().get_basename())
				else:
					AudioDirector.play_file(LingoValue.to_int(args[1]), LingoValue.to_str(args[2]))
			return 0
		"stop":
			if args.size() >= 2:
				AudioDirector.stop_channel(LingoValue.to_int(args[1]))
			else:
				AudioDirector.stop_all()
			return 0
		"fadeout", "fadein":
			## Bound and inert: AudioDirector has no fade, so the sound simply
			## keeps playing or stays stopped.
			return 0
		_:
			unhandled["sound %s" % verb] = true
			_report(LingoDiagnostics.BUILTIN, "sound %s" % verb)
			return 0


func _marker(args: Array) -> Variant:
	## `marker(0)` is the label of the current frame; Lingo compares it against
	## `label("x")`, so both must be frame numbers.
	if runtime == null:
		return 0
	var offset := LingoValue.to_int(args[0] if args.size() > 0 else 0)
	# Resolve by position, never by name. Director names an unnamed marker
	# "New Marker", and strtgame has 49 of them against 32 distinct labels, so a
	# name lookup collapsed every marker in the opening cinematic onto the first
	# at frame 42. `go(marker(0) + 1)` then meant "jump to 43" from anywhere,
	# which replayed the frame that starts the speech, so soundBusy(1) never
	# cleared and the Katzale/Nache scene looped forever.
	var frames: Array = []
	for marker in runtime.loader.markers:
		if typeof(marker) == TYPE_DICTIONARY:
			frames.append(int((marker as Dictionary).get("frame", 0)))
	frames.sort()
	var here: int = runtime.frame_index
	if offset == 0:
		# The marker at or before the playhead.
		var current := -1
		for frame in frames:
			if frame <= here:
				current = frame
			else:
				break
		return current + 1 if current >= 0 else 0
	if offset > 0:
		for frame in frames:
			if frame > here:
				return frame + 1
		return frames[frames.size() - 1] + 1 if not frames.is_empty() else 0
	var previous := 0
	for frame in frames:
		if frame >= here:
			break
		previous = frame
	return previous + 1


func unhandled_names() -> PackedStringArray:
	var out := PackedStringArray()
	for key in unhandled.keys():
		out.append(str(key))
	out.sort()
	return out
