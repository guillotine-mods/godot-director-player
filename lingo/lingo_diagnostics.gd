class_name LingoDiagnostics
extends RefCounted
## Where the runtime records a name it could not bind.
##
## One entry per name and location; a repeat bumps a count instead of
## allocating, so a handler that reads the same unbound name on every frame
## costs one entry and not thousands. Nothing is allocated until something is
## actually reported, so carrying the sink through a clean session is free.

## Categories, as strings rather than an enum so the emitted set survives a
## round trip through JSON and stays readable in a diff.
const SPRITE_PROP := "sprite_prop"
const MOVIE_PROP := "movie_prop"
const MEMBER_PROP := "member_prop"
const BUILTIN := "builtin"
const EVENT := "event"
## A name that resolved nowhere: not a local, not a global, not a handler and
## not a builtin.
const UNBOUND_NAME := "unbound_name"
## A variable the script itself owns but has not assigned yet, because the
## branch that would have assigned it was not taken. That is the game's own
## business, not a missing binding, and mixing the two buries a real gap list
## under hundreds of uninitialised loop counters.
const UNSET_VARIABLE := "unset_variable"

## A runaway script must not turn the sink into the leak it exists to find.
const MAX_ENTRIES := 2000

## identity -> {category, name, script, handler, line, count}
var _entries: Dictionary = {}
## How many entries the cap refused, so a truncated set says so.
var dropped: int = 0


func report(category: String, name: String, script: String, handler: String,
		line: int = 0) -> void:
	var key := identity_of(category, name, script, handler, line)
	var seen: Variant = _entries.get(key, null)
	if seen != null:
		(seen as Dictionary)["count"] = int((seen as Dictionary)["count"]) + 1
		return
	if _entries.size() >= MAX_ENTRIES:
		dropped += 1
		return
	_entries[key] = {
		"category": category,
		"name": name,
		"script": script,
		"handler": handler,
		"line": line,
		"count": 1,
	}


static func identity_of(category: String, name: String, script: String, handler: String,
		line: int) -> String:
	return "%s|%s|%s|%s|%d" % [category, name, script, handler, line]


static func identity(entry: Dictionary) -> String:
	## The same key from an entry read back off disk, so a recorded set diffs
	## against a live one.
	return identity_of(
		str(entry.get("category", "")), str(entry.get("name", "")),
		str(entry.get("script", "")), str(entry.get("handler", "")),
		int(entry.get("line", 0)))


func is_empty() -> bool:
	return _entries.is_empty()


func count() -> int:
	return _entries.size()


func occurrences() -> int:
	var total := 0
	for key in _entries:
		total += int((_entries[key] as Dictionary)["count"])
	return total


func clear() -> void:
	_entries.clear()
	dropped = 0


func entries(category: String = "") -> Array:
	## Sorted by identity, so two runs that reached the same state emit the same
	## bytes and a diff shows only what moved.
	var keys: Array = _entries.keys()
	keys.sort()
	var out: Array = []
	for key in keys:
		var entry: Dictionary = _entries[key]
		if category != "" and str(entry["category"]) != category:
			continue
		out.append(entry.duplicate())
	return out


func names_in(category: String) -> PackedStringArray:
	## The distinct names in one category, which is the shape a gap list wants.
	var seen: Dictionary = {}
	for key in _entries:
		var entry: Dictionary = _entries[key]
		if str(entry["category"]) == category:
			seen[str(entry["name"])] = true
	var out := PackedStringArray()
	for name in seen:
		out.append(str(name))
	out.sort()
	return out


func to_json() -> String:
	return JSON.stringify({"entries": entries(), "dropped": dropped}, "  ")


static func diff(before: Array, after: Array) -> Dictionary:
	## What a change added and removed between two runs of the same session.
	## Occurrence counts move with ordinary play, so identity alone decides
	## membership and a count that merely rose is not a difference.
	var was: Dictionary = {}
	for entry in before:
		was[identity(entry)] = entry
	var added: Array = []
	var kept: Dictionary = {}
	for entry in after:
		var key := identity(entry)
		kept[key] = true
		if not was.has(key):
			added.append(entry)
	var removed: Array = []
	for key in was:
		if not kept.has(key):
			removed.append(was[key])
	return {"added": added, "removed": removed}
