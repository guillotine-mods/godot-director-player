extends RefCounted
## What the run learned about its own Lingo, printed on `L` and at exit.
##
## This exists because **"no sound" has at least four distinct causes and only
## this tells them apart**: no handler was dispatched, none was found, none
## reached a builtin, or a builtin was reached and did nothing. From the outside
## all four are silence. The same is true of "the pacing feels wrong", which
## separates into "the score asked for a hold and nothing took it" and "the score
## asked for nothing at all", and of "the cursor is broken", which is usually
## "this room asks for no cursor".
##
## Every line here was added after a session was lost to one of those ambiguities.

static func emit(host) -> void:
	# A window's report is the same report for a different movie, and the two
	# would otherwise be indistinguishable in a log where a window opened, ran and
	# was forgotten in the middle of the stage's run.
	if host._window_key != "":
		print("--- window %s (%s) ---" % [host._window_key, host.movie_name()])
	print("lingo dispatched : %s" % JSON.stringify(host._sent))
	print("lingo ran        : %s" % JSON.stringify(host._ran))
	if host._host != null:
		print("builtins reached : %s" % JSON.stringify(host._host.reached))
		print("builtins unbound : %s" % JSON.stringify(host._host.unbound))
	print("ccl cast list  : %s" % str(host._ccl))
	print("film loops     : %s" % JSON.stringify(host._loop_stats))
	# "The pacing feels wrong" has to be separable into "the score asked for a
	# hold and nothing took it" and "the score asked for nothing". Only five
	# frames in this corpus carry a transition and thirty-six carry a delay, so a
	# run that reports zero of each is usually telling the truth about the movie.
	print("clock          : %s, %d transition(s) played" % [
		host._clock.status(), host._transitions_played,
	])
	# Whether a room set any cursor at all is a question that kept being answered
	# by looking at the screen and seeing an arrow, which cannot distinguish "the
	# cursor code is broken" from "this room asks for no cursor". Most of them ask
	# for none: the game sets `the cursor of sprite` on inventory items and in a
	# handful of rooms, so an arrow is usually correct.
	print("cursors        : %d channel(s) %s, global %s" % [
		host._channel_cursors.size(), str(host._channel_cursors.keys()), str(host._global_cursor)
	])
	if not host._traced.is_empty():
		print("sound trace (last %d):" % host._traced.size())
		for line in host._traced:
			print("   %s" % line)
	if host._score != null:
		var kinds: Dictionary = {}
		var resolved := 0
		var unresolved: Array = []
		for interval in host._score.intervals():
			host._tally(kinds, str(interval["kind"]))
			var member := int(interval["script_member"])
			if host._script_for_member(member).is_empty():
				if unresolved.size() < 8 and not unresolved.has(member):
					unresolved.append(member)
			else:
				resolved += 1
		print("score intervals  : %s" % JSON.stringify(kinds))
		print("  scripts found  : %d of %d" % [resolved, host._score.intervals().size()])
		if not unresolved.is_empty():
			print("  unresolved mbr : %s" % str(unresolved))
		var fs: Dictionary = host._frame_script(host._index)
		var handlers: Array = []
		for handler in fs.get("handlers", []):
			handlers.append(str((handler as Dictionary).get("name", "")))
		print("  frame %d script: %s  handlers: %s" % [
			host._index, str(fs.get("script", "NONE")), ", ".join(handlers),
		])
	if host._interpreter != null:
		var names: PackedStringArray = host._interpreter.movie_handler_names()
		print("movie handlers   : %d  %s" % [names.size(), ", ".join(names)])
		var errors: Array = host._interpreter.errors
		if not errors.is_empty():
			print("interpreter errors (%d):" % errors.size())
			for line in errors.slice(0, 8):
				print("   %s" % line)
		# **The diagnostics sink was read by six harnesses and by nothing here**,
		# which is how `bugs.md` 123 stayed silent in both directions: a call that
		# resolved nowhere answered 0, and a 0 is indistinguishable from a handler
		# that returned 0. This is the one category worth a line of its own,
		# because it is not a binding the port owes -- it is a place where
		# Director stops the whole dispatch ("Handler not defined", `LC::call` ->
		# `lingoError` -> `_abort`) and this port runs on. `builtins unbound`
		# above is the other bucket and stays a work list; see
		# `lingo/lingo_reference_names.gd` for the split.
		var undefined: PackedStringArray = host._interpreter.diagnostics \
			.names_in(LingoDiagnostics.UNDEFINED_HANDLER)
		if not undefined.is_empty():
			print("undefined handlers: %d  %s  (Director aborts the dispatch here)"
				% [undefined.size(), ", ".join(undefined)])
