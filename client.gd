@tool
extends RefCounted
class_name GarlicLspClient
 
var stream: StreamPeerTCP
var framing: GarlicLspFraming
var nextId: int = 1

func connect_to_server(port: int = 6009) -> Error:
	stream = StreamPeerTCP.new()
	framing = GarlicLspFraming.new()
	var err = stream.connect_to_host("127.0.0.1", port)
	if err != OK:
		return err
	var deadline = Time.get_ticks_msec() + 3000
	while stream.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		stream.poll()
	if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ERR_CANT_CONNECT
	return OK
func notify(method: String, params: Dictionary) -> void:
	stream.put_data(GarlicLspJsonRpc.new().encode_notification(method, params))
func request(method: String, params: Dictionary, timeoutMs: int = 5000) -> Dictionary:
	var id = nextId
	nextId += 1
	var envelope = {"jsonrpc": "2.0", "id": id, "method": method, "params": params}
	stream.put_data(GarlicLspFraming.encode(JSON.stringify(envelope, "", false)))
	var deadline = Time.get_ticks_msec() + timeoutMs
	while Time.get_ticks_msec() < deadline:
		stream.poll()
		var available = stream.get_available_bytes()
		while available > 0:
			var data = stream.get_data(available)
			for body in framing.feed(data[1]):
				var message = JSON.parse_string(body)
				if typeof(message) == TYPE_DICTIONARY and message.get("id") != null and int(message["id"]) == id:
					return message
			available = stream.get_available_bytes()
		OS.delay_msec(10)
	return {}
func self_test(port: int = 6009) -> Dictionary:
	var results = {}
	if connect_to_server(port) != OK:
		return {"error": "connect failed"}
	var initResult = request("initialize", {"processId": OS.get_process_id(), "rootUri": null, "capabilities": {}})
	results["initialize"] = initResult.has("result")
	notify("initialized", {})
	var source = "root(body={print(content=string_literal(content=\"hello\"));});"
	var file = FileAccess.open("res://addons/shrimpvm/garlic/examples/add.srk", FileAccess.ModeFlags.READ)
	if file:
		source = file.get_as_text()
	var uri = "file:///selftest.srk"
	notify("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "garlic", "version": 1, "text": source}})
	OS.delay_msec(400)
	var completion = request("textDocument/completion", {"textDocument": {"uri": uri}, "position": {"line": 0, "character": 0}})
	var items = completion.get("result", [])
	var itemCount = 0
	if typeof(items) == TYPE_ARRAY:
		itemCount = items.size()
	results["completionItems"] = itemCount
	var hover = request("textDocument/hover", {"textDocument": {"uri": uri}, "position": {"line": 0, "character": 0}})
	results["hover"] = hover.get("result") != null
	results["shutdown"] = request("shutdown", {}).has("result")
	notify("exit", {})
	stream.disconnect_from_host()
	return results
