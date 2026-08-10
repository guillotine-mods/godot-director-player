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
## **Unexercised by the six shipped titles**, which ship no palette member and no
## `CLUT` chunk at all (`tools/palette_survey.gd`), and cycle zero times.
## `itamar-park` exercises all of it: 162 `CLUT` chunks, 145 palette members, and
## a palette named by 655 of its 657 bitmap members.

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
## same id has to see the mutation. It is also why the six shipped titles do not
## move — every one of their bitmaps names system Mac, which is the id their
## stage is on from the first frame to the last.
##
## A palette this port cannot build — `itamar-magichat`'s 881 members naming the
## Windows D5 table, `piposh-dream`'s 167 naming a member no cast in that title
## holds — falls back to the stage table rather than to a guess, which is the
## same substitution `DirectorPalette.builtin` makes and for the same reason.
static func table_for_member(m: Dictionary, table, stage: PackedByteArray,
		stage_id: int) -> PackedByteArray:
	var id := int(m.get("palette_id", Palette.SYSTEM_MAC))
	if id == stage_id:
		return stage
	var own := table_for(id, table, int(m.get("palette_lib", 0)))
	return own if own.size() == Palette.TABLE_BYTES else stage
