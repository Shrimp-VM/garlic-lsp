extends RefCounted
class_name GarlicLspWorkspace

var documents: Dictionary = {}

func open(params: Dictionary) -> void:
	var doc: Dictionary = params.get("textDocument", {})
	documents[doc.get("uri", "")] = {"text": doc.get("text", ""), "version": doc.get("version", 0)}
func change(params: Dictionary) -> void:
	var doc: Dictionary = params.get("textDocument", {})
	var uri: String = doc.get("uri", "")
	if not documents.has(uri):
		return
	var changes: Array = params.get("contentChanges", [])
	if changes.is_empty():
		return
	documents[uri]["text"] = changes[0].get("text", documents[uri]["text"])
	documents[uri]["version"] = doc.get("version", documents[uri]["version"])
func close(uri: String) -> void:
	documents.erase(uri)
func has(uri: String) -> bool:
	return documents.has(uri)
func get_text(uri: String) -> String:
	if documents.has(uri):
		return documents[uri]["text"]
	return ""
