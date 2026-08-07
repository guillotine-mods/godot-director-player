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
## **Unexercised by this corpus**, which ships no palette member and no `CLUT`
## chunk at all (`tools/palette_survey.gd`), and cycles zero times.

const Palette := preload("res://director/director_palette.gd")


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
static func table_for(id: int, table) -> PackedByteArray:
	if id < 0:
		return Palette.builtin(id) if Palette.can_build(id) else PackedByteArray()
	if id == 0 or table == null:
		return PackedByteArray()
	for lib in libs(table):
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
