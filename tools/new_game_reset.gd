extends SceneTree
## Does a New Game actually reset the tables the game schedules itself from?
##
##   godot --headless --script tools/new_game_reset.gd -- --root rating --boot NAVIGATE.dir
##
## `rating` keeps its story schedule in two Director fields and resets them by
## copying one over the other. `NAVIGATE.dir`'s `initDemo`, called from the
## `exitFrame` of the movie's first frame:
##
##     put field "timebaseinit" of castLib "panel.cst" into field "timebasebackup" of castLib "panel.cst"
##     put field "Guestbaseinit" of castLib "panel.cst" into field "Guestbasebackup" of castLib "panel.cst"
##     put "0,0,0,...,0" into line 2 of field "inventorylist" of castLib "panel.cst"
##
## `timebasebackup` is what decides where the player is sent and which people are
## where: `Panel.cst`'s `checkroom` reads `item ITEMKEEPER of line TIMEKEEPER` of
## it and `go to movie` there, and `NAVIGATE`'s reception hotspot reads `item 3`
## of the same line to choose between `therecept`, `explain`, `newsys`, `newans`
## and `newinf`. So a `timebasebackup` that still holds a played session's
## schedule is a game that starts partway through its own story.
##
## That is not hypothetical for this title. Director's `saveMovie` writes fields
## back into the container, which is how this game saves, so the `Panel.cst` on
## the disc carries whatever the authors last played — `bugs.md` 54 measured the
## shipped `inventorylist` as already having its first item collected. The
## authored text being dirty is exactly why the reset has to work.
##
## Asserts the player-visible invariant: after a New Game the three tables read
## as their init copies, not as the shipped text. It compares the *fields*, so it
## cannot pass by a setter agreeing with a getter — the init member and the
## backup member are different members, and one is the authored file.
##
## Boots the real player and awaits real frames, because `initDemo` is reached
## through an `exitFrame` and a synthetic tick loop does not run the score.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## init member -> the member it must have been copied into.
const RESET_PAIRS := {
	"timebaseinit": "timebasebackup",
	"guestbaseinit": "guestbasebackup",
}


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	if preview.get("_score") == null:
		print("no score loaded — pass --root and --boot")
		quit(1)
		return

	# Far enough for frame 1's `exitFrame` to have run and for the `go` at the end
	# of the init chain to have settled. Real frames: `initDemo` is only reachable
	# through the score.
	for i in Args.number(args, "steps", 24):
		preview.call("_advance")
		await process_frame

	h.begin("a New Game resets the tables the story schedules itself from")

	for init_name in RESET_PAIRS:
		var backup_name: String = RESET_PAIRS[init_name]
		var init_text := str(preview.call("lingo_field", init_name, "panel.cst"))
		var backup_text := str(preview.call("lingo_field", backup_name, "panel.cst"))
		h.check("`%s` is not empty, so the comparison means something" % init_name,
			init_text.strip_edges() != "", "%d chars" % init_text.length())
		h.check("`%s` was copied into `%s`" % [init_name, backup_name],
			init_text == backup_text,
			"init %d chars, backup %d chars, %s" % [
				init_text.length(), backup_text.length(),
				"identical" if init_text == backup_text else "DIFFERENT"])

	# The have-list, reset by a literal rather than by an init member — which is
	# why `bugs.md` 54 searched seven containers for an `inventorylistinit` and
	# found none. Every item must read 0: the authored text ships with item 1
	# already collected.
	var inventory := str(preview.call("lingo_field", "inventorylist", "panel.cst"))
	var lines := inventory.split("\r") if inventory.contains("\r") else inventory.split("\n")
	h.check("`inventorylist` has a second line to reset", lines.size() >= 2,
		"%d line(s)" % lines.size())
	if lines.size() >= 2:
		var items := str(lines[1]).split(",")
		var collected: Array = []
		for i in items.size():
			if str(items[i]).strip_edges() != "0":
				collected.append("item %d = '%s'" % [i + 1, str(items[i]).strip_edges()])
		h.check("nothing is collected at the start of a New Game",
			collected.is_empty(),
			"%d item(s), %s" % [items.size(),
				"all 0" if collected.is_empty() else ", ".join(collected)])

	h.complete("a New Game resets the tables the story schedules itself from")
	quit(h.finish("the New Game reset of rating's story tables"))
