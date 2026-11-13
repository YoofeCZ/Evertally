//! The forum of the in-game Community page.
//!
//! Two directions, both through files the game itself reads and writes:
//! * game -> web: what the player wrote in game waits in `EvertallyDB.forum.outbox` (`Evertally.lua`, saved by the game on
//!   `/reload` or logout). Only that list is read and sent; the rest of the history stays local.
//! * web -> game: the current forum is written to `Interface/AddOns/Evertally/ForumData.lua`, which the game loads at login
//!   or `/reload`. The addon validates it again; this file only ever contains data, never code.

use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::{local, savedvars};

/// Name of the data file inside the addon folder (listed in the addon's TOC).
pub const DATA_FILE: &str = "ForumData.lua";
const MAX_OUTBOX: usize = 160;
const MAX_THREADS: usize = 60;
const MAX_POSTS: usize = 30;
const MAX_FILE_BYTES: usize = 900_000;
const CATEGORIES: [&str; 6] = [
    "general",
    "dungeons",
    "professions",
    "trading",
    "guilds",
    "feedback",
];

fn valid_id(value: &str) -> bool {
    (8..=40).contains(&value.len())
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn id_of(entry: &Value, key: &str) -> Option<String> {
    entry
        .get(key)?
        .as_str()
        .filter(|id| valid_id(id))
        .map(str::to_owned)
}

fn text_of(entry: &Value, key: &str, max_chars: usize) -> Option<String> {
    let text = entry.get(key)?.as_str()?;
    let cut: String = text.chars().take(max_chars).collect();
    (!cut.trim().is_empty()).then_some(cut)
}

fn int_of(entry: &Value, key: &str, low: i64, high: i64) -> Option<i64> {
    let number = entry.get(key)?.as_f64()?;
    #[allow(clippy::cast_possible_truncation)]
    let whole = number.floor() as i64;
    (number.is_finite() && (low..=high).contains(&whole)).then_some(whole)
}

/// One outbox entry as the server accepts it, or `None` when the entry is damaged. The server checks everything again.
fn outbox_entry(entry: &Value) -> Option<Value> {
    let kind = entry.get("kind")?.as_str()?;
    let mut out = Map::new();
    out.insert("kind".into(), kind.into());
    out.insert("id".into(), id_of(entry, "id")?.into());
    out.insert("body".into(), text_of(entry, "body", 4000)?.into());
    out.insert("author".into(), text_of(entry, "author", 200)?.into());
    out.insert(
        "createdAt".into(),
        int_of(entry, "createdAt", 0, 253_402_300_799)?.into(),
    );
    if let Some(class) = int_of(entry, "classId", 1, 100) {
        out.insert("classId".into(), class.into());
    }
    match kind {
        "thread" => {
            let category = entry.get("category")?.as_str()?;
            if !CATEGORIES.contains(&category) {
                return None;
            }
            out.insert("category".into(), category.into());
            out.insert("title".into(), text_of(entry, "title", 400)?.into());
        }
        "post" => {
            out.insert("threadId".into(), id_of(entry, "threadId")?.into());
            if let Some(reply) = id_of(entry, "replyTo") {
                out.insert("replyTo".into(), reply.into());
            }
        }
        _ => return None,
    }
    Some(Value::Object(out))
}

/// What the player wrote in game and the server may not have yet, from one `SavedVariables` folder.
#[must_use]
pub fn read_outbox(saved_variables: &Path) -> Vec<Value> {
    let file = saved_variables.join(local::DB_FILE);
    if !file.is_file() {
        return Vec::new();
    }
    let Ok(text) = local::read_history(&file) else {
        return Vec::new();
    };
    let Ok(vars) = savedvars::parse_assignments(&text, &["EvertallyDB", "EvertallyPeersDB"]) else {
        return Vec::new();
    };
    vars.get("EvertallyDB")
        .and_then(|db| db.pointer("/forum/outbox"))
        .and_then(Value::as_array)
        .map(|list| {
            list.iter()
                .filter_map(outbox_entry)
                .take(MAX_OUTBOX)
                .collect()
        })
        .unwrap_or_default()
}

/// Outbox entries of several folders (one game, several accounts), each id once.
#[must_use]
pub fn read_outboxes(folders: &[PathBuf]) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    let mut all = Vec::new();
    for folder in folders {
        for entry in read_outbox(folder) {
            if let Some(id) = entry["id"].as_str()
                && seen.insert(id.to_owned())
            {
                all.push(entry);
            }
        }
    }
    all.truncate(MAX_OUTBOX);
    all
}

/// `<flavor>/Interface/AddOns/Evertally` for a `<flavor>/WTF/Account/<account>/SavedVariables` folder, if the addon is installed there.
#[must_use]
pub fn addon_folder(saved_variables: &Path) -> Option<PathBuf> {
    let flavor = saved_variables.parent()?.parent()?.parent()?.parent()?;
    let folder = flavor.join("Interface").join("AddOns").join("Evertally");
    folder.is_dir().then_some(folder)
}

fn lua_string(out: &mut String, value: &str) {
    out.push('"');
    for ch in value.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            c if (c as u32) < 32 || c as u32 == 127 => {
                out.push_str(&format!("\\{:03}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn field_str(out: &mut String, name: &str, value: &str) {
    out.push_str(name);
    out.push('=');
    lua_string(out, value);
    out.push(',');
}

fn field_num(out: &mut String, name: &str, value: i64) {
    out.push_str(&format!("{name}={value},"));
}

fn post_lua(post: &Value) -> Option<String> {
    let mut out = String::from("{");
    field_str(&mut out, "id", &id_of(post, "id")?);
    field_str(&mut out, "author", &text_of(post, "author", 80)?);
    field_str(&mut out, "body", &text_of(post, "body", 800)?);
    field_num(&mut out, "createdAt", int_of(post, "createdAt", 0, 253_402_300_799)?);
    field_str(
        &mut out,
        "origin",
        if post["origin"] == "game" { "game" } else { "web" },
    );
    if let Some(class) = int_of(post, "classId", 1, 100) {
        field_num(&mut out, "classId", class);
    }
    if let Some(reply) = id_of(post, "replyTo") {
        field_str(&mut out, "replyTo", &reply);
    }
    out.push('}');
    Some(out)
}

fn thread_lua(thread: &Value) -> Option<String> {
    let category = thread.get("category")?.as_str()?;
    if !CATEGORIES.contains(&category) {
        return None;
    }
    let posts: Vec<String> = thread
        .get("posts")?
        .as_array()?
        .iter()
        .filter_map(post_lua)
        .take(MAX_POSTS)
        .collect();
    if posts.is_empty() {
        return None;
    }
    let mut out = String::from("{");
    field_str(&mut out, "id", &id_of(thread, "id")?);
    field_str(&mut out, "category", category);
    field_str(&mut out, "title", &text_of(thread, "title", 80)?);
    field_str(&mut out, "author", &text_of(thread, "author", 80)?);
    field_str(
        &mut out,
        "origin",
        if thread["origin"] == "game" { "game" } else { "web" },
    );
    if let Some(class) = int_of(thread, "classId", 1, 100) {
        field_num(&mut out, "classId", class);
    }
    out.push_str(if thread["pinned"] == true {
        "pinned=true,"
    } else {
        "pinned=false,"
    });
    field_num(&mut out, "createdAt", int_of(thread, "createdAt", 0, 253_402_300_799)?);
    field_num(&mut out, "lastPostAt", int_of(thread, "lastPostAt", 0, 253_402_300_799)?);
    field_num(&mut out, "replies", int_of(thread, "replies", 0, 1_000_000).unwrap_or(0));
    out.push_str("posts={");
    out.push_str(&posts.join(","));
    out.push_str("}}");
    Some(out)
}

/// The Lua data file for the server's answer (`generatedAt` and `threads`). Anything that does not look like a forum is left out.
#[must_use]
pub fn data_file(answer: &Value) -> String {
    let generated = int_of(answer, "generatedAt", 0, 253_402_300_799).unwrap_or(0);
    let mut body = String::new();
    let mut count = 0;
    for thread in answer
        .get("threads")
        .and_then(Value::as_array)
        .map_or(&[][..], Vec::as_slice)
        .iter()
        .take(MAX_THREADS)
    {
        let Some(item) = thread_lua(thread) else {
            continue;
        };
        if body.len() + item.len() > MAX_FILE_BYTES {
            break;
        }
        body.push_str(&item);
        body.push_str(",\n");
        count += 1;
    }
    format!(
        "-- Written by Evertally Sync from the website forum. It is replaced after every sync; do not edit.\n\
         EvertallyForumData = {{\nschemaVersion=1,generatedAt={generated},count={count},\nthreads={{\n{body}}},\n}}\n"
    )
}

/// Writes `text` unless the file already has exactly this content. Returns whether the file changed.
///
/// # Errors
/// The file or its temporary copy cannot be written.
pub fn write_if_changed(path: &Path, text: &str) -> std::io::Result<bool> {
    if std::fs::read(path).is_ok_and(|old| old == text.as_bytes()) {
        return Ok(false);
    }
    let temp = path.with_extension("lua.tmp");
    std::fs::write(&temp, text)?;
    std::fs::rename(&temp, path)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("evertally-forum-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn data_file_is_data_only_escapes_text_and_drops_damaged_threads() {
        let answer = json!({
            "generatedAt": 1_794_236_400,
            "threads": [
                {"id":"wabcdef012345","category":"general","title":"Kde je \"Defias\"?","author":"Aria-Fixture Realm","origin":"web","classId":8,"pinned":false,
                 "createdAt":1,"lastPostAt":2,"replies":1,"posts":[
                    {"id":"wabcdef012345","author":"Aria-Fixture Realm","body":"řádek 1\nřádek 2 \\ ]] |cffff0000","createdAt":1,"origin":"web","classId":8},
                    {"id":"gpost00112233","author":"Bran-Realm","body":"odpověď","createdAt":2,"origin":"game","replyTo":"wabcdef012345"}]},
                {"id":"x","category":"general","title":"bad id","author":"A","createdAt":1,"lastPostAt":1,"posts":[]},
                {"id":"wabcdef099999","category":"politics","title":"bad category","author":"A","createdAt":1,"lastPostAt":1,"posts":[{"id":"wabcdef099999","author":"A","body":"b","createdAt":1}]},
                "not an object"
            ]
        });
        let lua = data_file(&answer);
        assert!(lua.starts_with("-- Written by Evertally Sync"));
        assert!(lua.contains("EvertallyForumData = {"));
        assert!(lua.contains("count=1,"));
        assert!(lua.contains(r#"title="Kde je \"Defias\"?""#));
        assert!(lua.contains(r#"body="řádek 1\nřádek 2 \\ ]] |cffff0000""#));
        assert!(lua.contains(r#"replyTo="wabcdef012345""#));
        assert!(!lua.contains("bad id") && !lua.contains("bad category"));
        // the file must read back through the data-only parser: no code, only a table
        let parsed = savedvars::parse_assignment(&lua, "EvertallyForumData").expect("data only");
        assert_eq!(parsed["threads"][0]["posts"][0]["body"], "řádek 1\nřádek 2 \\ ]] |cffff0000");
        assert_eq!(parsed["threads"][0]["posts"][1]["origin"], "game");
        assert_eq!(parsed["count"], 1);
    }

    #[test]
    fn control_characters_cannot_break_out_of_a_string() {
        let mut out = String::new();
        lua_string(&mut out, "a\u{0}b\u{7f}\"\r\\");
        assert_eq!(out, r#""a\000b\127\"\r\\""#);
    }

    #[test]
    fn empty_answer_is_a_valid_empty_forum() {
        let lua = data_file(&json!({}));
        let parsed = savedvars::parse_assignment(&lua, "EvertallyForumData").unwrap();
        assert_eq!(parsed["count"], 0);
    }

    #[test]
    fn outbox_keeps_only_well_formed_entries_and_known_fields() {
        let dir = temp("outbox");
        std::fs::write(
            dir.join(local::DB_FILE),
            r#"EvertallyDB = {
              ["schemaVersion"]=1, ["events"]={}, ["runs"]={}, ["settings"]={},
              ["forum"]={["outbox"]={
                {["kind"]="thread",["id"]="gabc12345678",["category"]="dungeons",["title"]="Deadmines",["body"]="Kdo jde?",["author"]="Hero-Fixture Realm",["classId"]=7,["createdAt"]=1794236400,["secret"]="x"},
                {["kind"]="post",["id"]="gpost1234567",["threadId"]="gabc12345678",["replyTo"]="gabc12345678",["body"]="Já.",["author"]="Hero-Fixture Realm",["createdAt"]=1794236460},
                {["kind"]="post",["id"]="bad",["threadId"]="gabc12345678",["body"]="x",["author"]="A",["createdAt"]=1},
                {["kind"]="thread",["id"]="gabc99999999",["category"]="nope",["title"]="x",["body"]="x",["author"]="A",["createdAt"]=1},
                {["kind"]="admin",["id"]="gabc00000000",["body"]="x",["author"]="A",["createdAt"]=1}
              }}
            }
            EvertallyPeersDB = {}"#,
        )
        .unwrap();
        let out = read_outbox(&dir);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0]["category"], "dungeons");
        assert!(out[0].get("secret").is_none());
        assert_eq!(out[1]["threadId"], "gabc12345678");
        // the same folder twice sends every entry once
        assert_eq!(read_outboxes(&[dir.clone(), dir.clone()]).len(), 2);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn missing_or_unreadable_history_means_an_empty_outbox() {
        let dir = temp("empty");
        assert!(read_outbox(&dir).is_empty());
        std::fs::write(dir.join(local::DB_FILE), "EvertallyDB = {").unwrap();
        assert!(read_outbox(&dir).is_empty());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn data_file_is_found_next_to_the_installed_addon_and_rewritten_only_when_it_changes() {
        let root = temp("addon");
        let saved = root.join("_forever_/WTF/Account/ACC/SavedVariables");
        std::fs::create_dir_all(&saved).unwrap();
        assert!(addon_folder(&saved).is_none());
        let addon = root.join("_forever_/Interface/AddOns/Evertally");
        std::fs::create_dir_all(&addon).unwrap();
        assert_eq!(addon_folder(&saved), Some(addon.clone()));
        let path = addon.join(DATA_FILE);
        assert!(write_if_changed(&path, "a").unwrap());
        assert!(!write_if_changed(&path, "a").unwrap());
        assert!(write_if_changed(&path, "b").unwrap());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "b");
        std::fs::remove_dir_all(root).unwrap();
    }
}
