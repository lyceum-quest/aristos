(function (global) {
  "use strict";

  const DATABASE_NAME = "aristos";
  const DATABASE_VERSION = 1;
  const MANIFEST_URL = "preload/corpora.json";

  function parseMetadata(line) {
    const match = /^#\s*([^=]+?)\s*=\s*(.*)$/.exec(line);
    return match ? [match[1].trim(), match[2]] : null;
  }

  function parseFields(serialized) {
    if (!serialized || serialized === "_") return {};

    return serialized.split("|").reduce(function (fields, item) {
      const separator = item.indexOf("=");
      if (separator === -1) {
        fields[item] = "";
      } else {
        fields[item.slice(0, separator)] = item.slice(separator + 1);
      }
      return fields;
    }, {});
  }

  function firstValue(metadata, keys) {
    for (const key of keys) {
      if (metadata[key]) return metadata[key];
    }
    return "";
  }

  function chapterFromReference(reference) {
    const localReference = reference.includes(":")
      ? reference.slice(reference.lastIndexOf(":") + 1)
      : reference;
    const match = /\d+/.exec(localReference);
    return match ? Number(match[0]) : 1;
  }

  function parseConllu(raw, manifestEntry) {
    const sentences = [];
    let metadata = {};
    let rows = [];

    function finishSentence() {
      if (rows.length === 0) return;

      const regularRows = rows.filter(function (row) {
        return /^\d+$/.test(row.id);
      });
      if (regularRows.length === 0) {
        metadata = {};
        rows = [];
        return;
      }

      const sentenceId = firstValue(metadata, ["sent_id", "sentence_id"]);
      const citation = firstValue(metadata, ["citation", "cts_urn"]);
      const firstMisc = parseFields(regularRows[0].misc);
      const reference = firstMisc.Ref || citation.slice(citation.lastIndexOf(":") + 1) || sentenceId;
      const stableId = metadata.sent_id || (citation && sentenceId ? citation + "-s" + sentenceId : sentenceId);

      const tokens = regularRows.map(function (row, index) {
        const features = parseFields(row.feats);
        const misc = parseFields(row.misc);
        const next = regularRows[index + 1];
        const spaceAfter = misc.SpaceAfter !== "No" && (!next || next.upos !== "PUNCT");

        return {
          i: Number(row.id),
          f: row.form === "_" ? "" : row.form,
          l: row.lemma === "_" ? "" : row.lemma,
          p: row.upos === "_" ? "" : row.upos,
          m: row.feats === "_" ? "" : row.feats,
          c: features.Case || "",
          n: features.Number || "",
          g: features.Gender || "",
          h: row.head === "_" ? 0 : Number(row.head),
          r: row.deprel === "_" ? "" : row.deprel,
          s: row.upos === "PUNCT" ? "" : (misc.Gloss || misc.gloss || ""),
          a: spaceAfter
        };
      });

      const reconstructedText = tokens.map(function (token) {
        return token.f + (token.a ? " " : "");
      }).join("").trimEnd();

      sentences.push({
        i: stableId || manifestEntry.id + "-sentence-" + (sentences.length + 1),
        c: chapterFromReference(reference),
        v: reference || sentenceId,
        x: metadata.text || reconstructedText,
        d: firstValue(metadata, ["text_en_literal", "literal_translation"]),
        e: firstValue(metadata, ["text_en", "prose_translation"]),
        t: tokens
      });

      metadata = {};
      rows = [];
    }

    raw.replace(/\r\n?/g, "\n").split("\n").forEach(function (line, lineIndex) {
      if (line === "") {
        finishSentence();
        return;
      }

      if (line.startsWith("#")) {
        const pair = parseMetadata(line);
        if (pair) metadata[pair[0]] = pair[1];
        return;
      }

      const columns = line.split("\t");
      if (columns.length !== 10) {
        throw new Error("Invalid CoNLL-U at line " + (lineIndex + 1) + ": expected 10 columns");
      }

      rows.push({
        id: columns[0],
        form: columns[1],
        lemma: columns[2],
        upos: columns[3],
        xpos: columns[4],
        feats: columns[5],
        head: columns[6],
        deprel: columns[7],
        deps: columns[8],
        misc: columns[9]
      });
    });
    finishSentence();

    if (sentences.length === 0) {
      throw new Error("Corpus " + manifestEntry.id + " contains no sentences");
    }

    return {
      source: Object.assign({ name: manifestEntry.id, url: "", commit: "", license: "", edition: "" }, manifestEntry.source),
      sentences: sentences
    };
  }

  function openDatabase() {
    return new Promise(function (resolve, reject) {
      if (!global.indexedDB) {
        reject(new Error("IndexedDB is unavailable"));
        return;
      }

      const request = global.indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
      request.onupgradeneeded = function () {
        const database = request.result;
        if (!database.objectStoreNames.contains("corpora")) {
          database.createObjectStore("corpora", { keyPath: "id" });
        }
        if (!database.objectStoreNames.contains("metadata")) {
          database.createObjectStore("metadata", { keyPath: "key" });
        }
        if (!database.objectStoreNames.contains("progress")) {
          database.createObjectStore("progress", { keyPath: "id" });
        }
      };
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error); };
    });
  }

  function transactionComplete(transaction) {
    return new Promise(function (resolve, reject) {
      transaction.oncomplete = function () { resolve(); };
      transaction.onerror = function () { reject(transaction.error); };
      transaction.onabort = function () { reject(transaction.error); };
    });
  }

  async function persistPreload(manifest, loadedCorpora) {
    const database = await openDatabase();
    try {
      const transaction = database.transaction(["corpora", "metadata"], "readwrite");
      const fetchedAt = new Date().toISOString();
      transaction.objectStore("metadata").put({ key: "preload-manifest", value: manifest, fetchedAt: fetchedAt });

      loadedCorpora.forEach(function (loaded) {
        transaction.objectStore("corpora").put({
          id: loaded.entry.id,
          path: loaded.entry.path,
          content: loaded.raw,
          fetchedAt: fetchedAt
        });
        transaction.objectStore("metadata").put({
          key: "corpus:" + loaded.entry.id,
          value: loaded.entry,
          fetchedAt: fetchedAt
        });
      });
      await transactionComplete(transaction);
    } finally {
      database.close();
    }
  }

  function requestValue(request) {
    return new Promise(function (resolve, reject) {
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error); };
    });
  }

  async function loadCachedPreload() {
    const database = await openDatabase();
    try {
      const metadataTransaction = database.transaction("metadata", "readonly");
      const manifestRecord = await requestValue(metadataTransaction.objectStore("metadata").get("preload-manifest"));
      if (!manifestRecord || !manifestRecord.value || !Array.isArray(manifestRecord.value.corpora)) {
        throw new Error("No cached corpus preload is available");
      }

      const corpusTransaction = database.transaction("corpora", "readonly");
      const requests = manifestRecord.value.corpora.map(function (entry) {
        return { entry: entry, request: corpusTransaction.objectStore("corpora").get(entry.id) };
      });
      const loaded = await Promise.all(requests.map(async function (pending) {
        const record = await requestValue(pending.request);
        if (!record || typeof record.content !== "string") {
          throw new Error("Cached corpus " + pending.entry.id + " is unavailable");
        }
        return { entry: pending.entry, raw: record.content, parsed: parseConllu(record.content, pending.entry) };
      }));
      return { manifest: manifestRecord.value, corpora: loaded, cached: true };
    } finally {
      database.close();
    }
  }

  async function fetchPreload() {
    const manifestResponse = await fetch(MANIFEST_URL, { cache: "no-cache" });
    if (!manifestResponse.ok) throw new Error("Could not fetch corpus manifest: HTTP " + manifestResponse.status);

    const manifest = await manifestResponse.json();
    if (manifest.version !== 1 || !Array.isArray(manifest.corpora) || manifest.corpora.length === 0) {
      throw new Error("Unsupported or empty corpus preload manifest");
    }

    const loaded = await Promise.all(manifest.corpora.map(async function (entry) {
      const corpusUrl = new URL(entry.path, manifestResponse.url);
      const response = await fetch(corpusUrl.toString(), { cache: "no-cache" });
      if (!response.ok) throw new Error("Could not fetch corpus " + entry.id + ": HTTP " + response.status);
      const raw = await response.text();
      return { entry: entry, raw: raw, parsed: parseConllu(raw, entry) };
    }));

    try {
      await persistPreload(manifest, loaded);
    } catch (error) {
      console.warn("Aristos could not persist corpus preload data", error);
    }

    return { manifest: manifest, corpora: loaded, cached: false };
  }

  async function load() {
    try {
      return await fetchPreload();
    } catch (networkError) {
      try {
        return await loadCachedPreload();
      } catch (_) {
        throw networkError;
      }
    }
  }

  async function saveProgress(progress) {
    const database = await openDatabase();
    try {
      const transaction = database.transaction("progress", "readwrite");
      transaction.objectStore("progress").put(Object.assign({}, progress, {
        updatedAt: new Date().toISOString()
      }));
      await transactionComplete(transaction);
    } finally {
      database.close();
    }
  }

  global.AristosPreload = {
    load: load,
    parseConllu: parseConllu,
    saveProgress: saveProgress
  };
})(window);
