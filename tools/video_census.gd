extends SceneTree
## Every moving picture in reach: which members claim to play one, which movies
## drive one, and what the files behind them actually are.
##
##   godot --headless --audio-driver Dummy --path . --script tools/video_census.gd
##   godot --headless --audio-driver Dummy --path . --script tools/video_census.gd -- --list
##   godot --headless --audio-driver Dummy --path . --script tools/video_census.gd -- \
##       --roots res://test-games/itamar-magichat --list
##
##   --roots A,B   only these corpus roots (default: every one under games/ and test-games/)
##   --list        print every video member and every media file, not only the totals
##
## ## Why a third census
##
## `tools/member_type_census.gd` answers "how many members of type N", and
## `tools/xtra_members.gd` answers "what does each Xtra member say it is". Neither
## can answer the question a *decoder* decision rests on, which has four parts and
## needs all four in one place:
##
##   1. how many members claim to play video -- both `#digitalVideo` (type 10)
##      **and** the Xtra members that are video players wearing a different type
##      code, which is how this corpus's own intro is authored;
##   2. whether any score actually **places** one, because a member nothing puts
##      on the stage costs a player nothing whatever the decoder situation;
##   3. which movies **drive** one from Lingo, because a movie that polls a video
##      it cannot see is where a hang would come from; and
##   4. what container format the bytes on disc are in, sniffed from their own
##      magic rather than from the extension -- which is the fact that decides
##      whether "transcode it" or "write a decoder" is even a sentence.
##
## Extension is not evidence and this tool does not treat it as such. `.mpg` is
## used here for MPEG-1 *system* streams, `.avi` for one RIFF file whose video
## stream is `mrle` and whose audio is raw PCM, and `.dat` for something that is
## not video at all (`windemo.dat` is an icon table). Each file's first bytes are
## read and classified, and anything unrecognised is printed rather than counted
## as "video, presumably".
##
## ## What a "video Xtra" is, and why it is a table rather than a guess
##
## A type-15 member is a native DLL's member, and the DLL decides what it is: a
## `text` Xtra draws text and a `DirectMediaXtra` plays an MPEG. There is no bit
## in the container that says "this one is a video player", so the only honest
## reading is a table keyed by the Xtra's own symbol -- the one the member records
## and `tools/xtra_members.gd` prints. `VIDEO_XTRAS` below is that table, with the
## reason for each entry beside it, and **every symbol not in it is printed in an
## `unclassified` list** rather than silently counted as not-video. A new corpus
## adds rows to the list, not a silent miscount.
##
## ## What is asserted
##
## Only things this port controls. It is not a failure for a title to ship an
## MPEG-1 file, so the census does not assert the corpus:
##
##   * every corpus root was reached and containers were opened -- the same
##     dark-harness guard `member_type_census.gd` carries, and for the same
##     reason: a census that walked nothing prints zeroes that read as findings;
##   * **every type-10 member the raw `CASt` scan finds is also reachable through
##     `DirectorCastTable`.** A first-`CAS*` walk misses 412 of `itamar-magichat`'s
##     454 Xtra members, so "the engine can address it" is a real question about
##     this type too, and a member the engine cannot reach is one no verdict about
##     it applies to;
##   * **every media file classifies to a named container.** The whole costed
##     decision below rests on "these are MPEG-1 and MS-RLE", so a file the sniff
##     cannot name is a hole in the evidence and is a failure here.
##
## Title-agnostic: it names no game, and discovers its roots by listing them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]

const VIDEO_TYPE := 10
const XTRA_TYPE := 15

## Xtra symbols that are video players, and why each is on the list.
##
## Keyed lowercase, because the symbol is spelled by whoever authored the movie
## and `DirectMediaXtra` / `directmediaxtra` are the same DLL.
##
## The evidence for a row is the *movie's own Lingo*, not the name: a member is
## on this list when a handler in the corpus sets `mediaFilename` on it to a
## video file, or calls `play()`/`getPlaybackEvent` on a sprite showing it. That
## is why `Trans` and `text` are absent and why nothing was added speculatively.
const VIDEO_XTRAS := {
	# Tabuleiro's DirectMedia Xtra: an MPEG/AVI/QuickTime player driven by
	# `mediaFilename`, `play()`, `stop()` and `getPlaybackEvent`. Magic Hat's
	# `init intro` sets `member("IntroRetroVideo").mediaFilename` to
	# `<moviePath><lang>\mainmenu\intro.mpg`.
	"directmediaxtra": "MPEG/AVI/QuickTime player (Tabuleiro DirectMedia)",
	"directmedia": "MPEG/AVI/QuickTime player (Tabuleiro DirectMedia)",
	# Macromedia's own QuickTime asset Xtra -- the type-10 member's D7 successor.
	"quicktimeasset": "QuickTime asset Xtra",
	"qt3asset": "QuickTime 3 asset Xtra",
	# Macromedia's MPEG Xtra and the RealMedia one, neither seen in this corpus
	# and both on the list because the question is "does any title in reach play
	# video", and a table that only knows the symbols already found answers it
	# wrongly the first time a new disc is added.
	"mpegxtra": "MPEG player Xtra",
	"mpegadvance": "MPEG Advance Xtra",
	"realmedia": "RealMedia streaming Xtra",
	"videosprite": "VideoSprite Xtra",
	# **This is the one Magic Hat's intro is built on**, and it is on the list
	# because of the movie's own Lingo rather than because of its name: the two
	# members carrying this symbol are `IntroRetroVideo` and `magicvideo`, and
	# `magichat.dir`'s `init intro` sets `member("IntroRetroVideo").mediaFilename`
	# to `<moviePath><lang>\mainmenu\intro.mpg` while `BehaviorScript 134` polls
	# `sprite(1).getPlaybackEvent`. Visible Light's OnStage Media Xtra is an
	# MPEG-1 player with exactly that surface.
	"visiblelightonstagemedia": "MPEG-1 player (Visible Light OnStage Media)",
}

## Members whose Xtra symbol is one of these are moving pictures but **not**
## digital video: they are their own animation formats with their own decoders,
## and they are counted separately so that "video" stays one question.
const ANIMATION_XTRAS := {
	"flash": "Flash (SWF) player",
	"flashasset": "Flash (SWF) player",
	"animgif": "animated GIF player",
	"animgifasset": "animated GIF player",
	"gifanimation": "animated GIF player",
}

## Lingo names that only mean something to a moving picture. A movie mentioning
## one is a movie that drives video, whether or not its own casts hold the member
## -- `sprite(1).getPlaybackEvent` names no member at all.
##
## `duration`, `play` and `stop` are deliberately **not** here: all three are
## ordinary Lingo used constantly for sounds, transitions and `play movie`, so
## including them would report every movie in the corpus and answer nothing.
##
## **Matched on a word boundary, not as a substring**, and that is not fussiness:
## the first version of this list matched `startTime` inside the property name
## `prStartTime` and reported five of Magic Hat's sixteen containers as driving
## video when none of them does. A token list whose hits are mostly false is a
## list nobody reads.
const VIDEO_TOKENS := [
	"getplaybackevent", "mediafilename", "movierate", "movietime",
	"digitalvideotype", "pausedatstart", "directtostage", "mostrecentcuepoint",
	"trackenabled", "settrackenabled", "starttime", "stoptime",
	"mediabusy", "videoforwindows", "quicktimemovie", "digitalvideotimescale",
]

## File extensions worth sniffing. The sniff decides what the file *is*; this
## only decides which files are worth opening, and it is deliberately generous --
## `.dat` is here because `windemo.dat` sits beside a title's movies and had to be
## ruled out rather than assumed.
const MEDIA_EXTENSIONS := [
	"mpg", "mpeg", "m1v", "m2v", "mpv", "avi", "mov", "qt", "moov",
	"flc", "fli", "flh", "cel", "swf", "gif", "ogv", "ogg", "webm", "mp4",
	"rm", "rmvb", "asf", "wmv", "dat", "dir_video",
]

## How many bytes of a file the sniff reads. Big enough to hold an AVI's `hdrl`
## list (its stream headers live in the first few hundred bytes) and an MPEG-1
## system stream's first sequence header, which can sit a few packets in.
const SNIFF_BYTES := 262144


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var list_them := Args.flag(args, "list")

	var roots := _roots(Args.text(args, "roots", ""))
	var token_res := _token_matchers()

	# corpus -> counters
	var stats: Dictionary = {}
	var video_members: Array[Dictionary] = []
	var placed: Array[Dictionary] = []
	var driving: Array[Dictionary] = []
	var unclassified: Dictionary = {}
	var unreachable: Array[String] = []
	var media: Array[Dictionary] = []
	var unknown_media: Array[String] = []
	var containers := 0

	for root in roots:
		var corpus := str(root).get_file()
		stats[corpus] = {
			"containers": 0, "type10": 0, "xtra_video": 0, "xtra_anim": 0,
			"xtra_total": 0, "placed": 0, "placed_anim": 0, "movies_driving": 0,
			"media_files": 0, "media_bytes": 0,
		}
		var files: Array[String] = []
		_walk_containers(root, files)
		files.sort()
		# One `Paths` per root: it indexes the whole tree on first use, so a fresh
		# one per movie turns this into an O(movies x files) scan. Same reason
		# `tools/xtra_members.gd` hoists it.
		var member_paths := Paths.new()
		member_paths.root = root
		var seen_casts: Dictionary = {}
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			containers += 1
			(stats[corpus] as Dictionary)["containers"] = int(
				(stats[corpus] as Dictionary)["containers"]) + 1

			# --- the denominator: raw CASt chunks of type 10 ---------------------
			# Only the type word is read, which is the one field whose position does
			# not depend on the type. This is what the reachability check below is
			# measured against.
			var raw_video := 0
			for id in f.ids_of("CASt"):
				var raw: PackedByteArray = f.read_chunk(int(id))
				if raw.size() >= 4 and ((raw[0] << 24) | (raw[1] << 16)
						| (raw[2] << 8) | raw[3]) == VIDEO_TYPE:
					raw_video += 1

			var member_table := CastTable.new()
			if not member_table.open(f, member_paths):
				member_table.close()
				f.close()
				if raw_video > 0:
					unreachable.append("%s %s: %d type-10 member(s), no cast table"
						% [corpus, path.get_file(), raw_video])
				continue

			# --- what the engine can address ------------------------------------
			var reached_video := 0
			var video_here: Dictionary = {}   # "lib:slot" -> member, for the score pass
			for lib in member_table.cast_libs.keys():
				var cast = member_table.cast_for(int(lib))
				if cast == null:
					continue
				var lib_path := str(member_table.cast_libs[lib].get("resolved_path", ""))
				var cast_key := "%s#%d" % [lib_path, int(cast.cas_chunk_id)]
				var fresh := not seen_casts.has(cast_key)
				seen_casts[cast_key] = true
				# **Scripts are attributed to the cast that holds them, not to every
				# container that links it**, and the first version did the opposite.
				# `itamar-park`'s MPEG player is one script member of the shared
				# `utils.cst`, and attributing it per container reported four of that
				# title's ten containers as "driving video" when the answer is one
				# library, linked four times. A count that multiplies by the link
				# graph is not a count of anything.
				var tokens_here: Dictionary = {}
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					if m.is_empty():
						continue
					var code := int(m.get("type", 0))
					if fresh:
						var source := str(m.get("source", "")).to_lower()
						if source != "":
							for token in VIDEO_TOKENS:
								if tokens_here.has(token):
									continue
								if (token_res[token] as RegEx).search(source) != null:
									tokens_here[token] = number
					if code != VIDEO_TYPE and code != XTRA_TYPE:
						continue
					if code == VIDEO_TYPE:
						reached_video += 1
					var symbol := str(m.get("xtra_symbol", "")).to_lower()
					var kind := _classify(code, symbol)
					if kind == "other-xtra":
						if fresh:
							(stats[corpus] as Dictionary)["xtra_total"] = int(
								(stats[corpus] as Dictionary)["xtra_total"]) + 1
							var key := symbol if symbol != "" else "(no symbol)"
							unclassified[key] = int(unclassified.get(key, 0)) + 1
						continue
					var record := {
						"corpus": corpus,
						"file": (lib_path if lib_path != "" else path).get_file(),
						"path": path, "lib": int(lib), "number": int(number),
						"name": str(m.get("name", "")), "kind": kind,
						"symbol": symbol, "type": code,
						"width": int(m.get("width", 0)), "height": int(m.get("height", 0)),
					}
					# **Kept for the score pass whether the cast is fresh or not.**
					# A shared library is walked once for counting, but a movie that
					# links it can still place its members, and skipping the record
					# here would make every video sprite in a linked cast invisible --
					# `album.cst` holds Magic Hat's album video and nine containers
					# link it.
					video_here["%d:%d" % [int(lib), int(number)]] = record
					if not fresh:
						continue
					video_members.append(record)
					if code == XTRA_TYPE:
						(stats[corpus] as Dictionary)["xtra_total"] = int(
							(stats[corpus] as Dictionary)["xtra_total"]) + 1
						var bucket := "xtra_video" if kind == "video-xtra" else "xtra_anim"
						(stats[corpus] as Dictionary)[bucket] = int(
							(stats[corpus] as Dictionary)[bucket]) + 1
					else:
						(stats[corpus] as Dictionary)["type10"] = int(
							(stats[corpus] as Dictionary)["type10"]) + 1

				if not tokens_here.is_empty():
					var names: Array = tokens_here.keys()
					names.sort()
					driving.append({
						"corpus": corpus,
						"file": (lib_path if lib_path != "" else path).get_file(),
						"tokens": names})
					(stats[corpus] as Dictionary)["movies_driving"] = int(
						(stats[corpus] as Dictionary)["movies_driving"]) + 1

			if reached_video < raw_video:
				unreachable.append("%s %s: %d of %d type-10 member(s) reachable"
					% [corpus, path.get_file(), reached_video, raw_video])

			# --- does any score put one on the stage? ----------------------------
			var vwsc: Array = f.ids_of("VWSC")
			if not vwsc.is_empty() and not video_here.is_empty():
				var config = Config.new()
				var version := int(config.version) if config.read(f) else 0
				var score = Score.new()
				if score.parse(f.read_chunk(int(vwsc[0])), version):
					var seen_here: Dictionary = {}
					for i in score.frame_count:
						for sprite_value in score.frame(i).get("sprites", []):
							var sprite: Dictionary = sprite_value
							var key := "%d:%d" % [
								int(sprite["cast_lib"]), int(sprite["cast_id"])]
							if not video_here.has(key):
								continue
							var slot := "%s ch%d" % [key, int(sprite["channel"])]
							if seen_here.has(slot):
								continue
							seen_here[slot] = true
							var rec: Dictionary = (video_here[key] as Dictionary).duplicate()
							rec["channel"] = int(sprite["channel"])
							rec["first_frame"] = i + 1
							rec["movie"] = path.get_file()
							placed.append(rec)
							# Counted apart, because an animated GIF and an MPEG
							# fail for different reasons and one total would let
							# the 52 Flash sprites hide the 2 video ones.
							var bucket := "placed_anim" if str(rec["kind"]) \
								== "animation-xtra" else "placed"
							(stats[corpus] as Dictionary)[bucket] = int(
								(stats[corpus] as Dictionary)[bucket]) + 1

			member_table.close()
			f.close()

		# --- what is on disc beside the movies ---------------------------------
		var media_files: Array[String] = []
		_walk_media(root, media_files)
		media_files.sort()
		for path in media_files:
			var info := _sniff(path)
			info["corpus"] = corpus
			media.append(info)
			(stats[corpus] as Dictionary)["media_files"] = int(
				(stats[corpus] as Dictionary)["media_files"]) + 1
			(stats[corpus] as Dictionary)["media_bytes"] = int(
				(stats[corpus] as Dictionary)["media_bytes"]) + int(info["bytes"])
			if str(info["format"]) == "unknown":
				unknown_media.append("%s %s" % [corpus, path])

	_report(stats, video_members, placed, driving, unclassified, media,
		list_them, roots)

	# ------------------------------------------------------------------ assertions
	h.begin("the census covered something")
	h.check("found corpus roots", not roots.is_empty(), "%d" % roots.size())
	h.check("opened containers", containers > 0, "%d" % containers)
	h.complete("the census covered something")

	h.begin("every video member the engine could be asked about is one it can reach")
	h.check(
		"every type-10 CASt chunk resolves through DirectorCastTable",
		unreachable.is_empty(),
		"; ".join(unreachable) if not unreachable.is_empty()
			else "a member behind a second cast library is one no verdict reaches")
	h.complete("every video member the engine could be asked about is one it can reach")

	h.begin("every media file on disc says what container it is")
	h.check(
		"nothing sniffs to `unknown`",
		unknown_media.is_empty(),
		"; ".join(unknown_media.slice(0, 8)) if not unknown_media.is_empty()
			else "the decoder question is decided by these formats, so an "
				+ "unclassified file is a hole in the evidence")
	h.complete("every media file on disc says what container it is")

	quit(h.finish("video members, the movies that drive them, and the files behind them"))


# ------------------------------------------------------------------------ report


func _report(stats: Dictionary, video_members: Array[Dictionary],
		placed: Array[Dictionary], driving: Array[Dictionary],
		unclassified: Dictionary, media: Array[Dictionary],
		list_them: bool, roots: Array[String]) -> void:
	var corpora: Array = stats.keys()
	corpora.sort()

	print("")
	print("%d corpus root(s)" % roots.size())
	print("")
	var rows := [
		["containers", "containers"],
		["type10", "digitalVideo (10)"],
		["xtra_video", "video Xtra"],
		["xtra_anim", "animation Xtra"],
		["xtra_total", "Xtra members"],
		["placed", "video sprites scored"],
		["placed_anim", "animation sprites scored"],
		["movies_driving", "casts driving video"],
		["media_files", "media files on disc"],
	]
	var header := "  %-24s" % ""
	for corpus in corpora:
		header += "%16s" % str(corpus).substr(0, 15)
	header += "%10s" % "total"
	print(header)
	for row in rows:
		var line := "  %-24s" % str(row[1])
		var total := 0
		for corpus in corpora:
			var v := int((stats[corpus] as Dictionary)[str(row[0])])
			total += v
			line += "%16d" % v
		line += "%10d" % total
		print(line)
	var line_mb := "  %-24s" % "media MB on disc"
	var total_mb := 0.0
	for corpus in corpora:
		var mb := float(int((stats[corpus] as Dictionary)["media_bytes"])) / 1048576.0
		total_mb += mb
		line_mb += "%16.1f" % mb
	line_mb += "%10.1f" % total_mb
	print(line_mb)

	# --- what the media actually is ------------------------------------------
	# Grouped by container *and shape* -- the codec and geometry -- and not by the
	# full detail string, which carries a frame count and would put every one of
	# the 415 FLIC files on its own row.
	var by_format: Dictionary = {}
	for info_value in media:
		var info: Dictionary = info_value
		var key := "%s / %s" % [str(info["format"]), str(info["shape"])]
		var agg: Dictionary = by_format.get(key, {"n": 0, "bytes": 0})
		agg["n"] = int(agg["n"]) + 1
		agg["bytes"] = int(agg["bytes"]) + int(info["bytes"])
		by_format[key] = agg
	print("")
	print("media files by container, sniffed from their own first bytes:")
	var formats: Array = by_format.keys()
	formats.sort()
	for key in formats:
		var agg: Dictionary = by_format[key]
		print("  %-58s %4d  %8.1f MB" % [
			key, int(agg["n"]), float(int(agg["bytes"])) / 1048576.0])

	# --- the members ----------------------------------------------------------
	# Video only unless `--list`. The animation Xtras outnumber the video members
	# by 226 to 1 in this corpus, so listing both by default buries the four
	# members the whole decoder question is about under 452 animated GIFs.
	var video_only := video_members.filter(
		func(r: Dictionary) -> bool: return str(r["kind"]) != "animation-xtra")
	print("")
	print("video members (%d of %d moving-picture members):"
		% [video_only.size(), video_members.size()])
	for record_value in (video_members if list_them else video_only):
		var r: Dictionary = record_value
		print("  %-16s %-20s #%-5d %-20s %-14s %s" % [
			str(r["corpus"]), str(r["file"]), int(r["number"]), str(r["name"]),
			str(r["kind"]), str(r["symbol"])])

	var placed_video := placed.filter(
		func(r: Dictionary) -> bool: return str(r["kind"]) != "animation-xtra")
	print("")
	print("video sprites the score places (%d of %d moving-picture sprites):"
		% [placed_video.size(), placed.size()])
	for record_value in (placed if list_them else placed_video):
		var r: Dictionary = record_value
		print("  %-16s %-20s ch%-3d from frame %-5d  #%-4d %-20s %s" % [
			str(r["corpus"]), str(r["movie"]), int(r["channel"]),
			int(r["first_frame"]), int(r["number"]), str(r["name"]),
			str(r["kind"])])

	print("")
	print("cast libraries whose Lingo drives a moving picture (%d):" % driving.size())
	for record_value in driving:
		var r: Dictionary = record_value
		print("  %-16s %-22s %s" % [
			str(r["corpus"]), str(r["file"]), ", ".join(r["tokens"] as Array)])

	if not unclassified.is_empty():
		print("")
		print("Xtra symbols not on either table -- read these before trusting a zero:")
		var syms: Array = unclassified.keys()
		syms.sort()
		for s in syms:
			print("  %-32s %d" % [s, int(unclassified[s])])

	if list_them:
		print("")
		print("every media file:")
		for info_value in media:
			var info: Dictionary = info_value
			print("  %-16s %-9s %-40s %8.2f MB  %s" % [
				str(info["corpus"]), str(info["format"]),
				str(info["path"]).replace("res://", ""),
				float(int(info["bytes"])) / 1048576.0, str(info["detail"])])


# ----------------------------------------------------------------- classification


## What a member of `code` naming Xtra `symbol` is, as one of `digitalVideo`,
## `video-xtra`, `animation-xtra` or `other-xtra`.
static func _classify(code: int, symbol: String) -> String:
	if code == VIDEO_TYPE:
		return "digitalVideo"
	if VIDEO_XTRAS.has(symbol):
		return "video-xtra"
	if ANIMATION_XTRAS.has(symbol):
		return "animation-xtra"
	return "other-xtra"


# ------------------------------------------------------------------- the sniff


## What a file on disc actually is, from its own first bytes.
##
## `{"path", "bytes", "format", "shape", "detail"}`. `format` is a container name
## or `"unknown"`; `detail` carries the codec, geometry and length where the
## header states them, because "AVI" and "AVI holding 640x480 8-bit RLE" are
## different answers to the costing question -- the second one is decodable in an
## afternoon and the first is not an answer at all. `shape` is the same thing
## with the per-file numbers (frame counts, durations) removed, so that files of
## one kind group onto one row of the report.
func _sniff(path: String) -> Dictionary:
	var out := {"path": path, "bytes": 0, "format": "unknown", "shape": "", "detail": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["detail"] = "unreadable"
		return out
	out["bytes"] = int(f.get_length())
	var head: PackedByteArray = f.get_buffer(mini(SNIFF_BYTES, int(f.get_length())))
	f.close()
	if head.size() < 12:
		out["format"] = "empty"
		return out

	# MPEG-1/2 system stream. The pack header is 00 00 01 BA and the two bits
	# after it tell the versions apart: `0b01` is MPEG-2's, anything else is
	# MPEG-1's four-bit `0b0010` marker.
	if _has(head, 0, [0x00, 0x00, 0x01, 0xBA]):
		var mpeg2 := (head[4] & 0xC0) == 0x40
		out["format"] = "MPEG-2 PS" if mpeg2 else "MPEG-1 system"
		# The MPEG detail carries no per-file number -- resolution, rate and bit
		# rate are the encode, so every file of one batch groups onto one row.
		out["detail"] = _mpeg_detail(head)
		out["shape"] = out["detail"]
		return out
	if _has(head, 0, [0x00, 0x00, 0x01, 0xB3]):
		out["format"] = "MPEG-1 video"
		out["detail"] = _mpeg_detail(head)
		out["shape"] = out["detail"]
		return out
	if _has(head, 0, [0x52, 0x49, 0x46, 0x46]) and _has(head, 8, [0x41, 0x56, 0x49, 0x20]):
		out["format"] = "RIFF AVI"
		var avi := _avi_detail(head)
		out["detail"] = str(avi["detail"])
		out["shape"] = str(avi["shape"])
		return out
	if _has(head, 0, [0x4F, 0x67, 0x67, 0x53]):
		out["format"] = "Ogg"
		# The one container Godot 4.7 has a decoder for, which is why it is
		# sniffed at all: a corpus file already in it would change the verdict.
		out["detail"] = "Theora" if _find(head, [0x80, 0x74, 0x68, 0x65, 0x6F, 0x72, 0x61]) >= 0 \
			else "no Theora stream in the first page"
		out["shape"] = out["detail"]
		return out
	# QuickTime / ISO-BMFF: a top-level atom at offset 4.
	var atom := head.slice(4, 8).get_string_from_ascii()
	if ["ftyp", "moov", "mdat", "wide", "free", "skip", "pnot"].has(atom):
		out["format"] = "QuickTime"
		out["detail"] = "first atom '%s'" % atom
		out["shape"] = out["detail"]
		return out
	# Autodesk FLIC: the magic is a little-endian u16 at offset 4, not at 0.
	var flic := int(head[4]) | (int(head[5]) << 8)
	if flic == 0xAF11 or flic == 0xAF12 or flic == 0xAF44:
		var names := {0xAF11: "FLI", 0xAF12: "FLC", 0xAF44: "FLC (EGI)"}
		var fw := int(head[8]) | (int(head[9]) << 8)
		var fh := int(head[10]) | (int(head[11]) << 8)
		out["format"] = "Autodesk FLIC"
		out["shape"] = "%s, %dx%d" % [str(names[flic]), fw, fh]
		out["detail"] = "%s, %d frame(s)" % [
			str(out["shape"]), int(head[6]) | (int(head[7]) << 8)]
		return out
	if head[0] == 0x46 or head[0] == 0x43 or head[0] == 0x5A:  # F/C/Z
		if head.slice(1, 3).get_string_from_ascii() == "WS":
			out["format"] = "SWF"
			out["detail"] = "version %d" % int(head[3])
			out["shape"] = out["detail"]
			return out
	if head.slice(0, 4).get_string_from_ascii() == "GIF8":
		out["format"] = "GIF"
		out["detail"] = "animated" if _find(head, [0x21, 0xF9]) >= 0 else "still"
		out["shape"] = out["detail"]
		return out
	if _has(head, 0, [0x1A, 0x45, 0xDF, 0xA3]):
		out["format"] = "Matroska/WebM"
		return out
	if _has(head, 0, [0x30, 0x26, 0xB2, 0x75]):
		out["format"] = "ASF/WMV"
		return out
	# Not video, and saying so is the point: `windemo.dat` sits beside a title's
	# movies and is an icon table. A census that counted it as "one more video
	# file we cannot play" would overstate the loss by one.
	if head.slice(1, 6).get_string_from_ascii() == "ICONS":
		out["format"] = "not video"
		out["detail"] = "icon table"
		out["shape"] = out["detail"]
		return out
	out["detail"] = "first bytes %s" % head.slice(0, 8).hex_encode()
	out["shape"] = out["detail"]
	return out


## Width, height, frame rate and bit rate out of an MPEG-1 sequence header.
static func _mpeg_detail(head: PackedByteArray) -> String:
	var at := _find(head, [0x00, 0x00, 0x01, 0xB3])
	if at < 0 or at + 12 > head.size():
		return "no sequence header in the first %d bytes" % head.size()
	var b := head.slice(at + 4, at + 12)
	var w := (int(b[0]) << 4) | (int(b[1]) >> 4)
	var hgt := ((int(b[1]) & 0x0F) << 8) | int(b[2])
	# Table 2-6 of ISO 11172-2. Index 0 is forbidden and is reported as such
	# rather than as a rate, because a zero fps in the report would read as a
	# still image.
	var rates: Array[float] = [0.0, 23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0]
	var code := int(b[3]) & 0x0F
	var fps: float = rates[code] if code < rates.size() else 0.0
	# 18 bits of 400 bit/s units, straddling three bytes.
	var bitrate := (int(b[4]) << 10) | (int(b[5]) << 2) | (int(b[6]) >> 6)
	var audio := "with MPEG audio" if _find(head, [0x00, 0x00, 0x01, 0xC0]) >= 0 \
		else "video only"
	return "%dx%d, %.2f fps, %d kbit/s, %s" % [
		w, hgt, fps, int(round(float(bitrate) * 400.0 / 1000.0)), audio]


## The video codec, geometry and length out of an AVI's `avih`/`strh`/`strf`.
##
## Read by hand rather than by a RIFF walker, because the only question is what
## the first video stream's four-character handler is and a handler is the one
## thing that decides whether a decoder is a weekend or a year.
##
## `{"shape", "detail"}` -- the second adds the frame count and running time,
## which are per-file and would split the report into one row each.
static func _avi_detail(head: PackedByteArray) -> Dictionary:
	var shape: Array[String] = []
	var length := ""
	var avih := _find(head, [0x61, 0x76, 0x69, 0x68])
	if avih >= 0 and avih + 8 + 40 <= head.size():
		var us := _le32(head, avih + 8)
		var frames := _le32(head, avih + 8 + 16)
		var w := _le32(head, avih + 8 + 32)
		var hgt := _le32(head, avih + 8 + 36)
		var fps := 1000000.0 / float(us) if us > 0 else 0.0
		shape.append("%dx%d at %.2f fps" % [w, hgt, fps])
		length = "%d frames (%.1fs)" % [
			frames, float(frames) / fps if fps > 0.0 else 0.0]
	var at := 0
	while true:
		at = _find(head, [0x73, 0x74, 0x72, 0x68], at)  # "strh"
		if at < 0 or at + 8 + 16 > head.size():
			break
		var kind := head.slice(at + 8, at + 12).get_string_from_ascii()
		var handler := head.slice(at + 12, at + 16).get_string_from_ascii()
		if kind == "vids":
			# `strf` for a video stream is a BITMAPINFOHEADER, so the depth and
			# the `biCompression` are here -- and 8-bit `mrle` is a different
			# proposition from 24-bit Cinepak.
			var strf := _find(head, [0x73, 0x74, 0x72, 0x66], at)
			var depth := ""
			if strf >= 0 and strf + 8 + 20 <= head.size():
				depth = ", %d-bit" % _le16(head, strf + 8 + 14)
			shape.append("video '%s'%s" % [handler, depth])
		elif kind == "auds":
			var strf := _find(head, [0x73, 0x74, 0x72, 0x66], at)
			if strf >= 0 and strf + 8 + 16 <= head.size():
				shape.append("audio tag %d, %d Hz, %d ch" % [
					_le16(head, strf + 8), _le32(head, strf + 12),
					_le16(head, strf + 10)])
			else:
				shape.append("audio")
		at += 4
	var joined := ", ".join(shape)
	return {"shape": joined, "detail": joined if length == ""
		else "%s, %s" % [joined, length]}


static func _has(data: PackedByteArray, at: int, want: Array) -> bool:
	if at + want.size() > data.size():
		return false
	for i in want.size():
		if int(data[at + i]) != int(want[i]):
			return false
	return true


## Where `want` first occurs in `data` at or after `from`, or -1.
##
## Written out rather than using `PackedByteArray.find`, which searches for a
## single byte value: passing it a subarray is a parse error and passing it the
## first byte alone would answer the wrong offset.
static func _find(data: PackedByteArray, want: Array, from: int = 0) -> int:
	var n := want.size()
	if n == 0:
		return -1
	var last := data.size() - n
	var at := maxi(from, 0)
	while at <= last:
		var hit := true
		for i in n:
			if int(data[at + i]) != int(want[i]):
				hit = false
				break
		if hit:
			return at
		at += 1
	return -1


static func _le16(d: PackedByteArray, at: int) -> int:
	return int(d[at]) | (int(d[at + 1]) << 8)


static func _le32(d: PackedByteArray, at: int) -> int:
	return _le16(d, at) | (_le16(d, at + 2) << 16)


# -------------------------------------------------------------------- walking


## One compiled matcher per token, anchored on word boundaries.
##
## Lingo's identifier characters are letters, digits and underscore, so a token
## preceded or followed by one of those is part of a longer name and not the
## property this is looking for. Built once rather than per member: there are
## sixteen tokens and 160,932 members in reach.
func _token_matchers() -> Dictionary:
	var out: Dictionary = {}
	for token in VIDEO_TOKENS:
		var re := RegEx.new()
		re.compile("(?<![a-z0-9_])%s(?![a-z0-9_])" % str(token))
		out[token] = re
	return out


func _roots(explicit: String) -> Array[String]:
	var roots: Array[String] = []
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
	return roots


func _walk_containers(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk_containers(dir_path.path_join(sub), out)


func _walk_media(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if MEDIA_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk_media(dir_path.path_join(sub), out)
