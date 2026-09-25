extends RefCounted
class_name GarlicLspFraming

const MAX_BUFFER_SIZE = 1048576

var buffer: PackedByteArray = PackedByteArray()

func feed(data: PackedByteArray) -> Array[String]:
	buffer.append_array(data)
	var messages: Array[String] = []
	while true:
		var headerEnd = find_header_end()
		if headerEnd < 0:
			if buffer.size() > MAX_BUFFER_SIZE:
				reset()
			break
		var contentLength = extract_content_length(buffer.slice(0, headerEnd).get_string_from_utf8())
		if contentLength < 0:
			reset()
			break
		var bodyStart = headerEnd + 4
		if buffer.size() < bodyStart + contentLength:
			break
		messages.append(buffer.slice(bodyStart, bodyStart + contentLength).get_string_from_utf8())
		buffer = buffer.slice(bodyStart + contentLength)
	return messages
func find_header_end() -> int:
	var size = buffer.size()
	for i in range(size - 3):
		if buffer[i] == 13 and buffer[i + 1] == 10 and buffer[i + 2] == 13 and buffer[i + 3] == 10:
			return i
	return -1
func extract_content_length(headerText: String) -> int:
	for line in headerText.split("\n"):
		var parts = line.strip_edges().split(":")
		if parts.size() >= 2 and parts[0].strip_edges().to_lower() == "content-length":
			return parts[1].strip_edges().to_int()
	return -1
func reset() -> void:
	buffer = PackedByteArray()

static func encode(body: String) -> PackedByteArray:
	var payload = body.to_utf8_buffer()
	var result = ("Content-Length: %d\r\n\r\n" % payload.size()).to_utf8_buffer()
	result.append_array(payload)
	return result
