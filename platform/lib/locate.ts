import {ApiError} from "./policy";
import type {Db} from "./people";
type Row=Record<string,unknown>;

/**
 * Someone asks a player's app for one position. Anyone who is signed in may ask anyone, but the player's own sharing choice
 * decides whether it is answered: the same rule that decides who may see their live position (everyone, signed-in visitors,
 * or confirmed friends). A player who shares with nobody cannot be asked, and the answer does not tell whether they exist.
 * Asking about oneself is always allowed. One account may ask about others once a minute, and a player is asked at most once
 * per half minute, so a flood of requests cannot use up the free database.
 */
export async function requestLocate(db:Db,viewerId:string,target:{profileId?:unknown;userId?:unknown}={}){
  const at=Math.floor(Date.now()/1000);
  const profileId=typeof target.profileId==="string"&&target.profileId?target.profileId.slice(0,200):null;
  const userId=typeof target.userId==="string"&&target.userId?target.userId.slice(0,200):null;
  let owner=viewerId;
  if(profileId||userId){
    const row=await db.prepare(`SELECT u.uid,s.friends,s.signed_in,s.public,
        EXISTS(SELECT 1 FROM et_friends f WHERE f.status='accepted' AND f.user_a=MIN(u.uid,?) AND f.user_b=MAX(u.uid,?)) AS is_friend
      FROM (SELECT ${profileId?"(SELECT user_id FROM atlas_profiles WHERE id=?)":"?"} AS uid) u LEFT JOIN et_sharing s ON s.user_id=u.uid`)
      .bind(viewerId,viewerId,profileId??userId).first<Row>();
    if(!row||row.uid==null)throw new ApiError("not_found","This player does not share their position with you.",404);
    owner=String(row.uid);
    if(owner!==viewerId&&!(row.public||row.signed_in||(row.friends&&row.is_friend)))throw new ApiError("not_found","This player does not share their position with you.",404);
  }
  if(owner!==viewerId){
    const ask=await db.prepare("INSERT INTO et_locate_asks(requester_id,asked_at) VALUES(?,?) ON CONFLICT(requester_id) DO UPDATE SET asked_at=excluded.asked_at WHERE excluded.asked_at>=et_locate_asks.asked_at+60").bind(viewerId,at).run();
    if(Number(ask.meta?.changes??0)===0)throw new ApiError("rate_limited","Wait a minute before asking about another player.",429);
  }
  await db.prepare("INSERT INTO et_locate_requests(user_id,requested_at) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET requested_at=excluded.requested_at WHERE excluded.requested_at>=et_locate_requests.requested_at+30")
    .bind(owner,at).run();
  return {requested:true,own:owner===viewerId};
}

export type Locatable = { profileId: string; name: string; realm: string | null; classId: number | null; level: number | null };

/**
 * Characters by name that this viewer may ask "where are you?": only those whose player shares their position with the viewer
 * (everyone, signed-in visitors, or confirmed friends), never the viewer's own characters. A name needs at least three letters,
 * so the list cannot be walked through, and at most ten are returned.
 */
export async function searchLocatable(db:Db,viewerId:string,query:string):Promise<Locatable[]>{
  const q=query.trim().toLowerCase().slice(0,40);
  if([...q].length<3)return [];
  const like=q.replace(/[!%_]/g,m=>"!"+m)+"%";
  const rows=await db.prepare(`SELECT p.id,p.name,p.realm,p.class_id,p.level FROM atlas_profiles p JOIN et_sharing s ON s.user_id=p.user_id
    WHERE p.user_id<>? AND p.name IS NOT NULL AND lower(p.name) LIKE ? ESCAPE '!'
      AND (s.public=1 OR s.signed_in=1 OR (s.friends=1 AND EXISTS(SELECT 1 FROM et_friends f WHERE f.status='accepted' AND f.user_a=MIN(p.user_id,?) AND f.user_b=MAX(p.user_id,?))))
    ORDER BY p.last_seen DESC LIMIT 10`).bind(viewerId,like,viewerId,viewerId).all<Row>();
  return rows.results.map(r=>({profileId:String(r.id),name:String(r.name),realm:typeof r.realm==="string"?r.realm:null,classId:typeof r.class_id==="number"?r.class_id:null,level:typeof r.level==="number"?r.level:null}));
}
