//! Explicit downloads of public aggregates. Never sends saved game data or credentials.
use std::{path::PathBuf, sync::mpsc::{self, Receiver}, time::Duration};
use eframe::egui::{self, RichText};
use serde::{Deserialize, Serialize};
use crate::{identity::Icons, model};

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all="camelCase")]
pub struct ActivityZone { pub map_id:u64,pub contributors:u64,pub observations:u64 }

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all="camelCase")]
pub struct Activity {pub window_hours:u64,pub min_contributors:u64,pub generated_at:u64,pub zones:Vec<ActivityZone>}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all="camelCase")]
struct Character {name:Option<String>,realm:Option<String>,class_id:Option<u64>,race_id:Option<u64>,level:Option<u64>}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
struct Entry {rank:u64,count:u64,character:Character}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all="camelCase")]
struct Leaderboard {entries:Vec<Entry>,#[serde(default)] sample_size:u64,#[serde(default)] rules_label:String}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
struct Cache {origin:String,activity:Activity,leaderboard:Leaderboard}

pub struct PublicData {
    cache:Cache,path:PathBuf,rx:Option<Receiver<Result<Cache,String>>>,error:Option<String>,allow_network:bool,query:String,
}

impl PublicData {
    pub fn new(dir:PathBuf,origin:String,allow_network:bool)->Self{
        let path=dir.join("public-community-cache.json");
        let cache=std::fs::metadata(&path).ok().filter(|m|m.len()<=2*1024*1024).and_then(|_|std::fs::read(&path).ok()).and_then(|bytes|serde_json::from_slice::<Cache>(&bytes).ok()).filter(|cache|cache.origin==origin).unwrap_or_else(||Cache{origin,..Cache::default()});
        Self{cache,path,rx:None,error:None,allow_network,query:String::new()}
    }

    pub fn poll(&mut self){
        if let Some(result)=self.rx.as_ref().and_then(|rx|rx.try_recv().ok()) {
            self.rx=None;
            match result {Ok(cache)=>{self.cache=cache;self.error=None;if let Ok(bytes)=serde_json::to_vec(&self.cache){let _=std::fs::write(&self.path,bytes);}},Err(error)=>self.error=Some(error)}
        }
    }

    pub fn controls(&mut self,ui:&mut egui::Ui,origin:&str,cs:bool){
        let t=|en,cz|if cs{cz}else{en};
        ui.horizontal_wrapped(|ui|{
            if ui.add_enabled(self.allow_network&&self.rx.is_none(),egui::Button::new(t("Refresh public community data","Načíst veřejná komunitní data"))).clicked(){
                let (tx,rx)=mpsc::channel();self.rx=Some(rx);self.error=None;
                let origin=origin.to_owned();let ctx=ui.ctx().clone();
                std::thread::spawn(move||{let result=download(origin);let _=tx.send(result);ctx.request_repaint();});
            }
            if self.rx.is_some(){ui.spinner();ui.label(t("Downloading public aggregates…","Načítám veřejné souhrny…"));}
            if self.cache.activity.generated_at>0{ui.weak(format!("{} {}",t("Cached","Uloženo"),model::timestamp(Some(self.cache.activity.generated_at as f64))));}
        });
        if let Some(error)=&self.error{ui.colored_label(egui::Color32::from_rgb(234,179,138),format!("{} {error}",t("Download failed; retaining the previous cache.","Načtení selhalo; zůstává předchozí cache.")));}
    }

    pub fn activity(&self)->&Activity {&self.cache.activity}

    pub fn rankings(&mut self,ui:&mut egui::Ui,origin:&str,icons:&Icons,cs:bool){
        let t=|en,cz|if cs{cz}else{en};
        self.controls(ui,origin,cs);
        ui.add_space(12.0);
        ui.label(t("Shared completed-run participations","Sdílené účasti v dokončených výpravách"));
        ui.weak(t("Count rankings from voluntary public profiles. Several characters can report the same group run. Verified speed rankings are not available.","Žebříček počtů z dobrovolně veřejných profilů. Jeden skupinový běh může nahlásit více postav. Ověřené rychlostní rekordy zatím nejsou dostupné."));
        ui.add(egui::TextEdit::singleline(&mut self.query).hint_text(t("Character, class or race…","Postava, classa nebo rasa…")).desired_width(f32::INFINITY));
        if self.cache.leaderboard.entries.is_empty(){ui.add_space(14.0);ui.heading(t("No public ranking entries yet","Veřejný žebříček zatím nemá záznamy"));return;}
        for entry in &self.cache.leaderboard.entries {
            let label=format!("{} {} {}",entry.character.name.as_deref().unwrap_or(""),model::class_name(entry.character.class_id),model::race_name(entry.character.race_id));
            if !self.query.trim().is_empty()&&!label.to_lowercase().contains(&self.query.to_lowercase()){continue;}
            egui::Frame::new().fill(egui::Color32::from_rgb(28,26,40)).corner_radius(7).inner_margin(12).show(ui,|ui|{
                ui.horizontal(|ui|{
                    ui.label(RichText::new(format!("#{}",entry.rank)).size(20.0));
                    icons.show(ui,"classes",entry.character.class_id,32.0,model::class_name(entry.character.class_id));
                    icons.show(ui,"races",entry.character.race_id,30.0,model::race_name(entry.character.race_id));
                    ui.vertical(|ui|{ui.label(RichText::new(entry.character.name.as_deref().unwrap_or(t("Public character","Veřejná postava"))).strong());ui.weak(format!("{} · {}",entry.character.realm.as_deref().unwrap_or("—"),model::class_name(entry.character.class_id)));});
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center),|ui|{ui.label(RichText::new(entry.count.to_string()).size(24.0).monospace());});
                });
            });
            ui.add_space(6.0);
        }
    }
}

fn download(origin:String)->Result<Cache,String>{
    let agent:ureq::Agent=ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(15))).build().into();
    let get=|path:&str|->Result<serde_json::Value,String>{
        let mut response=agent.get(format!("{origin}{path}")).call().map_err(|_|"Server unavailable".to_owned())?;
        let text=response.body_mut().with_config().limit(2*1024*1024).read_to_string().map_err(|_|"Invalid public response".to_owned())?;
        serde_json::from_str(&text).map_err(|_|"Invalid public JSON".to_owned())
    };
    let activity=activity_from_value(get("/api/activity")?)?;
    let mut leaderboard:Leaderboard=serde_json::from_value(get("/api/leaderboards?metric=count")?).map_err(|_|"Invalid leaderboard".to_owned())?;
    leaderboard.entries.truncate(500);
    Ok(Cache{origin,activity,leaderboard})
}

fn activity_from_value(value:serde_json::Value)->Result<Activity,String>{
    let mut activity:Activity=serde_json::from_value(value).map_err(|_|"Invalid activity aggregate".to_owned())?;
    if activity.min_contributors<3||activity.window_hours!=24{return Err("Unsupported activity privacy threshold".into());}
    activity.zones.retain(|zone|zone.map_id>0&&zone.contributors>=activity.min_contributors);
    activity.zones.truncate(1000);
    Ok(activity)
}

#[cfg(test)]
mod tests{
    use super::*;
    use serde_json::json;
    #[test]
    fn population_cache_cannot_store_player_identities_or_coordinates(){
        let activity=activity_from_value(json!({"windowHours":24,"minContributors":3,"generatedAt":1,"zones":[{"mapId":1426,"contributors":3,"observations":8,"x":0.42,"y":0.3,"players":["Private"]},{"mapId":1429,"contributors":2,"observations":2}]})).unwrap();
        let value=serde_json::to_value(activity).unwrap();assert_eq!(value["zones"].as_array().unwrap().len(),1);assert!(value["zones"][0].get("x").is_none());assert!(value["zones"][0].get("players").is_none());
    }
}
