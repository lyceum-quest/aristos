# The `subscription` backend of the gloss and translate stages: one `claude -p` call on this machine's Claude Code
# login instead of an HTTP request to an OpenAI-compatible API (the `api` backend). Its JSON result is rewritten into
# the chat-completion shape the stages and loop.roc already read, with `usage.cost` set to Claude Code's
# `total_cost_usd`: the list-price API cost of the call, not an amount billed to the subscription.
Backend :: [].{

	# `claude` runs from /tmp so it does not discover this repository's AGENTS.md or CLAUDE.md, with no tools, MCP
	# servers, skills, settings, or saved session, and with the stage prompt replacing Claude Code's system prompt.
	# Thinking is off, matching the `api` backend's disabled reasoning; Claude Code otherwise thinks on longer requests.
	# `--bare` would skip more, but it refuses subscription logins.
	claude_args : Str, Str, Str -> List(Str)
	claude_args = |model, system, user| [
		"-C",
		"/tmp",
		"MAX_THINKING_TOKENS=0",
		"claude",
		"-p",
		"--model",
		model,
		"--system-prompt",
		system,
		"--output-format",
		"json",
		"--tools",
		"",
		"--strict-mcp-config",
		"--disable-slash-commands",
		"--no-session-persistence",
		"--setting-sources",
		"",
		user,
	]

	ClaudeResult : { is_error : Bool, result : Str, total_cost_usd : Dec, usage : { input_tokens : U64, output_tokens : U64, cache_creation_input_tokens : U64, cache_read_input_tokens : U64 } }

	# Claude Code's `--output-format json` result -> `{ choices: [{ message: { content } }], usage: { cost, … } }`.
	completion : Str -> Try(Str, [SubscriptionError(Str), ..])
	completion = |output| {
		parsed : Try(ClaudeResult, _)
		parsed = Json.parse(clamp_fractions(Str.trim(output)))
		match parsed {
			Ok(reply) =>
				if reply.is_error {
					Err(SubscriptionError(reply.result))
				} else {
					encoded = Json.to_str_try({
						backend: "subscription",
						choices: [{ message: { content: reply.result } }],
						usage: {
							cost: reply.total_cost_usd,
							prompt_tokens: reply.usage.input_tokens + reply.usage.cache_creation_input_tokens + reply.usage.cache_read_input_tokens,
							completion_tokens: reply.usage.output_tokens,
						},
					})
					match encoded {
						Ok(text) => Ok(text)
						Err(_) => Err(SubscriptionError("could not encode the claude result"))
					}
				}
			Err(_) => Err(SubscriptionError(Str.trim(output)))
		}
	}

	# Claude Code can report costs with more fraction digits than Dec's 18 (`"total_cost_usd":0.0007735999999999999`),
	# and Json.parse then rejects the whole result, discarding a successful reply. Outside JSON strings, this drops
	# fraction digits past the 18th; the cost is informational, so truncating it is harmless. No upstream Roc issue
	# exists yet (searched roc-lang/roc 2026-10-01); the repro is drafted as roc-issues BUG-015
	# (json-dec-over-18-fraction-digits). Remove this once Json.parse accepts such numbers into Dec.
	clamp_fractions : Str -> Str
	clamp_fractions = |text| {
		start = { out: List.with_capacity(Str.count_utf8_bytes(text)), string: Bool.False, escaped: Bool.False, digit: Bool.False, fraction: Bool.False, digits: 0 }
		clamped = List.fold(
			Str.to_utf8(text),
			start,
			|state, byte| {
				digit = byte >= '0' and byte <= '9'
				if state.string {
					string = state.escaped or byte != '"'
					{ ..state, out: List.append(state.out, byte), string, escaped: !state.escaped and byte == '\\' }
				} else if state.fraction and digit {
					digits = state.digits + 1
					{ ..state, out: if digits > 18 state.out else List.append(state.out, byte), digits }
				} else {
					{ ..state, out: List.append(state.out, byte), string: byte == '"', digit, fraction: byte == '.' and state.digit, digits: 0 }
				}
			},
		)
		Str.from_utf8(clamped.out) ?? text
	}

	expect clamp_fractions("{\"total_cost_usd\":0.0007735999999999999,\"n\":12}") == "{\"total_cost_usd\":0.000773599999999999,\"n\":12}"
	expect clamp_fractions("{\"result\":\"0.12345678901234567890 \\\" 1.1234567890123456789\",\"c\":1.5}") == "{\"result\":\"0.12345678901234567890 \\\" 1.1234567890123456789\",\"c\":1.5}"
	expect {
		reply = completion("{\"is_error\":false,\"result\":\"ok\",\"total_cost_usd\":0.0007735999999999999,\"usage\":{\"input_tokens\":2,\"output_tokens\":47,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":1498}}")
		match reply {
			Ok(text) => Str.contains(text, "\"content\":\"ok\"")
			Err(_) => Bool.False
		}
	}
}
