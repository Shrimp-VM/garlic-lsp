extends RefCounted
class_name GarlicLspAnalyzer

func tokenize(text: String) -> Array[GarlicLexer.Token]:
	var lexer = GarlicLexer.new()
	return lexer.tokenize(text)
func collect_diagnostics(text: String) -> Array:
	var diagnostics: Array = []
	var lexer = GarlicLexer.new()
	var tokens = lexer.tokenize(text)
	for err in lexer.structuredErrors:
		diagnostics.append(make_diagnostic(text, err["line"], err["column"], err["message"]))
	if lexer.errors.is_empty():
		var parser = GarlicParser.new()
		parser.tokens = tokens
		parser.parse_file()
		for err in parser.structuredErrors:
			diagnostics.append(make_diagnostic(text, err["line"], err["column"], err["message"]))
	return diagnostics
func make_diagnostic(text: String, line: int, column: int, message: String) -> Dictionary:
	var lineLength = line_length(text, line)
	var startChar = clampi(column - 1, 0, lineLength)
	var endChar = mini(startChar + 1, lineLength)
	return {
		"range": {
			"start": {"line": line - 1, "character": startChar},
			"end": {"line": line - 1, "character": endChar}
		},
		"severity": 1,
		"source": "garlic",
		"message": message
	}
func line_length(text: String, line: int) -> int:
	var lines = text.split("\n")
	if line >= 1 and line <= lines.size():
		return lines[line - 1].length()
	return 0
func locate(tokens: Array, line: int, character: int) -> Dictionary:
	var contextTokens: Array = []
	var filterText = ""
	var insideString = false
	var hasToken = false
	for token in tokens:
		if token.type == GarlicLexer.TokenType.EOF:
			break
		var startLine: int = token.line - 1
		var startChar: int = token.column - 1
		if startLine > line or (startLine == line and startChar > character):
			break
		var span = token_span(token)
		var endLine: int = startLine + span["lines"]
		var endChar: int = startChar + span["chars"]
		if endLine < line or (endLine == line and endChar <= character):
			contextTokens.append(token)
			continue
		if token.type == GarlicLexer.TokenType.STRING or token.type == GarlicLexer.TokenType.STRING_NAME:
			insideString = true
		elif token.type == GarlicLexer.TokenType.IDENT:
			filterText = token.value
			hasToken = true
		break
	return {"tokens": contextTokens, "filterText": filterText, "insideString": insideString, "hasToken": hasToken}
func token_span(token: GarlicLexer.Token) -> Dictionary:
	match token.type:
		GarlicLexer.TokenType.IDENT:
			return {"lines": 0, "chars": token.value.length()}
		GarlicLexer.TokenType.NUMBER:
			return {"lines": 0, "chars": str(token.value).length()}
		GarlicLexer.TokenType.BOOL:
			return {"lines": 0, "chars": 4 if token.value else 5}
		GarlicLexer.TokenType.STRING, GarlicLexer.TokenType.STRING_NAME:
			var value: String = token.value
			return {"lines": value.count("\n"), "chars": value.length() + 2}
		_:
			return {"lines": 0, "chars": 1}
func resolve_context(tokens: Array) -> Dictionary:
	if tokens.is_empty():
		return {"kind": "node_name", "nodeType": "", "key": "", "seenKeys": []}
	var last = tokens[tokens.size() - 1]
	if last.type == GarlicLexer.TokenType.NUMBER or last.type == GarlicLexer.TokenType.STRING \
			or last.type == GarlicLexer.TokenType.STRING_NAME or last.type == GarlicLexer.TokenType.BOOL:
		return {"kind": "none", "nodeType": "", "key": "", "seenKeys": []}
	var openerIndex = find_unmatched_opener(tokens)
	if openerIndex < 0:
		return {"kind": "node_name", "nodeType": "", "key": "", "seenKeys": []}
	var opener = tokens[openerIndex]
	match opener.value:
		"(":
			var nodeType = node_type_at(tokens, openerIndex)
			var seenKeys = collect_seen_keys(tokens, openerIndex)
			if last.type == GarlicLexer.TokenType.PUNCT and last.value == "=":
				var key = ""
				if tokens.size() >= 2 and tokens[tokens.size() - 2].type == GarlicLexer.TokenType.IDENT:
					key = tokens[tokens.size() - 2].value
				return {"kind": "value", "nodeType": nodeType, "key": key, "seenKeys": seenKeys}
			return {"kind": "key", "nodeType": nodeType, "key": "", "seenKeys": seenKeys}
		"[":
			var info = attribute_before_array(tokens, openerIndex)
			return {"kind": "array_item", "nodeType": info["nodeType"], "key": info["key"], "seenKeys": []}
		_:
			return {"kind": "node_name", "nodeType": "", "key": "", "seenKeys": []}
func find_unmatched_opener(tokens: Array) -> int:
	var depth = 0
	for i in range(tokens.size() - 1, -1, -1):
		var token = tokens[i]
		if token.type != GarlicLexer.TokenType.PUNCT:
			continue
		if token.value == ")" or token.value == "]" or token.value == "}":
			depth += 1
		elif token.value == "(" or token.value == "[" or token.value == "{":
			if depth == 0:
				return i
			depth -= 1
	return -1
func node_type_at(tokens: Array, openerIndex: int) -> String:
	if openerIndex >= 1 and tokens[openerIndex - 1].type == GarlicLexer.TokenType.IDENT:
		return tokens[openerIndex - 1].value
	return ""
func collect_seen_keys(tokens: Array, openerIndex: int) -> Array:
	var seen: Array = []
	var depth = 0
	for i in range(openerIndex + 1, tokens.size()):
		var token = tokens[i]
		if token.type != GarlicLexer.TokenType.PUNCT:
			continue
		if token.value == "(" or token.value == "[" or token.value == "{":
			depth += 1
		elif token.value == ")" or token.value == "]" or token.value == "}":
			depth -= 1
		elif token.value == "=" and depth == 0 and i >= 1:
			var prev = tokens[i - 1]
			if prev.type == GarlicLexer.TokenType.IDENT:
				seen.append(prev.value)
	return seen
func attribute_before_array(tokens: Array, openerIndex: int) -> Dictionary:
	if openerIndex >= 3:
		var assign = tokens[openerIndex - 1]
		var key = tokens[openerIndex - 2]
		var paren = tokens[openerIndex - 3]
		if assign.type == GarlicLexer.TokenType.PUNCT and assign.value == "=" \
				and key.type == GarlicLexer.TokenType.IDENT \
				and paren.type == GarlicLexer.TokenType.PUNCT and paren.value == "(":
			return {"nodeType": node_type_at(tokens, openerIndex - 3), "key": key.value}
	return {"nodeType": "", "key": ""}
