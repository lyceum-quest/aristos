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
		parsed = Json.parse(Str.trim(output))
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
}
