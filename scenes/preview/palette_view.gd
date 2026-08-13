extends RefCounted
## Resolving a palette id to a colour table.
##
## Small, and separate for one reason: **a palette change invalidates every
## decoded bitmap.** An indexed member is decoded *through* the table, so the
## texture cache is artwork baked against a palette; keeping it across a switch
## draws the new frame in the old colours, which reads as an ink fault rather
## than a palette one. That coupling between "the palette moved" and "throw the
## artwork away" is easy to forget and expensive to debug, so the two live next
## to each other here rather than at opposite ends of a 4,000-line file.
##
## It is also the price of an RGB renderer that Director did not pay: Director
## swaps a CLUT and the same pixels mean new colours. It costs nothing until
## something actually switches.
##
## **Barely exercised by the six shipped titles, but not unexercised**, which is
## what this said and what `tools/palette_survey.gd` was read as proving. Measured
## over all six by `tools/palette_corpus.gd`: `piposh-ru` ships **3 `CLUT` chunks
## and 3 palette members**, and they cycle zero times. `itamar-park` exercises the
## rest of it: 162 `CLUT` chunks, 145 palette members, and a palette named by 655
## of its 657 bitmap members.

const Palette := preload("res://director/director_palette.gd")

## "The caller does not know what palette the stage is on." No member's palette
## id can equal it, so a member that names a buildable palette always gets its
## own — which is what a diagnostic with no running movie should draw.
const NO_STAGE_ID := 0x7FFFFFFF


## Every cast library this movie can reach, its own first.
static func libs(table) -> Array:
	var out: Array = [1]
	for lib in table.cast_libs.keys():
		if int(lib) != 1:
			out.append(int(lib))
	return out


## An id to a colour table, for the state machine's resolution order. Empty means
## "not loaded", which is what makes the re-check at every step meaningful.
##
## A negative id is a built-in and `director_palette.gd` answers for it; a
## positive one is a palette cast member, whose `CLUT` chunk is its payload the
## same way a bitmap's `BITD` is. Searched across every library this movie can
## address rather than assuming library 1: a palette in a shared cast is exactly
## the case that would resolve to the wrong member by number alone.
## `prefer_lib` is the library the id was named *from* — the score's palette
## channel and a bitmap member's palette field both carry one — and it is tried
## first rather than trusted outright, because Director tolerates a reference
## whose library no longer holds the member. 0 and -1 both mean "no opinion":
## Director writes -1 for "my own cast" in a member's palette field and 1024 for
## the same thing in the score, which `director_score.gd` has already folded to 1
## by the time this sees it.
##
## **The score's palette channel carries a library too and does not get to use
## it**, because `director_palette_state.gd` keys everything on the id alone —
## `table_for` there is `func(id) -> table`, `current_id` is one number, and the
## save format writes four of them. Threading a library through all of that is a
## real change and it buys nothing measurable today: over both test corpora every
## one of the 32 frames that names a palette resolves to the same table with the
## library and without it, because no cast holds a *palette* member at a number
## another cast also holds a palette member at. The first title where those two
## answers differ is the one that pays for the refactor.
static func table_for(id: int, table, prefer_lib: int = 0) -> PackedByteArray:
	if id < 0:
		return Palette.builtin(id) if Palette.can_build(id) else PackedByteArray()
	if id == 0 or table == null:
		return PackedByteArray()
	var order: Array = libs(table)
	if prefer_lib > 0 and order.has(prefer_lib):
		order = [prefer_lib] + order
	for lib in order:
		var m: Dictionary = table.get_member(lib, id)
		if m.is_empty() or int(m.get("type", 0)) != Palette.MEMBER_TYPE:
			continue
		var chunk_id := int(m.get("data_chunk_id", -1))
		if chunk_id < 0:
			continue
		var f = table.file_for(lib)
		if f == null:
			continue
		return Palette.from_clut(f.read_chunk(chunk_id))
	return PackedByteArray()


## The table one bitmap member's indices are numbers in.
##
## **A member's pixels mean what its own palette says they mean, not what the
## stage happens to be holding.** Director on an 8-bit screen has one CLUT and
## blits indices straight into it, so the score's palette channel is what makes
## artwork the right colour; on a 16-bit or deeper screen — which is what every
## one of these movies declares, `movieDepth` 32 in the config chunk — it
## converts each bitmap through the palette the *member* names and the screen
## CLUT stops reaching bitmaps at all. The port's stage is true colour, so it is
## the second path it has to reproduce.
##
## Measured, because the two readings are not close. Over `itamar-park`'s three
## scores there are 5,692 (frame, bitmap sprite) pairs whose member names a
## palette, and the stage is holding that palette for **22** of them: 5,670 name
## something else, almost always the cast member immediately before the bitmap,
## which is what Director writes when artwork is imported with its own palette.
## Drawing that title through the stage palette makes 99.6% of its artwork the
## wrong colour, and it shipped, so Director was not drawing it that way.
##
## **The stage table still wins when the member names the palette the stage is
## already on**, and that is what keeps §11's fades and cycles visible: they
## mutate the stage table in place under an unchanged id, so a member naming that
## same id has to see the mutation.
##
## **It is not true that every bitmap in the six shipped titles names system Mac**,
## which this paragraph used to claim as the reason none of them could move. Of
## 118,991 bitmaps, 118,747 name system Mac, **244 name the Windows D5 table** and
## **167 name a member that is not a palette** (`tools/palette_corpus.gd`). The
## last group is what `bugs.md` 104 was.
##
## **A palette that does not resolve falls back to system Mac, not to the stage.**
## This returned `stage` until `bugs.md` 104, and its own docstring carried the
## contradiction: it said the substitution was "the same one
## `DirectorPalette.builtin` makes and for the same reason", and `builtin`
## substitutes system Mac.
##
## The reference is unambiguous and it is one line —
## `castmember/bitmap.cpp:484`, `getDitherImg` case 8:
##
##     CastMemberID palIndex = pals.contains(castPaletteId)
##         ? castPaletteId : CastMemberID(kClutSystemMac, -1);
##
## `srcPal` is what turns the member's indices into RGB, and on a true-colour
## stage (`targetBpp != 1`) that branch is entered for every 8-bit bitmap. So a
## member naming a palette the engine has not loaded is drawn through system Mac
## whatever the stage is holding. The 4-bit case at `:461` says the same thing
## again, and `movie.cpp:290` and `builtin()` both substitute system Mac for the
## same reason: it is Director's own default, so it is the one guess that is not
## a guess.
##
## **Measured, on the report that found it.** `piposh-dream/dinner1.dir` #87 is a
## 738x439 close-up of Piposh and names palette member 154, which is a film loop
## in that cast — so it does not resolve. Six of that title's movies declare the
## Windows D5 table as their default (`-102`), and `director_palette_state.reset`
## starts the stage there, so entering one of them anywhere but its frame 0 left
## #87 drawn through Win D5: skin `#a0a0a4`, which is Win D5 index 8 and is not
## in system Mac at all, against `#ffcc99` at the same index in system Mac. The
## player's screenshot carried 214,739 pixels of `#a0a0a4`. Falling back here is
## what fixes it, and **not** the -102 default, which is read correctly and which
## the reference keeps too: `movie.cpp:287` substitutes only when it does *not*
## have the palette, and it has that one.
##
## Corpus-wide this reaches 167 members, all in `piposh-dream`, of which the 81
## in a Windows-default movie change colour and the other 86 do not — their stage
## was already system Mac. `itamar-magichat`'s 881 members naming the Windows D5
## table are no longer in this population at all: `data/director_palettes.json`
## supplies -102, so they resolve.
##
## One consequence worth stating so it does not get "fixed" back: a member in
## this state no longer sees a running fade or cycle, because it is no longer
## reading the stage's mutating table. That is the reference's behaviour — in
## true colour the dither branch runs regardless of `isColorCycling` — and the
## `id == stage_id` short-circuit above is what still carries §11's effects to
## every member that names the palette the stage is actually on.
static func table_for_member(m: Dictionary, table, stage: PackedByteArray,
		stage_id: int) -> PackedByteArray:
	var id := int(m.get("palette_id", Palette.SYSTEM_MAC))
	if id == stage_id:
		return stage
	var own := table_for(id, table, int(m.get("palette_lib", 0)))
	if own.size() == Palette.TABLE_BYTES:
		return own
	return Palette.builtin(Palette.SYSTEM_MAC)
