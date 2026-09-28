# Groups a work's tokens into study passages by its canonical citation (data/oga/refs/<cts-id>.tsv, from OGA's
# PAULA citation layer). Fully deterministic: the finest canonical unit is the passage, unless the work's mean unit
# is under 12 tokens (lines of poetry: each sentence becomes a passage, labelled with its citation range) or over
# 150 tokens (Stephanus pages, long chapters: each unit is split at its sentences, labelled unit §n). In
# dialogues the sentences are grouped into speaker turns first (see `block_tokens`).
Passages :: [].{

	Passage : { ref : Str, label : Str, tokens : List(Str) }
	Mode : [Canonical, BySentence, SplitUnits]

	small_unit = 12
	large_unit = 150

	refs_path : Str -> Str
	refs_path = |cts_id| "data/oga/refs/${cts_id}.tsv"

	# `t_N<TAB>1_5` rows -> (token id -> citation), plus the work's mean tokens per citation.
	citations : Str -> { refs : Dict(Str, Str), mean : U64 }
	citations = |tsv| {
		rows = List.keep_if(List.map(Str.split_on(tsv, "\n"), Str.trim), |line| line != "")
		refs = insert_rows(rows, Dict.empty())
		units = Dict.len(count_units(Dict.to_list(refs), Dict.empty()))
		{ refs, mean: if units == 0 0 else Dict.len(refs) // units }
	}

	mode : U64 -> Mode
	mode = |mean| if mean < small_unit BySentence else if mean > large_unit SplitUnits else Canonical

	# Bible citations read chapter:verse; every other work joins its levels with dots.
	label_style : Str -> Str
	label_style = |cts_id| if Str.starts_with(cts_id, "tlg0031.") or Str.starts_with(cts_id, "tlg0527.") ":" else "."

	# Passages for the given CoNLL-U sentence blocks, in text order. Every visible token must have a citation.
	build : Str, Str, List(Str) -> Try(List(Passage), [MissingCitation(Str), ..])
	build = |cts_id, tsv, blocks| {
		cited = citations(tsv)
		separator = label_style(cts_id)
		tokens = block_tokens(blocks)
		located = locate(tokens, cited.refs, [])?
		Ok(group(located, mode(cited.mean), separator, [], Nothing, Dict.empty()))
	}

	# (token id, segment) for every visible row; OGA placeholder rows (MISC `e_…`) are skipped. A segment is a
	# sentence, except in dialogues (works with speaker-label sentences such as `ΣΩ .`), where it is a speaker's turn,
	# split at a sentence once it reaches `turn_cap` tokens.
	block_tokens = |blocks| {
		parsed = List.map(blocks, parse_block)
		assign(parsed, List.any(parsed, |block| block.label), 0, 0, 0, [])
	}

	turn_cap = 60

	assign = |parsed, dialogue, index, segment, size, found| match parsed {
		[] => found
		[block, .. as rest] => {
			count = List.len(block.tokens)
			start = if dialogue (block.label or size >= turn_cap) else index != 0
			next = if start { segment: segment + 1, size: if block.label 0 else count } else { segment, size: size + count }
			assign(rest, dialogue, index + 1, next.segment, next.size, List.concat(found, List.map(block.tokens, |token| { token, sentence: next.segment })))
		}
	}

	parse_block = |block| {
		rows = List.keep_oks(Str.split_on(block, "\n"), |line|
			if Str.starts_with(line, "#") {
				Err(Comment)
			} else {
				match Str.split_on(line, "\t") {
					[_, form, _, _, _, _, _, _, _, misc] => {
						token = List.first(Str.split_on(misc, "|")) ?? ""
						if Str.starts_with(token, "t_") Ok({ token, form }) else Err(Placeholder)
					}
					_ => Err(NotARow)
				}
			})
		{ tokens: List.map(rows, |row| row.token), label: speaker_label(List.map(rows, |row| row.form)) }
	}

	# `ΣΩ .`: a sentence of one short word in unaccented Greek capitals and a full stop.
	speaker_label = |forms| match forms {
		[name, "."] => {
			bytes = Str.to_utf8(name)
			!List.is_empty(bytes) and List.len(bytes) <= 8 and capitals(bytes)
		}
		_ => Bool.False
	}

	# Α–Ω are U+0391–U+03A9: UTF-8 0xCE 0x91–0xA9.
	capitals = |bytes| match bytes {
		[] => Bool.True
		[lead, second, .. as rest] => lead == 0xCE and second >= 0x91 and second <= 0xA9 and capitals(rest)
		_ => Bool.False
	}

	locate = |tokens, refs, found| match tokens {
		[] => Ok(found)
		[item, .. as rest] =>
			match Dict.get(refs, item.token) {
				Ok(ref) => locate(rest, refs, List.append(found, { token: item.token, sentence: item.sentence, ref }))
				Err(_) => Err(MissingCitation(item.token))
			}
	}

	insert_rows = |rows, found| match rows {
		[] => found
		[line, .. as rest] =>
			match Str.split_on(line, "\t") {
				[token, ref] => insert_rows(rest, Dict.insert(found, token, ref))
				_ => insert_rows(rest, found)
			}
	}

	count_units = |pairs, found| match pairs {
		[] => found
		[(_, ref), .. as rest] => count_units(rest, Dict.insert(found, ref, {}))
	}

	# `open` is the passage being built; finished passages accumulate in `done`.
	group = |located, how, separator, done, open, seen| match located {
		[] =>
			match open {
				Just(draft) => List.map(List.append(done, draft), |passage| finish(passage, how, separator))
				Nothing => List.map(done, |passage| finish(passage, how, separator))
			}
		[item, .. as rest] => {
			key = match how {
				Canonical => item.ref
				BySentence => U64.to_str(item.sentence)
				SplitUnits => "${item.ref}#${U64.to_str(item.sentence)}"
			}
			match open {
				Just(draft) if draft.key == key =>
					group(rest, how, separator, done, Just({ ..draft, tokens: List.append(draft.tokens, item.token), last_ref: item.ref }), seen)
				_ => {
					# A unit split at sentences is numbered within its unit; any repeated ref gets a suffix to stay unique.
					within = (Dict.get(seen, item.ref) ?? 0) + 1
					started = { key, first_ref: item.ref, last_ref: item.ref, within, tokens: [item.token] }
					finished = match open {
						Just(draft) => List.append(done, draft)
						Nothing => done
					}
					group(rest, how, separator, finished, Just(started), Dict.insert(seen, item.ref, within))
				}
			}
		}
	}

	finish = |draft, how, separator| {
		first = dotted(draft.first_ref)
		match how {
			Canonical => {
				ref = if draft.within == 1 first else "${first}~${U64.to_str(draft.within)}"
				{ ref, label: labelled(draft.first_ref, separator), tokens: draft.tokens }
			}
			BySentence => {
				ref = if draft.within == 1 first else "${first}~${U64.to_str(draft.within)}"
				label = if draft.first_ref == draft.last_ref labelled(draft.first_ref, separator) else "${labelled(draft.first_ref, separator)}–${last_part(draft.first_ref, draft.last_ref, separator)}"
				{ ref, label, tokens: draft.tokens }
			}
			SplitUnits =>
				{ ref: "${first}~${U64.to_str(draft.within)}", label: "${labelled(draft.first_ref, separator)} §${U64.to_str(draft.within)}", tokens: draft.tokens }
		}
	}

	# OGA `1_5` -> URL-friendly `1.5`.
	dotted = |ref| Str.join_with(Str.split_on(ref, "_"), ".")

	# `1_5` -> `1:5` for the Bible (last level after a colon), `1.1.1` elsewhere.
	labelled = |ref, separator| {
		parts = Str.split_on(ref, "_")
		if separator == ":" and List.len(parts) >= 2 {
			"${Str.join_with(List.drop_last(parts, 1), ".")}:${List.last(parts) ?? ""}"
		} else {
			Str.join_with(parts, ".")
		}
	}

	# The end of a range, dropping the levels it shares with the start: `1_1`–`1_7` -> `7`, `1_9`–`2_3` -> `2.3`.
	last_part = |first_ref, last_ref, separator| {
		first = Str.split_on(first_ref, "_")
		last = Str.split_on(last_ref, "_")
		if List.len(first) == List.len(last) and List.drop_last(first, 1) == List.drop_last(last, 1) {
			List.last(last) ?? last_ref
		} else {
			labelled(last_ref, separator)
		}
	}
}
