extends RefCounted
class_name GarlicLspSchemaRegistry

const REFRESH_INTERVAL_MS = 30000

var nodes: Dictionary = {}
var refreshedAt: int = -REFRESH_INTERVAL_MS

func refresh() -> void:
	nodes = {}
	if not ProjectSettings.has_setting("importer_defaults/%s" % ShrimpCompiler.IMPORTER_ID):
		return
	for ir in ShrimpVMUtil.get_configured_irs():
		if ir == null or ir.is_hidden():
			continue
		var schema: Dictionary = ir.get_wrapper_schema()
		nodes[ir.get_node_type()] = {
			"type": ir.get_node_type(),
			"category": ir.get_category_tag(),
			"name": schema.get("name", ir.get_node_type()),
			"description": schema.get("description", ""),
			"attributes": schema.get("attributes", {})
		}
func ensure_fresh() -> void:
	if Time.get_ticks_msec() - refreshedAt >= REFRESH_INTERVAL_MS:
		refresh()
		refreshedAt = Time.get_ticks_msec()
func get_node(nodeType: String) -> Dictionary:
	ensure_fresh()
	return nodes.get(nodeType, {})
func get_nodes() -> Array:
	ensure_fresh()
	var list = nodes.values()
	list.sort_custom(func(a, b): return a["type"] < b["type"])
	return list
func get_attribute(nodeType: String, key: String) -> Dictionary:
	return get_node(nodeType).get("attributes", {}).get(key, {})
