#!/usr/bin/env swift

import Foundation

private struct PageEnvelope: Decodable {
    var data: [ImageRecord]
}

private struct ImageRecord: Decodable {
    struct Hashes: Decodable {
        var sha256: String
    }

    struct Image: Decodable {
        struct Raw: Decodable {
            var url: String
        }

        var raw: Raw
    }

    var id: Int
    var index: String?
    var indexNumeric: Double?
    var language: String?
    var type: String?
    var hashes: Hashes
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

private struct ReviewItem: Codable {
    var id: String
    var imageURL: String
    var sourceURL: String?
    var sourceGroup: String
    var seriesID: String
    var seriesTitle: String
    var language: String?
    var type: String?
    var index: String?
    var sha256: String
}

private struct ReviewGroup: Codable {
    var id: String
    var type: String
    var index: String
    var indexNumeric: Double
    var items: [ReviewItem]
}

private let fileManager = FileManager.default
private let repoRoot = URL(
    fileURLWithPath: fileManager.currentDirectoryPath,
    isDirectory: true
)
private let auditRoot = repoRoot
    .appendingPathComponent("build/OnePieceSafetyAudit", isDirectory: true)
private let pagesDirectory = auditRoot.appendingPathComponent("pages", isDirectory: true)
private let coversDirectory = auditRoot.appendingPathComponent("covers", isDirectory: true)
private let outputDirectory = repoRoot
    .appendingPathComponent("build/OnePieceSafetyReview", isDirectory: true)
private let outputURL = outputDirectory.appendingPathComponent("index.html")

private let languageOrder = ["ja", "en", "de", "fr", "it", "ko", "pt"]

private func typeRank(_ type: String) -> Int {
    switch type {
    case "volume": 0
    case "volume_back": 1
    default: 2
    }
}

private func displayIndex(_ record: ImageRecord) -> String {
    if let index = record.index, !index.isEmpty {
        return index
    }
    guard let number = record.indexNumeric else { return "0" }
    return number.rounded() == number ? String(Int(number)) : String(number)
}

private func loadRecords() throws -> [ImageRecord] {
    let pageURLs = try fileManager.contentsOfDirectory(
        at: pagesDirectory,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }
    let decoder = JSONDecoder()
    return try pageURLs.flatMap { pageURL in
        try decoder.decode(
            PageEnvelope.self,
            from: Data(contentsOf: pageURL)
        ).data
    }
}

private func makeDeck(from records: [ImageRecord]) -> [ReviewGroup] {
    let available = records.filter { record in
        fileManager.fileExists(
            atPath: coversDirectory
                .appendingPathComponent("\(record.id).jpg")
                .path(percentEncoded: false)
        )
    }
    let grouped = Dictionary(grouping: available) { record in
        "\(record.type ?? "other")|\(displayIndex(record))"
    }
    return grouped.map { key, records in
        let first = records[0]
        let type = first.type ?? "other"
        let index = displayIndex(first)
        let number = first.indexNumeric ?? Double(index) ?? 0
        let items = records.sorted { left, right in
            let leftLanguage = languageOrder.firstIndex(of: left.language ?? "")
                ?? languageOrder.count
            let rightLanguage = languageOrder.firstIndex(of: right.language ?? "")
                ?? languageOrder.count
            if leftLanguage != rightLanguage {
                return leftLanguage < rightLanguage
            }
            return left.id < right.id
        }.map { record in
            ReviewItem(
                id: "one-piece-377-\(record.id)",
                imageURL: coversDirectory
                    .appendingPathComponent("\(record.id).jpg")
                    .absoluteString,
                sourceURL: record.image.raw.url,
                sourceGroup: "One Piece human review",
                seriesID: "377",
                seriesTitle: "ONE PIECE",
                language: record.language,
                type: record.type,
                index: displayIndex(record),
                sha256: record.hashes.sha256
            )
        }
        return ReviewGroup(
            id: key,
            type: type,
            index: index,
            indexNumeric: number,
            items: items
        )
    }.sorted { left, right in
        let leftRank = typeRank(left.type)
        let rightRank = typeRank(right.type)
        if leftRank != rightRank { return leftRank < rightRank }
        if left.indexNumeric != right.indexNumeric {
            return left.indexNumeric < right.indexNumeric
        }
        return left.index < right.index
    }
}

private let pageTemplate = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>One Piece Cover Safety Review</title>
  <style>
    :root {
      color-scheme: light dark;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --line: color-mix(in srgb, CanvasText 17%, transparent);
      --subtle: color-mix(in srgb, CanvasText 6%, Canvas);
      --muted: color-mix(in srgb, CanvasText 65%, transparent);
      --safe: #27824f;
      --suggestive: #b67a00;
      --erotica: #c45518;
      --pornographic: #b8323a;
    }
    * { box-sizing: border-box; letter-spacing: 0; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    button, select, textarea, input { font: inherit; }
    button, label.import { min-height: 40px; cursor: pointer; }
    button:focus-visible, select:focus-visible, textarea:focus-visible, input:focus-visible {
      outline: 3px solid AccentColor;
      outline-offset: 2px;
    }
    header {
      position: sticky;
      top: 0;
      z-index: 4;
      padding: 12px 18px;
      border-bottom: 1px solid var(--line);
      background: Canvas;
    }
    .header-row, .toolbar, .group-nav, .summary, .bulk-ratings {
      display: flex;
      align-items: center;
      gap: 10px;
      flex-wrap: wrap;
    }
    h1 { margin: 0 auto 0 0; font-size: 19px; }
    h2 { margin: 0; font-size: 18px; }
    progress { width: min(360px, 42vw); height: 12px; }
    .summary { margin-top: 8px; color: var(--muted); font-size: 13px; }
    main { padding: 16px 18px 22px; }
    .review-head {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 14px;
      align-items: end;
      padding-bottom: 14px;
    }
    .eyebrow { color: var(--muted); font-size: 13px; margin-bottom: 4px; }
    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(185px, 1fr));
      gap: 12px;
      align-items: start;
    }
    .cover-card {
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
      background: var(--subtle);
    }
    .cover-frame {
      aspect-ratio: 2 / 3;
      display: grid;
      place-items: center;
      background: Canvas;
      border-bottom: 1px solid var(--line);
      overflow: hidden;
    }
    .cover-frame img { width: 100%; height: 100%; object-fit: contain; display: block; }
    .card-body { padding: 10px; }
    .card-title { display: flex; justify-content: space-between; gap: 8px; align-items: baseline; }
    .language { font-weight: 700; text-transform: uppercase; }
    .item-number { color: var(--muted); font-size: 12px; }
    .card-ratings { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 5px; margin-top: 9px; }
    .rating-button, .secondary, label.import {
      border: 1px solid var(--line);
      border-radius: 6px;
      background: Canvas;
      color: CanvasText;
    }
    .rating-button { padding: 7px 4px; font-weight: 700; }
    .rating-button[data-rating="safe"] { color: var(--safe); }
    .rating-button[data-rating="suggestive"] { color: var(--suggestive); }
    .rating-button[data-rating="erotica"] { color: var(--erotica); }
    .rating-button[data-rating="pornographic"] { color: var(--pornographic); }
    .rating-button[aria-pressed="true"] { color: white; border-color: transparent; }
    .rating-button[data-rating="safe"][aria-pressed="true"] { background: var(--safe); }
    .rating-button[data-rating="suggestive"][aria-pressed="true"] { background: var(--suggestive); }
    .rating-button[data-rating="erotica"][aria-pressed="true"] { background: var(--erotica); }
    .rating-button[data-rating="pornographic"][aria-pressed="true"] { background: var(--pornographic); }
    textarea {
      width: 100%;
      min-height: 54px;
      margin-top: 8px;
      padding: 7px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: Canvas;
      color: CanvasText;
    }
    .bulk-ratings { justify-content: flex-end; }
    .bulk-ratings .rating-button { padding: 8px 11px; }
    .secondary, label.import { padding: 8px 11px; }
    label.import { display: inline-flex; align-items: center; }
    select { min-height: 38px; padding: 5px 28px 5px 9px; }
    .check { display: inline-flex; align-items: center; gap: 6px; min-height: 38px; }
    .check input { width: 18px; height: 18px; }
    .empty { padding: 70px 20px; text-align: center; color: var(--muted); }
    .legend { margin: 0 0 12px; color: var(--muted); font-size: 13px; }
    footer { padding: 10px 18px; border-top: 1px solid var(--line); color: var(--muted); font-size: 12px; }
    @media (max-width: 760px) {
      .review-head { grid-template-columns: 1fr; }
      .bulk-ratings { justify-content: flex-start; }
      progress { width: 100%; }
      .cards { grid-template-columns: repeat(auto-fit, minmax(155px, 1fr)); }
    }
  </style>
</head>
<body>
  <header>
    <div class="header-row">
      <h1>One Piece Cover Safety Review</h1>
      <span id="progressText" aria-live="polite"></span>
      <progress id="progress" max="1" value="0"></progress>
    </div>
    <div class="summary">
      <span id="counts"></span>
      <span>Blind human review: existing MangaBaka safety labels are not shown or imported.</span>
    </div>
    <div class="toolbar">
      <select id="section" aria-label="Cover section">
        <option value="all">All cover types</option>
        <option value="volume">Front covers</option>
        <option value="volume_back">Back covers</option>
        <option value="other">Other images</option>
      </select>
      <label class="check"><input id="unjudged" type="checkbox"> Unjudged groups only</label>
      <button class="secondary" id="undo">Undo</button>
      <button class="secondary" id="export">Export judgments</button>
      <label class="import">Import<input id="import" type="file" accept="application/json" hidden></label>
    </div>
  </header>

  <main>
    <div class="review-head">
      <div>
        <div class="eyebrow" id="groupProgress"></div>
        <h2 id="groupTitle"></h2>
      </div>
      <div class="bulk-ratings" aria-label="Rate every cover shown">
        <button class="rating-button" data-bulk-rating="safe">All Safe</button>
        <button class="rating-button" data-bulk-rating="suggestive">All Suggestive</button>
        <button class="rating-button" data-bulk-rating="erotica">All Erotica</button>
        <button class="rating-button" data-bulk-rating="pornographic">All Pornographic</button>
      </div>
    </div>
    <p class="legend">Safe: no sexual theme. Suggestive: swimsuit, lingerie, cleavage, sexualized pose or framing. Erotica: nudity focus, exposed buttocks or bondage. Pornographic: genitals, sex acts, sexual fluids or sex toys.</p>
    <section id="cards" class="cards" aria-live="polite"></section>
    <p id="empty" class="empty" hidden>No groups match this view.</p>
    <div class="group-nav">
      <button class="secondary" id="previous">Previous</button>
      <button class="secondary" id="next">Next</button>
      <button class="secondary" id="clearGroup">Clear this group</button>
    </div>
  </main>
  <footer>Local review page for MangaBaka series 377. Images stay on this Mac; only an exported JSON file leaves the page.</footer>

<script>
const bytes = Uint8Array.from(atob("__DECK_BASE64__"), value => value.charCodeAt(0));
const deck = JSON.parse(new TextDecoder().decode(bytes));
const byItemID = new Map(deck.flatMap(group => group.items).map(item => [item.id, item]));
const storageKey = 'sable-one-piece-safety-review-human-v1';
let saved = JSON.parse(localStorage.getItem(storageKey) || '{"decisions":{},"history":[],"groupID":null}');
saved.decisions ||= {};
saved.history ||= [];

const cards = document.querySelector('#cards');
const empty = document.querySelector('#empty');
const progress = document.querySelector('#progress');
const progressText = document.querySelector('#progressText');
const counts = document.querySelector('#counts');
const groupTitle = document.querySelector('#groupTitle');
const groupProgress = document.querySelector('#groupProgress');
const section = document.querySelector('#section');
const unjudged = document.querySelector('#unjudged');
let visibleGroups = [];
let cursor = 0;

function persist() {
  saved.groupID = visibleGroups[cursor]?.id || saved.groupID;
  localStorage.setItem(storageKey, JSON.stringify(saved));
}

function groupComplete(group) {
  return group.items.every(item => saved.decisions[item.id]);
}

function typeLabel(type) {
  if (type === 'volume') return 'Front cover';
  if (type === 'volume_back') return 'Back cover';
  return 'Other image';
}

function rebuildVisibleGroups(keepID) {
  visibleGroups = deck.filter(group => {
    const sectionMatches = section.value === 'all'
      || group.type === section.value
      || (section.value === 'other' && !['volume', 'volume_back'].includes(group.type));
    return sectionMatches && (!unjudged.checked || !groupComplete(group));
  });
  const targetID = keepID || saved.groupID;
  const targetIndex = visibleGroups.findIndex(group => group.id === targetID);
  cursor = targetIndex >= 0 ? targetIndex : Math.min(cursor, Math.max(0, visibleGroups.length - 1));
}

function updateProgress() {
  const decisions = Object.entries(saved.decisions).filter(([id]) => byItemID.has(id));
  const tally = {safe: 0, suggestive: 0, erotica: 0, pornographic: 0};
  decisions.forEach(([, decision]) => { if (tally[decision.rating] !== undefined) tally[decision.rating] += 1; });
  progress.max = byItemID.size;
  progress.value = decisions.length;
  progressText.textContent = `${decisions.length} of ${byItemID.size} covers judged`;
  counts.textContent = `Safe ${tally.safe} · Suggestive ${tally.suggestive} · Erotica ${tally.erotica} · Pornographic ${tally.pornographic}`;
}

function makeRatingButton(item, rating, shortLabel) {
  const button = document.createElement('button');
  button.className = 'rating-button';
  button.dataset.rating = rating;
  button.textContent = shortLabel;
  button.setAttribute('aria-label', `Rate ${item.language || 'unknown language'} ${rating}`);
  button.setAttribute('aria-pressed', saved.decisions[item.id]?.rating === rating ? 'true' : 'false');
  button.addEventListener('click', () => rateItems([item], rating));
  return button;
}

function makeCard(item) {
  const article = document.createElement('article');
  article.className = 'cover-card';
  const frame = document.createElement('div');
  frame.className = 'cover-frame';
  const image = document.createElement('img');
  image.src = item.imageURL;
  image.alt = `${item.seriesTitle}, ${typeLabel(item.type)}, number ${item.index}, ${item.language || 'unknown language'}`;
  image.loading = 'eager';
  frame.appendChild(image);

  const body = document.createElement('div');
  body.className = 'card-body';
  const title = document.createElement('div');
  title.className = 'card-title';
  const language = document.createElement('span');
  language.className = 'language';
  language.textContent = item.language || 'und';
  const number = document.createElement('span');
  number.className = 'item-number';
  number.textContent = `#${item.index}`;
  title.append(language, number);

  const ratingGrid = document.createElement('div');
  ratingGrid.className = 'card-ratings';
  ratingGrid.append(
    makeRatingButton(item, 'safe', 'Safe'),
    makeRatingButton(item, 'suggestive', 'Sug.'),
    makeRatingButton(item, 'erotica', 'Erot.'),
    makeRatingButton(item, 'pornographic', 'Porn.')
  );

  const note = document.createElement('textarea');
  note.placeholder = 'Optional note';
  note.setAttribute('aria-label', `Optional note for ${item.language || 'unknown language'} cover`);
  note.value = saved.decisions[item.id]?.note || '';
  note.addEventListener('change', () => {
    if (!saved.decisions[item.id]) return;
    saved.decisions[item.id].note = note.value.trim();
    persist();
  });
  body.append(title, ratingGrid, note);
  article.append(frame, body);
  return article;
}

function render() {
  updateProgress();
  const group = visibleGroups[cursor];
  const hasGroup = Boolean(group);
  cards.hidden = !hasGroup;
  empty.hidden = hasGroup;
  document.querySelectorAll('[data-bulk-rating], #clearGroup').forEach(button => button.disabled = !hasGroup);
  document.querySelector('#previous').disabled = !hasGroup || cursor === 0;
  document.querySelector('#next').disabled = !hasGroup || cursor >= visibleGroups.length - 1;
  if (!group) {
    groupTitle.textContent = 'Review complete';
    groupProgress.textContent = 'No remaining cover groups';
    cards.replaceChildren();
    return;
  }
  saved.groupID = group.id;
  groupTitle.textContent = `${typeLabel(group.type)} ${group.index}`;
  groupProgress.textContent = `Group ${cursor + 1} of ${visibleGroups.length} · ${group.items.length} language edition${group.items.length === 1 ? '' : 's'}`;
  cards.replaceChildren(...group.items.map(makeCard));
  persist();
}

function rateItems(items, rating) {
  const previous = items.map(item => [item.id, saved.decisions[item.id] || null]);
  saved.history.push(previous);
  for (const item of items) {
    saved.decisions[item.id] = {
      rating,
      note: saved.decisions[item.id]?.note || '',
      reviewedAt: new Date().toISOString()
    };
  }
  if (saved.history.length > 100) saved.history.shift();
  const currentID = visibleGroups[cursor]?.id;
  rebuildVisibleGroups(currentID);
  if (!visibleGroups[cursor] || visibleGroups[cursor].id !== currentID) {
    cursor = Math.min(cursor, Math.max(0, visibleGroups.length - 1));
  } else if (groupComplete(visibleGroups[cursor]) && cursor < visibleGroups.length - 1) {
    cursor += 1;
  }
  persist();
  render();
}

function undo() {
  const operation = saved.history.pop();
  if (!operation) return;
  for (const [id, previous] of operation) {
    if (previous) saved.decisions[id] = previous;
    else delete saved.decisions[id];
  }
  const restoredGroup = deck.find(group => group.items.some(item => operation.some(([id]) => id === item.id)));
  rebuildVisibleGroups(restoredGroup?.id);
  persist();
  render();
}

function clearGroup() {
  const group = visibleGroups[cursor];
  if (!group) return;
  const previous = group.items.map(item => [item.id, saved.decisions[item.id] || null]);
  saved.history.push(previous);
  group.items.forEach(item => delete saved.decisions[item.id]);
  rebuildVisibleGroups(group.id);
  persist();
  render();
}

function exportJudgments() {
  const reviewed = deck.flatMap(group => group.items)
    .filter(item => saved.decisions[item.id])
    .map(item => ({...item, ...saved.decisions[item.id]}));
  const payload = {
    schemaVersion: 1,
    ruleVersion: 'sable-cover-safety-human-only-2026-08-03',
    exportedAt: new Date().toISOString(),
    reviewedCount: reviewed.length,
    items: reviewed
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], {type: 'application/json'});
  const anchor = document.createElement('a');
  anchor.href = URL.createObjectURL(blob);
  anchor.download = `sable-one-piece-safety-judgments-${new Date().toISOString().slice(0, 10)}.json`;
  anchor.click();
  URL.revokeObjectURL(anchor.href);
}

document.querySelectorAll('[data-bulk-rating]').forEach(button => {
  button.addEventListener('click', () => {
    const group = visibleGroups[cursor];
    if (group) rateItems(group.items, button.dataset.bulkRating);
  });
});
document.querySelector('#previous').addEventListener('click', () => { if (cursor > 0) { cursor -= 1; render(); } });
document.querySelector('#next').addEventListener('click', () => { if (cursor < visibleGroups.length - 1) { cursor += 1; render(); } });
document.querySelector('#undo').addEventListener('click', undo);
document.querySelector('#clearGroup').addEventListener('click', clearGroup);
document.querySelector('#export').addEventListener('click', exportJudgments);
section.addEventListener('change', () => { rebuildVisibleGroups(); render(); });
unjudged.addEventListener('change', () => { rebuildVisibleGroups(); render(); });
document.querySelector('#import').addEventListener('change', async event => {
  const file = event.target.files[0];
  if (!file) return;
  try {
    const payload = JSON.parse(await file.text());
    for (const item of payload.items || []) {
      if (byItemID.has(item.id) && ['safe', 'suggestive', 'erotica', 'pornographic'].includes(item.rating)) {
        saved.decisions[item.id] = {
          rating: item.rating,
          note: item.note || '',
          reviewedAt: item.reviewedAt || new Date().toISOString()
        };
      }
    }
    rebuildVisibleGroups();
    persist();
    render();
  } catch {
    alert('That judgment file could not be imported.');
  }
});

rebuildVisibleGroups();
render();
</script>
</body>
</html>
"""#

guard fileManager.fileExists(atPath: pagesDirectory.path(percentEncoded: false)),
      fileManager.fileExists(atPath: coversDirectory.path(percentEncoded: false)) else {
    fputs("One Piece audit pages and covers were not found under build/OnePieceSafetyAudit.\n", stderr)
    exit(EXIT_FAILURE)
}

private let records = try loadRecords()
private let deck = makeDeck(from: records)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let deckData = try encoder.encode(deck)
let html = pageTemplate.replacingOccurrences(
    of: "__DECK_BASE64__",
    with: deckData.base64EncodedString()
)
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try html.write(to: outputURL, atomically: true, encoding: .utf8)

let itemCount = deck.reduce(0) { $0 + $1.items.count }
let typeCounts = Dictionary(grouping: deck, by: \.type).mapValues { groups in
    groups.reduce(0) { $0 + $1.items.count }
}
print("Wrote \(itemCount) blind One Piece covers in \(deck.count) groups")
print("Review page: \(outputURL.path(percentEncoded: false))")
for type in typeCounts.keys.sorted(by: { typeRank($0) < typeRank($1) }) {
    print("  \(type): \(typeCounts[type, default: 0])")
}
