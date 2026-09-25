extends RefCounted
class_name GarlicLspFeatures

var registry: GarlicLspSchemaRegistry
var analyzer: GarlicLspAnalyzer

func _init(registryX: GarlicLspSchemaRegistry, analyzerX: GarlicLspAnalyzer) -> void:
	registry = registryX
	analyzer = analyzerX

func completion(text: String, line: int, character: int) -> Array:
	var tokens = analyzer.tokenize(text)
	var located = analyzer.locate(tokens, line, character)
	if located["insideString"]:
		return []
	var context = analyzer.resolve_context(located["tokens"])
	match context["kind"]:
		"node_name":
			return node_items()
		"key":
			return key_items(context)
		"value":
			return value_items(context)
		"array_item":
			return array_items(context)
		_:
			return []
func hover(text: String, line: int, character: int):
	var tokens = analyzer.tokenize(text)
	var located = analyzer.locate(tokens, line, character)
	if located["insideString"] or not located["hasToken"]:
		return null
	var word: String = located["filterText"]
	var cursorIndex: int = located["tokens"].size()
	if cursorIndex + 1 < tokens.size():
		var nextToken = tokens[cursorIndex + 1]
		if nextToken.type == GarlicLexer.TokenType.PUNCT and nextToken.value == "(":
			return node_hover(word)
	var context = analyzer.resolve_context(located["tokens"])
	if context["kind"] == "key":
		return key_hover(context["nodeType"], word)
	return node_hover(word)
func node_items() -> Array:
	var items: Array = []
	for meta in registry.get_nodes():
		var documentation: String = meta.get("description", "")
		var attrLines: Array = []
		for key in meta.get("attributes", {}):
			var attr: Dictionary = meta["attributes"][key]
			attrLines.append("- `%s`: %s%s — %s" % [key, type_label(attr.get("type")), array_suffix(attr), attr.get("label", "")])
		if not attrLines.is_empty():
			documentation += "\n\n" + "\n".join(PackedStringArray(attrLines))
		items.append({
			"label": meta["type"],
			"kind": 3,
			"detail": "%s · %s" % [meta.get("category", ""), meta.get("name", "")],
			"documentation": {"kind": "markdown", "value": documentation}
		})
	return items
func key_items(context: Dictionary) -> Array:
	var meta = registry.get_node(context["nodeType"])
	if meta.is_empty():
		return []
	var seen: Array = context.get("seenKeys", [])
	var items: Array = []
	for key in meta.get("attributes", {}):
		if key in seen:
			continue
		var attr: Dictionary = meta["attributes"][key]
		items.append({
			"label": key,
			"kind": 5,
			"detail": "%s%s" % [type_label(attr.get("type")), array_suffix(attr)],
			"documentation": {"kind": "markdown", "value": attr.get("label", "")},
			"insertText": "%s=" % key
		})
	return items
func value_items(context: Dictionary) -> Array:
	var attr = registry.get_attribute(context["nodeType"], context["key"])
	if attr.is_empty():
		return []
	var type = attr.get("type")
	if type == ShrimpIR.TYPE_ENUM or type == ShrimpIR.TYPE_EXTERNAL_PARAMETER:
		return node_items()
	if type == Variant.Type.TYPE_BOOL:
		return [
			{"label": "true", "kind": 12, "detail": "bool"},
			{"label": "false", "kind": 12, "detail": "bool"}
		]
	if type == Variant.Type.TYPE_STRING:
		return [literal_item("\"$1\"", "string")]
	if type == Variant.Type.TYPE_STRING_NAME:
		return [literal_item("「$1」", "string_name")]
	return []
func array_items(context: Dictionary) -> Array:
	var attr = registry.get_attribute(context["nodeType"], context["key"])
	if attr.is_empty():
		return []
	var type = attr.get("type")
	if type == Variant.Type.TYPE_BOOL:
		return [
			{"label": "true", "kind": 12, "detail": "bool"},
			{"label": "false", "kind": 12, "detail": "bool"}
		]
	if type == Variant.Type.TYPE_STRING:
		return [literal_item("\"$1\"", "string")]
	if type == Variant.Type.TYPE_STRING_NAME:
		return [literal_item("「$1」", "string_name")]
	return []
func literal_item(insertText: String, detail: String) -> Dictionary:
	return {
		"label": insertText,
		"kind": 12,
		"detail": detail,
		"insertText": insertText,
		"insertTextFormat": 2
	}
func node_hover(nodeType: String):
	var meta = registry.get_node(nodeType)
	if meta.is_empty():
		return null
	var lines: Array = ["**%s** `%s`" % [meta.get("name", nodeType), nodeType]]
	var description: String = meta.get("description", "")
	if not description.is_empty() and description != "No descritpion.":
		lines.append("")
		lines.append(description)
	for key in meta.get("attributes", {}):
		var attr: Dictionary = meta["attributes"][key]
		lines.append("- `%s`: %s%s — %s" % [key, type_label(attr.get("type")), array_suffix(attr), attr.get("label", "")])
	return {"contents": {"kind": "markdown", "value": "\n".join(PackedStringArray(lines))}}
func key_hover(nodeType: String, key: String):
	var attr = registry.get_attribute(nodeType, key)
	if attr.is_empty():
		return null
	var value = "`%s`: %s%s — %s" % [key, type_label(attr.get("type")), array_suffix(attr), attr.get("label", "")]
	return {"contents": {"kind": "markdown", "value": value}}
func type_label(type) -> String:
	match type:
		ShrimpIR.TYPE_ENUM:
			return "node"
		ShrimpIR.TYPE_EXTERNAL_PARAMETER:
			return "external"
		Variant.Type.TYPE_BOOL:
			return "bool"
		Variant.Type.TYPE_INT:
			return "int"
		Variant.Type.TYPE_FLOAT:
			return "number"
		Variant.Type.TYPE_STRING:
			return "string"
		Variant.Type.TYPE_STRING_NAME:
			return "string_name"
		_:
			return str(type)
func array_suffix(attr: Dictionary) -> String:
	if attr.get("array", false):
		return "[]"
	return ""
