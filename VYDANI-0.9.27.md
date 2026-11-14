# Evertally 0.9.27 (Bridge zůstává 0.9.10)

**Web ve tvaru Raider.IO.** Žebříčky mají tlačítka Úroveň · Dokončení · Nejrychlejší časy · Instance · DPS · HPS · Cechy · Síň slávy · Statistiky a filtry třídy, rasy, frakce, realmu a role.

- **Cechy:** žebříček cechů podle poražených raid bossů (pak dokončení, členové, úroveň), stránka cechu s pořadím celkově i na realmu, raid progresí, zobrazenými členy a jejich posledními běhy. Cech tvoří jen veřejné postavy, jejichž hráči zapnuli „Cech“; soupis guildmastera se nikdy nepoužije.
- **Raid progrese** z boss fightů, které addon nahrává (`raid.encounter_finished`): u cechu i u postavy, „7/10“ podle databáze dungeonů (bez položek Trash, Tier sety, All bosses), první zabití a počet.
- **Síň slávy:** první tři cechy u každého raid bosse.
- **Statistiky:** frakce, úrovně, třídy, rasy, role a třídy, které dokončují dungeony a raidy.
- **Postava:** pořadí na realmu, spec a role (strom s nejvíc body; role podle anglického názvu stromu, jinak podle pořadí stromu), graf postupu úrovní (jen den, ne hodina), výbava, talenty a statistiky.
- **Přehled:** Nejlepší cechy; hledání postavy ukáže i odpovídající cechy.

**Nový souhlas „Výbava a talenty“** (výchozí vypnuto): na webu v Účtu i ve hře v Nastavení → Webový export („…s výbavou a talenty na stránce postavy (tašky nikdy)“). Teprve s ním web ukáže nasazené předměty, statistiky a talenty veřejné postavy a její spec a roli. Tašky a profese se nikdy nezveřejní. Platí novější volba, ať ve hře, nebo na webu.

**Pořadí vydání:** migrace `drizzle/0011_public_gear.sql` na produkční D1 → web → addon 0.9.27 (server se starým schématem by `character.publish` s `showGear` odmítl).

Ověřeno: web 265 testů, Lua 530, `tsc` a `eslint` celého webu, v prohlížeči na dočasných lokálních datech (smazána). Neověřeno ve hře: nový přepínač v Nastavení. Instalátor přestavěn s addonem 0.9.27; aplikace se nemění, mosty se tedy znovu neinstalují a addon si stáhnou samy. Z 0.9.26 stačí `/reload`.
