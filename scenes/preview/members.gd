extends RefCounted
## Which cast member a Lingo reference names.
##
## **The library is part of the answer, not a hint.** Member numbers are per
## cast, so `member(64, "island2")` and member 64 of the movie's own cast are
## different members that happen to share a number, and resolving in the wrong
## one returns a stranger rather than nothing -- which is silence, not an error.
##
## `searchfunk` in MASTER is what that cost. It does
## `myname = member(the memberNum of sprite the clickOn, "island2").name` and
## then matches that name against a table to decide what a click on the scenery
## reveals. Resolving in library 1 gave it the name of an unrelated member, no
## line ever matched, and the handler returned having done nothing. Every "I
## clicked the thing and nothing happened" of that shape is this.
##
## Resolution goes through the shared cast table, whose internal cast is opened
## once and cached, rather than a fresh `Cast` per call: `number_of` builds its
## name map by parsing every member in the library, so a new instance each time
## re-reads the `CAS*` chunk and every `CASt` record behind it. Measured over 250
## steps of MAP, where the frame script performs 24 name lookups per exitFrame:
## 125-144 ms before, 65-81 ms after, over three runs each.


## `[cast library, member number]` for a Lingo member reference.
##
## An unnamed cast means the movie's own, which is how Director resolves a bare
## `member(N)`; a name that matches no library falls back to the same rather than
## answering nothing, because a wrong-but-present member is easier to see in a
## trace than a silent zero.
static func resolve_ref(which: Variant, cast: String, table) -> Array:
	if table == null:
		return [1, 0]
	var lib := 1
	var wanted := cast.strip_edges().to_lower()
	var found_lib := false
	if wanted != "":
		for number in table.cast_libs:
			if str(table.cast_libs[number].get("name", "")).to_lower() == wanted:
				lib = int(number)
				found_lib = true
				break
	# Director's cast argument is a name **or** a library number -- `member(x, 2)`
	# and `the ... of castLib 2` are as legal as the spelled-out name, and this
	# host stringifies the argument before it arrives, so a number reaches here as
	# "2". Matched against library *names* it matches nothing, and the reference
	# then falls back to library 1: the library named in the script is discarded
	# and the member number resolved somewhere else, which is this module's whole
	# subject. The name is tried first so a library genuinely called "2" still
	# wins, which is the only way the two readings can disagree.
	#
	# 227 references in this corpus name their library by number and 226 of them
	# say `castLib 1`, so the miss was invisible: the wrong answer and the right
	# one were the same library. The odd one out is SAVELOAD's
	# `field "plane" of castLib 2`.
	if not found_lib and wanted != "" and wanted.is_valid_int():
		var asked := int(wanted)
		if table.cast_libs.has(asked):
			lib = asked
			found_lib = true
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		return [lib, int(which)]
	# A name, which Director looks up across every cast when the reference does
	# not name one. Searching the named library first keeps an explicit
	# `of castLib "master"` authoritative.
	var named = table.cast_for(lib)
	if named != null:
		var here: int = named.number_of(str(which))
		if here > 0:
			return [lib, here]
	if wanted != "":
		return [lib, 0]
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for other in libs:
		var cast_file = table.cast_for(int(other))
		if cast_file == null:
			continue
		var found: int = cast_file.number_of(str(which))
		if found > 0:
			return [int(other), found]
	return [lib, 0]


## `the <prop> of member`.
##
## `number`/`membernum`/`castnum` are one arm on purpose.
## `member("able1").memberNum` and `the number of member "able1"` ask the same
## question by two spellings, and only the second used to have a path here: the
## first fell out of the match and returned 0. That is silent, because 0 is a
## plausible member number -- so every
## `set the cursor of sprite i to [member("able1").memberNum, member("able2").memberNum]`
## in MAP stored `[0, 0]` and composed to nothing.
static func read_prop(host, where: Array, prop: String, table) -> Variant:
	var m: Dictionary = table.get_member(int(where[0]), int(where[1]))
	match prop:
		"name":
			return str(m.get("name", ""))
		"width":
			return int(m.get("width", 0))
		"height":
			return int(m.get("height", 0))
		"text":
			# Through the same override the renderer reads, or `the text of
			# member` would answer the authored placeholder while the screen
			# showed the current value.
			return host._field_text_of(m)
		"number", "membernum", "castnum":
			return int(where[1])
	return 0
