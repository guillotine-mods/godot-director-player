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

const Score := preload("res://director/director_score.gd")

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
##   {channel, cast_name, cast_id, loc_h, loc_v, width, height, ink, stretch}
##
## `cast_name` is "" for a child in the owning cast itself.
func children(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _score == null or frame_count <= 0:
		return out
	var frame: Dictionary = _score.frame(_wrap(index))
	for sprite in frame.get("sprites", []):
		var raw := int(sprite["cast_lib"])
		var name := ""
		# DirectorScore already folded 0xFFFF to 1 for a movie's own cast; here
		# that same value means "index 0 of the ccl list", so the two cases have
		# to be told apart by whether a list exists at all.
		if not cast_list.is_empty():
			var at := raw - 1 if raw >= 1 else raw
			if at < 0 or at >= cast_list.size():
				continue
			name = cast_list[at]
			if name.strip_edges() == "":
				# A degenerate `ccl ` entry. One cast in this game has exactly
				# one, zero-length: its children are dropped rather than aimed at
				# a member that would resolve to something unrelated.
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
## The entry offsets are relative to a base a little past the end of the table,
## and how far past varies, so the base is chosen as the one that makes every
## entry a length-prefixed printable string rather than assumed.
static func read_cast_list(payload: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	if payload.size() < 8:
		return out
	var count := _be_u16(payload, 4)
	if count <= 0 or count > 64:
		return out
	var table := 6
	if table + count * 2 > payload.size():
		return out
	var offsets: Array = []
	for i in count:
		offsets.append(_be_u16(payload, table + i * 2))
	# The base is searched rather than assumed, and the test demands *plausible*
	# names, not merely parseable ones. A length byte of zero yields a valid
	# empty string, so a test that only checks bounds accepts the first base it
	# tries and returns a list of empty names — which then drops every film-loop
	# child, silently, because a child whose cast cannot be named is dropped by
	# design.
	# The offset table's width and its base both vary, and reading them wrong is
	# not loud: every offset resolving to the same entry yields a list of the
	# right length whose entries are all one cast, and every film-loop child then
	# draws from that cast — a stranger's bitmap rather than nothing.
	#
	# So the names are recovered by walking the payload for length-prefixed
	# printable strings and taking them in order. The chunk is a short ordered
	# list of cast paths and holds nothing else, which makes the scan
	# unambiguous where the table arithmetic is not.
	var at := table
	while at < payload.size() and out.size() < count:
		var length: int = payload[at]
		if length > 0 and length <= 64 and at + 1 + length <= payload.size():
			var name := payload.slice(at + 1, at + 1 + length).get_string_from_ascii()
			if _printable(name) and name.strip_edges() != "":
				out.append(name)
				at += 1 + length
				continue
		at += 1
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
