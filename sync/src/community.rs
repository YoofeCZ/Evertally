//! Website facts without pasting: the public community package of the website is fetched over HTTPS and written to
//! `Interface/AddOns/Evertally/CommunityData.lua`, which the game loads at login (the same way as the forum data).
//! The package is public and anonymous, so no device credential is sent. Everything is checked here and the addon checks it
//! again with the same rules as for a pasted package; anything damaged is simply not written.
use anyhow::{Result, ensure};
use serde_json::Value;
use std::{path::Path, time::Duration};

pub const DATA_FILE: &str = "CommunityData.lua";
const PLACEHOLDER: &str = "-- Placeholder. The Evertally desktop app writes the website's public facts here; the game loads it at login.\nEvertallyCommunityData = nil\n";
const MAX_BYTES: u64 = 48 * 1024;
const MAX_ENTITIES: usize = 150;
const WEEK: i64 = 604_800;

fn whole(value: &Value, low: i64, high: i64) -> Option<i64> {
    let n = value.as_f64()?;
    #[allow(clippy::cast_possible_truncation)]
    let w = n.floor() as i64;
    (n.is_finite() && (low..=high).contains(&w) && (n - n.floor()).abs() < f64::EPSILON).then_some(w)
}

fn valid_name(name: &str) -> bool {
    let n = name.chars().count();
    (1..=160).contains(&n) && !name.chars().any(|c| (c as u32) < 32 || c as u32 == 127 || c == '|') && name.chars().any(|c| !c.is_whitespace())
}

fn fraction(value: &Value) -> Option<f64> {
    value.as_f64().filter(|v| v.is_finite() && (0.0..=1.0).contains(v))
}

/// The Lua text for a package, or `None` when anything in it is outside what the addon accepts.
#[must_use]
pub fn data_file(package: &Value) -> Option<String> {
    if package.get("schemaVersion")?.as_i64()? != 1
        || package.get("kind")?.as_str()? != "evertally-community"
        || package.get("scope")?.as_str()? != "world_facts"
        || package.get("game")?.get("product")?.as_str()? != "forever"
    {
        return None;
    }
    let generated = whole(package.get("generatedAt")?, 0, 253_402_300_799)?;
    let expires = whole(package.get("expiresAt")?, 0, 253_402_300_799)?;
    if expires <= generated || expires > generated + WEEK {
        return None;
    }
    let provenance = package.get("provenance")?;
    let truncated = provenance.get("truncated")?.as_bool()?;
    let observations = whole(provenance.get("observationCount")?, 0, 10_000)?;
    let entity_count = whole(provenance.get("entityCount")?, 0, 10_000)?;
    let entities = package.get("entities")?.as_array()?;
    if entities.len() > MAX_ENTITIES || (entities.len() as i64) > entity_count {
        return None;
    }
    let mut body = String::new();
    let mut seen = std::collections::HashSet::new();
    for entity in entities {
        let kind = entity.get("kind")?.as_str()?;
        if !["quest", "npc", "item"].contains(&kind) {
            return None;
        }
        let id = whole(entity.get("id")?, 1, 2_147_483_647)?;
        let name = entity.get("name")?.as_str().filter(|n| valid_name(n))?;
        let count = whole(entity.get("count")?, 1, 10_000)?;
        let last_seen = whole(entity.get("lastSeen")?, 0, generated + 300)?;
        if !seen.insert((kind.to_owned(), id)) {
            return None;
        }
        body.push_str(&format!("{{kind=\"{kind}\",id={id},name="));
        crate::forum::lua_string(&mut body, name);
        body.push_str(&format!(",count={count},lastSeen={last_seen}"));
        if let Some(map) = entity.get("mapId") {
            body.push_str(&format!(",mapId={}", whole(map, 1, 2_147_483_647)?));
        }
        match (entity.get("x"), entity.get("y")) {
            (None, None) => {}
            (Some(x), Some(y)) if entity.get("mapId").is_some() => body.push_str(&format!(",x={},y={}", fraction(x)?, fraction(y)?)),
            _ => return None,
        }
        body.push_str("},\n");
    }
    Some(format!(
        "-- Written by Evertally Sync from the website's public facts. It is replaced after every sync; do not edit.\n\
         EvertallyCommunityData = {{\nschemaVersion=1,kind=\"evertally-community\",scope=\"world_facts\",generatedAt={generated},expiresAt={expires},\n\
         game={{product=\"forever\"}},\nprovenance={{source=\"community\",countingUnit=\"observations\",truncated={truncated},observationCount={observations},entityCount={entity_count}}},\n\
         entities={{\n{body}}},\n}}\n"
    ))
}

/// Fetches the package and writes it next to every installed addon. Returns how many addon folders changed.
///
/// # Errors
/// Network failures and packages that do not pass the checks.
pub fn sync(origin: &str, addons: &[std::path::PathBuf]) -> Result<usize> {
    ensure!(origin.starts_with("https://"), "community sync requires HTTPS");
    // The placeholder keeps the game from warning about a missing file even when the website cannot be reached.
    for addons_dir in addons {
        let target = addons_dir.join("Evertally").join(DATA_FILE);
        if !target.exists() {
            let _ = crate::forum::write_if_changed(&target, PLACEHOLDER);
        }
    }
    let agent: ureq::Agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(25))).max_redirects(0).build().into();
    let bytes = crate::addon_update::read_url(&agent, &format!("{origin}/api/community"), MAX_BYTES)?;
    let package: Value = serde_json::from_slice(&bytes)?;
    let text = data_file(&package).ok_or_else(|| anyhow::anyhow!("the website's community package did not pass the checks"))?;
    let mut changed = 0;
    for addons_dir in addons {
        let folder = addons_dir.join("Evertally");
        if folder.is_dir() && crate::forum::write_if_changed(&Path::new(&folder).join(DATA_FILE), &text)? {
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
        json!({"schemaVersion":1,"kind":"evertally-community","scope":"world_facts","generatedAt":1_794_603_121,"expiresAt":1_795_207_921,
            "game":{"product":"forever"},"provenance":{"source":"community","countingUnit":"observations","truncated":true,"observationCount":1880,"entityCount":627},
            "entities":[{"kind":"item","id":4888,"name":"Crawler Mucus","count":3,"lastSeen":1_794_603_049},
                        {"kind":"npc","id":706,"name":"Trollí \"jeskyně\"","count":2,"lastSeen":1_794_603_000,"mapId":1426,"x":0.5,"y":0.25}]})
    }

    #[test]
    fn a_good_package_becomes_data_only_lua() {
        let lua = data_file(&package()).expect("valid");
        assert!(lua.contains("EvertallyCommunityData = {"));
        let parsed = crate::savedvars::parse_assignment(&lua, "EvertallyCommunityData").expect("data only, no code");
        assert_eq!(parsed["entities"][0]["name"], "Crawler Mucus");
        assert_eq!(parsed["entities"][1]["name"], "Trollí \"jeskyně\"");
        assert_eq!(parsed["entities"][1]["x"], 0.5);
        assert_eq!(parsed["provenance"]["truncated"], true);
    }

    #[test]
    fn damaged_packages_are_never_written() {
        let mut cases = Vec::new();
        for (path, value) in [("schemaVersion", json!(2)), ("scope", json!("own_character")), ("kind", json!("other")), ("expiresAt", json!(1_794_603_121))] {
            let mut p = package(); p[path] = value; cases.push(p);
        }
        let mut p = package(); p["entities"][0]["name"] = json!("|Hplayer:x|h"); cases.push(p);
        let mut p = package(); p["entities"][0]["kind"] = json!("object"); cases.push(p);
        let mut p = package(); p["entities"][1]["x"] = json!(1.5); cases.push(p);
        let mut p = package(); p["entities"][1].as_object_mut().unwrap().remove("mapId"); cases.push(p);
        let mut p = package(); p["entities"][1]["id"] = json!(4888); p["entities"][1]["kind"] = json!("item"); cases.push(p);
        let mut p = package(); p["provenance"]["entityCount"] = json!(1); cases.push(p);
        let mut p = package(); p["extra"] = json!(1); let _ = &p; // unknown top-level keys are ignored, not copied
        assert!(!data_file(&p).unwrap().contains("extra"));
        for (i, case) in cases.iter().enumerate() {
            assert!(data_file(case).is_none(), "case {i} must be refused");
        }
    }

    /// Needs the network: `cargo test -- --ignored live_package`.
    #[test]
    #[ignore]
    fn live_package_is_fetched_checked_and_written() {
        let dir = std::env::temp_dir().join(format!("evertally-community-test-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("Evertally")).unwrap();
        let changed = sync("https://evertally.afstudio.dev", &[dir.clone()]).expect("the live package passes the checks");
        let text = std::fs::read_to_string(dir.join("Evertally").join(DATA_FILE)).unwrap();
        let parsed = crate::savedvars::parse_assignment(&text, "EvertallyCommunityData").expect("data only");
        assert_eq!(changed, 1);
        assert!(parsed["entities"].as_array().is_some_and(|e| !e.is_empty()));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_real_website_shape_is_accepted_for_every_entity_kind() {
        let mut p = package();
        p["entities"] = json!((1..=150).map(|i| json!({"kind":"quest","id":i,"name":format!("Quest {i}"),"count":1,"lastSeen":1_794_603_000})).collect::<Vec<_>>());
        p["provenance"]["entityCount"] = json!(150);
        assert!(data_file(&p).is_some());
    }
}
