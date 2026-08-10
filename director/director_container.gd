extends RefCounted
## When two names mean the same Director container.
##
## Title-agnostic, dependency-free, and the single authority on this question.
## Everything that compares or resolves a container name goes through here rather
## than carrying its own table: path resolution, Lingo's `=` and `<>`, and
## anything added later. The rule was originally implemented twice, once in
## `director_paths.gd` and once in `lingo_value.gd`, which is how a rule quietly
## becomes two rules that disagree.
##
## `.dxr` is a protected `.dir` and `.cxt` a protected `.cst`; `.dcr` and `.cct`
## are the Shockwave forms. They are packaging, not identity — the same movie,
## saved differently.
##
## Director never had to think about it, because a shipped title was protected
## throughout and the spelling in the source always matched the spelling on disc.
## Converting the originals to editable containers breaks that agreement, and it
## breaks it silently: a comparison answers false and a lookup finds nothing, and
## neither is an error.
##
## Piposh 2 shows both halves. Its scripts name `.dxr` in 18 places and `.dir` in
## 21 for the *same* movies while every file on the original disc is `.dxr`, so
## Director was already substituting extensions at runtime. And
## `the movieName = "day1.dxr"` — the only exact filename comparison in the whole
## corpus, four sites — gates the entire cursor assignment in `cursorfunk` and,
## twice, the `go` that changes room when a walk completes.
##
## Deliberately **not** extension-blind. A movie is never a cast: `x.dir` and
## `x.cst` stay different, because conflating them would resolve a movie to a
## cast file and fail somewhere much further along.

## Movie containers, in order of preference when a canonical spelling is wanted.
const MOVIE := ["dir", "dxr", "dcr"]
## Cast containers, likewise.
const CAST := ["cst", "cxt", "cct"]
## Every extension this engine recognises as a container.
const ALL := ["dir", "dxr", "dcr", "cst", "cxt", "cct"]


## The family an extension belongs to, or `[]` if it names no container.
static func family_of(extension: String) -> Array:
	var lower := extension.to_lower()
	if MOVIE.has(lower):
		return MOVIE
	if CAST.has(lower):
		return CAST
	return []


static func is_container(name: String) -> bool:
	return not family_of(name.get_extension()).is_empty()


## Every spelling that could name the same container, **the given one first**.
##
## Order matters: a title that ships both a `.dir` and a `.dxr` of one movie must
## get the one the caller asked for, and only fall back when that does not exist.
## **A name with no extension is a container reference too, and Director appends
## the extension itself.** `the fileName of window` is the common way to write one
## -- Director's own documentation spells it without a suffix -- and a movie that
## opens a Movie-in-a-Window is the case that depends on it:
##
##     LevelsWindow.fileName = "@" & DirChar & DirChar & "levels" & DirChar & "levels"
##     open(LevelsWindow)
##
## That is Itamar Park's level select, and with no extension tried the window
## never opened. What that looks like from outside is the part worth recording:
## the frame behind it is `on exitFrame / go(the frame)`, an ordinary hold, so the
## movie sat on frame 2 for ever with no error, no hang and nothing in the
## diagnostics -- a legitimate wait for something that was never coming. A
## reference that resolves to nothing is reported; one that is never tried is not.
##
## Both families are offered, movies first: the extension is absent precisely
## because the caller did not care which packaging exists, and a window names a
## movie far more often than a cast.
static func spellings(name: String) -> Array:
	var out: Array = [name]
	var extension := name.get_extension().to_lower()
	var family := family_of(extension)
	if family.is_empty():
		# Nothing after the last dot is not the same as no dot at all: `a.b/c` has
		# no extension of its own, and `get_basename` on it would eat the folder.
		if extension == "" and not name.ends_with("."):
			for other in MOVIE + CAST:
				out.append("%s.%s" % [name, other])
		return out
	var stem := name.get_basename()
	for other in family:
		if other != extension:
			out.append("%s.%s" % [stem, other])
	return out


## Do two names identify the same container?
##
## Case-insensitive, as Lingo compares strings. A name with no extension is not a
## container name and never matches one — `day1` is not `day1.dxr`, because
## treating a bare stem as a container would make far too much compare equal.
static func same(a: String, b: String) -> bool:
	var lower_a := a.to_lower()
	var lower_b := b.to_lower()
	if lower_a == lower_b:
		return true
	var ext_a := lower_a.get_extension()
	var ext_b := lower_b.get_extension()
	if ext_a == "" or ext_b == "" or ext_a == ext_b:
		return false
	var family := family_of(ext_a)
	if family.is_empty() or not family.has(ext_b):
		return false
	return lower_a.get_basename() == lower_b.get_basename()


## One spelling per container, for use as a dictionary key. The family's first
## extension wins, so `DAY1.DXR` and `day1.dir` both key as `day1.dir`.
static func canonical(name: String) -> String:
	var lower := name.to_lower()
	var family := family_of(lower.get_extension())
	if family.is_empty():
		return lower
	return "%s.%s" % [lower.get_basename(), family[0]]


## Every spelling of `text` when `text` is itself a container name, the given one
## first; otherwise just `text`.
##
## This exists so that reconciliation is not limited to `=`. A title is free to
## test its packaging any way Lingo allows, and this corpus already shows two
## shapes -- `the movieName = "day1.dxr"` and `the movieName contains "hotel"`.
## A third title might well write `the movieName contains "dxr"`, or
## `the last 4 chars of the movieName = ".dxr"`, and each of those has to keep
## working against a converted `.dir` or the engine has simply moved the bug.
##
## Bare extensions are covered by the same rule without a special case: `.dir`
## and `.dxr` parse as names with an empty stem, so `same()` already answers true
## for them.
static func alternatives(text: String) -> Array:
	if not is_container(text):
		return [text]
	return spellings(text)
