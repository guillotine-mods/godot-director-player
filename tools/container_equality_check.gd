extends SceneTree
## `day1.dxr` and `day1.dir` are one movie, and Lingo must agree.
##
##   godot --headless --script tools/container_equality_check.gd
##
## A shipped Director title is protected throughout, so the filename a script was
## authored against and the filename on disk always agreed and nobody had to
## think about it. Converting the originals to unprotected containers breaks that
## agreement, and every exact filename comparison silently answers false.
##
## Piposh 2 has exactly four such comparisons, all `the movieName = "day1.dxr"`,
## and between them they gate the whole of `cursorfunk` — which assigns the
## cursors for sprites 2, 7-9, 14 and 10-13, the exit arrows — and, twice inside
## `whatodoeveryframe`, the `go` that changes room when a walk completes. With
## the file named `.dir` the character walks to the doorway, is hidden by the
## line immediately above the test, and the room never changes. That is a
## complete account of "no cursor, the sides do nothing, and walking to the
## stairs makes him vanish".
##
## The negative cases matter as much as the positives: a movie must never equal a
## cast, and two different movies must never equal each other.

const Harness := preload("res://tools/lib/harness.gd")
const ContainerName := preload("res://director/director_container.gd")


func _init() -> void:
	var h := Harness.new()

	h.begin("a protected and an unprotected container are the same file")
	for pair in [["day1.dxr", "day1.dir"], ["DAY1.DXR", "day1.dir"],
			["strtgame.dir", "strtgame.dxr"], ["x.dcr", "x.dir"],
			["master.cst", "master.cxt"], ["master.cxt", "master.cct"]]:
		h.check("%s = %s" % [pair[0], pair[1]],
			LingoValue.equal(pair[0], pair[1]), "")
		# `<>` is the same predicate inverted, so it has to follow.
		h.check("%s <> %s is false" % [pair[0], pair[1]],
			not (not LingoValue.equal(pair[0], pair[1])), "")
	h.complete("a protected and an unprotected container are the same file")

	h.begin("nothing else is quietly made equal")
	# A movie is not a cast, however alike the stems.
	h.check("day1.dir <> day1.cst", not LingoValue.equal("day1.dir", "day1.cst"))
	h.check("master.cst <> master.dir", not LingoValue.equal("master.cst", "master.dir"))
	# Different movies stay different.
	h.check("day1.dxr <> day2.dir", not LingoValue.equal("day1.dxr", "day2.dir"))
	h.check("night1.dir <> night2.dxr", not LingoValue.equal("night1.dir", "night2.dxr"))
	# Extensions this engine has no business reconciling.
	h.check("a.txt <> a.dir", not LingoValue.equal("a.txt", "a.dir"))
	h.check("a.exe <> a.dxr", not LingoValue.equal("a.exe", "a.dxr"))
	# No extension at all is not a container name.
	h.check("day1 <> day1.dxr", not LingoValue.equal("day1", "day1.dxr"))
	h.check("empty strings are still equal", LingoValue.equal("", ""))
	# The stem still has to match.
	h.check("a.dir <> b.dxr", not LingoValue.equal("a.dir", "b.dxr"))
	h.complete("nothing else is quietly made equal")

	h.begin("the reconciliation survives the paths a script actually writes")
	# Scripts build these by concatenation, and case is Lingo's to ignore.
	h.check("case is ignored across the extension too",
		LingoValue.equal("Day1.DXR", "dAY1.dir"))
	# `compare` backs <, >, <= and >=; it must not disagree with `equal`.
	h.check("compare() agrees that they are equal",
		LingoValue.compare("day1.dxr", "day1.dir") == 0,
		str(LingoValue.compare("day1.dxr", "day1.dir")))
	h.check("compare() still orders unrelated names",
		LingoValue.compare("a.dir", "b.dir") < 0)
	h.complete("the reconciliation survives the paths a script actually writes")

	# The rule has one home. A second copy is how `.dxr` came to resolve one way
	# for a path lookup and another for a Lingo comparison.
	h.begin("path resolution and Lingo agree, because they share the rule")
	for pair in [["day1.dxr", "day1.dir"], ["master.cxt", "master.cst"]]:
		var spellings: Array = ContainerName.spellings(pair[0])
		h.check("%s offers %s as an alternative" % [pair[0], pair[1]],
			spellings.has(pair[1]), str(spellings))
		h.check("%s is offered first" % pair[0],
			spellings.size() > 0 and str(spellings[0]) == pair[0], str(spellings))
		h.check("Lingo agrees they are equal", LingoValue.equal(pair[0], pair[1]))
	h.check("a non-container name offers only itself",
		ContainerName.spellings("notes.txt").size() == 1, str(ContainerName.spellings("notes.txt")))
	h.check("canonical collapses packaging",
		ContainerName.canonical("DAY1.DXR") == ContainerName.canonical("day1.dir"),
		"%s vs %s" % [ContainerName.canonical("DAY1.DXR"), ContainerName.canonical("day1.dir")])
	h.check("canonical keeps movies and casts apart",
		ContainerName.canonical("x.dir") != ContainerName.canonical("x.cst"))
	h.complete("path resolution and Lingo agree, because they share the rule")

	# A title is free to test its packaging any way Lingo allows. This corpus
	# writes `the movieName = "day1.dxr"` and `the movieName contains "hotel"`,
	# but nothing stops another from writing any of these, and each has to keep
	# working against a converted container or the bug has only moved.
	h.begin("every way a script might test its packaging")
	var name := "day1.dir"          # what `the movieName` answers after conversion
	h.check("= against the protected spelling", LingoValue.equal(name, "day1.dxr"))
	h.check("<> against it is false", LingoValue.equal(name, "day1.dxr"))
	h.check("contains the protected extension", LingoValue.contains(name, "dxr"))
	h.check("contains the whole protected name", LingoValue.contains(name, "day1.dxr"))
	h.check("starts with the stem still works", LingoValue.starts(name, "day1"))
	h.check("starts with the protected name", LingoValue.starts(name, "day1.dxr"))
	# `the last 4 chars of the movieName = ".dxr"` -- a bare extension parses as a
	# name with an empty stem, so the same rule covers it with no special case.
	h.check("a bare extension compares equal", LingoValue.equal(".dir", ".dxr"))
	# `case the movieName of "day1.dxr":` routes through `equal`, so it follows.
	h.check("a cast name reconciles the same way", LingoValue.equal("master.cst", "master.cxt"))
	# And the negatives, which matter more here than anywhere: reconciliation
	# must not leak into text that merely mentions an extension.
	h.check("a non-container haystack is untouched",
		not LingoValue.contains("notes.txt", "dxr"))
	h.check("a movie never contains a cast extension",
		not LingoValue.contains("day1.dir", "cxt"))
	h.check("a different movie is still different",
		not LingoValue.contains("day2.dir", "day1.dxr"))
	h.complete("every way a script might test its packaging")

	quit(h.finish("container-extension equality in Lingo"))
