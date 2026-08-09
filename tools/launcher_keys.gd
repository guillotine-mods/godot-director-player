extends SceneTree
## What the launcher refuses to store as a preview binding.
##
##   godot --headless --path . --script tools/launcher_keys.gd
##
## `DebugKeys.load_config` answers a bad binding with `push_warning`, and a
## warning in a log is not a UI. It is less than that here: the overlay is not
## read at all in a headless process, so **no gate ever sees what the launcher
## writes**. The checks have to be in the editor, and this is what asserts they
## are the same checks.
##
## The third is the one that matters and the one a constant gets wrong. The
## preview shares a keyboard with the movie, and Director gave the movie all of
## it, so "is this key free" is a question about the *games* -- answered by
## reading their scripts, over every root, exactly as `tools/debug_bindings.gd`
## does. `tools/lib/key_sites.gd` records what happened last time that answer
## lived in a list: it was swept from `reference/lingo/`, which holds one title
## of six, and put the pause on F10, which Rating tests at 48 sites.

const Harness := preload("res://tools/lib/harness.gd")
const BindingRules := preload("res://scenes/launcher/binding_rules.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")


func _init() -> void:
	var h := Harness.new()

	var case := "a name that is not a key is refused"
	h.begin(case)
	h.check("'F5' is a key", BindingRules.named("F5") != KEY_NONE)
	h.check("'Shift+F5' is a key", BindingRules.named("Shift+F5") != KEY_NONE)
	h.check("'Banana' is not", BindingRules.named("Banana") == KEY_NONE)
	h.check("'' is not", BindingRules.named("") == KEY_NONE)
	h.complete(case)

	case = "two commands on one key is refused"
	h.begin(case)
	var bindings := {"step_back": "F5", "step_forward": "F6"}
	h.check("F6 collides with step_forward",
		BindingRules.collision(bindings, "step_back", "F6") == "step_forward",
		BindingRules.collision(bindings, "step_back", "F6"))
	h.check("F7 collides with nothing",
		BindingRules.collision(bindings, "step_back", "F7") == "")
	# Rebinding a command to the key it already holds is not a collision with
	# itself, or no binding could ever be re-saved unchanged.
	h.check("a command does not collide with itself",
		BindingRules.collision(bindings, "step_back", "F5") == "")
	h.complete(case)

	case = "a key some title's scripts test is refused"
	h.begin(case)
	var tested := BindingRules.tested_codes()
	if not h.check("the corpus yields tested key codes", not tested.is_empty(),
			"%d code(s)" % tested.size()):
		h.complete(case)
		quit(h.finish("what the launcher refuses to bind"))
		return
	# F10 is Mac code 109 and Rating tests it at 48 sites. It is the reason the
	# pause is on F9, and it is the case a hand-written list got wrong.
	h.check("F10 is claimed", not BindingRules.claimed_by("F10").is_empty(),
		", ".join(BindingRules.claimed_by("F10")))
	h.check("Escape is claimed", not BindingRules.claimed_by("Escape").is_empty(),
		", ".join(BindingRules.claimed_by("Escape")))
	h.check("PageDown is free", BindingRules.claimed_by("PageDown").is_empty(),
		", ".join(BindingRules.claimed_by("PageDown")))
	# `fromnow` is installed by 46 scripts and tests `the keyCode = "49"` --
	# space, measured, not the character. It is why the pause moved off space
	# long before the F-key band existed.
	h.check("Space is claimed", not BindingRules.claimed_by("Space").is_empty(),
		", ".join(BindingRules.claimed_by("Space")))
	h.complete(case)

	# The second half of the rule. `director_game.cfg` states the predicate as
	# "types no character *and* is a key no title is measured to test", and
	# `tools/debug_bindings.gd` asserts both per binding. A launcher checking
	# only the keyCode accepts a plain letter.
	case = "a key that types a character some title tests is refused"
	h.begin(case)
	var chars := BindingRules.tested_chars()
	if not h.check("the corpus yields tested characters", not chars.is_empty(),
			"%d character(s)" % chars.size()):
		h.complete(case)
		quit(h.finish("what the launcher refuses to bind"))
		return
	h.check("F9 types nothing", BindingRules.typed_in("F9").is_empty(),
		", ".join(BindingRules.typed_in("F9")))
	h.check("PageDown types nothing", BindingRules.typed_in("PageDown").is_empty(),
		", ".join(BindingRules.typed_in("PageDown")))
	# `the key = "q"` in rating -- a literal character comparison, which is the
	# only thing a character test can be measured from. This is the assertion
	# that fails if `_event` forgets `unicode`: without it every letter answers
	# "" and this case would pass by measuring nothing.
	h.check("Q is claimed by what it types",
		not BindingRules.typed_in("Q").is_empty(),
		", ".join(BindingRules.typed_in("Q")))
	h.complete(case)

	# And the shipped map has to survive both halves, or the launcher would
	# refuse to store the bindings the port ships with.
	case = "every shipped binding passes the rules the launcher enforces"
	h.begin(case)
	var refused: Array[String] = []
	for command in DebugKeys.DEFAULTS:
		var name := str(DebugKeys.DEFAULTS[command])
		if name == "":
			continue
		if not BindingRules.claimed_by(name).is_empty():
			refused.append("%s on %s: keyCode tested by %s"
				% [command, name, ", ".join(BindingRules.claimed_by(name))])
		if not BindingRules.typed_in(name).is_empty():
			refused.append("%s on %s: types a character tested by %s"
				% [command, name, ", ".join(BindingRules.typed_in(name))])
	h.check("all %d shipped binding(s) pass" % DebugKeys.DEFAULTS.size(),
		refused.is_empty(), "; ".join(refused))
	h.complete(case)

	quit(h.finish("what the launcher refuses to bind"))
