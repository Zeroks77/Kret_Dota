# Replay Parser (Clarity suggested)

This folder is reserved for our in-house replay parser. We plan to implement it using Clarity (Java with CLI) or node-clarity equivalents. The pipeline expects a command like:

- node scripts/parser/index.js --in <replay.dem|.dem.bz2> --out <out.json>

Contract:
- Input: a single .dem or .dem.bz2 file
- Output: JSON matching `schemas/enriched_match.schema.json`

Until implemented, you can use `scripts/parser/stub.js` which writes a minimal JSON with match_id only.

Clarity CLI (Java)
- Location: `scripts/parser/clarity-cli`
- Build:
	- mvn -q -f scripts/parser/clarity-cli/pom.xml -DskipTests package
	- JAR: `scripts/parser/clarity-cli/target/clarity-cli-0.1.0-jar-with-dependencies.jar`
- Run:
	- pwsh -File scripts/ingest_batch.ps1 -Source list -MatchListFile scripts/sample_match_ids.txt -MappingCsv scripts/replay_mapping.csv -ParserCmd "java -jar scripts/parser/clarity-cli/target/clarity-cli-0.1.0-jar-with-dependencies.jar --in {in} --out {out}" -BatchSize 5

## Enriched output (Auszug)

- enriched.objectives_basic[]: time, event, team, target, by, seq, chain_id, swing { gold, xp }
- enriched.wards_events[]: time, player, type, removed_at, removed_by, deward_source_time, deward_source_player, lifetime, expected_lifetime, effective_ratio
- enriched.fights_simple[]: start, end, duration, participants[], participants_count, swing { gold, xp }, ults_count, ults_by_caster, buybacks_count, buybacks_by_player
	- Zusätzlich: events[] (für spätere Spatial-Analyse), spatial_groups[] (verbundene Komponenten über Interaktionen), damage_proxy_by_actor (Fallback, wenn kein GOLD/XP)
- enriched.buybacks[]: time, player
- enriched.ability_casts[]: time, caster, ability, is_ult
- enriched.damage_summary: "attacker|target|inflictor" -> sum
- enriched.healing_summary: "attacker|target|inflictor" -> sum
- enriched.cc_summary: target -> { stun, root, silence, hex }
- enriched.aggregated_stats:
  - ability_usage_by_caster, ability_usage_by_ability, ult_usage_by_caster
  - damage_by_attacker, damage_by_pair (attacker|target), damage_by_attacker_ability (attacker|ability)
  - cc_by_attacker, cc_instances[] { target, source, modifier, category, start, end, duration }

Hinweis: Zeitstempel in Sekunden (gerundet). GOLD/XP-Swing wird nur berechnet, wenn die entsprechenden CombatLog-Events verfügbar sind.

Ult-Mapping: `scripts/parser/clarity-cli/src/main/resources/ult_abilities.json`. Optional erweiterbar über Env-Variable `KRET_ULTS_PATH` (Pfad zu JSON-Array), ohne Neu-Build.
