extends SceneTree
## A file on disc is bytes in the title's script system, both ways.
##
##   godot --headless --script tools/lingo_file_codepage.gd -- --allow-writes
##
## `director/director_codepage.gd` settled this for **container** text — member
## names, field text, Lingo source — and the two Lingo file paths kept decoding
## UTF-8 for another year, which is a different answer to the same question about
## the same title's own bytes:
##
##   `lingo/lingo_fileio.gd`    `FileIO`'s `readFile`/`writeString`, which is what
##                              `LoadFileToField` is built on.
##   `lingo/lingo_buddyapi.gd`  `baReadIni`/`baWriteIni`, which is how both Itamar
##                              titles read every configured string they own.
##
## What it cost, photographed: Magic Hat's login panel lists its saved players
## from `magichat.ini`'s `[users] names=[...]`, and drew them as `?????` and
## `????1234567890`. The digits came through and every Hebrew letter did not,
## which is the signature of a UTF-8 decoder meeting single-byte text — not of a
## missing font, and not of a file that is not there.
##
## Three assertions, and the third is the one that makes the other two safe:
##
##   read     bytes written raw in the active codepage come back as the
##            characters that codepage assigns them.
##   write    text handed to `writeString` reaches the disc as those same bytes,
##            so a file this port writes is a file the original could read.
##   round    write-then-read is the identity, through both APIs. A reader and a
##            writer that disagree by one byte corrupt a save rather than
##            failing, so fixing one half alone is worse than fixing neither.
##
## Title-agnostic: the fixture is built from whatever `Codepage.active()` is, so
## this asserts the *mechanism* rather than Hebrew. Under the identity codepage
## it still has content — every byte 0x80-0xFF maps to its own code point there,
## which UTF-8 also cannot represent one byte at a time.

const Harness := preload("res://tools/lib/harness.gd")
## Preloaded rather than reached by `class_name`, for the reason
## `tools/lingo_scope_check.gd` gives at its own preload.
const Codepage := preload("res://director/director_codepage.gd")
const FileIO := preload("res://lingo/lingo_fileio.gd")
const BuddyAPI := preload("res://lingo/lingo_buddyapi.gd")


## Every high byte the active codepage can carry back out again, as text.
##
## Built from the codepage rather than written down: a fixture with Hebrew
## letters in it would assert this project's corpus instead of the mechanism, and
## would be untestable the day somebody points the engine at a Cyrillic title.
func _high_text() -> String:
	var raw := PackedByteArray()
	for byte in range(0xA0, 0x100):
		raw.append(byte)
	var text := Codepage.decode(raw)
	# Only the characters that survive an encode are fair to assert on: a Mac
	# script system keeps two spellings of some ASCII, so `decode` is one-to-one
	# and `encode` is not, and the ambiguous ones are the encoder's business
	# (`tools/text_codepage.gd` owns that claim).
	var out := ""
	for i in text.length():
		var point := text.unicode_at(i)
		if Codepage.can_hold(point) and point >= 0x80:
			out += String.chr(point)
	return out


func _init() -> void:
	var h := Harness.new()
	var preview: Node = (load("res://scenes/director_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame

	# **`user://`, and a null host, so nothing is written inside a corpus.** The
	# first version took `FileIO.game_root()` and wrote its fixture into
	# `games/piposh2` -- a git submodule holding somebody's saves, and the one
	# tree a harness must never touch. `FileIO.under_root` lets a null host choose
	# its own path (its own note says so: "a harness driving the Xtra directly...
	# there is nothing to protect it from"), and `normalise` protects `user://`
	# from the Mac colon rewrite, so this is the supported spelling rather than a
	# way round the guard.
	var host = null
	var root_dir := "user://"
	var title := "the fixture has something to assert"
	h.begin(title)
	var sample := _high_text()
	h.check("the active codepage carries high bytes", sample.length() > 0,
		"codepage %s, %d character(s)" % [Codepage.active(), sample.length()])
	h.check("the fixture writes outside every corpus", root_dir.begins_with("user://"), root_dir)
	h.complete(title)
	if sample.is_empty() or root_dir == "":
		quit(h.finish("Lingo file codepage"))
		return

	var path := "%s.qa_codepage.txt" % root_dir
	var expected := Codepage.encode(sample)

	title = "a file written in the title's codepage reads back as its characters"
	h.begin(title)
	# Written as raw bytes, deliberately not through the API under test: a
	# fixture produced by the writer would agree with the reader whatever both of
	# them do, which is the shape of assertion that cannot fail.
	var raw_out := FileAccess.open(path, FileAccess.WRITE)
	if raw_out == null:
		h.check("the fixture file could be created", false, path)
		h.complete(title)
		quit(h.finish("Lingo file codepage"))
		return
	raw_out.store_buffer(expected)
	raw_out.close()

	var io := FileIO.new()
	io.host = host
	io.lingo_perform("openFile", [path, 1])
	var read_back := str(io.lingo_perform("readFile", [])[0])
	io.lingo_perform("closeFile", [])
	h.check("readFile answers the codepage's characters",
		read_back == sample,
		"%d char(s) back, first difference at %d" % [
			read_back.length(), _first_diff(read_back, sample)])
	h.complete(title)

	title = "text written through the API reaches the disc as codepage bytes"
	h.begin(title)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var writer := FileIO.new()
	writer.host = host
	writer.lingo_perform("createFile", [path])
	writer.lingo_perform("openFile", [path, 0])
	writer.lingo_perform("writeString", [sample])
	writer.lingo_perform("closeFile", [])
	var on_disc := PackedByteArray()
	var check_in := FileAccess.open(path, FileAccess.READ)
	if check_in != null:
		on_disc = check_in.get_buffer(check_in.get_length())
		check_in.close()
	h.check("the bytes on disc are one per character",
		on_disc == expected,
		"%d byte(s) written, %d expected" % [on_disc.size(), expected.size()])
	h.complete(title)

	title = "write then read is the identity, through both file APIs"
	h.begin(title)
	var reader := FileIO.new()
	reader.host = host
	reader.lingo_perform("openFile", [path, 1])
	var round_trip := str(reader.lingo_perform("readFile", [])[0])
	reader.lingo_perform("closeFile", [])
	h.check("FileIO: writeString then readFile", round_trip == sample,
		"first difference at %d" % _first_diff(round_trip, sample))

	var ini := "%s.qa_codepage.ini" % root_dir
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ini))
	BuddyAPI.write_ini(host, ["s", "k", sample, ini])
	var ini_back := str(BuddyAPI.read_ini(host, ["s", "k", "", ini]))
	h.check("BuddyAPI: baWriteIni then baReadIni", ini_back == sample,
		"%d char(s) back, first difference at %d" % [
			ini_back.length(), _first_diff(ini_back, sample)])
	h.complete(title)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ini))
	quit(h.finish("Lingo file codepage"))


## Where two strings first differ, or -1. A count of characters says a round trip
## failed; the position says whether it failed at the first high byte or at the
## last, which is the difference between a decoder and an off-by-one.
static func _first_diff(a: String, b: String) -> int:
	var n: int = mini(a.length(), b.length())
	for i in n:
		if a.unicode_at(i) != b.unicode_at(i):
			return i
	return -1 if a.length() == b.length() else n
