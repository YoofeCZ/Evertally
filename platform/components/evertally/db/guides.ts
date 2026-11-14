// Curated outside resources (checked live 2026-11-10) and short Evertally how-tos.
// Descriptions are written by us from each site's own summary; external sites are not operated by Evertally.
export type Resource = { id: string; url: string; name: string; en: string; cs: string; tags: string[] };
export type HowTo = { id: string; title: { en: string; cs: string }; steps: { en: string; cs: string }[] };

export const RESOURCES: Resource[] = [
  { id: "wowhead", url: "https://www.wowhead.com/forever", name: "Wowhead Forever", tags: ["database", "guides"], en: "The largest WoW Forever site: class and profession guides, best-in-slot lists, a quest database and a talent calculator.", cs: "Největší web o WoW Forever: návody ke classám a profesím, BiS seznamy, databáze questů a kalkulačka talentů." },
  { id: "foreverbase", url: "https://foreverbase.org/en/", name: "foreverbase", tags: ["database", "maps", "addons"], en: "Guides, a database and maps for WoW Forever, plus a catalogue of addons that work on Forever.", cs: "Návody, databáze a mapy pro WoW Forever a katalog addonů, které na Forever fungují." },
  { id: "foreverera", url: "https://theforeverera.com/en/", name: "The Forever Era", tags: ["database", "maps", "builds"], en: "Talent calculator, best-in-slot by class and level, map, dungeons and every change from Classic, build by build.", cs: "Kalkulačka talentů, BiS podle classy a levelu, mapa, dungeony a všechny změny oproti Classicu, build po buildu." },
  { id: "foreverchanges", url: "https://foreverchanges.pro/", name: "ForeverChanges", tags: ["changes", "talents"], en: "Latest Forever updates and patch notes, class buffs and nerfs, and everything Forever changes from Classic.", cs: "Poslední aktualizace Forever a patch notes, buffy a nerfy classů a všechno, co Forever mění oproti Classicu." },
  { id: "wowf", url: "https://wowf.io/en/", name: "WOWF.IO", tags: ["talents", "maps", "dungeons"], en: "Talent calculator and spellbook for all nine classes, race and class combinations with reworked racials, maps and dungeon guides.", cs: "Kalkulačka talentů a kniha kouzel pro všech devět classů, kombinace ras a class s přepracovanými rasovými schopnostmi, mapy a návody k dungeonům." },
  { id: "forevertalents", url: "https://wowforevertalents.com/", name: "WoW Forever Talents", tags: ["talents", "quests", "dungeons"], en: "Talent calculator for all nine classes with 51 points, plus quest and dungeon pages.", cs: "Kalkulačka talentů pro všech devět classů s 51 body a stránky s questy a dungeony." },
  { id: "foreverguides", url: "https://theforeverguides.com/", name: "Forever Guides", tags: ["guides", "gold", "professions"], en: "Researched class guides, gold and profession guides, trackers, tools and daily news.", cs: "Důkladné návody ke classám, goldu a profesím, trackery, nástroje a denní novinky." },
  { id: "wowsrc", url: "https://wowsrc.com/", name: "WoW Source", tags: ["tools", "dungeons", "professions"], en: "Tools and guides: Legacy planner, dungeon list, class changes and professions.", cs: "Nástroje a návody: plánovač Legacy, seznam dungeonů, změny classů a profese." },
];

export const HOWTOS: HowTo[] = [
  {
    id: "start", title: { en: "Getting started with Evertally", cs: "První kroky s Evertally" },
    steps: [
      { en: "Install the addon with the Evertally installer (or copy the two addon folders into Interface/AddOns), then fully restart WoW.", cs: "Nainstaluj addon instalátorem Evertally (nebo zkopíruj obě složky addonu do Interface/AddOns) a úplně restartuj WoW." },
      { en: "In game type /etally. The window shows your own history. Nothing leaves your PC until you turn on web export.", cs: "Ve hře napiš /etally. Okno ukazuje tvoji vlastní historii. Nic neopustí tvůj počítač, dokud nezapneš webový export." },
      { en: "Run a dungeon: the timer starts at the first pull; bosses are recorded when they die. A /reload interrupts the measurement and marks it as such.", cs: "Projdi dungeon: čas začne prvním pullem a bossové se zapisují po smrti. /reload měření přeruší a označí ho." },
    ],
  },
  {
    id: "sync", title: { en: "Upload your data (optional)", cs: "Nahrání dat na web (volitelné)" },
    steps: [
      { en: "Type /etally web on in game, choose what may be shared, then /reload so the game writes the export file.", cs: "Ve hře napiš /etally web on, vyber, co se smí sdílet, a dej /reload, aby hra zapsala exportní soubor." },
      { en: "Open Web sync from Evertally Bridge next to the Windows clock, choose Pair this PC, sign in with Discord on the website and approve the code. New records upload after each /reload or logout.", cs: "Z ikony Evertally Bridge vedle hodin Windows otevři Web sync, vyber Spárovat tento počítač, přihlas se na webu přes Discord a potvrď kód. Nové záznamy se odesílají po každém /reload nebo odhlášení." },
      { en: "Profiles stay private until you publish them. Public profiles and community layers never show exact player positions, only visited zones. The optional My route and My guild choices are off by default.", cs: "Profily zůstávají soukromé, dokud je nezveřejníš. Veřejné profily a komunitní vrstvy nikdy neukazují přesné polohy hráčů, jen navštívené oblasti. Dobrovolná Moje trasa a Můj cech jsou ve výchozím stavu vypnuté." },
    ],
  },
  {
    id: "sources", title: { en: "How to read this database", cs: "Jak číst tuto databázi" },
    steps: [
      { en: "NPCs, quests and spawn points come from QuestieDB; item tooltips and loot sources from a Forever item cache snapshot; dungeon facts from the DungeonJournal addon.", cs: "NPC, questy a body výskytu pocházejí z QuestieDB; tooltipy itemů a zdroje lootu z cache itemů pro Forever; fakta o dungeonech z addonu DungeonJournal." },
      { en: "Drop chances are shown only where a source provides them. A loot source is not a measured drop rate, and a snapshot can lag behind the live game.", cs: "Šance na drop se ukazují jen tam, kde je zdroj uvádí. Zdroj lootu není změřená šance a snímek může za živou hrou zaostávat." },
      { en: "Items marked as having no tooltip are known to the quest database but missing from the item cache; their facts are limited.", cs: "Itemy označené jako bez tooltipu zná databáze questů, ale chybí v cache itemů; jejich údaje jsou omezené." },
    ],
  },
];
