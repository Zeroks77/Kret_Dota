# Replay Parsing & Enrichment

This folder contains scripts to enrich match data using two approaches:

1) Own parser (primary):
   - Download Valve replay files and run your parser (Node/Python) to extract events and metrics (stacks, blocked camps, farmed camps with owners, smokes, objectives, ward lifetimes, item timings, etc.).

Note: The previous OpenDota-based enrichment path has been removed to standardize on the own replay parser.

## 2) Full replay parsing (optional)

### Step A: Ingest in small batches (max 5)

- Requires a local mapping `match_id -> (cluster, replay_salt)` via CSV. No OpenDota API calls are made.
- Use the orchestrator to download → parse → cleanup in batches up to 5 (good for GitHub Actions storage limits).

```powershell
# From a file (one match ID per line)
pwsh -File scripts/ingest_batch.ps1 -Source list -MatchListFile scripts/sample_match_ids.txt -MappingCsv scripts/replay_mapping.csv -ParserCmd "node scripts/parser/stub.js --in {in} --out {out}" -BatchSize 5

# Daily (Kret Daily): takes a single date, finds matches in data/matches/YYYY-MM.json
pwsh -File scripts/ingest_daily.ps1 -Date 2025-09-23 -MappingCsv scripts/replay_mapping.csv -ParserCmd "node scripts/parser/stub.js --in {in} --out {out}"

# League: uses chunks/league/<CODE>/matches.json
pwsh -File scripts/ingest_league.ps1 -LeagueCode TI2025 -MappingCsv scripts/replay_mapping.csv -ParserCmd "node scripts/parser/stub.js --in {in} --out {out}"
```

Files are streamed in batches; replays are deleted after parsing unless you pass `-KeepReplays` to `ingest_batch.ps1`.

### Step B: Parser implementation

Provide a parser command template that accepts `{in}` and `{out}` placeholders. We suggest Clarity (Java) or a Node wrapper. A temporary stub exists at `scripts/parser/stub.js` for wiring.

```powershell
# Node example (direct, if you downloaded separately)
pwsh -File scripts/parse_replays.ps1 -ParserCmd "node scripts/parser/stub.js --in {in} --out {out}" -Limit 10

# Python example
pwsh -File scripts/parse_replays.ps1 -ParserCmd "python scripts/replay_parser.py --in {in} --out {out}"
```

Expected output is one JSON per match at `data/enriched/matches/<match_id>.json` conforming to `schemas/enriched_match.schema.json`.

### Schema

See `schemas/enriched_match.schema.json` for the normalized enriched output (item_first_purchase, wards, stacks, smokes, objectives, …).

## Integration ideas

- Add an enrichment merge step in `reportgenerator.ps1` to fold per-match enriched fields into monthly aggregates.
- Gate replay parsing via a flag so CI/docs build remains fast; store enriched outputs under `data/enriched/matches/` and reference them when available.

## Notes

- Replay URLs use Valve CDN: `http://replay<cluster>.valve.net/570/<match_id>_<replay_salt>.dem.bz2`
- OpenDota provides `cluster` and `replay_salt` in match details.
- Be mindful of bandwidth and storage; the orchestrator processes in batches of up to 5 and cleans up replays by default.
