extends RefCounted
## The keys the frame in front of you needs, and a way to press them with a finger.
##
## **The problem, stated as the owner hit it.** These titles were authored in 1997
## for a keyboard and a mouse. A phone has neither. Piposh 1's roulette wants a
## number typed into a field; Rating's `arcade1.dir` steers on the arrow keys and
## quits on Escape; 46 scripts across the corpus skip a line of speech on key code
## 49. Every one of those scenes starts, draws correctly, and cannot be played,
## which is the expensive failure mode -- nothing is reported and nothing looks
## broken.
##
## `DisplayServer.virtual_keyboard_show` is the engine's only answer today
## (`text_focus.gd:205`) and it serves a text *field*. It does nothing at all for a
## script that polls `the keyCode` out of an `exitFrame` loop, which is how nearly
## every one of these scenes is written.
##
## **The rule this file exists to obey: fix it in the engine, with as little
## per-title data as possible.** A table saying "arcade1 frames 63-270 need the
## arrows" would work and would be the wrong shape -- 700 movies, hand-written,
## stale the first time anything is re-decoded. The information is already in the
## title: the movie's own scripts say which keys they test, and the movie's own
## score says on which frames those scripts are attached. So the demand is
## *derived*, per frame, from data the engine has already parsed to play the movie
## at all. Nothing here knows what a game is called and no title is named in it.
##
## ## Two halves, and the split is deliberate
##
## **The measurement** (`scan_source`, `actions_of`, `classify`, `demand_at`) is
## the part that has to be right, and it is verified over the whole corpus rather
## than over the scene somebody happened to look at: `tools/key_demand.gd` runs
## exactly these functions across all eight roots -- the six shipped titles and
## both Itamar corpora -- and reports the census scene by scene. It is one
## definition used twice, so a census that passes is a statement about the code
## that ships and not about a re-implementation of it.
##
## **The overlay** (`enabled`, `buttons`, `draw`, `pointer`) is the part that is a
## judgement call. It offers two controls, and which one is on screen is decided by
## the measurement rather than by a setting:
##
##   * a **stick** -- a visible virtual joystick -- for the actions that are
##     directions, because a direction held is what steering is;
##   * a **row of labelled buttons** for every action that is not, because a
##     gesture cannot express "Escape" and pretending otherwise is worse than a
##     button.
##
## ## What a held stick maps to, and why it repeats
##
## **A stick pushed over is a key held down, and a key held down repeats.** That is
## the whole of the mapping and it is the decision most likely to be wrong, so it is
## written here rather than left in the code. Director's own `keyDown` fires again
## while a key is held -- that is what makes `arcade1.dir` steer rather than step
## once per press -- and its play spans install a `keyDownScript` that reads `the
## keyCode` and moves a character. Firing once per push would make the arcade
## unplayable in a subtler way than not firing at all: it would work, badly, and
## look like a physics bug.
##
## So a committed direction sends a press immediately, then a further press every
## `REPEAT_MS` after an initial `REPEAT_FIRST_MS` delay, and a release when the
## finger lifts or the stick returns inside the dead zone. The two numbers are a
## keyboard's, not a guess.
##
## **The repeat is a press/release pair rather than an `echo` press**, and that is a
## trade rather than a detail: it is indistinguishable from a held key to everything
## in this corpus that reads `the keyCode`, `the key` or `on keyDown`, and it cannot
## leave a key logically stuck if the process ends mid-hold. What it is *not*
## faithful to is `the keyUpScript`, which sees one release per repeat instead of one
## at the end. No scene measured by `tools/key_demand.gd` installs a `keyUpScript`
## and reads a direction, so nothing in reach can tell; it is recorded as a known
## divergence rather than as a thing that was checked and found equivalent.
##
## ## Moving the stick, and why a long press rather than two fingers
##
## The player can pick the stick up and put it somewhere else -- a left-handed
## player wants it on the left, and where it sits is a preference, not a property of
## the movie.
##
## The obvious gesture is a two-finger drag, and it is **unavailable**, for a reason
## that is measured rather than aesthetic: this engine reads touch through Godot's
## mouse emulation (`docs/MOBILE.md`, "Input"), which tracks **exactly one finger**
## -- a second finger sends nothing at all, verified in `tools/touch_input.gd`. A
## two-finger gesture would therefore need a real touch path this engine does not
## have, and it would have no mouse equivalent, so `--touch-input` could not test it
## on a desktop. That is precisely the shape of thing that ships untested.
##
## So it is **press and hold on the stick, then drag**. It cannot be confused with
## driving because the two are separated in *time* and the separation is enforced
## rather than hoped for: a drive commits the moment the finger leaves the dead
## zone, and the pick-up only arms if the finger is *still inside* it after
## `PICKUP_MS`. Once either has started the other can no longer begin. It is
## discoverable because the ring thickens while the hold is counting down, so the
## gesture announces itself before it completes, and it is one code path for a
## finger and for a mouse.
##
## ## Nothing changes on desktop
##
## `enabled()` is false unless the machine is mobile, or has a touchscreen and no
## mouse, or `--touch-input` forces it. `director_preview.gd` caches that in
## `_key_overlay` and branches on the bool, so on a desktop the paint path and the
## click path are what they were.
##
## ## What "an action" is, and why it is not "a key"
##
## `if (the keyCode = 126) or (the keyCode = 13) then` is **one** thing the player
## does. Rating's arcade spells "up" as either the up arrow or W -- a
## Hebrew-keyboard alternate, not a second control -- and counting literals gives
## two buttons where the player needs one. Measured on `arcade1.dir`: counted per
## literal its play spans demand eight keys and read as a scene no button row can
## serve; counted per action they demand four, three of which are directions, and
## a D-pad plus one button plays the game. The grouping is the author's own line
## break, which is weaker than parsing the boolean expression and is what `or` on
## its own line would defeat; nothing in the eight corpora writes it that way, and
## where something does the count comes out high rather than wrong.
##
## ## What a static read cannot see, stated rather than smoothed over
##
## A handler reached only through `do`, a script attached by `puppetSprite` plus
## `set the scriptInstanceList`, and a `keyDownScript` whose *string* is built at
## run time are all invisible here. `the keyDownScript` assigned to a **named**
## handler is followed -- that is what turns arcade1's seventeen assignment sites
## from a movie-wide smear into demand on the spans that install them -- but the
## hook outlives the span that installed it, so the attribution is a lower bound.
## The overlay's answer for a frame it has nothing for is to draw nothing, which
## is the same as today.
##
## ## Which control a scene gets
##
## `stick_actions` splits the frame's demand into directions and everything else.
## **A direction anywhere in the scene earns a stick, and the row carries the rest**
## -- the two coexist, because a gesture cannot express "Escape" and a row cannot
## express steering, and a scene that needs both needs both.
##
## That produces exactly four shapes, and `gate.sh` runs one movie of each rather
## than assuming any of them:
##
##   stick only        `piposh2 PIP2DATA/ARCADE2.dir` -- `stg1go` needs Up/W,
##                     Right/E, Down/D and nothing else.
##   stick **and** row `rating arcade1.dir` -- three directions and Escape. The most
##                     valuable case, because it is the only one where the two
##                     controls have to coexist without eating each other's input.
##   row only          `rating navigate.dir` -- Escape and F10, no direction
##                     anywhere in the movie.
##   neither           `piposh PIPDATA/ROULLETE.dir` -- an editable field, so the
##                     system keyboard is the answer and both controls decline.
##
## Where a stick is possible the player can still choose the row, and the choice is
## a chip on screen rather than a setting behind a restart. It persists across a
## room change, because it says something about the player and not about the movie.

const Paint := preload("res://director/director_paint.gd")
const Keys := preload("res://director/director_keys.gd")

# ---------------------------------------------------------------- the patterns

## How a script can ask for the keyboard at all, as label -> pattern, matched
## against lower-cased source.
##
## `tools/lib/key_sites.gd` carries the same table for a **different question**
## and the two are deliberately not folded: that one answers "which keys does this
## *title* touch anywhere", which is what `tools/debug_bindings.gd` needs to decide
## whether the preview may bind F10, and it is a union over a hundred movies. This
## one answers "what does the frame in front of the player need". A union is the
## wrong answer to the second question -- Rating's union is 24 keys and no scene in
## it needs more than four.
const ASKS := {
	"on keyDown": "(?m)^\\s*on\\s+keydown\\b",
	"on keyUp": "(?m)^\\s*on\\s+keyup\\b",
	"the keyDownScript": "the\\s+keydownscript",
	"the keyUpScript": "the\\s+keyupscript",
	"when keyDown then": "when\\s+keydown\\s+then",
	"when keyUp then": "when\\s+keyup\\s+then",
	"the key": "the\\s+key\\s*(?![a-z])",
	"the keyCode": "the\\s+keycode",
	"dontPassEvent": "dontpassevent",
}

## `the key = "x"` -- the character the player must be able to type.
const CHAR_PATTERN := "the\\s+key\\s*(?![a-z])\\s*=\\s*\"([^\"]*)\""
## `the keyCode = 109`, quoted or not. Director stringifies the comparison in about
## half these scripts and not in the other half.
const CODE_PATTERN := "the\\s+keycode\\s*=\\s*\"?(\\d+)\"?"
## `set the keyDownScript to "x"` and `the keyUpScript = "x"` in one pattern.
## Director accepts both spellings and the corpus uses both; the unquoted operand
## is matched because `EMPTY` is how all seventeen of `arcade1.dir`'s sites *clear*
## the hook, and a pattern that only saw quoted strings would read a clear as an
## install of a handler called nothing.
const INSTALL_PATTERN := \
	"the\\s+key(?:down|up)script\\s*(?:to|=)\\s*(?:\"([^\"]*)\"|([a-z_][a-z0-9_]*))"
## `on <name>` at the start of a line, which opens a handler block.
const HANDLER_PATTERN := "(?m)^\\s*on\\s+([a-z_][a-z0-9_]*)"

## Director's script member types: 1 score/behaviour, 3 movie, 7 parent. Only 3 is
## movie-wide, which is the distinction the whole per-frame attribution rests on.
const SCRIPT_TYPE_MOVIE := 3
const MEMBER_TYPE_SCRIPT := 11

## `the keyCode` for the four arrows, from `director_keys.gd`.
const ARROW_CODES := [Keys.LEFT, Keys.RIGHT, Keys.DOWN, Keys.UP]
## `the key` reports these for the arrows -- Director's documented substitution
## (§8.3), mirrored in `director_keys.char_for`. A script comparing `the key`
## against one of them is asking for an arrow and not for a control character.
const ARROW_CHARS := ["\u001c", "\u001d", "\u001e", "\u001f"]

## How a scene asks for the keyboard. These are the census buckets, and each one is
## a *different* on-screen control -- which is the reason for separating them at
## all. Collapsing `ANY` into `FEW` is how a port ends up drawing a keyboard for a
## scene that needs one button.
enum Shape {
	NONE,    ## no script on these frames touches the keyboard
	ANY,     ## asks, tests no literal: any key continues
	ARROWS,  ## every action is a direction
	FEW,     ## up to FEW_LIMIT named keys
	DIGITS,  ## digits among the literals: a number
	TEXT,    ## an editable field is on stage: a real keyboard
	MANY,    ## more named keys than a button row can hold
}

const SHAPE_NAMES := [
	"none", "any key", "arrows", "a few keys", "digits", "typed text", "many keys",
]

## Where "a few labelled buttons" stops being a reasonable overlay. Six is a row
## across a 640-wide stage at a finger-sized target. It is a design judgement and
## not a measurement, and it is named here so the census can be re-cut against
## another number without hunting for a literal.
const FEW_LIMIT := 6


# ------------------------------------------------------------- the measurement

static var _compiled: Dictionary = {}
## Source text -> its scan. Cast members are shared across movies and a handler is
## routinely pasted into a dozen behaviours, so the same text is scanned many times
## over a corpus and the regexes are the whole cost of this file.
static var _source_cache: Dictionary = {}


static func _re(pattern: String) -> RegEx:
	if _compiled.has(pattern):
		return _compiled[pattern]
	var re := RegEx.new()
	re.compile(pattern)
	_compiled[pattern] = re
	return re


## An empty demand record. The shape every function here passes around:
##
##   asks            this script reaches for the keyboard at all
##   codes / chars   every literal, for reporting
##   groups          the literals of one source line, which is one action
##   installs        it assigns a keyDownScript/keyUpScript
##   installs_named  the handler names it assigns, for `resolve_installs`
##   text            an editable field is on stage (set by the caller, not here)
static func empty() -> Dictionary:
	return {
		"asks": false, "codes": {}, "chars": {},
		"groups": [], "installs": false, "installs_named": {}, "text": false,
	}


static func merge(into: Dictionary, from: Dictionary) -> void:
	if bool(from["asks"]):
		into["asks"] = true
	if bool(from.get("installs", false)):
		into["installs"] = true
	if bool(from.get("text", false)):
		into["text"] = true
	for code in from["codes"]:
		into["codes"][code] = true
	for ch in from["chars"]:
		into["chars"][ch] = true
	for group in from["groups"]:
		into["groups"].append(group)
	for name in from.get("installs_named", {}):
		into["installs_named"][name] = true


## One script member, split into the handlers it declares:
##
##   {"member": every literal in the member,
##    "hooks":  only `on keyDown`/`on keyUp` and any top-level code,
##    "handlers": {"zigiscript": that handler's literals, ...}}
##
## **The split is what makes a movie script's demand honest.** `arcade1.dir`
## carries `zigiscript`, `normalkeys` and `normkeys1..3` -- six handlers testing
## eight keys between them -- in members that are *movie* scripts, and a movie
## script is live for the whole movie. Read at member granularity, all 35 of that
## movie's scenes demand all eight keys. But Director does not *call* those
## handlers movie-wide: they run only while something has assigned them to `the
## keyDownScript`, and the seventeen assignment sites are behaviours the score
## attaches to spans. `hooks` is the part a movie script really does contribute
## everywhere -- `on keyDown` is Director's global keyboard entry and nothing else
## is -- and `handlers` is what an install resolves to.
##
## Measured with the split: arcade1's `zigihelp` scene demands Escape alone while
## its play spans demand three directions and Escape. Without it every span reads
## the same and the derivation cannot tell a help screen from an arcade game.
static func scan_source(source: String) -> Dictionary:
	if _source_cache.has(source):
		return _source_cache[source]
	var out := {"member": empty(), "hooks": empty(), "handlers": {}}
	# Cached before the work, so a source that somehow recurses cannot loop.
	_source_cache[source] = out

	var lowered := source.to_lower()
	var asks := false
	var installs := false
	for label in ASKS:
		if _re(str(ASKS[label])).search(lowered) != null:
			asks = true
			if label == "the keyDownScript" or label == "the keyUpScript":
				installs = true
	if not asks:
		return out
	out["member"]["asks"] = true
	out["member"]["installs"] = installs

	var handler := ""
	var open_re := _re(HANDLER_PATTERN)
	var char_re := _re(CHAR_PATTERN)
	var code_re := _re(CODE_PATTERN)
	var install_re := _re(INSTALL_PATTERN)
	for line in source.split("\n"):
		var lowered_line := str(line).to_lower()
		var opened := open_re.search(lowered_line)
		if opened != null:
			handler = opened.get_string(1)
			if not (out["handlers"] as Dictionary).has(handler):
				out["handlers"][handler] = empty()
			out["handlers"][handler]["asks"] = true

		var into: Array[Dictionary] = [out["member"]]
		if handler == "" or handler == "keydown" or handler == "keyup":
			# Code outside any handler runs when the script is instantiated, which
			# for a movie script is the movie; `keyDown`/`keyUp` are Director's own
			# global entry. Both are hooks.
			into.append(out["hooks"])
		else:
			into.append(out["handlers"][handler])

		# **A line, not a script, is the unit of an action.** See the file header.
		var group: Array[String] = []
		for hit in char_re.search_all(lowered_line):
			var literal := hit.get_string(1)
			if literal != "":
				group.append("char:%s" % literal)
		for hit in code_re.search_all(lowered_line):
			group.append("code:%d" % int(hit.get_string(1)))

		var installed := ""
		var install_hit := install_re.search(lowered_line)
		if install_hit != null:
			installed = install_hit.get_string(1).strip_edges()
			if installed == "":
				installed = install_hit.get_string(2).strip_edges()
			if installed == "empty":
				installed = ""

		for target in into:
			for token in group:
				if str(token).begins_with("code:"):
					target["codes"][int(str(token).substr(5))] = true
				else:
					target["chars"][str(token).substr(5)] = true
			if not group.is_empty():
				target["groups"].append(group)
			if installed != "":
				target["installs"] = true
				target["installs_named"][installed] = true
				target["asks"] = true

	# A member whose only keyboard mention is inside a named handler still `asks`
	# at member level; `hooks` does not, and that is the whole point of the split.
	out["hooks"]["asks"] = _hooks_ask(out["hooks"], lowered)
	return out


static func _hooks_ask(hooks: Dictionary, lowered: String) -> bool:
	if not (hooks["codes"] as Dictionary).is_empty():
		return true
	if not (hooks["chars"] as Dictionary).is_empty():
		return true
	if not (hooks["installs_named"] as Dictionary).is_empty():
		return true
	# A bare `on keyDown` that tests nothing is the "any key continues" case, and
	# it is demand: something has to be pressable.
	for label in ["on keyDown", "on keyUp", "when keyDown then", "when keyUp then"]:
		if _re(str(ASKS[label])).search(lowered) != null:
			return true
	return false


## The demand of the whole member -- what a *behaviour* contributes to its span.
static func demand_of(source: String) -> Dictionary:
	return scan_source(source)["member"]


## Fold in the demand of every handler this script installs as a `keyDownScript`.
##
## Returns a **new** dictionary rather than mutating, because `scan_source`'s
## answers are cached by source text and shared by every member holding the same
## text; writing the resolution into one would leak it into all of them, and the
## resolution depends on which movie is asking.
static func resolve_installs(d: Dictionary, handlers: Dictionary) -> Dictionary:
	if (d["installs_named"] as Dictionary).is_empty():
		return d
	var out := empty()
	merge(out, d)
	for name in d["installs_named"]:
		if handlers.has(name):
			merge(out, handlers[name])
	return out


## Handler name -> that handler's demand, over every library a movie can address.
##
## Built per movie, because a `keyDownScript` names its handler by string and the
## string is resolved against whatever the movie can see. First declaration wins,
## which is what the interpreter does for a duplicate handler and what
## `director_labels` does for a duplicate label.
static func handler_index(table) -> Dictionary:
	var out: Dictionary = {}
	for lib in table.cast_libs:
		var scanned := library_scan(table, int(lib))
		for name in scanned["handlers"]:
			if not out.has(name):
				out[name] = scanned["handlers"][name]
	return out


## Container path -> `{"handlers": {...}, "hooks": <demand>, "editable": {...}}`.
##
## **Keyed by the file, not by the library number or the movie.** Piposh 2's
## `MASTER.CST` is 61 MB and every one of its 61 movies links it, and a `CastTable`
## is built per movie -- so a scan that walked the libraries a movie can address
## re-parsed thousands of the same cast members once per movie. Measured: the
## corpus sweep did not finish its **first** root in twelve minutes with that walk
## in it, against roughly five without. The cache is on the file because a cast is
## the same cast whichever movie asked, which is the same argument
## `director_cast_table._by_path` already makes one layer down and for the same
## reason.
static var _by_container: Dictionary = {}


static func library_scan(table, lib: int) -> Dictionary:
	var path := str(table.container_path_of(lib))
	if path != "" and _by_container.has(path):
		return _by_container[path]
	var out := {"handlers": {}, "hooks": empty(), "editable": {}}
	var cast = table.cast_for(lib)
	if cast == null:
		return out
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(number)
		if m.is_empty():
			continue
		if bool(m.get("editable", false)):
			out["editable"][number] = true
		var source := str(m.get("source", ""))
		if source.strip_edges() == "":
			continue
		var scanned := scan_source(source)
		for name in scanned["handlers"]:
			if not (out["handlers"] as Dictionary).has(name):
				out["handlers"][name] = scanned["handlers"][name]
		# **Only a movie script is movie-wide, and only its hooks.** A behaviour
		# that asks for the keyboard is demand on the frames the score gave it and
		# nowhere else; a movie script's named handler is demand only where
		# something installs it.
		if int(m.get("type", 0)) != MEMBER_TYPE_SCRIPT \
				or int(m.get("script_type", 0)) != SCRIPT_TYPE_MOVIE:
			continue
		if bool(scanned["hooks"]["asks"]):
			merge(out["hooks"], scanned["hooks"])
	if path != "":
		_by_container[path] = out
	return out


## What every **movie script** of every library contributes to every frame, and
## which members are editable fields.
##
##   {"demand": <movie-wide demand>, "editable": {"lib:member": true}}
##
## Editability is read from the *member* and not from the score, which is not a
## shortcut: `director_cast.gd:537` records that not one of Piposh 2's 816,318
## sprite records sets the score's own editable bit, so a reader that looked only
## at the score would find no typing anywhere in this corpus.
static func movie_wide(table, handlers: Dictionary) -> Dictionary:
	var out := {"demand": empty(), "editable": {}}
	for lib in table.cast_libs:
		var scanned := library_scan(table, int(lib))
		# `resolve_installs` is applied here rather than inside `library_scan`,
		# because which handler a name resolves to is a property of the **movie** --
		# a shared cast is read by movies that see different handler sets, and a
		# resolution folded into the file's cache would be the first movie's answer
		# handed to every later one.
		if bool(scanned["hooks"]["asks"]):
			merge(out["demand"], resolve_installs(scanned["hooks"], handlers))
		for number in scanned["editable"]:
			out["editable"]["%d:%d" % [lib, number]] = true
	return out


## Every score-attached script that asks for the keyboard, as
## `{start, end, demand}` -- the frames the score gave it and what it needs.
##
## This is the function that makes the answer per *scene* rather than per movie:
## `score.intervals()` carries each frame script's and each sprite behaviour's own
## `start`/`end`, so a behaviour testing `the keyCode = 123` is demand on exactly
## those frames.
static func spans(score, table, handlers: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for interval in score.intervals():
		var lib := int(interval["script_cast_lib"])
		# 0 and -1 both mean "this movie's own cast" in a score record; the table is
		# keyed by library number and library 1 is the internal cast.
		if lib <= 0:
			lib = 1
		var m: Dictionary = table.get_member(lib, int(interval["script_member"]))
		var source := str(m.get("source", ""))
		if source.strip_edges() == "":
			continue
		var d := resolve_installs(demand_of(source), handlers)
		if not bool(d["asks"]):
			continue
		out.append({
			"start": int(interval["start"]), "end": int(interval["end"]), "demand": d,
		})
	return out


## How many **actions** a demand is: its groups joined transitively wherever they
## share a literal.
##
## Sharing matters because two lines can name the same key for the same purpose --
## `if the keyCode = 53` appears four times in `arcade1.dir` -- and four groups of
## one Escape is one button, not four. Transitive rather than pairwise so that
## `{up, W}` and `{W, X}` fold into one action; nothing in the corpus writes that,
## and the alternative is a count that depends on the order the groups arrived in.
static func actions_of(d: Dictionary) -> Array:
	var components: Array = []
	for group in d["groups"]:
		var merged: Dictionary = {}
		for token in group:
			merged[token] = true
		var keep: Array = []
		for existing in components:
			var shares := false
			for token in existing:
				if merged.has(token):
					shares = true
					break
			if shares:
				for token in existing:
					merged[token] = true
			else:
				keep.append(existing)
		keep.append(merged)
		components = keep
	return components


## Which of the seven shapes a demand is.
##
## The precedence is the whole content of this function and it is not arbitrary.
## Text wins because a scene with an editable field needs a real keyboard whatever
## else it tests. Arrows beat "a few keys" because four arrows are a D-pad and not
## four buttons, and a set that is exactly directions is the one case a gesture can
## answer. Digits beat "a few" because ten of them is a number pad rather than a
## button row, and because a scene asking for digits is nearly always asking for a
## typed *number* -- Piposh 1's roulette is the case that named this bucket.
static func classify(d: Dictionary) -> int:
	if not bool(d["asks"]):
		return Shape.NONE
	if bool(d.get("text", false)):
		return Shape.TEXT
	var actions := actions_of(d)
	if actions.is_empty():
		return Shape.ANY
	var digits := digit_codes()
	var arrow_actions := 0
	var digit_actions := 0
	for action in actions:
		var is_arrow := false
		var is_digit := false
		for token in action:
			var t := str(token)
			if t.begins_with("code:"):
				var code := int(t.substr(5))
				if ARROW_CODES.has(code):
					is_arrow = true
				if digits.has(code):
					is_digit = true
			else:
				var ch := t.substr(5)
				if ARROW_CHARS.has(ch):
					is_arrow = true
				if ch.length() == 1 and ch >= "0" and ch <= "9":
					is_digit = true
		# An action whose alternates include an arrow **is** a direction: Rating's
		# arcade spells "up" as up-arrow-or-W, and calling that a named key because
		# W is in the set would put a labelled button where a D-pad belongs.
		if is_arrow:
			arrow_actions += 1
		elif is_digit:
			digit_actions += 1
	if arrow_actions == actions.size() and actions.size() <= 4:
		return Shape.ARROWS
	if digit_actions > 0:
		return Shape.DIGITS
	return Shape.FEW if actions.size() <= FEW_LIMIT else Shape.MANY


## Mac virtual key codes of the ten digits, derived from `Keys.MAC_CODES` rather
## than transcribed -- a transcript of a table in another file is a second copy of
## it, and the Mac codes are not in numeric order.
static func digit_codes() -> Array:
	var out: Array = []
	for keycode in [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
		out.append(int(Keys.MAC_CODES[keycode]))
	return out


## The Godot keycode an action should send: the first alternate that maps.
##
## The *first* rather than the arrow, because the alternates are equals as far as
## the script is concerned and picking one needs no cleverness -- but sorted, so
## that the same action always sends the same key and a harness can assert it.
## `KEY_NONE` when nothing in the action maps to a key this engine can synthesise,
## which is a button that would do nothing and is therefore not drawn.
static func keycode_of(action: Dictionary) -> Key:
	for token in _ordered(action):
		var t := str(token)
		if t.begins_with("code:"):
			var wanted := int(t.substr(5))
			for keycode in Keys.MAC_CODES:
				if int(Keys.MAC_CODES[keycode]) == wanted:
					return keycode
		else:
			var ch := t.substr(5)
			var arrow := ARROW_CHARS.find(ch)
			if arrow >= 0:
				return [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN][arrow]
			if ch.length() == 1:
				var upper := ch.to_upper()
				var found := OS.find_keycode_from_string(upper)
				if found != KEY_NONE:
					return found
	return KEY_NONE


## What a button for this action says. The key's own name, with alternates joined
## by `/` -- "Up/W" rather than "Up", because a player who knows the game knows W.
static func label_of(action: Dictionary) -> String:
	var names: Array[String] = []
	for token in _ordered(action):
		var t := str(token)
		if t.begins_with("code:"):
			names.append(key_name(int(t.substr(5))))
		else:
			names.append(printable(t.substr(5)))
	return "/".join(names)


## An action's alternates in the order a button should present them: **an arrow
## first**, then everything else sorted.
##
## The arrow is not an arbitrary tie-break. Where a Director script offers a
## direction and a letter for the same control, the direction is the thing the
## player is doing and the letter is a keyboard convenience -- Rating's arcade
## spells "up" as up-arrow-or-W because a Hebrew layout puts W where a right hand
## sits. A button labelled `Up/W` reads as a direction; `W/Up` reads as a letter.
##
## Sorted after that so a run is repeatable: an unordered `Dictionary.keys()` would
## make the label and the key a button sends depend on insertion order, and a
## harness could not assert either.
static func _ordered(action: Dictionary) -> Array:
	var arrows: Array = []
	var rest: Array = []
	for token in action:
		var t := str(token)
		var is_arrow := (t.begins_with("code:") and ARROW_CODES.has(int(t.substr(5)))) \
			or (t.begins_with("char:") and ARROW_CHARS.has(t.substr(5)))
		if is_arrow:
			arrows.append(t)
		else:
			rest.append(t)
	arrows.sort()
	rest.sort()
	return arrows + rest


## The Godot key whose Mac virtual code this is, as a printable name.
static func key_name(mac_code: int) -> String:
	for keycode in Keys.MAC_CODES:
		if int(Keys.MAC_CODES[keycode]) == mac_code:
			return OS.get_keycode_string(keycode)
	return "#%d" % mac_code


## A `the key` literal as a reader sees it. The four arrow substitutes are named
## rather than shown, because `chr(28)` on a button is not a direction to anybody.
static func printable(ch: String) -> String:
	var i := ARROW_CHARS.find(ch)
	if i >= 0:
		return ["Left", "Right", "Up", "Down"][i]
	if ch.length() == 1 and ch.unicode_at(0) < 32:
		return "chr(%d)" % ch.unicode_at(0)
	return ch.to_upper()


# ------------------------------------------------------- the loaded movie's map

## Movie path -> `{"wide": demand, "editable": {...}, "spans": [...]}`.
##
## Static and keyed by path rather than held on the node, so nothing has to be
## added to the preview's save state or to `tools/preview_surface.gd`'s field list
## -- a derived fact about a file on disk is not session state, and a save that
## carried it would restore a stale copy of something the file already says.
static var _movies: Dictionary = {}


## The map for the movie the preview currently has open, built on first ask.
##
## Costs one pass over the movie's casts, which is the same walk
## `tools/key_demand.gd` makes and is seconds for the largest title in the corpus.
## It happens once per movie per session and never on a frame path.
static func map_for(host) -> Dictionary:
	var path: String = host.movie_path()
	if _movies.has(path):
		return _movies[path]
	var out := {"wide": empty(), "editable": {}, "spans": [] as Array[Dictionary]}
	_movies[path] = out
	if host._table == null or host._score == null:
		# Not an answer worth caching: the movie is mid-load and the next ask
		# should try again.
		_movies.erase(path)
		return out
	var handlers := handler_index(host._table)
	var wide := movie_wide(host._table, handlers)
	out["wide"] = wide["demand"]
	out["editable"] = wide["editable"]
	out["spans"] = spans(host._score, host._table, handlers)
	return out


## What the frame the playhead is on needs: the movie-wide demand plus every span
## covering it, plus the editable-field flag if one is on the stage right now.
##
## The editable half is asked of the **live frame** rather than of the score,
## because by the time the player is looking at it the field may have been put
## there by `puppetSprite` and not by the score at all.
## Movie path + frame -> the demand there. `buttons()` runs from `_paint`, which is
## every frame the stage draws, and `press()` runs it again for the same frame; the
## answer is a property of the movie and the frame number, so computing it twice a
## tick is work with no possible result. Cleared when the movie changes, because the
## key is the movie's path and a second movie's frame 63 is a different question.
static var _at_frame: Dictionary = {}
## Which movie `_at_frame` holds, so it can be dropped whole when the playhead
## leaves. One movie's frames are bounded; a session's are not -- these titles walk
## a hundred containers and Piposh 2 alone has 61,371 frames, and a memo that never
## forgets is a leak on the platform least able to afford one.
static var _at_frame_path := ""


static func demand_at(host, index: int) -> Dictionary:
	var path: String = host.movie_path()
	if path != _at_frame_path:
		_at_frame.clear()
		_at_frame_path = path
	var key := "%s#%d" % [path, index]
	if _at_frame.has(key):
		return _at_frame[key]
	var map := map_for(host)
	var out := empty()
	merge(out, map["wide"])
	for span in map["spans"]:
		if int(span["start"]) <= index and int(span["end"]) >= index:
			merge(out, span["demand"])
	if not (map["editable"] as Dictionary).is_empty() and _editable_on_stage(host, map, index):
		out["text"] = true
		out["asks"] = true
	# Only cached once the map is real; a movie caught mid-load answers empty and
	# must be asked again rather than remembered as a frame that needs nothing.
	if not (map["spans"] as Array).is_empty() or bool(map["wide"]["asks"]):
		_at_frame[key] = out
	return out


static func _editable_on_stage(host, map: Dictionary, index: int) -> bool:
	if host._score == null:
		return false
	var frame: Dictionary = host._score.frame(index)
	for sprite in frame.get("sprites", []):
		var lib := int((sprite as Dictionary).get("cast_lib", 1))
		var member := int((sprite as Dictionary).get("cast_id", 0))
		if member > 0 and (map["editable"] as Dictionary).has("%d:%d" % [lib, member]):
			return true
	return false


# --------------------------------------------------------------- the overlay

## -1 not yet decided, 0 off, 1 on. Read once because the answer is about the
## machine and not about the frame.
static var _forced := -1

## Which control the player last chose.
##
## **A static, so it outlives a movie.** This and `_stick_norm` are the two things
## the player sets, and a room change must not undo either: somebody who switched to
## buttons because the stick covers the art, or who moved the stick to the left
## because they are left-handed, has said something about *themselves* and not about
## the movie. A field on the preview node would be recreated per movie, which is
## exactly the bug.
##
## **Neither survives the process, and that is stated rather than hidden.**
## `save_state.gd` deliberately excludes device facts (see its `_key_overlay` row),
## and a preference file is separate work with its own path questions on Android. A
## player who restarts finds the defaults; a player who walks through fifty rooms
## does not.
enum Mode {
	STICK,    ## the virtual joystick drives the directions
	BUTTONS,  ## every action, directions included, is a labelled button
}
static var _mode: Mode = Mode.STICK
## Where the stick sits, as a **fraction of the stage** rather than pixels, so it
## survives a movie whose stage is a different size. `Vector2(-1, -1)` means "never
## moved", which is not the same as "moved to the top-left corner".
static var _stick_norm := Vector2(-1, -1)

## Where the row sits and how big a target is, in **stage** coordinates -- the whole
## overlay is drawn through `Paint`, so `_fit_to_window`'s letterbox scale and
## position apply to it for free and nothing here converts a coordinate.
##
## 44 is the smallest target Apple and Google both call reachable, in points; the
## stage is 640x480 and letterboxes *up* on every phone this will run on, so 44
## stage pixels is a floor rather than a target.
const BUTTON := Vector2(56, 44)
const GAP := 8.0
const MARGIN := 10.0

## The stick. `RADIUS` is the ring the knob travels in; `DEAD_ZONE` is how far the
## finger must move before a direction is committed, and is also the region a
## pick-up must stay inside.
const STICK_RADIUS := 46.0
const KNOB_RADIUS := 17.0
const DEAD_ZONE := 14.0

## Auto-repeat, in milliseconds. **A keyboard's numbers, not a guess**: a held key
## waits about a third of a second and then repeats around ten times a second, and
## the whole point of the stick is that it behaves like a held key.
const REPEAT_FIRST_MS := 320
const REPEAT_MS := 90

## How long the finger must sit still on the stick before it can be picked up. Long
## enough that nobody starting a drive triggers it -- a drive leaves the dead zone in
## well under a tenth of a second -- and short enough to be found by accident, which
## is how a gesture with no menu entry gets discovered at all.
const PICKUP_MS := 450

## The mode chip: small, because it is chrome and not a control the game needs.
const TOGGLE := Vector2(58, 22)

## Whether the stick needs the scene to be **entirely** directional before it is
## offered, or only to have a direction in it somewhere.
##
## **`false`: a direction anywhere in the scene earns a stick, and the row carries
## whatever is left.** The two controls sit side by side, and `arcade1.dir` is what
## that is for -- its play spans need up, right, down *and* Escape, so it gets a
## three-way stick and one Escape button.
##
## **What the strict reading would have cost, recorded so it is not re-argued from
## scratch.** `true` restricts the stick to scenes that are *entirely* directional:
## 86 across the eight corpora, by `tools/key_demand.gd`. Everything else -- 380
## named-key scenes and every mixed one among them -- falls back to a row with the
## directions in it as ordinary buttons. Two things are wrong with that. It
## contradicts the sentence that asked for the feature, which was "switch between
## modes (**if arrows are participating**)": under `true` a scene with three arrows
## and an Escape has arrows participating and gets neither a stick nor a chip to ask
## for one. And it excludes `arcade1.dir`, which is one of the two rooms this whole
## piece of work was reported from -- Rating has **zero** entirely-directional
## scenes, so the strict rule hands the room that motivated the stick a button row
## and nothing else.
##
## The constant stays because the question is a real one and a future session should
## be able to see both answers rather than infer that only one was considered.
## `tools/key_overlay.gd` covers all four shapes the loose rule produces -- stick
## only, stick and row together, row only, neither -- so flipping it back would fail
## loudly rather than silently change what players get.
const STICK_NEEDS_EVERY_ACTION := false


## Whether the overlay exists at all on this machine.
##
## **Two device tests, or'd, and the reason for each is different.**
##
## `OS.has_feature("mobile")` is the platform test, and it is here despite this
## codebase having been burned by exactly that shape once already:
## `_pointer_from_events` latched `not has_feature(FEATURE_MOUSE)` at load and was
## wrong on every machine with both a mouse and a touchscreen, and now decides per
## event. The difference is what is being asked. That one asks "which pointer moved
## last", which only an event can answer. This one asks "is there a hardware
## keyboard in the room", and Godot exposes no API for it at all -- so the platform
## is the closest honest proxy, and phones and tablets are the platforms where the
## answer is reliably no.
##
## The mouse test is second and is a **fallback rather than the rule**, because
## `docs/MOBILE.md` lists "whether Android reports `FEATURE_MOUSE`" among the things
## nobody has checked on a device. If it does, an `and` between the two would make
## the overlay never appear on the one platform it exists for -- a silent no on a
## phone, which is the failure this whole feature is about. So the mouseless-touch
## case adds machines rather than removing them, and being wrong about it costs a
## visible control on a Windows touchscreen laptop instead of an unplayable scene on
## a phone.
##
## **`--touch-input` forces the whole path on**, and it is the flag to reach for
## rather than a debug toggle: it makes a desktop run behave like a phone *through
## the same code*, because the stick and the row are driven from ordinary mouse
## events -- which is what Godot's own emulation turns a finger into. A mouse drag is
## a swipe here for the same reason a finger drag is, and that is why there is one
## gesture path to test rather than two. `--touch-input=off` turns it off on a device.
static func enabled() -> bool:
	if _forced >= 0:
		return _forced == 1
	_forced = 0
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-input" or arg == "--touch-input=on":
			_forced = 1
		elif arg == "--touch-input=off":
			_forced = 2
	if _forced == 1:
		return true
	if _forced == 2:
		_forced = 0
		return false
	var mouseless_touch := DisplayServer.is_touchscreen_available() \
		and not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)
	_forced = 1 if (OS.has_feature("mobile") or mouseless_touch) else 0
	return _forced == 1


## Whether `--touch-input` is on the command line at all.
##
## `tools/key_overlay.gd` asserts it, so that a run which passes on a developer's
## touchscreen laptop cannot be mistaken for one that proved the flag.
static func forced_by_flag() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-input" or arg == "--touch-input=on":
			return true
	return false


## Force the overlay on or off, or hand the decision back to `enabled()`.
static func force(state: int) -> void:
	_forced = state


static func mode() -> Mode:
	return _mode


## Whether the stick is currently picked up and following the finger.
##
## Exposed because it is the one half of the pick-up a harness cannot infer from the
## outside: "the stick did not move" is also true of a pick-up that armed and was
## then dragged nowhere, so `tools/key_overlay.gd` asserts the *timer* rather than
## only its consequence.
static func picked_up() -> bool:
	return _moving


static func set_mode(to: Mode) -> void:
	if to == _mode:
		return
	_release_held()
	_mode = to


## Drop everything derived from the movie, leaving what the *player* set.
##
## The split is the point: `tools/key_overlay.gd` calls this to stand in for a room
## change and then asserts that the mode and the stick position came through it.
## Anything that ends up on the wrong side of this line is a preference that resets
## itself in the next room, which is the bug the statics exist to prevent.
static func forget() -> void:
	_movies.clear()
	_at_frame.clear()
	_at_frame_path = ""
	_end_gesture()


# ----------------------------------------------------------- what is on screen

## The frame's demand split into `{"stick": [...], "buttons": [...]}` -- the actions
## a direction can express, and everything else. Each entry is
## `{label, keycode, dir}`.
##
## An action counts as a direction if **any** of its alternates is an arrow, which is
## the same rule `classify` uses and for the same reason: Rating's arcade spells "up"
## as up-arrow-or-W, and a control that refused it because W is in the set would put
## a labelled letter where a direction belongs.
static func stick_actions(host) -> Dictionary:
	var out := {"stick": [], "buttons": [], "possible": false}
	if not enabled() or host._score == null:
		return out
	var d := demand_at(host, host._index)
	var shape := classify(d)
	if shape == Shape.NONE or shape == Shape.TEXT:
		# A scene with an editable field wants the system keyboard, which
		# `text_focus.gd` already raises when the field takes focus, and a row of
		# letter buttons over the top of it would be a worse keyboard in front of a
		# better one. Confirmed independently on `PIPDATA/ROULLETE.dir`, whose
		# `betfield1..5` (members 129, 131-134) carry the container's own editable
		# flag and whose `fieldkeydown` (member 149) reads digit codes 18-29 and
		# backspace 51: the movie ships no number buttons of its own -- `betclik1..6`
		# are chip bitmaps -- so the system keyboard is not a fallback there, it is
		# the only answer.
		return out
	if shape == Shape.ANY:
		# Nothing to label. The whole scene is "press something", so one button says
		# so and sends the key every such scene in this corpus is written around:
		# 46 scripts install `fromnow`, which skips a line of speech on code 49.
		out["buttons"].append({"label": "KEY", "keycode": KEY_SPACE, "dir": Vector2i.ZERO})
		return out

	var directions: Array = []
	var named: Array = []
	var ordered: Array = []
	for action in actions_of(d):
		var keycode := keycode_of(action)
		if keycode == KEY_NONE:
			continue
		var entry := {
			"label": label_of(action), "keycode": keycode, "dir": _direction_of(action),
		}
		ordered.append(entry)
		if entry["dir"] == Vector2i.ZERO:
			named.append(entry)
		else:
			directions.append(entry)

	# **Whether a stick is possible is a fact about the scene, not about the mode**,
	# and the two have to be answered separately or the chip becomes a control that
	# does nothing: in BUTTONS mode the directions are already in the row, so asking
	# "is the stick list empty" would say no stick is possible and hide the switch
	# back. `possible` is what `toggle_available` reads.
	out["possible"] = not directions.is_empty() \
		and (not STICK_NEEDS_EVERY_ACTION or named.is_empty())
	if out["possible"] and _mode == Mode.STICK:
		out["stick"] = directions
		out["buttons"] = named
	else:
		# The row carries everything, directions included, in the order
		# `actions_of` produced them -- so a scene reads the same left to right
		# whichever mode it is in.
		out["buttons"] = ordered
	return out


## Which way an action points, as a unit `Vector2i`, or zero when it is not a
## direction. Screen axes: y grows downward, so "down" is +1.
##
## **The two arrow tables are in different orders and that is the trap here.**
## `ARROW_CODES` is `[LEFT, RIGHT, DOWN, UP]` -- the Mac virtual codes 123-126 in
## their own numeric order -- and `ARROW_CHARS` is `[left, right, up, down]`, which
## is Director's documented substitution order for characters 28-31 (§8.3). Reading
## one index against the other list swaps up and down on a control that looks
## perfectly right, so each list is indexed against its own vector table.
static func _direction_of(action: Dictionary) -> Vector2i:
	const BY_CODE := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	const BY_CHAR := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for token in action:
		var t := str(token)
		if t.begins_with("code:"):
			var i := ARROW_CODES.find(int(t.substr(5)))
			if i >= 0:
				return BY_CODE[i]
		else:
			var j := ARROW_CHARS.find(t.substr(5))
			if j >= 0:
				return BY_CHAR[j]
	return Vector2i.ZERO


## Is the stick on screen for this frame?
static func stick_available(host) -> bool:
	return not (stick_actions(host)["stick"] as Array).is_empty()


## Is the mode chip on screen? Only where there is something to switch *between* --
## a scene with no direction in it has one answer, and a chip offering the other
## would be a control that does nothing.
static func toggle_available(host) -> bool:
	return enabled() and bool(stick_actions(host)["possible"])


## Where the stick's centre is, in stage coordinates.
static func stick_centre(host) -> Vector2:
	var stage: Vector2i = host.stage_size()
	if _stick_norm.x < 0.0:
		# Default: bottom-left, because the row of buttons is centred or right-
		# aligned and the two must not overlap at any stage size, and because a
		# player holding a phone in landscape has a left thumb free.
		return Vector2(STICK_RADIUS + MARGIN, float(stage.y) - STICK_RADIUS - MARGIN)
	return Vector2(_stick_norm.x * float(stage.x), _stick_norm.y * float(stage.y))


## The buttons for the current frame, as `{rect, label, keycode}`, along the bottom.
##
## Empty for a frame that needs no key, which is 88.9% of the corpus's scenes -- and
## that is the point: this is not a permanent control panel, it is the answer to
## "what does *this* scene need", and a scene that needs nothing shows nothing.
##
## Centred when it is the only control and right-aligned when the stick is also up,
## so the two never overlap however many buttons there are.
static func buttons(host) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var split := stick_actions(host)
	var wanted: Array = split["buttons"]
	if wanted.is_empty():
		return out

	var stage: Vector2i = host.stage_size()
	var width := wanted.size() * BUTTON.x + (wanted.size() - 1) * GAP
	var top := float(stage.y) - BUTTON.y - MARGIN
	var left := (float(stage.x) - width) * 0.5
	if not (split["stick"] as Array).is_empty():
		left = float(stage.x) - width - MARGIN
	for i in wanted.size():
		out.append({
			"rect": Rect2(left + i * (BUTTON.x + GAP), top, BUTTON.x, BUTTON.y),
			"label": wanted[i]["label"],
			"keycode": wanted[i]["keycode"],
		})
	return out


## The mode chip, above the button row and right-aligned so it never lands on the
## stick.
static func toggle_rect(host) -> Rect2:
	var stage: Vector2i = host.stage_size()
	return Rect2(
		float(stage.x) - TOGGLE.x - MARGIN,
		float(stage.y) - BUTTON.y - MARGIN - TOGGLE.y - GAP,
		TOGGLE.x, TOGGLE.y)


# ------------------------------------------------------------------ the gesture

## True while a finger is down inside something the overlay owns.
static var _down := false
## Where it went down, and where it is now, in stage coordinates.
static var _origin := Vector2.ZERO
static var _at := Vector2.ZERO
static var _down_ms := 0
## True once the finger has been held still on the stick long enough to pick it up.
static var _moving := false
## Which key the stick currently has held, which way, and when the next repeat is due.
static var _held: Key = KEY_NONE
static var _held_dir := Vector2i.ZERO
static var _repeat_at := 0


## A press or a release. True when the overlay took it, which stops the click
## reaching the movie underneath.
##
## **Only a press inside a control is claimed.** A press anywhere else is the
## movie's, which is what keeps every hotspot in an arcade reachable while a stick is
## on screen -- and it is why the stick is a drawn object with an area rather than an
## invisible swipe zone over the whole stage. An invisible zone has to choose between
## eating every click and stealing a press it has already passed on, and there is no
## third option: by the time a swipe is recognisable the press is long gone.
static func pointer(host, pressed: bool, at: Vector2) -> bool:
	if not enabled():
		return false
	if not pressed:
		if not _down:
			return false
		_end_gesture()
		return true

	if toggle_available(host) and toggle_rect(host).has_point(at):
		set_mode(Mode.BUTTONS if _mode == Mode.STICK else Mode.STICK)
		return true

	for row in buttons(host):
		if (row["rect"] as Rect2).has_point(at):
			_tap(row["keycode"])
			return true

	if stick_available(host) and stick_centre(host).distance_to(at) <= STICK_RADIUS:
		_down = true
		_origin = at
		_at = at
		_down_ms = Time.get_ticks_msec()
		_moving = false
		return true
	return false


## Pointer motion. True while a gesture owns it, so the movie sees no drag it did not
## start -- a moveable sprite (§7.6) must not follow a finger that is steering.
static func motion(host, at: Vector2) -> bool:
	if not enabled() or not _down:
		return false
	_at = at
	if _moving:
		var stage: Vector2i = host.stage_size()
		# Clamped so the stick cannot be dragged off the stage and lost, which on a
		# phone would take a restart to undo.
		_stick_norm = Vector2(
			clampf(at.x, STICK_RADIUS, float(stage.x) - STICK_RADIUS) / float(stage.x),
			clampf(at.y, STICK_RADIUS, float(stage.y) - STICK_RADIUS) / float(stage.y))
		return true
	_aim(host)
	return true


## Per-frame work: the auto-repeat, and the hold that arms a pick-up.
##
## Called from `draw`, which asks for the next paint while anything is live -- a
## preview holding on `go to the frame` repaints only when asked, and a stick whose
## repeat depended on the movie animating would steer in some rooms and not others.
## Public so `tools/key_overlay.gd` can drive it after awaiting real frames.
static func tick(host) -> void:
	if not enabled():
		return
	var now := Time.get_ticks_msec()
	if _down and not _moving and _held == KEY_NONE \
			and _origin.distance_to(_at) <= DEAD_ZONE and now - _down_ms >= PICKUP_MS:
		# **Held still, so this is a pick-up and not a drive.** The two cannot be
		# confused: a drive commits the moment the finger leaves the dead zone and
		# sets `_held`, and this arm requires both that it has not and that the
		# finger is still inside. They are separated in time, and the separation is
		# enforced here rather than hoped for.
		_moving = true
	if _held != KEY_NONE and now >= _repeat_at:
		_send(_held, true)
		_send(_held, false)
		_repeat_at = now + REPEAT_MS


## Commit, change or drop the direction the stick is pushed in.
static func _aim(host) -> void:
	var offset := _at - stick_centre(host)
	if offset.length() <= DEAD_ZONE:
		_release_held()
		return
	# Snapped to four by whichever axis dominates, because the keys are four and a
	# diagonal that sent two of them would move a character twice as fast on the
	# diagonal -- the classic eight-way-on-a-four-way-input bug.
	var dir := Vector2i(signi(int(offset.x)), 0) if absf(offset.x) >= absf(offset.y) \
		else Vector2i(0, signi(int(offset.y)))
	if dir == _held_dir:
		return
	var wanted: Key = KEY_NONE
	for entry in stick_actions(host)["stick"]:
		if (entry as Dictionary)["dir"] == dir:
			wanted = (entry as Dictionary)["keycode"]
			break
	if wanted == KEY_NONE:
		# The scene has no key for that way. Nothing is sent and whatever was held is
		# dropped, so pushing into a wall stops the character rather than leaving it
		# walking in the last direction that did work.
		_release_held()
		return
	_release_held()
	_held = wanted
	_held_dir = dir
	_send(_held, true)
	_repeat_at = Time.get_ticks_msec() + REPEAT_FIRST_MS


static func _release_held() -> void:
	if _held == KEY_NONE:
		return
	_send(_held, false)
	_held = KEY_NONE
	_held_dir = Vector2i.ZERO


static func _end_gesture() -> void:
	_release_held()
	_down = false
	_moving = false


## A button: one whole press and release, because Director has both (§8.1) and 205
## sites across the corpus set a `keyUpScript`.
static func _tap(keycode: Key) -> void:
	_send(keycode, true)
	_send(keycode, false)


## **Through `Input.parse_input_event`, not by calling the dispatch directly**, and
## that is the load-bearing choice here: the synthesised event then takes the same
## path a real key takes -- `_input`, the `_lingo_breathing` queue,
## `InputRouter.key_event`, the modifier check, the widget arm, `the key`/`the
## keyCode`, the five-tier chain. A shortcut into `_dispatch_key` would skip the
## queue, and a key delivered while a Lingo handler is on the stack is exactly the
## re-entrancy that queue exists to prevent. Same argument `tools/touch_input.gd`
## makes for feeding touch through `Input` rather than calling the router.
static func _send(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = _unicode_for(keycode)
	event.pressed = pressed
	Input.parse_input_event(event)


## The character a synthesised key should carry, so `the key` answers what the script
## compares against. `director_keys.char_for` reads `event.unicode`, and an event
## built in code has none unless it is put there.
static func _unicode_for(keycode: Key) -> int:
	var name := OS.get_keycode_string(keycode)
	if name.length() == 1:
		return name.to_lower().unicode_at(0)
	if keycode == KEY_SPACE:
		return 32
	return 0


# -------------------------------------------------------------------- the paint

## Draw whatever this frame has. Called from `_paint` **above** the debug gate,
## because this is a player affordance and not a developer one -- a release build
## with the debug layer off still has a player who cannot reach a keyboard.
static func draw(host, _stage: Vector2i) -> void:
	if not enabled():
		return
	tick(host)
	var split := stick_actions(host)
	if not (split["stick"] as Array).is_empty():
		_draw_stick(host, split["stick"])
	for row in buttons(host):
		_draw_button(host, row["rect"], str(row["label"]))
	if toggle_available(host):
		_draw_button(host, toggle_rect(host), "STICK" if _mode == Mode.STICK else "KEYS")
	# A held direction repeats on a clock and a pick-up arms on one, so the next paint
	# has to be asked for or both stop the moment the movie does. Same reason
	# `Toast.draw` asks, and confined the same way -- only while something is live.
	if _down or _held != KEY_NONE:
		host.queue_redraw()


static func _draw_stick(host, entries: Array) -> void:
	var centre := stick_centre(host)
	# **The ring thickens while a pick-up counts down**, and that is the whole
	# discoverability argument for the gesture: it announces itself before it
	# completes, so a player who rests a thumb on the stick sees something happen and
	# can let go, and a player who wanted to move it gets told it worked.
	var arming := 0.0
	if _down and not _moving and _held == KEY_NONE:
		arming = clampf(float(Time.get_ticks_msec() - _down_ms) / float(PICKUP_MS), 0.0, 1.0)
	_disc(host, centre, STICK_RADIUS, Color(0, 0, 0, 0.40))
	_ring(host, centre, STICK_RADIUS, Color(1, 1, 1, 0.45 + 0.35 * arming), 1.0 + 2.5 * arming)
	if _moving:
		# Picked up: a second ring says so, because "the control is following your
		# finger" and "the control is being pushed" look identical otherwise.
		_ring(host, centre, STICK_RADIUS + 5.0, Color(1, 1, 1, 0.8), 1.0)

	# One tick per direction the scene actually has, so the stick shows what it can do
	# rather than a generic four-way that lies about two of them. `arcade1.dir` has
	# three, and a fourth tick there would be a control that does nothing.
	for entry in entries:
		var dir: Vector2i = (entry as Dictionary)["dir"]
		var to := centre + Vector2(dir) * (STICK_RADIUS - 9.0)
		var lit := dir == _held_dir
		_disc(host, to, 4.0 if lit else 2.5, Color(1, 1, 1, 0.95 if lit else 0.5))

	var knob := centre
	if _held != KEY_NONE:
		knob = centre + Vector2(_held_dir) * (STICK_RADIUS - KNOB_RADIUS - 2.0)
	_disc(host, knob, KNOB_RADIUS, Color(1, 1, 1, 0.28))
	_ring(host, knob, KNOB_RADIUS, Color(1, 1, 1, 0.75), 1.0)


## A filled disc and an unfilled ring.
##
## **Not in `director_paint.gd`, deliberately.** That file owns exactly the four
## primitives the *stage* draws -- `rect`, `text`, `texture`, `texture_rect` -- and
## its header explains that each is a pass-through to the `RenderingServer` call
## `CanvasItem` would make, so the two entry points cannot drift. A circle is not a
## Director primitive; it is this control's chrome. Adding two more functions to a
## shared file for one caller is how a paint helper becomes a junk drawer, and it
## would also put a shape the reference has no equivalent for into the file that is
## meant to mirror the reference.
static func _disc(host, centre: Vector2, radius: float, color: Color) -> void:
	RenderingServer.canvas_item_add_circle(host.get_canvas_item(), centre, radius, color)


static func _ring(host, centre: Vector2, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		points.append(centre + Vector2(cos(a), sin(a)) * radius)
	RenderingServer.canvas_item_add_polyline(
		host.get_canvas_item(), points, PackedColorArray([color]), width, true)


static func _draw_button(host, rect: Rect2, label: String) -> void:
	var font := ThemeDB.fallback_font
	Paint.rect(host, rect, Color(0, 0, 0, 0.55), true)
	Paint.rect(host, rect, Color(1, 1, 1, 0.8), false, 1.0)
	# The label is centred in the button rather than at a fixed inset, and it shrinks
	# rather than overflowing: "Up/W" and "Backspace" both come out of `label_of`, and
	# a button whose text runs off the edge is a button nobody can identify. Measured
	# through the font, because guessing an advance width per character is what puts a
	# two-glyph label off-centre.
	var size := 12
	while size > 7 and font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x - 6.0:
		size -= 1
	var metrics := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := rect.position + Vector2(
		maxf(3.0, (rect.size.x - metrics.x) * 0.5),
		(rect.size.y + float(size)) * 0.5 - 1.0)
	Paint.text(host, font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(1, 1, 1, 0.95))


