//! Server acknowledgements for the addon's bounded outbox. SavedVariables stay read-only.
use std::{collections::BTreeMap, path::Path};
use anyhow::{Context, Result, ensure};
use serde_json::Value;
use crate::upload::UploadState;

const MARKER: &str = "-- Evertally upload acknowledgements: ";
const MAX_BYTES: usize = 2 * 1024 * 1024;
type Receipts = BTreeMap<String, Vec<String>>;

fn read(text: &str) -> Receipts {
    text.lines().find_map(|line| line.strip_prefix(MARKER))
        .and_then(|json| serde_json::from_str::<Receipts>(json).ok())
        .filter(|map| map.len() <= 128 && map.iter().all(|(source, ids)| source.len()<=200 && ids.len()<=6000 && ids.iter().all(|id|id.len()<=180)))
        .unwrap_or_default()
}

fn render(base: &str, receipts: &Receipts) -> Result<String> {
    let mut text=base.split_once(MARKER).map_or(base, |(before,_)|before).to_owned();
    if !text.ends_with('\n') { text.push('\n'); }
    text.push_str(MARKER);text.push_str(&serde_json::to_string(receipts)?);
    text.push_str("\nA.bridgeUploaded = {\n");
    for (source,ids) in receipts {
        text.push('[');crate::forum::lua_string(&mut text,source);text.push_str("]={");
        for id in ids {text.push('[');crate::forum::lua_string(&mut text,id);text.push_str("]=true,");}
        text.push_str("},\n");
    }
    text.push_str("}\n");
    ensure!(text.len()<=MAX_BYTES,"upload acknowledgement file exceeds its limit");
    Ok(text)
}

/// Preserve validated data when the existing installation proof is refreshed.
pub(crate) fn preserve(base: &str, previous: &str) -> Result<String> {
    let receipts=read(previous);
    if receipts.is_empty() {Ok(base.to_owned())} else {render(base,&receipts)}
}

pub(crate) fn write(saved_variables: &Path, envelope: &Value, state: &UploadState) -> Result<()> {
    let Some(producer)=envelope["producerId"].as_str() else {return Ok(())};
    let Some(epoch)=envelope["consentEpoch"].as_i64() else {return Ok(())};
    let source=format!("{producer}:{epoch}");
    let Some(events)=envelope["events"].as_array() else {return Ok(())};
    let ids:Vec<String>=events.iter().filter_map(|event|event["eventId"].as_str())
        .filter(|id|state.contains(&source,id)).map(str::to_owned).collect();
    if ids.is_empty() {return Ok(())}
    let Some(addon)=crate::forum::addon_folder(saved_variables) else {return Ok(())};
    let path=addon.join("BridgeInstallation.lua");
    if !path.is_file(){return Ok(())}
    crate::addon_update::safe_ancestors(&path)?;
    crate::addon_update::safe_ancestors(&path.with_extension("lua.tmp"))?;
    ensure!(std::fs::metadata(&path)?.len()<=MAX_BYTES as u64,"installation file exceeds its limit");
    let previous=std::fs::read_to_string(&path).context("read existing installation proof")?;
    let mut receipts=read(&previous);
    receipts.retain(|key,_|!key.starts_with(&format!("{producer}:")));
    receipts.insert(source,ids);
    crate::forum::write_if_changed(&path,&render(&previous,&receipts)?).context("write upload acknowledgement")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn receipts_survive_installation_refresh_as_data_only(){
        let receipts=BTreeMap::from([("source:1".into(),vec!["one".into(),"quote\"\n; do_not_run()".into()])]);
        let before=render("local _, A = ...\nA.bridgeInstallation={createdAt=1}\n",&receipts).unwrap();
        let after=preserve("local _, A = ...\nA.bridgeInstallation={createdAt=2}\n",&before).unwrap();
        assert_eq!(read(&after),receipts);assert!(after.contains("createdAt=2"));
        assert!(after.contains("[\"one\"]=true"));
        assert_eq!(after.matches("A.bridgeUploaded =").count(),1);
    }

    #[test]
    fn write_acknowledges_only_accepted_ids_and_never_changes_the_game_save(){
        let root=std::env::temp_dir().join(format!("evertally-upload-ack-{}-{}",std::process::id(),crate::bridge::now()));
        let saves=root.join("WTF/Account/fixture/SavedVariables");
        let addon=root.join("Interface/AddOns/Evertally");
        std::fs::create_dir_all(&saves).unwrap();std::fs::create_dir_all(&addon).unwrap();
        let game=saves.join(crate::wow::EXPORT_FILE);std::fs::write(&game,"original save").unwrap();
        let receipt=addon.join("BridgeInstallation.lua");std::fs::write(&receipt,"local _, A = ...\nA.bridgeInstallation={}\n").unwrap();
        let envelope=serde_json::json!({"producerId":"fixture","consentEpoch":1,"events":[{"eventId":"accepted"},{"eventId":"pending"}]});
        let mut state=UploadState::default();state.mark("fixture:1",["accepted".into()]);
        write(&saves,&envelope,&state).unwrap();
        assert_eq!(read(&std::fs::read_to_string(receipt).unwrap()),BTreeMap::from([("fixture:1".into(),vec!["accepted".into()])]));
        assert_eq!(std::fs::read_to_string(&game).unwrap(),"original save");
        assert!(root.starts_with(std::env::temp_dir())&&root.file_name().unwrap().to_string_lossy().starts_with("evertally-upload-ack-"));
        std::fs::remove_dir_all(root).unwrap();
    }
}
