extends RefCounted
## An Xtra as the registry holds it, and the protocol every native object in this
## port answers (§7.3).
##
## Two objects, not one, because Director has two and scripts can tell them
## apart:
##
##   `xtra("FileIO")`        the **Xtra itself** — what this class is. It is what
##                           `the xtras` lists and what `new` is applied to.
##   `new(xtra("FileIO"))`   an **instance**, which is what every method call
##                           takes as its first argument.
##
## Collapsing the two would make `openFile(xtra("FileIO"), …)` work, which
## Director refuses, and would give every movie one shared file handle.
##
## ## The protocol
##
## A native object -- an Xtra instance, and anything else this port grows later
## -- answers three methods, and nothing in `lingo/` may assume more:
##
##   `lingo_responds_to(name) -> bool`     what `respondsTo` asks
##   `lingo_message_list() -> Array`       what `messageList` answers
##   `lingo_perform(name, args) -> Array`  `[]` for "not mine", `[value]` for
##                                         "handled, and this is the answer"
##
## The one-element-Array return is the same shape `lingo_builtins.gd` uses for
## `handled`, and for the same reason: VOID is a legitimate answer and `null`
## cannot also mean "no such method". §7.3 is explicit that a stubbed Xtra has to
## answer the standard set because scripts probe with `respondsTo` before
## calling, so a native object that cannot say "not mine" is one that lies.

## The Xtra's registered name, normalised by `preview_lingo_host.gd:xtra_key` on
## both sides of the lookup so `FileIO.x32`, `Macintosh HD:Xtras:FileIO` and
## `fileio` are one Xtra.
var name := ""
## The script an instance is made from. `new()` on it is the whole of
## instantiation; the Xtra has no per-class state of its own.
var factory: GDScript = null
## Handed to every instance so it can reach the movie -- paths, the search list,
## the write guard. Null in a harness that builds an Xtra on its own, and every
## instance method has to survive that.
var host: Object = null


func _init(xtra_name: String = "", from: GDScript = null, for_host: Object = null) -> void:
	name = xtra_name
	factory = from
	host = for_host


func xtra_name() -> String:
	return name


## `new(xtra("FileIO"))`. The interpreter finds this by name rather than by type,
## which is what keeps `lingo_interpreter.gd` from having to know what an Xtra is.
func make_xtra_instance(args: Array) -> Variant:
	if factory == null:
		return null
	var instance = factory.new()
	instance.set("host", host)
	# Director's `new` on an Xtra runs the Xtra's own constructor, and FileIO's
	# takes no arguments. An Xtra that wants them reads them here.
	if instance.has_method("xtra_new"):
		instance.call("xtra_new", args)
	return instance


## The Xtra object itself answers nothing but its own identity. A movie that
## sends it a method is asking the *class* to read a file, which Director
## answers with a script error; VOID plus a report is the closest this port has.
func lingo_responds_to(method: String) -> bool:
	return method.to_lower() == "name"


func lingo_message_list() -> Array:
	return ["name"]


func lingo_perform(method: String, _args: Array) -> Array:
	if method.to_lower() == "name":
		return [name]
	return []


## Whether a value is a native object of this protocol -- an Xtra or an instance
## of one. The test every caller needs and none should spell for itself.
static func is_native(value: Variant) -> bool:
	return value is Object and (value as Object).has_method("lingo_perform") \
		and (value as Object).has_method("lingo_responds_to")


func _to_string() -> String:
	return "<Xtra \"%s\">" % name
