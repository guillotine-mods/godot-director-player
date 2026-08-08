extends SceneTree
## Does the engine bind what `docs/LINGO_SURFACE.md` says it binds?
##
##   godot --headless --path . --script tools/lingo_surface_audit.gd
##   godot --headless --path . --script tools/lingo_surface_audit.gd -- --survey
##   godot --headless --path . --script tools/lingo_surface_audit.gd -- --name intersects
##
## `tools/check_surface_coverage.gd` used to ask this question and was deleted
## with the retired renderer, **because it audited the retired renderer's host**.
## That is the whole reason this file exists: the one instrument that could have
## caught `intersects` was pointed at the wrong object, so §9.3 could list the
## operator as implemented for as long as the preview has been the main scene
## while `scenes/preview_lingo_host.gd` bound neither it nor `within` -- and every
## inventory drop in every room of every title evaluated to "nothing", silently,
## because an unbound operator answers VOID and VOID is falsy.
##
## Three more of the same shape, all found by accident in one session:
##
##   `set the text of member`      `set_member_prop` was a bare `pass`, §9.3
##   `set the editable of member`  listed both as implemented member writes
##   `puppetTempo`                 in the host's IGNORED list; §9.1 gives it
##                                 precedence over the score's tempo
##   `saveMovie`                   likewise, and no save in the game outlived
##                                 its own process until it was implemented
##
## ## What it compares
##
## Three sources, and the value is entirely in the disagreements between them:
##
## 1. **What the document claims** -- §19's claim table, which is machine-readable
##    precisely so that this can read it. Prose cannot be audited.
## 2. **What the live engine binds** -- and, crucially, whether a binding *does*
##    anything. `IGNORED` and a bare `pass` body both look exactly like a binding
##    to a naive scan, and both were how a documented capability turned out not to
##    exist. `live`, `inert` and `absent` are three *observed* states here, never
##    two; `noop` is a fourth the document may record and observation cannot see.
## 3. **What the corpus calls** -- every container under every root in `games/`,
##    read as the authored Lingo in the `CASt` records. So each gap carries a
##    usage count and the priority list orders itself.
##
## **A row that is claimed `live`, is bound, and is inert is the highest-severity
## finding there is.** It is the `intersects` shape, and it is invisible from
## every direction except this one: the doc says yes, the binding exists, the
## call returns cleanly, and nothing happens.
##
## The last check is the one that keeps the table from becoming a suppression
## list. A table seeded from the engine agrees with the engine by construction,
## so §19 also pins the *number* of capabilities a movie can still reach and this
## fails if it moves in either direction -- a gap closed without the count coming
## down is as red as a new one opening.
##
## ## Why the corpus is read from the containers and not from `reference/lingo/`
##
## Two reasons, and the second is the one that bites.
##
## `reference/lingo/` is Piposh 2 and nothing else. The engine runs six titles,
## and a name with 0 uses in one title and 205 in another is exactly the shape
## `tools/key_script_survey.gd` was written to stop being surprised by.
##
## And `reference/lingo/` is ProjectorRays' *decompilation*, which renders bare
## `pass` as `pass()` and `dontPassEvent` as `dont(pass)` -- so a token grep for
## either answers 0 where the real count is 6. The `CASt` records hold what the
## author typed. Where a count here disagrees with one quoted in the document,
## this is the authored source and the document's is the decompiled tree.
##
## ## How it is kept from going dark
##
## `gate.sh` reports a 0-check PASS as EMPTY because four harnesses in one day
## reported success over an empty set. This one asserts its own inputs are
## non-trivial *before* it compares anything: no claims parsed, no bindings
## found, or no corpus scanned is a **failure of the harness**, not a clean bill
## of health. And the name map is closed in both directions -- a name the engine
## binds with no row in §19 fails, and a name the corpus calls with no row fails
## -- so the audited set cannot quietly shrink to the part that agrees.
##
## Title-agnostic. Nothing here knows which game is loaded; the corpus sweep is
## over every root there is.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Host := preload("res://scenes/preview_lingo_host.gd")
const Builtins := preload("res://lingo/lingo_builtins.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")

const DOC := "res://docs/LINGO_SURFACE.md"
const HOST_SRC := "res://scenes/preview_lingo_host.gd"
const PREVIEW_SRC := "res://scenes/director_preview.gd"
const MEMBERS_SRC := "res://scenes/preview/members.gd"
const SPRITE_STATE_SRC := "res://scenes/preview/sprite_state.gd"
const WINDOWS_SRC := "res://scenes/preview/windows.gd"
const SOUND_SRC := "res://scenes/preview/sound.gd"
const GAMES_DIR := "res://games"

## The one seam a property name crosses on its way to the renderer, loaded so the
## audit compares the same spellings the engine does.
const SpriteProps := preload("res://scenes/preview/sprite_props.gd")
## The parser's keyword table, for the names §1 calls builtins and §11.3 makes
## grammar. Read rather than restated, for the reason `preview_lingo_host.gd`
## gives at its own `GO_WORDS`: the parser emitted them, so the parser's list is
## the authority on what can arrive.
const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

## The three states a name can be in, and the reason there are three rather than
## two. `absent` is honest -- the interpreter reports it and a log names it.
## `inert` is the dangerous one: it answers, it is counted as reached, and it
## does nothing.
const LIVE := "live"
const INERT := "inert"
const ABSENT := "absent"
## A fourth *recorded* state, indistinguishable from `inert` by observation and
## different from it in the only way that matters: Director's own semantics for
## the name are "nothing a movie can observe happens here". `nothing` is the
## clearest case; the `preLoad`/`unLoad` family are memory hints; `restart` and
## `shutDown` are a 1995 idea. Recording one of these as `inert` would put it in
## the priority list for ever and push the real gaps down the page.
##
## It is a suppression channel and it is meant to be an uncomfortable one: it is
## per name, it is written in the document rather than in this file, and the
## reason belongs in the row's note. Anything whose absence a player could
## notice -- `beep`, `alert`, `quit`, `continue`, `updateStage` -- is a gap.
const NOOP := "noop"

## Floors under each input. Not a style choice: every one of these was a
## harness that passed over an empty set. They are deliberately far below the
## real numbers, so they catch a source that has *stopped resolving* rather than
## one that has merely changed.
const MIN_CLAIMS := 80
const MIN_ARMS := 20
const MIN_CONTAINERS := 50
const MIN_ROOTS := 2
const MIN_TOKENS := 5000


func _init() -> void:
	var args := Args.parse()
	var survey := Args.flag(args, "survey")
	var only := Args.text(args, "name").to_lower()

	var h := Harness.new()

	# ---------------------------------------------------------------- inputs
	var claims := _claims()
	var catalogue := _catalogue()
	var bound := await _bound()
	var corpus := _corpus(only)

	h.begin("the audit has three non-empty sources")
	h.check(
		"§19's claim table parses (%d rows, floor %d)" % [claims.size(), MIN_CLAIMS],
		claims.size() >= MIN_CLAIMS,
		"docs/LINGO_SURFACE.md §19 is the specification this audits against; "
		+ "no rows means the parse broke, not that the engine is clean")
	h.check(
		"§1-§5's catalogue parses (%d Director names)" % catalogue.size(),
		catalogue.size() >= MIN_CLAIMS,
		"the tables in §1 name what Director offers; an empty read makes every "
		+ "corpus name look unknown")
	h.check(
		"the live host binds something (%d builtin arms, floor %d)"
			% [int(bound.get("arms", 0)), MIN_ARMS],
		int(bound.get("arms", 0)) >= MIN_ARMS,
		"scanned %s; if this is 0 the scan lost the file, and every name would "
			% HOST_SRC + "report as a gap")
	h.check(
		"the corpus scan reached %d roots and %d containers (floors %d/%d)"
			% [int(corpus["roots"]), int(corpus["containers"]), MIN_ROOTS, MIN_CONTAINERS],
		int(corpus["roots"]) >= MIN_ROOTS and int(corpus["containers"]) >= MIN_CONTAINERS,
		"a gap with no usage count is a gap nobody can prioritise")
	h.check(
		"the corpus scan read %d call and property sites (floor %d)"
			% [int(corpus["total"]), MIN_TOKENS],
		int(corpus["total"]) >= MIN_TOKENS,
		"containers opened but nothing was read out of them")
	h.complete("the audit has three non-empty sources")

	var rows := _rows(claims, catalogue, bound, corpus)
	if only != "":
		var narrowed: Array = []
		for row in rows:
			if str((row as Dictionary)["name"]).contains(only):
				narrowed.append(row)
		rows = narrowed
	_print_table(rows, survey)
	if only != "":
		print("corpus sites containing \"%s\":" % only)
		for site in (corpus["sites"] as Array):
			print("  %s" % site)
		print("")

	if survey:
		# Survey mode exists to *author* §19, so it prints the rows in the table's
		# own spelling and asserts nothing about agreement. It still runs the
		# input floors above, because a survey over an empty set is the same lie.
		_print_seed(rows)
		quit(h.finish("surveyed the Lingo surface (no agreement asserted)"))
		return

	# ------------------------------------------------------------ the verdict
	h.begin("every name the engine binds is recorded in §19")
	var unrecorded: Array[String] = []
	for row in rows:
		var r: Dictionary = row
		if not bool(r["recorded"]) and str(r["observed"]) != ABSENT:
			unrecorded.append("%s (%s, %s)" % [r["name"], r["kind"], r["observed"]])
	h.check(
		"no binding is missing from the claim table",
		unrecorded.is_empty(),
		"; ".join(unrecorded))
	h.complete("every name the engine binds is recorded in §19")

	h.begin("every Director name the corpus calls is recorded in §19")
	var unclaimed: Array[String] = []
	for row in rows:
		var r: Dictionary = row
		if not bool(r["recorded"]) and int(r["uses"]) > 0:
			unclaimed.append("%s (%s, %d uses)" % [r["name"], r["kind"], r["uses"]])
	h.check(
		"no used capability is missing from the claim table",
		unclaimed.is_empty(),
		"; ".join(unclaimed))
	h.complete("every Director name the corpus calls is recorded in §19")

	h.begin("the document and the engine agree, name by name")
	var disagreements := 0
	for row in rows:
		var r: Dictionary = row
		if not bool(r["recorded"]):
			continue
		var claimed: String = str(r["claimed"])
		var observed: String = str(r["observed"])
		if claimed == observed or (claimed == NOOP and observed == INERT):
			continue
		disagreements += 1
		h.check(
			"%s %s -- §19 says %s, the engine is %s%s" % [
				r["kind"], r["name"], claimed, observed,
				("  [%d corpus sites]" % int(r["uses"])) if int(r["uses"]) > 0 else ""],
			false,
			_severity(claimed, observed, int(r["uses"])))
	if disagreements == 0:
		h.check("all %d recorded names match the live engine" % claims.size(), true)
	h.complete("the document and the engine agree, name by name")

	# A table seeded from the engine agrees with the engine by construction, and
	# that is exactly how a claim table decays into a suppression list: record the
	# gap, the row matches, the gate is green for ever. So the *number* of gaps a
	# movie can still reach is recorded separately and pinned. It can only be
	# wrong in two directions and both are worth a red gate: a new inert binding
	# for a name some title calls, or a gap closed without the count coming down.
	h.begin("the reachable-gap count is what §19 records")
	var open_gaps: Array = []
	for row in rows:
		var r: Dictionary = row
		if str(r["claimed"]) == NOOP:
			continue
		if str(r["observed"]) != LIVE and int(r["uses"]) > 0:
			open_gaps.append(r)
	var recorded_gaps := _recorded_gap_count()
	h.check(
		"%d capabilities are reachable by a movie and not live (§19 records %d)"
			% [open_gaps.size(), recorded_gaps],
		open_gaps.size() == recorded_gaps,
		"if this fell, lower the number in §19 and say which gap closed; "
			+ "if it rose, something bound a name inert that a title calls")
	h.complete("the reachable-gap count is what §19 records")
	_print_priority(open_gaps)

	quit(h.finish(
		"docs/LINGO_SURFACE.md §19 against %s, %s and %d containers"
			% [HOST_SRC.get_file(), "lingo_builtins.gd", int(corpus["containers"])]))


## Why a particular disagreement matters, in the order the brief ranks them.
func _severity(claimed: String, observed: String, uses: int) -> String:
	if claimed == LIVE and observed == INERT:
		return "HIGHEST -- claimed, bound and inert. This is the `intersects` " \
			+ "shape: the call succeeds, is counted as reached, and does nothing"
	if claimed == LIVE and observed == ABSENT:
		return "the document promises a capability the engine does not have; " \
			+ ("%d call sites reach it" % uses if uses > 0 else "unused today, but the doc is the spec")
	if claimed == ABSENT and observed != ABSENT:
		return "the engine gained this and the document did not follow -- " \
			+ "update §19 rather than the code"
	if (claimed == INERT or claimed == NOOP) and observed == LIVE:
		return "implemented since §19 was written; promote the row and bring the " \
			+ "reachable-gap count down with it"
	if claimed == NOOP and observed == ABSENT:
		return "recorded as a deliberate no-op and not bound at all -- an unbound " \
			+ "name is reported and a no-op is not, so this is a demotion"
	return "recorded state and observed state differ"


# ============================================================ the claim table
#
# §19 is a markdown table and nothing else, for one reason: prose cannot be
# audited, and every one of the four failures this file exists for was a prose
# claim that nobody could check mechanically.
#
#   | `name` | kind | state | note |
#
# `kind` is builtin / system / sprite / member; `state` is live / inert / absent.


func _claims() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(DOC)
	if text == "":
		return out
	var section := _section(text, "# 19.")
	# From `## The table` onward only. §19 also carries a prioritised list of the
	# open gaps, and that is a markdown table too -- parsed as claims it added
	# thirteen rows named after their own site counts, each of which then failed
	# as a disagreement. The claim table is the one under its own heading.
	var at := section.find("## The table")
	if at < 0:
		return out
	section = section.substr(at)
	if section == "":
		return out
	for line in section.split("\n"):
		var row := str(line).strip_edges()
		if not row.begins_with("|"):
			continue
		var cells := _cells(row)
		if cells.size() < 3:
			continue
		var name := _unquote(cells[0]).to_lower()
		var kind := cells[1].strip_edges().to_lower()
		var state := cells[2].strip_edges().to_lower()
		# The header and separator rows are rejected by the state cell alone -- and
		# it has to be the state cell, not the name. Rejecting the literal name
		# "name" also threw away `the name of member`, 756 sites, which then failed
		# as an unrecorded binding: the guard against the header ate a row.
		if name == "" or not [LIVE, INERT, ABSENT, NOOP].has(state):
			continue
		out[_key(kind, name)] = {
			"name": name, "kind": kind, "state": state,
			"note": cells[3].strip_edges() if cells.size() > 3 else "",
		}
	return out


## Director's own names, read out of §1 (builtins) and §3-§5 (properties).
##
## Read from the document rather than restated here, because "the reference
## documents are the specification" (`AGENTS.md`) and a second copy of the
## catalogue is a second thing to keep in step. It is used only to decide
## whether a corpus token is a *Director* name or one of the game's own 39
## handlers -- `displayobject`, `cursorfunk`, `soundspath` and the rest, which
## §9.1 records reporting as unbound builtins for exactly this reason.
func _catalogue() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(DOC)
	if text == "":
		return out
	for spec in [
		# §1 is tables and its prose names the port's own internals -- `_freezeState`,
		# `call_builtin` -- so only the first cell of a table row counts there. §3-§5
		# are prose paragraphs listing backticked property names, so those are read
		# whole.
		["# 1.", "builtin", true], ["## 1.15", "builtin", false],
		["# 3.", "system", false],
		["# 4.", "sprite", false], ["# 5.", "member", false],
	]:
		var pair: Array = spec
		var body := _section(text, str(pair[0]))
		var kind := str(pair[1])
		if bool(pair[2]):
			body = _first_cells(body)
		for name in _backticked(body):
			var low := name.to_lower()
			# `the X` and `X` are one name; the section decides which kind it is.
			if low.begins_with("the "):
				low = low.substr(4)
			if not _plain(low):
				continue
			out[_key(kind, low)] = true
	# §5.1's other qualified entities, which are not sprite and not member and
	# need their own dispatch path -- which is exactly why they are easy to miss.
	for spec in [["window", "of window W"], ["sound", "the volume of sound"]]:
		var pair: Array = spec
		var at := text.find(str(pair[1]))
		if at < 0:
			continue
		var line_end := text.find("\n\n", at)
		for name in _backticked(text.substr(at, maxi(line_end - at, 0))):
			if _plain(name):
				out[_key(str(pair[0]), name.to_lower())] = true
	return out


## The first cell of every markdown table row in a block, joined -- so §1's
## tables contribute their names and its prose does not.
static func _first_cells(text: String) -> String:
	var out := ""
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := _cells(line)
		if cells.size() > 0:
			out += cells[0] + "\n"
	return out


## Every backticked identifier in a block of markdown. Anything with a space, a
## bracket or an operator in it is prose or a code fragment, not a name.
func _backticked(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("`([^`\\n]+)`")
	for hit in re.search_all(text):
		var raw := hit.get_string(1).strip_edges()
		# `preLoad`, `preLoadCast`, `preLoadMember` -- a table cell may list several.
		for part in raw.split(",", false):
			var name := str(part).strip_edges().trim_prefix("the ").strip_edges()
			if _plain(name):
				out.append(name)
	return out


static func _plain(name: String) -> bool:
	if name.length() < 2 or name.length() > 30:
		return false
	# A GDScript constant quoted in the prose -- `SPRITE_WRITES`, `NATIVE_HANDLERS`,
	# `EMPTY` -- is a statement about this port's own code, not a Lingo name. The
	# language's own all-caps words are the constants in §1.15, and those are
	# reachable by their lower-case spellings from the same tables.
	if name == name.to_upper():
		return false
	if name.begins_with("_"):
		return false
	for i in name.length():
		var c := name[i]
		if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## A markdown section, from its heading to the next heading of the same level --
## so `# 1.` keeps §1.3 inside it and `## 1.15` stops at §1.16.
func _section(text: String, heading: String) -> String:
	var start := text.find("\n%s" % heading)
	if start < 0:
		return ""
	start += 1
	var level := heading.substr(0, heading.find(" ") + 1)
	if level == "":
		level = "# "
	var end := text.find("\n%s" % level, start + heading.length())
	return text.substr(start, (end - start) if end > start else -1)


static func _cells(row: String) -> PackedStringArray:
	var body := row.strip_edges().trim_prefix("|").trim_suffix("|")
	var out := PackedStringArray()
	for cell in body.split("|"):
		out.append(str(cell).strip_edges())
	return out


static func _unquote(cell: String) -> String:
	return cell.strip_edges().trim_prefix("`").trim_suffix("`").strip_edges()


static func _key(kind: String, name: String) -> String:
	return "%s/%s" % [kind, name]


# ============================================================== the live engine
#
# Two instruments, deliberately, and they check each other.
#
# The **probe** is the live object: `Host.new().call_builtin(name, [])` with no
# preview attached. Every bound arm guards on `preview == null` and returns 0, and
# the fall-through returns `null` -- so a null answer is "this host binds no such
# name", from the running code rather than from a reading of it. No side effects
# reach anything, because there is nothing attached for them to reach.
#
# The **scan** reads the same file's `match` arms, and exists to answer the
# question the probe cannot: *which* arm answered, and whether that arm does
# anything. A name in `IGNORED` and a name with a real arm both probe as bound.


func _bound() -> Dictionary:
	var out := {"arms": 0, "state": {}, "detail": {}}
	var state: Dictionary = out["state"]
	var detail: Dictionary = out["detail"]

	var host_src := FileAccess.get_file_as_string(HOST_SRC)
	var preview_src := FileAccess.get_file_as_string(PREVIEW_SRC)
	var arms := _match_arms(host_src, "func call_builtin", "if IGNORED.has(low)")
	out["arms"] = arms.size()

	var probe := Host.new()
	var ignored: Array = Host.IGNORED

	# --- builtins answered by the host -------------------------------------
	for name in arms:
		var answered: Variant = probe.call_builtin(str(name), [])
		var body: String = str(arms[name])
		var inert := _arm_is_inert(body)
		state[_key("builtin", str(name))] = ABSENT if answered == null \
			else (INERT if inert else LIVE)
		detail[_key("builtin", str(name))] = "host arm" + ("  (no effect)" if inert else "")
	for name in ignored:
		var key := _key("builtin", str(name))
		if state.has(key):
			continue
		var answered: Variant = probe.call_builtin(str(name), [])
		state[key] = ABSENT if answered == null else INERT
		detail[key] = "host IGNORED"

	# --- builtins answered by the title-agnostic module ---------------------
	#
	# Probed by name against the module itself, over the catalogue, because the
	# module has no table to read: `call_builtin` dispatches through seven
	# private matches and `handled` is the only thing that says whether a name
	# was one of its own.
	for name in _module_names():
		var key := _key("builtin", str(name))
		if state.get(key, ABSENT) == LIVE:
			continue
		state[key] = LIVE
		detail[key] = "lingo_builtins.gd"

	# --- names the parser consumes as grammar --------------------------------
	#
	# §1's tables list `put`, `set`, `tell`, `sprite`, `member` and `field` as
	# builtins, and none of them ever reaches `call_builtin`: the parser turns
	# them into statement and reference *nodes* (§11.5, §11.7), and the
	# interpreter executes those directly. Absent from the host is the correct
	# state for every one of them, so they are read out of the parser's own
	# keyword table rather than excused by a list here -- a hand-written
	# exemption list is how a real gap gets hidden among the false ones.
	var catalogue := _catalogue()
	for word in Grammar.KEYWORDS:
		var key := _key("builtin", str(word))
		if state.get(key, ABSENT) != ABSENT:
			continue
		# Only the words §1 also calls builtins. `on`, `end`, `if` and `repeat` are
		# grammar and nothing else, and adding them here would bury the audited
		# surface under 67,000 `end` statements.
		if not catalogue.has(key):
			continue
		state[key] = LIVE
		detail[key] = "grammar: a parser keyword (§11.3), never dispatched"

	# --- system properties --------------------------------------------------
	#
	# `get_system_prop` returns 0 the moment `preview` is null, so the probe used
	# above cannot see past it. The arms are read instead, and the read half is
	# then confirmed live against a booted preview below.
	var reads := _match_arms(host_src, "func get_system_prop", "func _ticks_since")
	var writes := _match_arms(host_src, "func set_system_prop", "func get_sprite_prop")
	for name in reads:
		var key := _key("system", str(name))
		state[key] = INERT if _arm_is_inert(str(reads[name])) else LIVE
		detail[key] = "read" + ("+write" if writes.has(name) else " only")
	for name in writes:
		var key := _key("system", str(name))
		if state.has(key):
			continue
		# A write with no read is legitimate -- `the keyDownScript` had one for a
		# while -- but it is worth naming, because a property a script cannot read
		# back is one a script cannot round-trip.
		state[key] = INERT if _arm_is_inert(str(writes[name])) else LIVE
		detail[key] = "write only"

	# --- sprite properties ---------------------------------------------------
	#
	# The write path is where the trap lives, and it is a *third* shape of inert:
	# `sprite_state.write_prop` stores any name at all in the override table, so a
	# write always round-trips through `read_prop`, and only the keys
	# `sprite_state.effective` consumes ever reach the screen. `moveableSprite`,
	# `editableText` and `constraint` were each stored, read back correctly, and
	# consumed by nobody -- which is why this scans the *consumer* and not the
	# setter.
	var sprite_reads := _match_arms(
		FileAccess.get_file_as_string(SPRITE_STATE_SRC), "func read_prop", "# The channel holds")
	var consumed := _consumed_keys()
	for name in consumed:
		var key := _key("sprite", str(name))
		state[key] = LIVE
		detail[key] = "merged by effective()"
	# Readable and *not* merged is not "live". `the ink of sprite N` reads back the
	# score's own byte, so a read looks right, and `set the ink of sprite N` is
	# stored in the override table and consumed by nobody -- the exact shape
	# `moveableSprite`, `editableText` and `the constraint of sprite` each had.
	# Recording it as live because the read works is how it stayed hidden.
	for name in sprite_reads:
		var key := _key("sprite", str(name))
		if state.get(key, "") == LIVE:
			continue
		state[key] = INERT
		detail[key] = "read from the score record; a write reaches nothing"
	# Anything a script can write and nothing consumes. Canonicalised first,
	# through the same seam the host writes go through: `moveableSprite` is stored
	# as `moveable` and `editableText` as `editable`, and comparing the *script's*
	# spelling against the *record's* keys is the very mistake `sprite_props.gd`
	# exists to make impossible.
	var aliases: Dictionary = SpriteProps.ALIASES
	for name in _override_only():
		var key := _key("sprite", str(name))
		if state.has(key):
			continue
		var canonical := str(aliases.get(str(name), str(name)))
		if consumed.has(canonical) or sprite_reads.has(canonical):
			state[key] = LIVE
			detail[key] = "merged by effective() as `%s`" % canonical
			continue
		state[key] = INERT
		detail[key] = "stored in _overrides, consumed by nothing"

	# --- window and sound properties ----------------------------------------
	#
	# §5.1's other qualified entities. They earn a scan of their own because they
	# need their own dispatch path, and the last time one did not have it `set the
	# volume of sound N` -- 66 writes -- went nowhere with nothing recorded
	# (`docs/bugs-closed.md` 27).
	var windows_src := FileAccess.get_file_as_string(WINDOWS_SRC)
	var sound_src := FileAccess.get_file_as_string(SOUND_SRC)
	for spec in [
		["window", windows_src, "static func read_prop", "static func size_of", "windows.gd read"],
		["window", windows_src, "static func write_prop", "## The window property",
			"windows.gd read+write"],
		["sound", sound_src, "static func read_prop", "\nstatic func ", "sound.gd read"],
	]:
		var pair: Array = spec
		var entity_arms := _match_arms(str(pair[1]), str(pair[2]), str(pair[3]))
		for name in entity_arms:
			var key := _key(str(pair[0]), str(name))
			var inert := _arm_is_inert(str(entity_arms[name]))
			if state.get(key, "") == LIVE:
				detail[key] = str(pair[4])
				continue
			state[key] = INERT if inert else LIVE
			detail[key] = str(pair[4]) + ("  (no effect)" if inert else "")
	# The write path for `the volume of sound N` is not a `match` -- it is a
	# single `if prop != "volume"` guard, which is a fourth shape and the one the
	# arm scan cannot see.
	if preview_src.contains("if prop != \"volume\" or _audio == null:"):
		state[_key("sound", "volume")] = LIVE
		detail[_key("sound", "volume")] = "read and write"

	# --- member properties ---------------------------------------------------
	var member_reads := _match_arms(
		FileAccess.get_file_as_string(MEMBERS_SRC), "func read_prop", "return 0")
	var member_writes := _match_arms(
		preview_src, "func lingo_set_member_prop", "func lingo_sel_start")
	for name in member_reads:
		state[_key("member", str(name))] = LIVE
		detail[_key("member", str(name))] = "members.gd read_prop"
	# `editable` is answered ahead of `read_prop`, on the node, because its value
	# is the authored flag *or* whatever Lingo last wrote.
	if preview_src.contains("if prop == \"editable\":"):
		state[_key("member", "editable")] = LIVE
		detail[_key("member", "editable")] = "director_preview.gd, read and write"
	for name in member_writes:
		var key := _key("member", str(name))
		state[key] = LIVE
		detail[key] = str(detail.get(key, "")) if detail.has(key) else "write"

	# --- the preview, booted -------------------------------------------------
	#
	# The probe above is honest about the host in isolation; this is the only
	# thing that can say a *system property read* reaches an answer rather than
	# the fall-through. Reads only: every name here is a read of hardware, of a
	# timestamp or of engine state, and none of them moves anything.
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	var live_host := Host.new()
	live_host.preview = preview
	for name in reads:
		var key := _key("system", str(name))
		if live_host.get_system_prop(str(name)) == null:
			# The arm exists and still falls through -- a `match` on a name the arm
			# does not actually cover. Nothing in the tree does this today; it is
			# checked because the scan alone could not tell.
			state[key] = ABSENT
			detail[key] = "arm present, read falls through"
	preview.queue_free()
	return out


## Every `match` arm label between two anchors in a source file, as
## `name -> the arm's body`. Labels are the quoted strings on an arm line.
func _match_arms(source: String, from: String, to: String) -> Dictionary:
	var out: Dictionary = {}
	var start := source.find(from)
	if start < 0:
		return out
	var end := source.find(to, start)
	var body := source.substr(start, (end - start) if end > start else -1)
	var open: Array[String] = []
	var collected := ""
	# A label may span lines, ending each but the last with a backslash. Getting
	# this wrong is not cosmetic: the first version flushed the *previous* arm's
	# body against the continuation's names, which reported the nine window
	# properties of `get_system_prop` as inert when they are the one arm in that
	# function that reaches furthest into the preview.
	var continuing := false
	for raw in body.split("\n"):
		var trimmed := str(raw).strip_edges()
		var label := trimmed.begins_with("\"") and (trimmed.ends_with(":") or trimmed.ends_with("\\"))
		if label:
			if not continuing:
				for name in open:
					out[name] = collected
				open = []
				collected = ""
			open.append_array(_quoted(trimmed))
			continuing = trimmed.ends_with("\\")
			continue
		continuing = false
		if trimmed.begins_with("#") or trimmed == "":
			continue
		collected += trimmed + "\n"
	for name in open:
		out[name] = collected
	return out


static func _quoted(line: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("\"([^\"]+)\"")
	for hit in re.search_all(line):
		out.append(hit.get_string(1).to_lower())
	return out


## Does this arm do anything the movie can see?
##
## The two shapes that have already shipped: a body that is only `return 0`, and
## a body that is only `pass`. Both answer cleanly and neither is counted as a
## gap, which is what makes them worse than an unbound name rather than better.
static func _arm_is_inert(body: String) -> bool:
	var meat := ""
	for raw in body.split("\n"):
		var line := str(raw).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		meat += line + ";"
	if meat == "":
		return true
	if meat == "pass;":
		return true
	# Only constant returns and null guards -- nothing reaches the preview, no
	# host state is written.
	if meat.contains("preview.") or meat.contains("preview\n") or meat.contains("="):
		return false
	var re := RegEx.new()
	re.compile("^(return (0|null|\\{\\}|\\[\\]|-1);)+$")
	return re.search(meat) != null


## Names `lingo/lingo_builtins.gd` answers, probed rather than transcribed: it
## dispatches through seven private matches and `handled` is the only public
## statement that a name was one of its own.
func _module_names() -> Array[String]:
	var out: Array[String] = []
	for name in _catalogue():
		var kind_and_name: String = str(name)
		if not kind_and_name.begins_with("builtin/"):
			continue
		var bare := kind_and_name.substr(8)
		# Arity *and* type. `duplicate` refuses everything but a one-argument
		# list, because the two-argument cast-member form shares its name and
		# belongs to the host (§1.6) -- so an all-integer probe reported the one
		# builtin Piposh Dream's Fritz puzzle is built on as unbound.
		for probe_args in [[], [0], [0, 0], [0, 0, 0], [[]], [{}], [""], [[], 0]]:
			var handled: Array = []
			Builtins.call_builtin(bare, probe_args, handled)
			if not handled.is_empty():
				out.append(bare)
				break
	return out


## The override keys `sprite_state.effective` actually merges into the drawn
## sprite, plus the two the node routes elsewhere before it gets there.
func _consumed_keys() -> Array[String]:
	var out: Array[String] = ["cursor", "constraint", "puppet"]
	var text := FileAccess.get_file_as_string(SPRITE_STATE_SRC)
	var body := text.substr(maxi(text.find("func effective"), 0))
	# **`effective` and nothing after it.** The end anchor named a function three
	# further down, so the slice covered `release_auto_puppets` and `with_puppets`
	# as well -- and `with_puppets` keys the score's own record into the override
	# entry as `over["_score"]`, which this then reported as a sprite property the
	# engine binds and §19 does not record. A named anchor also rots the moment
	# somebody reorders the file; the next `static func` cannot.
	var after := body.find("\nstatic func ", 1)
	body = body.substr(0, after) if after > 0 else body
	var re := RegEx.new()
	# `has` **and** `get`. A key consulted with a default -- `over.get("visible",
	# 1)`, which is the hide every script in every title writes -- is merged just
	# as surely as one behind an `over.has`, and reading only the one shape
	# reported `the visible of sprite` as inert at 12,548 sites. That is this
	# file's own highest-severity verdict, produced against a property that works,
	# which is the one failure mode a gate has no defence against: the next
	# session spends its day on a bug that is not there, or learns to discount the
	# red.
	re.compile("over\\.(?:has|get)\\(\"([a-z_]+)\"")
	for hit in re.search_all(body):
		out.append(hit.get_string(1))
	# `membernum` and `castnum` are merged by a loop rather than by an `over.has`,
	# and reading only the one shape credited them to the score-record read below
	# -- which answers the same value and would have gone on answering it after the
	# merge was deleted.
	var loop := RegEx.new()
	loop.compile("for key in \\[([^\\]]*)\\]")
	var quoted := RegEx.new()
	quoted.compile("\"([a-z_]+)\"")
	for hit in loop.search_all(body):
		for name in quoted.search_all(hit.get_string(1)):
			out.append(name.get_string(1))
	# `loc` is written through the node's own position path, which `effective`
	# then reads back as `loch`/`locv`.
	for name in ["loch", "locv"]:
		if not out.has(name):
			out.append(name)
	return out


## Sprite properties `docs/LINGO_SURFACE.md` §4 says are writable, that this
## engine will accept a write for and store, and that nothing then reads.
##
## Deliberately derived from §4 rather than listed: the point is the difference
## between what the language offers and what the renderer consumes, and a
## hand-written list here would be the same claim this file exists to check.
func _override_only() -> Array[String]:
	var out: Array[String] = []
	for key in _catalogue():
		var name: String = str(key)
		if not name.begins_with("sprite/"):
			continue
		# §4's prose names the *command* `puppetSprite` while describing the
		# autopuppet rule. It is a builtin, audited as one, and it is not a sprite
		# property; picking it up here would put a row in §19 for a name that has
		# no such spelling.
		if name == "sprite/puppetsprite":
			continue
		out.append(name.substr(7))
	return out


# ================================================================== the corpus
#
# Every container under every root in `games/`, read as the authored Lingo in
# the `CASt` member records -- the same path `tools/lib/key_sites.gd` takes, and
# for the same reason: `reference/lingo/` is one title out of six, and it is a
# decompilation rather than what the author typed.


## `only` is the `--name` filter. When it is set, the sweep also keeps the first
## few *lines* each match came from: a gap with a count is something to
## prioritise, and a gap with a site is something to fix this evening.
func _corpus(only: String = "") -> Dictionary:
	var out := {
		"roots": 0, "containers": 0, "total": 0,
		"calls": {}, "props": {}, "of": {}, "dot": {}, "sites": [],
	}
	var dir := DirAccess.open(GAMES_DIR)
	if dir == null:
		return out

	# One pass of six regexes per script, rather than one regex per audited name
	# per script: the second is 3M searches and this is 90k.
	var comment := RegEx.new()
	comment.compile("--[^\\n]*")
	var call := RegEx.new()
	call.compile("([a-z_][a-z0-9_]*)\\s*\\(")
	var command := RegEx.new()
	command.compile("(?m)(?:^|\\bthen\\s+|\\belse\\s+)[ \\t]*([a-z_][a-z0-9_]*)\\b")
	var the := RegEx.new()
	the.compile("\\bthe\\s+([a-z_][a-z0-9_]*)\\b")
	var qualified := RegEx.new()
	qualified.compile(
		"\\bthe\\s+([a-z_][a-z0-9_]*)\\s+of\\s+(sprite|member|field|window|sound|cast|castlib)\\b")
	# The dot spelling, **with its owner**. §4 records this game using
	# `sprite(N).locH` far more often than `the locH of sprite N`, so a walker that
	# ignored it would under-report every sprite property -- and one that read the
	# property without the word in front of it over-reports every one of them,
	# which is worse: the first pass of this file credited `member("x").name` to
	# `the name of sprite` and reported 518 sites for a property with none.
	var dotted := RegEx.new()
	dotted.compile(
		"\\b(sprite|member|cast|castlib|field|window|sound)\\s*\\((?:[^()]|\\([^()]*\\))*\\)"
		+ "\\s*\\.\\s*([a-z_][a-z0-9_]*)\\b")
	var verb := RegEx.new()
	verb.compile("\\bsound\\s+(playfile|stop|close|fadein|fadeout)\\b")

	for sub in dir.get_directories():
		var paths := Paths.new()
		paths.root = GAMES_DIR.path_join(sub)
		var seen_any := false
		for relative in paths.containers():
			var path := paths.resolve(str(relative))
			if path == "":
				continue
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var cast := Cast.new()
			if not cast.open(f):
				f.close()
				continue
			seen_any = true
			out["containers"] = int(out["containers"]) + 1
			for number in cast.member_numbers():
				var m: Dictionary = cast.member(number)
				var source := str(m.get("source", ""))
				if source.strip_edges() == "":
					continue
				# Comments first. `docs/` prose quoted inside a `--` comment is not
				# a call site, and this game's scripts are heavily commented.
				var text := comment.sub(source.to_lower(), "", true)
				_tally(out, "calls", call, text)
				_tally(out, "calls", command, text)
				_tally(out, "props", the, text)
				for hit in dotted.search_all(text):
					_bump(out["dot"], "%s/%s" % [_owner(hit.get_string(1)), hit.get_string(2)])
					out["total"] = int(out["total"]) + 1
				for hit in qualified.search_all(text):
					_bump(out["of"], "%s/%s" % [_owner(hit.get_string(2)), hit.get_string(1)])
				for hit in verb.search_all(text):
					_bump(out["calls"], "sound")
				if only != "" and text.contains(only):
					var sites: Array = out["sites"]
					for line in text.split("\n"):
						if sites.size() >= 24:
							break
						if str(line).contains(only):
							sites.append("%s %s #%d | %s"
								% [sub, relative, number, str(line).strip_edges()])
			f.close()
		if seen_any:
			out["roots"] = int(out["roots"]) + 1
	return out


func _tally(out: Dictionary, bucket: String, re: RegEx, text: String) -> void:
	for hit in re.search_all(text):
		_bump(out[bucket], hit.get_string(1))
		out["total"] = int(out["total"]) + 1


static func _bump(into: Dictionary, key: String) -> void:
	into[key] = int(into.get(key, 0)) + 1


## Which audited kind a qualifier names. `field "x"` is a text member reached by
## a shorter spelling (§5.1), so its properties are member properties; `castLib`
## is its own entity and keeps its own bucket.
static func _owner(word: String) -> String:
	match word:
		"field":
			return "member"
		"castlib":
			return "cast"
	return word


## How many sites in the corpus reach a name, by kind.
##
## A builtin is counted in call and command position; a system property as
## `the X`; a sprite or member property as `the X of sprite` plus the dot
## spelling, which §4 records this game using far more often -- a walker that saw
## only `the X of sprite N` would under-report every entry.
func _uses(kind: String, name: String, corpus: Dictionary) -> int:
	match kind:
		"builtin":
			return int((corpus["calls"] as Dictionary).get(name, 0))
		"system":
			# `the X of sprite N` is not a read of the system property `X`, and
			# `the width of sprite` versus `the width of member` is exactly the
			# collision this subtracts out.
			var all := int((corpus["props"] as Dictionary).get(name, 0))
			var of_something := 0
			for owner in ["sprite", "member", "window", "sound", "cast"]:
				of_something += int((corpus["of"] as Dictionary).get("%s/%s" % [owner, name], 0))
			return maxi(all - of_something, 0)
		"sprite", "member", "window", "sound", "cast":
			return int((corpus["of"] as Dictionary).get("%s/%s" % [kind, name], 0)) \
				+ int((corpus["dot"] as Dictionary).get("%s/%s" % [kind, name], 0))
	return 0


# ================================================================== the report


func _rows(claims: Dictionary, catalogue: Dictionary, bound: Dictionary,
		corpus: Dictionary) -> Array:
	var keys: Dictionary = {}
	for key in claims:
		keys[key] = true
	for key in (bound["state"] as Dictionary):
		keys[key] = true
	for key in catalogue:
		keys[key] = true

	var out: Array = []
	for key in keys:
		var parts := str(key).split("/", true, 1)
		var kind: String = parts[0]
		var name: String = parts[1]
		var claim: Dictionary = claims.get(key, {})
		var observed: String = str((bound["state"] as Dictionary).get(key, ABSENT))
		out.append({
			"name": name,
			"kind": kind,
			"recorded": claims.has(key),
			"claimed": str(claim.get("state", "")),
			"observed": observed,
			"detail": str((bound["detail"] as Dictionary).get(key, "")),
			"note": str(claim.get("note", "")),
			"uses": _uses(kind, name, corpus),
		})
	out.sort_custom(func(a, b):
		if int(a["uses"]) != int(b["uses"]):
			return int(a["uses"]) > int(b["uses"])
		if str(a["kind"]) != str(b["kind"]):
			return str(a["kind"]) < str(b["kind"])
		return str(a["name"]) < str(b["name"]))
	return out


func _print_table(rows: Array, survey: bool) -> void:
	print("")
	print("%-24s %-8s %-9s %-9s %6s  %s"
		% ["name", "kind", "claimed", "engine", "uses", "where"])
	print("%s" % "-".repeat(96))
	var shown := 0
	for row in rows:
		var r: Dictionary = row
		var claimed: String = str(r["claimed"]) if bool(r["recorded"]) else "--"
		var flag := " "
		if bool(r["recorded"]) and claimed != str(r["observed"]):
			flag = "!"
		if claimed == LIVE and str(r["observed"]) == INERT:
			flag = "#"
		if not survey and flag == " " and int(r["uses"]) == 0 \
				and str(r["observed"]) == ABSENT:
			# Unrecorded, unused and unbound: catalogue names no title has
			# reached and nothing claims. Printed in survey mode, where the point
			# is the whole catalogue, and folded away in the gate, where the point
			# is the disagreements.
			continue
		shown += 1
		print("%s%-23s %-8s %-9s %-9s %6d  %s" % [
			flag, r["name"], r["kind"], claimed, r["observed"], int(r["uses"]),
			r["detail"] if str(r["detail"]) != "" else r["note"]])
	print("%s" % "-".repeat(96))
	print("%d rows shown of %d.  ! = the document and the engine disagree." % [shown, rows.size()])
	print("# = claimed, bound and inert -- the `intersects` shape, and the worst of them.")
	print("")


## The number §19 pins the reachable gaps at, read out of the sentence that
## carries it. -1 when the sentence is missing, which fails the check rather than
## passing an unpinned run.
func _recorded_gap_count() -> int:
	var re := RegEx.new()
	re.compile("Reachable gaps recorded here: (\\d+)")
	var hit := re.search(FileAccess.get_file_as_string(DOC))
	return int(hit.get_string(1)) if hit != null else -1


## The deliverable, printed rather than left for a reader to sort: every gap a
## movie can reach, worst first. `AGENTS.md` is explicit that a measured zero is a
## reason to build something *last* and never a reason to skip it, so the
## unreached ones are still rows in §19 -- they are just not this list.
func _print_priority(gaps: Array) -> void:
	print("")
	print("reachable gaps, worst first -- claimed-and-inert outranks absent,")
	print("because an absent name is at least reported and an inert one is not:")
	for row in gaps:
		var r: Dictionary = row
		print("  %6d  %-8s %-24s %-7s  %s" % [
			int(r["uses"]), r["kind"], r["name"], r["observed"], r["detail"]])
	print("")


## §19's rows, printed ready to paste. Survey mode only: this is how the table is
## authored and re-authored, so that the document's claims stay something a
## machine can read rather than something a session has to re-derive.
func _print_seed(rows: Array) -> void:
	print("---- §19 seed ----")
	for row in rows:
		var r: Dictionary = row
		if str(r["observed"]) == ABSENT and int(r["uses"]) == 0:
			# Nothing to record: the engine does not bind it and no title asks for
			# it. §9.2 is where the catalogue's unused remainder is listed, and a
			# row per name here would be 275 of them.
			continue
		print("| `%s` | %s | %s | %s%s |" % [
			r["name"], r["kind"], r["observed"],
			("%d sites" % int(r["uses"])) if int(r["uses"]) > 0 else "0 sites",
			("; " + str(r["detail"])) if str(r["detail"]) != "" else ""])
	print("---- end ----")
