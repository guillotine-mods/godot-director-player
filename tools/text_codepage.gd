extends SceneTree
## Which single-byte codepage this corpus is in, and does the round trip survive?
##
##   godot --headless --path . --script tools/text_codepage.gd
##   godot --headless --path . --script tools/text_codepage.gd -- --all
##   godot --headless --path . --script tools/text_codepage.gd -- --root piposh-ru
##   godot --headless --path . --script tools/text_codepage.gd -- --report
##
## Four questions, and the first is the one nobody had asked.
##
## **Which codepage.** Reported as `?` was the symptom -- a player typed a Hebrew
## save name and got `?????` -- and the fix is a table, so the table had better be
## the right one. The corpus is Mac-authored and was mass-converted through
## Director on Windows, so Mac OS Hebrew and Windows-1255 were both live, and they
## agree on every Hebrew letter: alef..tav is 0xE0..0xFA in both. The letters
## therefore prove nothing and the discrimination is entirely in the bytes that
## are *not* letters, which is what `_measure` reads. Every one of them says Mac
## OS Hebrew, and the eight bytes that Windows-1255 leaves undefined say it on
## their own.
##
## **The round trip.** `decode` then `encode` must give back the bytes, for every
## authored string in every container of every title -- because `saveMovie`
## rewrites `STXT` payloads in place, and a reader and a writer that disagree by
## one byte corrupt a game file rather than failing. Mac script systems are not
## one-to-one (Mac OS Hebrew keeps a second copy of most of ASCII at 0xA0-0xBF and
## 0xFB-0xFF for right-to-left runs), so the exceptions are *named* here rather
## than absorbed. Two claims, and the strong one is the second:
##
##   bytes   a byte outside the ambiguous ranges that does not come back is a
##           failure. Only the bytes that *changed* are judged -- a Hebrew letter
##           standing next to an ambiguous space is not evidence of anything.
##   text    `decode(encode(decode(bytes)))` equals `decode(bytes)`, everywhere,
##           no exceptions. This is the one a save depends on: the writer is
##           handed text, not bytes, so text being a fixed point is what makes a
##           rewritten field say what it said.
##
## The ambiguous strings are *listed* rather than merely counted, so the number
## cannot quietly grow.
##
## **The bug itself.** A Hebrew string must encode to Hebrew bytes and not to
## `0x3f`. Stated against the identity codepage too, so the case says what the
## regression *was* rather than only that it is gone.
##
## **The gate is the whole corpus, not one file.** `--all` walks all six roots.
## Title-agnostic: nothing here names a room, a channel or a member, and the
## Hebrew subjects are found by scanning for high bytes rather than by being
## listed.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Codepage := preload("res://director/director_codepage.gd")
const Paths := preload("res://director/director_paths.gd")

## Every root under `games/`, for `--all`. Named rather than discovered, for the
## same reason `parse_residue.gd` names them: a directory dropped in beside them
## must not silently join the sweep and change the number this reports.
const ROOTS := ["piposh", "piposh2", "piposh-en", "piposh-ru", "piposh-dream", "rating"]

## What the measurement decides between. Both are single-byte Hebrew codepages
## that put the letters in the same 27 places.
const CANDIDATES := ["mac_hebrew", "windows_1255"]

## Mac OS Hebrew's second copy of ASCII: `0xA0` is a space, `0xB0`-`0xB9` the
## digits, `0xFB`-`0xFF` the braces and the bar. Decoding is unambiguous; encoding
## picks the lowest byte, so a *byte* in these ranges does not come back although
## the *text* does. Named here rather than derived, so that a table change which
## widened the ambiguity would fail this rather than be absorbed by it.
const AMBIGUOUS := [[0xA0, 0xBF], [0xFB, 0xFF]]

## A Hebrew word, as code points, for the encode case. `chr(0x5D0)` and its
## neighbours: alef, bet, gimel, dalet. Written as numbers because a source file
## that carries the letters is one more thing that can be re-encoded on the way
## into git.
const HEBREW := [0x05D0, 0x05D1, 0x05D2, 0x05D3]


func _init() -> void:
	var args := Args.parse()
	if Args.text(args, "child", "") != "":
		_child(args)
		return
	var h := Harness.new()
	var roots: Array = ROOTS if Args.flag(args, "all") else [_single_root(args)]

	# The measurement sweeps the whole of `games/`, whatever root is selected.
	# Which codepage a corpus was authored in is a fact about the corpus, and the
	# bytes that discriminate are rare -- Piposh 1 has eight that Windows-1255
	# leaves undefined and Piposh 2 has none -- so a measurement pinned to one
	# root would answer "no evidence either way" and read as a pass.
	_measure(h, _present(ROOTS))
	_encodes(h)
	for root in roots:
		_round_trip(h, str(root), Args.flag(args, "report"))
	if not Args.flag(args, "no-save"):
		await _two_process(h, args)
	_configured(h)
	quit(h.finish("the corpus's codepage, measured, and its round trip"))


## Is the engine actually *using* what the corpus was authored in?
##
## Everything above forces `mac_hebrew`, because everything above is measuring the
## table rather than the configuration. This is the case that asks whether a
## player gets it, and it is deliberately the one that can go red on a working
## engine: `director/director_codepage.gd` defaults to the identity so that no
## title acquires a codepage nobody measured, which means a title that *has* been
## measured has to be told. One line in `director_game.cfg`:
##
##     [game]
##     codepage = "mac_hebrew"
##
## A failure here is not a broken mechanism -- the cases above prove the
## mechanism -- it is a configuration that has not been given the answer this
## harness just worked out. Stated as a failure rather than a printed note
## because a printed note is what nobody reads: the whole reason this file exists
## is that a player typed Hebrew into a save name and got `?????`, and a green
## gate over a configuration that still does that is the safety net going dark.
func _configured(h: Harness) -> void:
	h.begin("the engine is configured for the codepage the corpus measures as")
	# Re-resolved from scratch, so what is reported is what a player's process
	# would resolve and not what the cases above left in force.
	Codepage.reset()
	var live := Codepage.active()
	print("    configured codepage: %s (measured: mac_hebrew)" % live)
	var word := ""
	for point in HEBREW:
		word += String.chr(point)
	h.check("the configured codepage can hold this corpus's own letters",
		Codepage.holds(word),
		("`%s` cannot; add `codepage = \"mac_hebrew\"` to [game] in " % live)
			+ "director_game.cfg, or pass --codepage mac_hebrew")
	h.check("a forced codepage takes effect in both directions", _override_works(),
		"windows_1251 0xC0 -> Cyrillic A, then the identity 0xC0 -> A-grave")
	h.complete("the engine is configured for the codepage the corpus measures as")


func _override_works() -> bool:
	Codepage.use("windows_1251")
	var cyrillic: bool = Codepage.decode(PackedByteArray([0xC0])) == String.chr(0x0410)
	Codepage.use(Codepage.IDENTITY)
	var identity: bool = Codepage.decode(PackedByteArray([0xC0])) == String.chr(0x00C0)
	Codepage.reset()
	return cyrillic and identity


## The named roots that are actually checked out. `games/` holds submodules, and
## a sweep that failed because one was not initialised would be reporting the
## checkout rather than the corpus.
func _present(names: Array) -> Array:
	var out: Array = []
	for name in names:
		if DirAccess.dir_exists_absolute("res://games/%s" % str(name)):
			out.append(str(name))
	return out


func _single_root(args: Dictionary) -> String:
	var paths := Paths.new()
	if paths.load_config():
		return str(paths.root).get_file()
	return Args.text(args, "root", ROOTS[1])


# ------------------------------------------------------------------ measuring

## Read every high byte the corpus actually uses, and ask each candidate to
## account for it.
##
## The verdict is not "which one produces Hebrew" -- both do, identically -- it is
## which one produces *sense* everywhere else. Three tests, in increasing order of
## how hard they are to argue with:
##
##   defined     a byte the codepage has no mapping for cannot have been written
##               in it. Windows-1255 leaves eleven positions undefined.
##   numeric     a byte inside a comma-separated numeric column has to be a digit.
##   spacing     a byte between a word and a number, in 22 member names, has to be
##               a space.
func _measure(h: Harness, roots: Array) -> void:
	h.begin("which codepage the corpus was authored in")
	var bytes := {}
	var names: Array[String] = []
	var digits: Array[String] = []
	for root in roots:
		_collect_high_bytes(str(root), bytes, names, digits)
	h.check("the corpus uses high bytes at all", not bytes.is_empty(),
		"%d distinct" % bytes.size())

	var undefined := {}
	for candidate in CANDIDATES:
		Codepage.use(candidate)
		var missing: Array[String] = []
		for byte in bytes:
			# Windows codepages mark a hole by mapping the byte to the C1 control
			# of the same value, which is the shape of "no character here".
			var point: int = Codepage.TABLES[candidate][int(byte) - 0x80]
			if point == int(byte) and int(byte) >= 0x80 and int(byte) <= 0x9F:
				missing.append("%02X" % int(byte))
		undefined[candidate] = missing
	h.check("mac_hebrew defines every byte the corpus uses",
		(undefined["mac_hebrew"] as Array).is_empty(),
		", ".join(undefined["mac_hebrew"]))
	h.check("windows_1255 does not, so nothing here was written in it",
		not (undefined["windows_1255"] as Array).is_empty(),
		"undefined and present: " + ", ".join(undefined["windows_1255"]))

	# A `searchinfo`-shaped field: a comma-separated record whose high byte sits
	# in a column of numbers. Found by shape, not by name.
	if h.check("the corpus has a numeric column carrying a high byte",
			not digits.is_empty(), "%d" % digits.size()):
		for candidate in CANDIDATES:
			Codepage.use(candidate)
			var numeric := 0
			for sample in digits:
				if _is_digit_run(sample):
					numeric += 1
			h.check("%s: the numeric column stays numeric" % candidate,
				(numeric == digits.size()) == (candidate == "mac_hebrew"),
				"%d of %d" % [numeric, digits.size()])

	# A `<word><high byte><digit>` member name. Under Mac OS Hebrew the byte is a
	# space; under Windows-1255 it is a no-break space, which is not what anybody
	# typed into a cast member's name field in 1997.
	if h.check("the corpus names members `<word><high byte><digit>`",
			not names.is_empty(), "%d" % names.size()):
		Codepage.use("mac_hebrew")
		var spaced := 0
		for sample in names:
			if _decoded(sample).contains(" "):
				spaced += 1
		h.check("mac_hebrew: the separator in those names is a space",
			spaced == names.size(), "%d of %d" % [spaced, names.size()])
		Codepage.use("windows_1255")
		var nbsp := 0
		for sample in names:
			if _decoded(sample).contains(" "):
				nbsp += 1
		h.check("windows_1255: it is not", nbsp == 0,
			"%d of %d came out spaced" % [nbsp, names.size()])
	h.complete("which codepage the corpus was authored in")


## Bytes of the raw sample, decoded under whatever codepage is in force.
func _decoded(sample: String) -> String:
	var raw := PackedByteArray()
	for i in sample.length():
		raw.append(sample.unicode_at(i))
	return Codepage.decode(raw)


func _is_digit_run(sample: String) -> bool:
	var text := _decoded(sample)
	if text == "":
		return false
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 0x30 or c > 0x39:
			return false
	return true


## Walk a root with the identity codepage in force, so what comes back out of the
## cast is the container's own bytes as code points -- the raw material the
## measurement is done on, rather than one candidate's reading of it.
func _collect_high_bytes(root: String, bytes: Dictionary,
		names: Array[String], digits: Array[String]) -> void:
	Codepage.use(Codepage.IDENTITY)
	for path in _containers(root):
		var file := ContainerFile.new()
		if not file.open(path):
			continue
		var cast := Cast.new()
		if not cast.open(file):
			continue
		for number in cast.member_numbers():
			var member: Dictionary = cast.member(number)
			for key in ["name", "text", "source"]:
				var text := str(member.get(key, ""))
				var high := false
				for i in text.length():
					var c := text.unicode_at(i)
					if c > 0x7F:
						bytes[c] = int(bytes.get(c, 0)) + 1
						high = true
				if not high:
					continue
				if key == "name":
					var separator := _word_then_number(text)
					if separator != "":
						names.append(separator)
				elif key == "text":
					for column in _numeric_columns(text):
						digits.append(column)
		file.close()


## `<letters><high byte><ASCII digits>` in a member name, returned as just the
## high byte and the digits around it. "" when the name is not that shape.
func _word_then_number(text: String) -> String:
	for i in range(1, text.length() - 1):
		if text.unicode_at(i) <= 0x7F:
			continue
		var after := text.unicode_at(i + 1)
		var before := text.unicode_at(i - 1)
		if after >= 0x30 and after <= 0x39 and before > 0x7F:
			return text.substr(i, 1)
	return ""


## Comma-separated items of `text` that are entirely high bytes and ASCII digits
## and are not entirely digits already -- a numeric column with something in it
## that is not a digit yet.
func _numeric_columns(text: String) -> Array[String]:
	var out: Array[String] = []
	for line in text.split("\n"):
		for item in str(line).split(","):
			var value := str(item)
			if value == "":
				continue
			var high := false
			var digit := false
			var ok := true
			for i in value.length():
				var c := value.unicode_at(i)
				if c > 0x7F:
					high = true
				elif c >= 0x30 and c <= 0x39:
					digit = true
				else:
					ok = false
					break
			# **A digit has to already be there.** Without that, a comma-separated
			# list of Hebrew words qualifies -- every character is a high byte, so
			# "nothing here is a non-digit" is trivially true -- and Piposh 1's
			# `words` field turns 4 real subjects into 40 that no codepage can
			# make numeric.
			if ok and high and digit:
				out.append(value)
	return out


# ------------------------------------------------------------------ encoding

## The reported bug, as a case: Hebrew in, Hebrew bytes out.
func _encodes(h: Harness) -> void:
	h.begin("a typed Hebrew name reaches the container as Hebrew")
	var word := ""
	for point in HEBREW:
		word += String.chr(point)

	Codepage.use(Codepage.IDENTITY)
	var before := Codepage.encode(word)
	var all_question := before.size() == word.length()
	for byte in before:
		if byte != 0x3f:
			all_question = false
	h.check("with no codepage it is the row of `?` the player reported",
		all_question, _hex(before))

	Codepage.use("mac_hebrew")
	var after := Codepage.encode(word)
	h.check("with mac_hebrew it is 0xE0..0xE3", _hex(after) == "E0 E1 E2 E3",
		_hex(after))
	h.check("and it decodes back to what was typed",
		Codepage.decode(after) == word)
	h.check("mac_hebrew reports it can hold Hebrew", Codepage.holds(word))
	Codepage.use(Codepage.IDENTITY)
	h.check("the identity reports it cannot", not Codepage.holds(word))

	# ASCII is untouched by any of this, which is the promise that keeps every
	# other harness in the suite meaningful.
	Codepage.use("mac_hebrew")
	var ascii := " !0123456789?ABCXYZabcxyz~"
	h.check("ASCII encodes to itself", Codepage.encode(ascii) == ascii.to_ascii_buffer(),
		_hex(Codepage.encode(ascii)))
	h.check("ASCII decodes to itself", Codepage.decode(ascii.to_ascii_buffer()) == ascii)
	h.complete("a typed Hebrew name reaches the container as Hebrew")


# --------------------------------------------------------------- two processes

## The reported bug end to end: a Hebrew name written by one process, read back by
## another that never had the file open.
##
## A single process cannot make this assertion. `saveMovie` was once bound inert,
## and every save "worked" until the player restarted -- so a check that reads the
## field back out of the same session is a check that cannot fail for the reason
## that matters. The child boots the real player, writes the field through the
## same `lingo_set_field` a script does and calls `lingo_save_movie`; this process
## reopens the container afterwards.
##
## **The container is put back**, byte for byte, and the restore is itself
## checked. `games/` is the user's own 1997 discs.
func _two_process(h: Harness, args: Dictionary) -> void:
	h.begin("a Hebrew name survives the process that saved it")
	var paths := Paths.new()
	if not h.check("a game is configured", paths.load_config(),
			"director_game.cfg names no root"):
		h.complete("a Hebrew name survives the process that saved it")
		return
	var wanted := Args.text(args, "file", "")
	var field_name := Args.text(args, "field", "")
	var target := paths.resolve(wanted) if wanted != "" else ""
	if target == "":
		# Smallest rather than first, and both words matter: deterministic,
		# because a gate that picks a different file per run is not a gate, and
		# smallest because this rewrites a real game container.
		var found := _smallest_field_container(paths)
		if not h.check("a container under %s has a field member" % paths.root,
				not found.is_empty()):
			h.complete("a Hebrew name survives the process that saved it")
			return
		target = str(found[0])
		if field_name == "":
			field_name = str(found[1])
	if not h.check("the subject resolves", target != "" and field_name != "",
			"%s / %s" % [target, field_name]):
		h.complete("a Hebrew name survives the process that saved it")
		return

	var original := FileAccess.get_file_as_bytes(target)
	if not h.check("the container reads", not original.is_empty(), target):
		h.complete("a Hebrew name survives the process that saved it")
		return

	# A name a player could type: four Hebrew letters and an ASCII tag, so the
	# assertion is about the mixture rather than about one script.
	var typed := ""
	for point in HEBREW:
		typed += String.chr(point)
	typed += " %d" % (Time.get_ticks_usec() % 100000)

	var child := [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/text_codepage.gd", "--",
		"--child", "true", "--typed", typed,
		"--field", field_name, "--file", str(target).get_file(),
		"--codepage", Codepage.active(),
	]
	if Args.text(args, "root", "") != "":
		child.append_array(["--root", Args.text(args, "root", "")])
	# And the boot movie with it, on the same argument as `--root` above. This
	# child names its own `--file`, so it does not depend on the boot movie today;
	# forwarding it anyway is what keeps the three child-spawning harnesses saying
	# the same thing, so the next one copied from here inherits the whole pin.
	if Args.text(args, "boot", "") != "":
		child.append_array(["--boot", Args.text(args, "boot", "")])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), child, out, true)
	for line in out:
		for row in str(line).split("\n"):
			if str(row).strip_edges() != "":
				print("    | %s" % str(row).strip_edges())
	if h.check("the saving process exits cleanly", code == 0, "exit %d" % code):
		var file := ContainerFile.new()
		if h.check("the saved container reopens here", file.open(target), file.error):
			var cast := Cast.new()
			var parsed: bool = cast.open(file)
			var got := str(cast.member(cast.number_of(field_name)).get("text", ""))
			file.close()
			h.check("its cast parses", parsed)
			h.check("the field holds the Hebrew the other process typed",
				got == typed, "%s, wanted %s" % [JSON.stringify(got), JSON.stringify(typed)])
			h.check("and not a row of `?`", not got.contains("?"), JSON.stringify(got))

	var back := FileAccess.open(target, FileAccess.WRITE)
	if h.check("the original container can be written back", back != null,
			error_string(FileAccess.get_open_error())):
		back.store_buffer(original)
		back.close()
	h.check("the container is byte-identical to how it was found",
		FileAccess.get_file_as_bytes(target) == original, target)
	h.complete("a Hebrew name survives the process that saved it")


## The other process: boot the player, write the field the way a script does,
## `saveMovie`, exit.
func _child(args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	# Held before the first frame: a save movie's own first frame script routinely
	# sends the playhead somewhere else, which would leave a different container
	# open than the one the parent is about to check.
	preview.call("lingo_hold")
	await process_frame
	if preview.get("_movie") == null:
		print("child: no movie opened")
		quit(1)
		return
	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		preview.call("lingo_hold")
		await process_frame
		var open_name := str(preview.get("_movie").path).get_file()
		if open_name.to_lower() != wanted.to_lower():
			print("child: %s is open, not %s" % [open_name, wanted])
			quit(1)
			return
	preview.call("lingo_set_field", Args.text(args, "field", ""), "",
		Args.text(args, "typed", ""))
	var report: Dictionary = preview.call("lingo_save_movie",
		str(preview.get("_movie").path).get_file())
	print("child: codepage %s, saved %s, %d field(s)%s" % [
		Codepage.active(), str(report["path"]), int(report["written"]),
		("  ERROR " + str(report["error"])) if str(report["error"]) != "" else ""])
	quit(0 if str(report["error"]) == "" and int(report["written"]) > 0 else 1)


## The smallest container under the root with a named field member.
func _smallest_field_container(paths: Paths) -> Array:
	var best: Array = []
	var smallest := 1 << 62
	for relative in paths.containers():
		var resolved := paths.resolve(str(relative))
		if resolved == "":
			continue
		var size := FileAccess.get_file_as_bytes(resolved).size()
		if size <= 0 or size >= smallest:
			continue
		var file := ContainerFile.new()
		if not file.open(resolved):
			continue
		var cast := Cast.new()
		var name := ""
		if cast.open(file):
			for number in cast.member_numbers():
				var member: Dictionary = cast.member(number)
				if int(member.get("type", 0)) == 3 and str(member.get("name", "")) != "":
					name = str(member["name"])
					break
		file.close()
		if name == "":
			continue
		smallest = size
		best = [resolved, name]
	return best


# ---------------------------------------------------------------- round trip

## Every authored string in a title, decoded and re-encoded, against its own
## bytes.
func _round_trip(h: Harness, root: String, report: bool) -> void:
	var case_name := "%s: decode then encode gives the bytes back" % root
	h.begin(case_name)
	var strings := 0
	var fields := 0
	var lost: Array[String] = []
	var changed_text: Array[String] = []
	var ambiguous: Array[String] = []
	var ambiguous_fields: Array[String] = []
	for path in _containers(root):
		# The bytes, read with nothing applied.
		Codepage.use(Codepage.IDENTITY)
		var file := ContainerFile.new()
		if not file.open(path):
			continue
		var cast := Cast.new()
		if not cast.open(file):
			file.close()
			continue
		var raw := {}
		for number in cast.member_numbers():
			var member: Dictionary = cast.member(number)
			for key in ["name", "text", "source"]:
				raw["%d/%s" % [number, key]] = str(member.get(key, ""))
		file.close()

		# ...and again through the codepage under test.
		Codepage.use("mac_hebrew")
		var again := ContainerFile.new()
		if not again.open(path):
			continue
		var reread := Cast.new()
		if not reread.open(again):
			again.close()
			continue
		for number in reread.member_numbers():
			var member: Dictionary = reread.member(number)
			for key in ["name", "text", "source"]:
				var slot := "%d/%s" % [number, key]
				var was := str(raw.get(slot, ""))
				var now := str(member.get(key, ""))
				if was == "":
					continue
				strings += 1
				if key == "text":
					fields += 1
				# `_text` normalises the Mac carriage return, and the writer puts
				# it back, so the comparison is against the same normalisation.
				var source := _bytes_of(was.replace("\r\n", "\n").replace("\r", "\n"))
				var back := Codepage.encode(now)
				# The text is a fixed point even where the bytes are not: what a
				# save rewrites is the *text* the movie put there, so a byte that
				# changes while the characters do not is a different and much
				# smaller claim than one that loses a character.
				if Codepage.decode(back) != now:
					changed_text.append("%s #%s" % [path.get_file(), slot])
				if back == source:
					continue
				var where := _differing(source, back)
				if _all_ambiguous(source, where):
					ambiguous.append("%s #%s %s" % [
						path.get_file(), slot, _at(source, where)])
					if key == "text":
						# A field is what `saveMovie` rewrites, so an ambiguity in
						# one is a byte a save of that field would actually change.
						ambiguous_fields.append("%s #%s %s" % [
							path.get_file(), slot, _at(source, where)])
					continue
				lost.append("%s #%s %s -> %s" % [
					path.get_file(), slot, _at(source, where), _at(back, where)])
		again.close()

	h.check("%s has authored strings to check" % root, strings > 0, "%d" % strings)
	h.check("%s: the text is a fixed point of decode-encode-decode" % root,
		changed_text.is_empty(), "%d changed%s" % [changed_text.size(),
			("; first: " + changed_text[0]) if not changed_text.is_empty() else ""])
	h.check("%s: every byte outside the ambiguous ranges survives" % root,
		lost.is_empty(), "%d lost%s" % [lost.size(),
			("; first: " + lost[0]) if not lost.is_empty() else ""])
	if report or not ambiguous.is_empty():
		print("    %s: %d strings (%d field). %d re-encode to a different byte "
			% [root, strings, fields, ambiguous.size()]
			+ "for the same text, %d of them in a field:" % ambiguous_fields.size())
		for line in ambiguous:
			print("      %s" % line)
	h.complete(case_name)


## Byte positions at which two payloads differ. Equal-length by construction --
## this codepage is one byte per character in both directions -- and a length
## change is reported as every trailing position.
func _differing(a: PackedByteArray, b: PackedByteArray) -> Array[int]:
	var out: Array[int] = []
	for i in maxi(a.size(), b.size()):
		if i >= a.size() or i >= b.size() or a[i] != b[i]:
			out.append(i)
	return out


## Are all the bytes that changed inside a documented ambiguous range? Bytes that
## did not change are not evidence either way, which is the distinction the first
## version of this got wrong: a Hebrew letter beside an ambiguous space made the
## whole string look lost.
func _all_ambiguous(source: PackedByteArray, where: Array[int]) -> bool:
	if where.is_empty():
		return false
	for i in where:
		if i >= source.size():
			return false
		var byte: int = source[i]
		var inside := false
		for span in AMBIGUOUS:
			if byte >= int(span[0]) and byte <= int(span[1]):
				inside = true
		if not inside:
			return false
	return true


## The differing bytes and nothing else, so a failure detail is readable rather
## than a kilobyte of a field's contents.
func _at(raw: PackedByteArray, where: Array[int]) -> String:
	var parts := PackedStringArray()
	for i in where:
		parts.append("@%d=%02X" % [i, raw[i] if i < raw.size() else 0])
		if parts.size() >= 8:
			parts.append("...")
			break
	return " ".join(parts)


static func _bytes_of(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	for i in text.length():
		var point := text.unicode_at(i)
		out.append(point if point < 256 else 0x3f)
	return out


static func _hex(raw: PackedByteArray) -> String:
	var parts := PackedStringArray()
	for byte in raw:
		parts.append("%02X" % byte)
	return " ".join(parts)


func _containers(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := root if root.begins_with("res://") else "res://games/%s" % root
	_collect(dir, out)
	return out


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.get_extension().to_lower() in ["dir", "dxr", "cst", "cxt", "cct", "dcr"]:
			out.append(full)
	dir.list_dir_end()
