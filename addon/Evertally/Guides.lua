local _, A = ...
-- Written chapters and profession batches, all readable in game. This page has no external URL flow.
local TEXT={
 en={guides="Guides",sub_guides="Read class, dungeon, leveling and profession guides here. Open recipes, materials and talent plans inside Evertally.",guideAll="All",guideProfessions="Professions",guideClasses="Classes",guideLeveling="Leveling",guideDungeons="Dungeons",guideRead="Mark read",guideReadDone="Read",guideNext="Next chapter",guideProgress="%d / %d chapters read",guideRecipe="Open recipe",guideRecipes="Browse recipes",guideTalents="Open talent planner",guideMap="Gathering map",guideBatch="%d–%d · %d × %s",guideUnits="%d × %s",guideRecipeMissing="No usable recipe is documented at skill %d. Choose a recipe you can learn in Recipes before continuing.",guideBatchHint="The route uses local recipe skill thresholds and direct ingredient counts, not auction prices. Learn each pattern before buying materials: some recipes require a vendor, drop or specialisation.",guideChance="Yellow or green: this is the minimum batch of attempts, not a guaranteed skill gain. Continue until the target skill and allow extra materials.",guideOrange="Orange: make the batch, then check your actual skill before continuing.",guideMaterials="Materials for these batches",guideMaterialsHint="Direct ingredients for the minimum batches below. Intermediate crafts are not expanded. Random skill gains may require more.",guideNoData="The recipe data could not be loaded. Written chapters remain available.",guidePreparation="Training and preparation",guidePreparationBody="Bring tools, free bag space and train the next skill cap before reaching the current one. Each recipe's learning requirement and colour thresholds are available in Recipes.",guideRoute="Recipe route 1–300"},
 cs={guides="Návody",sub_guides="Čti návody ke třídám, dungeonům, levelování a profesím přímo tady. Recepty, suroviny a talenty se otevřou uvnitř Evertally.",guideAll="Vše",guideProfessions="Profese",guideClasses="Třídy",guideLeveling="Levelování",guideDungeons="Dungeony",guideRead="Označit přečtené",guideReadDone="Přečteno",guideNext="Další kapitola",guideProgress="Přečteno %d / %d kapitol",guideRecipe="Otevřít recept",guideRecipes="Procházet recepty",guideTalents="Plán talentů",guideMap="Mapa sbírání",guideBatch="%d–%d · %d × %s",guideUnits="%d × %s",guideRecipeMissing="Pro dovednost %d není doložen použitelný recept. V Receptech vyber takový, který se můžeš naučit, a pak pokračuj.",guideBatchHint="Postup používá místní hranice dovednosti a počty přímých surovin, ne ceny aukce. Před nákupem materiálu se recept nauč: některé vzory mohou být od prodejce, dropu nebo vyžadovat specializaci.",guideChance="Žlutý nebo zelený recept: jde o minimální sérii pokusů, ne zaručený zisk dovednosti. Vyráběj do cílové hodnoty a počítej s dalšími surovinami.",guideOrange="Oranžový recept: vyrob sérii a před pokračováním zkontroluj skutečnou dovednost.",guideMaterials="Suroviny pro uvedené série",guideMaterialsHint="Přímé suroviny minimálních sérií níže. Mezivýrobky nejsou rozložené na základní materiál. Náhodný zisk dovednosti může spotřebu zvýšit.",guideNoData="Balíček receptů se nepodařilo načíst. Psané kapitoly zůstávají dostupné.",guidePreparation="Trénink a příprava",guidePreparationBody="Vezmi nástroje, nech místo v taškách a před dosažením stropu se nauč další stupeň. Požadavek pro naučení receptu a hranice jeho barev ukazuje stránka Recepty.",guideRoute="Postup podle receptů 1–300"},
}
for lang,entries in pairs(TEXT)do for key,value in pairs(entries)do A.locale[lang][key]=value end end
A.locale.en.guideNavigate="Navigate"
A.locale.cs.guideNavigate="Navigovat"
local function cz()return A.db and A.db.settings.language=="cs"end
local function tr(en,cs)return cz()and cs or en end
local function s(en,cs,textEn,textCs,action)return{title=tr(en,cs),body=tr(textEn,textCs),action=action}end
local BOOKS={}
local function add(id,category,en,cs,sections,icon)BOOKS[#BOOKS+1]={id=id,category=category,en=en,cs=cs,sections=sections,icon=icon or"Interface\\Icons\\INV_Misc_Book_09"}end
function A.RegisterGuide(id,category,en,cs,sections,icon)
 for _,book in ipairs(BOOKS)do if book.id==id then return false end end
 add(id,category,en,cs,sections,icon);return true
end
add("leveling","leveling","Leveling: plan a useful session","Levelování: plán pro tvoje hraní",function()return{
 s("1–10: prepare your character","1–10: připrav postavu","Finish a compact starting area. Train abilities you use and maintain your main weapon. Set the hearthstone near regular quest turn-ins. Keep food, free bag slots and a safe escape route.","Dokonči souvislou startovní oblast. Trénuj používané schopnosti a průběžně obnovuj hlavní zbraň. Hearthstone nastav poblíž pravidelného odevzdávání questů. Nos jídlo, nech volné tašky a promysli únikovou cestu."),
 s("10–20: combine nearby quests","10–20: spoj blízké questy","Collect quests from one hub. In the Database check their objectives, start NPCs and turn-ins, then finish nearby objectives in one circuit. Before a dungeon inspect its quest tab and complete any outdoor prerequisites first.","Naber questy z jednoho centra. V Databázi ověř cíle, zadavatele a odevzdání a blízké úkoly spoj do jednoho okruhu. Před dungeonem projdi jeho questy a venkovní podmínky řetězců.","database"),
 s("20–40: reduce downtime","20–40: zkrať prostoje","Carry food, drinks if you use mana, and bandages. Return to town with several completed quests or full bags, not after every kill. Unlock flight points as you pass them. Compare a gear upgrade with the time and money needed to obtain it.","Nos jídlo, při používání many i pití a obvazy. Do města se vracej s více hotovými questy nebo plnými taškami, ne po každém zabití. Cestou odemykej letové body. Zlepšení výbavy porovnej s časem a penězi potřebnými k jeho získání."),
 s("40–60: pick manageable objectives","40–60: vybírej zvládnutelné cíle","Prefer objectives you can complete without repeated deaths. Check dungeon levels, entrances and quests before travelling. Change area when most objectives require much stronger enemies. In the journal distinguish unfinished, abandoned and completed quests.","Dávej přednost cílům bez opakovaných smrtí. Před cestou ověř úroveň, vchod a questy dungeonu. Změň oblast, když většina úkolů vyžaduje výrazně silnější nepřátele. V Deníku rozlišuj rozpracované, opuštěné a splněné questy.","journal"),
}end)
add("first-dungeon","dungeons","Your first dungeon","První dungeon",function()return{
 s("Before entering","Před vstupem","Agree on tank, healer and damage roles and loot rules. Repair, clear bags and bring food, water and ability reagents. Check the entrance and dungeon quests, including the place where each quest is turned in.","Domluvte tanka, healera, poškození i pravidla lootu. Oprav výbavu, uvolni tašky a vezmi jídlo, vodu a suroviny schopností. Ověř vchod a questy včetně míst odevzdání.","dungeons"),
 s("Pulls and control","Skupiny nepřátel a kontrola","Let the tank establish control before heavy damage. Focus the marked target, interrupt dangerous casts and avoid breaking crowd control. Wait when the healer needs mana. Call out extra enemies instead of running away through another pack.","Nech tanka získat kontrolu před velkým poškozením. Útoč do označeného cíle, přerušuj nebezpečná kouzla a neruš crowd control. Počkej, když healer potřebuje manu. Přidané nepřátele nahlas; neutíkej přes další skupinu."),
 s("Loot and leaving","Loot a odchod","Compare loot for your intended role, not just its quality colour. Before leaving inspect unfinished quest objectives and remaining turn-ins. Run history distinguishes what was observed from a claimed full clear.","Loot porovnávej podle zamýšlené role, ne jen barvy kvality. Před odchodem zkontroluj nedokončené cíle questů a odevzdání. Historie běhů rozlišuje pozorovaný průchod a úplné vyčištění.","history"),
}end)
add("roles","dungeons","Tanking, healing and damage","Tankování, léčení a poškození",function()return{
 s("Tank","Tank","Pick a safe fighting position. Check line of sight before pulling casters and do not chain into the next pack while the healer is unready. Keep resources for defensive and threat abilities.","Vyber bezpečné místo boje. Před nalákáním kouzelníka ověř výhled a další skupinu neber, pokud healer není připraven. Nech zdroje na obranu a získávání hrozby."),
 s("Healer","Healer","Stay in range and line of sight. Heal according to missing health and incoming damage; a large overheal wastes mana. Keep yourself alive and tell the group before you must drink.","Zůstávej na dosah a ve výhledu. Léč podle chybějícího zdraví a přicházejícího poškození; velké přeléčení plýtvá manou. Udrž sebe naživu a včas řekni, že potřebuješ pít."),
 s("Damage","Poškození","Follow target priority, interrupt and avoid unnecessary damage. Position without pulling adjacent enemies. When an enemy targets you, move toward the tank rather than away from the group.","Dodržuj pořadí cílů, přerušuj a vyhýbej se zbytečnému poškození. Stůj tak, abys nepřidal vedlejší nepřátele. Pokud tě nepřítel pronásleduje, přibliž se k tankovi místo útěku od skupiny."),
}end)
add("professions","professions","Professions: materials and skill colours","Profese: suroviny a barvy dovednosti",function()return{
 s("Choose a recipe route","Vyber výrobní postup","Choose a profession in this library for a 1–300 recipe route. It uses shipped skill thresholds and direct ingredient counts, not auction prices. A recipe existing in the database does not mean your trainer offers it: learn it before buying the batch.","Vyber profesi v knihovně pro postup podle receptů 1–300. Používá přibalené hranice dovednosti a přímé suroviny, ne ceny aukce. Recept v databázi nemusí nabízet trenér: nauč se ho před nákupem série.","recipes"),
 s("Read the colours","Čti barvy","Orange recipes provide the most reliable skill progress; yellow and green can require extra attempts. Grey recipes no longer raise skill. Check your skill after each batch and move to the next recipe instead of crafting the old one indefinitely.","Oranžové recepty poskytují nejspolehlivější postup; žluté a zelené mohou vyžadovat další pokusy. Šedé už dovednost nezvyšují. Po sérii ověř dovednost a přejdi na další recept místo nekonečné výroby starého."),
 s("Keep intermediates","Uschovej mezivýrobky","Bolts, bars, leather and powders may be needed by later recipes. The shopping list shows direct ingredients; it does not expand a bolt into cloth or a bar into ore. Click materials to open their database sources and vendors.","Role látky, pruty, kůže a prášky mohou být potřeba později. Nákupní součet uvádí přímé suroviny; nerozkládá roli na látku ani prut na rudu. Kliknutím na materiál otevřeš jeho zdroje a prodejce."),
}end)
add("talent-planning","classes","Plan your talent build","Naplánuj si talenty",function()return{
 s("Choose your role","Vyber svoji roli","Decide whether you plan solo leveling, tanking, healing or group damage. Read full talent tooltips. The planner uses the current character's class data from the client.","Urči, jestli plánuješ sólo levelování, tankování, léčení nebo skupinové poškození. Čti celé tooltipy talentů. Plánovač používá data třídy aktuální postavy z klienta.","talents"),
 s("Allocate and save","Rozděl a ulož","Set the planned level. Left click adds a rank, right click removes it. Higher rows require points in earlier rows and linked talents require a maximised prerequisite. Save named builds for different roles. This never spends your actual game points.","Nastav plánovanou úroveň. Levý klik přidá bod a pravý ho odebere. Vyšší řady potřebují body v předchozích a propojené talenty dokončenou podmínku. Pro různé role ulož pojmenované buildy. Skutečné herní body se tím nemění.","talents"),
 s("Check the result in play","Ověř výsledek při hraní","Compare survival, resource downtime and group control with the abilities and equipment you actually have. Keep the previous saved build when testing. Class chapters explain decisions; they do not claim an unverified universally optimal build.","Porovnej přežití, prostoje kvůli zdrojům a kontrolu skupiny se schopnostmi a výbavou, které opravdu máš. Při testování nech původní build uložený. Kapitoly tříd vysvětlují rozhodování a netvrdí neověřený univerzální nejlepší build."),
}end)
local CLASSES={
 {"WARRIOR","Warrior","Válečník","Build rage in combat; keep a reserve for interrupts and defensive abilities. Train the weapon type you use. A main-weapon upgrade affects both damage and resource generation.","V boji získávej zuřivost a nech rezervu na přerušení a obranu. Trénuj používaný druh zbraně. Zlepšení hlavní zbraně mění poškození i získávání zdroje.","If tanking, carry a shield and usable one-handed weapon. Mark targets and pull manageable packs. For damage, compare weapon performance and the stats your abilities actually use.","Pro tankování nos štít a použitelnou jednoruční zbraň. Označ cíle a ber zvládnutelné skupiny. Pro poškození posuzuj výkon zbraně a statistiky používané tvými schopnostmi."},
 {"PALADIN","Paladin","Paladin","Maintain the intended seal, use judgement for the encounter and keep enough mana for an emergency heal. Choose an aura and blessing for the group and role.","Udržuj zamýšlený seal, judgement používej podle souboje a nech manu na nouzové léčení. Auru a požehnání vybírej podle skupiny a role.","Agree on your role before a dungeon. Carry tanking equipment with a shield or healing equipment when needed. A hybrid class still needs positioning, resources and a suitable talent plan.","Před dungeonem domluv svoji roli. Nos tankovací výbavu se štítem nebo léčivou výbavu podle potřeby. Hybrid stále potřebuje správné postavení, zdroje a vhodné talenty."},
 {"HUNTER","Hunter","Lovec","Maintain pet happiness and abilities. Control its attacks near extra enemies. Keep the distance your ranged skills need and watch the pet's route back to you.","Udržuj spokojenost a schopnosti mazlíčka. U dalších nepřátel ovládej jeho útoky. Dodržuj vzdálenost pro střelbu a hlídej cestu zvířete zpět.","Carry ammunition if your weapon needs it. Disable pet taunts while a player tanks. Agree on trap and crowd-control targets; do not break a controlled enemy with pet attacks.","Pokud zbraň potřebuje munici, nos ji. Když tankuje hráč, vypni provokování zvířete. Domluv cíle pastí a kontroly; útokem mazlíčka neruš ovládaného nepřítele."},
 {"ROGUE","Rogue","Zloděj","Spend energy deliberately and keep enough for important interrupts. Use finishers before switching targets when practical. Avoid chasing an enemy into another pack.","Energii utrácej záměrně a nech ji na důležitá přerušení. Pokud to jde, použij zakončení před změnou cíle. Nepronásleduj nepřítele do další skupiny.","Prepare poisons and train your weapon types. Agree on a Sap target. Save defensive cooldowns for emergencies; avoidable damage also consumes the healer's mana.","Připrav jedy a trénuj používané zbraně. Domluv cíl pro Sap. Obranné cooldowny nech na nouzi; zbytečné poškození spotřebovává i manu léčitele."},
 {"PRIEST","Priest","Kněz","Choose heals for missing health and incoming damage; large overheals waste mana. Keep yourself safe enough to continue healing and remain in line of sight.","Léčení vybírej podle chybějícího zdraví a příchozího poškození; velké přeléčení plýtvá manou. Udrž sebe v bezpečí a zůstaň ve výhledu.","Check mana before pulls and discuss dispels and crowd control. When dealing damage, reserve mana for essential support. Compare equipment for the role you actually play.","Před soubojem ověř manu a domluv odstraňování efektů či kontrolu. Při poškození nech manu na potřebnou podporu. Výbavu porovnávej podle skutečně hrané role."},
 {"SHAMAN","Shaman","Šaman","Place totems where the fight will happen and renew them after moving. Read range and effect in the client. Reserve mana for interrupts, healing or utility your role needs.","Totemy stav tam, kde bude boj, a po přesunu je obnov. Dosah a efekt čti v klientu. Nech manu na přerušení, léčení či podporu podle role.","Agree on the party's buffs. Avoid leaving a totem where it may pull unwanted enemies. Maintain weapon enhancement and choose gear for melee, caster or healing use.","Domluv buffy party. Nenechávej totem tam, kde přidá nechtěné nepřátele. Udržuj posílení zbraně a vybírej výbavu pro boj zblízka, kouzlení nebo léčení."},
 {"MAGE","Mage","Mág","Use control to maintain a manageable distance and plan an escape before large pulls. Area damage helps only when the group can safely hold the pack.","Kontrolou udržuj zvládnutelnou vzdálenost a před větší skupinou promysli únikovou cestu. Plošné poškození pomáhá jen při bezpečně zvládnuté skupině.","Prepare water and required reagents. Agree on Polymorph targets, avoid breaking them with area damage, wait for threat and interrupt dangerous spells.","Připrav vodu a potřebné suroviny. Domluv cíle Polymorphu, nerozbíjej je plošným útokem, počkej na hrozbu a přerušuj nebezpečná kouzla."},
 {"WARLOCK","Warlock","Černokněžník","Choose a pet for the task. Put damage-over-time effects only on enemies you mean to fight; they can break control. Keep a safe health reserve when converting health into resources.","Vyber mazlíčka podle úkolu. Průběžné poškození dávej jen zamýšleným cílům; může rušit kontrolu. Při výměně zdraví za zdroje nech bezpečnou rezervu.","Carry soul shards for skills that consume them, prepare a healthstone and discuss summons before leaving. Control pet attacks and Fear so they do not pull another group.","Nos soul shards pro schopnosti, které je spotřebují, připrav healthstone a před cestou domluv přivolávání. Hlídej mazlíčka i Fear, aby nepřidali další skupinu."},
 {"DRUID","Druid","Druid","Use a form appropriate to the task and account for the cost of switching. Keep emergency healing available when possible. A form does not replace the gear and talents required by its role.","Použij formu vhodnou pro úkol a počítej s náklady změny. Pokud to jde, nech nouzové léčení. Forma nenahrazuje výbavu a talenty potřebné pro roli.","Agree whether you tank, heal or deal damage. Carry appropriate sets for changes of role. Practice changing forms without losing control of a pull or moving out of healing range.","Domluv tankování, léčení nebo poškození. Pro změnu role nos vhodné sady. Natrénuj změny forem bez ztráty kontroly nad bojem nebo dosahu léčení."},
}
for _,class in ipairs(CLASSES)do local c=class;add("class-"..c[1],"classes",c[2]..": practical play",c[3]..": praktické hraní",function()return{
 s("Resources and abilities","Zdroje a schopnosti",c[4],c[5]),s("Equipment and group play","Výbava a hra ve skupině",c[6],c[7]),
 s("Your talent plan","Tvůj plán talentů","Read the current character's talent tooltips, set the planned level and save separate builds for different roles. Equipment and available abilities affect which plan is useful.","Čti tooltipy talentů aktuální postavy, nastav zamýšlenou úroveň a pro různé role ulož samostatné buildy. Vhodný plán závisí na výbavě a dostupných schopnostech.","talents"),
}end)end
local PROFESSIONS={{171,"Alchemy","Alchymie","herb"},{164,"Blacksmithing","Kovářství","ore"},{165,"Leatherworking","Kožedělnictví"},{197,"Tailoring","Krejčovství"},{202,"Engineering","Inženýrství","ore"},{333,"Enchanting","Očarování"},{185,"Cooking","Vaření","fishing"},{129,"First Aid","První pomoc"},{186,"Mining","Těžba","ore"},{182,"Herbalism","Bylinkářství","herb"},{393,"Skinning","Stahování kůží"},{356,"Fishing","Rybaření","fishing"}}
local GATHER={
 [182]={
 {"1–75","Gather Peacebloom, Silverleaf and Earthroot near starting areas. Enable herb tracking and follow a safe short circuit.","Sbírej Peacebloom, Silverleaf a Earthroot poblíž startovních oblastí. Zapni sledování bylin a jezdi bezpečný krátký okruh."},
 {"75–150","Train the next cap. In the gathering catalogue filter Briarthorn, Bruiseweed and herbs your current skill allows. The node tooltip gives the required skill.","Zvyš strop dovednosti. V katalogu sbírání filtruj Briarthorn, Bruiseweed a dostupné byliny. Potřebnou dovednost ověř tooltipem uzlu."},
 {"150–225","Move through suitable higher areas after training. Filter only the herbs you need. Reference pins are possible spawns, not currently spawned plants.","Po tréninku přejdi do vhodných vyšších oblastí. Filtruj jen potřebné byliny. Referenční piny jsou možná naleziště, ne právě dostupné rostliny."},
 {"225–300","Gather higher herbs that still raise skill, avoiding dangerous caves when alone. Replace grey nodes with useful ones and store herbs according to your planned recipes.","Sbírej vyšší byliny, které stále zvyšují dovednost; sólo se vyhýbej nebezpečným jeskyním. Šedé uzly nahraď a zásoby vybírej podle plánovaných receptů."},
 },
 [186]={
 {"1–75","Carry a pick and enable Find Minerals. Mine safe copper circuits; smelt while the recipe still raises skill and keep bars needed by your production profession.","Nos krumpáč a zapni Find Minerals. Těž měď v bezpečném okruhu; tav, dokud recept zvyšuje dovednost, a pruty nech pro výrobní profesi."},
 {"75–150","Train the next cap and filter copper, tin and silver. Check each node's requirement in the game before entering a dangerous area.","Zvyš strop a filtruj měď, cín a stříbro. Před nebezpečnou oblastí zkontroluj požadavek konkrétní žíly ve hře."},
 {"150–225","Gather higher deposits including iron and mithril when your skill permits. Keep stone as well as ore if your Engineering or Blacksmithing recipes use it.","Těž vyšší žíly včetně železa a mithrilu, pokud je dovednost dovolí. Pro Inženýrství a Kovářství nech i potřebný kámen."},
 {"225–300","Train and move to higher circuits. Mine deposits that are not grey. Check a node's tooltip before a cave; reference pins do not guarantee a spawned vein.","Po tréninku přejdi na vyšší okruhy. Těž nešedé žíly. Před jeskyní ověř tooltip; referenční pin nezaručuje dostupnou žílu."},
 },
 [393]={
 {"1–75","Carry a skinning knife and skin looted beasts as you quest. Verify the requirement before attacking much stronger beasts. Store light leather and scraps.","Nos stahovací nůž a při questech stahuj vylootené bestie. Před výrazně silnější bestií ověř požadavek. Lehkou kůži a útržky uschovej."},
 {"75–150","Train the next cap. Choose dense safe beasts with little travel. Keep bags free so corpses can be looted before skinning.","Zvyš strop. Vyber hustě rozmístěné bezpečné bestie s krátkými přesuny. Nech volné tašky pro vylootění mrtvol před stažením."},
 {"150–225","Collect the leather your current beasts provide. Check Leatherworking before converting all lower-grade leather: later recipes may need it directly.","Sbírej kůže z dostupných bestií. Před přeměnou veškeré nižší kůže projdi Kožedělnictví; pozdější recept ji může potřebovat přímo."},
 {"225–300","Train and choose beasts that are safe while still giving skill. Keep hides separate: cured hides and ordinary leather serve different recipes.","Po tréninku vybírej bezpečné bestie, které stále dávají dovednost. Usně nech zvlášť: vyčiněné usně a obyčejná kůže patří do různých receptů."},
 },
 [356]={
 {"1–75","Buy and equip a fishing pole. Cast in safe water, wait for the bobber and loot the catch. Carry lures and keep fish used by Cooking.","Kup a vybav prut. Nahoď v bezpečné vodě, sleduj splávek a vylootuj úlovek. Vezmi návnady a nech ryby potřebné pro Vaření."},
 {"75–150","Train the next cap before long sessions. Use water where catches are reliable. A pool reference pin is not proof the pool is currently present.","Před delším chytáním zvyš strop. Vyber vodu se spolehlivými úlovky. Referenční pin hejna nedokazuje jeho současnou dostupnost."},
 {"150–225","Continue catches until the next training requirement. Fishing is not one skill point per cast. Open Cooking recipes to choose useful fish.","Chytej do dalšího tréninkového požadavku. Rybaření nedává bod za každý nához. V Receptech Vaření vyber užitečný druh ryby."},
 {"225–300","Complete the training or fishing quest required by your client before continuing above the cap. Use lures in harder water and repeat catches to 300.","Před postupem nad strop dokonči trénink nebo rybářský quest požadovaný klientem. V těžší vodě použij návnady a pokračuj v úlovcích do 300."},
 },
}
function A.ProfessionGuidePlan(line,recipes,from,target)
 local plan={steps={},materials={},from=math.max(1,math.floor(from or 1)),target=math.min(300,math.floor(target or 300))}
 local skill=plan.from
 while skill<plan.target and #plan.steps<160 do
  local best,band,score
  for _,r in ipairs(recipes or{})do local k=r.skill
   if r.line==line and r.id~=818 and type(k)=="table" and #k>=4 and (r.out or line==333 or line==186) and #(r.reagents or{})>0 then
    local learn=math.max(k[1]or 1,r.req or 1)
    if learn<=skill and k[4]>skill then
     local b=skill<k[2]and 0 or skill<k[3]and 1 or 2;local units=0
     for _,v in ipairs(r.reagents)do units=units+(v[2]or 0)end
     local cost=b*100000+units+#r.reagents*3-math.min(25,math.max(0,k[2]-skill))*.1
     if not score or cost<score or cost==score and r.id<best.id then best,band,score=r,b,cost end
    end
   end
  end
  if not best then plan.uncovered=skill;break end
  local limit=best.skill[band==0 and 2 or band==1 and 3 or 4]
  local stop=math.min(plan.target,skill+25,math.max(skill+1,limit))
  for _,boundary in ipairs({75,150,225})do if skill<boundary then stop=math.min(stop,boundary);break end end
  local count=stop-skill;local step={from=skill,to=stop,crafts=count,recipe=best,chance=band>0,materials={}}
  for _,v in ipairs(best.reagents)do step.materials[#step.materials+1]={v[1],v[2]*count};plan.materials[v[1]]=(plan.materials[v[1]]or 0)+v[2]*count end
  plan.steps[#plan.steps+1]=step;skill=stop
 end
 plan.reached=skill;return plan
end
local function itemName(id)return A.map and A.map.ItemName and A.map.ItemName(id)or A.Call(GetItemInfo,id)or("#"..id)end
local function professionSections(p)
 local result={{title=A.L("guidePreparation"),body=A.L("guidePreparationBody")}}
 if GATHER[p[1]]then
  for _,step in ipairs(GATHER[p[1]])do result[#result+1]={title=step[1],body=tr(step[2],step[3])}end
  result[#result+1]={title=tr("Find reference locations","Najdi referenční místa"),body=tr("Filter the gathering map by the resources you need. Grey nodes no longer raise skill; check the client's requirement before moving.","Na mapě sbírání vyber potřebné suroviny. Šedé uzly už dovednost nezvyšují; před přesunem ověř požadavek klienta."),action=p[4]and"gather:"..p[4]or"database"};return result
 end
 if A.LoadGuide then A.LoadGuide()end
 local recipes=A.map and A.map.recipes
 result[#result+1]={title=A.L("guideRoute"),body=A.L("guideBatchHint"),action="recipes"}
 if not recipes then result[#result+1]={title=A.L("guideRoute"),body=A.L("guideNoData")};return result end
 local plan=A.ProfessionGuidePlan(p[1],recipes)
 for _,step in ipairs(plan.steps)do
  local ingredients={};for _,v in ipairs(step.materials)do ingredients[#ingredients+1]=string.format(A.L("guideUnits"),v[2],itemName(v[1]))end
  result[#result+1]={title=string.format(A.L("guideBatch"),step.from,step.to,step.crafts,step.recipe.name),body=table.concat(ingredients,"  ·  ").."\n"..A.L(step.chance and"guideChance"or"guideOrange"),action="recipe:"..step.recipe.id,materials=step.materials,range={step.from,step.to}}
 end
 if plan.uncovered then result[#result+1]={title=tr("Check the next recipe","Ověř další recept"),body=string.format(A.L("guideRecipeMissing"),plan.uncovered),action="recipes"}end
 result[#result+1]={title=A.L("guideMaterials"),body=A.L("guideMaterialsHint")}
 local shopping={};for id,count in pairs(plan.materials)do shopping[#shopping+1]={id=id,count=count}end;table.sort(shopping,function(a,b)return a.id<b.id end)
 for _,v in ipairs(shopping)do result[#result+1]={title=string.format(A.L("guideUnits"),v.count,itemName(v.id)),body="",action="item:"..v.id,itemId=v.id}end
 return result
end
for _,profession in ipairs(PROFESSIONS)do local p=profession;add("profession-"..p[1],"professions",p[2].." 1–300",p[3].." 1–300",function()return professionSections(p)end,"Interface\\Icons\\Trade_Engineering")end
function A.GuideLibrary()return BOOKS end
function A.GuideArticle(id)for _,b in ipairs(BOOKS)do if b.id==id then return{id=id,title=tr(b.en,b.cs),category=b.category,sections=b.sections(),icon=b.icon}end end end
local function readStore()if not A.db then return{}end;if type(A.db.guideRead)~="table"then A.db.guideRead={}end;return A.db.guideRead end
local function follow(action)
 if not action then return end
 local kind,id=action:match("^([^:]+):(.+)$")
 if kind=="navigate"then
  local map,x,y,title=id:match("^(%d+):([%d%.]+):([%d%.]+):(.+)$")
  map,x,y=tonumber(map),tonumber(x),tonumber(y)
  if map and x and y and x>=0 and x<=1 and y>=0 and y<=1 and A.NavigateToPoint then
   local ok,reason=A.NavigateToPoint(title,map,x,y,{view="guides"})
   if not ok then A.Print(A.L(reason=="map_off" and "navErr_map_off" or "navNoMap"))end
  end
 elseif kind=="item"then if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item",tonumber(id))end
 elseif kind=="recipe"then A.ShowView("recipes");if A.map and A.map.OpenRecipe then A.map.OpenRecipe(tonumber(id))end
 elseif kind=="gather"then A.ShowView("world");if A.map and A.map.SetGatherType then A.map.SetGatherType(id,true)end;if A.worldBody and A.map then A.worldBody.mode="gather";A.map.RefreshWorld(A.worldBody)end
 else A.ShowView(action)end
end
local function parchment(frame,kit)
 if A.NativeParchment then return A.NativeParchment(frame,kit.C)end
 kit.fill(frame,kit.C.well,1);kit.outline(frame,kit.C.line or kit.C.gold)
 return{ink=kit.C.text,mutedInk=kit.C.mist,heading=kit.C.bright or kit.C.gold}
end
function A.BuildGuidesPage(page,kit)
 local C=kit.C;kit.PageHeader(page,"guides")
 local g={rows={},sections={},category="all",query="",selected="leveling"};page.guides=g
 g.search=kit.SearchBox(page,240,function(value)g.query=value or"";g.renderKey=nil;if page.Refresh then page.Refresh()end end);g.search:SetPoint("TOPLEFT",0,-57)
 g.progress=kit.label(page,11,C.mist);g.progress:SetPoint("TOPRIGHT",0,-65)
 g.tabs={};for i,pair in ipairs({{"all","guideAll"},{"professions","guideProfessions"},{"classes","guideClasses"},{"leveling","guideLeveling"},{"dungeons","guideDungeons"}})do
  local key=pair[1];local chip=kit.Chip(page,function()g.category=key;g.renderKey=nil;page.Refresh()end);chip.SetLabel(A.L(pair[2]));chip.key=key;chip.localeKey=pair[2]
  if i==1 then chip:SetPoint("TOPLEFT",0,-94)else chip:SetPoint("LEFT",g.tabs[i-1],"RIGHT",5,0)end;g.tabs[i]=chip
 end
 g.list=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate");g.list:SetPoint("TOPLEFT",0,-130);g.list:SetPoint("BOTTOMLEFT",0,5);g.list:SetWidth(190)
 g.listContent=CreateFrame("Frame",nil,g.list);g.listContent:SetSize(174,1000);g.list:SetScrollChild(g.listContent)
 g.index=CreateFrame("Frame",nil,page);g.index:SetPoint("TOPLEFT",g.list,"TOPLEFT",-1,1);g.index:SetPoint("BOTTOMRIGHT",g.list,"BOTTOMRIGHT",1,-1)
 if g.index.SetFrameLevel and g.list.GetFrameLevel then g.index:SetFrameLevel(math.max(0,(g.list:GetFrameLevel()or 1)-1))end
 A.NativePanel(g.index,C)
 g.panel=CreateFrame("Frame",nil,page);g.panel:SetPoint("TOPLEFT",g.list,"TOPRIGHT",22,0);g.panel:SetPoint("BOTTOMRIGHT",0,5);g.palette=parchment(g.panel,kit)
 g.reader=CreateFrame("ScrollFrame",nil,g.panel,"UIPanelScrollFrameTemplate");g.reader:SetPoint("TOPLEFT",16,-15);g.reader:SetPoint("BOTTOMRIGHT",-29,52)
 g.content=CreateFrame("Frame",nil,g.reader);g.content:SetSize(350,800);g.reader:SetScrollChild(g.content)
 g.title=kit.label(g.content,22,g.palette.heading);g.title:SetPoint("TOPLEFT");g.title:SetPoint("TOPRIGHT");g.title:SetJustifyV("TOP")
 g.mark=kit.Button(g.panel,"guideRead",150,"ghost",function()readStore()[g.selected]=not readStore()[g.selected]or nil;page.Refresh()end);g.mark:SetPoint("BOTTOMLEFT",14,12)
 g.next=kit.Button(g.panel,"guideNext",126,"primary",function()for i,b in ipairs(g.results or{})do if b.id==g.selected and g.results[i+1]then g.selected=g.results[i+1].id;g.renderKey=nil;break end end;page.Refresh()end);g.next:SetPoint("BOTTOMRIGHT",-14,12)
 local function renderArticle()
  local article=A.GuideArticle(g.selected);if not article then return end
  local savedScroll=g.article and g.article.id==article.id and(g.reader:GetVerticalScroll()or 0)or 0
  local width=math.max(180,(g.panel:GetWidth()or 400)-48);g.content:SetWidth(width);g.title:SetText(article.title);g.title:SetWidth(width)
  local y=math.max(30,g.title:GetStringHeight()or 30)+20
  for _,frame in ipairs(g.sections)do frame:Hide()end
  for index,spec in ipairs(article.sections)do
   local frame=g.sections[index]
   if not frame then
    frame=CreateFrame("Frame",nil,g.content);frame.head=kit.label(frame,15,g.palette.heading);frame.head:SetPoint("TOPLEFT");frame.head:SetPoint("TOPRIGHT");frame.head:SetJustifyV("TOP")
    frame.text=kit.label(frame,13,g.palette.ink);frame.text:SetJustifyV("TOP");frame.text:SetJustifyH("LEFT")
    frame.action=kit.Button(frame,nil,160,"ghost",function(self)follow(self.actionKey)end);g.sections[index]=frame
   end
   frame:ClearAllPoints();frame:SetPoint("TOPLEFT",0,-y);frame:SetWidth(width);frame.head:SetWidth(width);frame.head:SetText(spec.title)
   local hh=math.max(18,frame.head:GetStringHeight()or 18);frame.text:ClearAllPoints();frame.text:SetPoint("TOPLEFT",0,-hh-6);frame.text:SetPoint("TOPRIGHT",0,-hh-6);frame.text:SetWidth(width);frame.text:SetText(spec.body or"")
   local th=spec.body~=""and math.max(14,frame.text:GetStringHeight()or 14)or 0;local height=hh+6+th
   frame.action:SetShown(spec.action~=nil);frame.action.actionKey=spec.action
   if spec.action then
    frame.action:ClearAllPoints();frame.action:SetPoint("TOPLEFT",0,-height-9)
    local actionKind=spec.action:match("^([^:]+)")
    frame.action.text:SetText(A.L(actionKind=="navigate"and"guideNavigate"or actionKind=="recipe"and"guideRecipe"or actionKind=="gather"and"guideMap"or actionKind=="talents"and"guideTalents"or actionKind=="recipes"and"guideRecipes"or actionKind=="item"and"openDatabase"or spec.action));height=height+42
   end
   frame:SetHeight(height);frame:Show();y=y+height+20
  end
  g.content:SetHeight(y+10);g.reader:SetVerticalScroll(math.min(savedScroll,math.max(0,y+10-(g.reader:GetHeight()or 0))));g.article=article
 end
 function page.Refresh()
  local read=readStore();local count=0;for _,b in ipairs(BOOKS)do if read[b.id]then count=count+1 end end;g.progress:SetText(string.format(A.L("guideProgress"),count,#BOOKS))
  for _,chip in ipairs(g.tabs)do chip.SetLabel(A.L(chip.localeKey));chip.SetOn(chip.key==g.category)end
  local query=kit.fold(g.query);g.results={}
  for _,b in ipairs(BOOKS)do if(g.category=="all"or b.category==g.category)and kit.fold(b.en.." "..b.cs):find(query,1,true)then g.results[#g.results+1]=b end end
  local selected=false;for _,b in ipairs(g.results)do if b.id==g.selected then selected=true end end
  if not selected and #g.results>0 then g.selected=g.results[1].id;g.renderKey=nil end
  for _,row in ipairs(g.rows)do row:Hide()end
  for i,b in ipairs(g.results)do local row=g.rows[i]
   if not row then
    row=CreateFrame("Button",nil,g.listContent);row:SetHeight(52);row.bg=kit.fill(row,C.card,1);row.edge=kit.fill(row,C.gold,0,"ARTWORK")
    row.accent=row:CreateTexture(nil,"OVERLAY");row.accent:SetPoint("TOPLEFT");row.accent:SetPoint("BOTTOMLEFT");row.accent:SetWidth(2);kit.paint(row.accent,C.gold,1)
    local hover=row:CreateTexture(nil,"HIGHLIGHT");hover:SetAllPoints(row);kit.paint(hover,C.gold,.10)
    row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(26,26);row.icon:SetPoint("LEFT",9,0)
    row.title=kit.label(row,12,C.text);row.title:SetPoint("TOPLEFT",43,-10);row.title:SetPoint("TOPRIGHT",-8,-10);row.title:SetHeight(34);row.title:SetWordWrap(true);row.title:SetJustifyV("TOP")
    row:SetScript("OnClick",function(self)g.selected=self.chapter.id;g.renderKey=nil;page.Refresh()end);g.rows[i]=row
   end
   row.chapter=b;row:ClearAllPoints();row:SetPoint("TOPLEFT",3,-(i-1)*56-3);row:SetPoint("TOPRIGHT",-3,-(i-1)*56-3);row.icon:SetTexture(b.icon);row.title:SetText((read[b.id]and"• "or"")..tr(b.en,b.cs));row.edge:SetAlpha(b.id==g.selected and.14 or 0);row.accent:SetShown(b.id==g.selected);row:Show()
  end
  g.listContent:SetHeight(math.max(1,#g.results*56+6))
  local key=tostring(g.selected)..":"..tostring(cz())..":"..tostring(g.panel:GetWidth())
  if key~=g.renderKey and #g.results>0 then renderArticle();g.renderKey=key end
  g.panel:SetShown(#g.results>0);g.mark.text:SetText(A.L(read[g.selected]and"guideReadDone"or"guideRead"))
 end
 local function layout(_,width)
  width=tonumber(width)or page:GetWidth()or 640;if width<300 then width=640 end
  g.list:SetWidth(math.max(170,math.min(270,width*.32)));g.listContent:SetWidth(g.list:GetWidth()-18)
  g.search:SetWidth(math.max(180,math.min(280,width*.48)))
  local bw=math.max(96,math.min(150,((g.panel:GetWidth()or 350)-40)/2));g.mark:SetWidth(bw);g.next:SetWidth(bw)
  g.renderKey=nil;if page:IsShown()and page.Refresh then page.Refresh()end
 end
 page:SetScript("OnSizeChanged",layout);page.Layout=layout
end

