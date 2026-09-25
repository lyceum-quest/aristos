LyceumConllu :: [].{

	Passage : { sentence_id : Str, reference : Str }
	Verse : { reference : Str, greek : Str, prose : Str, words : List(Word) }
	Word : { form : Str, lemma : Str, pos : Str, morphology : Str, gloss : Str, transliteration : Str }

	parse : Str, Str -> Try(List(Verse), [InvalidConllu(Str), ..])
	parse = |source, work_urn| parse_with_references(source, work_urn, [])

	parse_with_references : Str, Str, List(Passage) -> Try(List(Verse), [InvalidConllu(Str), ..])
	parse_with_references = |source, work_urn, passages| {
		remaining = validate_passages(passages, work_urn, [])?
		lines = Str.split_on(Str.replace_each(source, "\r\n", "\n"), "\n")
		state = parse_lines(lines, [], { verses: [], remaining, mapped: !List.is_empty(passages) }, work_urn)?
		match state.remaining {
			[unused, ..] => Err(InvalidConllu("unused passage mapping: ${unused.sentence_id}"))
			[] => if List.is_empty(state.verses) Err(InvalidConllu("empty input")) else Ok(reverse_verses(state.verses, []))
		}
	}

	validate_passages = |passages, work_urn, validated|
		match passages {
			[] => Ok(validated)
			[passage, .. as rest] => {
				sentence_id = clean_required(passage.sentence_id, "mapping sentence ID")?
				reference = canonical_reference(clean_required(passage.reference, "mapping reference")?, work_urn)?
				if List.any(validated, |prior| prior.sentence_id == sentence_id) {
					Err(InvalidConllu("duplicate mapping sentence ID: ${sentence_id}"))
				} else {
					validate_passages(rest, work_urn, List.prepend(validated, { sentence_id, reference }))
				}
			}
		}

	clean_required = |value, label|
		if has_control(Str.to_utf8(value)) {
			Err(InvalidConllu("control character in ${label}"))
		} else {
			required(Str.trim(value), label)
		}

	parse_lines = |lines, block, state, work_urn|
		match lines {
			[] => finish_block(block, state, work_urn)
			[line, .. as rest] =>
				if Str.trim(line) == "" {
					next = finish_block(block, state, work_urn)?
					parse_lines(rest, [], next, work_urn)
				} else {
					parse_lines(rest, List.append(block, line), state, work_urn)
				}
			}

	finish_block = |block, state, work_urn|
		if List.is_empty(block) {
			Ok(state)
		} else {
			comments = List.map(List.keep_if(block, |line| Str.starts_with(line, "#")), |line| Str.replace_first(line, "#", ""))
			mapping = (
				if state.mapped {
					sentence_id = required(field(comments, ["sentence_id", "sent_id"], "sentence ID")?, "sentence ID")?
					take_passage(state.remaining, sentence_id)
				} else {
					Ok({ reference: "", remaining: state.remaining })
				}
			)?
			verse = parse_block(block, comments, work_urn, mapping.reference)?
			verses = add_verse(state.verses, verse, state.mapped)?
			Ok({ ..state, verses, remaining: mapping.remaining })
		}

	# Consuming each mapping rejects repeated source IDs as well as unmapped blocks.
	take_passage = |passages, sentence_id|
		match List.keep_if(passages, |passage| passage.sentence_id == sentence_id) {
			[passage] => Ok({ reference: passage.reference, remaining: List.keep_if(passages, |entry| entry.sentence_id != sentence_id) })
			_ => Err(InvalidConllu("missing or already used passage mapping: ${sentence_id}"))
		}

	# Verses are reversed during parsing, so only the head can be merged.
	add_verse = |verses, verse, mapped|
		match verses {
			[prior, .. as rest] =>
				if mapped and prior.reference == verse.reference {
					Ok(
						List.prepend(
							rest,
							{
								..prior,
								greek: "${Str.trim(prior.greek)} ${Str.trim(verse.greek)}",
								prose: "${Str.trim(prior.prose)} ${Str.trim(verse.prose)}",
								words: List.concat(prior.words, verse.words),
							},
						),
					)
				} else {
					add_distinct_verse(verses, verse)
				}
			[] => Ok([verse])
		}

	reverse_verses = |verses, ordered|
		match verses {
			[] => ordered
			[verse, .. as rest] => reverse_verses(rest, List.prepend(ordered, verse))
		}

	add_distinct_verse = |verses, verse|
		if List.any(verses, |prior| prior.reference == verse.reference) {
			Err(InvalidConllu("duplicate verse block: ${verse.reference}"))
		} else {
			Ok(List.prepend(verses, verse))
		}

	parse_block = |lines, comments, work_urn, mapped_reference| {
		comment_reference = canonical_reference(field(comments, ["ref", "reference", "citation"], "reference")?, work_urn)?
		reference = (
			if mapped_reference == "" {
				Ok(comment_reference)
			} else if comment_reference == "" or comment_reference == mapped_reference {
				Ok(mapped_reference)
			} else {
				Err(InvalidConllu("conflicting verse references: ${comment_reference} / ${mapped_reference}"))
			}
		)?
		prose = required(field(comments, ["prose_translation", "text_en"], "prose translation")?, "prose translation")?
		text = field(comments, ["text"], "Greek text")?
		rows = List.keep_if(lines, |line| !Str.starts_with(line, "#"))
		state = parse_rows(rows, { previous: 0.U64, reference, greek: "", words: [], joined: Bool.False, work_urn })?
		final_reference = required(state.reference, "canonical verse reference")?
		if List.is_empty(state.words) {
			Err(InvalidConllu("verse has no real words: ${final_reference}"))
		} else if text != "" and Str.replace_each(text, " ", "") != Str.replace_each(state.greek, " ", "") {
			Err(InvalidConllu("Greek text does not match token forms: ${final_reference}"))
		} else {
			Ok({ reference: final_reference, prose, greek: if text == "" state.greek else text, words: state.words })
		}
	}

	# Known aliases share one slot: even identical duplicates are errors.
	field = |fields, keys, label| {
		values = List.keep_if(
			fields,
			|entry| {
				key = match Str.split_on(entry, "=") {
					[first, ..] => Str.trim(first)
					[] => ""
				}
				List.contains(keys, key)
			},
		)
		match values {
			[] => Ok("")
			[entry] => {
				value = match Str.split_on(entry, "=") {
					[_, .. as rest] => Str.join_with(rest, "=")
					[] => ""
				}
				if has_control(Str.to_utf8(value)) {
					Err(InvalidConllu("control character in ${label}"))
				} else {
					required(Str.trim(value), label)
				}
			}
			_ => Err(InvalidConllu("duplicate or conflicting ${label}"))
		}
	}

	required = |value, label|
		if value == "" or value == "_" Err(InvalidConllu("missing ${label}")) else Ok(value)

	canonical_reference = |value, work_urn|
		if Str.starts_with(value, "urn:cts:") {
			_ = (
				if Str.starts_with(value, "${work_urn}:") or Str.starts_with(value, "${work_urn}.") {
					Ok({})
				} else {
					Err(InvalidConllu("citation belongs to another work: ${value}"))
				}
			)?
			match Str.split_on(value, ":") {
				[_, _, _, _, last] => canonical_reference(required(last, "CTS passage reference")?, work_urn)
				_ => Err(InvalidConllu("invalid CTS citation: ${value}"))
			}
		} else if Str.contains(value, " ") or Str.contains(value, ":") or Str.contains(value, "-") or Str.contains(value, "/") {
			Err(InvalidConllu("expected one canonical verse reference, not a range: ${value}"))
		} else {
			Ok(value)
		}

	parse_rows = |rows, state|
		match rows {
			[] => Ok(state)
			[line, .. as rest] =>
				match Str.split_on(line, "\t") {
					[id_text, form, lemma, upos, _xpos, feats, _head, _deprel, _deps, misc] => {
						id = token_id(id_text)?
						if id <= state.previous {
							Err(InvalidConllu("token IDs must be unique and ascending: ${id_text}"))
						} else if List.any(Str.split_on(line, "\t"), |column| column == "" or has_control(Str.to_utf8(column))) {
							Err(InvalidConllu("empty column or control character at token ${id_text}"))
						} else {
							fields = Str.split_on(misc, "|")
							row_ref = canonical_reference(field(fields, ["Ref"], "token ${id_text} reference")?, state.work_urn)?
							reference = (
								if row_ref == "" {
									Ok(state.reference)
								} else if state.reference == "" or state.reference == row_ref {
									Ok(row_ref)
								} else {
									Err(InvalidConllu("conflicting verse references: ${state.reference} / ${row_ref}"))
								}
							)?
							next = { ..state, previous: id, reference }
							if List.any(fields, |entry| Str.starts_with(entry, "e_")) {
								parse_rows(rest, next)
							} else {
								_ = required(Str.trim(form), "token ${id_text} form")?
								punctuation = upos == "PUNCT" or upos == "u"
								words = (
									if punctuation {
										Ok(state.words)
									} else {
										gloss = required(field(fields, ["gloss", "Gloss"], "token ${id_text} gloss")?, "token ${id_text} gloss")?
										transliteration = field(fields, ["Translit"], "token ${id_text} transliteration")?
										Ok(List.append(state.words, { form, lemma: optional(lemma), pos: reader_pos(upos), morphology: optional(feats), gloss, transliteration }))
									}
								)?
								# OGA lacks spacing: attach closing punctuation left and opening brackets right.
								# Explicit SpaceAfter=No also joins the following real token; quotes are heuristic.
								opening = List.contains(["(", "[", "{", "«", "“", "‘"], form)
								separator = if state.greek == "" or state.joined or (punctuation and !opening) "" else " "
								joined = List.contains(fields, "SpaceAfter=No") or opening
								parse_rows(rest, { ..next, words, greek: "${state.greek}${separator}${form}", joined })
							}
						}
					}
					_ => Err(InvalidConllu("expected exactly 10 tab-separated columns: ${line}"))
				}
			}

	token_id = |value|
		if Str.contains(value, "-") {
			Err(InvalidConllu("unsupported multiword range ID: ${value}"))
		} else if Str.contains(value, ".") {
			Err(InvalidConllu("unsupported decimal empty-node ID: ${value}"))
		} else if value == "" or !List.all(Str.to_utf8(value), |byte| byte >= 48 and byte <= 57) {
			Err(InvalidConllu("invalid positive integer token ID: ${value}"))
		} else {
			id = U64.from_str(value) ? |_| InvalidConllu("invalid positive integer token ID: ${value}")
			if id == 0 Err(InvalidConllu("token ID must be positive")) else Ok(id)
		}

	optional = |value| if value == "_" "" else value

	# C0, DEL, and UTF-8-encoded C1 controls; do not reject Greek continuation bytes.
	has_control = |bytes|
		match bytes {
			[] => Bool.False
			[194, next, .. as rest] => (next >= 128 and next <= 159) or has_control(rest)
			[byte, .. as rest] => byte < 32 or byte == 127 or has_control(rest)
		}

	# Map the supplied tag only, never infer a correction from an unreliable lemma.
	reader_pos = |tag|
		match tag {
			"NOUN" | "PROPN" | "n" => "noun"
			"VERB" | "AUX" | "v" => "verb"
			"ADJ" | "a" => "adjective"
			"ADV" | "d" => "adverb"
			"DET" | "l" => "article"
			"PRON" | "p" => "pronoun"
			"ADP" | "r" => "preposition"
			"CCONJ" | "SCONJ" | "CONJ" | "c" => "conjunction"
			"NUM" | "m" => "numeral"
			"PART" | "g" => "particle"
			"INTJ" | "i" => "interjection"
			"PUNCT" | "u" => "punctuation"
			"SYM" => "symbol"
			_ => "unknown"
		}
}
