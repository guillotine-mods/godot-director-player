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
##
## **Weak, and that is the whole of the fix for the leak every run used to
## print.** The host builds this registry in its own `_init` and passes `self`
## (`preview_lingo_host.gd:438`), so a strong field here is a two-object
## `RefCounted` cycle -- the host owns the Xtra, the Xtra owns the host -- and
## Godot has no cycle collector. Neither side was ever freed, which pinned four
## GDScripts (this one, the host, and the two `factory` scripts) and made every
## clean exit end with `4 resources still in use` plus three leaked instances
## *per host constructed*. `boot.gd:start_lingo` builds a fresh host per movie,
## which is why the leak count grew with the length of the run.
##
## Weak rather than a teardown call, because the direction of ownership is a
## permanent fact and not a moment: the preview node owns the interpreter and the
## host, the host owns this registry, and the registry must not own the host
## back. A teardown re-asserts that at one point in time, and the points it would
## have to be reached from include a `tools/` harness that never adds the preview
## to the tree and `lingo_quit`, which does not take the tree down under
## `--script`. `NOTIFICATION_PREDELETE` cannot help either: it does not fire for
## an object that is leaked, which is the thing being fixed.
##
## The *instance's* `host` stays strong (`make_xtra_instance` below) and is not
## part of any cycle: nothing in the host holds an instance, and a FileIO
## instance parked in a Lingo global -- which `start_lingo` carries across movie
## boundaries -- then keeps the host that made it alive for exactly as long as
## the script can still reach it, and both die together afterwards.
var _host_ref: WeakRef = null


func _init(xtra_name: String = "", from: GDScript = null, for_host: Object = null) -> void:
	name = xtra_name
	factory = from
	_host_ref = weakref(for_host) if for_host != null else null


## The host, or null once it has gone. Every reader has to handle the null, which
## was already true of the no-host harness case this field documents.
func host_object() -> Object:
	return null if _host_ref == null else _host_ref.get_ref() as Object


func xtra_name() -> String:
	return name


## `new(xtra("FileIO"))`. The interpreter finds this by name rather than by type,
## which is what keeps `lingo_interpreter.gd` from having to know what an Xtra is.
func make_xtra_instance(args: Array) -> Variant:
	if factory == null:
		return null
	var instance = factory.new()
	instance.set("host", host_object())
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
