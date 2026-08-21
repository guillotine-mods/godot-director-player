extends RefCounted
## Adopting a container as the movie now playing.
##
## This exists because the same sequence ran in two places and drifted. Opening
## the boot movie and `go to movie` both have to read the score, the labels, the
## cast table, the config, the starting tempo and the film-loop cast list -- and
## the film-loop cast list was once read in `_ready` and in `lingo_go_movie` and
## *not* in `_load_container`, which is exactly the shape of omission a second
## copy produces. `adopt` is the single copy; each caller does only what is
## genuinely its own.
##
## What is genuinely each caller's own is the tear-down. Opening the first movie
## has nothing to discard; `go to movie` has to discard almost everything, and
## `forget_previous` documents each thing it drops and, more importantly, the two
## things it deliberately does not.

const CastTable := preload("res://director/director_cast_table.gd")
const Labels := preload("res://director/director_labels.gd")
const Config := preload("res://director/director_config.gd")
const Palette := preload("res://director/director_palette.gd")
const FilmLoop := preload("res://director/director_film_loop.gd")
const FrameClock := preload("res://director/director_frame_clock.gd")


## Everything derived from a container that has just become the current movie.
##
## The score is set by the caller, because the two callers obtain it differently
## -- one fails the whole load on a bad score, the other declines the jump and
## keeps playing what it has.
static func adopt(host) -> void:
	host._labels = Labels.new()
	var vwlb: Array = host._movie.ids_of("VWLB")
	if not vwlb.is_empty():
		host._labels.parse(host._movie.read_chunk(vwlb[0]))

	host._table = CastTable.new()
	host._table.open(host._movie, host._paths)

	# The movie's own stage rect. Only a window uses it, but it is read for every
	# movie because a window's placement is the *difference* between its rect and
	# the stage movie's, and the stage is whichever movie happens to be playing.
	var config = Config.new()
	host._config = config if config.read(host._movie) else null

	# The rate this movie starts at, before its score writes a tempo. Without it
	# every movie that never writes one runs at the engine's guess -- which is
	# nearly twice too fast for a title whose rooms mostly want 8 fps, and the
	# only symptom is that it feels wrong.
	var stated := int(host._config.default_tempo) if host._config != null else 0
	host._clock.movie_default_fps = float(stated) if stated > 0 else FrameClock.DEFAULT_FPS
	# Which tempo convention this movie's score cell is written in is a property
	# of the movie, and its config chunk is the only thing that says. A no-op
	# today -- the clock reads 0 as D6-or-later and `director_score.gd` decodes
	# nothing older -- and wired here rather than when a pre-D6 reader lands, so
	# that reader arrives to a clock that already knows rather than to a silent
	# wrong answer on every frame.
	host._clock.movie_file_version = int(host._config.version) if host._config != null else 0

	# Palette ids are per movie, so the state resets with the movie rather than
	# carrying the last one's cache and cycling offsets into this one.
	#
	# **The movie's own default is what it resets to**, which is §11's last resort
	# and used to be a hardcoded system Mac. Every movie states one in its config
	# chunk; the six shipped titles all state system Mac, so nothing about them
	# moves, and a Windows-authored title states the Windows table instead --
	# `itamar-park`'s two movies and 16 of `itamar-magichat`'s do. A movie with no
	# readable config keeps system Mac, because a movie that will not say has no
	# opinion to honour.
	host._palette_state.table_for = host._palette_table_for
	var default_palette := Palette.SYSTEM_MAC
	if host._config != null and int(host._config.default_palette) != 0:
		default_palette = int(host._config.default_palette)
	host._palette_state.reset(default_palette)
	host._palette = host._palette_state.table

	host._ccl = PackedStringArray()
	var ccl_ids: Array = host._movie.ids_of("ccl ")
	if not ccl_ids.is_empty():
		host._ccl = FilmLoop.read_cast_list(host._movie.read_chunk(ccl_ids[0]))


## Drop everything that belonged to the movie being left.
##
## Keeping any of it means the next movie draws with the last one's art and
## resolves members in the last one's casts -- which resolves to *real* members
## and so looks like corruption rather than an error.
##
## Two things deliberately survive, and both were bugs when they did not.
##
## **Field text in linked casts.** These used to be dropped wholesale, because
## the key was `<library number>:<member>` and a library number is local to the
## movie that was open when a script wrote it. Now the key names the cast's
## *file*, so only the movie's own internal cast can collide, and that is all
## that is dropped. The player's score and inventory live in `field "points"` and
## `field "objectsfield"` of the linked cast; clearing them on every `go to
## movie` reset the HUD at every doorway, and it is also what makes a save
## restorable at all -- `SAVELOAD` writes seven of those fields and then sends
## the stage to another movie in the next statement.
##
## **Lingo globals.** Not touched here at all. They are the movie-independent
## state the whole boot chain exists to establish.
static func forget_previous(host, previous_path: String) -> void:
	host._textures.clear()
	host._hit_images.clear()
	host._matte_masks.clear()
	host._clear_trails()
	host._forget_field_text_of(previous_path)
	host._loops.clear()
	host._overrides.clear()
	# Which channels the *previous* movie measured says nothing about this one.
	host._collision_channels.clear()
	# Channel cursors survive frame changes and cast swaps but not a new movie,
	# which is one of the points Director forces a recompute at. The stored value
	# is a pair of member *numbers*, and those are local to the cast that was open
	# when the script wrote them: MAP leaves [14, 15] on channels 3-14 for
	# `able1`/`able2`, and members 14 and 15 of the next movie's cast are whatever
	# that movie happens to hold. Carried over, the pair does not keep a cursor,
	# it installs a different one. `_cursor_applied` is cleared with them, or the
	# new movie's first genuine assignment compares equal to the stale key and is
	# never pushed to the OS at all.
	host._channel_cursors.clear()
	host._global_cursor = 0
	host._cursor_applied = "?none"
	# `the constraint of sprite` is channel state by the same rule, and dies at
	# the same point. A constraint names a *channel number*, which is meaningless
	# in the next movie, and an invented one is silent: all it does is stop a
	# position write landing where the script asked.
	host._channel_constraints.clear()
	# Both are keyed by channel and measured against `_ticks`, which restarts
	# below. Left behind, a channel's loop start would sit in the *previous*
	# movie's clock and every film loop in the new room would be asked for a
	# negative frame.
	host._last_member.clear()
	host._loop_start.clear()
	host._assigned_member.clear()
	host._index = 0
	host._ticks = 0
	host._held = true
	# The clock belongs to the movie that is being left: its tempo, any wait it
	# had armed and any transition it was still playing all go with it. So does
	# the deferred `enterFrame` a transition was holding -- the frame it was owed
	# to is in a container that is now closed.
	host._clock.reset()
	host._pending_enter = null
	host._puppet_transition = {}
	host._entered_index = -1
	host._jump_queued = false
	# **Cleared, not ended.** The reference sends no `endSprite` when a movie is
	# left: `killScriptInstances` is called from one place, `score.cpp:702` inside
	# `update()`, and a `go to movie` destroys the whole `Score` with every
	# `_scriptInstanceList` in it. What has to go is the record, because it is keyed
	# by channel and by frame span -- both of which name something else in the movie
	# that is arriving, so a channel left in here would compare equal to a stranger
	# and that sprite would never be told it had begun.
	host._begun_sprites.clear()
	# Restart-on-change compares this frame's sound channels against the frame
	# before. Carried across a movie change, the new movie's first frame would be
	# compared against the last frame of the old one -- which in the case that
	# matters, both naming member 3 of their own casts, reads as "no change" and
	# opens the room silent.
	host._score_sound.reset()
	# A new movie starting is one of the five moments Director *forces* a cursor
	# recompute (DIRECTOR_ENGINE.md 7.5), and it is the only one of the five that
	# no pointer event will stand in for. Clearing `_cursor_applied` above only
	# arms the next recompute; without this line nothing asks for one, and the
	# movie being left keeps its custom cursor on screen -- over a room that never
	# assigned one -- until the player happens to move the mouse.
	host._resolve_cursor()
