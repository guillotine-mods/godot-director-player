extends RefCounted
## Every name the reference resolves *without* aborting, derived from its own
## tables.
##
## This exists for one decision, made at `lingo_interpreter.gd:_call`'s
## fall-through: a call that resolved nowhere is either **a handler the movie
## does not define** -- which the reference ends with
## `lingoError("Call to undefined handler ...")`, setting `_abort` -- or **a
## builtin this port has not bound yet**, which the reference answers normally
## and which must therefore keep answering here. The two are indistinguishable at
## that site without a list of what the reference knows, and treating a port hole
## as an undefined handler would abort a dispatch because of a gap on our side.
## That is the failure mode `bugs.md` 123 was filed to avoid.
##
## `LC::call(const String &name, ...)` (`reference/scummvm/lingo/lingo-code.cpp:
## 1647`) tries, in order: a factory/XObject method, a script/Xtra method, a
## method on `me`, `getHandler`, `_builtinListHandlers`, `_builtinFuncs` /
## `_builtinCmds`, and then `_theEntities` as a function. `LC::call(const Symbol
## &, ...)` then checks `_theEntities` **again** for a zero-argument call before
## it aborts -- and that second check does *not* test `isFunction`, so every
## entity name answers a bare call rather than aborting. Only after all of that
## does the abort happen. So the set below is the union of the four name tables
## those lookups read:
##
## | table | file | names |
## |---|---|---|
## | `builtins` | `lingo-builtins.cpp:56` | 201 |
## | `entities` | `lingo-the.cpp` | 151 |
## | `predefinedMethods` | `lingo-object.cpp:205` | 11 |
## | `windowMethods` | `lingo-object.cpp:226` | 5 |
##
## 360 distinct after lowercasing and overlap. **Version gating is deliberately
## not applied.** The reference skips a table row whose `version` exceeds the
## movie's, so a D6-only builtin called from a D4 movie *does* abort there. Honouring
## that would make the abort fire on names this port might well bind, and the
## conservative direction here is the one that aborts less: a missed abort is a
## fidelity gap, a wrong abort truncates a handler.
##
## Not the port's own surface. `lingo_builtins.gd`, `_own_builtin` and the host
## bindings are what the port answers, and a name any of them answers never
## reaches the fall-through at all -- so this list does not need to agree with
## them and must not be maintained against them. It is a statement about the
## reference, and it moves only when `reference/scummvm/` does.
##
## The chunk keywords (`char`, `line`, `word`, `item`) are absent on purpose:
## they are designators in the grammar, not entries in any of the four tables, and
## they never reach a call site.


## Lowercased. A Dictionary rather than an Array because the only question asked
## of it is membership, on a path that is already the slow one.
const KNOWN := {
	"abort": true, "abs": true, "activewindow": true, "actorlist": true,
	"add": true, "addat": true, "addprop": true, "alert": true,
	"alerthook": true, "append": true, "applicationpath": true, "atan": true,
	"backspace": true, "beep": true, "beepon": true, "beginrecording": true,
	"birth": true, "buttonstyle": true, "call": true, "callancestor": true,
	"cancelidleload": true, "cast": true, "castlib": true, "castlibs": true,
	"castmembers": true, "centerstage": true, "charpostoloc": true, "chars": true,
	"chartonum": true, "checkboxaccess": true, "checkboxtype": true, "chunk": true,
	"clearframe": true, "clearglobals": true, "clickloc": true, "clickon": true,
	"close": true, "closeda": true, "closeresfile": true, "closexlib": true,
	"colordepth": true, "colorqd": true, "commanddown": true, "constrainh": true,
	"constrainv": true, "continue": true, "controldown": true, "copytoclipboard": true,
	"cos": true, "count": true, "cpuhogticks": true, "currentspritenum": true,
	"cursor": true, "date": true, "delay": true, "deleteat": true,
	"deleteframe": true, "deleteone": true, "deleteprop": true, "describe": true,
	"desktoprectlist": true, "digitalvideotimescale": true, "dispose": true, "do": true,
	"dontpassevent": true, "doubleclick": true, "duplicate": true, "duplicateframe": true,
	"editabletext": true, "empty": true, "emulatemultibuttonmouse": true, "endrecording": true,
	"enter": true, "erase": true, "exitlock": true, "exp": true,
	"externalparamcount": true, "externalparamname": true, "externalparamvalue": true, "factory": true,
	"false": true, "field": true, "findempty": true, "findpos": true,
	"findposnear": true, "finishidleload": true, "fixstagesize": true, "float": true,
	"floatp": true, "floatprecision": true, "forget": true, "frame": true,
	"framelabel": true, "framepalette": true, "frameready": true, "framescript": true,
	"framesound1": true, "framesound2": true, "framestohms": true, "frametempo": true,
	"frametransition": true, "freeblock": true, "freebytes": true, "frontwindow": true,
	"fullcolorpermit": true, "get": true, "getaprop": true, "getat": true,
	"getlast": true, "getnthfilenameinfolder": true, "getone": true, "getpos": true,
	"getpref": true, "getprop": true, "getpropat": true, "getvolumes": true,
	"go": true, "halt": true, "hmstoframes": true, "idlehandlerperiod": true,
	"idleloaddone": true, "idleloadmode": true, "idleloadperiod": true, "idleloadtag": true,
	"idlereadchunksize": true, "ilk": true, "imagedirect": true, "immediatesprite": true,
	"importfileinto": true, "inflate": true, "insertframe": true, "inside": true,
	"installmenu": true, "instancerespondsto": true, "integer": true, "integerp": true,
	"intersect": true, "ispastcuepoint": true, "itemdelimiter": true, "key": true,
	"keycode": true, "keydownscript": true, "keypressed": true, "keyupscript": true,
	"label": true, "labellist": true, "lastclick": true, "lastevent": true,
	"lastframe": true, "lastkey": true, "lastroll": true, "length": true,
	"lineheight": true, "linepostolocv": true, "list": true, "listp": true,
	"loctocharpos": true, "locvtolinepos": true, "log": true, "machinetype": true,
	"map": true, "marker": true, "max": true, "maxinteger": true,
	"mci": true, "mciwait": true, "member": true, "memorysize": true,
	"menu": true, "menuitem": true, "menuitems": true, "messagelist": true,
	"min": true, "mousecast": true, "mousechar": true, "mousedown": true,
	"mousedownscript": true, "mouseh": true, "mouseitem": true, "mouseline": true,
	"mousemember": true, "mouseup": true, "mouseupscript": true, "mousev": true,
	"mouseword": true, "move": true, "moveablesprite": true, "movetoback": true,
	"movetofront": true, "movie": true, "moviefilefreesize": true, "moviefilesize": true,
	"moviename": true, "moviepath": true, "multisound": true, "name": true,
	"netthrottleticks": true, "new": true, "nothing": true, "numberofchars": true,
	"numberofitems": true, "numberoflines": true, "numberofwords": true, "numtochar": true,
	"objectp": true, "offset": true, "open": true, "openda": true,
	"openresfile": true, "openxlib": true, "optiondown": true, "organizationname": true,
	"palettemapping": true, "param": true, "paramcount": true, "pass": true,
	"pasteclipboardinto": true, "pathname": true, "pause": true, "pausestate": true,
	"perform": true, "perframehook": true, "pi": true, "picturep": true,
	"platform": true, "play": true, "playaccel": true, "point": true,
	"power": true, "preload": true, "preloadcast": true, "preloadeventabort": true,
	"preloadmember": true, "preloadmovie": true, "preloadram": true, "printfrom": true,
	"productname": true, "productversion": true, "puppetpalette": true, "puppetsound": true,
	"puppetsprite": true, "puppettempo": true, "puppettransition": true, "put": true,
	"quicktimepresent": true, "quit": true, "quote": true, "ramneeded": true,
	"random": true, "randomseed": true, "rect": true, "respondsto": true,
	"restart": true, "result": true, "return": true, "rightmousedown": true,
	"rightmouseup": true, "rollover": true, "romanlingo": true, "runmode": true,
	"safeplayer": true, "save": true, "savemovie": true, "score": true,
	"scoreselection": true, "script": true, "scrollbyline": true, "scrollbypage": true,
	"scummvmassert": true, "scummvmassertequal": true, "scummvmnofatalerror": true, "scummvmversion": true,
	"searchcurrentfolder": true, "searchpath": true, "searchpaths": true, "selection": true,
	"selend": true, "selstart": true, "send": true, "sendallsprites": true,
	"sendancestor": true, "sendsprite": true, "serialnumber": true, "setaprop": true,
	"setat": true, "setcallback": true, "setpref": true, "setprop": true,
	"shiftdown": true, "showglobals": true, "showlocals": true, "showresfile": true,
	"showxlib": true, "shutdown": true, "sin": true, "sort": true,
	"sound": true, "soundbusy": true, "sounddevice": true, "soundenabled": true,
	"soundkeepdevice": true, "soundlevel": true, "sprite": true, "spritebox": true,
	"sqrt": true, "stage": true, "stagebottom": true, "stagecolor": true,
	"stageleft": true, "stageright": true, "stagetop": true, "starttimer": true,
	"stilldown": true, "stopevent": true, "string": true, "stringp": true,
	"switchcolordepth": true, "symbol": true, "symbolp": true, "tab": true,
	"tan": true, "ticks": true, "time": true, "timeoutkeydown": true,
	"timeoutlapsed": true, "timeoutlength": true, "timeoutmouse": true, "timeoutplay": true,
	"timeoutscript": true, "timer": true, "trace": true, "traceload": true,
	"tracelogfile": true, "trackcount": true, "trackstarttime": true, "trackstoptime": true,
	"tracktype": true, "true": true, "union": true, "unload": true,
	"unloadcast": true, "unloadmember": true, "unloadmovie": true, "updateframe": true,
	"updatelock": true, "updatemovieenabled": true, "updatestage": true, "username": true,
	"value": true, "version": true, "videoforwindowspresent": true, "void": true,
	"voidp": true, "window": true, "windowlist": true, "windowpresent": true,
	"xfactorylist": true, "xtra": true, "xtras": true, "zoombox": true,
}


static func knows(name: String) -> bool:
	return KNOWN.has(name.to_lower())
