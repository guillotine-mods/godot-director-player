class_name DirectorFilmLoop
extends RefCounted
## A film loop's own miniature score: the children it draws, per loop frame.
##
## A film loop is a cast member that holds a score of its own — the same 48-byte
## sprite records and the same delta encoding as a movie's `VWSC`, so
## `DirectorScore` decodes it unchanged. What differs is one field, and getting
## it wrong is silent:
##
## In a movie's score the `u16` at offset 4 of a sprite record is the cast
## library, `0xFFFF` meaning the movie's own cast. In a loop's mini-score it is a
## **zero-based index into the owning file's `ccl ` chunk** — an ordered list of
## the external casts the loops reference, which is *not* the movie's cast-library
## order. MURDER1's libraries run internal, goldolin, hezi, tofi while its `ccl `
## runs tofi, goldolin, hezi. Read as a library index, a child lands on a real but
## unrelated member and draws a stranger's bitmap rather than nothing.
##
## So a child naming a cast the `ccl ` cannot resolve is dropped, deliberately.
## Falling back to the cast that owns the loop is the bug this reading exists to
## avoid: it draws the wrong art instead of no art, and nothing reports it.
##
## Three things have to be right together, and each of them failed silently on
## its own (bugs.md 34):
##
## 1. **The index is zero-based and is not adjusted.** `0xFFFF` means the loop's
##    own cast; every other value indexes `ccl ` directly. Subtracting one from
##    it -- which this did, to work around `DirectorScore` folding `0xFFFF` to 1
##    -- shifts every child one cast earlier, so MURDER1's `goldolin right` drew
##    out of `tofi` and its `hezi right + angry` out of `goldolin`. That is the
##    user-visible report this entry closes.
## 2. **`0xFFFF` must survive the decode.** With it folded away, "the owning
##    cast" and "`ccl ` entry 1" are the same value; `DirectorScore` now carries
##    `cast_lib_raw` beside the folded one so the two stay distinguishable.
## 3. **The list is the *loop's own* container's.** A loop member living in a
##    linked cast indexes that cast file's `ccl `, not the playing movie's --
##    which for a `.cst` is usually absent, meaning every child names its own
##    cast. `DirectorCastTable.cast_list_for` is where that is answered.
##
## Measured over the 12,111 distinct children reachable from every movie in the
## corpus, against an oracle from outside the rule (an unstretched child's
## recorded rect is its member's natural size, so at most one library can hold
## that member at that size): 9,824 children are decided by it, and the reading
## above agrees with 9,824 of them. The previous reading agreed with 6,006.

const Score := preload("res://director/director_score.gd")

## The sprite record's "my own cast" sentinel, before `DirectorScore` folds it.
const OWN_CAST := 0xFFFF
## A `ccl ` chunk is a handful of cast paths, never a hundred. A count past this
## means the chunk was not read as a `ccl ` at all.
const MAX_ENTRIES := 64

## Cast names from the owning container's `ccl `, in order. Empty when absent —
## which is itself meaningful: a file with no `ccl ` must only emit children
## naming their own cast, and any external index is unresolvable by definition.
var cast_list: PackedStringArray = PackedStringArray()
var looping := true
var frame_count := 0
var error := ""

var _score = null


## Reads the loop's `SCVW`. `cast_names` is the owning container's `ccl ` list.
func parse(payload: PackedByteArray, cast_names: PackedStringArray, is_looping: bool) -> bool:
	error = ""
	cast_list = cast_names
	looping = is_looping
	_score = Score.new()
	if not _score.parse(payload):
		error = _score.error
		_score = null
		return false
	frame_count = _score.frame_count
	return true


## The children drawn on one loop frame, low channel first. Each carries the cast
## *name* rather than a library number, because the number means something
## different here and resolving it is the caller's job through its own cast table.
##
##   {channel, cast_name, cast_id, loc_h, loc_v, width, height, ink, stretch,
##    flip_h, flip_v, has_blend, blend_amount}
##
## The rendering attributes travel with the child because a loop's children are
## sprites in their own score and carry their own ink, blend and flip; dropping
## them here makes the loop's contents draw by rules its own author did not
## write, and the omission is invisible until a title uses one.
##
## `cast_name` is "" for a child in the owning cast itself.
func children(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _score == null or frame_count <= 0:
		return out
	var frame: Dictionary = _score.frame(_wrap(index))
	for sprite in frame.get("sprites", []):
		# `cast_lib_raw`, not `cast_lib`: the folded field cannot tell "my own
		# cast" from "`ccl ` entry 1", and this is the one reader that needs to.
		var raw := int(sprite.get("cast_lib_raw", OWN_CAST))
		var name := ""
		if raw != OWN_CAST:
			# Zero-based, taken as it stands. Any adjustment here is a second
			# cast list that disagrees with the first, one entry along.
			if raw < 0 or raw >= cast_list.size():
				continue
			name = cast_list[raw]
			if name.strip_edges() == "":
				# A degenerate `ccl ` entry. Two containers in this game carry
				# exactly one, zero-length: their children are dropped rather
				# than aimed at a member that would resolve to something
				# unrelated.
				continue
		out.append({
			"channel": int(sprite["channel"]),
			"cast_name": name,
			"cast_id": int(sprite["cast_id"]),
			"loc_h": int(sprite["loc_h"]),
			"loc_v": int(sprite["loc_v"]),
			"width": int(sprite["width"]),
			"height": int(sprite["height"]),
			"ink": int(sprite["ink"]),
			"stretch": bool(sprite["stretch"]),
			"flip_h": bool(sprite["flip_h"]),
			"flip_v": bool(sprite["flip_v"]),
			"has_blend": bool(sprite["has_blend"]),
			"blend_amount": int(sprite["blend_amount"]),
		})
	return out


## A loop that does not loop holds on its last frame rather than restarting.
func _wrap(index: int) -> int:
	if frame_count <= 0:
		return 0
	if looping:
		return index % frame_count
	return mini(index, frame_count - 1)


## The `ccl ` chunk: the ordered external casts a file's film loops reference.
##
##     <u32 4> <u16 count> then count+1 big-endian u32 offsets, then the entries
##     as length-prefixed strings, offset 0 being the first
##
## The offsets are relative to a base a little past the end of the table, and how
## far past varies between files, so the base is chosen as the one that makes
## every entry a length-prefixed printable string rather than assumed.
##
## Reading this as a *scan* for length-prefixed printable strings -- which it was,
## because the table arithmetic was got wrong once and the scan looked robust --
## is order-preserving and still wrong, because the payload holds bytes that scan
## as entries and are not. ALLIN's chunk yields a spurious `"` ahead of the real
## seven, which shifts every index by one and loses the eighth; DAY1's yields
## `...\PIP2DATA\won` where the entry is `C:\...\PIP2DATA\wonder.cst`, which is
## what the `won`-as-a-prefix-of-`wonder` incident was actually made of. The table
## read recovers both, and agrees with the scan on the other 26 `ccl ` chunks in
## the corpus. `tools/director_film_loops.py:parse_ccl` reads it the same way and
## is the reading validated against 2,145 children.
##
## An empty result is meaningful rather than a failure: the loops in this file
## reference nothing outside their own cast, which is what a count of 0 says and
## what a file with no `ccl ` at all says.
static func read_cast_list(payload: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	if payload.size() < 10:
		return out
	var count := _be_u16(payload, 4)
	if count <= 0 or count > MAX_ENTRIES:
		return out
	var table_end := 6 + 4 * (count + 1)
	if table_end + 2 > payload.size():
		return out
	var offsets: Array = []
	for i in count + 1:
		offsets.append(_be_u32(payload, 6 + 4 * i))
	# The shape of the table is what says it was read at the right width: the
	# first entry starts at 0 and they only ever go forwards. Read as u16 the
	# same bytes come out as a plausible-looking list of alternating zeroes, so
	# this test is the one thing standing between a wrong width and a cast list
	# that is the right length and names the wrong casts.
	if int(offsets[0]) != 0:
		return out
	for i in range(1, offsets.size()):
		if int(offsets[i]) < int(offsets[i - 1]):
			return out
	# The test demands *plausible* names, not merely parseable ones. A length byte
	# of zero yields a valid empty string, so a test that only checks bounds
	# accepts the first base it tries and returns a list of empty names -- which
	# then drops every film-loop child, silently, because a child whose cast
	# cannot be named is dropped by design.
	for base in [table_end + 2, table_end, table_end + 1, table_end + 3]:
		var entries := PackedStringArray()
		for i in count:
			var start: int = base + int(offsets[i])
			if start >= payload.size():
				break
			var stop: int = start + 1 + payload[start]
			if stop > payload.size():
				break
			var name := payload.slice(start + 1, stop).get_string_from_ascii()
			if not _printable(name):
				break
			entries.append(name)
		if entries.size() == count:
			return entries
	return out


## Cast names are plain identifiers. Anything else means the base is wrong.
static func _printable(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 0x20 or c > 0x7E:
			return false
	return true


static func _be_u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
