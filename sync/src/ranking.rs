//! The website's public leaderboard for the in-game unit tooltip: the public ranking package is fetched over HTTPS
//! without credentials and written to `Interface/AddOns/Evertally/RankingData.lua`, which the game loads at login.
//! It holds only what the website already shows to everyone (name, realm, level, class, race, places on the board,
//! completed runs, and item level and guild where the player chose to show them). Every field is checked here and the
//! addon checks it again; a package with anything outside the rules is not written at all.
use anyhow::{Context, Result, anyhow, ensure};
use serde_json::Value;
use std::{collections::HashSet, fmt::Write as _, path::PathBuf, time::Duration};

pub const DATA_FILE: &str = "RankingData.lua";
const PLACEHOLDER: &str = "-- Placeholder. The Evertally desktop app writes the website's public leaderboard here; the game loads it at login.\nEvertallyRankingData = nil\n";
const MAX_BYTES: u64 = 512 * 1024;
const MAX_PLAYERS: usize = 2000;
const MAX_LIFETIME: i64 = 7 * 86_400;
const LATEST_TIME: i64 = 253_402_300_799;

/// A whole number inside `low..=high`.
fn whole(value: Option<&Value>, low: i64, high: i64) -> Option<i64> {
    value?.as_i64().filter(|n| (low..=high).contains(n))
}

/// `Some(None)` when the field is missing or null, `Some(Some(n))` when it is a valid number, `None` when it is invalid.
fn optional_whole(value: Option<&Value>, low: i64, high: i64) -> Option<Option<i64>> {
    match value {
        None | Some(Value::Null) => Some(None),
        Some(v) => whole(Some(v), low, high).map(Some),
    }
}

/// Text the game can show as it is: no control characters, no `|` (the game's escape character), not only spaces.
fn valid_text(text: &str, max_chars: usize) -> bool {
    let count = text.chars().count();
    (1..=max_chars).contains(&count)
        && !text.chars().any(|c| c.is_control() || c == '|')
        && text.chars().any(|c| !c.is_whitespace())
}

fn text(value: Option<&Value>, max_chars: usize) -> Option<&str> {
    value?.as_str().filter(|t| valid_text(t, max_chars))
}

/// One player as a Lua table, or `None` when any field is outside the rules.
fn player(out: &mut String, p: &Value, seen: &mut HashSet<(String, String)>) -> Option<()> {
    let name = text(p.get("name"), 48)?;
    let realm = text(p.get("realm"), 64)?;
    if !seen.insert((name.to_lowercase(), realm.to_lowercase())) {
        return None;
    }
    let level = optional_whole(p.get("level"), 1, 100)?;
    let class = optional_whole(p.get("classId"), 1, 30)?;
    let race = optional_whole(p.get("raceId"), 1, 200)?;
    let rank = whole(p.get("rank"), 1, 1_000_000)?;
    let class_rank = whole(p.get("classRank"), 1, 1_000_000)?;
    let completed = whole(p.get("completed"), 0, 1_000_000)?;
    let item_level = optional_whole(p.get("itemLevel"), 1, 1000)?;
    let guild = match p.get("guild") {
        None | Some(Value::Null) => None,
        some => Some(text(some, 48)?),
    };
    out.push_str("{n=");
    crate::forum::lua_string(out, name);
    out.push_str(",r=");
    crate::forum::lua_string(out, realm);
    // Writing into a String cannot fail.
    let _ = write!(out, ",k={rank},ck={class_rank},u={completed}");
    for (key, value) in [("l", level), ("c", class), ("x", race), ("i", item_level)] {
        if let Some(v) = value {
            let _ = write!(out, ",{key}={v}");
        }
    }
    if let Some(g) = guild {
        out.push_str(",g=");
        crate::forum::lua_string(out, g);
    }
    out.push_str("},\n");
    Some(())
}

/// The Lua text for a package, or `None` when anything in it is outside what the addon accepts.
#[must_use]
pub fn data_file(package: &Value) -> Option<String> {
    if package.get("schemaVersion")?.as_i64()? != 1
        || package.get("kind")?.as_str()? != "evertally-ranking"
        || package.get("game")?.get("product")?.as_str()? != "forever"
    {
        return None;
    }
    let generated = whole(package.get("generatedAt"), 0, LATEST_TIME)?;
    let expires = whole(package.get("expiresAt"), 0, LATEST_TIME)?;
    if expires <= generated || expires > generated + MAX_LIFETIME {
        return None;
    }
    let total = whole(package.get("total"), 0, 10_000_000)?;
    let truncated = package.get("truncated")?.as_bool()?;
    let players = package.get("players")?.as_array()?;
    if players.len() > MAX_PLAYERS || i64::try_from(players.len()).ok()? > total {
        return None;
    }
    let mut body = String::with_capacity(players.len() * 80);
    let mut seen = HashSet::with_capacity(players.len());
    for p in players {
        player(&mut body, p, &mut seen)?;
    }
    Some(format!(
        "-- Written by Evertally Sync from the website's public leaderboard. It is replaced after every sync; do not edit.\n\
         EvertallyRankingData = {{\nschemaVersion=1,kind=\"evertally-ranking\",generatedAt={generated},expiresAt={expires},\n\
         game={{product=\"forever\"}},total={total},truncated={truncated},\nplayers={{\n{body}}},\n}}\n"
    ))
}

/// Fetches the package and writes it next to every installed addon. Returns how many addon folders changed.
///
/// # Errors
/// Network failures, an origin that is not HTTPS, and packages that do not pass the checks.
pub fn sync(origin: &str, addons: &[PathBuf]) -> Result<usize> {
    ensure!(origin.starts_with("https://"), "leaderboard sync requires HTTPS");
    // The placeholder keeps the game from warning about a missing file even when the website cannot be reached.
    for addons_dir in addons {
        let target = addons_dir.join("Evertally").join(DATA_FILE);
        if !target.exists() && addons_dir.join("Evertally").is_dir() {
            let _ = crate::forum::write_if_changed(&target, PLACEHOLDER);
        }
    }
    let agent: ureq::Agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(25))).max_redirects(0).build().into();
    let bytes = crate::addon_update::read_url(&agent, &format!("{origin}/api/ranking-package"), MAX_BYTES)?;
    let package: Value = serde_json::from_slice(&bytes).context("the leaderboard package is not JSON")?;
    let text = data_file(&package).ok_or_else(|| anyhow!("the website's leaderboard package did not pass the checks"))?;
    let mut changed = 0;
    for addons_dir in addons {
        let folder = addons_dir.join("Evertally");
        if folder.is_dir() && crate::forum::write_if_changed(&folder.join(DATA_FILE), &text)? {
            changed += 1;
        }
    }
    Ok(changed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn package() -> Value {
        json!({"schemaVersion":1,"kind":"evertally-ranking","game":{"product":"forever"},"generatedAt":1_794_603_121,"expiresAt":1_794_862_321,
            "total":3,"truncated":false,"players":[
                {"name":"Aerin","realm":"Firemaw","level":60,"classId":11,"raceId":95,"rank":1,"classRank":1,"completed":4,"itemLevel":62,"guild":"Dawn \"Watch\""},
                {"name":"Brok","realm":"Firemaw","level":60,"classId":1,"raceId":2,"rank":2,"classRank":1,"completed":0},
                {"name":"Žofie","realm":"Golemagg","level":null,"classId":null,"raceId":null,"rank":3,"classRank":1,"completed":1}]})
    }

    #[test]
    fn a_valid_package_becomes_lua_data_with_escaped_text_and_optional_fields() {
        let lua = data_file(&package()).expect("valid package");
        assert!(lua.contains("EvertallyRankingData = {"));
        assert!(lua.contains(r#"{n="Aerin",r="Firemaw",k=1,ck=1,u=4,l=60,c=11,x=95,i=62,g="Dawn \"Watch\""},"#));
        assert!(lua.contains(r#"{n="Brok",r="Firemaw",k=2,ck=1,u=0,l=60,c=1,x=2},"#), "no item level or guild when not shown");
        assert!(lua.contains(r#"{n="Žofie",r="Golemagg",k=3,ck=1,u=1},"#), "unknown level, class and race are left out");
        let parsed = crate::savedvars::parse_assignment(&lua, "EvertallyRankingData").expect("data only, no code");
        assert_eq!(parsed["players"].as_array().map(Vec::len), Some(3));
    }

    #[test]
    fn anything_outside_the_rules_writes_nothing() {
        let broken: [fn(&mut Value); 9] = [
            |p| p["kind"] = json!("evertally-community"),
            |p| p["expiresAt"] = json!(1_794_603_121 + MAX_LIFETIME + 1),
            |p| p["expiresAt"] = p["generatedAt"].clone(),
            |p| p["players"][0]["level"] = json!(61.5),
            |p| p["players"][0]["name"] = json!("Aerin|cffff0000"),
            |p| p["players"][1]["name"] = json!("aerin"),
            |p| p["players"][0]["guild"] = json!("x".repeat(49)),
            |p| p["players"][0]["rank"] = json!(0),
            |p| p["total"] = json!(2),
        ];
        for (i, change) in broken.iter().enumerate() {
            let mut p = package();
            change(&mut p);
            assert!(data_file(&p).is_none(), "case {i} must be refused");
        }
    }

    #[test]
    fn the_placeholder_is_valid_lua_data() {
        let parsed = crate::savedvars::parse_assignment(PLACEHOLDER, "EvertallyRankingData");
        assert!(parsed.is_ok_and(|v| v.is_null()));
    }

    #[test]
    fn only_https_origins_are_fetched() {
        assert!(sync("http://example.test", &[]).is_err());
    }
}
