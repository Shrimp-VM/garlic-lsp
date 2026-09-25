@tool
extends Node
class_name GarlicLspServer

const DEFAULT_PORT = 6009
const DIAGNOSTIC_DELAY = 0.3
const SETTING_PORT = "shrimpvm/garlic/lsp_port"

var tcpServer: TCPServer
var clientStream: StreamPeerTCP
var framing: GarlicLspFraming
var rpcInstance: GarlicLspJsonRpc
var workspace: GarlicLspWorkspace
var registry: GarlicLspSchemaRegistry
var analyzer: GarlicLspAnalyzer
var features: GarlicLspFeatures
var pendingDiagnostics: Dictionary = {}
var diagnosticTimer: float = 0.0
var shutdownRequested: bool = false

func _ready() -> void:
	framing = GarlicLspFraming.new()
	rpcInstance = GarlicLspJsonRpc.new()
	workspace = GarlicLspWorkspace.new()
	analyzer = GarlicLspAnalyzer.new()
	registry = GarlicLspSchemaRegistry.new()
	features = GarlicLspFeatures.new(registry, analyzer)
	tcpServer = TCPServer.new()
	var port = DEFAULT_PORT
	if ProjectSettings.has_setting(SETTING_PORT):
		port = int(ProjectSettings.get_setting(SETTING_PORT))
	if tcpServer.listen(port, "127.0.0.1") != OK:
		push_warning("GarlicLSP: failed to listen on port %d." % port)
		tcpServer = null
func _exit_tree() -> void:
	drop_client()
	if tcpServer != null:
		tcpServer.stop()
		tcpServer = null
func _process(delta: float) -> void:
	if tcpServer == null:
		return
	if clientStream == null and tcpServer.is_connection_available():
		clientStream = tcpServer.take_connection()
		clientStream.set_no_delay(true)
		shutdownRequested = false
	if clientStream != null:
		clientStream.poll()
		var status = clientStream.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			var available = clientStream.get_available_bytes()
			if available > 0:
				var data = clientStream.get_data(available)
				for body in framing.feed(data[1]):
					handle_message(body)
		elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			drop_client()
	diagnosticTimer += delta
	if diagnosticTimer >= DIAGNOSTIC_DELAY:
		diagnosticTimer = 0.0
		flush_diagnostics()

func drop_client() -> void:
	if clientStream != null:
		clientStream.disconnect_from_host()
		clientStream = null
	framing.reset()
	pendingDiagnostics = {}
	shutdownRequested = false
func send(payload: PackedByteArray) -> void:
	if clientStream != null:
		clientStream.put_data(payload)
func handle_message(body: String) -> void:
	var message = rpcInstance.decode(body)
	if message.get("invalid", false):
		return
	if rpcInstance.is_request(message):
		handle_request(message)
	elif rpcInstance.is_notification(message):
		handle_notification(message)
func handle_request(message: Dictionary) -> void:
	var id = message["id"]
	var method: String = message["method"]
	var params: Dictionary = message.get("params", {})
	match method:
		"initialize":
			send(rpcInstance.encode_response(id, build_capabilities()))
		"shutdown":
			shutdownRequested = true
			send(rpcInstance.encode_response(id, null))
		"textDocument/completion":
			send(rpcInstance.encode_response(id, request_completion(params)))
		"textDocument/hover":
			send(rpcInstance.encode_response(id, request_hover(params)))
		"textDocument/diagnostic":
			send(rpcInstance.encode_response(id, request_diagnostic(params)))
		_:
			send(rpcInstance.encode_error(id, GarlicLspJsonRpc.METHOD_NOT_FOUND, "method not supported: %s" % method))
func handle_notification(message: Dictionary) -> void:
	var method: String = message["method"]
	var params: Dictionary = message.get("params", {})
	match method:
		"initialized":
			pass
		"exit":
			drop_client()
		"textDocument/didOpen":
			workspace.open(params)
			mark_diagnostics(params.get("textDocument", {}).get("uri", ""))
		"textDocument/didChange":
			workspace.change(params)
			mark_diagnostics(params.get("textDocument", {}).get("uri", ""))
		"textDocument/didClose":
			var uri: String = params.get("textDocument", {}).get("uri", "")
			workspace.close(uri)
			pendingDiagnostics.erase(uri)
			publish_diagnostics(uri, [])
		_:
			pass
func build_capabilities() -> Dictionary:
	return {
		"capabilities": {
			"positionEncoding": "utf-32",
			"textDocumentSync": {"openClose": true, "change": 1},
			"completionProvider": {"triggerCharacters": [], "resolveProvider": false},
			"hoverProvider": true,
			"diagnosticProvider": {"interFileDependencies": false, "workspaceDiagnostics": false}
		},
		"serverInfo": {"name": "garlic-lsp", "version": "0.1.0"}
	}
func request_completion(params: Dictionary) -> Array:
	var uri: String = params.get("textDocument", {}).get("uri", "")
	if not workspace.has(uri):
		return []
	var position: Dictionary = params.get("position", {})
	return features.completion(
		workspace.get_text(uri),
		int(position.get("line", 0)),
		int(position.get("character", 0))
	)
func request_hover(params: Dictionary):
	var uri: String = params.get("textDocument", {}).get("uri", "")
	if not workspace.has(uri):
		return null
	var position: Dictionary = params.get("position", {})
	return features.hover(
		workspace.get_text(uri),
		int(position.get("line", 0)),
		int(position.get("character", 0))
	)
func request_diagnostic(params: Dictionary) -> Dictionary:
	var uri: String = params.get("textDocument", {}).get("uri", "")
	if not workspace.has(uri):
		return {"kind": "full", "items": []}
	return {"kind": "full", "items": analyzer.collect_diagnostics(workspace.get_text(uri))}
func mark_diagnostics(uri: String) -> void:
	if not uri.is_empty():
		pendingDiagnostics[uri] = true
func flush_diagnostics() -> void:
	var uris = pendingDiagnostics.keys()
	pendingDiagnostics = {}
	for uri in uris:
		if not workspace.has(uri):
			continue
		publish_diagnostics(uri, analyzer.collect_diagnostics(workspace.get_text(uri)))
func publish_diagnostics(uri: String, items: Array) -> void:
	send(rpcInstance.encode_notification("textDocument/publishDiagnostics", {"uri": uri, "diagnostics": items}))
