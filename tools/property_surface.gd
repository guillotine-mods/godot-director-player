extends SceneTree
## Does this engine *say so* when a property write or read goes nowhere?
##
##   godot --headless --path . --script tools/property_surface.gd
##   godot --headless --path . --script tools/property_surface.gd -- --survey
##   godot --headless --path . --script tools/property_surface.gd -- --survey --kind member
##
## `tools/lingo_surface_audit.gd` beside this asks whether a name is *bound*, by
## reading the sources. This asks the question one step further along and by
## observation instead: a movie writes a property, and does anything at all
## record that the write went nowhere?
##
## For five years the answer was no, and it is the single most expensive blind
## spot this port has had. `LingoDiagnostics` has declared `SPRITE_PROP`,
## `MOVIE_PROP` and `MEMBER_PROP` since the day it was written. An unbound
## *builtin* reports through `lingo_interpreter.gd:_host_call` and lands in the
## diagnostics with a script, a handler and a line; a bound property setter that
## stores a name nothing reads returns cleanly, reads back the value it was
## given, and says nothing. So builtin gaps were found by the gate and property
## gaps were found by players — `moveableSprite` (no drag at all in DAY1),
## `editableText`, `the constraint of sprite`, `the member of sprite`, `flipH`,
## and most recently `ink`, `blend`, `foreColor` and `backColor`, which were
## stored on write and merged by nobody while the one diagnostic meant to catch
## them was excusing two of them by name.
##
## ## The three checks, and why the third is the one that matters
##
## **It fires.** Each of the three categories is driven with a property name this
## engine does not bind, in both directions, and has to report.
##
## **It stays quiet.** Each category is driven with a name the engine *does*
## bind, and must not report. A report that fires for everything is exactly as
## useless as one that fires for nothing, and it is the cheaper failure to ship:
## the entries pile up, nobody reads them, and the one real name is in there
## somewhere. `tools/puppet_persists.gd` was green for months while asserting
## half its rule, which is the same lesson from the other side.
##
## **Nothing is bound inert.** The first two checks can only see a name with *no*
## arm. The shape that actually shipped five times is a name **with** an arm,
## whose effect reaches a store nothing reads — and no runtime probe can see that,
## because the write succeeds and the read agrees. So it is derived here from the
## code that consumes it: every write arm is traced to a consumer, and an arm
## whose effect stops inside the setter fails this harness. That is what would go
## red the day someone binds `the buttonStyle` to `button_style = value` with no
## reader, or aliases a sprite property onto a key `sprite_state.effective` does
## not merge.
##
## Title-agnostic: every name is driven against whichever movie the config boots,
## and nothing here knows a room, a channel or a member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Diagnostics := preload("res://lingo/lingo_diagnostics.gd")
const SpriteProps := preload("res://scenes/preview/sprite_props.gd")
const SpriteState := preload("res://scenes/preview/sprite_state.gd")
const LingoValue := preload("res://lingo/lingo_value.gd")

const HOST_SRC := "res://scenes/preview_lingo_host.gd"
const PREVIEW_SRC := "res://scenes/director_preview.gd"
const REF_THE := "res://reference/scummvm/lingo-the.cpp"

## Names no Director release has and no title could be written against, so a
## report for one is the harness's own signal and never a corpus finding.
##
## **Two of them, one per direction, and that is the whole check working.** The
## first version used one name for both and let the read assertion pass if the
## name was in the set "or already there from the write" — so the write probe put
## it there, the read assertion was satisfied by the write's own entry, and the
## read half of both `MOVIE_PROP` and `MEMBER_PROP` could be deleted outright
## with this harness still green. Caught by mutating the engine and watching for
## a red that never came, which is the only way to find it: a check that cannot
## fail looks exactly like a check that passes.
const NOWHERE_WRITE := "harnessUnboundProbeW"
const NOWHERE_READ := "harnessUnboundProbeR"

var _preview: Node = null
var _host = null
var _interp = null


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	_preview = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(_preview)
	await process_frame
	await process_frame
	_host = _preview.get("_host")
	_interp = _preview.get("_interpreter")

	h.begin("the harness has a movie, a host and an interpreter")
	h.check("the Lingo host is attached", _host != null)
	h.check("the interpreter is attached", _interp != null)
	h.check("the preview booted a cast table", _preview.get("_table") != null)
	h.complete("the harness has a movie, a host and an interpreter")
	if _host == null or _interp == null or _preview.get("_table") == null:
		quit(h.finish("the property surface reports what it drops"))
		return

	if Args.flag(args, "survey"):
		_survey(Args.text(args, "kind", ""))
		_preview.queue_free()
		await process_frame
		quit(0)
		return

	if args.has("play"):
		await _play(Args.number(args, "play", 300))
		_preview.queue_free()
		await process_frame
		quit(0)
		return

	_fires(h)
	_stays_quiet(h)
	_nothing_is_bound_inert(h)

	_preview.queue_free()
	await process_frame
	quit(h.finish("the property surface reports what it drops"))


# ------------------------------------------------------- the reports fire


## A write and a read of a name this engine does not bind, per category.
##
## Both directions, because they fail differently and only one of them was ever
## covered. `lingo_set_member_prop` has reported its fall-through since the
## `hilite` fix; `members.gd:read_prop` answered **0** for every name it had no
## arm for, which is worse than VOID and was completely silent — 0 is a plausible
## value for most of the fifty properties above it, so `the frameRate of member N`
## and `the width of member N` came back as two integers a script cannot tell
## apart.
func _fires(h) -> void:
	h.begin("a property nothing consumes is reported, in both directions")
	var member := _some_member()
	h.check("the movie has a member to address (%d)" % member, member > 0)
	for spec in [
		[Diagnostics.SPRITE_PROP, "sprite",
			"set the %s of sprite 1 to 1" % NOWHERE_WRITE,
			"the %s of sprite 1" % NOWHERE_READ],
		[Diagnostics.MOVIE_PROP, "movie",
			"set the %s to 1" % NOWHERE_WRITE, "the %s" % NOWHERE_READ],
		[Diagnostics.MEMBER_PROP, "member",
			"set the %s of member %d to 1" % [NOWHERE_WRITE, member],
			"the %s of member %d" % [NOWHERE_READ, member]],
	]:
		var row: Array = spec
		var category := str(row[0])
		h.check(
			"`%s` reports %s" % [str(row[2]), category],
			not _names(category).has(NOWHERE_WRITE.to_lower()) and _reports(
				category, str(row[2]), NOWHERE_WRITE),
			"a write that returns cleanly and moves nothing is the shape that "
			+ "shipped as moveableSprite, editableText, constraint, the member "
			+ "of sprite and flipH")
		h.check(
			"`the %s ...` reports %s on the read as well" % [NOWHERE_READ, category],
			not _names(category).has(NOWHERE_READ.to_lower()) and _reports(
				category, "put " + str(row[3]), NOWHERE_READ),
			"the read half answers a plausible value rather than nothing, which "
			+ "is why it hides better than the write half -- and it is the half "
			+ "that has to be probed under its own name, or the write's entry "
			+ "answers for it")
	h.complete("a property nothing consumes is reported, in both directions")


## The other half of the rule, and the half a harness usually forgets.
##
## Every one of these is a property this engine really does carry to something a
## movie can see, so a report here means the check above is passing on noise. The
## sprite entry is deliberately `the moveableSprite of sprite`: it is the alias
## the whole seam was built for, and a derivation that lost the alias table would
## report Director's own spelling as unconsumed while the score key beside it
## looked fine.
func _stays_quiet(h) -> void:
	h.begin("a property that is consumed is not reported")
	var member := _some_member()
	for spec in [
		[Diagnostics.SPRITE_PROP, "set the moveableSprite of sprite 1 to 1"],
		[Diagnostics.SPRITE_PROP, "set the locH of sprite 1 to 10"],
		[Diagnostics.SPRITE_PROP, "set the flipH of sprite 1 to 1"],
		[Diagnostics.SPRITE_PROP, "set the constraint of sprite 1 to 0"],
		[Diagnostics.MOVIE_PROP, "set the itemDelimiter to \",\""],
		[Diagnostics.MOVIE_PROP, "set the timer to 0"],
		[Diagnostics.MOVIE_PROP, "put the frame"],
		[Diagnostics.MOVIE_PROP, "put the lastFrame"],
		[Diagnostics.MEMBER_PROP, "put the name of member %d" % member],
		[Diagnostics.MEMBER_PROP, "put the width of member %d" % member],
		[Diagnostics.MEMBER_PROP, "set the text of member %d to \"x\"" % member],
	]:
		var row: Array = spec
		var category := str(row[0])
		var before := _names(category)
		_run(str(row[1]))
		var after := _names(category)
		h.check(
			"`%s` reports nothing" % str(row[1]),
			after.size() == before.size(),
			"a report that fires for a bound name buries the one that matters; "
			+ "new: %s" % str(_added(before, after)))
	h.complete("a property that is consumed is not reported")
	_puppet_spelling(h)


## `the puppet of sprite N` and `puppetSprite N` are one flag, asserted against
## the model rather than against each other.
##
## The seventh instance of this port's oldest bug and the one this file found:
## the flag lives under `channel.gd:PUPPET_KEY`, which is `"_puppet"`, and the
## property spelling landed in the override entry under `"puppet"`. Both halves
## were wrong and both round-tripped -- `puppetSprite 5, TRUE` then `the puppet of
## sprite 5` answered 0, and `set the puppet of sprite 6 to 1` answered 1 with the
## channel not puppeted.
##
## Checked against `Channel.is_puppet` and not against a read-back, because a
## read-back is exactly what passed for the whole time this was broken.
func _puppet_spelling(h) -> void:
	h.begin("`the puppet of sprite` is the flag `puppetSprite` sets")
	var overrides: Dictionary = _preview.get("_overrides")
	_run("puppetSprite 5, TRUE")
	h.check("the builtin claims the channel",
		SpriteState.Channel.at(5, overrides).is_puppet())
	h.check("and the property sees it",
		LingoValue.to_int(_value("the puppet of sprite 5")) == 1,
		"the read fell through the channel table to EMPTY_CHANNEL's 0, so a movie "
		+ "that had just puppeted a channel was told it had not")
	_run("set the puppet of sprite 6 to 1")
	h.check("the property claims the channel",
		SpriteState.Channel.at(6, overrides).is_puppet(),
		"stored as `puppet` beside a flag called `_puppet`, read back as 1, and "
		+ "the channel was never frozen -- the `moveableSprite` shape exactly")
	h.check("and reads back through the property",
		LingoValue.to_int(_value("the puppet of sprite 6")) == 1,
		"the round-trip is the half that always passed; it is here so that a "
		+ "future fix cannot trade it for the half above")
	_run("puppetSprite 5, FALSE")
	_run("set the puppet of sprite 6 to 0")
	h.check("and both spellings release it again",
		not SpriteState.Channel.at(5, overrides).is_puppet()
			and not SpriteState.Channel.at(6, overrides).is_puppet())
	h.complete("`the puppet of sprite` is the flag `puppetSprite` sets")


# --------------------------------------------------- nothing is bound inert


## The check the two above cannot make, derived from the code that consumes each
## write rather than from a list beside it.
##
## Three seams, one rule: **a write arm must end somewhere outside its own
## setter.** Each is read out of the source, so a name added tomorrow is audited
## tomorrow and there is nothing to keep in step by hand. A hand-written list of
## "names that are really fine" is a suppression list, and it is precisely how
## `ink` and `blend` sat in `sprite_props.gd`'s predecessor being excused.
func _nothing_is_bound_inert(h) -> void:
	_sprite_aliases_land(h)
	_movie_writes_land(h)
	_member_writes_land(h)


## Every alias in `sprite_props.gd` has to name a key something merges.
##
## The alias table is the seam between Director's spelling and the score record's,
## and an alias pointing at a key `sprite_state.effective` does not merge is the
## original bug with the translation added: the write lands under a name at the
## far end of a chain that has no far end. `consumed()` is derived from `FIELDS`
## and `ROUTED`, so this is a closed loop over the two tables rather than a
## restatement of either.
func _sprite_aliases_land(h) -> void:
	h.begin("every sprite-property alias names a key something merges")
	var aliases: Dictionary = SpriteProps.ALIASES
	h.check("the alias table is non-trivial (%d entries)" % aliases.size(),
		aliases.size() >= 5,
		"an empty table would make every check below vacuous")
	for spelling in aliases:
		h.check(
			"`the %s of sprite` -> `%s` is consumed"
				% [str(spelling), str(aliases[spelling])],
			SpriteProps.consumed(str(spelling)),
			"the alias translated the name and nothing at the other end reads it")
	# And the identity direction: a key the model merges must be reachable by the
	# spelling a script writes. `moveable` is merged and `moveablesprite` is what
	# Lingo says, which is the pair the whole file exists for.
	for key in SpriteState.FIELDS:
		h.check(
			"the merged key `%s` answers `consumed`" % str(key),
			SpriteProps.consumed(str(key)),
			"`consumed` is derived from FIELDS, so this can only fail if the "
			+ "derivation stopped being a derivation")
	h.complete("every sprite-property alias names a key something merges")


## Every `set_system_prop` arm has to reach past the host.
##
## Four honest endings for a movie-property write, and the fourth is the trap:
##
##   `preview.…`            the engine sees it directly
##   `LingoValue.x = …`     a static on a module that consumes it
##   `LingoDiagnostics.x =` likewise
##   `field = …`            a host field, live **only** if something reads it
##
## The fourth is `beep_on`, `exit_lock`, `search_path`, the four primary-handler
## script names and `timer_reset_ms`, and each of them is genuinely read
## elsewhere today. The day one is not, this goes red — which is the whole point,
## because `tools/lingo_surface_audit.gd` scores any arm containing an `=` as
## `live` and cannot tell the two apart.
func _movie_writes_land(h) -> void:
	h.begin("every movie-property write reaches a consumer")
	_setter_checks(h, "the movie", HOST_SRC, "func set_system_prop",
		"func get_sprite_prop", 10)
	h.complete("every movie-property write reaches a consumer")


## The same rule for `set the X of member`.
##
## The three stores this port has are `_field_text` (drawn by `text_art.gd`),
## `_member_hilite` (substituted by `hilite.gd`) and `_member_style` (assembled by
## `text_art.style_for`), plus `TextFocus.set_member_editable`. A fourth store
## added with no painter behind it is the failure this looks for.
func _member_writes_land(h) -> void:
	h.begin("every member-property write reaches a consumer")
	_setter_checks(h, "a member", PREVIEW_SRC, "func lingo_set_member_prop",
		"## A member property nothing in this port consumes", 3)
	h.complete("every member-property write reaches a consumer")


## One setter, checked from both ends.
##
## **Per arm: does the arm do anything at all?** A body that is `pass`, empty, or
## a bare `return` accepts the statement and drops it, which is how
## `set_member_prop` spent its life. This is the same reading
## `tools/lingo_surface_audit.gd:_arm_is_inert` makes, applied to the one place
## the audit's own rule is weakest.
##
## **Per setter: does every store it writes have a reader?** This is the half the
## audit cannot make, because it scores *any* line containing `=` as live — so
## `button_style = value` with nothing reading `button_style` would be recorded
## `live` at 0 sites and nobody would ever look again.
##
## Deliberately **per setter and not per arm**. An earlier draft attributed each
## store to the arm that wrote it and called three properties inert that work:
## `the searchPaths` delegates to `the searchPath`'s arm rather than storing
## anything itself, and `the textSize of member` writes through a *nested* match
## whose inner labels split the outer arm's body in two, leaving `textsize` and
## `fontsize` holding the half that only declares locals. Both were the probe
## inspecting one stage of a chain, which is the mistake this whole file is about
## — so the question is asked of the setter, which has no stages.
func _setter_checks(h, what: String, path: String, from: String, to: String,
		floor_arms: int) -> void:
	var source := FileAccess.get_file_as_string(path)
	var arms := _match_arms(source, from, to)
	h.check("`%s`'s arms parse (%d)" % [from.substr(5), arms.size()],
		arms.size() >= floor_arms,
		"0 arms means the scan lost its anchors, not that the setter is clean")
	for name in arms:
		h.check(
			"`set the %s` of %s does something" % [str(name), what],
			not _arm_is_inert(str(arms[name])),
			"an arm that accepts the statement and drops it is the shape "
			+ "`set_member_prop` shipped as a bare `pass`")
	var start := source.find(from)
	var end := source.find(to, start)
	if start < 0:
		return
	var body := source.substr(start, (end - start) if end > start else -1)
	var outside := source.substr(0, start) \
		+ (source.substr(end) if end > start else "")
	var stores := _stores_of(body)
	h.check("`%s` writes something (%d store(s): %s)"
			% [from.substr(5), stores.size(), ", ".join(stores)],
		stores.size() > 0,
		"a setter that assigns nothing anywhere cannot be carrying a value")
	var elsewhere := outside + "\n" + _engine_source(path)
	for store in stores:
		h.check(
			"`%s` is read outside the setter" % store,
			_is_read_in(store, elsewhere),
			"the value stops here; that is `moveableSprite` with the name "
			+ "spelled right, and it reads as `live` to the surface audit")


## Everything a function assigns that is not one of its own locals.
##
## A local is declared with `var` inside the function, and it is not a store: the
## `over` dictionary that `set the textSize of member` builds is a local, and the
## store is the `_member_style[key] = over` that follows it. Dropping locals is
## what makes the reader test below mean something -- with them in, every setter
## fails on a name that never leaves the stack frame.
##
## `Module.field = x` counts as a store named `Module.field`, and the reader test
## finds its consumer in that module: `LingoDiagnostics.trace` is read by
## `lingo_interpreter.gd:_exec` and that is exactly the chain worth asserting.
func _stores_of(body: String) -> PackedStringArray:
	var locals: Dictionary = {}
	var declare := RegEx.new()
	declare.compile("^var\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var seen: Dictionary = {}
	var out := PackedStringArray()
	for raw in body.split("\n"):
		var line := str(raw).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		# `"keydownscript": key_down_script = text` -- a `match` arm whose body is
		# on the label's own line. Four of `set_system_prop`'s stores are written
		# that way, and a scan that only reads statements starting in column one
		# of their own line does not see any of them: the arms parsed, the stores
		# came back nine instead of thirteen, and the four that hide are the four
		# primary-handler script names. Same shape as the nested-match slip above,
		# and the same cure -- strip the label and read what follows it.
		line = _after_arm_label(line)
		if line == "":
			continue
		var declared := declare.search(line)
		if declared != null:
			locals[declared.get_string(1)] = true
			continue
		var name := _assigned_name(line)
		if name == "" or locals.has(name) or seen.has(name):
			continue
		seen[name] = true
		out.append(name)
	return out


## A statement with its `match` label removed, or the statement unchanged.
##
## `"a", "b": stmt` and `_: stmt` both become `stmt`; a label with nothing after
## it becomes "" and a line that is not a label is returned as it stands.
static func _after_arm_label(line: String) -> String:
	var re := RegEx.new()
	re.compile("^((\"[^\"]*\"\\s*,?\\s*)+|_\\s*):\\s*")
	var hit := re.search(line)
	if hit == null:
		return line
	return line.substr(hit.get_end()).strip_edges()


## The name a statement assigns to, or "".
##
## Written as a scan rather than as a regex because the subscript may nest, and
## a regex that stops at the first `]` gets the wrong answer on the two lines
## that matter most here:
##
##     _field_text[_field_key(int(where[0]), int(where[1]))] = LingoValue...
##
## which `\\[[^\\]]*\\]` reads as `_field_text[...where[0]` and then fails to see
## an assignment at all. Both member stores were invisible for exactly that, and
## the check passed over an empty set -- the failure `gate.sh` calls EMPTY.
static func _assigned_name(line: String) -> String:
	var head := RegEx.new()
	head.compile("^([A-Za-z_][A-Za-z0-9_.]*)")
	var hit := head.search(line)
	if hit == null:
		return ""
	var name := hit.get_string(1)
	var i := name.length()
	if i < line.length() and line[i] == "[":
		var depth := 0
		while i < line.length():
			if line[i] == "[":
				depth += 1
			elif line[i] == "]":
				depth -= 1
				if depth == 0:
					i += 1
					break
			i += 1
	var rest := line.substr(i).strip_edges()
	if not rest.begins_with("="):
		return ""
	if rest.begins_with("=="):
		return ""
	return name


## Every engine source but the one the setter lives in, so a store handed to a
## painter three modules away counts as read.
##
## The first version searched only the setter's own file and reported
## `_member_style` -- which `preview/text_art.gd:style_for` assembles every field
## style from -- as a value that stops at the setter. A consumer in another file
## is the *normal* shape here (`_field_text` is drawn by `text_art.gd`,
## `_member_hilite` substituted by `hilite.gd`, `search_path` resolved by the
## audio path), so a scan that cannot see across files reports the working case.
func _engine_source(exclude: String) -> String:
	var out := ""
	for dir in ["res://scenes", "res://scenes/preview", "res://lingo", "res://autoload"]:
		for file in DirAccess.get_files_at(dir):
			if not str(file).ends_with(".gd"):
				continue
			var path := "%s/%s" % [dir, file]
			if path == exclude:
				continue
			out += FileAccess.get_file_as_string(path) + "\n"
	return out


## Is this store read by anything but its own declaration and its own writes?
##
## `_member_style` is matched in `text_art.gd` and in `save_state.gd`;
## `beep_on` in the host's own `beep` arm. The two exclusions are the line that
## declares it and any line that only writes it again -- without them a field
## would be its own consumer and every check here would pass.
func _is_read_in(store: String, text: String) -> bool:
	var bare := store.get_slice(".", store.get_slice_count(".") - 1)
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		if line.begins_with("#") or not line.contains(bare):
			continue
		if line.begins_with("var %s" % bare) or line.begins_with("%s :=" % bare):
			continue
		var writes := RegEx.new()
		writes.compile("^%s\\s*(\\[[^\\]]*\\])?\\s*=[^=]" % bare)
		if writes.search(line) != null:
			continue
		return true
	return false


## An arm that accepts the statement and does nothing with it. The same two
## shapes `tools/lingo_surface_audit.gd` names, kept here rather than shared
## because that file's copy is `static` on a `SceneTree` script and reaching it
## would mean instantiating the audit.
static func _arm_is_inert(body: String) -> bool:
	var meat := ""
	for raw in body.split("\n"):
		var line := str(raw).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		meat += line + ";"
	if meat == "" or meat == "pass;":
		return true
	var re := RegEx.new()
	re.compile("^(return( (0|null|\\{\\}|\\[\\]|-1))?;)+$")
	return re.search(meat) != null


# --------------------------------------------------------------- the survey


## Every property name Director has, driven through this engine and sorted by
## what the engine said about it.
##
## The names come from `reference/scummvm/lingo-the.cpp` rather than from §19 or
## from the corpus, for `AGENTS.md`'s reason: both of those are bounded by what
## this port or this title already knows about, and the point of the exercise is
## the names nobody here has thought of. A survey, not a gate — it prints and
## asserts nothing.
func _survey(only_kind: String) -> void:
	var wanted := _reference_property_names()
	var found := {"sprite": {}, "movie": {}, "member": {}}
	var quiet := {"sprite": 0, "movie": 0, "member": 0}
	var member := _some_member()
	for entry in wanted:
		var pair: Array = entry
		var kind := str(pair[0])
		var name := str(pair[1])
		if only_kind != "" and only_kind != kind:
			continue
		var category := str({
			"sprite": Diagnostics.SPRITE_PROP, "movie": Diagnostics.MOVIE_PROP,
			"member": Diagnostics.MEMBER_PROP,
		}[kind])
		var read := ""
		var write := ""
		match kind:
			"sprite":
				read = "put the %s of sprite 1" % name
				write = "set the %s of sprite 1 to 1" % name
			"movie":
				read = "put the %s" % name
				write = "set the %s to 1" % name
			"member":
				read = "put the %s of member %d" % [name, member]
				write = "set the %s of member %d to 1" % [name, member]
		# **Read and write, told apart.** The first version drove both and printed
		# one verdict, which made `the frame`, `the mouseH` and `the clickOn` look
		# unbound: every one of them reads perfectly and every one of them is
		# read-only, so the *write* probe reported and the name landed in the gap
		# list. 120 of 143 movie properties came out "reported" that way, which is
		# a number so wrong it is at least obvious -- the quiet failure would have
		# been the other direction.
		_interp.diagnostics.clear()
		_run(read)
		var reported_read := _names(category).has(name)
		_interp.diagnostics.clear()
		_run(write)
		var reported_write := _names(category).has(name)
		if reported_read or reported_write:
			var how := "read+write" if reported_read and reported_write \
				else ("read" if reported_read else "write")
			(found[kind] as Dictionary)[name] = how
		else:
			quiet[kind] = int(quiet[kind]) + 1
	_interp.diagnostics.clear()
	print("")
	print("Director property names driven through this engine, from %s" % REF_THE)
	print("`read` means the engine answered VOID and said so; `write` means the")
	print("write fell off the end of the setter. **`write` alone is usually")
	print("correct** -- Director makes most of these read-only too, and this port")
	print("has no read-only list for `the X` to tell a refusal from an absence.")
	print("`read` and `read+write` are the rows worth reading.")
	for kind in ["sprite", "movie", "member"]:
		var names: Array = (found[kind] as Dictionary).keys()
		names.sort()
		var reads := 0
		for name in names:
			if str((found[kind] as Dictionary)[name]) != "write":
				reads += 1
		print("")
		print("-- %s: %d name(s) reported (%d of them on the read), %d answered both ways"
			% [kind, names.size(), reads, int(quiet[kind])])
		for name in names:
			print("     %-28s %s" % [str(name), str((found[kind] as Dictionary)[name])])


## `(kind, name)` for every property in the reference's own `the` tables.
##
## Only the three kinds this file is about. `window`, `sound`, `cast`, `chunk`,
## `menu` and `menuItem` have their own dispatch and their own rows in §19;
## driving them through the sprite or member path would report them all.
func _reference_property_names() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var src := FileAccess.get_file_as_string(REF_THE)
	# `{ kTheName, "name", hasId, version, isFunction },` -- a movie property is
	# the entity that takes no id.
	var entity_re := RegEx.new()
	entity_re.compile(
		"\\{\\s*kThe\\w+\\s*,\\s*\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*,"
		+ "\\s*(true|false)\\s*,\\s*(\\d+)\\s*,\\s*(true|false)")
	for hit in entity_re.search_all(src):
		if hit.get_string(2) == "true":
			continue
		var name := hit.get_string(1).to_lower()
		if seen.has("movie/" + name):
			continue
		seen["movie/" + name] = true
		out.append(["movie", name])
	# `{ kTheOwner, "name", kTheField, version },`
	var field_re := RegEx.new()
	field_re.compile(
		"\\{\\s*kThe(\\w+)\\s*,\\s*\"([A-Za-z_][A-Za-z0-9_]*)\"\\s*,"
		+ "\\s*kThe\\w+\\s*,\\s*(\\d+)\\s*\\}")
	for hit in field_re.search_all(src):
		var owner := hit.get_string(1).to_lower()
		var kind := ""
		if owner == "sprite":
			kind = "sprite"
		elif owner == "cast" or owner == "field":
			kind = "member"
		if kind == "":
			continue
		var name := hit.get_string(2).to_lower()
		if seen.has(kind + "/" + name):
			continue
		seen[kind + "/" + name] = true
		out.append([kind, name])
	return out


# ------------------------------------------------------------- what play finds


## Play the boot movie and print what the three reports caught.
##
## The other modes ask "would this report if it had to"; this asks what a real
## session actually reaches, which is the only one that can find a name nobody
## thought to look for. Real frames, not a synthetic tick loop -- `AGENTS.md` is
## explicit, and a soundBusy guard that never clears makes a movie look stuck
## rather than idle.
##
##   godot --headless --path . --script tools/property_surface.gd -- --play 600
##   ... -- --play 600 --root piposh-dream --boot fritz1.dir
##
## A survey, not a gate: it prints and asserts nothing, because what a movie
## reaches depends on where the playhead got to.
func _play(frames: int) -> void:
	for i in range(frames):
		await process_frame
	print("")
	print("what %d frames of play reported" % frames)
	for category in [Diagnostics.SPRITE_PROP, Diagnostics.MOVIE_PROP,
			Diagnostics.MEMBER_PROP]:
		var entries: Array = _interp.diagnostics.entries(category)
		print("")
		print("-- %s: %d name(s), %d entr(ies)"
			% [category, _names(category).size(), entries.size()])
		for entry in entries:
			var row: Dictionary = entry
			print("     %-28s %s:%s:%d  x%d" % [str(row["name"]), str(row["script"]),
				str(row["handler"]), int(row["line"]), int(row["count"])])


# ------------------------------------------------------------------ plumbing


## `_match_arms` from `tools/lingo_surface_audit.gd`, kept to the two shapes this
## file needs. Not shared with it: that tool reads the whole surface and this one
## reads two setters, and the anchors are the fragile part rather than the loop.
func _match_arms(source: String, from: String, to: String) -> Dictionary:
	var out: Dictionary = {}
	var start := source.find(from)
	if start < 0:
		return out
	var end := source.find(to, start)
	var body := source.substr(start, (end - start) if end > start else -1)
	var open: Array[String] = []
	var collected := ""
	var continuing := false
	for raw in body.split("\n"):
		var trimmed := str(raw).strip_edges()
		if _is_arm_label(trimmed):
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


static func _is_arm_label(line: String) -> bool:
	if not line.begins_with("\""):
		return false
	if not (line.ends_with(":") or line.ends_with("\\")):
		return false
	var re := RegEx.new()
	re.compile("^(\"[^\"]*\"\\s*,?\\s*)+(:|\\\\)$")
	return re.search(line) != null


static func _quoted(line: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("\"([^\"]+)\"")
	for hit in re.search_all(line):
		out.append(hit.get_string(1).to_lower())
	return out


## A member this movie really has, so the member checks address something rather
## than member 0. Title-agnostic: the first numbered member of library 1.
func _some_member() -> int:
	var table = _preview.get("_table")
	if table == null:
		return 0
	var cast = table.cast_for(1)
	if cast == null:
		return 0
	for number in cast.member_numbers():
		return int(number)
	return 0


## Run one statement and say whether it put `name` into `category`.
##
## The name is the assertion, not the set's size: a category that gained *an*
## entry may have gained somebody else's, and a probe that counts is satisfied by
## whatever the movie happened to do on the same frame.
func _reports(category: String, source: String, name: String) -> bool:
	_run(source)
	return _names(category).has(name.to_lower())


func _names(category: String) -> PackedStringArray:
	return _interp.diagnostics.names_in(category)


func _added(before: PackedStringArray, after: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for name in after:
		if not before.has(name):
			out.append(name)
	return out


func _run(source: String) -> void:
	var script := Compiler.new().compile_source(
		"on probe\n  %s\nend\n" % source, "PropertySurfaceProbe")
	if script.is_empty():
		push_warning("property_surface: `%s` did not compile" % source)
		return
	_interp.call_handler("probe", [], script)
	_interp.reset_steps()


func _value(expression: String) -> Variant:
	var script := Compiler.new().compile_source(
		"on probe\n  return %s\nend\n" % expression, "PropertySurfaceProbe")
	if script.is_empty():
		return null
	var out: Variant = _interp.call_handler("probe", [], script)
	_interp.reset_steps()
	return out
