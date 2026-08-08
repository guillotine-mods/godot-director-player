class_name DirectorLabels
extends RefCounted
## One movie's `VWLB`: the frame markers, and the name a room announces itself by.
##
## Three rules, each of which the corpus punishes you for missing:
##
## Frames are 1-based in the chunk and 0-based everywhere in the runtime.
##
## Markers with an empty name exist — eight movies carry one to three of them —
## and must be dropped, or every later marker's index shifts and "which room am
## I in" answers with the wrong one.
##
## Duplicate names are common (one movie has the same name on 22 markers), and
## the label resolves to the *first*, which is what Director did.

const Codepage := preload("res://director/director_codepage.gd")

## Ordered `{frame:int, name:String}`, frame 0-based, empty names dropped.
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
		if start < text_base or stop > payload.size() or stop <= start:
			# A zero-length name is a real, empty marker; anything else is out
			# of range and equally not a marker.
			continue
		# A marker name is authored text, so it goes through the title's codepage
		# like every other authored string -- `go("<hebrew>")` has to match the
		# label the same way `member("<hebrew>")` matches a name.
		var name := Codepage.decode(payload.slice(start, stop)).strip_edges()
		var zero_based := frame - 1
		# An unnamed marker is kept, and that is not tidiness -- `marker(n)` counts
		# *entries*, not names, so dropping one shifts every marker after it. The
		# reference inserts one label per entry and walks all of them.
		#
		# Rating's `BATZEGOZ.dir` is the case: its `play done` sits on frame 215, an
		# unnamed marker between `egozspeak1` and `Batz2A`. Dropped, `marker(1)`
		# counted past it, `play done` never ran anywhere in the movie, and all three
		# dialogue options landed on the same destination -- the speech starting and
		# being cut off a moment later.
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
