# Builds a work's citation from its OGA input path and OGA's bibliographic table (data/oga/urn_cts.xml).
# Every field comes from the table or from the fixed rules below; nothing is typed per work.
Citation :: [].{

	Text : { urn : Str, author : Str, title : Str, labels : List(Str), edition : Str, repository : Str, repository_url : Str, snapshot : Str, license : Str, reader_url : Str, source_url : Str }
	Generated : { model : Str, prompts : Str }
	Work : { text : Text, generated : Generated }

	table_path : Str
	table_path = "data/oga/urn_cts.xml"

	annotation_name = "Opera Graeca Adnotata"
	annotation_version = "v0.2.0"
	annotation_creator = "Giuseppe G. A. Celano"
	annotation_layers = "tokenization, sentence segmentation, lemmas, morphology, and dependency syntax"
	annotation_doi = "10.5281/zenodo.14206061"
	generated_layers = "prose and literal translations and contextual glosses"
	license = "CC BY-SA 4.0"

	# `tlg0031.tlg003.perseus-grc2.tok01_sentence-seg01_annotated_lemma.conllu` -> `tlg0031.tlg003.perseus-grc2`
	cts_id : Str -> Try(Str, [NoCtsId(Str), ..])
	cts_id = |input| {
		file = List.last(Str.split_on(input, "/")) ?? input
		match Str.split_on(file, ".") {
			[group, work, edition, ..] =>
				if group != "" and work != "" and Str.contains(edition, "-grc") {
					Ok("${group}.${work}.${edition}")
				} else {
					Err(NoCtsId(input))
				}
			_ => Err(NoCtsId(input))
		}
	}

	# The original repositories as OGA v0.2.0 bundles them (original_Greek_files/README.md), pinned to its snapshot tags.
	repository_for : Str -> Try({ repository : Str, snapshot : Str }, [NoSourceRepository(Str), ..])
	repository_for = |id|
		if Str.contains(id, ".perseus-grc") {
			Ok({ repository: "PerseusDL/canonical-greekLit", snapshot: "0.0.11376425141" })
		} else if Str.contains(id, ".1st1K-grc") {
			Ok({ repository: "OpenGreekAndLatin/First1KGreek", snapshot: "1.1.11352615003" })
		} else {
			Err(NoSourceRepository(id))
		}

	build : Str, Str, Str, Str -> Try(Work, [NoCtsId(Str), NoSourceRepository(Str), UnknownWork(Str), DuplicateWork(Str), MissingField(Str, Str), ..])
	build = |table, input, model, prompts| {
		id = cts_id(input)?
		entry = entry_for(table, id)?
		source = repository_for(id)?
		path = match Str.split_on(id, ".") {
			[group, work, ..] => "data/${group}/${work}/${id}.xml"
			_ => ""
		}
		labels = List.keep_if(Str.split_on(field(entry, "title_labels"), "_"), |label| label != "")
		text = {
			urn: "urn:cts:greekLit:${id}",
			author: required(id, "author", field(entry, "author"))?,
			title: required(id, "title_from_print_edition", field(entry, "title_from_print_edition"))?,
			labels,
			edition: required(id, "printed_edition", field(entry, "printed_edition"))?,
			repository: source.repository,
			repository_url: "https://github.com/${source.repository}/releases/tag/${source.snapshot}",
			snapshot: source.snapshot,
			license,
			reader_url: "https://scaife.perseus.org/reader/urn:cts:greekLit:${id}/",
			source_url: "https://github.com/${source.repository}/blob/${source.snapshot}/${path}",
		}
		_ = required(id, "model", model)?
		_ = required(id, "prompts", prompts)?
		Ok({ text, generated: { model, prompts } })
	}

	entry_for = |table, id|
		match Str.split_on(table, "<urn_cts>${id}</urn_cts>") {
			[_, after] => Ok(List.first(Str.split_on(after, "</work>")) ?? "")
			[_] => Err(UnknownWork(id))
			_ => Err(DuplicateWork(id))
		}

	field = |entry, name|
		match Str.split_on(entry, "<${name}>") {
			[_, rest, ..] => unescape(Str.trim(List.first(Str.split_on(rest, "</${name}>")) ?? ""))
			_ => ""
		}

	required = |id, name, value| if value == "" Err(MissingField(id, name)) else Ok(value)

	unescape = |value|
		value
			.replace_each("&lt;", "<")
			.replace_each("&gt;", ">")
			.replace_each("&quot;", "\"")
			.replace_each("&apos;", "'")
			.replace_each("&amp;", "&")

	to_json : Work -> Str
	to_json = |citation| {
		text = citation.text
		labels = Str.join_with(List.map(text.labels, json_string), ",")
		text_json = "{\"urn\":${json_string(text.urn)},\"author\":${json_string(text.author)},\"title\":${json_string(text.title)},\"titleLabels\":[${labels}],\"edition\":${json_string(text.edition)},\"repository\":${json_string(text.repository)},\"repositoryUrl\":${json_string(text.repository_url)},\"snapshot\":${json_string(text.snapshot)},\"license\":${json_string(text.license)},\"readerUrl\":${json_string(text.reader_url)},\"sourceUrl\":${json_string(text.source_url)}}"
		annotations_json = "{\"name\":${json_string(annotation_name)},\"version\":${json_string(annotation_version)},\"creator\":${json_string(annotation_creator)},\"layers\":${json_string(annotation_layers)},\"doi\":${json_string(annotation_doi)},\"url\":${json_string("https://doi.org/${annotation_doi}")},\"license\":${json_string(license)}}"
		generated_json = "{\"name\":\"Aristos\",\"layers\":${json_string(generated_layers)},\"model\":${json_string(citation.generated.model)},\"prompts\":${json_string(citation.generated.prompts)},\"license\":${json_string(license)}}"
		"{\"text\":${text_json},\"annotations\":${annotations_json},\"generated\":${generated_json}}"
	}

	json_string : Str -> Str
	json_string = |value| {
		escaped = value
			.replace_each("\\", "\\\\")
			.replace_each("\"", "\\\"")
			.replace_each("\n", "\\n")
			.replace_each("\r", "\\r")
			.replace_each("\t", "\\t")

		"\"${escaped}\""
	}
}
