extends RefCounted
## Names **Director itself documents**, family by family, from Director's own
## dictionary rather than from ScummVM's implemented subset.
##
## `lingo_reference_names.gd` is the other half of the discriminator at
## `lingo/lingo_interpreter.gd:_call`'s fall-through, and it answers a different
## question. That file is a statement about *the reference*: the union of the four
## name tables `LC::call` consults before it aborts. This file is a statement about
## *Director*: what the language documents, whether or not `reference/scummvm/`
## implements it. `bugs.md` 123 is the entry that says why the difference decides a
## control-flow question rather than a cosmetic one.
##
## **The measured reason this file exists.** `tools/undefined_calls.gd --all` put 19
## call sites across the six shipped roots in "neither table", over 7 distinct
## names, and two of them were `gotoNetPage` -- real Director NetLingo, absent from
## the whole of `reference/scummvm/lingo/` (grep it: no `netpage`, no `netDone`, no
## `getNetText`, and the `xtras/` directory holds one letter). So with the reference
## as the only discriminator, "the reference has no table entry" meant *either*
## "the movie called a handler nobody defined" *or* "ScummVM has not got round to
## NetLingo", and a port that aborted on the second would truncate a handler
## because of a gap on ScummVM's side. That is what stopped the abort being
## implementable, and adding this table is what separates the two cases:
## `gotoNetPage` is known-to-Director-and-unbound-here, and `rating`'s `mraker`
## -- `go(mraker(1))` written directly above a correct `go(marker(0))` -- is
## undefined in Director too and stays undefined.
##
## ## Where each family came from
##
## The source is the **Macromedia Director MX Lingo Dictionary** (Macromedia's own
## reference manual, 756 pages), read through the scanned copy at
## `archive.org/details/manualzilla-id-7413404`, full text
## `7413404_djvu.txt`. Its front matter carries a chapter called **"Lingo by
## Feature"** which enumerates the language grouped into 52 topic families --
## Accessibility, Animated GIFs, ... Network Lingo, ... XML parsing, Xtra
## extensions. That chapter *is* Director's own statement of its vocabulary, in
## Director's own grouping, and every family below names the section it was read
## out of. Nothing here is inferred from what this port needs, from what the corpus
## calls, or from what ScummVM happens to implement.
##
## The Network family, the one the entry turns on, was cross-checked against a
## second, independent listing before being trusted: the NetLingo command set as
## published outside Adobe (DreamLight Director Talisman "NetLingo, Network Lingo
## Tips & Tricks", and the Columbia University R4110 "Shockwave and NetLingo"
## handout) names the same set -- `getStreamStatus`, `getLatestNetID`, `netAbort`,
## `netDone`, `netError`, `netPresent`, `netLastModDate`, `netMIME`,
## `netTextResult`, `proxyServer`, `tellStreamStatus`, `URLEncode` -- and the two
## agree name for name.
##
## ## Two rules that kept invented entries out, and cost real names
##
## **A name whose only printed occurrence is OCR-damaged is not added.** The scan
## is Tesseract over a 1990s manual and it mangles `fi` and `ll`: the Vector shapes
## section prints `illColor`, `illCycles`, `illDirection`, `illMode`, `illOffset`
## and `illScale` for the `fill*` properties, Digital video prints `movielTime` and
## `rackText`, Sound prints `fadelIn`, Bitmaps prints `movielmageQuality`, Text
## prints `fontf` and `original Font`. Repairing those would mean *I* chose the
## spelling, and this table's whole value is that it did not. So `movieTime`,
## `trackText`, the six `fill*` names, `fadeIn`, `movieImageQuality`, `font`,
## `originalFont`, `moveVertexHandle`, `getErrorString`, `runPropertyDialog` and
## `pointInHyperlink` are **missing on purpose**, and a missing name only costs a
## fidelity gap where an invented one silently turns a correct abort into a
## fall-through. `tellStreamStatus` is here despite printing as `tel1lStreamStatus`
## because the second, independent NetLingo listing spells it cleanly; that is the
## only repair, and it is a second source rather than a guess.
##
## **A name printed with an `on ` prefix is a handler the movie writes, not
## vocabulary Director answers**, and is excluded. `on cuePassed`, `on streamStatus`,
## `on EvalScript`, `on getBehaviorDescription`, `on getPropertyDescriptionList`,
## `on isOKToAttach`, `on prepareFrame` and the rest of the Events section are names
## *Director calls into the movie with*. A movie that calls one and defines none
## gets exactly the undefined-handler abort this table exists to allow, so listing
## them would suppress the correct case. `externalEvent` and `netStatus` are in the
## Network family because the dictionary prints them without the prefix in the same
## sentence that prints `on EvalScript` with it.
##
## ## What is not here
##
## Shockwave 3D. The "Lingo by Feature" chapter of this edition has no 3D section
## -- 52 families, none of them 3D -- so there is nothing to read the `member3D`,
## `model`, `shader`, `camera` vocabulary out of, and it is not invented here.
## Nothing in the six shipped roots is D8.5, so the hole costs this corpus nothing;
## it is written down because "0 uses in the corpus" is not why it is missing.
##
## Overlap with `lingo_reference_names.gd` is not trimmed. Both files answer
## membership about their own subject and the consumer asks both, so a name in the
## reference's tables *and* in Director's dictionary appears twice, which is the
## honest shape: trimming would make this file a diff against ScummVM and it would
## then rot the moment ScummVM moved.


## `Lingo by Feature` -> `Network Lingo`. The family `bugs.md` 123 is about.
## Cross-checked against the two independent NetLingo listings named in the header.
const NETWORK := [
	"downloadnetthing", "getnettext", "gotonetmovie", "gotonetpage",
	"postnettext", "preloadnetthing", "frameready", "mediaready",
	"getstreamstatus", "getlatestnetid", "netabort", "netdone", "neterror",
	"netpresent", "netlastmoddate", "netmime", "nettextresult",
	"tellstreamstatus", "urlencode", "browsername", "clearcache",
	"cachedocverify", "cachesize", "getpref", "setpref", "proxyserver",
	"netstatus", "externalevent", "netthrottleticks", "url",
]

## `Lingo by Feature` -> `Accessibility`. The Speech Xtra's voice surface, which
## the reference does not implement at all.
const ACCESSIBILITY := [
	"voicecount", "voiceget", "voicegetpitch", "voicegetrate",
	"voicegetvolume", "voiceinitialize", "voicepause", "voiceresume",
	"voiceset", "voicesetpitch", "voicesetrate", "voicesetvolume",
	"voicespeak", "voicestate", "voicestop", "voicewordpos",
	"autotab", "hilite", "keyboardfocussprite", "selectedtext", "selection",
	"selend", "selstart",
]

## `Lingo by Feature` -> `Bitmaps`, including its image-object subsections. D8's
## imaging Lingo.
const IMAGING := [
	"alphathreshold", "backcolor", "blend", "depth", "dither",
	"trimwhitespace", "imagecompression", "imagequality",
	"movieimagecompression", "forecolor", "palette", "picture", "picturep",
	"usealpha", "createmask", "creatematte", "extractalpha", "setalpha",
	"copypixels", "crop", "draw", "duplicate", "fill", "getpixel", "image",
	"rect", "setpixel",
]

## `Lingo by Feature` -> `Sound`. D8's sound-channel object and its methods.
const SOUND := [
	"channelcount", "sound", "soundbusy", "samplecount", "soundenabled",
	"volume", "isbusy", "status", "puppetsound", "breakloop", "endtime",
	"fadeout", "getplaylist", "loopcount", "loopstarttime", "member", "pause",
	"queue", "stop", "elapsedtime", "fadeto", "setplaylist", "loopendtime",
	"loopsremaining", "pan", "playnext", "rewind", "play",
]

## `Lingo by Feature` -> `Shockwave audio`.
const SHOCKWAVE_AUDIO := [
	"bitrate", "bitspersample", "copyrightinfo", "duration", "geterror",
	"numchannels", "percentplayed", "percentstreamed", "preloadtime",
	"samplerate", "soundchannel", "state", "streamname",
]

## `Lingo by Feature` -> `Flash` and `Vector shapes`. One family here because the
## dictionary gives them one shared property surface and repeats most of it in
## both sections.
const FLASH_AND_VECTOR := [
	"actionsenabled", "broadcastprops", "buffersize", "buttonsenabled",
	"bytesstreamed", "callframe", "centerregpoint", "clearerror", "clickmode",
	"defaultrect", "defaultrectmode", "directtostage", "endtelltarget",
	"eventpassmode", "findlabel", "fixedrate", "flashrect", "flashtostage",
	"framecount", "framerate", "getflashproperty", "getframelabel",
	"getvariable", "gotoframe", "pathname", "pausedatstart", "playbackmode",
	"playing", "posterframe", "print", "printasbitmap", "quality", "rotation",
	"scale", "scalemode", "setcallback", "settingspanel", "setflashproperty",
	"setvariable", "showprops", "soundmixmedia", "sourcefilename",
	"stagetoflash", "static", "hittest", "hold", "imageenabled", "linked",
	"loop", "mouseoverbutton", "newobject", "obeyscorerotation", "originh",
	"originmode", "originpoint", "originv", "stream", "streammode",
	"streamsize", "telltarget", "viewh", "viewpoint", "viewscale", "viewv",
	"clearasobjects", "addvertex", "backgroundcolor", "closed", "deletevertex",
	"curve", "regpointvertex", "gradienttype", "movevertex", "skew",
	"strokecolor", "strokewidth", "vertexlist", "newcurve", "antialias",
	"fliph", "flipv", "endcolor", "fillmode",
]

## `Lingo by Feature` -> `Text`. The field/text surface, minus the four names the
## OCR damaged (see the header).
const TEXT := [
	"delete", "put", "string", "stringp", "text", "chars", "contains", "empty",
	"itemdelimiter", "last", "length", "offset", "paragraph", "ref", "value",
	"editable", "recordfont", "bitmapsizes", "characterset", "bgcolor",
	"charspacing", "color", "dropshadow", "fontsize", "fontstyle", "alignment",
	"bottomspacing", "firstindent", "fixedlinespace", "leftindent", "margin",
	"rightindent", "tabcount", "tabs", "wordwrap", "antialiasthreshold",
	"html", "kerning", "kerningthreshold", "rtf", "pointtochar", "pointtoitem",
	"pointtoparagraph", "pointtoword", "border", "boxtype", "linecount",
	"lineheight", "pageheight", "linepostolocv", "loctocharpos",
	"locvtolinepos", "scrollbyline", "scrollbypage", "scrolltop",
]

## `Lingo by Feature` -> `XML parsing`. The XML Parser Xtra's object surface.
const XML := [
	"attributename", "attributevalue", "child", "count", "doneparsing",
	"geterror", "ignorewhitespace", "makelist", "makesublist", "name",
	"parsestring", "parseurl",
]

## `Lingo by Feature` -> `Timeouts`. D8's timeout object.
const TIMEOUTS := [
	"time", "timeoutkeydown", "timeoutlapsed", "timeoutlength", "name",
	"persistent", "timeouthandler", "timeoutmouse", "timeoutplay",
	"timeoutscript", "period", "target", "timeout", "timeoutlist", "forget",
]

## `Lingo by Feature` -> `Media synchronization`. `on cuePassed` is excluded by
## the `on ` rule in the header.
const CUE_POINTS := [
	"cuepointnames", "cuepointtimes", "mostrecentcuepoint", "ispastcuepoint",
]

## `Lingo by Feature` -> `Parent scripts`.
const PARENT_SCRIPTS := [
	"actorlist", "property", "ancestor", "new", "handlers", "rawnew",
	"handler",
]

## `Lingo by Feature` -> `Xtra extensions`.
const XTRAS := ["moviextralist", "xtra", "xtralist", "xtras"]

## `Lingo by Feature` -> `Digital video`. `movieTime` and `trackText` are missing
## here for the OCR reason in the header, and both are real Director properties;
## that is the cost of the rule, recorded rather than smoothed over.
const DIGITAL_VIDEO := [
	"controller", "digitalvideotimescale", "digitalvideotype",
	"tracknextsampletime", "trackpreviouskeytime", "trackprevioussampletime",
	"trackstarttime", "trackstoptime", "quicktimeversion", "tracktype",
	"trackcount", "timescale", "trackenabled", "video",
	"videoforwindowspresent", "movierate", "resume",
]

## `Lingo by Feature` -> `Memory management`.
const MEMORY := [
	"cancelidleload", "finishidleload", "freeblock", "freebytes",
	"idlehandlerperiod", "idleloaddone", "idleloadperiod", "idleloadtag",
	"idlereadchunksize", "loaded", "memorysize", "moviefilefreesize",
	"moviefilesize", "preload", "preloadbuffer", "preloadeventabort",
	"preloadmode", "preloadmember", "preloadmovie", "preloadram",
	"purgepriority", "ramneeded", "size", "unload", "unloadmember",
	"unloadmovie",
]

## `Lingo by Feature` -> `Movies`, `Casts`, `Cast members`, `Score`, `Sprites`,
## `Movies in a window`, `Projectors`, `Monitor`, `Stage`, `Time`, `Transitions`,
## `Variables`, `Palettes and color`, `Mouse interaction`, `Message window`,
## `Navigation`, `Lists`, `Points and rectangles`, `Data types`, `Lingo`,
## `Computer and operating system`, `External files`, `Interface elements`,
## `Keys`, `Frames`, `Menus`, `Puppets`, `Random numbers`, `Shapes`, `Tempo`,
## `Multiuser server`, `Communication between movies`, `Animation`,
## `Animated GIFs`, `Operators`.
##
## **Almost all of these families are already inside the reference's four tables**,
## which is the expected result and worth stating: ScummVM's coverage of Director's
## *core* is close to complete, and the divergence that made this file necessary is
## concentrated in the families above -- network, speech, imaging, the D8 sound
## object, Flash and vector shapes, XML. What is listed here is only the residue:
## names read out of those sections that the reference's tables do not hold. They
## are kept together rather than split into thirty near-empty families because the
## family is not what a caller asks about; the section each came from is in the
## sentence above, and the run that produced the residue is
## `tools/undefined_calls.gd --all`.
const CORE_RESIDUE := [
	"linkas", "moviefileversion", "comments", "creationdate", "modifiedby",
	"modifieddate", "seconds", "environment", "scorecolor", "scriptnum",
	"scripttype", "markerlist", "media", "modified", "regpoint", "center",
	"constraint", "quad", "trails", "tweened", "puppet", "activecastlib",
	"appminimize", "title", "titlevisible", "modal", "drawrect", "sourcerect",
	"windowtype", "editshortcutsenabled", "systemdate", "milliseconds",
	"long", "short", "abbr", "abbrev", "abbreviated", "changearea",
	"chunksize", "transitiontype", "globals", "rgb", "mouseloc", "deleteall",
	"filled", "linedirection", "linesize", "pattern", "shapetype",
	"scriptsenabled", "scripttext", "number", "type", "loc", "loch", "locv",
	"height", "width", "bottom", "left", "right", "top", "ink", "membernum",
	"castlibnum", "enabled", "buttontype", "checkmark", "flushinputevents",
	"keypressed",
]
## `duplicate member`, `erase member`, `move member` and `save castLib` are
## printed as **two-word commands** in the Cast members and Casts sections and are
## deliberately not folded into `duplicatemember`, `erasemember`, `movemember` and
## `savecastlib`. The folded spellings are not what the dictionary prints, and a
## single-word call site would be a different statement; inventing four names to
## make the list look complete is the failure this file's header is about.


## Every family, in one place, so `knows` is one lookup and a reader can see the
## whole set without reading the arrays.
##
## Built once on first use rather than written out as a literal: a hand-merged
## `KNOWN` would have to be re-merged by hand every time a family gained a name,
## and the merge is exactly the step where a name goes missing without anyone
## noticing. The families above are the source of truth and this is derived.
static var _index: Dictionary = {}

const FAMILIES := {
	"network": NETWORK,
	"accessibility": ACCESSIBILITY,
	"imaging": IMAGING,
	"sound": SOUND,
	"shockwave_audio": SHOCKWAVE_AUDIO,
	"flash_and_vector": FLASH_AND_VECTOR,
	"text": TEXT,
	"xml": XML,
	"timeouts": TIMEOUTS,
	"cue_points": CUE_POINTS,
	"parent_scripts": PARENT_SCRIPTS,
	"xtras": XTRAS,
	"digital_video": DIGITAL_VIDEO,
	"memory": MEMORY,
	"core_residue": CORE_RESIDUE,
}


## Does Director document this name?
##
## Lowercased, like `lingo_reference_names.gd:knows`, because Lingo is
## case-insensitive and both tables are stored folded.
static func knows(name: String) -> bool:
	if _index.is_empty():
		_build()
	return _index.has(name.to_lower())


## Which family a name came from, or "" -- for a diagnostic that wants to say
## *why* a name is known rather than only that it is.
static func family_of(name: String) -> String:
	if _index.is_empty():
		_build()
	return str(_index.get(name.to_lower(), ""))


static func size() -> int:
	if _index.is_empty():
		_build()
	return _index.size()


static func _build() -> void:
	for family in FAMILIES:
		for name in (FAMILIES[family] as Array):
			# First family wins, so a name in two sections reports the section it
			# is most specific to. Nothing depends on which; `knows` is the only
			# question with a control-flow consequence.
			if not _index.has(str(name)):
				_index[str(name)] = str(family)
