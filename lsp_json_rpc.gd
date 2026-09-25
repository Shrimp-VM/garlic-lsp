extends RefCounted
class_name GarlicLspJsonRpc

const PARSE_ERROR = -32700
const INVALID_REQUEST = -32600
const METHOD_NOT_FOUND = -32601

func decode(body: String) -> Dictionary:
	var parsed = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"invalid": true}
	return parsed
func is_request(message: Dictionary) -> bool:
	return message.has("id") and message.has("method")
func is_notification(message: Dictionary) -> bool:
	return message.has("method") and not message.has("id")
func encode_message(message: Dictionary) -> PackedByteArray:
	return GarlicLspFraming.encode(JSON.stringify(message, "", false))
func encode_response(id, result) -> PackedByteArray:
	return encode_message({"jsonrpc": "2.0", "id": id, "result": result})
func encode_error(id, code: int, message: String) -> PackedByteArray:
	return encode_message({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})
func encode_notification(method: String, params) -> PackedByteArray:
	return encode_message({"jsonrpc": "2.0", "method": method, "params": params})
