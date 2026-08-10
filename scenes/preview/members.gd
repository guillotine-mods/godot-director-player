extends RefCounted
## Which cast member a Lingo reference names.
##
## **The library is part of the answer, not a hint.** Member numbers are per
## cast, so `member(64, "island2")` and member 64 of the movie's own cast are
## different members that happen to share a number, and resolving in the wrong
## one returns a stranger rather than nothing -- which is silence, not an error.
##
## `searchfunk` in MASTER is what that cost. It does
## `myname = member(the memberNum of sprite the clickOn, "island2").name` and
## then matches that name against a table to decide what a click on the scenery
## reveals. Resolving in library 1 gave it the name of an unrelated member, no
## line ever matched, and the handler returned having done nothing. Every "I
## clicked the thing and nothing happened" of that shape is this.
##
## Resolution goes through the shared cast table, whose internal cast is opened
## once and cached, rather than a fresh `Cast` per call: `number_of` builds its
## name map by parsing every member in the library, so a new instance each time
## re-reads the `CAS*` chunk and every `CASt` record behind it. Measured over 250
## steps of MAP, where the frame script performs 24 name lookups per exitFrame:
## 125-144 ms before, 65-81 ms after, over three runs each.

## For `the lineCount of member`, which is `count(the text of member, #line)` by
## another spelling and must not be a second implementation of the line rule --
## Director drops a trailing empty line and `LingoValue.count_of` is where that
## is written down. Preloaded rather than reached by `class_name`, for the reason
## `lingo_interpreter.gd` records at its own `preload`.
const LingoValue := preload("res://lingo/lingo_value.gd")
## The one place a field's style is assembled -- the member's authored run with
## whatever Lingo has written over it. Read through rather than around, or `set
## the textSize of member` would read back the authored size and the write would
## be a lie the caller cannot detect.
const TextArt := preload("res://scenes/preview/text_art.gd")
## The digital-video and sound property surface, which is one surface in Director
## and is one module here. Read through rather than duplicated: `the duration`,
## `the mediaReady` and the nine media names below all consult the same decoded
## facts, so a member cannot answer a duration one caller can see and another
## cannot.
const Media := preload("res://scenes/preview/media.gd")
const Palette := preload("res://director/director_palette.gd")


## How far apart two libraries sit when a `(library, slot)` pair is carried as
## one integer.
##
## `the castNum of sprite` has to survive being handed straight back to
## `member()`, and a bare member number cannot: numbers are per library, so the
## library has to travel with it. This port packs rather than reproducing
## Director's own encoding, which it is free to do because **every castNum site
## in the corpus produces and consumes the integer inside a single expression**
## and none stores, compares or does arithmetic on it. Measured across all six
## roots: five titles have the read idiom only, in one shape --
## `member(the castNum of sprite 1).name`, or Piposh 1's
## `the name of member the castNum of sprite 1` -- and `rating` has the write
## idiom only, `set the castNum of sprite 18 to the number of member ...`, whose
## right-hand side is a bare number. So nothing in this corpus can observe the
## encoding, and reusing it anywhere the integer might be *stored* would need
## that claim re-measured.
##
## 0x20000 is far above any member number this corpus reaches (the largest cast
## holds a few thousand), so a packed value can never be mistaken for a bare one
## and rating's small-integer writes stay on the unpacked path.
const LIB_STRIDE := 0x20000


## Carry `(library, slot)` in one integer.
##
## Library 1 packs to the bare member number, so the overwhelmingly common case
## is byte-identical to what this returned before packing existed and no existing
## behaviour moves. A library of 0 -- which `castlibnum` answers for a sprite
## record that never decoded one -- means the same thing, because `(0 - 1)` times
## a stride is a negative address and not a library.
static func pack_ref(lib: int, member: int) -> int:
	if lib <= 1:
		return member
	return (lib - 1) * LIB_STRIDE + member


## Which library `of castLib <x>` names, or **0 for none**.
##
## `Movie::getCastLibIDByName` is an exact case-insensitive match against the
## names the movie's `MCsL` gave its libraries, and answers -1 when nothing
## matches (`movie.cpp:692-699`); 0 here is that answer, because 0 is not a
## library number in this port either.
##
## Director's cast argument is a name **or** a library number -- `member(x, 2)`
## and `the ... of castLib 2` are as legal as the spelled-out name, and this host
## stringifies the argument before it arrives, so a number reaches here as "2".
## Matched against library *names* it matches nothing, and the caller then falls
## back to library 1: the library named in the script is discarded and the member
## number resolved somewhere else, which is this module's whole subject. The name
## is tried first so a library genuinely called "2" still wins, which is the only
## way the two readings can disagree.
##
## 227 references in this corpus name their library by number and 226 of them say
## `castLib 1`, so the miss was invisible: the wrong answer and the right one were
## the same library. The odd one out is SAVELOAD's `field "plane" of castLib 2`.
##
## Split out of `resolve_ref` so that a caller which needs to know *whether* the
## script's library exists -- `director_preview.gd:_resolve_field`, which stops
## searching once it has been told where to look -- asks the same question rather
## than a second copy of it.
static func library_named(cast: String, table) -> int:
	if table == null:
		return 0
	var wanted := cast.strip_edges().to_lower()
	if wanted == "":
		return 0
	for number in table.cast_libs:
		if str(table.cast_libs[number].get("name", "")).to_lower() == wanted:
			return int(number)
	if wanted.is_valid_int() and table.cast_libs.has(int(wanted)):
		return int(wanted)
	return 0


## `[cast library, member number]` for a Lingo member reference.
##
## An unnamed cast means the movie's own, which is how Director resolves a bare
## `member(N)`; a name that matches no library falls back to the same rather than
## answering nothing, because a wrong-but-present member is easier to see in a
## trace than a silent zero.
static func resolve_ref(which: Variant, cast: String, table) -> Array:
	if table == null:
		return [1, 0]
	# A packed reference carries its library by construction, so it is decoded
	# before anything else looks at the `cast` argument and it wins outright.
	# Letting a named library override it would discard the one piece of
	# information packing exists to preserve -- which is the bug packing was
	# added for. No site in this corpus passes both.
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		var packed := int(which)
		if packed >= LIB_STRIDE:
			return [packed / LIB_STRIDE + 1, packed % LIB_STRIDE]
	var wanted := cast.strip_edges().to_lower()
	var found := library_named(cast, table)
	var lib := found if found > 0 else 1
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		return [lib, int(which)]
	# A name, which Director looks up across every cast when the reference does
	# not name one. Searching the named library first keeps an explicit
	# `of castLib "master"` authoritative.
	var named = table.cast_for(lib)
	if named != null:
		var here: int = named.number_of(str(which))
		if here > 0:
			return [lib, here]
	if wanted != "":
		return [lib, 0]
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for other in libs:
		var cast_file = table.cast_for(int(other))
		if cast_file == null:
			continue
		var elsewhere: int = cast_file.number_of(str(which))
		if elsewhere > 0:
			return [int(other), elsewhere]
	return [lib, 0]


## `the <prop> of member`.
##
## `number`/`membernum`/`castnum` are one arm on purpose.
## `member("able1").memberNum` and `the number of member "able1"` ask the same
## question by two spellings, and only the second used to have a path here: the
## first fell out of the match and returned 0. That is silent, because 0 is a
## plausible member number -- so every
## `set the cursor of sprite i to [member("able1").memberNum, member("able2").memberNum]`
## in MAP stored `[0, 0]` and composed to nothing.
static func read_prop(host, where: Array, prop: String, table) -> Variant:
	var m: Dictionary = table.get_member(int(where[0]), int(where[1]))
	# The reference in the shape `text_art.style_for` takes, built once. A local
	# rather than three inline literals, and not only for the repetition: a
	# dictionary literal wrapped onto a second line puts a **quoted key at the
	# start of a line ending in a colon**, which is indistinguishable from a
	# `match` arm to `tools/lingo_surface_audit.gd` -- so `align`, `cast_id` and
	# `cast_lib` were reported as member properties this engine binds.
	var ref := {"cast_lib": int(where[0]), "cast_id": int(where[1])}
	match prop:
		"name":
			return str(m.get("name", ""))
		"width":
			return int(m.get("width", 0))
		"height":
			return int(m.get("height", 0))
		"text":
			# Through the same override the renderer reads, or `the text of
			# member` would answer the authored placeholder while the screen
			# showed the current value.
			return host._field_text_of(m)
		"number", "membernum", "castnum":
			# Packed, for the same reason `the castNum of sprite` is: the number is
			# per library, so a number that dropped the library it was looked up in
			# is not an answer, it is a coincidence waiting to resolve somewhere
			# else. `the number of member "cutcursor" of castLib "panel.cst"`
			# returned a bare 166, and 166 is `leftcursor2` in the movie's own cast
			# -- so Rating's שיחה button drew a silhouette out of the wrong file
			# (docs/bugs-closed.md 65).
			#
			# Library 1 packs to the bare number, so every same-cast site in the
			# corpus is byte-identical and only cross-library reads move -- and
			# those were reading a different member than the script named.
			return pack_ref(int(where[0]), int(where[1]))
		"castlibnum":
			# The library half of the reference, and the one a script needs to hand
			# a member number back to `member()` in the cast it came from.
			return int(where[0])

		# ------------------------------------------------- what kind of member
		#
		# **`the type of member` is a symbol**, not a number. Director answers
		# `#bitmap`, `#field`, `#shape`; a script tests `if the type of member x =
		# #field`, and an integer would compare equal to nothing it was written
		# against. `director_cast.gd:TYPE_NAMES` already maps the type code onto
		# the reference's own word for it, so this is that name promoted to a
		# symbol rather than a second table.
		"type", "casttype":
			return StringName(str(m.get("type_name", "empty")))
		"scripttype":
			# `#movie`, `#score` or `#parent` -- what the script member is attached
			# as. The score's own word for it is the u16 in the specific block.
			match int(m.get("script_type", 0)):
				1: return &"score"
				2: return &"movie"
				3: return &"parent"
			return &"score"

		# ----------------------------------------------------- where and how big
		#
		# `the rect of member` is the member's **own** rectangle, in the member's
		# own coordinates -- not the rectangle of any sprite showing it. Director
		# stores it and this port decodes it as `initial_rect`; where a member type
		# carries none, the width and height are the whole of it.
		"rect":
			var box: Dictionary = m.get("initial_rect", {})
			if box.is_empty():
				return [0, 0, int(m.get("width", 0)), int(m.get("height", 0))]
			return [int(box.get("left", 0)), int(box.get("top", 0)),
				int(box.get("right", 0)), int(box.get("bottom", 0))]
		"regpoint":
			# The registration point, as an offset from the member's top-left --
			# which is what `locH`/`locV` position (§8.10). Answered as the
			# two-element list this port represents a point with, the same shape
			# `the loc of sprite` answers, so one can be written to the other.
			return [int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0))]
		"size":
			# Bytes of the member's own payload chunk. Director reports what the
			# member costs in memory, and the payload is that cost: the bitmap
			# bits, the styled text, the colour table.
			return table.member_payload_size(int(where[0]), int(where[1]))
		"depth":
			return int(m.get("bits_per_pixel", 0))
		"palette", "paletteref":
			# The palette this member's art is indexed against. Negative is one of
			# Director's built-ins and positive is a member number, which is the
			# reference's own encoding and the reason this is signed.
			#
			# **This answered -1 for every member of every title until the field
			# was read from the right offset** -- offset 24 of a bitmap's specific
			# block is the palette's *cast library*, not the palette
			# (`director_cast.gd:_parse_clut`). The six shipped titles genuinely
			# are all system Mac, so the wrong answer and the right one agreed
			# there and nowhere else: 655 of `itamar-park`'s 657 bitmap members
			# name a palette member.
			return int(m.get("palette_id", Palette.SYSTEM_MAC))

		# ------------------------------------------------------- memory and file
		#
		# 1997 memory questions with a 2026 answer. This port decodes a member
		# when something asks for it and purges nothing, so a member a script can
		# ask about is a member that is loaded -- and every guard of the shape
		# `repeat while not the mediaReady of member x` leaves on its first test
		# rather than never.
		"loaded", "mediaready":
			# **Time-based media is the exception, and it is not a caveat.** A
			# bitmap, a field or a shape is decoded on demand and never purged, so
			# it is loaded by the time anything can ask. A `#digitalVideo` member is
			# not: there is no QuickTime or AVI decoder here, so its media never
			# becomes ready and `repeat while not the mediaReady of member x` is a
			# loop Director would not leave either. A `#sound` member answers
			# whether its own bytes decoded. `preview/media.gd` is where both are
			# worked out and its header is the account of why.
			if Media.is_media(m):
				return 1 if bool(Media.facts_of(host, where, table)["ready"]) else 0
			return 1
		"mediabusy":
			# "Loading right now". Nothing here loads asynchronously -- a decode
			# either happened inside the call that asked or never will -- so this is
			# FALSE for every member type, including the video that will never be
			# ready. The pair is not a negation: `mediaReady` false and `mediaBusy`
			# false together is Director's "this will not arrive", which is exactly
			# the state a video is in.
			return 0
		# ------------------------------------------------------ time-based media
		#
		# The property set a `#sound` and a `#digitalVideo` member share, answered
		# by `preview/media.gd` because the two halves are one surface in Director
		# and splitting them here would be two copies of eighteen answers. A member
		# of any other type falls through to the report at the end, which is right:
		# `the sampleRate of member` of a bitmap is a question with no answer,
		# not a 0.
		#
		# Beside `the mediaReady` rather than at the end of the match, because they
		# are the same subject: whether a member's media could be opened, and what
		# it says if it could.
		"controller", "directtostage", "video", "sound", "crop", "center", \
		"scale", "framerate", "pausedatstart", "loop", "preload", \
		"digitalvideotype", "timescale", "cuepointnames", "cuepointtimes", \
		"channelcount", "samplerate", "samplesize":
			return Media.read_member(host, where, prop, table)
		"purgepriority":
			# 3 is Director's "never purge". Nothing here purges, so that is the
			# truth rather than a default.
			return 3
		"modified":
			# Whether the movie has written this member since it was loaded. The
			# text override table is the record of that, and it is the only member
			# state a script can change in this port today.
			return 1 if host._field_text.has(host._field_key(
				int(where[0]), int(where[1]))) else 0
		"filename":
			# The container the member lives in. For a *linked* member Director
			# answers the external file; every member in this corpus is internal,
			# and the container is then the honest answer to "where does this come
			# from".
			return table.container_path_of(int(where[0]))
		"scripttext":
			# The member's own Lingo, as the author typed it. `director_cast.gd`
			# reads it out of the info block for every member that has one, which
			# is how the whole corpus is compiled -- there was simply no spelling
			# for a movie to ask.
			return str(m.get("source", ""))

		# ------------------------------------------------------------- text boxes
		#
		# Two spellings each, and they are the same property: `the textSize` is
		# D3's and `the fontSize` is D5's, and a title mixing script vintages
		# writes both. Splitting them is how one would come to answer a value the
		# other could not read back.
		"textsize", "fontsize":
			# Through the override the renderer reads, not the authored run alone.
			# A write that reads back as the authored value is a lie the caller
			# cannot detect, which is the shape `preview/sprite_props.gd` was
			# written to make impossible one entity along.
			return int(TextArt.style_for(host, ref, m)["font_size"])
		"textstyle", "fontstyle":
			# Director's style is a word list -- "plain", "bold italic". The slant
			# byte carries the two this corpus uses.
			var slant := int((m.get("text_style", {}) as Dictionary).get("slant", 0))
			var words := PackedStringArray()
			if (slant & 1) != 0:
				words.append("bold")
			if (slant & 2) != 0:
				words.append("italic")
			return "plain" if words.is_empty() else " ".join(words)
		"textheight", "lineheight":
			return int(TextArt.style_for(host, ref, m)["line_height"])
		"textalign", "alignment":
			# 0 left, 1 centre, -1 right. `the textAlign` is a string and `the
			# alignment` a symbol; both name the same cell.
			var word := "left"
			match int(TextArt.style_for(host, ref, m)["align"]):
				1: word = "center"
				-1: word = "right"
			return word if prop == "textalign" else StringName(word)
		"boxtype":
			# How the box behaves when the text outgrows it. The specific block's
			# byte 3 is the author's choice of the four Director offers.
			match int(m.get("text_type", 0)):
				1: return &"scroll"
				2: return &"fixed"
				3: return &"limit"
			return &"adjust"
		"border":
			return int(m.get("border", 0))
		"margin":
			# Director's margin is the gutter between the border and the text.
			return int(m.get("gutter", 0))
		"boxdropshadow":
			return int(m.get("box_shadow", 0))
		"dropshadow":
			return int(m.get("text_shadow", 0))
		"autotab":
			return 1 if bool(m.get("auto_tab", false)) else 0
		"wordwrap":
			return 1 if bool(m.get("word_wrap", true)) else 0
		"scrolltop":
			return int(m.get("scroll", 0))
		"pageheight":
			# The height of the visible box, which for every member type here is
			# the member's own height; `the height` is the same number and this is
			# the spelling a scrolling field uses.
			return int(m.get("height", 0))
		"linecount":
			return LingoValue.count_of(host._field_text_of(m), "line")

		# ------------------------------------------------------------- shapes
		"shapetype":
			match int(m.get("shape_type", 0)):
				2: return &"roundRect"
				3: return &"oval"
				4: return &"line"
			return &"rect"
		"filled":
			return 1 if bool(m.get("filled", false)) else 0
		"linesize":
			# **The stored thickness is one greater than the drawn one**, which is
			# `director_cast.gd`'s finding and not a rounding: a stored 1 is an
			# invisible outline, and 162 of this corpus's 169 shape members are
			# exactly that -- the hotspots the game is built out of. Director's
			# property is the drawn thickness, so the stored byte is brought down
			# to it here rather than handed out raw.
			return maxi(int(m.get("line_thickness", 1)) - 1, 0)
		"pattern":
			return int(m.get("pattern", 0))
		"forecolor":
			return int(m.get("shape_fore", 0))
		"backcolor":
			return int(m.get("shape_back", 0))

		# --------------------------------------------------------- transitions
		#
		# A transition member is six bytes and `director/director_transition.gd`
		# decodes all of them; §10 already drives the frame's transition from the
		# same record. These are the spellings a movie uses to read one back.
		"transitiontype":
			return int(m.get("transition_type", 0))
		"chunksize":
			return int(m.get("chunk_size", 0))
		"changearea":
			return int(m.get("change_area", 0))
		"duration":
			# **One property, two member types, and the branch is Director's.** A
			# transition member's duration is how long the frame that names it will
			# spend; a sound or digital video member's is the length of its media.
			# The same word, asked of two things, and a port that answered only the
			# transition would report 0 for every sound in the language.
			if Media.is_media(m):
				return int(Media.facts_of(host, where, table)["duration"])
			# Milliseconds. Director reports a transition member's duration in
			# ticks, and this port carries it in milliseconds because that is what
			# the clock holds it in; converted here rather than stored twice.
			return int(float(m.get("duration_ms", 0.0)) * 60.0 / 1000.0)

	# **Nothing, not 0.** This fall-through is the only place that knows a member
	# property reached the end of the match without an arm, and for as long as it
	# answered 0 that knowledge was destroyed here: `the frameRate of member 12`
	# and `the width of member 12` came back as two integers a script cannot tell
	# apart, and 0 is a plausible value for most of the fifty names above.
	#
	# `director_preview.gd:lingo_member_prop` turns this back into the 0 a caller
	# has always seen, after reporting it as `LingoDiagnostics.MEMBER_PROP`. The
	# answer a movie gets does not move; the session gains the one fact it had no
	# way to record.
	#
	# **This match is the derivation.** `sprite_props.gd:consumed` has to consult a
	# table because `sprite_state.write_prop` accepts every key and has no
	# fall-through to reach. Here the arms *are* the list of consumed names, so
	# adding one removes a name from the report by construction and there is no
	# second copy to drift. That holds only while no arm answers null, which is
	# true of all fifty above and is the thing to re-check when one is added.
	return null
