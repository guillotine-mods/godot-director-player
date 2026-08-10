extends SceneTree
## `field "x" of castLib Y` and `the <prop> of field "x"`: the two halves of a
## field designator this port was throwing away.
##
##   godot --headless --path . --script tools/field_designator.gd
##   godot --headless --path . --script tools/field_designator.gd -- --root piposh --survey
##
##   --survey   open every movie of the corpus and report every qualified field
##              reference its scripts spell, and which of them name a library the
##              movie does not have. Minutes, not seconds — off in the gate.
##
## ## What it asserts, and why each one could not be seen before
##
## **The library the script named stops the search.**
## `Movie::getCastMemberIDByNameAndType(name, castLib, type)` searches the named
## library and nothing else; only the `castLib == 0` arm walks every cast, and a
## named library that does not hold the name answers -1 rather than falling
## through (`reference/scummvm/movie.cpp:720-759`). This port's `lingo_field` and
## `lingo_set_field` took the library and spelled the parameter `_cast`, so
## `field "x" of castLib "master"` was resolved as though the clause had not been
## written and answered with whichever library held that name first.
##
## Nothing could catch it by reading values back, because a wrong library that
## happens to hold the *only* member of that name gives the right answer: 170 of
## Piposh 2's 170 qualified references resolve to the same member either way.
## So the check below is the negative one — a field asked for in a library that
## does not hold it must answer **nothing**, not the copy next door. That is the
## one shape the corpus cannot produce by luck.
##
## **A field designator carries a property, and it is not always `the text`.**
## `Lingo::getTheField` resolves the designator to a cast member, refuses one
## that is not a field, and answers `member->getField(prop)`;
## `Lingo::setTheField` is `member->setField(prop, value)`
## (`reference/scummvm/lingo-the.cpp:2334-2398`). The interpreter dropped the
## property name and sent both directions to `get_field`/`set_field`, so every
## one of the fifty member properties read back as the **text**, and every write
## replaced the text. `set the textSize of field "globalmoney" to 24` — Piposh
## 1's slot machine, in all three language builds — therefore put the string
## `24` where the money was. A write that lands on the value it was not
## addressing round-trips perfectly, which is why it had survived: the next read
## of `the text` answers what the wrong write put there.
##
## ## Title-agnostic
##
## Nothing here names a movie, a member or a channel. The fixture is *found*: the
## cast table is asked for a field member in a library above the movie's own
## whose name library 1 does not also carry, and the checks are stated against
## whatever that turns out to be. A corpus that offers none says so and the
## library half is skipped rather than asserted over nothing — which is reported,
## because a harness that quietly asserts nothing is the failure this repo has
## been bitten by (`bugs.md` 33).

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")
const Ink := preload("res://director/director_ink.gd")
const Members := preload("res://scenes/preview/members.gd")

var _preview: Node = null
var _interp = null


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	_preview = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(_preview)
	await process_frame
	await process_frame
	_interp = _preview.get("_interpreter")

	var case := "the harness has a movie and an interpreter"
	h.begin(case)
	h.check("the preview booted a cast table", _preview.get("_table") != null)
	h.check("the interpreter is attached", _interp != null)
	h.complete(case)
	if _preview.get("_table") == null or _interp == null:
		quit(h.finish("the field designator"))
		return

	await _open_a_movie_with_fields(h)
	_library_checks(h)
	_property_checks(h)

	if Args.flag(args, "survey"):
		await _survey()

	_preview.queue_free()
	await process_frame
	quit(h.finish("the field designator"))


# ------------------------------------------------------------- the fixture


## Walk the corpus until a movie offers the fixture, and stop there.
##
## The boot movie is tried first and is usually not it: `piposh2`'s `strtgame.dir`
## loads one cast and carries no field member at all, so a harness that asserted
## only against whatever the config booted would report "nothing to state this
## about" and pass — the shape `bugs.md` 33 is about. Every title in this repo has
## rooms with a linked cast full of fields; this finds the first one rather than
## naming it, so the file stays title-agnostic and still asserts.
func _open_a_movie_with_fields(h: Harness) -> void:
	var case := "a movie with a field to state the rules about"
	h.begin(case)
	var table = _preview.get("_table")
	var here := ""
	if not _find_field(table, true).is_empty() and not _find_field(table, false).is_empty():
		here = str(_preview.get("_container_path"))
	else:
		var paths := Paths.new()
		paths.load_config()
		var containers: Array = []
		for entry in paths.containers():
			if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
				continue
			containers.append(str(entry))
		containers.sort()
		for movie in containers:
			_preview.call("lingo_go_movie", movie, null)
			await process_frame
			table = _preview.get("_table")
			if table == null:
				continue
			if _find_field(table, true).is_empty() or _find_field(table, false).is_empty():
				continue
			here = movie
			break
	h.check("the corpus offers one", here != "", here)
	if here != "":
		print("field fixture: %s" % here)
	h.complete(case)


## A field member the checks can be stated about: `{"name":, "lib":, "id":}`.
##
## Preferring one in a library above the movie's own, because that is the only
## arrangement in which "the named library is authoritative" and "the first
## library that answers wins" give different answers. A field in library 1 alone
## proves nothing: both readings find it in library 1.
func _find_field(table, want_linked: bool) -> Dictionary:
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	var own = table.cast_for(1)
	for lib in libs:
		if want_linked and int(lib) == 1:
			continue
		var cast = table.cast_for(int(lib))
		if cast == null:
			continue
		for number in cast.member_numbers():
			var m: Dictionary = cast.member(int(number))
			if int(m.get("type", 0)) != Ink.TYPE_FIELD:
				continue
			var name := str(m.get("name", ""))
			if name == "":
				continue
			if want_linked and own != null and own.number_of(name) > 0:
				# The name is in library 1 as well, so "search library 1 first"
				# and "search only the library named" agree about it.
				continue
			return {"name": name, "lib": int(lib), "id": int(number)}
	return {}


# ------------------------------------------------- the library half (§11.8)


func _library_checks(h: Harness) -> void:
	var case := "`field \"x\" of castLib Y` is resolved in Y and nowhere else"
	h.begin(case)
	var table = _preview.get("_table")
	var found: Dictionary = _find_field(table, true)
	if found.is_empty():
		# Said out loud rather than skipped in silence. The property half below
		# still runs, so the file is not asserting nothing either way.
		h.check("the movie carries a field in a linked library to state this about",
			false, "no linked-library field with a name library 1 does not share")
		h.complete(case)
		return
	var name := str(found["name"])
	var lib := int(found["lib"])
	var id := int(found["id"])

	var loose: Array = _preview.call("_resolve_field", name, "")
	h.check("an unqualified `field \"%s\"` still walks the libraries" % name,
		loose.size() == 2 and int(loose[0]) == lib and int(loose[1]) == id,
		"answered %s, wanted [%d, %d]" % [str(loose), lib, id])

	var named: Array = _preview.call("_resolve_field", name, str(lib))
	h.check("naming its own library answers the same member",
		named.size() == 2 and int(named[0]) == lib and int(named[1]) == id,
		"answered %s" % str(named))

	# The check the corpus cannot produce by luck: library 1 does not hold this
	# name, so a resolution that honours the clause finds nothing and one that
	# ignores it finds the copy in `lib`.
	var elsewhere: Array = _preview.call("_resolve_field", name, "1")
	h.check("naming a library that does not hold it answers nothing",
		elsewhere.is_empty(), "answered %s" % str(elsewhere))

	# Through Lingo, not only through the node, because the interpreter is what
	# decides whether the clause reaches the host at all.
	var text := str(_value("the text of field \"%s\" of castLib 1" % name))
	h.check("and the same through a script", text == "",
		"`the text of field \"%s\" of castLib 1` answered %s" % [name, JSON.stringify(text)])
	h.complete(case)


# ------------------------------------------ the property half (§11.8, §9.3)


func _property_checks(h: Harness) -> void:
	var case := "`the <prop> of field \"x\"` is the member's property, not its text"
	h.begin(case)
	var table = _preview.get("_table")
	var found: Dictionary = _find_field(table, false)
	if found.is_empty():
		h.check("the movie carries a field member to state this about", false)
		h.complete(case)
		return
	var name := str(found["name"])

	# A value the text cannot be mistaken for, put there through the same path a
	# movie uses, so that "the property answered the text" is visible rather than
	# arguable.
	_run("put \"the quick brown fox\" into field \"%s\"" % name)
	var text := str(_value("the text of field \"%s\"" % name))
	h.check("`the text of field` is still the text", text == "the quick brown fox",
		JSON.stringify(text))

	var member_name := str(_value("the name of field \"%s\"" % name))
	h.check("`the name of field` is the member's name",
		member_name.to_lower() == name.to_lower(),
		"answered %s, wanted %s" % [JSON.stringify(member_name), JSON.stringify(name)])

	var lib_num := int(_value("the castLibNum of field \"%s\"" % name))
	h.check("`the castLibNum of field` is a library number",
		lib_num == int(found["lib"]),
		"answered %d, wanted %d" % [lib_num, int(found["lib"])])

	# The write half. `textSize` because it is the one property this corpus
	# actually sets through a field designator -- Piposh 1's slot machine, three
	# builds -- and because its value and the text are different types, so a write
	# that lands on the text cannot pass by coincidence.
	_run("set the textSize of field \"%s\" to 33" % name)
	var size := int(_value("the textSize of field \"%s\"" % name))
	h.check("a `textSize` write reaches the member's style", size == 33,
		"`the textSize of field` answered %d" % size)
	var through_member := int(_value("the textSize of member \"%s\"" % name))
	h.check("and the member spelling agrees with the field spelling",
		through_member == 33, "`the textSize of member` answered %d" % through_member)
	var after := str(_value("the text of field \"%s\"" % name))
	h.check("and the text it was not addressing is untouched",
		after == "the quick brown fox", JSON.stringify(after))
	h.complete(case)


# ------------------------------------------------------------- the survey


## Every `field "x" of castLib Y` the corpus spells, and the ones whose library
## the movie does not have.
##
## Reported, never asserted: it is a fact about the *data*, and the three misses
## it finds are why `director_preview.gd:_resolve_field` falls back to the walk
## when the clause names no library at all rather than answering nothing the way
## `getCastLibIDByName` would.
func _survey() -> void:
	var paths := Paths.new()
	paths.load_config()
	var rx := RegEx.new()
	rx.compile("(?i)field\\s+\"([^\"]+)\"\\s+of\\s+castlib\\s+(\"[^\"]+\"|[0-9]+)")
	var seen: Dictionary = {}
	var missing: Dictionary = {}
	for entry in paths.containers():
		var movie := str(entry)
		if ContainerName.CAST.has(movie.get_extension().to_lower()):
			continue
		_preview.call("lingo_go_movie", movie, null)
		await process_frame
		var table = _preview.get("_table")
		if table == null:
			continue
		for lib in table.cast_libs:
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			for number in cast.member_numbers():
				var src := str((cast.member(int(number)) as Dictionary).get("source", ""))
				if src == "":
					continue
				for hit in rx.search_all(src):
					var field_name := hit.get_string(1)
					var lib_word := hit.get_string(2).replace("\"", "")
					seen["%s|%s|%s" % [movie.get_file(), field_name.to_lower(),
						lib_word.to_lower()]] = true
					if Members.library_named(lib_word, table) > 0:
						continue
					missing["%s: field \"%s\" of castLib \"%s\"" % [
						movie.get_file(), field_name, lib_word]] = true
	print("")
	print("root %s" % paths.root)
	print("  distinct `field \"x\" of castLib Y` references : %d" % seen.size())
	print("  naming a library the movie does not have      : %d" % missing.size())
	for key in missing:
		print("    %s" % key)


# --------------------------------------------------------------- driving


func _run(source: String) -> void:
	var script := Compiler.new().compile_source(
		"on probe\n  %s\nend\n" % source, "FieldDesignatorProbe")
	if script.is_empty():
		push_warning("field_designator: `%s` did not compile" % source)
		return
	_interp.call_handler("probe", [], script)


func _value(expression: String) -> Variant:
	var script := Compiler.new().compile_source(
		"on probe\n  return %s\nend\n" % expression, "FieldDesignatorProbe")
	if script.is_empty():
		return "<did not compile>"
	return _interp.call_handler("probe", [], script)
