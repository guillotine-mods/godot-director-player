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
## For the fixture search only. Opening a container and reading its member
## records costs milliseconds; `lingo_go_movie` compiles every script in the
## movie and its linked casts, which on Piposh 1's rooms is seconds each and on
## a 124-container corpus is the difference between a harness and a sweep.
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")

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
	_dot_property_checks(h)
	_library_by_file_checks(h)
	_number_checks(h)
	# Last, because it walks the corpus and leaves the preview on whatever movie
	# offered its fixture.
	await _type_collision_checks(h)

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
		# `movie_name()`, not a `get()` on a private field: a name that has moved
		# makes `get()` answer null, `str(null)` answer "<null>", and this check
		# pass while labelling the fixture with a placeholder -- the dark-harness
		# failure `scenes/preview/README.md` names.
		here = str(_preview.call("movie_name"))
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


## `field("x").prop` — the dot spelling of the same property. `bugs.md` 76.
##
## Director has two spellings of one access and the reference reaches
## `member->getField(prop)` from both; this port had an arm for the designator
## and none for the dot, so `_eval`'s `dot` case evaluated the owner -- which
## yields the field's **text** -- and then asked `get_member_prop` for a member of
## *that* name. `field("save1").textSize` therefore read a property of a member
## called `Tal` when the save slot said `Tal`, and VOID when nothing was named
## that. `field("x").text = y` took the identical route.
##
## **Stated as an agreement between the two spellings rather than against a
## literal**, because that is the invariant that cannot rot: the value a property
## answers is the engine's business and may legitimately change, and the day the
## two spellings disagree is the day one of them is wrong whatever the number is.
## The one literal below is the text, which is asserted because the *bug* was that
## the dot spelling answered it.
##
## 0 sites in the six titles use this spelling. It is built because Director has
## it, and it is a case here rather than a file because it is the same rule as the
## designator above and must be measured against the same fixture -- two harnesses
## over one rule is how the two spellings drift apart.
func _dot_property_checks(h: Harness) -> void:
	var case := "`field(\"x\").prop` is the same access as `the prop of field \"x\"`"
	h.begin(case)
	var table = _preview.get("_table")
	var found: Dictionary = _find_field(table, false)
	if found.is_empty():
		h.check("the movie carries a field member to state this about", false)
		h.complete(case)
		return
	var name := str(found["name"])

	_run("put \"dotted\" into field \"%s\"" % name)
	_run("set the textSize of field \"%s\" to 21" % name)
	var dotted_size := int(_value("field(\"%s\").textSize" % name))
	h.check("the dot spelling reads the member property, not the text",
		dotted_size == 21, "answered %d, wanted 21" % dotted_size)
	var dotted_name := str(_value("field(\"%s\").name" % name))
	h.check("and `.name` is the member's name and not its contents",
		dotted_name.to_lower() == name.to_lower(),
		"answered %s, wanted %s" % [JSON.stringify(dotted_name), JSON.stringify(name)])
	var dotted_text := str(_value("field(\"%s\").text" % name))
	h.check("`.text` is still the text", dotted_text == "dotted",
		JSON.stringify(dotted_text))

	# The write half, and the reason it is the half that hurts: a write through
	# the dot went to `set_member_prop` on a member named after the text, so it
	# either vanished or landed on a stranger.
	_run("field(\"%s\").textSize = 34" % name)
	var through_designator := int(_value("the textSize of field \"%s\"" % name))
	h.check("a write through the dot reaches what the designator reads",
		through_designator == 34,
		"`the textSize of field` answered %d" % through_designator)
	_run("field(\"%s\").text = \"written through the dot\"" % name)
	var text_now := str(_value("the text of field \"%s\"" % name))
	h.check("and `.text = ` writes the text", text_now == "written through the dot",
		JSON.stringify(text_now))
	h.complete(case)


## A library named by its **file** resolves to that library. `bugs.md` 75.
##
## The corpus spells `of castLib "master.cst"` where the movie's `MCsL` calls the
## same library `master`, and Piposh 1 writes both spellings across its rooms --
## `master`/`master.cst`, `zoom1`/`zoom1.cst`, `pirats`/`pirats.cst` -- so
## whichever half a given movie carries, some script naming it spells the other.
## Before this, such a reference matched no library and fell through to
## `_resolve_field`'s unqualified walk, which can answer out of *any* cast; the
## reference would answer nothing at all (`movie.cpp:692-699`, `:247` -- the name
## table is keyed by the `MCsL` name and never by the path).
##
## **The negative is the check that matters**, as it is for the library rule
## above: a file name that names no library must still answer 0, or "match on the
## file" has become "match on anything that looks like one".
##
## Skipped, loudly, on a movie whose libraries declare no path -- an internal cast
## has none by construction, so a movie with one library can say nothing about
## this.
func _library_by_file_checks(h: Harness) -> void:
	var case := "`of castLib \"<file>.cst\"` names the library that file is"
	h.begin(case)
	var table = _preview.get("_table")
	var lib := 0
	var file := ""
	for number in table.cast_libs:
		var path := str(table.cast_libs[number].get("path", ""))
		if path == "":
			continue
		lib = int(number)
		file = path.replace(":", "/").replace("\\", "/").get_file()
		break
	if lib == 0:
		h.check("this movie links a cast with a path to state this about", false,
			"%s declares only embedded libraries" % _preview.call("movie_path"))
		h.complete(case)
		return
	h.check("the library's file resolves to the library",
		Members.library_named(file, table) == lib,
		"%s -> %d, wanted %d" % [file, Members.library_named(file, table), lib])
	h.check("its `MCsL` name still resolves to the same one",
		Members.library_named(str(table.cast_libs[lib].get("name", "")), table) == lib,
		"name %s" % str(table.cast_libs[lib].get("name", "")))
	h.check("a file no library is named after resolves to nothing",
		Members.library_named("no-such-cast-9001.cst", table) == 0)
	h.complete(case)


# ------------------------------------------ the numeric half (§11.8, §9.3)


## `field 122` is member 122; `field "122"` is a member *named* `122`.
##
## Director resolves a designator by number or by name according to the
## subscript's **type**, and this port flattened the two: the interpreter
## stringified the subscript before the host saw it and the host resolves a string
## as a name (`preview/members.gd:resolve_ref`), so every numeric field reference
## in every title resolved to nothing -- the write dropped, the read "".
##
## The corpus spells it with a variable rather than a literal, which is why the
## fault survived: `repeat with i = 122 to 130 / put value(the text of field i) - 1
## into field i` is `piposh-dream`'s `eat.dir` counting nine timers down, and there
## are 134 such sites across the six roots against 0 literal `field <digits>`. With
## the timers frozen the click handler's `value(the text of field ("chara" & n))
## <= 4` gate never opened and its `< 0` gameover arm never fired: nine clickable
## characters that answered every click by doing nothing, and a scene that could
## be neither won nor lost.
##
## So both spellings are asserted, and the negative with them -- a name that
## happens to be digits must **not** resolve to the member at that number, or the
## fix has merely moved the collapse in the other direction.
##
## **An unqualified numeric designator resolves in library 1** (`resolve_ref`
## defaults the library) and a member number is per cast, so the fixture decides
## which spelling can be stated here: a named field in the movie's own cast gets
## the bare form -- `eat.dir`'s own -- and a movie whose only named fields are in a
## linked library gets `field <number> of castLib <n>`, which asks the same
## question of the library the member is actually in. **Neither arm may be a
## failure**: which one applies is a fact about a 1990s cast, and a harness that
## reds because a movie keeps its fields in an external cast is asserting the data
## (AGENTS.md). The one data-dependent assertion in this file stays the fixture
## check above.
func _number_checks(h: Harness) -> void:
	var case := "`field <number>` is the member at that number, not one named for it"
	h.begin(case)
	var table = _preview.get("_table")
	var found: Dictionary = _find_field_in_own_cast(table)
	var qualifier := ""
	if found.is_empty():
		found = _find_field(table, false)
		if found.is_empty():
			h.check("the movie carries a named field to state this about", false)
			h.complete(case)
			return
		qualifier = " of castLib %d" % int(found["lib"])
		print("no named field in library 1 here, so the number is asked for%s"
			% qualifier)
	var name := str(found["name"])
	var id := int(found["id"])

	_run("put \"17\" into field %d%s" % [id, qualifier])
	var by_name := str(_value("the text of field \"%s\"" % name))
	h.check("a write by number lands on the member the name names",
		by_name == "17", "`field \"%s\"` answered %s" % [name, JSON.stringify(by_name)])
	var by_number := str(_value("the text of field %d%s" % [id, qualifier]))
	h.check("and reads back by number", by_number == "17", JSON.stringify(by_number))
	var bare := str(_value("field %d%s" % [id, qualifier]))
	h.check("the bare designator answers the text too", bare == "17",
		JSON.stringify(bare))

	# The corpus's own spelling: a variable holding the number, which is what
	# `repeat with i = 122 to 130` produces.
	_run("nn = %d\n  put \"23\" into field nn%s" % [id, qualifier])
	var through_var := str(_value("the text of field \"%s\"" % name))
	h.check("a variable holding the number resolves the same way",
		through_var == "23", JSON.stringify(through_var))

	# The negative, and the reason it is guarded rather than asserted flat: it is
	# only a statement about *this* corpus that no cast holds a member called
	# "%d", and a harness that asserts what the data happens not to contain is
	# asserting the data.
	if _member_named(table, str(id)):
		print("a member is actually named %d here; the name/number split is not"
			% id + " assertable in this movie")
	else:
		var as_name: Variant = _preview.call("_resolve_field", str(id), "")
		h.check("the same digits as a *name* resolve to nothing",
			(as_name as Array).is_empty(), "answered %s" % str(as_name))
	# The bound on what the change can reach, asserted rather than argued: a
	# numeric designator naming a member that is not a field still answers
	# nothing, because `text_art.gd:resolve` takes the by-number answer only when
	# it really is a field and then walks the *names* for the digits. So a
	# `repeat with i` spanning a cast's bitmaps writes nowhere, exactly as before.
	var not_a_field := _find_non_field_in_own_cast(table)
	if not_a_field <= 0:
		print("library 1 is all fields here; the non-field bound is not assertable")
	else:
		var refused: Variant = _preview.call("_resolve_field", not_a_field, "")
		h.check("a number naming a member that is not a field answers nothing",
			(refused as Array).is_empty(),
			"member %d answered %s" % [not_a_field, str(refused)])
	h.complete(case)


## The first named field member of the movie's own cast, or `{}`.
func _find_field_in_own_cast(table) -> Dictionary:
	var cast = table.cast_for(1)
	if cast == null:
		return {}
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(int(number))
		if int(m.get("type", 0)) != Ink.TYPE_FIELD:
			continue
		if str(m.get("name", "")) == "":
			continue
		return {"name": str(m.get("name", "")), "lib": 1, "id": int(number)}
	return {}


## A member of the movie's own cast that is **not** a field, or 0.
static func _find_non_field_in_own_cast(table) -> int:
	var cast = table.cast_for(1)
	if cast == null:
		return 0
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(int(number))
		if int(m.get("type", 0)) != Ink.TYPE_FIELD and int(m.get("type", 0)) > 0:
			return int(number)
	return 0


# ------------------------------------- the typed half (`name:type`, §11.8)


## `field "x"` where a member of another type also answers to `x`.
##
## Director keeps **two** name keys per member — `name` and `name:type` — and a
## typed designator asks the second (`reference/scummvm/cast.cpp:174-186`, built
## at `rebuildCastNameCache`, 2448). So a name is unique per type, not per
## library, and a bitmap or an Xtra sharing a field's name is simply not a
## candidate for `field "x"`.
##
## This port had only the untyped key. `field "x"` asked for the lowest-numbered
## member of that name whatever its type, rejected the answer when it was not a
## field, and moved on to the **next library** rather than to the next member —
## so one non-field of that name in a library hid every field of that name in it.
## `SLOTMACH.dir` is what that costs: an Xtra `credit` at 83 hid the field
## `credit` at 97, so `value(the text of field "credit")` was 0 on every pull of
## the handle and the machine told the player they had not inserted a coin, while
## the coin slot's `put ... + 1 into field "credit"` wrote into nothing.
##
## The fixture is found, not named: the corpus is searched for a library where
## one name is held by a field *and* by a non-field with a **lower** member
## number, which is the only arrangement where the typed and untyped lookups can
## disagree. A corpus offering none says so and asserts nothing rather than
## passing over a check that cannot fail.
func _type_collision_checks(h: Harness) -> void:
	var case := "`field \"x\"` finds the field when another type owns the name first"
	h.begin(case)
	var table = _preview.get("_table")
	var found: Dictionary = _find_type_collision(table)
	var here := str(_preview.call("movie_name"))
	if found.is_empty():
		# Searched with the container reader rather than by opening each movie in
		# the player: the fixture is a fact about a cast's member records, and
		# paying a full Lingo compile per container to learn it turned this check
		# into a ten-minute sweep. One `lingo_go_movie` is spent, on the winner.
		var where_movie := _corpus_collision()
		if where_movie != "":
			_preview.call("lingo_go_movie", where_movie, null)
			await process_frame
			table = _preview.get("_table")
			found = _find_type_collision(table)
			here = where_movie
	if found.is_empty():
		print("no library in this corpus gives one name to a field and to an "
			+ "earlier member of another type -- nothing asserted here")
		h.complete(case)
		return

	var name := str(found["name"])
	print("type-collision fixture: %s  %s -> field %d:%d, %s %d:%d" % [
		here, name, int(found["lib"]), int(found["field"]),
		str(found["other_type"]), int(found["lib"]), int(found["other"]),
	])
	var where: Array = _preview.call("_resolve_field", name, "")
	h.check("the designator resolves to the field and not to the %s"
			% str(found["other_type"]),
		where == [int(found["lib"]), int(found["field"])], JSON.stringify(where))
	# Through the interpreter as well, because the resolver is not what a movie
	# calls: `value(the text of field "x")` reading 0 is the shape the player saw,
	# and a resolver that is right while the read is wrong would still be broken.
	var authored := str((table.get_member(
		int(found["lib"]), int(found["field"])) as Dictionary).get("text", ""))
	var text: Variant = _value("the text of field \"%s\"" % name)
	h.check("and a script reads the field's own text through it",
		str(text) == authored, "%s vs authored %s" % [
			JSON.stringify(text), JSON.stringify(authored)])
	# The untyped designator is deliberately *not* asserted to move: `member "x"`
	# is `kCastTypeAny` in the reference and still answers the earlier member.
	var any: Array = _preview.call("lingo_member_where", name)
	h.check("while the untyped `member \"x\"` still answers the earlier member",
		any == [int(found["lib"]), int(found["other"])], JSON.stringify(any))
	h.complete(case)


## `{name, lib, field, other, other_type}` for the first library in the movie
## that holds one name as a field and, at a lower number, as something else.
##
## The lower number is the whole point: the untyped lookup answers the lowest
## member of the name, so a collision where the field comes first is one both
## readings resolve identically and proves nothing. No earlier library may hold a
## field of that name either, or the walk would legitimately answer there and the
## assertion would be about library order rather than about type.
static func _find_type_collision(table) -> Dictionary:
	if table == null:
		return {}
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for lib in libs:
		var hit := _collision_in_cast(table.cast_for(int(lib)))
		if hit.is_empty():
			continue
		var earlier := false
		for before in libs:
			if int(before) >= int(lib):
				break
			var other_cast = table.cast_for(int(before))
			if other_cast != null \
					and other_cast.number_of_type(str(hit["name"]), Ink.TYPE_FIELD) > 0:
				earlier = true
				break
		if earlier:
			continue
		hit["lib"] = int(lib)
		return hit
	return {}


## The same question asked of one cast: `{name, field, other, other_type}`.
static func _collision_in_cast(cast) -> Dictionary:
	if cast == null:
		return {}
	var fields: Dictionary = {}
	var others: Dictionary = {}
	var kinds: Dictionary = {}
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(int(number))
		var name := str(m.get("name", "")).to_lower()
		if name == "":
			continue
		var kind := int(m.get("type", 0))
		if kind == Ink.TYPE_FIELD:
			if not fields.has(name):
				fields[name] = int(number)
		elif kind > 0:
			if not others.has(name):
				others[name] = int(number)
				kinds[name] = str(m.get("type_name", "?"))
	for name in fields:
		if not others.has(name) or int(others[name]) > int(fields[name]):
			continue
		return {
			"name": name, "field": int(fields[name]),
			"other": int(others[name]), "other_type": str(kinds[name]),
		}
	return {}


## The first movie container of the corpus whose own cast holds the collision,
## or "". Read straight off the disc; see the `ContainerFile` preload.
static func _corpus_collision() -> String:
	var paths := Paths.new()
	if not paths.load_config():
		return ""
	var containers: Array = []
	for entry in paths.containers():
		if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			continue
		containers.append(str(entry))
	containers.sort()
	for movie in containers:
		var path = paths.resolve(str(movie))
		if path == "":
			continue
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var cast := Cast.new()
		var hit: Dictionary = _collision_in_cast(cast) if cast.open(f) else {}
		f.close()
		if not hit.is_empty():
			return str(movie)
	return ""


static func _member_named(table, name: String) -> bool:
	for lib in table.cast_libs:
		var cast = table.cast_for(int(lib))
		if cast != null and cast.number_of(name) > 0:
			return true
	return false


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
