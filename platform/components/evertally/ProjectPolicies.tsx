"use client";
import { useEffect } from "react";
import Link from "next/link";
import { useI18n } from "@/lib/i18n";
import { Logo } from "./ui";

type PolicyPage = "privacy" | "terms";
type Section = { title: string; paragraphs: string[] };

const content = {
  en: {
    home: "Back to Evertally", privacy: "Privacy and data", terms: "Project rules", account: "Manage my web data", language: "Language",
    privacyLead: "What the addon keeps locally, what you can choose to share, and what remains after deleting web data.",
    termsLead: "Practical rules for this developing fan project and its community observations.",
    privacySections: [
      { title: "Local play and what the website gets", paragraphs: [
        "The WoW addon works offline. Once you install the Evertally app and pair it with the website, the addon sends everything it records: your characters, runs and bosses, quests, loot, professions, stats, talents and gear, your route and your guild. There is no choice per kind of data. Exact player positions are discarded from world facts; your route is the exception and is part of your public chronicle.",
        "Runs and the chronicle also show the names, classes and roles of the people you grouped with, as the game showed them to you. Records received from other players through the addon (what they let you see in the game) are kept separately and are never forwarded as your web export.",
      ] },
      { title: "Discord sign-in", paragraphs: [
        "Sign-in requests Discord's identify scope. Evertally receives your Discord identifier, username/display name and avatar information to recognise your account. It does not request your Discord password, email address, direct messages or friends list.",
        "The website uses the HttpOnly et_session cookie for a login session lasting up to 30 days. The OAuth state used to connect a sign-in attempt expires after 10 minutes. The EN/CS language choice is stored on your device in localStorage under et_lang.",
      ] },
      { title: "Public data", paragraphs: [
        "Like raider.io, every character recorded with Evertally is public on the website: its leaderboard places, runs, the chronicle (the journey replay with the route walked), stats, talents, professions and the armory (gear). The bags are the exception: another player sees them only after you allow it in the game.",
        "Zone activity is a delayed aggregate of distinct contributing accounts over 24 hours, shown only from three contributors per zone. It is not a live player tracker or a count of everyone online.",
        "Shared world facts contribute to the public atlas. The community package contains anonymous world-fact summaries, with a maximum of 150 entities and 48 KiB. It carries a generation time and a seven-day expiry. An addon can keep an expired package as a visibly stale offline cache.",
        "Hiding or deleting web data affects the current service. Copies of public profiles or community packages already downloaded by other people cannot be recalled from their devices.",
      ] },
      { title: "Your route, guild, groups and meets", paragraphs: [
        "The addon records where your characters walked, as map points, while the app is paired. The route is kept for 30 days and shown in your public chronicle; it is not used for zone activity.",
        "“My guild” sends which guild your character is in; the addon of a guild master also sends the member list (character names, levels and classes) so members can be recognised. Nothing is shown to a guild until you confirm that guild on the map and choose what to share: nothing, your last position, or your last position and route for 72 hours. Only members who confirmed the same guild see each other.",
        "The server cannot check a guild rank. The first guild master to upload a member list owns it, and the map names that character before you confirm. A position is only as fresh as your last /reload or logout, because the game saves it only then. Leaving the guild in game, being dropped from the next member list, revoking the consent or deleting your web data ends the visibility.",
        "A group (a party, a raid, friends) is created on the website and joined with an invite code. Everyone in it chooses what to share (nothing, last position, or last position and route) and can change or stop that at any time; the owner can remove members. A meet is a place and a time somebody proposes: it shows the place the creator picked, never where they are, to the guild or group they chose, or to anyone signed in who has its link. Answers show the name the responder chose. Meets are dropped a week after they end; leaving a group removes your answers to its meets.",
        "Looking at another player's gear, bags, professions or gold happens only inside the game, between two players with the addon, and only after the other player answers a request and ticks what to show. It never reaches the website, is not saved and does not enter any export. Trade proposals and meet points sent in the game are plain messages between the players involved.",
        "Live position is a separate in-game choice, off by default, for party / raid and for the guild. While it is on and you move, the addon sends your zone, your spot on it and your class to that channel about every five seconds, to players who run the addon. It is never uploaded to the website or saved, and the addon window shows a LIVE badge as long as it is on. Pings (one point, shown for five minutes) and the pins on the world map and minimap work the same way: only inside the game, only for the group or guild you sent them to.",
        "Your live position on the website has three further choices, each off until you turn it on and each ending at once when you turn it off: friends (both of you agreed, by Discord name), everyone who is signed in, and everyone including visitors who are not signed in. Only the live position is shown this way: never your route, never older positions, and only while the game is open, the bridge is running and your consent for route and character is on. A visitor who is not signed in sees the name, class, level and spot of the characters whose owners chose that, and nothing that identifies the account. In the game, a separate switch whispers your live position to the friends on your friends list who run the addon; a whispered position counts only from someone on the receiver's own friends list.",
      ] },
      { title: "Hosting and storage", paragraphs: [
        "The web service uses Cloudflare hosting and D1. The project's production D1 database has EU jurisdiction. Web requests, asset delivery and CDN processing use Cloudflare's global infrastructure.",
        "The Windows bridge reads Evertally's separate consent-filtered export for synchronisation. It does not collect your full WTF folder, unrelated addon files, private chat contents or passwords. Local synchronisation logs describe status and errors.",
      ] },
      { title: "Changing your choices and deleting web data", paragraphs: [
        "Characters can no longer be hidden one by one. To stop sharing, disconnect the device or revoke the upload consent in Account, or delete your web data. Disabling export in the game changes future saved exports; the file on disk is refreshed when WoW saves it, for example after /reload or logout.",
        "Delete my web data removes uploaded observations, character profiles and upload history, and revokes grants and devices. The login account's Discord identity and security records for revoked grants/devices remain stored. This action therefore does not delete every account-related record. Your local addon history is unchanged.",
      ] },
      { title: "How to read the data", paragraphs: [
        "The atlas represents observations shared by participating players. It is not a complete inventory of the realm. A sighting count is not a drop rate. Saved times are addon observations; an observed final-boss kill does not establish a full clear or a verified speed record.",
      ] },
    ] satisfies Section[],
    termsSections: [
      { title: "Contribute genuine observations", paragraphs: [
        "Upload your own observations through the supported export flow and the scopes you chose. Do not fabricate game records, impersonate another character or present received peer reports as your own observations. Do not use the service to intentionally disrupt other users or overload the project.",
      ] },
      { title: "Respect sharing choices", paragraphs: [
        "Web sharing, public profiles and ingame sharing are separate choices. Keep private data private and respect other players' decisions. A downloadable community package is a snapshot of shared world facts and stays separate from personally observed addon data.",
      ] },
      { title: "Keep results in context", paragraphs: [
        "Do not describe unverified addon times as official speed records. Last-boss finishes, full clears, interrupted timers and manual endings have different meanings. Race and class filters describe participants; they are not evidence of individual skill or a class's performance.",
        "Counts are based on the available sample. Several members of one group can report separate participations in the same visit. Vendor stock, positions, recipes and cooldown snapshots can become outdated.",
      ] },
      { title: "A developing fan project", paragraphs: [
        "Evertally is a fan project and is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and related names belong to their respective owners.",
        "The project is still being developed. Features, availability and the set of tested game scenarios can change. Check the displayed source, age and verification information before relying on a record. These pages describe current project behaviour and usage rules.",
      ] },
    ] satisfies Section[],
  },
  cs: {
    home: "Zpět na Evertally", privacy: "Soukromí a data", terms: "Pravidla projektu", account: "Spravovat moje webová data", language: "Jazyk",
    privacyLead: "Co addon uchovává místně, co můžeš sdílet a co zůstává po smazání webových dat.",
    termsLead: "Praktická pravidla rozvíjeného fanouškovského projektu a jeho komunitních pozorování.",
    privacySections: [
      { title: "Místní hraní a co dostane web", paragraphs: [
        "WoW addon funguje offline. Jakmile nainstaluješ aplikaci Evertally a spáruješ ji s webem, addon posílá všechno, co zaznamená: tvoje postavy, běhy a bossy, questy, kořist, profese, statistiky, talenty a výbavu, tvoji trasu a tvůj cech. Volba podle druhu dat není. Přesné pozice hráčů se z faktů o světě odstraňují; výjimkou je tvoje trasa, která je součástí tvé veřejné kroniky.",
        "Běhy a kronika ukazují i jména, classy a role lidí, se kterými jsi hrál ve skupině, tak jak ti je ukázala hra. Záznamy přijaté od jiných hráčů přes addon (co ti dovolili vidět ve hře) addon uchovává odděleně a nikdy je nepřidává do tvého webového exportu.",
      ] },
      { title: "Přihlášení přes Discord", paragraphs: [
        "Přihlášení žádá oprávnění Discord identify. Evertally obdrží tvůj Discord identifikátor, uživatelské či zobrazované jméno a údaje o avataru, aby poznal tvůj účet. Nežádá tvé heslo k Discordu, e-mail, soukromé zprávy ani seznam přátel.",
        "Web používá HttpOnly cookie et_session pro přihlášení až na 30 dnů. OAuth stav propojující pokus o přihlášení vyprší po 10 minutách. Volba jazyka EN/CS se ukládá na tvém zařízení do localStorage pod klíčem et_lang.",
      ] },
      { title: "Veřejná data", paragraphs: [
        "Stejně jako na raider.io je každá postava zaznamenaná přes Evertally na webu veřejná: umístění v žebříčcích, běhy, kronika (přehrávání cesty včetně trasy), statistiky, talenty, profese a Armory (výbava). Výjimkou je batoh: jiný hráč ho uvidí, jen když mu to povolíš ve hře.",
        "Aktivita oblastí je souhrn různých přispívajících účtů za 24 hodin, zveřejněný až od tří přispěvatelů v oblasti. Nejde o živé sledování hráčů ani počet všech online hráčů.",
        "Sdílená fakta o světě doplňují veřejný atlas. Komunitní balíček obsahuje anonymní souhrny faktů o světě, nejvýše 150 entit a 48 KiB. Nese čas vytvoření a platnost sedm dnů. Addon může prošlý balíček ponechat jako viditelně zastaralou místní mezipaměť.",
        "Skrytí či smazání webových dat se projeví v aktuální službě. Kopie veřejných profilů nebo komunitních balíčků, které si již stáhli jiní lidé, nelze odvolat z jejich zařízení.",
      ] },
      { title: "Tvoje trasa, cech, skupiny a srazy", paragraphs: [
        "Addon zaznamenává, kudy tvoje postavy šly, jako body na mapě, dokud je aplikace spárovaná. Trasa se uchovává 30 dní a je vidět ve tvé veřejné kronice; pro aktivitu oblastí se nepoužívá.",
        "„Můj cech“ pošle, v jakém cechu je postava; addon guildmastera pošle navíc seznam členů (jména postav, levely a classy), aby šlo členy poznat. Cechu se nic nezobrazí, dokud na mapě cech nepotvrdíš a nezvolíš, co sdílet: nic, poslední polohu, nebo poslední polohu a trasu za 72 hodin. Vidí se jen členové, kteří potvrdili stejný cech.",
        "Server hodnost v cechu ověřit neumí. Seznam členů vlastní první guildmaster, který ho nahraje, a mapa jeho postavu před potvrzením pojmenuje. Poloha je jen tak čerstvá jako poslední /reload nebo odhlášení, protože hra ji ukládá jen tehdy. Odchod z cechu ve hře, vynechání v dalším seznamu členů, odvolání souhlasu nebo smazání webových dat viditelnost ukončí.",
        "Skupina (parta, raid, kamarádi) se založí na webu a připojuje se kódem pozvánky. Každý v ní volí, co sdílí (nic, poslední polohu, nebo poslední polohu i trasu), a může to kdykoli změnit či ukončit; majitel může členy odebrat. Sraz je místo a čas, které někdo navrhne: ukáže místo, které autor vybral, nikdy kde je, cechu nebo skupině podle jeho volby, nebo komukoli přihlášenému, kdo má odkaz. Odpovědi ukazují jméno, které si odpovídající zvolil. Srazy se týden po skončení smažou; odchodem ze skupiny zmizí tvoje odpovědi na její srazy.",
        "Pohled do výbavy, tašek, profesí nebo zlata jiného hráče se děje jen ve hře, mezi dvěma hráči s addonem, a jen když druhý hráč na žádost odpoví a zaškrtne, co ukáže. Nikdy to nejde na web, neukládá se a nevstupuje do žádného exportu. Návrhy výměn a body srazů poslané ve hře jsou obyčejné zprávy mezi zúčastněnými hráči.",
        "Živá poloha je samostatná volba ve hře, ve výchozím stavu vypnutá, zvlášť pro partu / raid a pro cech. Dokud je zapnutá a hýbeš se, addon posílá zhruba každých pět sekund tvoji zónu, místo v ní a classu do toho kanálu hráčům, kteří addon mají. Nikdy se nenahrává na web ani neukládá a v okně addonu svítí štítek ŽIVĚ, dokud je zapnutá. Pingy (jeden bod, vidět pět minut) a body na světové mapě a minimapě fungují stejně: jen ve hře a jen pro skupinu nebo cech, kterým jsi je poslal.",
        "Tvoje živá poloha na webu má další tři volby, každou vypnutou, dokud ji nezapneš, a každá po vypnutí končí hned: přátelé (oba souhlasíte, přes Discord jméno), všichni přihlášení a úplně všichni včetně návštěvníků, kteří nejsou přihlášení. Takhle se ukazuje jen živá poloha: nikdy trasa, nikdy starší polohy, a jen když je hra zapnutá, most běží a máš zapnutý souhlas s trasou a postavou. Nepřihlášený návštěvník vidí jméno, classu, úroveň a místo u postav, jejichž majitelé to zvolili, a nic, co by identifikovalo účet. Ve hře samostatný přepínač pošle tvoji živou polohu šeptem přátelům ze seznamu přátel, kteří mají addon; poloha poslaná šeptem platí jen od někoho, kdo je na seznamu přátel příjemce.",
      ] },
      { title: "Hosting a ukládání", paragraphs: [
        "Web využívá hosting Cloudflare a D1. Produkční databáze D1 projektu má jurisdikci EU. Webové požadavky, doručování souborů a zpracování CDN používají globální infrastrukturu Cloudflare.",
        "Most pro Windows čte samostatný export Evertally omezený souhlasem pro synchronizaci. Nesbírá celou složku WTF, soubory nesouvisejících addonů, obsah soukromých chatů ani hesla. Místní synchronizační log popisuje stav a chyby.",
      ] },
      { title: "Změna voleb a smazání webových dat", paragraphs: [
        "Jednotlivé postavy už skrýt nejde. Sdílení zastavíš odpojením zařízení nebo odvoláním souhlasu s uploadem v Účtu, případně smazáním webových dat. Vypnutí exportu ve hře změní budoucí uložené exporty; soubor na disku se obnoví až při uložení WoW, například po /reload nebo odhlášení.",
        "Smazat moje webová data odstraní nahraná pozorování, profily postav a historii uploadů a odvolá souhlasy i zařízení. Discord identita přihlašovacího účtu a bezpečnostní záznamy odvolaných souhlasů či zařízení zůstávají uložené. Tato akce tedy nemaže každý záznam související s účtem. Místní historie addonu zůstává beze změny.",
      ] },
      { title: "Jak údaje číst", paragraphs: [
        "Atlas obsahuje pozorování sdílená zapojenými hráči. Není úplným přehledem realmu. Počet pozorování není šance na získání předmětu. Uložené časy jsou pozorování addonu; zaznamenané zabití posledního bosse nedokládá úplné vyčištění ani ověřený rychlostní rekord.",
      ] },
    ] satisfies Section[],
    termsSections: [
      { title: "Přispívej skutečnými pozorováními", paragraphs: [
        "Nahrávej vlastní pozorování podporovaným exportem a pouze ve zvolených oblastech souhlasu. Nevymýšlej herní záznamy, nevydávej se za jinou postavu a nepředkládej přijaté záznamy spoluhráčů jako vlastní pozorování. Nepoužívej službu k úmyslnému narušování ostatních uživatelů nebo přetěžování projektu.",
      ] },
      { title: "Respektuj volby sdílení", paragraphs: [
        "Webové sdílení, veřejný profil a sdílení ve hře jsou samostatné volby. Zachovávej soukromí neveřejných údajů a respektuj rozhodnutí ostatních hráčů. Stažitelný komunitní balíček je snímek sdílených faktů o světě a zůstává oddělený od vlastních pozorování addonu.",
      ] },
      { title: "Uváděj výsledky v souvislostech", paragraphs: [
        "Neoznačuj neověřené časy addonu za oficiální rychlostní rekordy. Dokončení posledního bosse, úplné vyčištění, přerušené měření a ruční ukončení mají odlišný význam. Filtry rasy a classy popisují účastníky; nedokládají individuální dovednost ani výkon dané classy.",
        "Počty vycházejí z dostupného vzorku. Více členů jedné skupiny může zaznamenat vlastní účast v téže návštěvě. Nabídky obchodníků, polohy, recepty a snímky cooldownů mohou zastarat.",
      ] },
      { title: "Rozvíjený fanouškovský projekt", paragraphs: [
        "Evertally je fanouškovský projekt bez spojení či schválení společností Blizzard Entertainment. World of Warcraft a související názvy patří příslušným vlastníkům.",
        "Projekt se dále vyvíjí. Funkce, dostupnost a rozsah otestovaných herních scénářů se mohou měnit. Při používání záznamu sleduj uvedený původ, stáří a stav ověření. Tyto stránky popisují aktuální fungování a pravidla projektu.",
      ] },
    ] satisfies Section[],
  },
};

export function ProjectPolicies({ page }: { page: PolicyPage }) {
  const { lang, setLang } = useI18n();
  const text = content[lang];
  const sections = page === "privacy" ? text.privacySections : text.termsSections;
  useEffect(() => { document.documentElement.lang = lang; }, [lang]);
  return <>
    <header className="topbar">
      <Link className="brand" href="/" aria-label={text.home}><Logo /><strong>Evertally</strong></Link>
      <nav className="button-row" aria-label="Evertally"><Link className="link-btn" href="/privacy" aria-current={page === "privacy" ? "page" : undefined}>{text.privacy}</Link><Link className="link-btn" href="/terms" aria-current={page === "terms" ? "page" : undefined}>{text.terms}</Link></nav>
      <div className="segmented" aria-label={text.language}><button className={lang === "en" ? "on" : ""} aria-pressed={lang === "en"} onClick={() => setLang("en")}>EN</button><button className={lang === "cs" ? "on" : ""} aria-pressed={lang === "cs"} onClick={() => setLang("cs")}>CS</button></div>
    </header>
    <main className="page-column">
      <header className="page-head"><h1 className="serif-heading">{text[page]}</h1><p className="lead">{page === "privacy" ? text.privacyLead : text.termsLead}</p></header>
      <div style={{ display: "grid", gap: 16, paddingBottom: 64 }}>{sections.map((section) => <section className="chapter-card tint-navy" key={section.title}>
        <h2 className="serif-heading small">{section.title}</h2>{section.paragraphs.map((paragraph) => <p key={paragraph} style={{ margin: 0, lineHeight: 1.7, maxWidth: 900 }}>{paragraph}</p>)}
      </section>)}<div className="button-row"><Link className="btn btn-primary" href="/#account">{text.account}</Link><Link className="btn btn-ghost" href="/">{text.home}</Link></div></div>
    </main>
  </>;
}
