class_name DirectorLabels
extends RefCounted
## One movie's `VWLB`: the frame markers, and the name a room announces itself by.
##
## Four rules, each of which the corpus punishes you for missing:
##
## Frames are 1-based in the chunk and 0-based everywhere in the runtime.
##
## **An entry is never dropped; only its name can be unreadable.** `marker(n)`
## counts *entries*, not names, so a `continue` anywhere in `parse` renumbers
## every marker after it. This file said the opposite for a long time — "markers
## with an empty name … must be dropped, or every later marker's index shifts" —
## and it is exactly backwards: dropping one is what shifts the index. Markers
## with an empty name are not rare and not decoration, they are how an author
## marks a frame only the score needs to reach: 2,236 of Rating's 4,220 entries,
## and 12 of Piposh 2's 3,019. `tools/label_index.gd` is the gate that this
## reader produces one marker per entry, because the failure is silent —
## `bugs.md` 40 is the player-visible half, and it survived a commit that
## rewrote the comment below without moving the guard that caused it.
##
## The chunk's u16s are **big-endian** even in a little-endian `XFIR` container.
## `DirectorFile.read_chunk` hands back the payload bytes untouched, and read
## big-endian the label frames and names come out matching the movie; read
## little-endian BATZEGOZ's 28 entries read as 7,168.
##
## Duplicate names are common (one movie has the same name on 22 markers), and
## the label resolves to the *first*, which is what Director did.

const Codepage := preload("res://director/director_codepage.gd")

## Ordered `{frame:int, name:String}`, frame 0-based, one per chunk entry —
## including the unnamed ones, whose `name` is "". This is `marker(n)`'s index
## space, so its size is the chunk's own count and nothing may filter it.
var markers: Array[Dictionary] = []
## Lowercased name -> 0-based frame, first occurrence wins.
var labels: Dictionary = {}
var error: String = ""


func parse(payload: PackedByteArray) -> bool:
	error = ""
	markers.clear()
	labels.clear()
	if payload.size() < 2:
		error = "VWLB too short (%d bytes)" % payload.size()
		return false

	var count := _u16(payload, 0)
	# One pair beyond the count is a sentinel whose offset ends the name blob.
	var pairs_at := 2
	var text_base := pairs_at + 4 * (count + 1)
	if text_base > payload.size():
		error = "VWLB claims %d markers, past the end of the chunk" % count
		return false

	for i in count:
		var at := pairs_at + i * 4
		var frame := _u16(payload, at)
		var start := text_base + _u16(payload, at + 2)
		var stop := text_base + _u16(payload, at + 6)
		# The offset pair decides the *name* and never the entry's existence. The
		# reference inserts one `Label` per entry and `getNextLabelNumber` walks the
		# lot, so a `continue` here is a renumbering: every `marker(n)` in the movie
		# counts to the wrong frame from this entry onward, and nothing reports it.
		#
		# Two reasons a name can be missing, and neither is a reason to lose the
		# frame. `start == stop` is a real unnamed marker, which is the common case.
		# A range outside the name blob is a decode this reader cannot honour, and an
		# entry whose name we could not read is still an entry at a frame.
		#
		# Rating's `BATZEGOZ.dir` is what the drop cost: its `play done` sits on
		# chunk frame 215, an unnamed marker between `egozspeak1` and `Batz2A`.
		# Dropped, `go(marker(1))` out of the talking loop counted past it to
		# `Batz2A`, `play done` never ran anywhere in the movie, the `mouseUp` parked
		# by `play frame` was never resumed, and all three dialogue options answered
		# with the first one's reply (`bugs.md` 40).
		var name := ""
		if stop > start and start >= text_base and stop <= payload.size():
			# A marker name is authored text, so it goes through the title's codepage
			# like every other authored string -- `go("<hebrew>")` has to match the
			# label the same way `member("<hebrew>")` matches a name.
			name = Codepage.decode(payload.slice(start, stop)).strip_edges()
		var zero_based := frame - 1
		markers.append({"frame": zero_based, "name": name})
		if name == "":
			continue
		var key := name.to_lower()
		if not labels.has(key):
			labels[key] = zero_based
	return true


## The marker covering a frame: the last one at or before it, or "".
func marker_at(frame: int) -> String:
	var found := ""
	for marker in markers:
		if int(marker["frame"]) <= frame:
			# Carried for `marker(n)`'s counting, but an unnamed marker is not an
			# answer to "what room is this" -- the last *named* one stands.
			if str(marker["name"]) != "":
				found = str(marker["name"])
		else:
			break
	return found


static func _u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]
