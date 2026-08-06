extends RefCounted
## Godot key codes to the Macintosh virtual key codes `the keyCode` reports.
##
## Title-agnostic. Nothing here knows what game is loaded.
##
## Director on Windows still reports **Mac** virtual key codes for `the keyCode`,
## because the language was defined on the Mac and the Windows player translates
## back. They are positional and bear no relation to ASCII: space is 49, the
## arrows are 123 to 126, and the letter codes follow the physical layout of a
## 1984 Macintosh keyboard rather than the alphabet. `the key` is different again
## — it is the *character* produced, which is what a script compares against a
## letter.
##
## What this corpus actually tests, from a sweep of `reference/lingo/`:
##
##   49            space, 20+ sites   — stops sound channel 1, cutting speech
##   123 124 125 126  arrows, 30+ sites — menu and map navigation
##   2 13 14       three letter keys, paired with an arrow in the same condition
##
## The map is complete rather than trimmed to those, because a keyboard map that
## covers only the keys someone noticed is the kind of thing that silently breaks
## the next room.

## Space. Named because it is the one code worth recognising on sight: it is how
## every line of speech in this game is skipped.
const SPACE := 49

const LEFT := 123
const RIGHT := 124
const DOWN := 125
const UP := 126

## Godot keycode -> Mac virtual key code.
const MAC_CODES := {
	# Letters, in the Mac's positional order.
	KEY_A: 0, KEY_S: 1, KEY_D: 2, KEY_F: 3, KEY_H: 4, KEY_G: 5,
	KEY_Z: 6, KEY_X: 7, KEY_C: 8, KEY_V: 9, KEY_B: 11, KEY_Q: 12,
	KEY_W: 13, KEY_E: 14, KEY_R: 15, KEY_Y: 16, KEY_T: 17,
	KEY_O: 31, KEY_U: 32, KEY_I: 34, KEY_P: 35, KEY_L: 37, KEY_J: 38,
	KEY_K: 40, KEY_N: 45, KEY_M: 46,
	# Digits, which are also not in order.
	KEY_1: 18, KEY_2: 19, KEY_3: 20, KEY_4: 21, KEY_5: 23, KEY_6: 22,
	KEY_7: 26, KEY_8: 28, KEY_9: 25, KEY_0: 29,
	# Punctuation.
	KEY_EQUAL: 24, KEY_MINUS: 27, KEY_BRACKETRIGHT: 30, KEY_BRACKETLEFT: 33,
	KEY_APOSTROPHE: 39, KEY_SEMICOLON: 41, KEY_BACKSLASH: 42, KEY_COMMA: 43,
	KEY_SLASH: 44, KEY_PERIOD: 47, KEY_QUOTELEFT: 50,
	# Controls.
	KEY_ENTER: 36, KEY_KP_ENTER: 76, KEY_TAB: 48, KEY_SPACE: SPACE,
	KEY_BACKSPACE: 51, KEY_ESCAPE: 53, KEY_DELETE: 117,
	KEY_HOME: 115, KEY_END: 119, KEY_PAGEUP: 116, KEY_PAGEDOWN: 121,
	KEY_LEFT: LEFT, KEY_RIGHT: RIGHT, KEY_DOWN: DOWN, KEY_UP: UP,
	# Function keys.
	KEY_F1: 122, KEY_F2: 120, KEY_F3: 99, KEY_F4: 118, KEY_F5: 96,
	KEY_F6: 97, KEY_F7: 98, KEY_F8: 100, KEY_F9: 101, KEY_F10: 109,
	KEY_F11: 103, KEY_F12: 111,
}


## The Mac virtual key code for a Godot key event, or -1 when unmapped.
##
## -1 rather than 0, because 0 is a real code — it is the `A` key. Returning 0
## for "no idea" would make every unmapped key look like a press of `A`.
static func code_for(event: InputEventKey) -> int:
	if event == null:
		return -1
	return int(MAC_CODES.get(event.keycode, -1))


## The character `the key` reports: what the keystroke typed, not where it sits.
##
## Director answers an empty string for keys that produce no character, which is
## what a script comparing `the key` to a letter expects — an arrow press must
## not compare equal to anything.
static func char_for(event: InputEventKey) -> String:
	if event == null:
		return ""
	var unicode := event.unicode
	if unicode >= 32 and unicode != 127:
		return char(unicode)
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			return "\r"
		KEY_TAB:
			return "\t"
		KEY_BACKSPACE:
			return char(8)
	return ""
