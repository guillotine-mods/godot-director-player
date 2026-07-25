class_name NavActions
extends RefCounted
## Resolve exported Lingo navigation intents into concrete runtime actions.


static func _s(v: Variant, fallback: String = "") -> String:
	if v == null:
		return fallback
	return str(v)


static func resolve(nav: Variant, loader: RenderModelLoader, frame_index: int) -> Dictionary:
	if typeof(nav) != TYPE_DICTIONARY or nav.is_empty():
		return {}
	var kind := _s(nav.get("kind", "")).to_lower()
	match kind:
		"hold":
			return {"kind": "hold"}
		"quit", "exit":
			return {"kind": "quit"}
		"label", "go":
			var label := _s(nav.get("value", ""))
			var idx := loader.resolve_label(label, false)
			if idx < 0:
				return {"kind": "hold"}
			return {"kind": "frame", "index": idx, "label": label}
		"frame":
			return {"kind": "frame", "index": maxi(0, int(nav.get("value", 1)) - 1)}
		"marker":
			var idx := resolve_marker_frame(loader, frame_index, int(nav.get("rel", 0)), int(nav.get("offset", 0)))
			if idx < 0:
				return {"kind": "hold"}
			return {"kind": "frame", "index": idx}
		"movie":
			return {
				"kind": "movie",
				"movie": _s(nav.get("value", "")),
				"frame": nav.get("frame", null),
				"label": nav.get("label", null),
				"arrive_at": nav.get("arrive_at", null),
				"newsyz": nav.get("newsyz", null),
			}
		"walk":
			return {"kind": "walk", "nav": nav}
		"walk_here":
			return {"kind": "walk_here", "nav": nav}
		"unsupported":
			return {"kind": "unsupported", "value": nav.get("value", "")}
		_:
			return {}


static func resolve_marker_frame(loader: RenderModelLoader, frame_index: int, rel: int, offset: int = 0) -> int:
	var markers: Array = loader.markers
	if markers.is_empty():
		return -1
	var base := -1
	for i in markers.size():
		var m: Dictionary = markers[i]
		if int(m.get("frame", 0)) <= frame_index:
			base = i
		else:
			break
	var target_idx: int
	if base < 0:
		target_idx = mini(maxi(rel - 1, 0), markers.size() - 1) if rel > 0 else 0
	else:
		target_idx = clampi(base + rel, 0, markers.size() - 1)
	return int(markers[target_idx].get("frame", 0)) + offset


static func describe(nav: Variant) -> String:
	if typeof(nav) != TYPE_DICTIONARY:
		return "none"
	var kind := _s(nav.get("kind", "?"))
	match kind:
		"movie":
			return "movie %s" % _s(nav.get("value", ""))
		"label", "go":
			return "label %s" % _s(nav.get("value", ""))
		"walk":
			return "walk → %s" % _s(nav.get("target_label", "?"))
		"walk_here":
			return "walk here"
		"frame":
			return "frame %s" % _s(nav.get("value", ""))
		"marker":
			return "marker rel=%s" % _s(nav.get("rel", 0))
		"quit":
			return "quit"
		"hold":
			return "hold"
		_:
			return kind
