import test from "node:test";
import assert from "node:assert/strict";
import { addonSnapshot, applyOutbox, cleanText, createPost, createThread, deleteForumPost, deviceForum, editForumPost, editPostInput, getThread, isForumAdmin, listForum, moderateForumThread, moderateThreadInput, POSTS_PER_HOUR, postInput, SNAPSHOT_POSTS_PER_THREAD, threadInput, THREADS_PER_HOUR } from "../lib/forum";
import { fixture } from "./sqlite-db";

const code = (expected: string) => (error: unknown) => (error as { code?: string }).code === expected;
const t = (extra: Record<string, unknown> = {}) => threadInput.parse({ category: "general", title: "Kde je Defias Pillager?", body: "Hledám ho od včera.", ...extra });
const nowS = () => Math.floor(Date.now() / 1000);
function world() {
  const f = fixture();
  for (const [id, name] of [["gm", "Aria"], ["bob", "Bran"], ["eve", "Eve"]]) f.sql.prepare("INSERT INTO et_users(id,username,display_name,created_at,last_login_at) VALUES(?,?,?,0,0)").run(id, name.toLowerCase(), name);
  return f;
}

test("Moderation: only server allowlisted Discord IDs belong to the signed-in account", async () => {
  const f = world();
  f.sql.prepare("UPDATE et_users SET discord_id=? WHERE id=?").run("123456789123456789", "gm");
  assert.equal(await isForumAdmin(f.db, "gm", "987654321 123456789123456789"), true);
  assert.equal(await isForumAdmin(f.db, "bob", "123456789123456789"), false);
  assert.equal(await isForumAdmin(f.db, "gm", "1234567891234567891"), false);
  assert.equal(await isForumAdmin(f.db, "gm", ""), false);
  assert.equal(await isForumAdmin(f.db, null, "123456789123456789"), false);
});

test("Moderation: authors edit own text and title; strangers cannot edit or remove; admin may", async () => {
  const f=world();
  const initial=await createThread(f.db,"gm",t());
  const id=initial.thread.id;
  const reply=await createPost(f.db,"bob",postInput.parse({threadId:id,body:"Původní odpověď"}));
  const post=reply.posts[1].id;
  const changed=await editForumPost(f.db,"gm",id,editPostInput.parse({title:"Nový název",body:"Nový text"}));
  assert.equal(changed.thread.title,"Nový název");assert.equal(changed.posts[0].body,"Nový text");
  assert.equal(changed.posts[0].canManage,true);assert.equal(changed.posts[1].canManage,false);
  assert.equal((await getThread(f.db,id,"eve",true)).posts.every((p)=>p.canManage),true);
  await assert.rejects(editForumPost(f.db,"eve",post,editPostInput.parse({body:"Ne"})),code("not_found"));
  await assert.rejects(deleteForumPost(f.db,"eve",post),code("not_found"));
  await assert.rejects(editForumPost(f.db,"bob",post,editPostInput.parse({title:"Cizí téma",body:"Ne"})),code("invalid_post"));
  assert.equal((await editForumPost(f.db,"bob",post,editPostInput.parse({body:"Moje změna"}))).posts[1].body,"Moje změna");
  assert.equal((await editForumPost(f.db,"eve",post,editPostInput.parse({body:"Moderace"}),true)).posts[1].body,"Moderace");
  await deleteForumPost(f.db,"eve",post,true);
  assert.equal((await getThread(f.db,id,"gm")).posts.length,1);
  await deleteForumPost(f.db,"eve",id,true);
  await assert.rejects(getThread(f.db,id,null),code("not_found"));
  assert.equal(editPostInput.safeParse({body:"",admin:true}).success,false);
});

test("Moderation: only admin pins, other moderation fields are rejected", async () => {
  const f=world();const made=await createThread(f.db,"gm",t());const id=made.thread.id;
  const input=moderateThreadInput.parse({pinned:true});
  await assert.rejects(moderateForumThread(f.db,"gm",id,input),code("forbidden"));
  assert.equal(moderateThreadInput.safeParse({pinned:true,admin:true}).success,false);
  const changed=await moderateForumThread(f.db,"eve",id,input,true);
  assert.equal(changed.thread.pinned,true);assert.equal(changed.thread.canModerate,true);
  assert.equal((await listForum(f.db,null,{})).threads[0].canModerate,false);
  assert.equal(moderateThreadInput.safeParse({pinned:true,locked:true}).success,false);
  await moderateForumThread(f.db,"eve",id,moderateThreadInput.parse({pinned:false}),true);
  assert.equal((await createPost(f.db,"bob",postInput.parse({threadId:id,body:"povoleno"}))).posts.length,2);
});

test("cleanText: řídicí znaky pryč, nové řádky jen tam, kde se smějí, a délka v znacích", () => {
  assert.equal(cleanText("  a\u0000b\tc  ", 20), "a b c");
  assert.equal(cleanText("řádek 1\r\n\r\n\r\n\r\nřádek 2‮", 100, true), "řádek 1\n\nřádek 2");
  assert.equal(cleanText("a\nb", 20), "a b");
  assert.equal(cleanText("ěščřžýáíé".repeat(5), 9), "ěščřžýáíé");
  assert.equal(cleanText(42, 5), "");
});

test("Vstup: neznámá kategorie, příliš krátký název a cizí pole se odmítnou", () => {
  assert.equal(threadInput.safeParse({ category: "general", title: "ab", body: "x" }).success, false);
  assert.equal(threadInput.safeParse({ category: "politics", title: "Dobrý název", body: "x" }).success, false);
  assert.equal(threadInput.safeParse({ category: "general", title: "Dobrý název", body: "x", admin: true }).success, false);
  assert.equal(threadInput.safeParse({ category: "general", title: "Dobrý název", body: "   " }).success, false);
  assert.equal(postInput.safeParse({ threadId: "short", body: "x" }).success, false);
});

test("Web: vlákno a odpověď se podepíšou celým jménem postavy včetně realmu a nejdou pod cizí postavou", async () => {
  const f = world();
  const made = await createThread(f.db, "gm", t({ profileId: "p-gm" }));
  assert.equal(made.thread.author, "Aria-Test");
  assert.equal(made.thread.classId, 8);
  assert.equal(made.thread.origin, "web");
  assert.equal(made.posts.length, 1);
  assert.equal(made.posts[0].id, made.thread.id);
  await assert.rejects(createThread(f.db, "bob", t({ profileId: "p-gm" })), code("invalid_character"));
  const after = await createPost(f.db, "bob", postInput.parse({ threadId: made.thread.id, body: "Je v Moonbrooku.", replyTo: made.thread.id, profileId: "p-bob" }));
  assert.equal(after.thread.replies, 1);
  assert.equal(after.posts[1].author, "Bran-Test");
  assert.equal(after.posts[1].replyTo, made.thread.id);
  assert.equal(after.posts[1].mine, true);
  const read = await getThread(f.db, made.thread.id, "gm");
  assert.equal(read.posts[1].mine, false);
  assert.equal(read.thread.mine, true);
});

test("Web bez postavy píše pod jménem účtu a prázdný seznam kategorií má všech šest počtů", async () => {
  const f = world();
  const made = await createThread(f.db, "eve", t());
  assert.equal(made.thread.author, "Eve");
  const list = await listForum(f.db, null, {});
  assert.equal(list.categories.length, 6);
  assert.equal(list.categories.find((c) => c.id === "general")?.threads, 1);
  assert.equal((await listForum(f.db, null, { category: "trading" })).threads.length, 0);
});

test("Hledání kombinuje kategorii, skutečný text, autora, stránkování a skrývá smazané", async () => {
  const f = world();
  const thread = f.sql.prepare("INSERT INTO et_forum_threads(id,category,title,user_id,author,origin,created_at,last_post_at,deleted_at) VALUES(?,?,?,?,?,'web',?,?,?)");
  const post = f.sql.prepare("INSERT INTO et_forum_posts(id,thread_id,user_id,author,origin,body,created_at,deleted_at) VALUES(?,?,?,?,'web',?,?,?)");
  for (let i = 0; i < 42; i++) {
    const id = `gsearch${String(i).padStart(6, "0")}`;
    thread.run(id, "dungeons", `Záznam ${i}`, "gm", "Aria-Test", i, i, null);
    post.run(id, id, "gm", "Aria-Test", "ŽLUTÝ drak má 50%_\\ kořisti", i, null);
  }
  thread.run("gother000001", "trading", "Žlutý lektvar", "gm", "Aria-Test", 99, 99, null);
  post.run("gother000001", "gother000001", "gm", "Aria-Test", "kouzelný", 99, null);
  thread.run("gdeleted0001", "dungeons", "ŽLUTÝ smazaný", "gm", "Aria-Test", 100, 100, 101);
  post.run("gdeleted0001", "gdeleted0001", "gm", "Aria-Test", "ŽLUTÝ", 100, null);
  thread.run("gpostdead001", "dungeons", "Nesouvisející", "gm", "Aria-Test", 101, 101, null);
  post.run("gdeadreply01", "gpostdead001", "bob", "Želmíra", "ŽLUTÝ", 101, 102);

  const first = await listForum(f.db, null, { category: "dungeons", q: "žlutý", page: 0 });
  const second = await listForum(f.db, null, { category: "dungeons", q: "ŽLUTÝ", page: 1 });
  assert.equal(first.threads.length, 40);
  assert.equal(first.hasMore, true);
  assert.equal(second.threads.length, 2);
  assert.equal(second.hasMore, false);
  assert.ok(first.threads.every((row) => row.category === "dungeons"));
  assert.equal(new Set([...first.threads, ...second.threads].map((row) => row.id)).size, 42);
  assert.equal((await listForum(f.db, null, { category: "trading", q: "žlutý" })).threads[0].id, "gother000001");
  assert.equal((await listForum(f.db, null, { q: "ŽELMÍRA" })).threads.length, 0, "deleted reply author's identity must not match");
  assert.equal((await listForum(f.db, null, { q: "ARIA-test", page: 1 })).threads.length, 4);
  assert.equal((await listForum(f.db, null, { q: "50%_\\" })).threads.length, 40);
  assert.equal((await listForum(f.db, null, { q: "50%_\\x" })).threads.length, 0, "LIKE wildcards remain literal");
  assert.equal((await listForum(f.db, null, { q: "' OR 1=1 --" })).threads.length, 0);
});

test("Omezení rychlosti: víc než limit vláken i příspěvků za hodinu se odmítne", async () => {
  const f = world();
  let first = "";
  for (let i = 0; i < THREADS_PER_HOUR; i++) first = (await createThread(f.db, "gm", t({ title: `Vlákno číslo ${i}` }))).thread.id;
  await assert.rejects(createThread(f.db, "gm", t()), code("rate_limited"));
  const room = POSTS_PER_HOUR - THREADS_PER_HOUR;
  for (let i = 0; i < room; i++) await createPost(f.db, "gm", postInput.parse({ threadId: first, body: `odpověď ${i}` }));
  await assert.rejects(createPost(f.db, "gm", postInput.parse({ threadId: first, body: "ještě jedna" })), code("rate_limited"));
});

test("Hra → web: outbox se zapíše, druhé odeslání je jen duplicita a špatné položky nic nerozbijí", async () => {
  const f = world();
  const at = nowS();
  const outbox = [
    { kind: "thread", id: "gabc12345678", category: "dungeons", title: "Deadmines v pátek", body: "Kdo jde?\n\nPotřebuju healera.", author: "Hero-Fixture Realm", classId: 7, createdAt: at - 60 },
    { kind: "post", id: "gpost1234567", threadId: "gabc12345678", replyTo: "gabc12345678", body: "Já.", author: "Hero-Fixture Realm", createdAt: at - 30 },
    { kind: "post", id: "gpost7654321", threadId: "gmissing12345", body: "Do prázdna.", author: "Hero-Fixture Realm", createdAt: at },
    { kind: "thread", id: "gbad", category: "general", title: "x", body: "x", author: "x", createdAt: at },
    { kind: "thread", id: "gabc99999999", category: "nope", title: "Nic", body: "nic", author: "x", createdAt: at },
    "not an object", { kind: "post", id: "gpostxxxxxxx", threadId: "gabc12345678", body: "   ", author: "Hero-Realm", createdAt: at },
  ];
  const first = await applyOutbox(f.db, "gm", outbox);
  assert.deepEqual({accepted:first.accepted,duplicates:first.duplicates,rejected:first.rejected}, { accepted: 2, duplicates: 0, rejected: 5 });
  assert.deepEqual(first.acknowledgedIds.sort(),["gabc12345678","gpost1234567"].sort());
  const again = await applyOutbox(f.db, "gm", outbox);
  assert.equal(again.accepted, 0);
  assert.equal(again.duplicates, 2);
  const read = await getThread(f.db, "gabc12345678", null);
  assert.equal(read.thread.author, "Hero-Fixture Realm");
  assert.equal(read.thread.origin, "game");
  assert.equal(read.thread.classId, 7);
  assert.equal(read.thread.replies, 1);
  assert.equal(read.posts[0].body, "Kdo jde?\n\nPotřebuju healera.");
  assert.equal(read.posts[1].replyTo, "gabc12345678");
});

test("Cizí účet nepřepíše vlákno tím, že pošle stejné id", async () => {
  const f = world();
  const at = nowS();
  await applyOutbox(f.db, "gm", [{ kind: "thread", id: "gowned123456", category: "general", title: "Moje vlákno", body: "původní", author: "Aria-Test", createdAt: at }]);
  const hijack = await applyOutbox(f.db, "bob", [{ kind: "thread", id: "gowned123456", category: "general", title: "Převzaté", body: "podvrh", author: "Aria-Test", createdAt: at }]);
  assert.equal(hijack.accepted, 0);
  assert.equal(hijack.rejected, 1);
  assert.deepEqual(hijack.acknowledgedIds, []);
  assert.equal((await getThread(f.db, "gowned123456", null)).thread.title, "Moje vlákno");
  await assert.rejects(deleteForumPost(f.db, "bob", "gowned123456"), code("not_found"));
});

test("Device ack confirms only own accepted/known IDs including soft deleted, never foreign or rejected", async () => {
  const f=world();const at=nowS();
  const own={kind:"thread",id:"gackown12345",category:"general",title:"Moje téma",body:"Můj obsah",author:"Aria-Test",createdAt:at};
  const foreign={kind:"thread",id:"gackother123",category:"general",title:"Cizí téma",body:"Cizí obsah",author:"Bran-Test",createdAt:at};
  const reply={kind:"post",id:"gackreply123",threadId:own.id,body:"odpověď",author:"Aria-Test",createdAt:at};
  const rejected={kind:"post",id:"gackreject12",threadId:"gmissing1234",body:"nelze",author:"Aria-Test",createdAt:at};
  await applyOutbox(f.db,"bob",[foreign]);
  assert.deepEqual((await applyOutbox(f.db,"gm",[own,reply])).acknowledgedIds,[own.id,reply.id]);
  await deleteForumPost(f.db,"gm",reply.id);
  await deleteForumPost(f.db,"gm",own.id);
  const synced=await deviceForum(f.db,"gm",{outbox:[own,foreign,reply,rejected]});
  assert.deepEqual(synced.acknowledgedIds.sort(),[own.id,reply.id].sort());
  assert.equal(synced.duplicates,2);assert.equal(synced.rejected,2);
  assert.equal(synced.threads.some(thread=>thread.id===own.id),false);
});

test("Device ack leaves rate-limited posts queued while confirming an already known own ID", async () => {
  const f=world();const at=nowS();
  const entry=(index:number)=>({kind:"thread",id:`gqueued${String(index).padStart(6,"0")}`,category:"general",title:`Téma ${index}`,body:"obsah",author:"A-Test",createdAt:at});
  const first=await applyOutbox(f.db,"gm",Array.from({length:THREADS_PER_HOUR},(_,index)=>entry(index)));
  assert.equal(first.acknowledgedIds.length,THREADS_PER_HOUR);
  const result=await applyOutbox(f.db,"gm",[entry(0),entry(99)]);
  assert.deepEqual(result.acknowledgedIds,[entry(0).id]);
  assert.equal(result.duplicates,1);assert.equal(result.rejected,1);
});

test("Čas z hry z budoucnosti nebo z dávné minulosti se nahradí časem serveru", async () => {
  const f = world();
  await applyOutbox(f.db, "gm", [
    { kind: "thread", id: "gfuture12345", category: "general", title: "Z budoucnosti", body: "x", author: "A-B", createdAt: nowS() + 86400 },
    { kind: "thread", id: "gancient1234", category: "general", title: "Z dávna", body: "x", author: "A-B", createdAt: 5 },
  ]);
  for (const id of ["gfuture12345", "gancient1234"]) assert.ok(Math.abs((await getThread(f.db, id, null)).thread.createdAt - nowS()) <= 2);
});

test("Snímek pro addon: otevírací příspěvek první, nejnovější odpovědi, web i hra dohromady, bez ID účtů", async () => {
  const f = world();
  const web = await createThread(f.db, "gm", t({ profileId: "p-gm", title: "Z webu" }));
  await applyOutbox(f.db, "bob", [{ kind: "thread", id: "gfromgame1234", category: "trading", title: "Z hry", body: "prodám rudu", author: "Bran-Test", classId: 4, createdAt: nowS() }]);
  const sent = await deviceForum(f.db, "gm", { outbox: [] });
  assert.equal(sent.threads.length, 2);
  const names = sent.threads.map((th) => th.title).sort();
  assert.deepEqual(names, ["Z hry", "Z webu"]);
  assert.equal(JSON.stringify(sent).includes("user_id"), false);
  assert.equal(JSON.stringify(sent).includes('"gm"'), false);
  assert.equal(sent.threads.find((th) => th.id === web.thread.id)?.posts[0].id, web.thread.id);
  // many replies: only the opening post and the newest ones go to the game
  const big = "gbigthread1234";
  const at = nowS();
  f.sql.prepare("INSERT INTO et_forum_threads(id,category,title,user_id,author,origin,created_at,last_post_at) VALUES(?,?,?,?,?,?,?,?)").run(big, "general", "Dlouhé", "eve", "Eve-Test", "web", at - 5000, at);
  const insert = f.sql.prepare("INSERT INTO et_forum_posts(id,thread_id,user_id,author,origin,body,created_at) VALUES(?,?,?,?,?,?,?)");
  insert.run(big, big, "eve", "Eve-Test", "web", "otevírací", at - 5000);
  for (let i = 0; i < 100; i++) insert.run(`greply${String(i).padStart(6, "0")}`, big, "eve", "Eve-Test", "web", `odpověď ${i}`, at - 4000 + i);
  const snapshot = await addonSnapshot(f.db);
  const thread = snapshot.threads.find((th) => th.id === big)!;
  assert.equal(thread.posts.length, SNAPSHOT_POSTS_PER_THREAD);
  assert.equal(thread.posts[0].body, "otevírací");
  assert.equal(thread.posts[thread.posts.length - 1].body, "odpověď 99");
});

test("Smazání vlastního příspěvku: odpověď zmizí, smazání otevíracího příspěvku smaže vlákno", async () => {
  const f = world();
  const made = await createThread(f.db, "gm", t());
  const replied = await createPost(f.db, "bob", postInput.parse({ threadId: made.thread.id, body: "odpověď" }));
  await assert.rejects(deleteForumPost(f.db, "gm", replied.posts[1].id), code("not_found"));
  await deleteForumPost(f.db, "bob", replied.posts[1].id);
  const back = await getThread(f.db, made.thread.id, null);
  assert.equal(back.posts.length, 1);
  assert.equal(back.thread.replies, 0);
  await deleteForumPost(f.db, "gm", made.thread.id);
  await assert.rejects(getThread(f.db, made.thread.id, null), code("not_found"));
  assert.equal((await listForum(f.db, null, {})).threads.length, 0);
});
