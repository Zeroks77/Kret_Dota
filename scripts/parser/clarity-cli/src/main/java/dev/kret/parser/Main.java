package dev.kret.parser;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import skadistats.clarity.Clarity;
import skadistats.clarity.model.CombatLogEntry;
import skadistats.clarity.model.Entity;
import skadistats.clarity.model.GameEvent;
import skadistats.clarity.processor.gameevents.OnCombatLogEntry;
import skadistats.clarity.processor.gameevents.OnGameEvent;
import skadistats.clarity.processor.entities.OnEntityCreated;
import skadistats.clarity.processor.entities.OnEntityUpdated;
import skadistats.clarity.source.MappedFileSource;
import skadistats.clarity.processor.runner.SimpleRunner;
import skadistats.clarity.wire.dota.common.proto.DOTAUserMessages.DOTA_COMBATLOG_TYPES;
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

public class Main {
    public static void main(String[] args) throws Exception {
        // args parsing
        String in = null;
        String out = null;
        for (int i = 0; i < args.length; i++) {
            if ("--in".equals(args[i]) && i + 1 < args.length) in = args[++i];
            else if ("--out".equals(args[i]) && i + 1 < args.length) out = args[++i];
        }
        if (in == null || out == null) {
            System.err.println("Usage: java -jar clarity-cli.jar --in <replay.dem[.bz2]> --out <out.json>");
            System.exit(2);
            return;
        }

        Path inPath = Path.of(in);
        Path outPath = Path.of(out);
        Files.createDirectories(outPath.getParent());

        // Resolve replay path; if bz2, decompress to a temp .dem and use a memory-mapped source for robust GameEvents
        Path replayPath = inPath;
        if (in.toLowerCase().endsWith(".bz2")) {
            Path tmpDem = Files.createTempFile("clarity-", ".dem");
            tmpDem.toFile().deleteOnExit();
            try (InputStream fin = Files.newInputStream(inPath);
                 BZip2CompressorInputStream bz = new BZip2CompressorInputStream(fin, true);
                 java.io.OutputStream fout = Files.newOutputStream(tmpDem)) {
                byte[] buf = new byte[1 << 16];
                int r;
                while ((r = bz.read(buf)) != -1) {
                    fout.write(buf, 0, r);
                }
            }
            replayPath = tmpDem;
        }

        ObjectMapper om = new ObjectMapper();
        ObjectNode root = om.createObjectNode();
        root.put("source", "clarity-cli");
        root.put("generated_at", java.time.Instant.now().toString());

        // derive match_id from filename prefix
        String base = inPath.getFileName().toString();
        String digits = base.replaceAll("[^0-9].*$", "");
        if (!digits.isEmpty()) {
            try { root.put("match_id", Long.parseLong(digits)); } catch (NumberFormatException ignored) {}
        }

        // enriched containers
        final ArrayNode wardsEvents = om.createArrayNode();
        final ArrayNode itemEvents = om.createArrayNode();
    final ArrayNode smokesEvents = om.createArrayNode();
    final ArrayNode itemUses = om.createArrayNode();
        final ArrayNode objectivesBasic = om.createArrayNode();
        final ArrayNode runesEvents = om.createArrayNode();
        final ObjectNode roshanSummary = om.createObjectNode();
        final ArrayNode buybacks = om.createArrayNode();
    final ArrayNode fightsSimple = om.createArrayNode();
    final ArrayNode abilityCasts = om.createArrayNode();
    final ObjectNode abilityUsageByCaster = om.createObjectNode(); // caster -> count
    final ObjectNode abilityUsageByOwner = om.createObjectNode(); // owner hero -> count
    final ObjectNode abilityUsageByAbility = om.createObjectNode(); // ability -> count
    final ObjectNode ultUsageByCaster = om.createObjectNode(); // caster -> count
    final ObjectNode damageByAttacker = om.createObjectNode(); // attacker -> total
    final ObjectNode damageByPair = om.createObjectNode(); // attacker|target -> total
    final ObjectNode damageByAttackerAbility = om.createObjectNode(); // attacker|ability -> total
        final ObjectNode damageSummary = om.createObjectNode();
    final ObjectNode healingSummary = om.createObjectNode();
    // hero->team map for team attribution
    final Map<String, String> heroTeamMap = new HashMap<>();

        // fight clustering state (simple time-gap based)
        final List<ObjectNode> fightBuffer = new ArrayList<>();
        final long[] lastFightTs = new long[]{Long.MIN_VALUE};
        final long FIGHT_GAP = 20; // seconds

        // Ward and sentry placements for deward chains
        final List<ObjectNode> wardPlacements = new ArrayList<>();
        final List<ObjectNode> sentryPlacements = new ArrayList<>();
    // Ward Entities (positions) for hotspots
    final List<ObjectNode> wardEntities = new ArrayList<>();
    // Hero position sampling (time->x,y per hero)
    final Map<String, List<double[]>> heroPosSamples = new HashMap<>(); // hero -> list of {time,x,y}
    final Map<String, Long> heroLastSample = new HashMap<>();
    final long POS_SAMPLE_STEP = 2; // seconds
    final double VISION_RADIUS = 1600.0; // spatial correlation radius
    final long[] currentTimeSec = new long[]{0L};

    // CC tracking
    final Map<String, Map<String, Long>> ccActiveStart = new HashMap<>();
    final Map<String, Map<String, String>> ccActiveSource = new HashMap<>();
    final ObjectNode ccSummary = om.createObjectNode(); // by target
    final ObjectNode ccByAttacker = om.createObjectNode(); // attacker -> {stun, root, ...}
    final ArrayNode ccInstances = om.createArrayNode();

        // GOLD/XP tracking for swing (best-effort if events exist)
        final List<ObjectNode> goldXp = new ArrayList<>();

        // run Clarity with processors
        // load ult mapping from resources (optional)
        final Set<String> ultNames = new HashSet<>();
        try (var inUlt = Main.class.getResourceAsStream("/ult_abilities.json")) {
            if (inUlt != null) {
                ArrayNode arr = (ArrayNode) om.readTree(inUlt);
                for (int i = 0; i < arr.size(); i++) ultNames.add(arr.get(i).asText());
            }
        } catch (Exception ignore) {}
        // Optional: external override via env KRET_ULTS_PATH (JSON array of strings)
        try {
            String ext = System.getenv("KRET_ULTS_PATH");
            if (ext != null && !ext.isEmpty()) {
                java.nio.file.Path p = java.nio.file.Path.of(ext);
                if (java.nio.file.Files.exists(p)) {
                    ArrayNode arr = (ArrayNode) om.readTree(java.nio.file.Files.readString(p));
                    for (int i = 0; i < arr.size(); i++) ultNames.add(arr.get(i).asText());
                }
            }
        } catch (Exception ignore) {}
        // no ability damage types mapping (removed by request)

    new SimpleRunner(new MappedFileSource(replayPath.toString())).runWith(new Object() {
            @OnEntityCreated
            public void onEntityCreated(Entity e) {
                try {
                    String dt = e.getDtClass() != null ? e.getDtClass().getDtName() : "";
                    if (dt != null && dt.startsWith("CDOTA_Unit_Hero_")) {
                        String unit = dt.toLowerCase().replace("cdota_unit_hero_", "npc_dota_hero_");
                        Object tn = null;
                        try { tn = e.getProperty("m_iTeamNum"); } catch (Exception ignore) {}
                        int teamNum = (tn instanceof Number) ? ((Number) tn).intValue() : -1;
                        String team = (teamNum == 2) ? "Radiant" : (teamNum == 3) ? "Dire" : "";
                        if (!unit.isEmpty() && !team.isEmpty()) heroTeamMap.put(unit, team);
                        // initialize position sampling structures
                        heroPosSamples.computeIfAbsent(unit, k -> new ArrayList<>());
                        heroLastSample.put(unit, Long.MIN_VALUE);
                    }
                    // Ward entities (observer/sentry) positions
                    if (dt != null && (dt.startsWith("CDOTA_NPC_ObserverWard") || dt.startsWith("CDOTA_NPC_ObserverWard_TrueSight"))) {
                        double x = 0, y = 0;
                        try {
                            Object vo = e.getProperty("m_vecOrigin");
                            if (vo instanceof float[]) {
                                float[] arr = (float[]) vo; if (arr.length >= 2) { x = arr[0]; y = arr[1]; }
                            } else if (vo instanceof double[]) {
                                double[] arr = (double[]) vo; if (arr.length >= 2) { x = arr[0]; y = arr[1]; }
                            }
                        } catch (Exception ignore) {}
                        if (x == 0 && y == 0) {
                            try {
                                Object cx = e.getProperty("m_cellX");
                                Object cy = e.getProperty("m_cellY");
                                if (cx instanceof Number && cy instanceof Number) {
                                    x = ((Number) cx).doubleValue();
                                    y = ((Number) cy).doubleValue();
                                }
                            } catch (Exception ignore) {}
                        }
                        Object tn = null; try { tn = e.getProperty("m_iTeamNum"); } catch (Exception ignore) {}
                        int teamNum = (tn instanceof Number) ? ((Number) tn).intValue() : -1;
                        String team = (teamNum == 2) ? "Radiant" : (teamNum == 3) ? "Dire" : "";
                        String type = dt.contains("TrueSight") ? "sentry" : "observer";
                        if (team != null && !team.isEmpty()) {
                            ObjectNode wn = om.createObjectNode();
                            wn.put("x", x); wn.put("y", y);
                            wn.put("team", team);
                            wn.put("type", type);
                            wardEntities.add(wn);
                        }
                    }
                } catch (Exception ignore) {}
            }
            @OnEntityUpdated
            public void onEntityUpdated(Entity e) {
                try {
                    String dt = e.getDtClass() != null ? e.getDtClass().getDtName() : "";
                    if (dt == null) return;
                    // Track hero positions
                    if (dt.startsWith("CDOTA_Unit_Hero_")) {
                        String unit = dt.toLowerCase().replace("cdota_unit_hero_", "npc_dota_hero_");
                        long last = heroLastSample.getOrDefault(unit, Long.MIN_VALUE);
                        if (last == Long.MIN_VALUE || currentTimeSec[0] - last >= POS_SAMPLE_STEP) {
                            double x = 0, y = 0;
                            try {
                                Object vo = e.getProperty("m_vecOrigin");
                                if (vo instanceof float[]) { float[] arr = (float[]) vo; if (arr.length >= 2) { x = arr[0]; y = arr[1]; } }
                                else if (vo instanceof double[]) { double[] arr = (double[]) vo; if (arr.length >= 2) { x = arr[0]; y = arr[1]; } }
                            } catch (Exception ignore) {}
                            if (x == 0 && y == 0) {
                                try {
                                    Object cx = e.getProperty("m_cellX"); Object cy = e.getProperty("m_cellY");
                                    if (cx instanceof Number && cy instanceof Number) { x = ((Number) cx).doubleValue(); y = ((Number) cy).doubleValue(); }
                                } catch (Exception ignore) {}
                            }
                            heroPosSamples.computeIfAbsent(unit, k -> new ArrayList<>()).add(new double[]{ currentTimeSec[0], x, y });
                            heroLastSample.put(unit, currentTimeSec[0]);
                        }
                    }
                    // Record item uses for controlled hero-like units (e.g., Tempest Double, Meepo, Lone Druid Bear if applicable)
                    // We approximate by listening in combat log for items; here we can supplement by checking inventory changes if needed.
                } catch (Exception ignore) {}
            }
            @OnGameEvent
            public void onGameEvent(GameEvent e) {
                String name = e.getName();

                if ("dota_item_purchase".equals(name)) {
                    ObjectNode n = om.createObjectNode();
                    n.put("time", parseTime(e.getProperty("game_time")));
                    n.put("player", toStr(e.getProperty("player")));
                    n.put("item", toStr(e.getProperty("item")));
                    n.put("action", "purchased");
                    itemEvents.add(n);
                }

                // General and neutral item pickups
                if ("dota_item_picked_up".equals(name) || "dota_neutral_item_picked_up".equals(name)) {
                    ObjectNode n = om.createObjectNode();
                    n.put("time", parseTime(e.getProperty("game_time")));
                    n.put("player", toStr(e.getProperty("player")));
                    // Try common property names for the item field
                    String itemName = toStr(e.getProperty("item"));
                    if (itemName == null) itemName = toStr(e.getProperty("itemname"));
                    if (itemName == null) itemName = toStr(e.getProperty("item_name"));
                    if (itemName == null) itemName = toStr(e.getProperty("item_def"));
                    n.put("item", itemName);
                    n.put("action", "picked_up");
                    if ("dota_neutral_item_picked_up".equals(name)) n.put("neutral", true);
                    itemEvents.add(n);
                }

                if ("dota_item_used".equals(name)) {
                    String item = toStr(e.getProperty("item"));
                    long ts = parseTime(e.getProperty("game_time"));
                    if ("item_smoke_of_deceit".equals(item)) {
                        ObjectNode n = om.createObjectNode();
                        n.put("time", ts);
                        String player = toStr(e.getProperty("player"));
                        n.put("player", player);
                        n.put("owner", normalizeOwner(player));
                        smokesEvents.add(n);
                    }
                    if ("item_ward_observer".equals(item) || "item_ward_sentry".equals(item)) {
                        ObjectNode n = om.createObjectNode();
                        n.put("time", ts);
                        String player = toStr(e.getProperty("player"));
                        n.put("player", player);
                        n.put("owner", normalizeOwner(player));
                        n.put("type", item);
                        wardsEvents.add(n);
                        if ("item_ward_observer".equals(item)) wardPlacements.add(n);
                        else sentryPlacements.add(n);
                    }
                }

                if ("dota_rune_activated".equals(name)) {
                    ObjectNode n = om.createObjectNode();
                    n.put("time", parseTime(e.getProperty("game_time")));
                    n.put("player", toStr(e.getProperty("player")));
                    n.put("rune", toStr(e.getProperty("rune")));
                    runesEvents.add(n);
                }
                if ("bottle_refill_used".equals(name) || "bottle_refill_obtained".equals(name)) {
                    ObjectNode n = om.createObjectNode();
                    n.put("time", parseTime(e.getProperty("game_time")));
                    n.put("player", toStr(e.getProperty("player")));
                    n.put("type", name);
                    runesEvents.add(n);
                }

                // Roshan
                if ("dota_roshan_kill".equals(name)) {
                    roshanSummary.put("kill_time", parseTime(e.getProperty("game_time")));
                    roshanSummary.put("killer", toStr(e.getProperty("killer")));
                }
                if ("aegis_picked_up".equals(name) || "dota_aegis_event".equals(name)) {
                    roshanSummary.put("aegis_holder", toStr(e.getProperty("player")));
                    roshanSummary.put("aegis_pickup_time", parseTime(e.getProperty("game_time")));
                }
                if ("aegis_denied".equals(name) || "aegis_snatched".equals(name)) {
                    roshanSummary.put("aegis_status", name);
                    roshanSummary.put("aegis_status_time", parseTime(e.getProperty("game_time")));
                }
                if ("aegis_expired".equals(name) || "aegis_lost".equals(name)) {
                    roshanSummary.put("aegis_lost_time", parseTime(e.getProperty("game_time")));
                }
                if ("shard_picked_up".equals(name)) {
                    roshanSummary.put("shard_holder", toStr(e.getProperty("player")));
                    roshanSummary.put("shard_pickup_time", parseTime(e.getProperty("game_time")));
                }
                if ("cheese_picked_up".equals(name)) {
                    roshanSummary.put("cheese_holder", toStr(e.getProperty("player")));
                    roshanSummary.put("cheese_pickup_time", parseTime(e.getProperty("game_time")));
                }

                // Objectives basic
                if ("dota_glyph_used".equals(name) || "dota_scan_used".equals(name)) {
                    ObjectNode n = om.createObjectNode();
                    n.put("time", parseTime(e.getProperty("game_time")));
                    n.put("event", name);
                    n.put("team", toStr(e.getProperty("team")));
                    objectivesBasic.add(n);
                }
            }

            @OnCombatLogEntry
            public void onCombat(CombatLogEntry cle) {
                try {
                    long t = Math.round(cle.getTimestamp());
                    currentTimeSec[0] = Math.max(currentTimeSec[0], t);
                    DOTA_COMBATLOG_TYPES type = cle.getType();
                    boolean isDamage = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_DAMAGE;
                    boolean isHeal = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_HEAL;
                    boolean isDeath = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_DEATH;
                    boolean isModifierAdd = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_MODIFIER_ADD;
                    boolean isModifierRemove = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_MODIFIER_REMOVE;
                    boolean isGold = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_GOLD;
                    boolean isXP = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_XP;
                    boolean isAbility = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_ABILITY || type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_ABILITY_TRIGGER;
                    boolean isItem = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_ITEM;
                    boolean isPurchase = type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_PURCHASE;

                    String attacker = safe(cle.getAttackerName());
                    String target = safe(cle.getTargetName());
                    String inflictor = safe(cle.getInflictorName());
                    int val = cle.getValue();

                    // Fallbacks when GameEvents are missing
                    if (isPurchase) {
                        // Item purchase info
                        ObjectNode n = om.createObjectNode();
                        n.put("time", t);
                        // Purchaser is often in target, but fall back to attacker
                        n.put("player", !target.isEmpty() ? target : attacker);
                        n.put("item", inflictor);
                        n.put("action", "purchased");
                        itemEvents.add(n);
                    }
                    if (isItem) {
                        // Smoke usage
                        if ("item_smoke_of_deceit".equals(inflictor)) {
                            ObjectNode n = om.createObjectNode();
                            n.put("time", t);
                            n.put("player", attacker);
                            n.put("owner", normalizeOwner(attacker));
                            smokesEvents.add(n);
                        }
                        // Ward placements
                        if ("item_ward_observer".equals(inflictor) || "item_ward_sentry".equals(inflictor)) {
                            ObjectNode n = om.createObjectNode();
                            n.put("time", t);
                            n.put("player", attacker);
                            n.put("owner", normalizeOwner(attacker));
                            n.put("type", inflictor);
                            wardsEvents.add(n);
                            if ("item_ward_observer".equals(inflictor)) wardPlacements.add(n); else sentryPlacements.add(n);
                        }
                        // Aegis pickup
                        if ("item_aegis".equals(inflictor)) {
                            roshanSummary.put("aegis_holder", attacker);
                            roshanSummary.put("aegis_pickup_time", t);
                        }
                        // Generic item use log (for controlled units too)
                        if (inflictor != null && !inflictor.isEmpty()) {
                            ObjectNode iu = om.createObjectNode();
                            iu.put("time", t);
                            iu.put("unit", attacker);
                            iu.put("owner", normalizeOwner(attacker));
                            iu.put("item", inflictor);
                            itemUses.add(iu);
                            String owner = normalizeOwner(attacker);
                            if (owner != null && !owner.isEmpty()) aggAdd(abilityUsageByOwner, owner, 0); // placeholder to ensure key exists
                        }
                    }

                    if (isDamage) {
                        aggAdd(damageSummary, key(attacker, target, inflictor), val);
                        // attacker totals
                        aggAdd(damageByAttacker, attacker, val);
                        aggAdd(damageByPair, key(attacker, target, ""), val);
                        aggAdd(damageByAttackerAbility, key(attacker, "", inflictor), val);
                    }
                    if (isHeal) aggAdd(healingSummary, key(attacker, target, inflictor), val);

                    if (isDeath && isBuilding(target)) {
                        ObjectNode n = om.createObjectNode();
                        n.put("time", t);
                        n.put("event", "building_kill");
                        n.put("target", target);
                        n.put("by", attacker);
                        n.put("team_target", teamFromName(target));
                        n.put("team_by", teamFromName(attacker));
                        objectivesBasic.add(n);
                    }
                    // Hero pickoff events for objective sequencing
                    if (isDeath && !isBuilding(target) && isHero(target)) {
                        ObjectNode n = om.createObjectNode();
                        n.put("time", t);
                        n.put("event", "hero_death");
                        n.put("target", target);
                        n.put("by", attacker);
                        n.put("team_target", teamFromName(target));
                        n.put("team_by", teamFromName(attacker));
                        objectivesBasic.add(n);
                    }
                    // Roshan kill fallback
                    if (isDeath && (target != null && target.toLowerCase().contains("roshan"))) {
                        roshanSummary.put("kill_time", t);
                        roshanSummary.put("killer", attacker);
                    }

                    // Heuristic ward death for deward chains
                    if (isDeath && isWard(target)) {
                        for (int i = wardPlacements.size() - 1; i >= 0; i--) {
                            ObjectNode w = wardPlacements.get(i);
                            if (w.has("removed_at")) continue;
                            long wt = w.path("time").asLong(-1);
                            if (wt >= 0 && wt <= t) {
                                w.put("removed_at", t);
                                w.put("removed_by", attacker);
                                // link to sentry within 60s prior
                                ObjectNode src = nearestSentry(sentryPlacements, wt, t);
                                if (src != null) {
                                    w.put("deward_source_time", src.path("time").asLong());
                                    w.put("deward_source_player", src.path("player").asText(""));
                                }
                                break;
                            }
                        }
                    }

                    if (type == DOTA_COMBATLOG_TYPES.DOTA_COMBATLOG_BUYBACK) {
                        ObjectNode n = om.createObjectNode();
                        n.put("time", t);
                        n.put("player", target);
                        buybacks.add(n);
                    }

                    if (isGold || isXP) {
                        ObjectNode g = om.createObjectNode();
                        g.put("time", t);
                        String team = teamFromName(target);
                        if (team == null || team.isEmpty()) team = teamFromName(attacker);
                        g.put("team", team == null ? "" : team);
                        g.put("gold", isGold ? val : 0);
                        g.put("xp", isXP ? val : 0);
                        goldXp.add(g);
                    }

                    // Fight clustering by time gap
                    if (isDamage || isHeal || isDeath) {
                        if (lastFightTs[0] != Long.MIN_VALUE && (t - lastFightTs[0]) > FIGHT_GAP) {
                            flushFight(fightBuffer, fightsSimple, om);
                        }
                        ObjectNode ev = om.createObjectNode();
                        ev.put("time", t);
                        ev.put("src", attacker);
                        ev.put("dst", target);
                        ev.put("inflictor", inflictor);
                        ev.put("kind", isDamage ? "damage" : (isHeal ? "heal" : "death"));
                        if (isDamage || isHeal) ev.put("value", val);
                        fightBuffer.add(ev);
                        lastFightTs[0] = t;
                    }

                    // CC durations via modifiers
                    if (isModifierAdd || isModifierRemove) {
                        String mod = safe(inflictor).toLowerCase();
                        String targetKey = target;
                        if (isRelevantCC(mod)) {
                            if (isModifierAdd) {
                                ccActiveStart.computeIfAbsent(targetKey, k -> new HashMap<>()).put(mod, t);
                                ccActiveSource.computeIfAbsent(targetKey, k -> new HashMap<>()).put(mod, attacker);
                            } else {
                                Map<String, Long> m = ccActiveStart.get(targetKey);
                                Map<String, String> srcMap = ccActiveSource.get(targetKey);
                                if (m != null && m.containsKey(mod)) {
                                    long start = m.remove(mod);
                                    String source = srcMap != null ? srcMap.remove(mod) : "";
                                    long dur = Math.max(0, t - start);
                                    String cat = ccCategory(mod);
                                    ObjectNode sum = (ObjectNode) ccSummary.get(targetKey);
                                    if (sum == null) { sum = om.createObjectNode(); ccSummary.set(targetKey, sum); }
                                    long prev = sum.has(cat) ? sum.get(cat).asLong() : 0L;
                                    sum.put(cat, prev + dur);

                                    // by attacker aggregation
                                    if (source != null && !source.isEmpty()) {
                                        ObjectNode a = (ObjectNode) ccByAttacker.get(source);
                                        if (a == null) { a = om.createObjectNode(); ccByAttacker.set(source, a); }
                                        long aprev = a.has(cat) ? a.get(cat).asLong() : 0L;
                                        a.put(cat, aprev + dur);
                                    }

                                    // record instance
                                    ObjectNode inst = om.createObjectNode();
                                    inst.put("target", targetKey);
                                    inst.put("source", source);
                                    inst.put("modifier", mod);
                                    inst.put("category", cat);
                                    inst.put("start", start);
                                    inst.put("end", t);
                                    inst.put("duration", dur);
                                    ccInstances.add(inst);
                                }
                            }
                        }
                    }
                    // Rune pickup fallback via rune modifiers applied
                    if (isModifierAdd) {
                        String modName = safe(inflictor).toLowerCase();
                        if (modName.contains("rune_")) {
                            ObjectNode n = om.createObjectNode();
                            n.put("time", t);
                            // The rune buff is applied to the picker (target)
                            n.put("player", target);
                            n.put("rune", modName);
                            runesEvents.add(n);
                        }
                    }
                    // Ability casts (for later ult detection)
                    if (isAbility) {
                        ObjectNode n = om.createObjectNode();
                        n.put("time", t);
                        n.put("caster", attacker);
                        n.put("ability", inflictor);
                        boolean isUlt = inflictor != null && ultNames.contains(inflictor);
                        n.put("is_ult", isUlt);
                        String owner = normalizeOwner(attacker);
                        if (owner != null && !owner.isEmpty()) n.put("owner_caster", owner);
                        abilityCasts.add(n);
                        // aggregates
                        if(attacker != null && !attacker.isEmpty()) aggAdd(abilityUsageByCaster, attacker, 1);
                        if(inflictor != null && !inflictor.isEmpty()) aggAdd(abilityUsageByAbility, inflictor, 1);
                        if(owner != null && !owner.isEmpty()) aggAdd(abilityUsageByOwner, owner, 1);
                        if(isUlt && attacker != null && !attacker.isEmpty()) aggAdd(ultUsageByCaster, attacker, 1);
                    }
                } catch (Exception ignore) {}
            }
        });

    // flush last fight
        flushFight(fightBuffer, fightsSimple, om);

        // Objective swing estimation: integrate gold/xp in 90s after event
        final long WINDOW = 90;
        for (int i = 0; i < objectivesBasic.size(); i++) {
            ObjectNode ev = (ObjectNode) objectivesBasic.get(i);
            long t = ev.path("time").asLong(-1);
            if (t < 0) continue;
            long end = t + WINDOW;
            long rGold=0, dGold=0, rXp=0, dXp=0;
            for (ObjectNode gx : goldXp) {
                long gt = gx.path("time").asLong();
                if (gt < t || gt > end) continue;
                String team = gx.path("team").asText("");
                long g = gx.path("gold").asLong(0);
                long x = gx.path("xp").asLong(0);
                if ("Radiant".equals(team)) { rGold += g; rXp += x; }
                else if ("Dire".equals(team)) { dGold += g; dXp += x; }
            }
            ObjectNode swing = om.createObjectNode();
            swing.put("gold", rGold - dGold);
            swing.put("xp", rXp - dXp);
            ev.set("swing", swing);
        }

        // Objective sequencing (chain_id when close in time)
        long lastT = Long.MIN_VALUE; int chain = 0; int seq = 0; long GAP = 15;
        List<ObjectNode> objs = new ArrayList<>();
        for (int i = 0; i < objectivesBasic.size(); i++) objs.add((ObjectNode) objectivesBasic.get(i));
        objs.sort(Comparator.comparingLong(o -> o.path("time").asLong(Long.MAX_VALUE)));
        for (ObjectNode ev : objs) {
            long t = ev.path("time").asLong(Long.MAX_VALUE);
            if (lastT == Long.MIN_VALUE || t - lastT > GAP) { chain++; }
            lastT = t; seq++;
            ev.put("seq", seq);
            ev.put("chain_id", chain);
        }

        // Ward quality: lifetime and flags
        for (ObjectNode w : wardPlacements) {
            long placed = w.path("time").asLong(-1);
            long removed = w.path("removed_at").asLong(-1);
            if (placed >= 0 && removed >= 0 && removed >= placed) {
                w.put("lifetime", removed - placed);
                w.put("dewarded", true);
                long expected = w.path("type").asText("").contains("observer") ? 420L : 90L; // approx.
                w.put("expected_lifetime", expected);
                double eff = expected > 0 ? Math.min(1.0, (removed - placed) / (double) expected) : 0.0;
                w.put("effective_ratio", eff);
            }
        }

        // Try to match ward placements to ward entity positions by team and type order
        // 1) Group ward entities by key = team|type (type: observer/sentry) preserving creation order
        Map<String, List<ObjectNode>> wardEntitiesByKey = new HashMap<>();
        for (ObjectNode we : wardEntities) {
            String team = we.path("team").asText("");
            String type = we.path("type").asText(""); // observer or sentry
            if (team.isEmpty() || type.isEmpty()) continue;
            String key = team + "|" + type;
            wardEntitiesByKey.computeIfAbsent(key, k -> new ArrayList<>()).add(we);
        }
        // 2) Sort ward placements chronologically and assign coordinates in-order per team/type
        List<ObjectNode> wardPlacementsSorted = new ArrayList<>(wardPlacements);
        wardPlacementsSorted.sort(Comparator.comparingLong(o -> o.path("time").asLong(Long.MAX_VALUE)));
        Map<String, Integer> wardEntityNextIdx = new HashMap<>();
        for (ObjectNode w : wardPlacementsSorted) {
            String player = w.path("player").asText("");
            String team = heroTeamMap.getOrDefault(player.toLowerCase(), "");
            if (team.isEmpty()) continue;
            String typeItem = w.path("type").asText(""); // item_ward_observer / item_ward_sentry
            String type = typeItem.contains("observer") ? "observer" : typeItem.contains("sentry") ? "sentry" : "";
            if (type.isEmpty()) continue;
            String key = team + "|" + type;
            List<ObjectNode> list = wardEntitiesByKey.getOrDefault(key, Collections.emptyList());
            int idx = wardEntityNextIdx.getOrDefault(key, 0);
            if (idx < list.size()) {
                ObjectNode ent = list.get(idx);
                wardEntityNextIdx.put(key, idx + 1);
                double x = ent.path("x").asDouble(Double.NaN);
                double y = ent.path("y").asDouble(Double.NaN);
                if (!Double.isNaN(x)) w.put("ward_x", x);
                if (!Double.isNaN(y)) w.put("ward_y", y);
            }
        }

        // Fight enrich: duration, participants_count, swing in and shortly after; ults & buybacks; spatial-ish groups
        for (int i = 0; i < fightsSimple.size(); i++) {
            ObjectNode f = (ObjectNode) fightsSimple.get(i);
            long s = f.path("start").asLong();
            long e = f.path("end").asLong();
            if (e < s) e = s;
            f.put("duration", e - s);
            int participants = f.path("participants").size();
            f.put("participants_count", participants);
            long end = e + 20;
            long rGold=0, dGold=0, rXp=0, dXp=0;
            boolean anyGoldXp = false;
            for (ObjectNode gx : goldXp) {
                long gt = gx.path("time").asLong();
                if (gt < s || gt > end) continue;
                String team = gx.path("team").asText("");
                long g = gx.path("gold").asLong(0);
                long x = gx.path("xp").asLong(0);
                if ("Radiant".equals(team)) { rGold += g; rXp += x; }
                else if ("Dire".equals(team)) { dGold += g; dXp += x; }
                anyGoldXp = true;
            }
            ObjectNode swing = om.createObjectNode();
            swing.put("gold", rGold - dGold);
            swing.put("xp", rXp - dXp);
            swing.put("source", anyGoldXp ? "combatlog_gold_xp" : "damage_proxy");
            f.set("swing", swing);

            // Spatial-ish grouping via interaction graph (connected components over src/dst within fight)
            Map<String, Set<String>> adj = new HashMap<>();
            ArrayNode events = (ArrayNode) f.path("events");
            if (events != null) {
                for (int j = 0; j < events.size(); j++) {
                    ObjectNode ev = (ObjectNode) events.get(j);
                    String a = ev.path("src").asText("");
                    String b = ev.path("dst").asText("");
                    if (a.isEmpty() || b.isEmpty()) continue;
                    adj.computeIfAbsent(a, k -> new HashSet<>()).add(b);
                    adj.computeIfAbsent(b, k -> new HashSet<>()).add(a);
                }
            }
            Set<String> seen = new HashSet<>();
            ArrayNode groups = om.createArrayNode();
            for (int j = 0; j < f.path("participants").size(); j++) {
                String startNode = f.path("participants").get(j).asText("");
                if (startNode.isEmpty() || seen.contains(startNode)) continue;
                // BFS
                Deque<String> dq = new ArrayDeque<>();
                dq.add(startNode); seen.add(startNode);
                List<String> comp = new ArrayList<>(); comp.add(startNode);
                while(!dq.isEmpty()){
                    String u = dq.removeFirst();
                    for (String v : adj.getOrDefault(u, Collections.emptySet())){
                        if (!seen.contains(v)) { seen.add(v); dq.addLast(v); comp.add(v); }
                    }
                }
                ObjectNode g = om.createObjectNode();
                ArrayNode gp = om.createArrayNode();
                for (String v : comp) gp.add(v);
                g.set("participants", gp);
                g.put("participants_count", comp.size());
                groups.add(g);
            }
            if (groups.size() > 0) f.set("spatial_groups", groups);

            // Damage proxy per actor inside the fight window (if no GOLD/XP events)
            if (!anyGoldXp && events != null) {
                ObjectNode dmg = om.createObjectNode();
                for (int j = 0; j < events.size(); j++) {
                    ObjectNode ev = (ObjectNode) events.get(j);
                    if (!"damage".equals(ev.path("kind").asText())) continue;
                    String a = ev.path("src").asText("");
                    int v = ev.path("value").asInt(0);
                    if (!a.isEmpty() && v > 0) aggAdd(dmg, a, v);
                }
                f.set("damage_proxy_by_actor", dmg);
            }

            // Ults during fight window (allow 2s slack after end)
            long fe = e + 2;
            int ultCount = 0;
            ObjectNode ultsByCaster = om.createObjectNode();
            for (int j = 0; j < abilityCasts.size(); j++) {
                ObjectNode ac = (ObjectNode) abilityCasts.get(j);
                if (!ac.path("is_ult").asBoolean(false)) continue;
                long t = ac.path("time").asLong(Long.MIN_VALUE);
                if (t < s || t > fe) continue;
                ultCount++;
                String caster = ac.path("caster").asText("");
                if (!caster.isEmpty()) aggAdd(ultsByCaster, caster, 1);
            }
            f.put("ults_count", ultCount);
            f.set("ults_by_caster", ultsByCaster);

            // Buybacks during/near fight window (allow 2s slack after end)
            int bbCount = 0;
            ObjectNode bbByPlayer = om.createObjectNode();
            for (int j = 0; j < buybacks.size(); j++) {
                ObjectNode bb = (ObjectNode) buybacks.get(j);
                long t = bb.path("time").asLong(Long.MIN_VALUE);
                if (t < s || t > fe) continue;
                bbCount++;
                String p = bb.path("player").asText("");
                if (!p.isEmpty()) aggAdd(bbByPlayer, p, 1);
            }
            f.put("buybacks_count", bbCount);
            f.set("buybacks_by_player", bbByPlayer);

            // Per-actor impact within fight
            Map<String, Integer> dmgByActor = new HashMap<>();
            Map<String, Integer> healByActor = new HashMap<>();
            Map<String, Integer> killsByActor = new HashMap<>();
            Map<String, Integer> assistsByActor = new HashMap<>();
            int totalKills = 0;
            int totalDamage = 0;
            int totalHealing = 0;
            final int ASSIST_WINDOW = 10;
            // Precollect death events
            List<ObjectNode> deathEvents = new ArrayList<>();
            if (events != null) {
                for (int j = 0; j < events.size(); j++) {
                    ObjectNode ev = (ObjectNode) events.get(j);
                    String kind = ev.path("kind").asText("");
                    String a = ev.path("src").asText("");
                    String b = ev.path("dst").asText("");
                    int v = ev.path("value").asInt(0);
                    long tt = ev.path("time").asLong(Long.MIN_VALUE);
                    if ("damage".equals(kind)) {
                        dmgByActor.put(a, dmgByActor.getOrDefault(a, 0) + v);
                        totalDamage += v;
                    } else if ("heal".equals(kind)) {
                        healByActor.put(a, healByActor.getOrDefault(a, 0) + v);
                        totalHealing += v;
                    } else if ("death".equals(kind)) {
                        killsByActor.put(a, killsByActor.getOrDefault(a, 0) + 1);
                        totalKills++;
                        deathEvents.add(ev);
                    }
                }
                // Assists: any actor who dealt damage to victim within window prior to death time
                for (ObjectNode d : deathEvents) {
                    String victim = d.path("dst").asText("");
                    long dt = d.path("time").asLong(Long.MIN_VALUE);
                    if (victim.isEmpty() || dt == Long.MIN_VALUE) continue;
                    for (int j = 0; j < events.size(); j++) {
                        ObjectNode ev = (ObjectNode) events.get(j);
                        if (!"damage".equals(ev.path("kind").asText(""))) continue;
                        String a = ev.path("src").asText("");
                        String b = ev.path("dst").asText("");
                        long tt = ev.path("time").asLong(Long.MIN_VALUE);
                        if (a.isEmpty() || b.isEmpty() || tt == Long.MIN_VALUE) continue;
                        if (!victim.equals(b)) continue;
                        if (tt >= dt - ASSIST_WINDOW && tt <= dt) {
                            assistsByActor.put(a, assistsByActor.getOrDefault(a, 0) + 1);
                        }
                    }
                }
            }
            ObjectNode byActor = om.createObjectNode();
            // Build per-actor stats for all participants
            for (int j = 0; j < f.path("participants").size(); j++) {
                String actor = f.path("participants").get(j).asText("");
                if (actor.isEmpty()) continue;
                ObjectNode a = om.createObjectNode();
                int dmg = dmgByActor.getOrDefault(actor, 0);
                int heal = healByActor.getOrDefault(actor, 0);
                int k = killsByActor.getOrDefault(actor, 0);
                int as = assistsByActor.getOrDefault(actor, 0);
                a.put("damage", dmg);
                a.put("healing", heal);
                a.put("kills", k);
                a.put("assists", as);
                a.put("damage_share", totalDamage > 0 ? (dmg / (double) totalDamage) : 0.0);
                a.put("healing_share", totalHealing > 0 ? (heal / (double) totalHealing) : 0.0);
                a.put("kparticipation", totalKills > 0 ? ((k + as) / (double) totalKills) : 0.0);
                int ults = ((ObjectNode) f.path("ults_by_caster")).path(actor).asInt(0);
                int bbc = ((ObjectNode) f.path("buybacks_by_player")).path(actor).asInt(0);
                double impact = a.path("damage_share").asDouble(0.0) * 1.0 + k * 0.5 + as * 0.25 + ults * 0.3 - bbc * 0.2;
                a.put("impact_score", impact);
                byActor.set(actor, a);
            }
            f.set("by_actor", byActor);
        }

    // Build additional aggregated stats
    // Precompute death times by target for CC efficiency
        Map<String, List<Long>> deathTimesByTarget = new HashMap<>();
        for (int i = 0; i < fightsSimple.size(); i++) {
            ObjectNode f = (ObjectNode) fightsSimple.get(i);
            ArrayNode events = (ArrayNode) f.path("events");
            for (int j = 0; j < events.size(); j++) {
                ObjectNode ev = (ObjectNode) events.get(j);
                if (!"death".equals(ev.path("kind").asText(""))) continue;
                String victim = ev.path("dst").asText("");
                long tt = ev.path("time").asLong(Long.MIN_VALUE);
                if (victim.isEmpty() || tt == Long.MIN_VALUE) continue;
                deathTimesByTarget.computeIfAbsent(victim, k -> new ArrayList<>()).add(tt);
            }
        }
        // 1) Wards aggregates per player (placements, dewarded, avg lifetime) and dewards made
        ObjectNode wardsByPlayer = om.createObjectNode();
        Map<String, Long> obsLifeSum = new HashMap<>();
        Map<String, Integer> obsLifeCnt = new HashMap<>();
        Map<String, Long> senLifeSum = new HashMap<>();
        Map<String, Integer> senLifeCnt = new HashMap<>();
        ObjectNode dewardsByPlayer = om.createObjectNode();
        for (ObjectNode w : wardPlacements) {
            String p = w.path("player").asText("");
            String type = w.path("type").asText("");
            boolean dewd = w.path("dewarded").asBoolean(false);
            long life = w.path("lifetime").asLong(-1);
            ObjectNode sub = (ObjectNode) wardsByPlayer.get(p);
            if (sub == null) { sub = om.createObjectNode(); wardsByPlayer.set(p, sub); }
            if ("item_ward_observer".equals(type)) {
                aggAdd(sub, "observer_placed", 1);
                if (dewd) aggAdd(sub, "observer_dewarded", 1);
                if (life >= 0) { obsLifeSum.put(p, obsLifeSum.getOrDefault(p, 0L) + life); obsLifeCnt.put(p, obsLifeCnt.getOrDefault(p, 0) + 1); }
            } else if ("item_ward_sentry".equals(type)) {
                aggAdd(sub, "sentry_placed", 1);
                if (dewd) aggAdd(sub, "sentry_dewarded", 1);
                if (life >= 0) { senLifeSum.put(p, senLifeSum.getOrDefault(p, 0L) + life); senLifeCnt.put(p, senLifeCnt.getOrDefault(p, 0) + 1); }
            }
            String removedBy = w.path("removed_by").asText("");
            if (!removedBy.isEmpty()) {
                aggAdd(dewardsByPlayer, removedBy, 1);
                ObjectNode subRB = (ObjectNode) wardsByPlayer.get(removedBy);
                if (subRB == null) { subRB = om.createObjectNode(); wardsByPlayer.set(removedBy, subRB); }
                aggAdd(subRB, "dewards_made", 1);
            }
        }
        // fill averages
        for (Iterator<String> it = wardsByPlayer.fieldNames(); it.hasNext();) {
            String p = it.next();
            ObjectNode sub = (ObjectNode) wardsByPlayer.get(p);
            long oSum = obsLifeSum.getOrDefault(p, 0L);
            int oCnt = obsLifeCnt.getOrDefault(p, 0);
            long sSum = senLifeSum.getOrDefault(p, 0L);
            int sCnt = senLifeCnt.getOrDefault(p, 0);
            if (oCnt > 0) sub.put("avg_observer_lifetime", oSum / (double) oCnt);
            if (sCnt > 0) sub.put("avg_sentry_lifetime", sSum / (double) sCnt);
        }

        // 2) Rune pickups by player (by type and total)
        ObjectNode runePickupsByPlayer = om.createObjectNode();
        for (int i = 0; i < runesEvents.size(); i++) {
            ObjectNode ev = (ObjectNode) runesEvents.get(i);
            String p = ev.path("player").asText("");
            String r = ev.path("rune").asText("");
            ObjectNode sub = (ObjectNode) runePickupsByPlayer.get(p);
            if (sub == null) { sub = om.createObjectNode(); runePickupsByPlayer.set(p, sub); }
            if (!r.isEmpty()) aggAdd(sub, r, 1);
            aggAdd(sub, "_total", 1);
        }

        // 3) Smokes by player
        ObjectNode smokesByPlayer = om.createObjectNode();
        for (int i = 0; i < smokesEvents.size(); i++) {
            ObjectNode ev = (ObjectNode) smokesEvents.get(i);
            String p = ev.path("player").asText("");
            if (!p.isEmpty()) aggAdd(smokesByPlayer, p, 1);
        }

        // 3b) Item pickups by player (counts per item + totals)
        ObjectNode itemPickupsByPlayer = om.createObjectNode();
        for (int i = 0; i < itemEvents.size(); i++) {
            ObjectNode itEv = (ObjectNode) itemEvents.get(i);
            String action = itEv.path("action").asText("");
            if (!"picked_up".equals(action)) continue;
            String p = itEv.path("player").asText("");
            String item = itEv.path("item").asText("");
            boolean neutral = itEv.path("neutral").asBoolean(false);
            if (p.isEmpty() || item.isEmpty()) continue;
            ObjectNode sub = (ObjectNode) itemPickupsByPlayer.get(p);
            if (sub == null) { sub = om.createObjectNode(); itemPickupsByPlayer.set(p, sub); }
            aggAdd(sub, item, 1);
            aggAdd(sub, "_total", 1);
            if (neutral) aggAdd(sub, "_neutral_total", 1);
        }

        // 4) Buybacks by player + first/last times
        ObjectNode buybacksByPlayer = om.createObjectNode();
        ObjectNode buybacksFirstTime = om.createObjectNode();
        ObjectNode buybacksLastTime = om.createObjectNode();
        for (int i = 0; i < buybacks.size(); i++) {
            ObjectNode bb = (ObjectNode) buybacks.get(i);
            String p = bb.path("player").asText("");
            long t = bb.path("time").asLong(-1);
            if (!p.isEmpty()) {
                aggAdd(buybacksByPlayer, p, 1);
                long first = buybacksFirstTime.path(p).asLong(Long.MAX_VALUE);
                long last = buybacksLastTime.path(p).asLong(Long.MIN_VALUE);
                if (t >= 0) {
                    if (t < first) buybacksFirstTime.put(p, t);
                    if (t > last) buybacksLastTime.put(p, t);
                }
            }
        }

        // 5) Objectives by team (counts)
        ObjectNode objectivesByTeam = om.createObjectNode();
        ObjectNode radiantObj = om.createObjectNode();
        ObjectNode direObj = om.createObjectNode();
        objectivesByTeam.set("Radiant", radiantObj);
        objectivesByTeam.set("Dire", direObj);
        for (int i = 0; i < objectivesBasic.size(); i++) {
            ObjectNode ev = (ObjectNode) objectivesBasic.get(i);
            String e = ev.path("event").asText("");
            String team = ev.path("team").asText("");
            if ("building_kill".equals(e)) {
                String tgt = ev.path("target").asText("").toLowerCase();
                String bucket = tgt.contains("barracks") || tgt.contains("rax") ? "barracks" : tgt.contains("outpost") ? "outposts" : tgt.contains("tower") ? "towers" : tgt.contains("fort") ? "ancients" : "buildings_other";
                String teamTarget = ev.path("team_target").asText("");
                // Count by team that LOST the building (team_target)
                ObjectNode objNode = "Radiant".equals(teamTarget) ? radiantObj : direObj;
                aggAdd(objNode, bucket, 1);
            } else if ("dota_glyph_used".equals(e)) {
                ObjectNode objNode = "Radiant".equals(team) ? radiantObj : direObj;
                aggAdd(objNode, "glyphs_used", 1);
            } else if ("dota_scan_used".equals(e)) {
                ObjectNode objNode = "Radiant".equals(team) ? radiantObj : direObj;
                aggAdd(objNode, "scans_used", 1);
            }
        }

        // 6) Fights overview
        ObjectNode fightsOverview = om.createObjectNode();
        int fCount = fightsSimple.size();
        long durSum = 0;
        int totalUlts = 0;
        int totalBuybacks = 0;
        for (int i = 0; i < fightsSimple.size(); i++) {
            ObjectNode f = (ObjectNode) fightsSimple.get(i);
            durSum += f.path("duration").asLong(0);
            totalUlts += f.path("ults_count").asInt(0);
            totalBuybacks += f.path("buybacks_count").asInt(0);
        }
        fightsOverview.put("count", fCount);
        if (fCount > 0) fightsOverview.put("avg_duration", durSum / (double) fCount);
        fightsOverview.put("total_ults", totalUlts);
        fightsOverview.put("total_buybacks", totalBuybacks);

        // 7) Damage received by target (aggregate across all sources)
        ObjectNode damageByTarget = om.createObjectNode();
        for (Iterator<String> it = damageSummary.fieldNames(); it.hasNext();) {
            String k = it.next();
            int v = damageSummary.path(k).asInt(0);
            String[] parts = k.split("\\|", -1);
            String target = parts.length > 1 ? parts[1] : "";
            if (!target.isEmpty()) aggAdd(damageByTarget, target, v);
        }

        // removed damage_by_type_by_player (ability damage types mapping was removed)

        // 8) First purchase times by player and item
        ObjectNode firstPurchaseByPlayerByItem = om.createObjectNode();
        for (int i = 0; i < itemEvents.size(); i++) {
            ObjectNode itEv = (ObjectNode) itemEvents.get(i);
            String action = itEv.path("action").asText("");
            if (!"purchased".equals(action)) continue; // ignore pickups for first purchase timing
            String p = itEv.path("player").asText("");
            String item = itEv.path("item").asText("");
            long t = itEv.path("time").asLong(-1);
            if (p.isEmpty() || item.isEmpty() || t < 0) continue;
            ObjectNode sub = (ObjectNode) firstPurchaseByPlayerByItem.get(p);
            if (sub == null) { sub = om.createObjectNode(); firstPurchaseByPlayerByItem.set(p, sub); }
            long prev = sub.path(item).asLong(Long.MAX_VALUE);
            if (t < prev) sub.put(item, t);
        }

        // 9) Power spikes by player (first ult cast, BKB/Shard/Aghs timing)
        ObjectNode powerSpikesByPlayer = om.createObjectNode();
        for (int i = 0; i < abilityCasts.size(); i++) {
            ObjectNode ac = (ObjectNode) abilityCasts.get(i);
            if (!ac.path("is_ult").asBoolean(false)) continue;
            String p = ac.path("caster").asText("");
            long t = ac.path("time").asLong(-1);
            if (p.isEmpty() || t < 0) continue;
            ObjectNode sub = (ObjectNode) powerSpikesByPlayer.get(p);
            if (sub == null) { sub = om.createObjectNode(); powerSpikesByPlayer.set(p, sub); }
            long prev = sub.path("first_ult_cast_time").asLong(Long.MAX_VALUE);
            if (t < prev) sub.put("first_ult_cast_time", t);
        }
        // Items for spikes
        for (Iterator<String> it = firstPurchaseByPlayerByItem.fieldNames(); it.hasNext();) {
            String p = it.next();
            ObjectNode items = (ObjectNode) firstPurchaseByPlayerByItem.get(p);
            ObjectNode sub = (ObjectNode) powerSpikesByPlayer.get(p);
            if (sub == null) { sub = om.createObjectNode(); powerSpikesByPlayer.set(p, sub); }
            long bkb = items.path("item_black_king_bar").asLong(-1);
            long aghs = items.path("item_ultimate_scepter").asLong(-1);
            long shard = items.path("item_aghanims_shard").asLong(-1);
            if (bkb >= 0) sub.put("bkb_purchase_time", bkb);
            if (aghs >= 0) sub.put("aghs_purchase_time", aghs);
            if (shard >= 0) sub.put("shard_purchase_time", shard);
        }

        // 10) CC efficiency (cc near death)
        ObjectNode ccEfficiency = om.createObjectNode();
        int ccTotal = 0;
        int ccNearDeath = 0;
        final int NEAR_DEATH_WINDOW = 2;
        for (int i = 0; i < ccInstances.size(); i++) {
            ObjectNode inst = (ObjectNode) ccInstances.get(i);
            String tgt = inst.path("target").asText("");
            long end = inst.path("end").asLong(-1);
            if (tgt.isEmpty() || end < 0) continue;
            ccTotal++;
            for (long dt : deathTimesByTarget.getOrDefault(tgt, Collections.emptyList())) {
                if (end <= dt && end >= dt - NEAR_DEATH_WINDOW) { ccNearDeath++; break; }
            }
        }
        ccEfficiency.put("cc_total", ccTotal);
        ccEfficiency.put("cc_near_death", ccNearDeath);

        // 11) Economy lead time series (per minute from gold/xp events)
        ArrayNode economySeries = om.createArrayNode();
        long maxT = 0;
        for (ObjectNode gx : goldXp) maxT = Math.max(maxT, gx.path("time").asLong(0));
        long rGold = 0, dGold = 0, rXp = 0, dXp = 0;
        // bucket events by minute
        Map<Long, long[]> buckets = new TreeMap<>();
        for (ObjectNode gx : goldXp) {
            long t = gx.path("time").asLong(0);
            long m = (t / 60) * 60;
            long[] arr = buckets.computeIfAbsent(m, k -> new long[]{0,0});
            String team = gx.path("team").asText("");
            long g = gx.path("gold").asLong(0);
            long x = gx.path("xp").asLong(0);
            if ("Radiant".equals(team)) { arr[0] += g; arr[1] += x; }
            else if ("Dire".equals(team)) { arr[0] -= g; arr[1] -= x; }
        }
        long cumG = 0, cumX = 0;
        for (Map.Entry<Long, long[]> en : buckets.entrySet()) {
            cumG += en.getValue()[0];
            cumX += en.getValue()[1];
            ObjectNode pt = om.createObjectNode();
            pt.put("time", en.getKey());
            pt.put("lead_gold", cumG);
            pt.put("lead_xp", cumX);
            economySeries.add(pt);
        }

        // 12) Objective sequences: pickoff -> objective within 45s
        ObjectNode objectiveSequences = om.createObjectNode();
        int pickoffToTower = 0, pickoffToOutpost = 0, pickoffToBarracks = 0, pickoffToAncient = 0;
        List<ObjectNode> objsSeq = new ArrayList<>();
        for (int i = 0; i < objectivesBasic.size(); i++) objsSeq.add((ObjectNode) objectivesBasic.get(i));
        objsSeq.sort(Comparator.comparingLong(o -> o.path("time").asLong(Long.MAX_VALUE)));
        final int SEQ_WINDOW = 45;
        ArrayNode objectiveChainDetails = om.createArrayNode();
        for (int i = 0; i < objsSeq.size(); i++) {
            ObjectNode ev = objsSeq.get(i);
            String e = ev.path("event").asText("");
            if (!"building_kill".equals(e)) continue;
            long t = ev.path("time").asLong(Long.MAX_VALUE);
            long from = t - SEQ_WINDOW;
            String bucket = ev.path("target").asText("").toLowerCase();
            String kind = bucket.contains("barracks") || bucket.contains("rax") ? "barracks" : bucket.contains("outpost") ? "outpost" : bucket.contains("tower") ? "tower" : bucket.contains("fort") ? "ancient" : "other";
            boolean precededByPickoff = false;
            long pickoffTime = Long.MIN_VALUE;
            for (int j = i - 1; j >= 0; j--) {
                ObjectNode prev = objsSeq.get(j);
                if (!"hero_death".equals(prev.path("event").asText(""))) continue;
                long pt = prev.path("time").asLong(Long.MIN_VALUE);
                if (pt < 0 || pt < from) break;
                precededByPickoff = true; pickoffTime = pt; break;
            }
            if (precededByPickoff) {
                switch (kind) {
                    case "tower": pickoffToTower++; break;
                    case "outpost": pickoffToOutpost++; break;
                    case "barracks": pickoffToBarracks++; break;
                    case "ancient": pickoffToAncient++; break;
                }
                // detail entry
                ObjectNode det = om.createObjectNode();
                det.put("pickoff_time", pickoffTime);
                det.put("objective_time", t);
                det.put("delta", t - pickoffTime);
                det.put("objective_kind", kind);
                det.put("team_target", ev.path("team_target").asText(""));
                ObjectNode sw = (ObjectNode) ev.path("swing");
                if (sw != null) {
                    det.put("swing_gold", sw.path("gold").asLong(0));
                    det.put("swing_xp", sw.path("xp").asLong(0));
                }
                // attach participants from overlapping fight if any
                ArrayNode parts = om.createArrayNode();
                ObjectNode nearestFight = null; long bestDt = Long.MAX_VALUE;
                for (int fi = 0; fi < fightsSimple.size(); fi++) {
                    ObjectNode f = (ObjectNode) fightsSimple.get(fi);
                    long fs = f.path("start").asLong(Long.MIN_VALUE);
                    long fe = f.path("end").asLong(Long.MIN_VALUE);
                    if (fs == Long.MIN_VALUE || fe == Long.MIN_VALUE) continue;
                    long dt = Math.max(0, Math.max(fs - t, t - fe));
                    if (t >= fs - 5 && t <= fe + 10) { nearestFight = f; break; }
                    if (dt < bestDt) { bestDt = dt; nearestFight = f; }
                }
                if (nearestFight != null) {
                    ArrayNode p = (ArrayNode) nearestFight.path("participants");
                    for (int pj = 0; pj < p.size(); pj++) parts.add(p.get(pj).asText(""));
                }
                det.set("participants", parts);
                objectiveChainDetails.add(det);
            }
        }
        objectiveSequences.put("pickoff_to_tower", pickoffToTower);
        objectiveSequences.put("pickoff_to_outpost", pickoffToOutpost);
        objectiveSequences.put("pickoff_to_barracks", pickoffToBarracks);
        objectiveSequences.put("pickoff_to_ancient", pickoffToAncient);

        // 13) Lead switch events
        int leadSwitchesGold = 0, leadSwitchesXp = 0;
        Integer prevSignG = null, prevSignX = null;
        for (int i = 0; i < economySeries.size(); i++) {
            ObjectNode pt = (ObjectNode) economySeries.get(i);
            long g = pt.path("lead_gold").asLong(0);
            long x = pt.path("lead_xp").asLong(0);
            int sg = Long.compare(g, 0);
            int sx = Long.compare(x, 0);
            if (prevSignG != null && sg != 0 && prevSignG != 0 && sg != prevSignG) leadSwitchesGold++;
            if (prevSignX != null && sx != 0 && prevSignX != 0 && sx != prevSignX) leadSwitchesXp++;
            if (sg != 0) prevSignG = sg;
            if (sx != 0) prevSignX = sx;
        }
        ObjectNode leadSwitchEvents = om.createObjectNode();
        leadSwitchEvents.put("gold", leadSwitchesGold);
        leadSwitchEvents.put("xp", leadSwitchesXp);

        // 14) Roshan context window (±60s): wards/smokes/runes activity counts
        ObjectNode roshanContext = om.createObjectNode();
        long rk = roshanSummary.path("kill_time").asLong(-1);
        if (rk >= 0) {
            long rs = rk - 60, re = rk + 60;
            int wCount = 0, sCount = 0, rCount = 0;
            for (int i = 0; i < wardsEvents.size(); i++) {
                long t = ((ObjectNode) wardsEvents.get(i)).path("time").asLong(Long.MIN_VALUE);
                if (t >= rs && t <= re) wCount++;
            }
            for (int i = 0; i < smokesEvents.size(); i++) {
                long t = ((ObjectNode) smokesEvents.get(i)).path("time").asLong(Long.MIN_VALUE);
                if (t >= rs && t <= re) sCount++;
            }
            for (int i = 0; i < runesEvents.size(); i++) {
                long t = ((ObjectNode) runesEvents.get(i)).path("time").asLong(Long.MIN_VALUE);
                if (t >= rs && t <= re) rCount++;
            }
            roshanContext.put("wards", wCount);
            roshanContext.put("smokes", sCount);
            roshanContext.put("runes", rCount);
            roshanContext.put("window", 60);
        }

        // Ward Hotspots clustering (DBSCAN-light): eps=1200 units, minPts=3
        final double EPS = 1200.0; final int MINPTS = 3;
        List<List<ObjectNode>> clusters = new ArrayList<>();
        boolean[] used = new boolean[wardEntities.size()];
        for (int i = 0; i < wardEntities.size(); i++) {
            if (used[i]) continue;
            ObjectNode a = wardEntities.get(i);
            double ax = a.path("x").asDouble(0), ay = a.path("y").asDouble(0);
            List<Integer> neigh = new ArrayList<>();
            for (int j = 0; j < wardEntities.size(); j++) {
                if (i == j) continue;
                ObjectNode b = wardEntities.get(j);
                double bx = b.path("x").asDouble(0), by = b.path("y").asDouble(0);
                double dx = ax - bx, dy = ay - by; double d = Math.hypot(dx, dy);
                if (d <= EPS) neigh.add(j);
            }
            if (neigh.size() + 1 < MINPTS) continue;
            // expand cluster
            List<ObjectNode> cl = new ArrayList<>();
            Deque<Integer> dq = new ArrayDeque<>();
            dq.add(i); used[i] = true;
            while(!dq.isEmpty()){
                int u = dq.removeFirst();
                ObjectNode uu = wardEntities.get(u);
                cl.add(uu);
                double ux = uu.path("x").asDouble(0), uy = uu.path("y").asDouble(0);
                List<Integer> neighU = new ArrayList<>();
                for (int v = 0; v < wardEntities.size(); v++) {
                    if (u == v) continue;
                    ObjectNode bb = wardEntities.get(v);
                    double vx = bb.path("x").asDouble(0), vy = bb.path("y").asDouble(0);
                    double dx2 = ux - vx, dy2 = uy - vy; double dd = Math.hypot(dx2, dy2);
                    if (dd <= EPS) neighU.add(v);
                }
                if (neighU.size() + 1 >= MINPTS) {
                    for (int v : neighU) { if (!used[v]) { used[v] = true; dq.add(v); } }
                }
            }
            clusters.add(cl);
        }
        ArrayNode wardHotspots = om.createArrayNode();
        for (List<ObjectNode> cl : clusters) {
            double sx=0, sy=0; int n=cl.size();
            Map<String,Integer> byType = new HashMap<>();
            Map<String,Integer> byTeam = new HashMap<>();
            for (ObjectNode w : cl) {
                sx += w.path("x").asDouble(0); sy += w.path("y").asDouble(0);
                byType.merge(w.path("type").asText(""), 1, Integer::sum);
                byTeam.merge(w.path("team").asText(""), 1, Integer::sum);
            }
            ObjectNode h = om.createObjectNode();
            h.put("x", n>0? sx/n:0); h.put("y", n>0? sy/n:0);
            h.put("count", n);
            ObjectNode t = om.createObjectNode();
            for (Map.Entry<String, Integer> e : byType.entrySet()) t.put(e.getKey(), e.getValue());
            h.set("by_type", t);
            ObjectNode tm = om.createObjectNode();
            for (Map.Entry<String, Integer> e : byTeam.entrySet()) tm.put(e.getKey(), e.getValue());
            h.set("by_team", tm);
            h.put("eps", EPS); h.put("minpts", MINPTS);
            wardHotspots.add(h);
        }

        // 15) Vision impact (first cut, temporal): kills and favorable fights within +60s after observer placement
        final int VISION_IMPACT_WINDOW = 60;
        ArrayNode visionImpactByWard = om.createArrayNode();
        ObjectNode visionImpactByPlayer = om.createObjectNode();
        ObjectNode visionImpactByTeam = om.createObjectNode();
        for (ObjectNode w : wardPlacements) {
            String type = w.path("type").asText("");
            if (!"item_ward_observer".equals(type)) continue;
            long ts = w.path("time").asLong(-1); if (ts < 0) continue;
            long te = ts + VISION_IMPACT_WINDOW;
            String owner = w.path("player").asText("");
            String team = heroTeamMap.getOrDefault(owner, "");
            // Try to assign ward coordinates from entity list by team/type order
            double wardX = w.path("ward_x").asDouble(Double.NaN);
            double wardY = w.path("ward_y").asDouble(Double.NaN);
            if (Double.isNaN(wardX) || Double.isNaN(wardY)) {
                String key = team + "|observer";
                // simple heuristic: use closest entity by index if not already assigned
                for (ObjectNode we : wardEntities) {
                    if (team.equals(we.path("team").asText("")) && "observer".equals(we.path("type").asText(""))) {
                        wardX = we.path("x").asDouble(wardX);
                        wardY = we.path("y").asDouble(wardY);
                        break;
                    }
                }
            }
            int killsForTeam = 0;
            int killsAgainstTeam = 0;
            int fightsInWindow = 0;
            int favorableFights = 0;
            // track enemy heroes and activity counts (damage/heal/death)
            Map<String, Integer> enemyEventCounts = new HashMap<>();
            // scan fights for events and favorable swings
            for (int i = 0; i < fightsSimple.size(); i++) {
                ObjectNode f = (ObjectNode) fightsSimple.get(i);
                long fs = f.path("start").asLong(Long.MIN_VALUE);
                boolean timeOk = fs >= ts && fs <= te;
                boolean spatialOk = false;
                if (!Double.isNaN(wardX) && !Double.isNaN(wardY)) {
                    // approximate fight location by averaging participants' last known sample before fs
                    ArrayNode parts = (ArrayNode) f.path("participants");
                    double sx = 0, sy = 0; int cnt = 0;
                    for (int pj = 0; pj < parts.size(); pj++) {
                        String hero = parts.get(pj).asText("");
                        List<double[]> samples = heroPosSamples.getOrDefault(hero, Collections.emptyList());
                        // find latest sample <= fs
                        double[] best = null;
                        for (int si = samples.size() - 1; si >= 0; si--) {
                            double[] s = samples.get(si);
                            if (s[0] <= fs) { best = s; break; }
                        }
                        if (best != null) { sx += best[1]; sy += best[2]; cnt++; }
                    }
                    if (cnt > 0) {
                        double cx = sx / cnt, cy = sy / cnt;
                        double dx = cx - wardX, dy = cy - wardY;
                        spatialOk = Math.hypot(dx, dy) <= VISION_RADIUS;
                    }
                }
                if (timeOk && (spatialOk || Double.isNaN(wardX))) {
                    fightsInWindow++;
                    ObjectNode sw = (ObjectNode) f.path("swing");
                    long g = sw != null ? sw.path("gold").asLong(0) : 0;
                    long x = sw != null ? sw.path("xp").asLong(0) : 0;
                    boolean fav = false;
                    if ("Radiant".equals(team)) fav = (g > 0) || (x > 0);
                    else if ("Dire".equals(team)) fav = (g < 0) || (x < 0);
                    if (fav) favorableFights++;
                }
                // events within window (using events in fights)
                ArrayNode evs = (ArrayNode) f.path("events");
                if (evs != null) {
                    for (int j = 0; j < evs.size(); j++) {
                        ObjectNode ev = (ObjectNode) evs.get(j);
                        String kind = ev.path("kind").asText("");
                        long t = ev.path("time").asLong(Long.MIN_VALUE);
                        if (t < ts || t > te) continue;
                        String attacker = ev.path("src").asText("");
                        String target = ev.path("dst").asText("");
                        String atkTeam = heroTeamMap.getOrDefault(attacker, teamFromName(attacker));
                        String tgtTeam = heroTeamMap.getOrDefault(target, teamFromName(target));
                        // spatial filter for enemy activity if ward coords available
                        if (!Double.isNaN(wardX) && !Double.isNaN(wardY)) {
                            boolean near = false;
                            // check attacker position near time t
                            List<double[]> atkSamples = heroPosSamples.getOrDefault(attacker, Collections.emptyList());
                            if (!atkSamples.isEmpty()) {
                                double[] best = null; for (int si = atkSamples.size()-1; si >= 0; si--) { double[] s = atkSamples.get(si); if (s[0] <= t) { best = s; break; } }
                                if (best != null && Math.hypot(best[1]-wardX, best[2]-wardY) <= VISION_RADIUS) near = true;
                            }
                            if (!near) {
                                List<double[]> tgtSamples = heroPosSamples.getOrDefault(target, Collections.emptyList());
                                if (!tgtSamples.isEmpty()) {
                                    double[] best = null; for (int si = tgtSamples.size()-1; si >= 0; si--) { double[] s = tgtSamples.get(si); if (s[0] <= t) { best = s; break; } }
                                    if (best != null && Math.hypot(best[1]-wardX, best[2]-wardY) <= VISION_RADIUS) near = true;
                                }
                            }
                            if (!near) continue; // skip event if not near ward
                        }
                        // enemy activity counts
                        if ("damage".equals(kind) || "heal".equals(kind) || "death".equals(kind)) {
                            if (attacker != null && !attacker.isEmpty()) {
                                String tm = heroTeamMap.getOrDefault(attacker, teamFromName(attacker));
                                if (tm != null && !tm.equals(team)) enemyEventCounts.merge(attacker, 1, Integer::sum);
                            }
                            if (target != null && !target.isEmpty()) {
                                String tm2 = heroTeamMap.getOrDefault(target, teamFromName(target));
                                if (tm2 != null && !tm2.equals(team)) enemyEventCounts.merge(target, 1, Integer::sum);
                            }
                        }
                        if (!"death".equals(kind)) continue;
                        if (atkTeam != null && atkTeam.equals(team)) killsForTeam++;
                        if (tgtTeam != null && tgtTeam.equals(team)) killsAgainstTeam++;
                    }
                }
            }
            int trackedEnemies = 0;
            int movementActors = 0;
            for (Map.Entry<String, Integer> en : enemyEventCounts.entrySet()) {
                if (en.getValue() > 0) trackedEnemies++;
                if (en.getValue() >= 2) movementActors++;
            }
            double efficiency = trackedEnemies * 0.5
                    + movementActors * 0.25
                    + favorableFights * 1.0
                    + (killsForTeam - killsAgainstTeam) * 0.75;
            ObjectNode v = om.createObjectNode();
            v.put("time", ts);
            v.put("player", owner);
            v.put("team", team);
            v.put("type", type);
            v.put("window", VISION_IMPACT_WINDOW);
            v.put("kills_for_team_window", killsForTeam);
            v.put("kills_against_team_window", killsAgainstTeam);
            v.put("fights_in_window", fightsInWindow);
            v.put("favorable_fights_window", favorableFights);
            if (!Double.isNaN(wardX)) v.put("ward_x", wardX);
            if (!Double.isNaN(wardY)) v.put("ward_y", wardY);
            v.put("tracked_enemy_heroes_estimate", trackedEnemies);
            v.put("movement_events_estimate", movementActors);
            v.put("efficiency_score", efficiency);
            visionImpactByWard.add(v);
            if (!owner.isEmpty()) {
                ObjectNode p = (ObjectNode) visionImpactByPlayer.get(owner);
                if (p == null) { p = om.createObjectNode(); visionImpactByPlayer.set(owner, p); }
                aggAdd(p, "kills_for_team_window", killsForTeam);
                aggAdd(p, "kills_against_team_window", killsAgainstTeam);
                aggAdd(p, "fights_in_window", fightsInWindow);
                aggAdd(p, "favorable_fights_window", favorableFights);
                aggAdd(p, "tracked_enemy_heroes_estimate", trackedEnemies);
                aggAdd(p, "movement_events_estimate", movementActors);
                aggAdd(p, "efficiency_score_sum", (int) Math.round(efficiency));
                aggAdd(p, "_count", 1);
            }
            if (team != null && !team.isEmpty()) {
                ObjectNode t = (ObjectNode) visionImpactByTeam.get(team);
                if (t == null) { t = om.createObjectNode(); visionImpactByTeam.set(team, t); }
                aggAdd(t, "kills_for_team_window", killsForTeam);
                aggAdd(t, "kills_against_team_window", killsAgainstTeam);
                aggAdd(t, "fights_in_window", fightsInWindow);
                aggAdd(t, "favorable_fights_window", favorableFights);
                aggAdd(t, "tracked_enemy_heroes_estimate", trackedEnemies);
                aggAdd(t, "movement_events_estimate", movementActors);
                aggAdd(t, "efficiency_score_sum", (int) Math.round(efficiency));
                aggAdd(t, "_count", 1);
            }
        }

        // 16) Lane/Role Approximation (early-window heuristic)
        final long EARLY_END = 7 * 60;
        Map<String, Integer> earlyWardsByPlayer = new HashMap<>();
        Map<String, Integer> earlySmokesByPlayer = new HashMap<>();
        for (int i = 0; i < wardsEvents.size(); i++) {
            ObjectNode w = (ObjectNode) wardsEvents.get(i);
            long t = w.path("time").asLong(0);
            if (t <= EARLY_END) earlyWardsByPlayer.merge(w.path("player").asText(""), 1, Integer::sum);
        }
        for (int i = 0; i < smokesEvents.size(); i++) {
            ObjectNode s = (ObjectNode) smokesEvents.get(i);
            long t = s.path("time").asLong(0);
            if (t <= EARLY_END) earlySmokesByPlayer.merge(s.path("player").asText(""), 1, Integer::sum);
        }
        ObjectNode laneRolesByPlayer = om.createObjectNode();
        Set<String> playersSeen = new HashSet<>();
        for (int i = 0; i < abilityCasts.size(); i++) {
            String p = ((ObjectNode) abilityCasts.get(i)).path("caster").asText(""); if (!p.isEmpty()) playersSeen.add(p);
        }
        for (Iterator<String> it = damageSummary.fieldNames(); it.hasNext();) {
            String k = it.next(); String[] parts = k.split("\\|", -1); if (parts.length>0 && !parts[0].isEmpty()) playersSeen.add(parts[0]);
        }
        for (String p : playersSeen) {
            ObjectNode lr = om.createObjectNode();
            int w = earlyWardsByPlayer.getOrDefault(p, 0);
            int s = earlySmokesByPlayer.getOrDefault(p, 0);
            boolean supportish = (w + s) >= 2;
            lr.put("role_guess", supportish ? "support" : "core");
            String team = heroTeamMap.getOrDefault(p, "");
            lr.put("team", team);
            lr.put("early_wards", w);
            lr.put("early_smokes", s);
            lr.put("confidence", supportish ? 0.6 : 0.5);
            laneRolesByPlayer.set(p, lr);
        }

    // 17) Roshan Control per team (±60s): wards/sentries and heroes presence by team (approx via fight participants)
        ObjectNode roshanControl = om.createObjectNode();
        if (rk >= 0) {
            long rs = rk - 60, re = rk + 60;
            ObjectNode wardsByTeamRC = om.createObjectNode();
            ObjectNode sentriesByTeamRC = om.createObjectNode();
            ObjectNode heroesPresenceRC = om.createObjectNode();
            for (int i = 0; i < wardsEvents.size(); i++) {
                ObjectNode w = (ObjectNode) wardsEvents.get(i);
                long t = w.path("time").asLong(Long.MIN_VALUE); if (t < rs || t > re) continue;
                String type = w.path("type").asText("");
                String owner = w.path("player").asText("");
                String team = heroTeamMap.getOrDefault(owner, "");
                if (type.contains("observer")) aggAdd(wardsByTeamRC, team, 1);
                else if (type.contains("sentry")) aggAdd(sentriesByTeamRC, team, 1);
            }
            Set<String> present = new HashSet<>();
            for (int fi = 0; fi < fightsSimple.size(); fi++) {
                ObjectNode f = (ObjectNode) fightsSimple.get(fi);
                long fs = f.path("start").asLong(Long.MIN_VALUE);
                long fe = f.path("end").asLong(Long.MIN_VALUE);
                if (fs == Long.MIN_VALUE || fe == Long.MIN_VALUE) continue;
                if (fe < rs || fs > re) continue;
                ArrayNode p = (ArrayNode) f.path("participants");
                for (int pj = 0; pj < p.size(); pj++) present.add(p.get(pj).asText(""));
            }
            ObjectNode hpTeam = om.createObjectNode();
            for (String actor : present) {
                String team = heroTeamMap.getOrDefault(actor, "");
                if (!team.isEmpty()) aggAdd(hpTeam, team, 1);
            }
            heroesPresenceRC.setAll(hpTeam);
            roshanControl.set("wards_by_team", wardsByTeamRC);
            roshanControl.set("sentries_by_team", sentriesByTeamRC);
            roshanControl.set("heroes_presence_by_team", heroesPresenceRC);
            roshanControl.put("window", 60);
        }

        // Build enriched
        ObjectNode enriched = om.createObjectNode();
        enriched.set("wards_events", wardsEvents);
        enriched.set("smokes_events", smokesEvents);
        enriched.set("item_events", itemEvents);
        enriched.set("runes_events", runesEvents);
        enriched.set("roshan_summary", roshanSummary);
        enriched.set("objectives_basic", objectivesBasic);
        enriched.set("buybacks", buybacks);
        enriched.set("fights_simple", fightsSimple);
        enriched.set("damage_summary", damageSummary);
        enriched.set("healing_summary", healingSummary);
        enriched.set("cc_summary", ccSummary);
    enriched.set("ability_casts", abilityCasts);
    enriched.set("item_uses", itemUses);
    // Aggregated stats block
    ObjectNode aggregated = om.createObjectNode();
    aggregated.set("ability_usage_by_caster", abilityUsageByCaster);
    aggregated.set("ability_usage_by_owner", abilityUsageByOwner);
    aggregated.set("ability_usage_by_ability", abilityUsageByAbility);
    aggregated.set("ult_usage_by_caster", ultUsageByCaster);
    aggregated.set("damage_by_attacker", damageByAttacker);
    aggregated.set("damage_by_target", damageByTarget);
    aggregated.set("damage_by_pair", damageByPair);
    aggregated.set("damage_by_attacker_ability", damageByAttackerAbility);
    aggregated.set("cc_by_attacker", ccByAttacker);
    aggregated.set("cc_instances", ccInstances);
    aggregated.set("wards_by_player", wardsByPlayer);
    aggregated.set("dewards_by_player", dewardsByPlayer);
    aggregated.set("rune_pickups_by_player", runePickupsByPlayer);
    aggregated.set("smokes_by_player", smokesByPlayer);
    aggregated.set("item_pickups_by_player", itemPickupsByPlayer);
    aggregated.set("buybacks_by_player", buybacksByPlayer);
    aggregated.set("buybacks_first_time", buybacksFirstTime);
    aggregated.set("buybacks_last_time", buybacksLastTime);
    aggregated.set("objectives_by_team", objectivesByTeam);
    aggregated.set("fights_overview", fightsOverview);
    aggregated.set("first_purchase_by_player_by_item", firstPurchaseByPlayerByItem);
    aggregated.set("power_spikes_by_player", powerSpikesByPlayer);
    aggregated.set("cc_efficiency", ccEfficiency);
    aggregated.set("economy_lead_series", economySeries);
    aggregated.set("lead_switch_events", leadSwitchEvents);
        aggregated.set("objective_sequences", objectiveSequences);
        if (wardHotspots != null && wardHotspots.size() > 0) {
            aggregated.set("ward_hotspots", wardHotspots);
        } else {
            aggregated.set("ward_hotspots", om.createArrayNode());
        }
    aggregated.set("vision_impact_by_ward", visionImpactByWard);
    // compute averages for efficiency in rollups
    ObjectNode visionImpactByPlayerOut = om.createObjectNode();
    for (Iterator<String> it = visionImpactByPlayer.fieldNames(); it.hasNext();) {
        String p = it.next();
        ObjectNode node = (ObjectNode) visionImpactByPlayer.get(p);
        int sum = node.path("efficiency_score_sum").asInt(0);
        int cnt = node.path("_count").asInt(0);
        if (cnt > 0) node.put("efficiency_score_avg", sum / (double) cnt);
        visionImpactByPlayerOut.set(p, node);
    }
    ObjectNode visionImpactByTeamOut = om.createObjectNode();
    for (Iterator<String> it = visionImpactByTeam.fieldNames(); it.hasNext();) {
        String t = it.next();
        ObjectNode node = (ObjectNode) visionImpactByTeam.get(t);
        int sum = node.path("efficiency_score_sum").asInt(0);
        int cnt = node.path("_count").asInt(0);
        if (cnt > 0) node.put("efficiency_score_avg", sum / (double) cnt);
        visionImpactByTeamOut.set(t, node);
    }
    aggregated.set("vision_impact_by_player", visionImpactByPlayerOut);
    aggregated.set("vision_impact_by_team", visionImpactByTeamOut);
    aggregated.set("objective_chain_details", objectiveChainDetails);
    if (roshanContext.size() > 0) aggregated.set("roshan_context", roshanContext);
    if (roshanControl.size() > 0) aggregated.set("roshan_control", roshanControl);
    aggregated.set("lane_roles_by_player", laneRolesByPlayer);
    enriched.set("aggregated_stats", aggregated);

        root.set("enriched", enriched);

        // meta
        ObjectNode meta = om.createObjectNode();
        meta.put("generator", "clarity-cli");
    meta.put("version", "0.1.1");
    meta.put("schema_version", "1.2.0");
        meta.put("notes", "timestamps in seconds; GameEvents+CombatLog blended; aggregated_stats includes wards/runes/smokes/buybacks/objectives/fights/damage");
        root.set("meta", meta);

        // write file
        Files.writeString(outPath, om.writerWithDefaultPrettyPrinter().writeValueAsString(root));
    }

    private static String toStr(Object o){ return o == null ? null : o.toString(); }
    private static String safe(String s){ return s == null ? "" : s; }
    private static String key(String a, String b, String c){ return (safe(a) + "|" + safe(b) + "|" + safe(c)); }
    private static boolean isBuilding(String name){
        String n = name == null ? "" : name.toLowerCase();
        return n.contains("tower") || n.contains("rax") || n.contains("fort") || n.contains("barracks") || n.contains("outpost");
    }
    private static boolean isWard(String name){
        String n = name == null ? "" : name.toLowerCase();
        return n.contains("ward");
    }
    private static boolean isHero(String name){
        String n = name == null ? "" : name.toLowerCase();
        return n.startsWith("npc_dota_hero_");
    }
    private static String normalizeOwner(String unit){
        if (unit == null) return "";
        String u = unit.toLowerCase();
        // If it is already a hero, that's the owner.
        if (u.startsWith("npc_dota_hero_")) return u;
        // Common controlled unit patterns to strip to the base hero when possible
        // Illusions: often carry the base hero name plus "_illusion" or "illusion_" prefix
        if (u.contains("illusion")) {
            // try to locate a hero substring
            int i = u.indexOf("npc_dota_hero_");
            if (i >= 0) {
                return u.substring(i);
            }
        }
        // Lone Druid Bear
        if (u.contains("spirit_bear")) return "npc_dota_hero_lone_druid";
        // Arc Warden Tempest Double
        if (u.contains("tempest_double") || u.contains("arc_warden_tempest")) return "npc_dota_hero_arc_warden";
        // Meepo clones
        if (u.contains("meepo") && !u.contains("npc_dota_hero_")) return "npc_dota_hero_meepo";
        // Visage familiars
        if (u.contains("visage_familiar")) return "npc_dota_hero_visage";
        // Chen/Enchantress dominated creeps or generic controlled units: leave as-is; upstream can map via player context if needed
        return u;
    }
    private static long parseTime(Object o){
        try {
            String s = String.valueOf(o);
            if (s == null || s.isEmpty() || s.equals("null")) return -1L;
            double d = Double.parseDouble(s);
            return (long) Math.round(d);
        } catch (Exception e){ return -1L; }
    }
    private static String teamFromName(String name){
        if (name == null) return "";
        String n = name.toLowerCase();
        if (n.contains("goodguys")) return "Radiant";
        if (n.contains("badguys")) return "Dire";
        return "";
    }
    private static boolean isRelevantCC(String mod){
        return mod.contains("stun") || mod.contains("root") || mod.contains("silence") || mod.contains("hex");
    }
    private static String ccCategory(String mod){
        if (mod.contains("stun")) return "stun";
        if (mod.contains("root")) return "root";
        if (mod.contains("silence")) return "silence";
        if (mod.contains("hex")) return "hex";
        return "other";
    }
    private static void flushFight(List<ObjectNode> buffer, ArrayNode out, ObjectMapper om){
        if (buffer.isEmpty()) return;
        long start = Long.MAX_VALUE, end = Long.MIN_VALUE;
        Set<String> participants = new HashSet<>();
        for (ObjectNode ev : buffer){
            long t = ev.path("time").asLong();
            if (t < start) start = t;
            if (t > end) end = t;
            if (ev.has("src") && !ev.path("src").asText().isEmpty()) participants.add(ev.path("src").asText());
            if (ev.has("dst") && !ev.path("dst").asText().isEmpty()) participants.add(ev.path("dst").asText());
        }
        ObjectNode f = om.createObjectNode();
        f.put("start", start);
        f.put("end", end);
        ArrayNode p = om.createArrayNode();
        for (String s : participants) p.add(s);
        f.set("participants", p);
        // include events for spatial clustering & proxies
        ArrayNode evs = om.createArrayNode();
        for (ObjectNode ev : buffer) { evs.add(ev.deepCopy()); }
        f.set("events", evs);
        out.add(f);
        buffer.clear();
    }
    private static void aggAdd(ObjectNode map, String key, int value){
        if (!map.has(key)) map.put(key, 0);
        map.put(key, map.get(key).asInt() + value);
    }
    private static ObjectNode nearestSentry(List<ObjectNode> sentries, long wardPlacedAt, long wardDiedAt){
        ObjectNode best = null;
        long bestDt = Long.MAX_VALUE;
        for (ObjectNode s : sentries){
            long st = s.path("time").asLong(-1);
            if (st < 0) continue;
            if (st > wardDiedAt) continue;
            long dt = wardDiedAt - st;
            if (dt < bestDt && dt <= 60) { bestDt = dt; best = s; }
        }
        return best;
    }
}
