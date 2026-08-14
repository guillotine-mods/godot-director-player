extends RefCounted
## Pass/fail reporting for the tools, with the guard that a dead check fails.
##
##   const Harness := preload("res://tools/lib/harness.gd")
##   var h := Harness.new()
##   h.begin("<movie> @<room>")
##   h.check("what the player should see", ok, detail)
##   h.complete("<movie> @<room>")
##   quit(h.finish("what the whole run asserted"))
##
## `begin`/`complete` is the whole reason this file exists. A GDScript runtime
## error aborts the handler it happens in and returns the type's zero value, so a
## harness that accumulates `failures += _check(...)` scores an *aborted* check as
## a pass: `verify_film_loops.gd` once printed "all 3 draw the expected members"
## while every one of the three had died on an error. Declaring the case before
## running it means an aborted case is still open at `finish` and reports FAIL,
## because the only thing that can close it is its own last line.
##
## Title-agnostic on purpose. Nothing here may know what game is being tested.

var _fails := 0
var _checks := 0
var _order: Array[String] = []
var _closed: Dictionary = {}


## Declare a case before running it. Anything still open at `finish` is a failure.
func begin(case_name: String) -> void:
	if not _closed.has(case_name):
		_order.append(case_name)
	_closed[case_name] = false


## Close a case. Call it as the case's own last line, never early.
func complete(case_name: String) -> void:
	if not _closed.has(case_name):
		_order.append(case_name)
	_closed[case_name] = true


## Returns `ok`, so a caller can branch on it without repeating the condition.
func check(name: String, ok: bool, detail: String = "") -> bool:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])
	return ok


func failures() -> int:
	return _fails


## Prints the verdict and returns the exit code. Pass it straight to `quit()`.
##
## Zero checks is a failure, not a pass. `begin`/`complete` only catches an abort
## that happened *after* a case was declared; a runtime error in `_init`, in the
## argument parsing, or in the first `await` before the first `begin` leaves
## `_order` empty and `_checks` at 0, and this printed `PASS (0 checks, 0 failed)`
## and returned 0. The gate reads the last `PASS`/`FAIL` line, so that run went
## green having asserted nothing -- the same shape as the vacuous scrape in
## `docs/bugs-closed.md` 106, and indistinguishable from a real pass in the table.
## All 130 harness callers make at least one `check`, so a run that made none did
## not reach its own assertions.
func finish(summary: String = "") -> int:
	if _checks == 0:
		_fails += 1
		print("FAIL  the run asserted nothing: it died before its first check (see the errors above)")
	for case_name in _order:
		if not bool(_closed[case_name]):
			_fails += 1
			print("FAIL  %s: the case did not complete (see the errors above)" % case_name)
	print("")
	var verdict := "PASS" if _fails == 0 else "FAIL"
	var counted := "%d checks, %d failed" % [_checks, _fails]
	if summary == "":
		print("%s (%s)" % [verdict, counted])
	else:
		print("%s  %s (%s)" % [verdict, summary, counted])
	return 1 if _fails > 0 else 0
