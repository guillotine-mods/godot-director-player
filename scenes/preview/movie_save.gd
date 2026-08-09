extends RefCounted
## `saveMovie` — deciding what a save writes, and where.
##
## The byte-level work is `director/director_writer.gd`; this is the half that
## knows about the *player*. Two questions, and both were the bug:
##
## **What changed.** A script's `put x into field "y"` does not touch the
## container -- it lands in the preview's override table, keyed by the cast's
## file and the member number (`text_art.gd:key_for`). So a save is exactly the
## set of overrides whose key names the container being written, turned back into
## `STXT` payloads. Nothing else in the movie is touched, which is what makes
## this safe to point at a game's own files: a `saveMovie` writes the fields the
## movie just wrote and not one byte more.
##
## **Where it goes.** Director resolved a `saveMovie` path like every other file
## reference, so this does too, through `DirectorPaths`. `savepath &
## "hezsave.dir"` therefore lands on the game's own `HEZSAVE.DIR` however
## `savepath` came out, which is the point: the movie reopens that file two
## statements later (`go("doload", savepath & "hezsave.dir")`) and reads its
## fields back. A save written anywhere else is a save the game cannot see.
##
## **Why the container is closed around the write.** The movie being saved is
## usually the movie playing -- `HEZSAVE.DIR` calls `saveMovie` on itself -- and
## the writer replaces the target rather than truncating it, which a platform
## that locks open files will refuse. So the handle is dropped for the duration
## and reopened after. Reopening is enough on its own: `DirectorFile.open`
## refreshes `chunks` in place, and every cast, member and film loop holds the
## same object, so nothing above it has to be rebuilt. The chunk *ids* are
## unchanged by design (`director_writer.gd`), so `data_chunk_id` still points at
## the member's text.

const Writer := preload("res://director/director_writer.gd")
const Ink := preload("res://director/director_ink.gd")
const TextArt := preload("res://scenes/preview/text_art.gd")


## Is this process allowed to rewrite a container on disk?
##
## **Yes while a person is playing, no for a script that is only looking.** The
## distinction is not fussiness about side effects: `saveMovie` writes the
## original 1997 file in place, those files are the corpus every measurement in
## `tools/` is taken against, and `games/` is six git submodules whose contents
## nothing here is supposed to change.
##
## What makes it a trap rather than a hazard is that no tool has to *ask* for a
## save to cause one. A movie calls `savemovie` from its own Lingo, and some call
## it from the frame they open on -- `piposh-dream/Saves.dir` frame 3 is
## `on exitFrame / dosave / end`, and `dosave` ends in `savemovie`. Booting that
## container to read its scripts rewrote it, which is how this guard came to be
## written: a diagnostic that only meant to print six handlers modified the game.
##
## Headless is the test because it is exactly the set of runs that are looking:
## every harness in `tools/`, every `gate.sh` pass, every probe. A real session
## has a display and saves normally. `--allow-writes` is the opt-in for the one
## harness whose subject *is* the save (`tools/save_movie.gd`, which writes a
## real container and puts it back).
static func writes_allowed() -> bool:
	if DisplayServer.get_name() != "headless":
		return true
	return OS.get_cmdline_user_args().has("--allow-writes")


## Write the movie now playing to `requested`. Returns a report rather than a
## bool, because a save that half-happened has to be able to say so: `written`
## is how many field members reached the file, and `error` is empty only when
## the container was replaced and reopened cleanly.
static func save(host, requested: String) -> Dictionary:
	var report := {"path": "", "written": 0, "error": ""}
	if not writes_allowed():
		report["error"] = "container writes are off (headless without --allow-writes)"
		return report
	if host._movie == null:
		report["error"] = "no movie is playing"
		return report
	var source_path := str(host._movie.path)
	var target: String = _target_for(host, requested)
	if target == "":
		report["error"] = "cannot place %s" % requested
		return report
	report["path"] = target

	var replacements: Dictionary = _changed_chunks(host, source_path)
	report["written"] = replacements.size()

	# A `saveMovie` to a path that is not the movie's own file is Director's Save
	# As, and it still has to produce a whole movie there even when no field
	# changed. Same file and nothing changed is the genuine no-op.
	var in_place: bool = target.to_lower() == source_path.to_lower()
	if replacements.is_empty():
		if in_place:
			return report
		var copied := DirAccess.copy_absolute(source_path, target)
		if copied != OK:
			report["error"] = "cannot copy to %s: %s" % [target, error_string(copied)]
		return report

	if in_place:
		host._movie.close()
	var failed: String = Writer.rewrite(host._movie, target, replacements)
	if in_place and not host._movie.open(source_path):
		# The movie cannot be reopened, which is worse than a failed save: the
		# player is left on a stage whose container is gone. Reported with the
		# writer's own reason ahead of it when there was one.
		report["error"] = "%s%s cannot be reopened: %s" % [
			failed + "; " if failed != "" else "", source_path, host._movie.error]
		return report
	report["error"] = failed
	if failed != "":
		report["written"] = 0
	return report


## Every field override that belongs to `container_path`, as `STXT` payloads.
##
## Keyed by chunk id, which is what the writer replaces. An override whose text
## already matches what the container holds is left out: a save that rewrote
## every field the movie has ever touched would relocate chunks for no change,
## and the file would grow on a save that saved nothing.
static func _changed_chunks(host, container_path: String) -> Dictionary:
	var out := {}
	if host._table == null:
		return out
	var prefix := container_path.to_lower() + ":"
	for key in host._field_text:
		if not str(key).begins_with(prefix):
			continue
		var number := int(str(key).substr(prefix.length()))
		var chunk_id: int = _stxt_of(host, container_path, number)
		if chunk_id < 0:
			continue
		var old: PackedByteArray = host._movie.read_chunk(chunk_id)
		if old.is_empty():
			continue
		var payload: PackedByteArray = Writer.stxt_with_text(
			old, str(host._field_text[key]))
		if payload.is_empty() or payload == old:
			continue
		out[chunk_id] = payload
	return out


## The `STXT` chunk of member `number` in whichever library of this movie lives
## in `container_path`, or -1.
##
## Libraries are walked in ascending order rather than assuming library 1,
## because a container can hold a second, embedded cast and the override key
## names the *file* both of them are in -- so the number alone does not say which
## one it meant. Ascending order makes the internal cast win, which is the one a
## `put ... into field` in the movie's own scripts addresses.
static func _stxt_of(host, container_path: String, number: int) -> int:
	var libs: Array = host._table.cast_libs.keys()
	libs.sort()
	for lib in libs:
		var entry: Dictionary = host._table.cast_libs[lib]
		if str(entry.get("resolved_path", "")).to_lower() != container_path.to_lower():
			continue
		var member: Dictionary = host._table.get_member(int(lib), number)
		if member.is_empty() or int(member.get("type", 0)) != Ink.TYPE_FIELD:
			continue
		var chunk_id := int(member.get("data_chunk_id", -1))
		if chunk_id >= 0:
			return chunk_id
	return -1


## Where a `saveMovie` path lands.
##
## Resolved beside the movie that named it and then anywhere under the game root,
## exactly as `go to movie` resolves the same string -- so the two agree about
## which file `savepath & "hezsave.dir"` means, which they must, because the save
## writes it and the load reopens it.
##
## A path that names no container the game ships is a new file rather than an
## error, and is honoured literally when its directory exists. Otherwise it is
## taken as a bare name beside the current movie, which is where Director put a
## relative one.
static func _target_for(host, requested: String) -> String:
	var here := str(host._movie.path).get_base_dir()
	# `saveMovie` with no path saves the movie over itself.
	if requested.strip_edges() == "":
		return str(host._movie.path)
	if host._paths == null:
		return here.path_join(_bare(requested)) if _bare(requested) != "" else ""
	var hit: String = host._paths.resolve(requested, here)
	if hit != "":
		return hit
	hit = host._paths.resolve(_bare(requested), here)
	if hit != "":
		return hit
	var literal := requested.strip_edges().replace("\\", "/")
	if literal != "" and DirAccess.dir_exists_absolute(literal.get_base_dir()):
		return literal
	return here.path_join(_bare(requested)) if _bare(requested) != "" else ""


## The filename out of a reference written in any of Director's spellings --
## `@:x.dir`, `MOVIES:x.dir`, `d:\pip2data\x.dir`.
static func _bare(reference: String) -> String:
	return reference.strip_edges().replace("\\", "/").replace(":", "/").get_file()
