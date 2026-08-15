extends SceneTree
## Do a score span's **authored behaviour parameters** reach the behaviour?
##
##   godot --headless --audio-driver Dummy --path . --script tools/behaviour_params.gd
##   godot --headless --audio-driver Dummy --path . --script tools/behaviour_params.gd -- --survey
##   godot --headless --audio-driver Dummy --path . --script tools/behaviour_params.gd -- \
##     --survey --roots res://test-games/itamar-magichat --list 12
##
## `bugs.md` 83's remaining third. Director stores the values an author typed into
## a behaviour's parameter dialog **per sprite span**, in an entry of the score
## list that the span's behaviour element names by index -- `initializerIndex`,
## opened with `getSpriteDetailsStream` (`score.cpp:2062-2075`, `:2623-2645`) and
## written onto the instance between `new` and the first message
## (`lingo-events.cpp:879-935`). Nothing in this port read that index. A behaviour
## therefore ran with its properties **declared and unset**: `go(prGotoFrame)`
## reached VOID through a declared, unassigned property, and every behaviour in
## the corpus that takes a parameter ran on nothing.
##
## ## What the corpus actually holds, and why the gate cannot assert it
##
## `--survey` over all eight roots, 2026-08-15: **677 containers, 491 scores,
## 127,559 behaviour elements walked, and 82 spans carry an authored initialiser
## -- every one of them `test-games/itamar-magichat`'s.** Zero in `piposh`,
## `piposh-dream`, `piposh-en`, `piposh-ru`, `piposh2`, `rating` and
## `itamar-park`; 11 of them are `magichat.dir`'s own 124 intervals and the rest
## are in that corpus's other containers. That is the
## whole population, and it is the reason this file carries a **fixture** rather
## than pointing the assertion at a container: `test-games/` is gitignored, no
## file under it has ever been committed, and four `gate.sh` entries were removed
## for depending on it (`AGENTS.md`, "Environment"). A gate entry that can only
## pass on one developer's disk gates nothing.
##
## So the three cases split by what each can honestly prove:
##
## 1. **The decode**, against a VWSC this harness builds byte by byte from the
##    layout in `director_score.gd:_read_interval`. Always present, so always
##    asserted. It is not a test of the data -- it is a test of the port's reader
##    against a documented layout, in the shape `AGENTS.md` asks for when the
##    corpus cannot express the feature.
## 2. **The path from the span to the instance**, driven through the real
##    `frame_loop.gd:send_sprite_message` on the real player with a real script of
##    whatever movie is loaded. Corpus-independent: it needs *a* behaviour script,
##    not a particular one.
## 3. **The live movie**, when the loaded title authors a parameter at all. It
##    says out loud when it does not and asserts nothing, which is
##    `sprite_lifetime`'s fourth-case pattern and the only honest thing to do.
##
## ## The fixture, and the second bug the survey turned up
##
## An initialiser entry is a NUL-terminated Lingo property-list literal padded to
## four bytes, and the long ones clear the 44-byte floor `parse()` uses to decide
## that an entry is a span info record: `[#prSprite: 7, #prSoundLoop: 0,
## #prSound: "", #prBackToGame: 0, #prFreezFlash: 0, #prPlayMuisc: 0]` is 100
## bytes in `trivia.dir`. Read as a span it yields `dLoo` as a sprite number and
## two ASCII words as a frame range, and the entry after it -- another initialiser
## -- as a behaviour stream. **122 intervals over the corpus that are not spans,
## all `itamar-magichat`'s and 0 in the six shipped titles**, which `--survey`
## measures by walking the entry table both ways and diffing them. So `parse()`
## now skips an entry that some element has named as an initialiser, and the
## fixture below reproduces exactly that shape: a 100-byte initialiser followed by
## a 28-byte one. With the skip reverted the fixture decodes 5 intervals where the
## score has 2.
##
## The diff is asserted in **both** directions, which is the half that matters
## here: the raw walk may have more intervals than the decoder and must never have
## fewer, so a skip set that ate a real span goes red rather than quietly losing a
## behaviour.
##
## Title-agnostic: it names no game, and the survey discovers its roots by listing
## them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Score := preload("res://director/director_score.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Paths := preload("res://director/director_paths.gd")

## Where corpora live. Each *subdirectory* of one of these is one corpus root --
## the same discovery `tools/member_type_census.gd` and `tools/channel_occupancy.gd`
## do, and the reason a survey run here is over eight roots and not over one.
const CORPUS_DIRS := ["res://games", "res://test-games"]

## The two literals the fixture authors, taken verbatim out of the corpus so the
## parser meets the shapes it will really meet: a bare symbol/string pair, and a
## six-property list with an empty string and a nested empty list in it.
const SHORT_PARAMS := "[#prGotoFrame: \"mainmenu\"]"
const LONG_PARAMS := "[#prSprite: 7, #prSoundLoop: 0, #prSound: \"\", #prBackToGame: 0, #prFreezFlash: 0, #prPlayMuisc: 0]"

## The fixture's two spans, as authored: 1-based frame numbers and Director's
## sprite numbers (0 is the behaviour channel, `CHANNEL_BIAS + n` is channel n).
const SPAN_A_SPRITE := Score.CHANNEL_BIAS + 6
const SPAN_A_FIRST := 3
const SPAN_A_LAST := 9
const SPAN_B_FIRST := 1
const SPAN_B_LAST := 12

## A channel no score in any corpus occupies, so case 2 can build an instance
## without disturbing one the movie is using. `channels_displayed` is at most 150
## in this corpus and the port's own ceiling is well below this.
const SCRATCH_CHANNEL := 900


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	if Args.flag(args, "survey"):
		_survey(h, args)
		quit(h.finish("every initialiser the score names is a property list"))
		return
	_fixture(h)
	await _player(h, args)
	quit(h.finish("a span's authored parameters reach the behaviour instance"))


# ------------------------------------------------------------------ fixture


static func _be32(out: PackedByteArray, at: int, value: int) -> void:
	out[at] = (value >> 24) & 0xFF
	out[at + 1] = (value >> 16) & 0xFF
	out[at + 2] = (value >> 8) & 0xFF
	out[at + 3] = value & 0xFF


static func _be16(out: PackedByteArray, at: int, value: int) -> void:
	out[at] = (value >> 8) & 0xFF
	out[at + 1] = value & 0xFF


## One score-list entry holding `text` the way Director writes an initialiser:
## the bytes, a NUL, then padding to a four-byte boundary. `size` is asserted
## rather than derived so the fixture states the widths the survey measured.
static func _string_entry(text: String, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	out.fill(0)
	var raw := text.to_utf8_buffer()
	for i in raw.size():
		out[i] = raw[i]
	return out


## A span info record: first frame, last frame and Director's sprite number, at
## the three offsets `_read_interval` reads them from. 44 bytes is the floor
## `parse()` uses; the real records are longer and the rest is not read here.
static func _span_entry(first: int, last: int, sprite_number: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(44)
	out.fill(0)
	_be32(out, 0, first)
	_be32(out, 4, last)
	_be32(out, 16, sprite_number)
	return out


## One `BehaviorElement`: cast library, member, and the entry index of the
## parameters. Eight bytes, which is the width `_read_interval`'s docstring
## settles from the corpus.
static func _behaviour_entry(lib: int, member: int, initializer_index: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(Score.BEHAVIOUR_ELEMENT_SIZE)
	out.fill(0)
	_be16(out, 0, lib)
	_be16(out, 2, member)
	_be32(out, 4, initializer_index)
	return out


## The frame stream, entry 0: a 20-byte header and one empty frame.
##
## `_read_frames` refuses a sprite record size other than 48 and stops at the
## first zero-length frame, so this is the shortest stream it accepts. The score
## the fixture is about is entirely in the interval entries; the frames only have
## to be well-formed enough that `parse()` gets past them.
static func _frame_stream() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(22)
	out.fill(0)
	_be32(out, 0, 22)
	_be32(out, 4, 20)
	_be32(out, 8, 1)
	_be16(out, 12, 7)
	_be16(out, 14, Score.SPRITE_RECORD_SIZE)
	_be16(out, 16, 24)
	_be16(out, 18, 24)
	_be16(out, 20, 2)
	return out


## A whole VWSC chunk from a list of entries, in the D5+ score-list layout
## `parse()` reads: a 28-byte header with the -3 marker at offset 4 and the entry
## count at 12, an offset table of `count + 1` entries at 24, then the entries.
static func _vwsc(entries: Array) -> PackedByteArray:
	var offsets_at := 24
	var base := offsets_at + 4 * (entries.size() + 1)
	var body := PackedByteArray()
	var offsets: Array[int] = []
	for entry in entries:
		offsets.append(body.size())
		body.append_array(entry as PackedByteArray)
	offsets.append(body.size())

	var out := PackedByteArray()
	out.resize(base)
	out.fill(0)
	_be32(out, 0, base + body.size())
	_be32(out, 4, Score.SCORE_LIST_MARKER)
	_be32(out, 12, entries.size())
	for i in offsets.size():
		_be32(out, offsets_at + i * 4, offsets[i])
	out.append_array(body)
	return out


## The eleven entries the fixture is, laid out the way `magichat.dir` lays its
## own out: the spans first, every initialiser appended after all of them, and
## two initialisers adjacent so that the long one has something ≥ 8 bytes behind
## it to be misread as a behaviour stream.
static func _fixture_payload() -> PackedByteArray:
	return _vwsc([
		_frame_stream(),                                    # 0  frames
		PackedByteArray(),                                  # 1  sprite order
		_span_entry(SPAN_A_FIRST, SPAN_A_LAST, SPAN_A_SPRITE),  # 2  span A info
		_behaviour_entry(1, 135, 10),                       # 3  span A behaviour
		PackedByteArray(),                                  # 4  span A name
		_span_entry(SPAN_B_FIRST, SPAN_B_LAST, 0),          # 5  span B info
		_behaviour_entry(1, 99, 9),                         # 6  span B behaviour
		PackedByteArray(),                                  # 7  span B name
		PackedByteArray(),                                  # 8  slack
		_string_entry(LONG_PARAMS, 100),                    # 9  span B parameters
		_string_entry(SHORT_PARAMS, 28),                    # 10 span A parameters
	])


func _fixture(h: Harness) -> void:
	h.begin("the decode")
	var score := Score.new()
	if not h.check("the fixture parses as a D5+ score list",
			score.parse(_fixture_payload()), score.error):
		h.complete("the decode")
		return
	var rows: Array[Dictionary] = score.intervals()
	# **The count is the skip-set assertion.** Entry 9 is 100 bytes of Lingo
	# source, which clears the 44-byte span floor; with `parse()`'s skip set gone
	# it is read as a span and entry 10 as its behaviour stream, and 28 bytes of
	# `[#prGotoFrame: "mainmenu"]` yield three 8-byte elements whose member words
	# are `pr`, `to` and `am` -- three intervals out of one string.
	h.check("the score's two spans are the only two intervals", rows.size() == 2,
		"%d interval(s): %s" % [rows.size(), _rows_shown(rows)])
	var sprite: Dictionary = {}
	var frame: Dictionary = {}
	for row in rows:
		if str(row.get("kind", "")) == "sprite" and sprite.is_empty():
			sprite = row
		elif str(row.get("kind", "")) == "frame" and frame.is_empty():
			frame = row
	if not h.check("both kinds are there to read", not sprite.is_empty() and not frame.is_empty(),
			_rows_shown(rows)):
		h.complete("the decode")
		return

	h.check("the sprite span kept its channel and range",
		int(sprite.get("channel", -1)) == SPAN_A_SPRITE - Score.CHANNEL_BIAS
			and int(sprite.get("start", -1)) == SPAN_A_FIRST - 1
			and int(sprite.get("end", -1)) == SPAN_A_LAST - 1,
		"channel %s [%s..%s]" % [str(sprite.get("channel")), str(sprite.get("start")),
			str(sprite.get("end"))])
	h.check("the sprite span carries the entry index its element names",
		int(sprite.get("initializer_index", 0)) == 10,
		"initializer_index %s" % str(sprite.get("initializer_index")))
	# The string, byte for byte and with nothing after the terminator: an entry
	# decoded whole would carry three NULs here, and `value()` answers VOID for a
	# string with a NUL in it -- the same failure as never reading the entry, and
	# harder to see.
	h.check("and the parameters the author typed, cut at the terminator",
		str(sprite.get("initializer_params", "")) == SHORT_PARAMS,
		"%s" % _shown(str(sprite.get("initializer_params", ""))))

	h.check("the behaviour channel's span is the frame tier",
		int(frame.get("channel", -1)) == 0,
		"kind %s channel %s" % [str(frame.get("kind")), str(frame.get("channel"))])
	h.check("a 100-byte initialiser survives the 44-byte span floor intact",
		str(frame.get("initializer_params", "")) == LONG_PARAMS,
		"%s" % _shown(str(frame.get("initializer_params", ""))))
	h.complete("the decode")

	# The join, on the fixture's own score rather than on a stub: this is the real
	# `sprite_behaviours_at` reading the real `DirectorScore` it just built, and it
	# is the step that carries the string from the interval into the identity array
	# `beginSprite` is handed. It is separated from the decode case because a
	# reader who sees it fail should look at `frame_loop.gd` and not at the bytes.
	h.begin("the span reaches the frame loop")
	var index := SPAN_A_FIRST - 1
	var spans: Dictionary = FrameLoop.sprite_behaviours_at(score, index)
	var channel := SPAN_A_SPRITE - Score.CHANNEL_BIAS
	if not h.check("frame %d carries both spans" % index,
			spans.has(channel) and spans.has(0), str(spans)):
		h.complete("the span reaches the frame loop")
		return
	var sprite_spec: Array = spans[channel]
	h.check("a behaviour is five slots wide", sprite_spec.size() == 5, str(sprite_spec))
	h.check("and the fifth is the parameters the span authored",
		sprite_spec.size() == 5 and str(sprite_spec[4]) == SHORT_PARAMS,
		_shown(str(sprite_spec[4]) if sprite_spec.size() == 5 else ""))
	h.check("the behaviour channel's span carries its own, not the sprite's",
		(spans[0] as Array).size() == 5 and str((spans[0] as Array)[4]) == LONG_PARAMS,
		_shown(str((spans[0] as Array)[4]) if (spans[0] as Array).size() == 5 else ""))
	h.complete("the span reaches the frame loop")

	# The other half of the decode: the string is only worth carrying if the
	# interpreter's own `value()` answers a property list for it. Asserted here
	# rather than in the player case because it is a fact about the two literals
	# and needs no movie.
	h.begin("the parameters evaluate")
	var short_list: Variant = _value_of(SHORT_PARAMS)
	h.check("a symbol/string pair is a property list",
		typeof(short_list) == TYPE_DICTIONARY
			and str((short_list as Dictionary).get("prGotoFrame", "")) == "mainmenu",
		str(short_list))
	var long_list: Variant = _value_of(LONG_PARAMS)
	h.check("six properties, an empty string among them, stay six",
		typeof(long_list) == TYPE_DICTIONARY and (long_list as Dictionary).size() == 6,
		str(long_list))
	h.complete("the parameters evaluate")


static func _value_of(text: String) -> Variant:
	var handled: Array = []
	return LingoBuiltins.call_builtin("value", [text], handled)


static func _shown(text: String) -> String:
	return "\"%s\" (%d bytes)" % [text, text.to_utf8_buffer().size()]


static func _rows_shown(rows: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for row in rows:
		out.append("%s ch %s [%s..%s] member %s" % [str(row.get("kind")),
			str(row.get("channel")), str(row.get("start")), str(row.get("end")),
			str(row.get("script_member"))])
	return "; ".join(out)


# ------------------------------------------------------------------ player


## A behaviour script of the loaded movie that declares **no** `beginSprite`, and
## the interval it came from.
##
## No `beginSprite` on purpose: `send_sprite_message` creates the instance and
## then only runs a handler the script declares, so a script without one lets
## this drive the real code path and change nothing about the movie. A script
## with one would run a screen's initialisation against a channel it is not on.
func _quiet_behaviour(preview) -> Array:
	var score = preview.get("_score")
	if score == null:
		return []
	for interval in score.intervals():
		var script: Dictionary = preview.call("_script_in_lib",
			int(interval["script_cast_lib"]), int(interval["script_member"]))
		if script.is_empty():
			continue
		var declares := false
		for handler in script.get("handlers", []):
			if str((handler as Dictionary).get("name", "")).to_lower() == "beginsprite":
				declares = true
				break
		if not declares:
			return [interval, script]
	return []


func _player(h: Harness, _args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	for _i in 90:
		await process_frame
	var interpreter = preview.get("_interpreter")
	var movie := str(preview.call("movie_name")).to_lower()
	print("movie: %s, frame %d" % [movie, int(preview.get("_index"))])

	h.begin("the span reaches the instance")
	var found: Array = _quiet_behaviour(preview)
	if found.is_empty():
		print("note: %s carries no behaviour script without a beginSprite" % movie)
		h.complete("the span reaches the instance")
		return
	var script: Dictionary = found[1]
	# Declared the way the movie would declare it, because Director's `property`
	# statement is the only thing that makes an instance variable and
	# `set_slot` refuses a name nobody declared -- which is `ScriptContext::
	# setProp`'s own rule (`lingo-object.cpp:742-765`) and the next check.
	var names: Array = script.get("properties", [])
	if not names.has("prgotoframe"):
		names.append("prgotoframe")
	script["properties"] = names
	interpreter.release_behaviour(script, SCRATCH_CHANNEL)

	# **The parameters come out of the fixture's decoded score, not out of a
	# literal here**, so this case fails when the decode is reverted rather than
	# passing on a string the harness supplied. The lib and member are the loaded
	# movie's, because only they resolve to a script; the fifth slot is the one the
	# score answered, carried through `sprite_behaviours_at`.
	var fixture := Score.new()
	fixture.parse(_fixture_payload())
	var fixture_spans: Dictionary = FrameLoop.sprite_behaviours_at(fixture, SPAN_A_FIRST - 1)
	var from_score := ""
	var fixture_spec: Array = fixture_spans.get(SPAN_A_SPRITE - Score.CHANNEL_BIAS, [])
	if fixture_spec.size() == 5:
		from_score = str(fixture_spec[4])
	# One pair the fixture authors and one the script cannot possibly declare, so
	# the drop below is asserted on the same instance as the write above it.
	var authored := "%s, #prNeverDeclared: 7]" % from_score.trim_suffix("]") \
		if from_score != "" else ""
	FrameLoop.send_sprite_message(preview, "beginSprite", SCRATCH_CHANNEL,
		[0, 0, int(found[0]["script_cast_lib"]), int(found[0]["script_member"]), authored])
	var instance: Variant = interpreter.live_behaviour(script, SCRATCH_CHANNEL)
	if not h.check("beginSprite made the instance", instance != null,
			"script %s" % str(script.get("script", ""))):
		h.complete("the span reaches the instance")
		return
	h.check("a declared property holds the value the span authored",
		str(instance.call("get_slot", "prGotoFrame")) == "mainmenu",
		"prGotoFrame is %s" % str(instance.call("get_slot", "prGotoFrame")))
	# The reference drops a pair the script never declared rather than creating
	# the slot: `setProp` with `force = false` offers it to the ancestor and then
	# gives up. Inventing it would let this port run a behaviour the original
	# could not, so the drop is asserted rather than tolerated.
	h.check("a pair the script never declared is dropped, not invented",
		not bool(instance.call("has_slot", "prNeverDeclared")),
		"slots %s" % str(instance.call("slot_names")))
	# The seeding happens once, on the pass that builds the object. A behaviour
	# that assigns its own property in `beginSprite` must not have the author's
	# value put back under it on the next message.
	instance.call("set_slot", "prGotoFrame", "changed by the script")
	FrameLoop.send_sprite_message(preview, "beginSprite", SCRATCH_CHANNEL,
		[0, 0, int(found[0]["script_cast_lib"]), int(found[0]["script_member"]),
		"[#prGotoFrame: \"mainmenu\"]"])
	h.check("a second message does not re-seed the live instance",
		str(instance.call("get_slot", "prGotoFrame")) == "changed by the script",
		"prGotoFrame is %s" % str(instance.call("get_slot", "prGotoFrame")))
	interpreter.release_behaviour(script, SCRATCH_CHANNEL)
	h.complete("the span reaches the instance")

	_live_movie(h, preview, interpreter, movie)


## The loaded title's own spans, when it authors a parameter at all.
##
## Says so and asserts nothing when it does not, which is the honest shape for a
## check whose subject is 0 in six of the eight corpus roots. `--survey` is where
## the population is counted.
func _live_movie(h: Harness, preview, interpreter, movie: String) -> void:
	var score = preview.get("_score")
	if score == null:
		return
	var authored: Array[Dictionary] = []
	for interval in score.intervals():
		if str(interval.get("initializer_params", "")) != "":
			authored.append(interval)
	print("%s: %d of %d interval(s) carry an authored parameter" % [
		movie, authored.size(), score.intervals().size()])
	if authored.is_empty():
		print("note: %s authors no behaviour parameter, so the live case asserts nothing" % movie)
		return
	h.begin("the live movie")
	var seeded := 0
	var spans: Dictionary = FrameLoop.sprite_behaviours_at(score, int(preview.get("_index")))
	for channel in spans:
		var spec: Array = spans[channel]
		var at := 0
		while at + 5 <= spec.size():
			if str(spec[at + 4]) != "":
				seeded += 1
			at += 5
	print("  %d of the spans covering frame %d carry one" % [seeded, int(preview.get("_index"))])
	var checked := 0
	# The one end-to-end proof this entry can get from real bytes: take a span the
	# *container* authored, build its instance through the real interpreter, and
	# read the property back. Built on `SCRATCH_CHANNEL` rather than on the span's
	# own channel so that nothing the movie is running is disturbed.
	var proved := ""
	for interval in authored:
		var script: Dictionary = preview.call("_script_in_lib",
			int(interval["script_cast_lib"]), int(interval["script_member"]))
		if script.is_empty():
			continue
		var parsed: Variant = _value_of(str(interval["initializer_params"]))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		checked += 1
		if proved != "":
			continue
		# `script["properties"]` keeps the case the author wrote and the instance
		# lower-cases on the way in (`lingo_object.gd:_init`), so the comparison
		# has to fold both sides -- a `has()` against the raw list answers no for
		# every property in the corpus and this case would then assert nothing.
		var declared: Array = []
		for name in (script.get("properties", []) as Array):
			declared.append(str(name).to_lower())
		for name in (parsed as Dictionary):
			if not declared.has(str(name).to_lower()):
				continue
			interpreter.release_behaviour(script, SCRATCH_CHANNEL)
			var instance: Variant = interpreter.behaviour_instance(script,
				SCRATCH_CHANNEL, false, str(interval["initializer_params"]))
			var got: Variant = instance.call("get_slot", str(name))
			h.check("%s's %s is the value the score authored" % [
					str(script.get("script", "")), str(name)],
				str(got) == str((parsed as Dictionary)[name]),
				"%s vs %s" % [str(got), str((parsed as Dictionary)[name])])
			interpreter.release_behaviour(script, SCRATCH_CHANNEL)
			proved = str(script.get("script", ""))
			break
	h.check("every authored parameter evaluates to a property list",
		checked > 0, "%d of %d resolved to a script and a list" % [checked, authored.size()])
	if proved == "":
		print("note: no authored parameter names a property its script declares")
	h.complete("the live movie")


# ------------------------------------------------------------------ survey


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


static func _i32(d: PackedByteArray, o: int) -> int:
	var v := (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
	return v - 4294967296 if v >= 2147483648 else v


## Every corpus root's spans, counted twice: once by `DirectorScore` and once by
## a raw walk of the entry table that does **not** skip initialiser entries.
##
## The two counts are the cross-check on the skip set and are the reason this
## mode asserts anything at all. In a corpus that authors no initialiser they
## must be identical -- which is what says the change cannot have cost the six
## shipped titles a span -- and in one that does, every interval the raw walk has
## and the decoder does not must be an entry some element named.
func _survey(h: Harness, args: Dictionary) -> void:
	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	if explicit != "":
		for part in explicit.split(",", false):
			roots.append(str(part).strip_edges())
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	roots.sort()
	var list_left := Args.number(args, "list", 8)

	var containers := 0
	var movies := 0
	var elements := 0
	var with_init := 0
	var bad_index := 0
	var not_a_list := 0
	var samples: Array[String] = []
	var per_root: Dictionary = {}
	# Where the raw walk and the decoder disagree about how many intervals a
	# container has, and whether the difference is explained.
	var extra_raw := 0
	var unexplained := 0

	for root in roots:
		var targets: Array[String] = []
		_walk(root, targets)
		targets.sort()
		var root_init := 0
		var root_elements := 0
		for path in targets:
			containers += 1
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var vwsc: Array = f.ids_of("VWSC")
			if vwsc.is_empty():
				f.close()
				continue
			var payload: PackedByteArray = f.read_chunk(int(vwsc[0]))
			f.close()
			var score := Score.new()
			if not score.parse(payload):
				continue
			movies += 1
			var named: Dictionary = {}
			for interval in score.intervals():
				var index := int(interval.get("initializer_index", 0))
				if index == 0:
					continue
				with_init += 1
				root_init += 1
				named[index] = true
				var params := str(interval.get("initializer_params", ""))
				if params == "":
					bad_index += 1
				elif typeof(_value_of(params)) != TYPE_DICTIONARY:
					not_a_list += 1
				if list_left > 0:
					list_left -= 1
					samples.append("    %s  %s ch %d member %d -> entry %d: %s" % [
						path.trim_prefix("res://"), str(interval.get("kind")),
						int(interval.get("channel", 0)), int(interval.get("script_member", 0)),
						index, params])
			var raw := _raw_intervals(payload)
			root_elements += raw[0]
			elements += raw[0]
			var difference: int = raw[1] - score.intervals().size()
			if difference != 0:
				extra_raw += difference
				# The raw walk sees more only because it read an initialiser entry
				# as a span. A container where it sees more *and* names no
				# initialiser is a decode this survey cannot account for.
				if named.is_empty() or difference < 0:
					unexplained += 1
					print("unexplained: %s raw %d vs decoded %d, %d initialiser(s)" % [
						path.trim_prefix("res://"), raw[1], score.intervals().size(),
						named.size()])
		per_root[root] = [root_init, root_elements]

	print("%d container(s), %d score(s), %d behaviour element(s)" % [
		containers, movies, elements])
	print("spans the decoder kept that name an initialiser: %d" % with_init)
	print("intervals the raw walk has and the decoder does not: %d" % extra_raw)
	print("per root (initialisers / elements):")
	for root in roots:
		var row: Array = per_root.get(root, [0, 0])
		print("    %-34s %6d / %6d" % [root, int(row[0]), int(row[1])])
	if not samples.is_empty():
		print("samples:")
		for line in samples:
			print(line)

	h.begin("the corpus")
	h.check("every initialiser index the decoder kept opened a non-empty entry",
		bad_index == 0, "%d of %d were empty" % [bad_index, with_init])
	h.check("and every one of them evaluates to a property list",
		not_a_list == 0, "%d of %d did not" % [not_a_list, with_init])
	h.check("no container loses an interval the raw walk found", unexplained == 0,
		"%d container(s) the skip set cannot account for" % unexplained)
	if with_init == 0:
		print("note: no root in this run authors a behaviour parameter, so the first two checks are vacuous")
	h.complete("the corpus")


## `[elements, intervals]` from a walk of the entry table with **no** skip set --
## `parse()` as it stood before `bugs.md` 83, so the two can be compared.
static func _raw_intervals(payload: PackedByteArray) -> Array:
	if payload.size() < 28 or _i32(payload, 4) != Score.SCORE_LIST_MARKER:
		return [0, 0]
	var entry_count := _i32(payload, 12)
	if entry_count <= 0:
		return [0, 0]
	var offsets_at := 24
	var base := offsets_at + 4 * (entry_count + 1)
	if base > payload.size():
		return [0, 0]
	var offsets := PackedInt32Array()
	offsets.resize(entry_count + 1)
	for i in entry_count + 1:
		offsets[i] = _i32(payload, offsets_at + i * 4)
	var slice := func(index: int) -> PackedByteArray:
		if index < 0 or index >= entry_count:
			return PackedByteArray()
		var start: int = base + offsets[index]
		var stop: int = base + offsets[index + 1]
		if start < 0 or stop > payload.size() or stop < start:
			return PackedByteArray()
		return payload.slice(start, stop)
	var elements := 0
	var intervals := 0
	for i in range(2, entry_count):
		var primary: PackedByteArray = slice.call(i)
		if primary.size() < 44:
			continue
		var behaviours: PackedByteArray = slice.call(i + 1)
		var at := 0
		while at + Score.BEHAVIOUR_ELEMENT_SIZE <= behaviours.size():
			elements += 1
			if ((behaviours[at + 2] << 8) | behaviours[at + 3]) > 0:
				intervals += 1
			if _i32(primary, 16) == 0:
				break
			at += Score.BEHAVIOUR_ELEMENT_SIZE
	return [elements, intervals]
