extends RefCounted
## `the <prop> of castLib N` — §5.1's third qualified entity.
##
## A cast library is a thing in its own right in Director, not a member and not a
## movie: `the name of castLib 2` and `the fileName of castLib "sounds"` ask
## about the *library*. There was no path to them here at all -- the parser fell
## them through to `prop_of` over a command-form call to a handler named
## `castlib`, which is unbound, so every one reported a missing builtin and
## answered VOID.
##
## **Read-only, and only three of Director's five.** The split is deliberate and
## each half is named rather than left to be inferred from what is here:
##
##   `name`, `fileName`, `number`  answered from the movie's own `MCsL` mapping,
##                                 which `director_cast_table.gd` already parses
##                                 to decide where a member number resolves. All
##                                 three are read-only in Director: a library is
##                                 renamed and re-pointed in the authoring tool.
##   `preLoadMode`                 **absent.** 0 "when needed", 1 "after frame
##                                 one", 2 "before frame one" -- and this port
##                                 loads on demand, which *is* mode 0, with
##                                 nothing that could act on the other two: the
##                                 preloader walks ahead of the playhead member
##                                 by member and has no notion of a library. A
##                                 stored mode nothing consults is the shape
##                                 §19 calls the worst state there is, so it is
##                                 left unbound and reported.
##   `selection`                   **absent.** The members selected in Director's
##                                 Cast *window*: an authoring-tool fact with no
##                                 runtime meaning. There is no window and no
##                                 selection, and answering `[]` would be a value
##                                 a script could branch on.
##
## `the number of castLib "x"` is the reverse lookup -- a name to a library
## number -- and is the same question `preview/members.gd:library_named` answers
## for a member reference, asked through that function rather than re-derived, or
## the two would disagree about a library genuinely named "2".

const Members := preload("res://scenes/preview/members.gd")


## Which library a `castLib` designator names. A number is itself; a string is
## looked up by name, and 0 for a name that matches nothing -- which is what
## `library_named` answers and is not a library number, so the reads below answer
## VOID for it rather than answering about library 1.
static func resolve(which: Variant, table) -> int:
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		return int(which)
	return Members.library_named(str(which), table)


## VOID for a property this port does not bind and for a library that is not
## there, which is what makes the caller report it instead of handing back a
## plausible 0.
static func read_prop(which: Variant, prop: String, table) -> Variant:
	if table == null:
		return null
	var lib := resolve(which, table)
	var known: bool = lib > 0 and (table.cast_libs as Dictionary).has(lib)
	var entry: Dictionary = (table.cast_libs as Dictionary)[lib] if known else {}
	# One `match` and no early returns, because `tools/lingo_surface_audit.gd`
	# reads this function's arms to decide which cast properties are bound: a
	# property answered by an `if` above the match is invisible to it and reports
	# `absent` however live it is. The existence test is therefore inside each
	# arm rather than in front of them all.
	match prop.to_lower():
		"number":
			# The one property whose *point* is asking about a library that may
			# not be there, so it is answered whether or not it is. Director
			# answers -1 for a name it cannot find; 0 would be indistinguishable
			# from a library-1 answer.
			return lib if known else -1
		"name":
			return str(entry.get("name", "")) if known else null
		"filename":
			if not known:
				return null
			# The path the movie *names*, not the one this port resolved it to.
			# Director's `the fileName of castLib` is the authored external-cast
			# path, and a title comparing it against a string it built itself is
			# comparing against the authored spelling; the resolved path is a fact
			# about this machine's filesystem. The internal cast has none, and
			# Director answers "" for it.
			return str(entry.get("path", ""))
	return null
