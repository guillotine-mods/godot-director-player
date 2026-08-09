extends SceneTree
## The tracked config, the machine-local overlay, and which one wins.
##
##   godot --headless --path . --script tools/game_config.gd
##
## Four sites used to load `director_game.cfg` for themselves. They ask
## `director/game_config.gd` now, and this is what that file promises them: the
## overlay wins per key, a key it does not carry falls through to the tracked
## file, an absent or unreadable overlay changes nothing, under `--headless`
## the real overlay is not consulted at all, and the real overlay is never
## offered to a tracked path other than the real one.
##
## That last one is what keeps the other 62 entries honest. The overlay is one
## file per machine, shared by every process on it, which is the same shape as
## the failure `gate.sh` removed when it stopped rewriting the `root` line: two
## runs at once had each other's corpus swapped out mid-run. Keying on the
## display server means a harness cannot read a human's overlay even by
## forgetting a flag, and neither can an ad-hoc `godot --headless --script` run.
##
## Title-agnostic: it writes its own files and names no game.

const Harness := preload("res://tools/lib/harness.gd")
const GameConfig := preload("res://director/game_config.gd")

const SCRATCH_TRACKED := "user://gate_game_config_tracked.cfg"
const SCRATCH_OVERLAY := "user://gate_game_config_overlay.cfg"
const SCRATCH_BROKEN := "user://gate_game_config_broken.cfg"


func _init() -> void:
	var h := Harness.new()
	_write(SCRATCH_TRACKED, "[game]\nroot = \"res://games/piposh2\"\nboot_movie = \"strtgame.dir\"\ncodepage = \"mac_hebrew\"\n\n[display]\naspect = \"native_4_3\"\n")
	_write(SCRATCH_OVERLAY, "[game]\nroot = \"res://games/rating\"\n")
	_write(SCRATCH_BROKEN, "this is not a config file\n[[[\n")

	var case := "the overlay wins per key and falls through for the rest"
	h.begin(case)
	GameConfig.invalidate()
	var merged := GameConfig.merged(SCRATCH_TRACKED, SCRATCH_OVERLAY)
	h.check("the overlay's root wins",
		str(merged.get_value("game", "root", "")) == "res://games/rating",
		str(merged.get_value("game", "root", "<missing>")))
	h.check("a key the overlay does not carry falls through",
		str(merged.get_value("game", "boot_movie", "")) == "strtgame.dir",
		str(merged.get_value("game", "boot_movie", "<missing>")))
	h.check("a whole section the overlay does not carry falls through",
		str(merged.get_value("display", "aspect", "")) == "native_4_3",
		str(merged.get_value("display", "aspect", "<missing>")))
	h.check("the tracked view is not touched by the overlay",
		str(GameConfig.tracked(SCRATCH_TRACKED).get_value("game", "root", "")) == "res://games/piposh2",
		str(GameConfig.tracked(SCRATCH_TRACKED).get_value("game", "root", "<missing>")))
	h.complete(case)

	case = "an absent or unreadable overlay changes nothing"
	h.begin(case)
	GameConfig.invalidate()
	var none := GameConfig.merged(SCRATCH_TRACKED, "user://gate_game_config_absent.cfg")
	h.check("an absent overlay leaves the tracked answer",
		str(none.get_value("game", "root", "")) == "res://games/piposh2",
		str(none.get_value("game", "root", "<missing>")))
	GameConfig.invalidate()
	var broken := GameConfig.merged(SCRATCH_TRACKED, SCRATCH_BROKEN)
	h.check("an unreadable overlay is ignored rather than fatal",
		str(broken.get_value("game", "root", "")) == "res://games/piposh2",
		str(broken.get_value("game", "root", "<missing>")))
	h.check("a missing tracked file reports absent",
		not GameConfig.exists("user://gate_game_config_nothing.cfg"))
	h.check("and a missing tracked file still answers the default",
		str(GameConfig.merged("user://gate_game_config_nothing.cfg", "").get_value(
			"game", "root", "fallback")) == "fallback")
	h.complete(case)

	# `wants_overlay` is asserted directly, as its own truth table, rather than
	# only through `merged()`. Every route through `merged()` passes
	# `overlay_applies()` for `applies`, which is false under `--headless` --
	# this process included -- so a check built on `merged()` alone can never
	# observe the path term below: it never gets past `applies` being false,
	# and the path guard could be deleted from `_build` without any such check
	# going dark. Forcing `applies` both ways here is the only way a headless
	# gate can catch that deletion.
	case = "the real overlay only ever wants the real tracked config"
	h.begin(case)
	h.check("the real tracked path wants it, when it applies",
		GameConfig.wants_overlay(GameConfig.TRACKED_PATH, true))
	h.check("a scratch tracked path does not, even when it applies",
		not GameConfig.wants_overlay(SCRATCH_TRACKED, true))
	h.check("the real tracked path does not, when it does not apply",
		not GameConfig.wants_overlay(GameConfig.TRACKED_PATH, false))
	h.check("a scratch tracked path does not either",
		not GameConfig.wants_overlay(SCRATCH_TRACKED, false))
	h.complete(case)

	# The rule the other 62 entries depend on. This process *is* headless, so
	# asking for the real overlay must not consult it -- asserted by writing one
	# that would be obvious if it were read. Two separate guards gate the read,
	# and each is checked on its own below rather than folded into one: headless
	# alone must block it, and so must asking under a path that is not the real
	# tracked file, because `overlay_applies()` cannot tell that path from this
	# one -- it only knows whether there is a display.
	case = "under --headless the real overlay is not consulted"
	h.begin(case)
	h.check("this run is headless", DisplayServer.get_name() == "headless",
		DisplayServer.get_name())
	h.check("so the overlay does not apply", not GameConfig.overlay_applies())
	# **The real overlay belongs to whoever is sitting here**, and this is the
	# one gate entry that has to touch it -- the rule under test is about that
	# exact path, so a scratch file would assert nothing. It is read back first
	# and put back after: `bash gate.sh` is the command this repository tells
	# you to run constantly, and a gate that silently wipes your launcher
	# settings would be a worse bug than the one it is guarding.
	var had := FileAccess.file_exists(GameConfig.OVERLAY_PATH)
	var saved := FileAccess.get_file_as_string(GameConfig.OVERLAY_PATH) if had else ""
	var planted := ConfigFile.new()
	planted.set_value("game", "root", "res://games/should-never-be-read")
	planted.save(GameConfig.OVERLAY_PATH)
	GameConfig.invalidate()
	# Exercised against the real `TRACKED_PATH` itself, so the path guard added
	# below is trivially satisfied here and cannot be what makes this pass --
	# only `overlay_applies()` (headless) is left to be doing the work.
	var expected_root := str(GameConfig.tracked(GameConfig.TRACKED_PATH).get_value(
		"game", "root", "<missing>"))
	var real := GameConfig.merged(GameConfig.TRACKED_PATH, "")
	h.check("a planted overlay is not read against the real tracked config",
		str(real.get_value("game", "root", "")) == expected_root
			and str(real.get_value("game", "root", "")) != "res://games/should-never-be-read",
		str(real.get_value("game", "root", "<missing>")))
	# A second guard, through the real entry point rather than `wants_overlay`
	# directly: the implicit overlay is only ever offered to the real tracked
	# file, because `overlay_applies()` cannot tell a harness's own `user://`
	# fixture from that path -- it only knows whether there is a display.
	# `fast_forward.gd` and `debug_bindings.gd` each merge such a fixture
	# through the same default argument `DebugKeys.load_config` always passes.
	#
	# This process is headless, so `overlay_applies()` alone already blocks the
	# read before the path is ever compared -- this check cannot fail here, the
	# same as the one above it, and covers the wiring through `merged()` rather
	# than the rule. The rule itself -- that a change dropping the path guard
	# from `_build` would be caught -- is what "the real overlay only ever
	# wants the real tracked config" above asserts directly, headless, by
	# calling `wants_overlay` with `applies` forced to `true`. A windowed run
	# of this same script (`godot --path . --script tools/game_config.gd`, no
	# `--headless`) corroborates both: there `overlay_applies()` is true, the
	# check above correctly flips to FAIL (the real path *should* pick up the
	# planted overlay when windowed, and does), and this one still holds -- the
	# scratch fixture reads its own `res://games/piposh2`, not the planted
	# `should-never-be-read`. The overlay planted above is still in place, so
	# this reuses it rather than planting a second one.
	GameConfig.invalidate()
	var scratch := GameConfig.merged(SCRATCH_TRACKED, "")
	h.check("a scratch tracked path never gets the implicit overlay",
		str(scratch.get_value("game", "root", "")) == "res://games/piposh2",
		str(scratch.get_value("game", "root", "<missing>")))
	if had:
		_write(GameConfig.OVERLAY_PATH, saved)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameConfig.OVERLAY_PATH))
	GameConfig.invalidate()
	h.check("the overlay this machine had is back as it was",
		FileAccess.file_exists(GameConfig.OVERLAY_PATH) == had
			and (not had or FileAccess.get_file_as_string(GameConfig.OVERLAY_PATH) == saved))
	h.complete(case)

	for path in [SCRATCH_TRACKED, SCRATCH_OVERLAY, SCRATCH_BROKEN]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameConfig.invalidate()
	quit(h.finish("the tracked config, the overlay, and which one wins"))


func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()
