#!/usr/bin/env swift

import CryptoKit
import Foundation

private struct ComicInfo: Decodable {
    var title: String?
    var publishers: [String]?
}

private struct CoverManifest: Decodable {
    struct Entry: Decodable {
        var covers: [Cover]
    }

    struct Cover: Decodable {
        var language: String?
        var path: String
        var providerItemID: String?
        var providerSeriesID: String?
        var providerTitle: String?
        var providerVolume: Double?
        var role: String?
        var source: String?
        var url: String?

        enum CodingKeys: String, CodingKey {
            case language
            case path
            case providerItemID = "provider_item_id"
            case providerSeriesID = "provider_series_id"
            case providerTitle = "provider_title"
            case providerVolume = "provider_volume"
            case role
            case source
            case url
        }
    }

    var entries: [Entry]
    var seriesTitle: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case seriesTitle = "series_title"
    }
}

private struct APIImagesEnvelope: Decodable {
    struct ImageRecord: Decodable {
        struct Hashes: Decodable {
            var sha256: String?
        }

        struct Image: Decodable {
            struct Raw: Decodable {
                var url: String
            }

            struct Sized: Decodable {
                var x2: String?
            }

            var raw: Raw
            var x350: Sized?
        }

        var id: Int
        var index: String?
        var indexNumeric: Double?
        var language: String?
        var type: String?
        var hashes: Hashes?
        var image: Image

        enum CodingKeys: String, CodingKey {
            case id
            case index
            case indexNumeric = "index_numeric"
            case language
            case type
            case hashes
            case image
        }
    }

    var data: [ImageRecord]
}

private struct APISeriesEnvelope: Decodable {
    struct Series: Decodable {
        var id: Int
        var title: String
    }

    var data: Series
}

private struct ReviewItem: Codable {
    var id: String
    var imageURL: String
    var sourceURL: String?
    var sourceGroup: String
    var seriesID: String?
    var seriesTitle: String
    var language: String?
    var type: String?
    var index: String?
    var sha256: String
}

private struct LocalCandidate {
    var item: ReviewItem
    var fileURL: URL
}

private let fileManager = FileManager.default
private let decoder = JSONDecoder()
private let repoRoot = URL(
    fileURLWithPath: fileManager.currentDirectoryPath,
    isDirectory: true
)
private let libraryRoot = fileManager.homeDirectoryForCurrentUser
    .appendingPathComponent("Downloads/Torika Library", isDirectory: true)
private let outputDirectory = repoRoot
    .appendingPathComponent("build/CoverSafetyReview", isDirectory: true)
private let outputURL = outputDirectory.appendingPathComponent("index.html")
private let apiCache = repoRoot
    .appendingPathComponent("build/CoverSafetyML/api-cache", isDirectory: true)
private let calibrationSeriesIDs = Set([
    1654, 36935, 1729, 766, 9620, 1576, 7204, 79765, 55040, 4726,
    99758, 121262, 287224, 584916, 590438, 590739,
])

private func stableDigest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

private func fileDigest(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
        return nil
    }
    return SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func displayIndex(_ value: Double?) -> String? {
    guard let value else { return nil }
    return value.rounded() == value ? String(Int(value)) : String(value)
}

private func publisherGroup(_ publishers: [String]) -> String {
    let normalized = publishers.joined(separator: " ").lowercased()
    if normalized.contains("yen press") || normalized.contains("yen on") {
        return "Yen Press / Yen On"
    }
    if normalized.contains("seven seas") || normalized.contains("ghost ship")
        || normalized.contains("airship") {
        return "Seven Seas / Ghost Ship"
    }
    if normalized.contains("j-novel") || normalized.contains("j novel")
        || normalized.contains("jnc") {
        return "J-Novel Club"
    }
    return "Local library mix"
}

private func collectLocalCandidates() -> [LocalCandidate] {
    guard let enumerator = fileManager.enumerator(
        at: libraryRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }

    var candidates: [LocalCandidate] = []
    for case let manifestURL as URL in enumerator
    where manifestURL.lastPathComponent == "cover-manifest.json" {
        let seriesDirectory = manifestURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let comicInfoURL = seriesDirectory.appendingPathComponent("ComicInfo.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(CoverManifest.self, from: manifestData)
        else { continue }
        let comicInfo = (try? Data(contentsOf: comicInfoURL))
            .flatMap { try? decoder.decode(ComicInfo.self, from: $0) }
        let title = comicInfo?.title
            ?? manifest.seriesTitle
            ?? seriesDirectory.lastPathComponent
        let group = publisherGroup(comicInfo?.publishers ?? [])

        for cover in manifest.entries.flatMap(\.covers) {
            let fileURL = seriesDirectory
                .appendingPathComponent(cover.path)
                .standardizedFileURL
            guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                continue
            }
            let identityParts: [String] = [
                cover.providerSeriesID ?? title,
                cover.language ?? "unknown",
                cover.role ?? "cover",
                cover.providerVolume.map { String($0) }
                    ?? cover.providerItemID
                    ?? cover.path,
            ]
            let identity = identityParts.joined(separator: "|")
            candidates.append(LocalCandidate(
                item: ReviewItem(
                    id: "local-\(stableDigest(identity).prefix(20))",
                    imageURL: fileURL.absoluteString,
                    sourceURL: cover.url,
                    sourceGroup: group,
                    seriesID: cover.providerSeriesID,
                    seriesTitle: cover.providerTitle ?? title,
                    language: cover.language,
                    type: cover.role,
                    index: displayIndex(cover.providerVolume),
                    sha256: ""
                ),
                fileURL: fileURL
            ))
        }
    }
    return candidates
}

private func roundRobinLocalSample(
    _ candidates: [LocalCandidate],
    perGroup: Int
) -> [ReviewItem] {
    let byGroup = Dictionary(grouping: candidates, by: { $0.item.sourceGroup })
    var result: [ReviewItem] = []
    for group in [
        "Yen Press / Yen On",
        "Seven Seas / Ghost Ship",
        "J-Novel Club",
        "Local library mix",
    ] {
        let values = byGroup[group] ?? []
        let bySeries = Dictionary(grouping: values) {
            $0.item.seriesID ?? $0.item.seriesTitle
        }.mapValues {
            $0.sorted { stableDigest($0.item.id) < stableDigest($1.item.id) }
        }
        let seriesKeys = bySeries.keys.sorted {
            stableDigest($0) < stableDigest($1)
        }
        var selected: [LocalCandidate] = []
        var round = 0
        while selected.count < perGroup {
            var added = false
            for key in seriesKeys where selected.count < perGroup {
                guard let series = bySeries[key], round < series.count else { continue }
                selected.append(series[round])
                added = true
            }
            guard added else { break }
            round += 1
        }
        for candidate in selected {
            guard let digest = fileDigest(candidate.fileURL) else { continue }
            var item = candidate.item
            item.sha256 = digest
            result.append(item)
        }
    }
    return result
}

private func collectCalibrationItems(limitPerSeries: Int) -> [ReviewItem] {
    var result: [ReviewItem] = []
    for seriesID in calibrationSeriesIDs.sorted() {
        let seriesCache = apiCache.appendingPathComponent("series-\(seriesID).json")
        let seriesEnvelope = (try? Data(contentsOf: seriesCache))
            .flatMap { try? decoder.decode(APISeriesEnvelope.self, from: $0) }
        let seriesTitle = seriesEnvelope?.data.title
            ?? "MangaBaka series \(seriesID)"
        var records: [APIImagesEnvelope.ImageRecord] = []
        for page in 1...20 {
            let cacheURL = apiCache.appendingPathComponent("images-\(seriesID)-\(page).json")
            guard let data = try? Data(contentsOf: cacheURL),
                  let envelope = try? decoder.decode(APIImagesEnvelope.self, from: data)
            else { break }
            records.append(contentsOf: envelope.data)
        }
        let selected = records.sorted {
            stableDigest("\($0.id)") < stableDigest("\($1.id)")
        }.prefix(limitPerSeries)
        for record in selected {
            let imageURL = record.image.x350?.x2 ?? record.image.raw.url
            let digest = record.hashes?.sha256
                ?? stableDigest(imageURL)
            result.append(ReviewItem(
                id: "api-\(seriesID)-\(record.id)",
                imageURL: imageURL,
                sourceURL: "https://mangabaka.org/\(seriesID)/covers",
                sourceGroup: "Earlier calibration mix",
                seriesID: String(seriesID),
                seriesTitle: seriesTitle,
                language: record.language,
                type: record.type,
                index: record.index ?? displayIndex(record.indexNumeric),
                sha256: digest
            ))
        }
    }
    return result
}

private let pageTemplate = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Sable Cover Safety Review</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    button, textarea, select { font: inherit; }
    button { min-height: 42px; cursor: pointer; }
    .app { min-height: 100vh; display: grid; grid-template-rows: auto 1fr auto; }
    header { position: sticky; top: 0; z-index: 2; padding: 12px 18px; border-bottom: 1px solid color-mix(in srgb, CanvasText 18%, transparent); background: Canvas; }
    .topline, .toolbar, .counts { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    h1 { font-size: 18px; margin: 0 auto 0 0; }
    progress { width: min(340px, 50vw); height: 12px; }
    .muted { color: color-mix(in srgb, CanvasText 65%, transparent); }
    main { min-height: 0; display: grid; grid-template-columns: minmax(320px, 1fr) minmax(340px, 460px); gap: 18px; padding: 18px; }
    .image-stage { min-height: 420px; display: grid; place-items: center; background: color-mix(in srgb, CanvasText 5%, Canvas); border: 1px solid color-mix(in srgb, CanvasText 15%, transparent); border-radius: 8px; overflow: hidden; }
    #cover { max-width: 100%; max-height: calc(100vh - 190px); object-fit: contain; display: block; }
    .panel { display: flex; flex-direction: column; gap: 14px; }
    .rules { margin: 0; padding-left: 20px; line-height: 1.4; }
    .rating-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .rating { text-align: left; padding: 12px; border: 2px solid transparent; border-radius: 7px; background: color-mix(in srgb, AccentColor 13%, Canvas); color: CanvasText; }
    .rating strong { display: block; font-size: 16px; }
    .rating span { display: block; margin-top: 3px; font-size: 12px; color: color-mix(in srgb, CanvasText 70%, transparent); }
    .rating:focus-visible, button:focus-visible, textarea:focus-visible { outline: 3px solid AccentColor; outline-offset: 2px; }
    textarea { width: 100%; min-height: 78px; resize: vertical; padding: 9px; border-radius: 6px; border: 1px solid color-mix(in srgb, CanvasText 24%, transparent); }
    .secondary { background: color-mix(in srgb, CanvasText 8%, Canvas); color: CanvasText; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 6px; padding: 8px 12px; }
    details { border-top: 1px solid color-mix(in srgb, CanvasText 15%, transparent); padding-top: 10px; }
    dl { display: grid; grid-template-columns: max-content 1fr; gap: 5px 10px; font-size: 13px; }
    dt { font-weight: 650; } dd { margin: 0; overflow-wrap: anywhere; }
    footer { padding: 10px 18px; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); font-size: 12px; }
    .done { padding: 40px; text-align: center; }
    @media (max-width: 850px) {
      main { grid-template-columns: 1fr; }
      #cover { max-height: 58vh; }
      .image-stage { min-height: 300px; }
    }
  </style>
</head>
<body>
<div class="app">
  <header>
    <div class="topline">
      <h1>Sable Cover Safety Review</h1>
      <span id="progressText" aria-live="polite"></span>
      <progress id="progress" max="1" value="0"></progress>
    </div>
    <div class="counts" id="counts"></div>
  </header>
  <main id="main">
    <section class="image-stage" aria-label="Cover to review">
      <p id="emptyState" class="done" hidden>Deck complete. Export your judgments, or undo the last one to review it again.</p>
      <img id="cover" alt="Cover awaiting a safety rating">
    </section>
    <section class="panel">
      <div>
        <strong>Judge only what is visible on this cover.</strong>
        <ul class="rules">
          <li><b>Safe:</b> no sexual theme.</li>
          <li><b>Suggestive:</b> swimsuit, lingerie, cleavage, provocative pose, or uncertain.</li>
          <li><b>Erotica:</b> nipples/buttocks, strong erotic near-nudity, bondage or restraints.</li>
          <li><b>Pornographic:</b> genitals, sex acts, sexual fluids or sex toys, including censored.</li>
        </ul>
      </div>
      <div class="rating-grid" aria-label="Safety rating">
        <button class="rating" data-rating="safe"><strong>1 · Safe</strong><span>No sexual theme</span></button>
        <button class="rating" data-rating="suggestive"><strong>2 · Suggestive</strong><span>Swimwear, lingerie, pose, uncertainty</span></button>
        <button class="rating" data-rating="erotica"><strong>3 · Erotica</strong><span>Explicit nudity focus or bondage</span></button>
        <button class="rating" data-rating="pornographic"><strong>4 · Pornographic</strong><span>Sex acts, genitals, fluids or toys</span></button>
      </div>
      <label for="note"><strong>Optional comment</strong></label>
      <textarea id="note" placeholder="What made this boundary clear or ambiguous?"></textarea>
      <div class="toolbar">
        <button class="secondary" id="undo">Undo last</button>
        <button class="secondary" id="skip">Skip for now</button>
        <button class="secondary" id="export">Export judgments</button>
        <label class="secondary">Import <input id="import" type="file" accept="application/json" hidden></label>
      </div>
      <p class="muted">Shortcuts: 1–4 rate, S skips, U undoes. Export whenever you like; you do not need to finish the whole deck.</p>
      <details>
        <summary>Cover details</summary>
        <dl id="details"></dl>
      </details>
    </section>
  </main>
  <footer>Private local review page. Images are loaded from your Torika library or their preserved MangaBaka source links. Nothing is uploaded or submitted.</footer>
</div>
<script>
const bytes = Uint8Array.from(atob("__DECK_BASE64__"), c => c.charCodeAt(0));
const deck = JSON.parse(new TextDecoder().decode(bytes));
const storageKey = "sable-cover-safety-review-v1";
let saved = JSON.parse(localStorage.getItem(storageKey) || '{"decisions":{},"order":[],"history":[]}');
const byId = new Map(deck.map(item => [item.id, item]));
saved.order = saved.order.filter(id => byId.has(id));
for (const item of deck) if (!saved.order.includes(item.id)) saved.order.push(item.id);
if (!localStorage.getItem(storageKey)) {
  for (let i = saved.order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [saved.order[i], saved.order[j]] = [saved.order[j], saved.order[i]];
  }
}
let cursor = Math.max(0, saved.order.findIndex(id => !saved.decisions[id]));
if (cursor < 0) cursor = 0;
const cover = document.querySelector('#cover');
const emptyState = document.querySelector('#emptyState');
const note = document.querySelector('#note');
const progress = document.querySelector('#progress');
const progressText = document.querySelector('#progressText');
const counts = document.querySelector('#counts');
const details = document.querySelector('#details');

function persist() { localStorage.setItem(storageKey, JSON.stringify(saved)); }
function currentId() { return saved.order[cursor]; }
function current() { return byId.get(currentId()); }
function completedCount() { return Object.keys(saved.decisions).filter(id => byId.has(id)).length; }
function detailRow(label, value) {
  if (!value) return '';
  const escaped = String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  return `<dt>${label}</dt><dd>${escaped}</dd>`;
}
function render() {
  const item = current();
  const done = completedCount();
  progress.max = deck.length;
  progress.value = done;
  progressText.textContent = `${done} of ${deck.length} judged`;
  const tally = {safe:0, suggestive:0, erotica:0, pornographic:0};
  Object.values(saved.decisions).forEach(d => { if (tally[d.rating] !== undefined) tally[d.rating]++; });
  counts.textContent = `Safe ${tally.safe} · Suggestive ${tally.suggestive} · Erotica ${tally.erotica} · Pornographic ${tally.pornographic}`;
  if (!item) {
    cover.hidden = true;
    emptyState.hidden = false;
    note.value = '';
    note.disabled = true;
    details.innerHTML = '';
    document.querySelectorAll('[data-rating]').forEach(button => button.disabled = true);
    return;
  }
  cover.hidden = false;
  emptyState.hidden = true;
  note.disabled = false;
  document.querySelectorAll('[data-rating]').forEach(button => button.disabled = false);
  cover.src = item.imageURL;
  cover.alt = `Cover awaiting a safety rating, item ${cursor + 1}`;
  note.value = saved.decisions[item.id]?.note || '';
  details.innerHTML = detailRow('Series', item.seriesTitle)
    + detailRow('Source group', item.sourceGroup)
    + detailRow('Language', item.language)
    + detailRow('Type', item.type)
    + detailRow('Number', item.index)
    + detailRow('Series ID', item.seriesID);
  const nextItem = byId.get(saved.order[cursor + 1]);
  if (nextItem) { const preload = new Image(); preload.src = nextItem.imageURL; }
}
function moveToNextUnjudged(start) {
  for (let offset = 1; offset <= saved.order.length; offset++) {
    const candidate = (start + offset) % saved.order.length;
    if (!saved.decisions[saved.order[candidate]]) { cursor = candidate; render(); return; }
  }
  cursor = saved.order.length;
  render();
}
function rate(rating) {
  const item = current(); if (!item) return;
  saved.decisions[item.id] = {
    rating,
    note: note.value.trim(),
    reviewedAt: new Date().toISOString()
  };
  saved.history.push(item.id);
  persist();
  moveToNextUnjudged(cursor);
}
function undo() {
  const id = saved.history.pop(); if (!id) return;
  delete saved.decisions[id];
  cursor = Math.max(0, saved.order.indexOf(id));
  persist(); render();
}
function skip() { moveToNextUnjudged(cursor); }
function exportJudgments() {
  const reviewed = deck.filter(item => saved.decisions[item.id]).map(item => ({
    ...item,
    ...saved.decisions[item.id]
  }));
  const payload = {
    schemaVersion: 1,
    ruleVersion: "sable-cover-safety-2026-08-03",
    exportedAt: new Date().toISOString(),
    reviewedCount: reviewed.length,
    items: reviewed
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], {type:'application/json'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `sable-cover-safety-judgments-${new Date().toISOString().slice(0,10)}.json`;
  a.click(); URL.revokeObjectURL(a.href);
}
document.querySelectorAll('[data-rating]').forEach(button => button.addEventListener('click', () => rate(button.dataset.rating)));
document.querySelector('#undo').addEventListener('click', undo);
document.querySelector('#skip').addEventListener('click', skip);
document.querySelector('#export').addEventListener('click', exportJudgments);
document.querySelector('#import').addEventListener('change', async event => {
  const file = event.target.files[0]; if (!file) return;
  try {
    const payload = JSON.parse(await file.text());
    for (const item of payload.items || []) {
      if (byId.has(item.id) && ['safe','suggestive','erotica','pornographic'].includes(item.rating)) {
        saved.decisions[item.id] = {rating:item.rating, note:item.note || '', reviewedAt:item.reviewedAt || new Date().toISOString()};
      }
    }
    persist();
    const nextUnjudged = saved.order.findIndex(id => !saved.decisions[id]);
    cursor = nextUnjudged < 0 ? saved.order.length : nextUnjudged;
    render();
  } catch { alert('That file could not be imported.'); }
});
document.addEventListener('keydown', event => {
  if (event.target === note) return;
  if (event.key === '1') rate('safe');
  if (event.key === '2') rate('suggestive');
  if (event.key === '3') rate('erotica');
  if (event.key === '4') rate('pornographic');
  if (event.key.toLowerCase() === 's') skip();
  if (event.key.toLowerCase() === 'u') undo();
});
cover.addEventListener('error', () => { cover.alt = 'Cover image could not be loaded; skip this item.'; });
persist(); render();
</script>
</body>
</html>
"""#

guard fileManager.fileExists(atPath: libraryRoot.path(percentEncoded: false)) else {
    fputs("Torika Library was not found at \(libraryRoot.path(percentEncoded: false))\n", stderr)
    exit(EXIT_FAILURE)
}

private let local = roundRobinLocalSample(collectLocalCandidates(), perGroup: 45)
private let calibration = collectCalibrationItems(limitPerSeries: 6)
private var seenHashes = Set<String>()
private let deck = (local + calibration).filter { seenHashes.insert($0.sha256).inserted }
    .sorted { stableDigest($0.id) < stableDigest($1.id) }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let deckData = try encoder.encode(deck)
let html = pageTemplate.replacingOccurrences(
    of: "__DECK_BASE64__",
    with: deckData.base64EncodedString()
)
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try html.write(to: outputURL, atomically: true, encoding: .utf8)

let counts = Dictionary(grouping: deck, by: \.sourceGroup).mapValues(\.count)
print("Wrote \(deck.count) blind review covers to \(outputURL.path(percentEncoded: false))")
for key in counts.keys.sorted() {
    print("  \(key): \(counts[key, default: 0])")
}
