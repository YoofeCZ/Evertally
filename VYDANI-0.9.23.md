# Evertally 0.9.23 — výběr jmenovek a živý náhled

- Průvodce nejprve nabídne **Blizzard** nebo **Evertally — doporučujeme**. Výběr se ihned aktivuje. Po výběru Evertally se otevře úprava vzhledu.
- Změny jmenovek v průvodci i Nastavení platí okamžitě. Ostatní volby průvodce se nadále ukládají až při Dokončit. Přeskočení průvodce nevrací již použité změny jmenovek.
- Pevný náhled nad ovládacími prvky používá stejný kód písma, ikon, aur, zdraví a kouzlení jako vykreslení nad hráči. Obsahuje vlastní jméno včetně příjmení a označené ukázkové ikony a aury. Měřítko se přizpůsobí prostoru náhledu. Nastavení pod ním se posouvá samostatně.
- Pět fontů: herní font, Friz Quadrata, Arial Narrow, Morpheus a Skurri. Volitelný obrys a stín.
- Samostatná velikost jména, značky a loga, celkové měřítko, posuny celé jmenovky a obou ikon vlevo/vpravo i nahoru/dolů.
- Nastavení dosahu mění `nameplateMaxDistance` a `nameplatePlayerMaxDistance` mimo boj. Zobrazuje hodnotu přijatou klientem, nikoli neověřený požadovaný dosah. Mimo dosah, kde hra neposkytuje nativní jmenovku pro přichycení, zůstává původní jméno Blizzardu.
- Oprava příjmení: na Forever je druhá hodnota `UnitName` příjmení, nikoli realm. Pro vykreslení a nové akce nabídky se používá celé jméno; realm se čte samostatně.
- Podporované nabídky portrétu, skupiny, raidu, přítele a vlastního hráče mají sekci Evertally: osobní značka, výběr jiné ikony, odebrání značky, navigace k hráči, Evertally inspect a nastavení jmenovek. Cíl akce zůstává hráč vybraný při otevření nabídky. Navigace použije sdílenou polohu, případně dostupnou nativní mapovou polohu. Inspect používá dosavadní žádost a souhlas druhého hráče.
- Nabídky se nerozšiřují během boje nebo při skryté identitě jednotky; nepřepisují se nativní UnitPopup tabulky.

Přibyly soubory v TOC: po instalaci WoW úplně ukonči a znovu spusť. Průvodce otevře `/etally setup`; jmenovky jsou krok 7. Nastavení otevře také pravé kliknutí na portrét → Evertally → Nastavení jmenovek.

Windows Bridge zůstává 0.9.8. Testy a izolované náhledy neověřují skutečný vzhled, dosah ani dostupnost menu v běžícím WoW. Kvůli této změně se herní okno automaticky neovládalo.

Podklady k API: [UnitPopup klienta Forever](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_UnitPopupShared/UnitPopupShared.lua), [příjmení v API Forever](https://github.com/ATTWoWAddon/AllTheThings/issues/2630), [proměnné dosahu klienta](https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/forever/Resources/CVars.lua). Číselná horní hranice viditelnosti nebyla ve hře ověřena.
