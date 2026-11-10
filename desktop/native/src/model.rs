//! Local presentation helpers. No network or account credentials are handled here.

use evertally_sync::local::AccountData;
use serde_json::Value;

#[derive(Clone, Debug, PartialEq)]
pub struct ZoneVisit {
    pub map_id: u64,
    pub name: String,
    pub count: usize,
    pub last_seen: f64,
}

/// Region history contains no point coordinates. Only explicit visit events count.
pub fn visited_zones(accounts: &[&AccountData], character_id: Option<&str>) -> Vec<ZoneVisit> {
    let mut zones = std::collections::BTreeMap::<u64, ZoneVisit>::new();
    for event in accounts.iter().flat_map(|account| &account.events) {
        if event["kind"] != "zone.visited"
            || character_id.is_some_and(|id| event["character"]["id"].as_str() != Some(id))
        {
            continue;
        }
        let payload = &event["payload"];
        let Some(map_id) = payload["mapId"].as_u64().filter(|id| *id > 0) else {
            continue;
        };
        let name = payload["mapName"]
            .as_str()
            .or_else(|| payload["name"].as_str())
            .unwrap_or("");
        let at = event["observedAt"]
            .as_f64()
            .filter(|v| v.is_finite())
            .unwrap_or(0.0);
        let entry = zones.entry(map_id).or_insert_with(|| ZoneVisit {
            map_id,
            name: if name.is_empty() {
                format!("Zone #{map_id}")
            } else {
                name.to_owned()
            },
            count: 0,
            last_seen: at,
        });
        entry.count += 1;
        if at >= entry.last_seen {
            entry.last_seen = at;
            if !name.is_empty() {
                entry.name = name.to_owned();
            }
        }
    }
    let mut list: Vec<_> = zones.into_values().collect();
    list.sort_by(|a, b| b.last_seen.total_cmp(&a.last_seen));
    list
}

/// The raw-data panel must not become a back door to exact player locations.
pub fn without_coordinates(value: &Value) -> Value {
    match value {
        Value::Object(object) => Value::Object(
            object
                .iter()
                .filter(|(key, _)| {
                    !matches!(
                        key.as_str(),
                        "x" | "y"
                            | "z"
                            | "positionX"
                            | "positionY"
                            | "positionZ"
                            | "worldX"
                            | "worldY"
                            | "worldZ"
                            | "position"
                    )
                })
                .map(|(k, v)| (k.clone(), without_coordinates(v)))
                .collect(),
        ),
        Value::Array(values) => Value::Array(values.iter().map(without_coordinates).collect()),
        _ => value.clone(),
    }
}

pub fn text<'a>(value: &'a Value, key: &str) -> &'a str {
    value[key].as_str().unwrap_or("—")
}

pub fn number(value: &Value, key: &str) -> String {
    value[key]
        .as_u64()
        .map_or_else(|| "—".to_owned(), |n| n.to_string())
}

pub fn duration(ms: Option<u64>) -> String {
    let Some(ms) = ms else { return "—".into() };
    let seconds = ms / 1000;
    if seconds >= 3600 {
        format!(
            "{}:{:02}:{:02}",
            seconds / 3600,
            seconds / 60 % 60,
            seconds % 60
        )
    } else {
        format!("{}:{:02}", seconds / 60, seconds % 60)
    }
}

pub fn timestamp(value: Option<f64>) -> String {
    value
        .filter(|v| v.is_finite() && *v >= 0.0 && *v <= 253_402_300_799.0)
        .map_or_else(
            || "—".to_owned(),
            |v| {
                evertally_sync::config::utc_timestamp(
                    std::time::UNIX_EPOCH + std::time::Duration::from_secs(v as u64),
                )
            },
        )
}

pub fn class_name(id: Option<u64>) -> &'static str {
    match id {
        Some(1) => "Warrior",
        Some(2) => "Paladin",
        Some(3) => "Hunter",
        Some(4) => "Rogue",
        Some(5) => "Priest",
        Some(6) => "Death Knight",
        Some(7) => "Shaman",
        Some(8) => "Mage",
        Some(9) => "Warlock",
        Some(10) => "Monk",
        Some(11) => "Druid",
        Some(12) => "Demon Hunter",
        Some(13) => "Evoker",
        _ => "—",
    }
}

pub fn race_name(id: Option<u64>) -> &'static str {
    match id {
        Some(1) => "Human",
        Some(2) => "Orc",
        Some(3) => "Dwarf",
        Some(4) => "Night Elf",
        Some(5) => "Undead",
        Some(6) => "Tauren",
        Some(7) => "Gnome",
        Some(8) => "Troll",
        Some(9) => "Goblin",
        Some(10) => "Blood Elf",
        Some(11) => "Draenei",
        Some(22) => "Worgen",
        Some(24..=26) => "Pandaren",
        _ => "—",
    }
}

pub fn matches(value: &Value, query: &str) -> bool {
    query.trim().is_empty()
        || value
            .to_string()
            .to_lowercase()
            .contains(&query.trim().to_lowercase())
}

/// Keep the last good local snapshot when the game is halfway through saving a file.
/// Error metadata remains visible so a retained snapshot is never presented as fresh.
pub fn merge_accounts(previous: &mut Vec<AccountData>, fresh: Vec<AccountData>) {
    let mut merged = Vec::with_capacity(fresh.len());
    for new in fresh {
        if let Some(index) = previous
            .iter()
            .position(|old| old.account == new.account && old.flavor == new.flavor)
        {
            let mut old = previous.remove(index);
            if new.error.is_some()
                && (!old.events.is_empty() || !old.runs.is_empty() || !old.characters.is_empty())
            {
                old.error = new.error;
                merged.push(old);
                continue;
            }
        }
        merged.push(new);
    }
    // WoW may briefly rename the old file while replacing it. Keep the last
    // snapshot visibly stale; explicit installation changes clear this cache.
    for mut old in previous.drain(..) {
        old.error = Some("History file unavailable; showing last saved snapshot".to_owned());
        merged.push(old);
    }
    *previous = merged;
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn duration_is_precise_and_missing_is_distinct_from_zero() {
        assert_eq!(duration(None), "—");
        assert_eq!(duration(Some(0)), "0:00");
        assert_eq!(duration(Some(65_999)), "1:05");
        assert_eq!(duration(Some(3_661_000)), "1:01:01");
    }

    #[test]
    fn visited_history_is_coarse_and_separate_per_character() {
        let a = account(
            None,
            vec![
                json!({"kind":"zone.visited","observedAt":10,"character":{"id":"A"},"payload":{"mapId":1426,"mapName":"Dun Morogh","x":0.4,"y":0.3}}),
                json!({"kind":"zone.visited","observedAt":20,"character":{"id":"B"},"payload":{"mapId":1426,"mapName":"Dun Morogh"}}),
                json!({"kind":"npc.observed","payload":{"mapId":1429,"x":0.4,"y":0.3}}),
            ],
        );
        assert_eq!(visited_zones(&[&a], Some("A"))[0].count, 1);
        assert_eq!(visited_zones(&[&a], None)[0].count, 2);
        assert_eq!(visited_zones(&[&a], None).len(), 1);
        assert_eq!(without_coordinates(&a.events[0])["payload"].get("x"), None);
        assert_eq!(without_coordinates(&a.events[0])["payload"]["mapId"], 1426);
    }

    #[test]
    fn search_handles_czech_and_nested_snapshots() {
        let run = json!({"name":"Jeskyně", "character":{"name":"Mardyx"}});
        assert!(matches(&run, "JESKYNĚ"));
        assert!(matches(&run, "mardyx"));
        assert!(!matches(&run, "Stratholme"));
        assert!(matches(&run, " "));
    }

    fn account(error: Option<&str>, events: Vec<Value>) -> AccountData {
        AccountData {
            account: "A".into(),
            flavor: "_forever_".into(),
            characters: vec![],
            runs: vec![],
            event_count: events.len(),
            run_count: 0,
            web_enabled: false,
            sharing_enabled: false,
            peers: 0,
            events,
            error: error.map(str::to_owned),
        }
    }

    #[test]
    fn partial_save_does_not_erase_last_good_local_history() {
        let mut old = vec![account(None, vec![json!({"kind":"quest.accepted"})])];
        merge_accounts(&mut old, vec![account(Some("partial file"), vec![])]);
        assert_eq!(old[0].events.len(), 1);
        assert!(old[0].error.is_some());
        merge_accounts(&mut old, vec![account(Some("still writing"), vec![])]);
        assert_eq!(old[0].events.len(), 1);
        merge_accounts(&mut old, vec![account(None, vec![])]);
        assert!(old[0].events.is_empty());
        assert!(old[0].error.is_none());
    }

    #[test]
    fn replacement_gap_keeps_a_visibly_stale_snapshot_without_duplicating_it() {
        let mut old = vec![account(None, vec![json!({"kind":"quest.accepted"})])];
        merge_accounts(&mut old, vec![]);
        assert_eq!(old.len(), 1);
        assert_eq!(old[0].events.len(), 1);
        assert!(old[0].error.is_some());
        merge_accounts(
            &mut old,
            vec![account(None, vec![json!({"kind":"quest.rewarded"})])],
        );
        assert_eq!(old.len(), 1);
        assert_eq!(old[0].events[0]["kind"], "quest.rewarded");
        assert!(old[0].error.is_none());
    }
}
