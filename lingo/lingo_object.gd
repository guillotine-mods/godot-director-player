extends RefCounted
## A Lingo **script object** — one instance of a parent script or a behaviour
## (`docs/LINGO_SURFACE.md` §7.1, §7.2).
##
## Director's object model is small and this is the whole of it: an object is a
## script plus a bag of *properties*, and one of those properties — `ancestor` —
## is the inheritance chain. There is no class, no vtable and no separate type;
## `new(script "foo")` copies nothing but the handler list it points at, and
## `me` inside a handler is this object.
##
## **Two lookups walk the ancestor chain and they are not the same walk.**
##
##   `resolve(name)`  a message not answered by this script is offered to the
##                    ancestor, and to its ancestor, and so on. That is the
##                    inheritance half.
##   `slot_owner(n)`  a *property* not declared on this object is read and
##                    written on the ancestor. Director really does this — an
##                    ancestor's property is visible to the child by its bare
##                    name — and it is the half that is easy to leave out,
##                    because a child that declares the same name shadows it and
##                    the two then look identical from inside the child.
##
## **`ancestor` is an ordinary property**, not a field beside them. Director has
## no `setAncestor`: a parent script writes `property ancestor` at the top and
## `ancestor = new(script "base")` in its `new` handler, so the chain is whatever
## that property currently holds. Keeping it as a field as well would give two
## answers to one question the first time a script assigned it.
##
## Cycles are refused rather than trusted. `me.ancestor = me` is a movie's
## mistake and not this port's, and without a guard it is an infinite walk inside
## a message dispatch — so both walks are depth-capped and the cap is named.

## How far an ancestor chain may go before this stops following it.
##
## Director documents no limit; this is a runaway guard in the same spirit as
## `LingoInterpreter.MAX_STEPS`, sized far above any real hierarchy (three or
## four deep is a deep one) so that it can only ever be reached by a cycle.
const MAX_ANCESTORS := 32

## The property Director reads the inheritance chain out of.
const ANCESTOR := "ancestor"

## The compiled script this is an instance of: `{"script":, "handlers":,
## "properties":, "globals":, "body":}`, exactly as `lingo_parser.gd` produces
## and `LingoInterpreter._scripts` stores.
var ast: Dictionary = {}
## Which compiled cast the script came from, so a handler running on this object
## resolves *its* movie's other scripts. Empty for an object built from an AST
## with no cast behind it, which is what a harness does.
var cast := ""
## Instance variables, lower-cased. Seeded from the script's `property` and
## `instance` declarations at VOID, which is what Director gives an unassigned
## one — not 0, because `if the ancestor of me then` must be false before a
## `new` handler has assigned it.
var props: Dictionary = {}


func _init(from_script: Dictionary = {}, from_cast: String = "") -> void:
	ast = from_script
	cast = from_cast
	for name in from_script.get("properties", []):
		props[str(name).to_lower()] = null


## The script's authored name — `"ParentScript 12"`, `"BehaviorScript 108"`.
func script_name() -> String:
	return str(ast.get("script", ""))


## Is this value one of these? The type test every caller needs and none should
## spell for itself: a Lingo value may be an Array, a Dictionary or a Godot
## object that is *not* one of these (a window handle is one), and `is
## RefCounted` alone would let those through.
static func is_object(value: Variant) -> bool:
	return value is RefCounted and (value as Object).has_method("script_name") \
		and (value as Object).has_method("slot_owner")


## The object this one inherits from, or null. Never a non-object.
func ancestor() -> Variant:
	var value: Variant = props.get(ANCESTOR, null)
	return value if is_object(value) else null


## The handler `name` answers with, and the object it belongs to:
## `[object, handler]`, or `[]` when nothing in the chain declares it.
##
## The object travels with the handler because `me` inside an inherited handler
## is **the ancestor**, not the child — that is what makes an ancestor's own
## `property` declarations reachable from its own code after a child has called
## into it.
func resolve(name: String) -> Array:
	var key := name.to_lower()
	var at: Variant = self
	for _hop in MAX_ANCESTORS:
		if at == null:
			return []
		for handler in (at.ast as Dictionary).get("handlers", []):
			if str((handler as Dictionary).get("name", "")).to_lower() == key:
				return [at, handler]
		at = at.ancestor()
	return []


## Whether this object, or anything it inherits from, declares `name`.
func has_slot(name: String) -> bool:
	return not slot_owner(name).is_empty()


## `[object]` holding the property `name`, or `[]`. The chain walk the property
## half of §7.1 describes — a child's own declaration shadows an ancestor's, and
## an undeclared name belongs to nobody rather than being created on read.
func slot_owner(name: String) -> Array:
	var key := name.to_lower()
	var at: Variant = self
	for _hop in MAX_ANCESTORS:
		if at == null:
			return []
		if (at.props as Dictionary).has(key):
			return [at]
		at = at.ancestor()
	return []


## Read a property through the chain. VOID for a name nobody declares, which is
## the same answer Director gives for an unassigned one — a caller that needs to
## tell the two apart asks `has_slot`.
func get_slot(name: String) -> Variant:
	var owner := slot_owner(name)
	if owner.is_empty():
		return null
	var holder: Variant = owner[0]
	return (holder.props as Dictionary).get(name.to_lower(), null)


## Write a property through the chain. Returns false when no object in the chain
## declares the name, so the caller can fall through to its own scope rather than
## inventing an instance variable — Director's `property` statement is the only
## thing that creates one.
func set_slot(name: String, value: Variant) -> bool:
	var owner := slot_owner(name)
	if owner.is_empty():
		return false
	var holder: Variant = owner[0]
	(holder.props as Dictionary)[name.to_lower()] = value
	return true


## Declare a property on *this* object, at VOID unless it already exists. What a
## `property x` statement inside a handler does.
func declare(name: String) -> void:
	var key := name.to_lower()
	if not props.has(key):
		props[key] = null


## Every property name this object answers to, its own and its ancestors',
## child-first. `the ancestor` is one of them: Director lists it too.
func slot_names() -> Array:
	var out: Array = []
	var at: Variant = self
	for _hop in MAX_ANCESTORS:
		if at == null:
			break
		for key in (at.props as Dictionary):
			if not out.has(key):
				out.append(key)
		at = at.ancestor()
	return out


## `put me` — Director prints `<offspring "ScriptName" 2 4a1b20>`. The identity
## suffix here is this port's own object id rather than Director's heap address,
## which no title can depend on and which still makes two instances of one script
## tell themselves apart in a trace.
func _to_string() -> String:
	return "<offspring \"%s\" %d>" % [script_name(), get_instance_id()]
