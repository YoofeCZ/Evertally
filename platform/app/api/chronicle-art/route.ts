import { chronicleArt } from "@/lib/chronicle-art";

export async function GET(request: Request) {
  const p = new URL(request.url).searchParams, kind = p.get("kind");
  const id = p.has("id") ? Number(p.get("id")) : undefined;
  const displayId = p.has("displayId") ? Number(p.get("displayId")) : undefined;
  const name = p.get("name") ?? undefined;
  if (kind !== "spell" && kind !== "npc" || [id,displayId].some(value=>value!==undefined && (!Number.isInteger(value)||value<=0||value>1e9)) || name && name.length>120)
    return Response.json({error:"Invalid artwork request"},{status:400});
  const art = await chronicleArt({kind,id,name,displayId});
  return Response.json(art,{headers:{"Cache-Control":art.image?"public, max-age=86400":"public, max-age=300","X-Content-Type-Options":"nosniff"}});
}
