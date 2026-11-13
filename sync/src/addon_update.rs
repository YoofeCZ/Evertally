//! Safe background installation of the published add-on bundle.
//! Downloads never use device credentials; WoW's live SavedVariables and the
//! generated ForumData.lua are outside the update payload.
use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::HashSet, fs, io::{Cursor, Read, Write}, path::{Component, Path, PathBuf}, time::{Duration, SystemTime, UNIX_EPOCH}};

const ROOTS: [&str; 3] = ["Evertally", "Evertally_Export", "Evertally_Map"];
const MAX_ARCHIVE: u64 = 32 * 1024 * 1024;
const MAX_TOTAL: u64 = 128 * 1024 * 1024;
const MAX_FILE: u64 = 16 * 1024 * 1024;
const MAX_ENTRIES: usize = 5000;

#[derive(Deserialize)]
struct Manifest { addon: Addon }
#[derive(Deserialize)]
struct Addon { file: String, bytes: u64, sha256: String }

#[derive(Serialize, Deserialize)]
struct Journal { staging: String, backup: String, existed: Vec<bool> }

struct FileEntry { relative: PathBuf, data: Vec<u8> }

pub(crate) fn read_url(agent: &ureq::Agent, url: &str, limit: u64) -> Result<Vec<u8>> {
    let mut response=agent.get(url).header("Cache-Control", "no-cache").call()?;
    ensure!(response.status().is_success(), "HTTP {}", response.status());
    let mut bytes=Vec::new();
    response.body_mut().as_reader().take(limit+1).read_to_end(&mut bytes)?;
    ensure!(bytes.len() as u64 <= limit, "download exceeds size limit");
    Ok(bytes)
}

fn safe_name(name: &str) -> Result<PathBuf> {
    ensure!(!name.is_empty() && !name.contains(['\\', ':']) && !name.starts_with('/'), "invalid archive path");
    let path=Path::new(name);
    ensure!(path.components().all(|c| matches!(c, Component::Normal(_))), "invalid archive path");
    let components: Vec<_>=name.split('/').collect();
    ensure!(components.len() >= 2 && ROOTS.contains(&components[0]), "unexpected archive root");
    for segment in &components {
        ensure!(!segment.is_empty() && !segment.ends_with([' ', '.']) && segment.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c,b'_'|b'-'|b'.')), "unsafe archive name");
        let reserved=segment.split('.').next().unwrap_or("").to_ascii_uppercase();
        ensure!(!matches!(reserved.as_str(), "CON"|"PRN"|"AUX"|"NUL"|"COM1"|"COM2"|"COM3"|"COM4"|"COM5"|"COM6"|"COM7"|"COM8"|"COM9"|"LPT1"|"LPT2"|"LPT3"|"LPT4"|"LPT5"|"LPT6"|"LPT7"|"LPT8"|"LPT9"), "reserved file name");
    }
    let ext=path.extension().and_then(|v|v.to_str()).unwrap_or("").to_ascii_lowercase();
    ensure!(["lua","toc","xml","md","txt","tga","blp"].contains(&ext.as_str()), "unexpected file type");
    Ok(path.to_path_buf())
}

fn unpack(bytes: &[u8]) -> Result<Vec<FileEntry>> {
    let mut zip=zip::ZipArchive::new(Cursor::new(bytes))?;
    ensure!(zip.len()<=MAX_ENTRIES, "too many files");
    let mut entries=Vec::new();let mut names=HashSet::new();let mut total=0u64;
    for index in 0..zip.len() {
        let mut file=zip.by_index(index)?;
        ensure!(!file.is_dir(), "unexpected directory entry");
        if let Some(mode)=file.unix_mode() { ensure!(mode & 0o170000 == 0 || mode & 0o170000 == 0o100000, "non-regular entry"); }
        let path=safe_name(file.name())?;
        let key=path.to_string_lossy().replace('\\',"/").to_ascii_lowercase();
        ensure!(names.insert(key.clone()), "duplicate archive path");
        ensure!(file.size()<=MAX_FILE, "file too large");total=total.checked_add(file.size()).context("archive overflow")?;
        ensure!(total<=MAX_TOTAL,"archive exceeds expanded size limit");
        let mut data=Vec::new();file.by_ref().take(MAX_FILE+1).read_to_end(&mut data)?;
        ensure!(data.len() as u64 == file.size(), "invalid archive file size");
        // Bridge-owned dynamic forum snapshot must never be replaced by the bundle.
        if key=="evertally/forumdata.lua" || key=="evertally/communitydata.lua" { continue; }
        entries.push(FileEntry{relative:path,data});
    }
    for root in ROOTS { ensure!(names.contains(&format!("{0}/{0}.toc",root.to_ascii_lowercase())), "missing addon manifest"); }
    Ok(entries)
}

fn safe_existing(path: &Path) -> Result<()> {
    let meta=fs::symlink_metadata(path)?;
    ensure!(!meta.file_type().is_symlink(), "symbolic link in addon path");
    #[cfg(windows)] { use std::os::windows::fs::MetadataExt; ensure!(meta.file_attributes() & 0x400 == 0, "reparse point in addon path"); }
    Ok(())
}

fn safe_ancestors(path: &Path) -> Result<()> {
    for parent in path.ancestors() { if parent.exists() { safe_existing(parent)?; } }
    Ok(())
}

fn copy_tree(from: &Path,to: &Path) -> Result<()> {
    safe_existing(from)?;fs::create_dir_all(to)?;
    for child in fs::read_dir(from)? {
        let child=child?;let path=child.path();safe_existing(&path)?;
        let dest=to.join(child.file_name());
        if child.file_type()?.is_dir(){copy_tree(&path,&dest)?;}
        else {ensure!(child.file_type()?.is_file(), "non-regular addon file");fs::copy(path,dest)?;}
    } Ok(())
}

fn matches_installed(addons: &Path, files: &[FileEntry]) -> bool {
    files.iter().all(|entry| {
        let path=addons.join(&entry.relative);
        safe_ancestors(&path).is_ok() && fs::metadata(&path).is_ok_and(|m|m.is_file() && m.len()==entry.data.len() as u64) && fs::read(path).is_ok_and(|b|b==entry.data)
    })
}

#[cfg(windows)]
fn game_running() -> Result<bool> {
    use windows_sys::Win32::{Foundation::{CloseHandle,INVALID_HANDLE_VALUE},System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot,Process32FirstW,Process32NextW,PROCESSENTRY32W,TH32CS_SNAPPROCESS}};
    unsafe {
        let snap=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
        ensure!(snap != INVALID_HANDLE_VALUE,"cannot inspect running games");
        let mut p:PROCESSENTRY32W=std::mem::zeroed();p.dwSize=std::mem::size_of::<PROCESSENTRY32W>() as u32;
        let mut ok=Process32FirstW(snap,&mut p);
        if ok==0 { CloseHandle(snap);bail!("cannot enumerate running games"); }
        let mut found=false;
        while ok!=0 { let end=p.szExeFile.iter().position(|c|*c==0).unwrap_or(p.szExeFile.len());let name=String::from_utf16_lossy(&p.szExeFile[..end]);
            if ["wow.exe","wowclassic.exe","wowclassicb.exe","wowclassicera.exe"].iter().any(|n| name.eq_ignore_ascii_case(n)){found=true;break;}
            ok=Process32NextW(snap,&mut p);
        }
        CloseHandle(snap);Ok(found)
    }
}
#[cfg(not(windows))] fn game_running()->Result<bool>{bail!("automatic installation supported on Windows only")}

pub(crate) fn roots(config: &crate::config::Config)->Vec<PathBuf>{
    let mut out=Vec::new();
    for root in crate::wow::candidate_roots(config.wow_path.as_deref()) {
        for flavor in [root.clone(),root.join("_forever_")] {
            let addons=flavor.join("Interface").join("AddOns");
            if addons.join("Evertally").join("Evertally.toc").is_file() && !out.contains(&addons) {out.push(addons)}
        }
    } out
}

fn restore(addons: &Path, work: &Path, journal: &Journal)->Result<()> {
    let backup=work.join(&journal.backup);let stage=work.join(&journal.staging);
    safe_ancestors(&backup)?;safe_ancestors(&stage)?;
    for (i,root) in ROOTS.iter().enumerate().rev() {
        let live=addons.join(root);let old=backup.join(root);let staged=stage.join(root);
        if old.exists() {
            if live.exists() {safe_existing(&live)?;fs::rename(&live,backup.join(format!("failed-{root}")))?;}
            safe_ancestors(&old)?;fs::rename(old,live)?;
        } else if !journal.existed[i] && !staged.exists() && live.exists() {
            safe_existing(&live)?;fs::rename(live,backup.join(format!("failed-{root}")))?;
        }
    }
    fs::remove_file(work.join("journal.json"))?;Ok(())
}

fn recover(addons: &Path, work: &Path)->Result<()> {
    let path=work.join("journal.json");if !path.exists(){return Ok(());}
    safe_ancestors(&path)?;
    let journal:Journal=serde_json::from_slice(&fs::read(path)?)?;
    ensure!(journal.existed.len()==ROOTS.len() && journal.backup.starts_with("backup-") && journal.staging.starts_with("stage-") && !journal.backup.contains(['/', '\\', ':']) && !journal.staging.contains(['/', '\\', ':']),"invalid update journal");
    restore(addons,work,&journal)
}

fn install_with_game_check(addons: &Path, files: &[FileEntry], forum_lock: &std::sync::Mutex<()>, game: impl Fn()->Result<bool>) -> Result<bool> {
    safe_ancestors(addons)?;
    let work=addons.parent().context("invalid addons directory")?.join("EvertallyUpdateBackups");
    if work.exists(){safe_ancestors(&work)?;} else {fs::create_dir(&work)?;}
    if !work.join("journal.json").exists() && matches_installed(addons,files) {return Ok(true);}
    if game()? { return Ok(false); }
    let _guard=forum_lock.lock().map_err(|_|anyhow::anyhow!("forum lock unavailable"))?;
    recover(addons,&work)?;
    if matches_installed(addons,files){return Ok(true);}
    let id=SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let journal=Journal{staging:format!("stage-{id}"),backup:format!("backup-{id}"),existed:ROOTS.iter().map(|r|addons.join(r).exists()).collect()};
    let stage=work.join(&journal.staging);let backup=work.join(&journal.backup);
    fs::create_dir(&stage)?;fs::create_dir(&backup)?;
    for root in ROOTS {let live=addons.join(root);let target=stage.join(root);if live.exists(){copy_tree(&live,&target)?;}else{fs::create_dir(&target)?;}}
    for entry in files {let target=stage.join(&entry.relative);fs::create_dir_all(target.parent().context("invalid file")?)?;fs::write(target,&entry.data)?;}
    // Game might have launched while staging; no live file has been changed yet.
    if game()? {return Ok(false);}
    let j=work.join("journal.json");let mut f=fs::File::create(&j)?;serde_json::to_writer(&mut f,&journal)?;f.flush()?;f.sync_all()?;
    let result=(||->Result<()> {for root in ROOTS {ensure!(!game()?,"game started during update");let live=addons.join(root);if live.exists(){fs::rename(&live,backup.join(root))?;}fs::rename(stage.join(root),live)?;}Ok(())})();
    if let Err(err)=result {restore(addons,&work,&journal).context("rollback failed")?;return Err(err);}
    fs::remove_file(j)?;
    Ok(true)
}

fn install(addons: &Path, files: &[FileEntry], forum_lock: &std::sync::Mutex<()>) -> Result<bool> {
    install_with_game_check(addons,files,forum_lock,game_running)
}

fn valid_bundle(data: &[u8], addon: &Addon)->bool {
    data.len() as u64==addon.bytes && format!("{:x}",Sha256::digest(data)).eq_ignore_ascii_case(&addon.sha256)
}

/// Keep one verified bundle in memory so a running game does not redownload it each poll.
pub struct Updater { cached: Option<(String, Vec<FileEntry>)>, cache_file: PathBuf, pending: HashSet<PathBuf> }

impl Updater {
#[must_use] pub fn new(cache_dir: &Path)->Self {Self{cached:None,cache_file:cache_dir.join("addon-update-cache.zip"),pending:HashSet::new()}}
/// One cycle. No game data is touched; only already-installed Evertally trees are updated.
pub fn check(&mut self, config: &crate::config::Config, forum_lock: &std::sync::Mutex<()>) -> Result<Option<bool>> {
    let addons=roots(config);if addons.is_empty(){return Ok(None);}
    let origin=config.server_origin()?;ensure!(origin.starts_with("https://"),"automatic updates require HTTPS");
    let agent:ureq::Agent=ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(25))).max_redirects(0).build().into();
    let manifest:Manifest=serde_json::from_slice(&read_url(&agent,&format!("{origin}/downloads/manifest.json"),65536)?)?;
    ensure!(manifest.addon.file=="Evertally.zip" && manifest.addon.bytes>0 && manifest.addon.bytes<=MAX_ARCHIVE && manifest.addon.sha256.len()==64 && manifest.addon.sha256.bytes().all(|b|b.is_ascii_hexdigit()),"invalid addon manifest");
    if self.cached.as_ref().is_none_or(|(hash,_)| !hash.eq_ignore_ascii_case(&manifest.addon.sha256)) {
        self.pending.clear();
        let valid=|data:&[u8]| valid_bundle(data,&manifest.addon);
        let cache=fs::symlink_metadata(&self.cache_file).ok().filter(|m|m.is_file() && m.len()<=MAX_ARCHIVE)
            .and_then(|_|fs::read(&self.cache_file).ok()).filter(|data|valid(data));
        let data=match cache {
            Some(data)=>data,
            None=>{
                let data=read_url(&agent,&format!("{origin}/downloads/Evertally.zip"),MAX_ARCHIVE)?;
                ensure!(valid(&data),"archive checksum mismatch");
                let temp=self.cache_file.with_extension("zip.tmp");
                if fs::write(&temp,&data).is_ok() {let _=fs::remove_file(&self.cache_file);let _=fs::rename(temp,&self.cache_file);}
                data
            }
        };
        ensure!(data.len() as u64==manifest.addon.bytes,"archive size mismatch");
        ensure!(format!("{:x}",Sha256::digest(&data)).eq_ignore_ascii_case(&manifest.addon.sha256),"archive checksum mismatch");
        self.cached=Some((manifest.addon.sha256,unpack(&data)?));
    }
    let files=&self.cached.as_ref().context("missing verified bundle")?.1;
    let mut ready=true;
    for dir in addons {
        if self.pending.contains(&dir) && game_running()? {ready=false;continue;}
        if install(&dir,files,forum_lock)? {self.pending.remove(&dir);}else{self.pending.insert(dir);ready=false;}
    }
    Ok(Some(ready))
}
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    struct Scratch(PathBuf);
    impl Scratch {
        fn new()->Self {let path=std::env::temp_dir().join(format!("evertally-addon-update-test-{}-{}",std::process::id(),SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()));fs::create_dir_all(path.join("Interface/AddOns/Evertally")).unwrap();Self(path)}
        fn addons(&self)->PathBuf {self.0.join("Interface/AddOns")}
    }
    impl Drop for Scratch {fn drop(&mut self){if self.0.starts_with(std::env::temp_dir()) && self.0.file_name().is_some_and(|n|n.to_string_lossy().starts_with("evertally-addon-update-test-")){let _=fs::remove_dir_all(&self.0);}}}
    fn fixture()->(Scratch,Vec<FileEntry>){
        let dir=Scratch::new();let addons=dir.addons();
        for r in ROOTS {let d=addons.join(r);fs::create_dir_all(&d).unwrap();fs::write(d.join(format!("{r}.toc")),"old").unwrap();}
        fs::write(addons.join("Evertally/ForumData.lua"),"user-forum").unwrap();
        fs::write(addons.join("Evertally/personal.txt"),"user-file").unwrap();
        let entries=ROOTS.iter().map(|r|FileEntry{relative:PathBuf::from(r).join(format!("{r}.toc")),data:b"new".to_vec()}).collect();
        (dir,entries)
    }
    #[test] fn rejects_path_traversal_and_non_addon_files(){
        for bad in ["../Evertally/x.lua","Evertally/../x.lua","Evertally\\x.lua","Evertally/x.lua:stream","Evertally/CON.lua","Other/x.lua","Evertally/x.exe","Evertally/a./x.lua"] {assert!(safe_name(bad).is_err(),"{bad}");}
        assert!(safe_name("Evertally_Map/Roads/Nav/Nav0.lua").is_ok());
    }
    #[test] fn rejects_duplicate_case_and_never_installs_forum_snapshot(){
        let mut data=Cursor::new(Vec::new());{
            let mut w=zip::ZipWriter::new(&mut data);let opts=zip::write::SimpleFileOptions::default();
            for r in ROOTS {w.start_file(format!("{r}/{r}.toc"),opts).unwrap();w.write_all(b"toc").unwrap();}
            w.start_file("Evertally/ForumData.lua",opts).unwrap();w.write_all(b"replacement").unwrap();w.finish().unwrap();
        }
        let out=unpack(&data.into_inner()).unwrap();assert_eq!(out.len(),3);
    }
    #[test] fn rejects_case_insensitive_duplicates(){
        let mut data=Cursor::new(Vec::new());{
            let mut w=zip::ZipWriter::new(&mut data);let opts=zip::write::SimpleFileOptions::default();
            for r in ROOTS {w.start_file(format!("{r}/{r}.toc"),opts).unwrap();w.write_all(b"toc").unwrap();}
            w.start_file("Evertally/A.lua",opts).unwrap();w.write_all(b"one").unwrap();
            w.start_file("Evertally/a.lua",opts).unwrap();w.write_all(b"two").unwrap();w.finish().unwrap();
        }
        assert!(unpack(&data.into_inner()).is_err());
    }
    #[test] fn published_bundle_is_accepted_and_forum_is_skipped(){
        let path=Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("releases/Evertally.zip");
        if !path.exists(){return;}
        let entries=unpack(&fs::read(path).unwrap()).unwrap();
        assert!(entries.len()>20);
        assert!(!entries.iter().any(|entry|entry.relative.to_string_lossy().replace('\\',"/").eq_ignore_ascii_case("Evertally/ForumData.lua")));
    }
    #[test] fn checksum_and_size_are_verified(){
        let data=b"verified";let addon=Addon{file:"Evertally.zip".into(),bytes:data.len() as u64,sha256:format!("{:x}",Sha256::digest(data))};
        assert!(valid_bundle(data,&addon));assert!(!valid_bundle(b"tampered",&addon));
        let mut wrong=addon;wrong.bytes+=1;assert!(!valid_bundle(data,&wrong));
    }
    #[test] fn install_preserves_forum_and_unknown_files_and_backups(){
        let (dir,files)=fixture();let lock=std::sync::Mutex::new(());
        assert!(install_with_game_check(&dir.addons(),&files,&lock,||Ok(false)).unwrap());
        for r in ROOTS {assert_eq!(fs::read(dir.addons().join(r).join(format!("{r}.toc"))).unwrap(),b"new");}
        assert_eq!(fs::read(dir.addons().join("Evertally/ForumData.lua")).unwrap(),b"user-forum");
        assert_eq!(fs::read(dir.addons().join("Evertally/personal.txt")).unwrap(),b"user-file");
        let work=dir.0.join("Interface/EvertallyUpdateBackups");
        let backup=fs::read_dir(&work).unwrap().flatten().find(|d|d.file_name().to_string_lossy().starts_with("backup-")).unwrap();
        assert_eq!(fs::read(backup.path().join("Evertally/Evertally.toc")).unwrap(),b"old");
        assert!(!work.join("journal.json").exists());
    }
    #[test] fn leaves_existing_installation_unchanged_while_game_runs(){
        let (dir,files)=fixture();let lock=std::sync::Mutex::new(());
        assert!(!install_with_game_check(&dir.addons(),&files,&lock,||Ok(true)).unwrap());
        assert_eq!(fs::read(dir.addons().join("Evertally/Evertally.toc")).unwrap(),b"old");
    }
    #[test] fn rollback_restores_all_roots_when_game_starts_mid_swap(){
        let (dir,files)=fixture();let lock=std::sync::Mutex::new(());let checks=Cell::new(0);
        let result=install_with_game_check(&dir.addons(),&files,&lock,||{checks.set(checks.get()+1);Ok(checks.get()>=4)});
        assert!(result.is_err());
        for r in ROOTS {assert_eq!(fs::read(dir.addons().join(r).join(format!("{r}.toc"))).unwrap(),b"old");}
        assert_eq!(fs::read(dir.addons().join("Evertally/ForumData.lua")).unwrap(),b"user-forum");
        assert!(!dir.0.join("Interface/EvertallyUpdateBackups/journal.json").exists());
    }
    #[test] fn recovers_interrupted_swap_before_starting_another(){
        let (dir,_)=fixture();let addons=dir.addons();let work=dir.0.join("Interface/EvertallyUpdateBackups");
        let journal=Journal{staging:"stage-crash".into(),backup:"backup-crash".into(),existed:vec![true;3]};
        fs::create_dir_all(work.join("backup-crash")).unwrap();fs::create_dir_all(work.join("stage-crash")).unwrap();
        fs::rename(addons.join("Evertally"),work.join("backup-crash/Evertally")).unwrap();
        fs::create_dir(addons.join("Evertally")).unwrap();fs::write(addons.join("Evertally/Evertally.toc"),"half-installed").unwrap();
        fs::write(work.join("journal.json"),serde_json::to_vec(&journal).unwrap()).unwrap();
        recover(&addons,&work).unwrap();
        assert_eq!(fs::read(addons.join("Evertally/Evertally.toc")).unwrap(),b"old");
        assert_eq!(fs::read(addons.join("Evertally/ForumData.lua")).unwrap(),b"user-forum");
        assert!(!work.join("journal.json").exists());
    }
    #[test] fn rejects_existing_symlink_when_supported(){
        let (dir,files)=fixture();let link=dir.addons().join("Evertally/linked");
        #[cfg(windows)] let made=std::os::windows::fs::symlink_dir(dir.0.join("Interface"),&link);
        #[cfg(unix)] let made=std::os::unix::fs::symlink(dir.0.join("Interface"),&link);
        #[cfg(not(any(unix,windows)))] let made=Err(std::io::Error::other("unsupported"));
        if let Err(err)=made {eprintln!("Symlink test skipped: {err}");return;}
        let lock=std::sync::Mutex::new(());assert!(install_with_game_check(&dir.addons(),&files,&lock,||Ok(false)).is_err());let _=fs::remove_dir(&link);
    }
    #[test] #[ignore = "read-only integration check against the public distribution server"]
    fn public_manifest_and_archive_verify_and_unpack(){
        let agent:ureq::Agent=ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(25))).max_redirects(0).build().into();
        let manifest:Manifest=serde_json::from_slice(&read_url(&agent,"https://evertally.afstudio.dev/downloads/manifest.json",65536).unwrap()).unwrap();
        let data=read_url(&agent,"https://evertally.afstudio.dev/downloads/Evertally.zip",MAX_ARCHIVE).unwrap();
        assert!(valid_bundle(&data,&manifest.addon));let entries=unpack(&data).unwrap();assert!(entries.len()>20);
    }
}
