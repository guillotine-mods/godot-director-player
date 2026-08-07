extends RefCounted
## Writing a Director container back out: `saveMovie`, at the byte level.
##
## Title-agnostic. Nothing here knows what game is loaded, and nothing here
## decides *which* chunks change -- it is handed a set of replacement payloads
## and re-emits the container around them.
##
## **The whole file is preserved byte for byte except the chunks named.** It is
## not re-laid-out and it is not rebuilt from a parse: everything this port does
## not yet decode -- `Lscr` bytecode, `Lctx`, `FXmp`, `XTRl`, the `free` list --
## survives because it is copied, not understood. A writer that re-emitted only
## the chunks it can parse would silently produce a movie missing its scripts,
## and the failure would look like "the port stopped running the save movie's
## Lingo" rather than like a broken writer.
##
## So a replacement lands one of two ways:
##
##   fits    the new payload is no larger than the old, so it is written over the
##           old one and only the chunk header's and the mmap entry's size change.
##   grows   the new payload is larger, so it is appended at the end of the file
##           and the mmap entry is repointed. The old bytes become dead space.
##
## Dead space is left dead rather than returned to the `free` list. Director kept
## one (this corpus's `HEZSAVE.DIR` carries 656 `free` entries and a `freeHead`
## in the mmap header) and reusing it would be the faithful thing; not reusing it
## costs a few hundred bytes per save on a file the game rewrites, and gets the
## allocator wrong in no way at all. `ENGINE_TODO.md` carries it.
##
## **The mmap is patched, never grown.** No entry is added, because no chunk is
## added: every replacement reuses the id it replaced. That is what makes this
## safe against everything that refers to a chunk *by id* -- `CAS*`, `KEY*` and
## the cast members' own `data_chunk_id` all keep pointing at the right thing.
##
## The odd-length case is real and is this corpus's save file: `HEZSAVE.DIR` is
## 137,655 bytes and its `RIFX` size field claims 137,656, because RIFF pads to
## an even boundary and the pad byte was never written. So the size fields are
## computed from the *padded* length, exactly as the original was.

const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")


## Re-emit `source` with `replacements` (chunk id -> new payload) applied, at
## `target_path`.
##
## Returns "" on success, or the reason it refused. It refuses rather than
## half-writing: the new container is built in memory, written to a sibling temp
## file, **reopened and read back**, and only then moved over the target. A movie
## that does not round-trip never reaches the target, because the alternative is
## destroying a game file that a failed save had no business touching.
##
## `source` must be an open `DirectorFile`. Its own handle is not used for the
## bytes -- they are re-read from `source.path` -- so the caller may hold it open
## across the call. It *does* have to be closed before the move on a platform
## that will not rename over an open file, which is the caller's business and is
## documented at `scenes/preview/movie_save.gd`.
static func rewrite(source, target_path: String, replacements: Dictionary) -> String:
	if source == null or str(source.path) == "":
		return "no source container"
	if target_path == "":
		return "no target path"
	if replacements.is_empty():
		return "nothing to write"

	var data := FileAccess.get_file_as_bytes(str(source.path))
	if data.is_empty():
		return "cannot re-read %s" % source.path
	var big: bool = bool(source.big_endian)
	var entries_at: int = int(source.mmap_offset) + ContainerFile.CHUNK_HEADER \
		+ int(source.mmap_header_len)
	var entry_len: int = int(source.mmap_entry_len)
	if entry_len < 12 or entries_at <= 0:
		return "unusable memory map"

	for id_value in replacements:
		var id := int(id_value)
		if id <= 0 or id >= source.chunks.size():
			return "no chunk %d to replace" % id
		var entry: Dictionary = source.chunks[id]
		if entry["tag"] in ContainerFile.NON_PAYLOAD_TAGS:
			return "chunk %d is a %s placeholder" % [id, entry["tag"]]
		var payload: PackedByteArray = replacements[id_value]
		var at: int = entries_at + id * entry_len
		if at + entry_len > data.size():
			return "mmap entry %d is outside the file" % id

		var offset := int(entry["offset"])
		if offset < 0 or offset + ContainerFile.CHUNK_HEADER + int(entry["size"]) > data.size():
			return "chunk %d (%s) runs past the end of %s" % [
				id, entry["tag"], source.path]
		if payload.size() <= int(entry["size"]):
			# Fits where it was. Only the two size fields move.
			for i in payload.size():
				data[offset + ContainerFile.CHUNK_HEADER + i] = payload[i]
		else:
			# Grows: append, keeping chunks on even boundaries as RIFF does.
			if data.size() % 2 == 1:
				data.append(0)
			offset = data.size()
			# The chunk's own header carries the same tag the map does, in the
			# container's byte order -- so it is copied from the entry rather
			# than re-encoded, and an `XFIR` file's reversed tag stays reversed.
			for i in 4:
				data.append(data[at + i])
			data.append_array(_u32(payload.size(), big))
			data.append_array(payload)
		_put_u32(data, offset + 4, payload.size(), big)
		_put_u32(data, at + 4, payload.size(), big)
		_put_u32(data, at + 8, offset, big)

	# The container's own extent, in the two places it is recorded: the `RIFX`
	# header at offset 4, and mmap entry 0. Both are the padded length less the
	# eight bytes of the header they follow.
	var padded: int = data.size() + (data.size() % 2)
	_put_u32(data, 4, padded - ContainerFile.CHUNK_HEADER, big)
	_put_u32(data, entries_at + 4, padded - ContainerFile.CHUNK_HEADER, big)

	var temp_path := target_path + ".saving"
	var out := FileAccess.open(temp_path, FileAccess.WRITE)
	if out == null:
		return "cannot write %s: %s" % [temp_path,
			error_string(FileAccess.get_open_error())]
	out.store_buffer(data)
	out.close()

	var proof := _verify(temp_path, replacements)
	if proof != "":
		DirAccess.remove_absolute(temp_path)
		return proof
	return _move_over(temp_path, target_path)


## Does the file just written open as a container, and does every chunk that was
## replaced read back exactly what was put in it?
##
## This is the whole safety argument, so it asks the engine's own reader rather
## than re-checking the arithmetic that produced the file. A writer that verifies
## itself against its own model of the format proves only that it is
## self-consistent; this proves the reader can open what the writer produced,
## which is the only property that matters.
static func _verify(temp_path: String, replacements: Dictionary) -> String:
	var check := ContainerFile.new()
	if not check.open(temp_path):
		return "rewritten container will not open: %s" % check.error
	var bad: Array[int] = check.out_of_bounds()
	if not bad.is_empty():
		check.close()
		return "%d chunks fall outside the rewritten container" % bad.size()
	for id_value in replacements:
		var want: PackedByteArray = replacements[id_value]
		var got: PackedByteArray = check.read_chunk(int(id_value))
		if got != want:
			check.close()
			return "chunk %d read back %d bytes of %d" % [
				int(id_value), got.size(), want.size()]
	# A movie without a readable cast is not a movie, and a cast that no longer
	# parses is exactly what a mis-sized `STXT` would produce.
	var cast := Cast.new()
	var opened: bool = cast.open(check)
	check.close()
	if not opened:
		return "rewritten container has no readable cast"
	return ""


## Put the verified file where the movie asked for it.
##
## Remove-then-rename rather than a straight overwrite, because an overwrite
## truncates the target first and a failure after that point leaves nothing to
## recover. The target only ceases to exist once a complete, verified replacement
## is sitting beside it.
static func _move_over(temp_path: String, target_path: String) -> String:
	if FileAccess.file_exists(target_path):
		var gone := DirAccess.remove_absolute(target_path)
		if gone != OK:
			DirAccess.remove_absolute(temp_path)
			return "cannot replace %s: %s" % [target_path, error_string(gone)]
	var moved := DirAccess.rename_absolute(temp_path, target_path)
	if moved != OK:
		# The verified replacement is still on disk under its temp name, and the
		# message says so: this is the one failure that can leave the target
		# missing, and the recovery is a rename a human can perform.
		return "cannot move %s into place: %s (the saved movie is at %s)" % [
			target_path, error_string(moved), temp_path]
	return ""


# ------------------------------------------------------------------ STXT

## A field member's `STXT` chunk carrying `text` instead of what it held.
##
## Built from the old payload rather than from scratch, for the same reason the
## container is: an `STXT` is a 12-byte header, the characters, and a run table,
## and only the middle of those three is being changed. The run table is the
## member's *styling* -- point size, slant, colour, line height -- and re-emitting
## a default one would silently restyle every field a save touches.
##
## The header is `{offset to the text, length of the text, length of the run
## table}`, all big-endian regardless of the container's byte order, which is the
## same rule `director_cast.gd` reads it under. Anything between the header and
## the text (there is none in this corpus, where the offset is 12 in all 321
## field members) is carried across rather than dropped.
##
## Run offsets are character positions, so a run that started past the end of a
## now-shorter string is clamped to it. Every field member in this corpus
## declares exactly one run, starting at 0, so the clamp is written from the
## format rather than measured -- it is what keeps a multi-run member from
## pointing outside its own text.
##
## Returns `[]` when the old payload is not an `STXT` this can rebuild, which the
## caller must treat as a refusal rather than as an empty chunk.
static func stxt_with_text(old: PackedByteArray, text: String) -> PackedByteArray:
	if old.size() < 12:
		return PackedByteArray()
	var offset := _be_u32(old, 0)
	var length := _be_u32(old, 4)
	if offset < 12 or offset + length > old.size():
		return PackedByteArray()

	var body := _to_bytes(text)
	var runs := old.slice(offset + length, old.size())
	if runs.size() >= 2:
		var count := (runs[0] << 8) | runs[1]
		for i in count:
			var at := 2 + i * 20
			if at + 20 > runs.size():
				break
			var start := mini(_be_u32(runs, at), body.size())
			runs[at] = (start >> 24) & 0xff
			runs[at + 1] = (start >> 16) & 0xff
			runs[at + 2] = (start >> 8) & 0xff
			runs[at + 3] = start & 0xff

	var out := PackedByteArray()
	out.append_array(_be(offset))
	out.append_array(_be(body.size()))
	out.append_array(_be(runs.size()))
	# Whatever sat between the header and the text, if a container ever puts
	# anything there.
	out.append_array(old.slice(12, offset))
	out.append_array(body)
	out.append_array(runs)
	return out


## Lingo's line separator is the Mac carriage return, and `director_cast.gd`
## turns it into `\n` on the way in. This is the other half of that.
##
## One byte per character, because that is how the text was read: Director wrote
## these fields in a single-byte Mac codepage -- this game's are Hebrew -- and
## `get_string_from_ascii` maps each byte to the code point of the same value.
## Writing them back the same way is exactly lossless for anything that came out
## of a container. A character that could not have come from one is written as
## `?` rather than as a multi-byte sequence the reader would split.
static func _to_bytes(text: String) -> PackedByteArray:
	var flat := text.replace("\r\n", "\r").replace("\n", "\r")
	var out := PackedByteArray()
	for i in flat.length():
		var c := flat.unicode_at(i)
		out.append(c if c < 256 else 0x3f)
	return out


static func _be(value: int) -> PackedByteArray:
	return PackedByteArray([
		(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff])


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _u32(value: int, big: bool) -> PackedByteArray:
	var out := _be(value)
	if not big:
		out.reverse()
	return out


static func _put_u32(d: PackedByteArray, at: int, value: int, big: bool) -> void:
	var raw := _u32(value, big)
	for i in 4:
		d[at + i] = raw[i]
