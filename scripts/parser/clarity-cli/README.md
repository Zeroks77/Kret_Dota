# Clarity CLI Parser

This module parses Dota 2 replays and emits enriched JSON with event lists and aggregated statistics.

Key outputs:
- enriched.wards_events, smokes_events, item_events, runes_events
- enriched.roshan_summary, objectives_basic, buybacks, fights_simple
- enriched.damage_summary, healing_summary, cc_summary, ability_casts
- enriched.aggregated_stats: ability usage, damage/cc aggregates, wards/runes/smokes/buybacks/objectives/fights overviews, power spikes, economy leads, objective sequences, roshan context/control, lane role approximation

Run:
```powershell
$env:JAVA_HOME="C:\\Program Files\\Java\\jdk-17"
$env:Path="$($env:JAVA_HOME)\\bin;$env:Path"
$env:MVN="$env:USERPROFILE\\Tools\\apache-maven-3.9.9\\bin\\mvn.cmd"
& $env:MVN -q -f ".\\scripts\\parser\\clarity-cli\\pom.xml" -DskipTests package
```

Then parse a replay (dem or dem.bz2):
```bash
/c/Program\ Files/Java/jdk-17/bin/java.exe -Xmx2g -jar /c/Users/Dominik/Desktop/Kret_Dota/scripts/parser/clarity-cli/target/clarity-cli-0.1.0-jar-with-dependencies.jar --in /c/Users/Dominik/Desktop/Kret_Dota/data/replays/<match>.dem.bz2 --out /c/Users/Dominik/Desktop/Kret_Dota/data/parsed/<match>.json
```

Notes:
- GameEvents + CombatLog are both used; bz2 is decompressed to a temp dem automatically.
- Some advanced heuristics (lane roles, roshan control heroes presence) are approximations without direct position tracking yet; will be refined in the next iteration.
