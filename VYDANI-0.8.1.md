# Evertally 0.8.1 — čitelné stránky a talentové API Forever

13. listopadu 2026. Opravy podle skutečných snímků z klienta po vydání 0.8.0.

- **Celý pergamenový panel má neprůhledný podklad.** Textura QuestBG má v tomto klientu průhlednou výplň; sama zakryla jen levý horní kus čtecí plochy. Čtecí stránky nyní mají vlastní plně neprůhledný podklad přes celou šířku a výšku. Společná oprava platí pro questy, recepty, návody i ostatní čtecí panely.
- **Spodní odkazy questů jsou čitelné.** Na tmavém řádku už není tmavý text.
- **Talenty používají API Forever.** Staré GetTalentInfo/GetNumTalentTabs v tomto klientu nejsou. Čtení nyní používá C_ClassTalents, C_Traits a C_Spell, včetně tří skupin, skutečných ranků, jmen, ikon, závislostí a spell tooltipů. Uložené buildy používají stabilní nodeID. Opožděně načtená konfigurace se obnoví při talentových událostech.
- Plánovač nadále mění jen místní plán; nevolá nákup, vracení ani potvrzování skutečných herních talentů. Starší Classic API zůstává pouze jako fallback pro jiné klienty.

Ověření zahrnuje osm regresí s výhradně C_Traits API a výslovně nepřítomnými GetTalent funkcemi, dva testy plného neprůhledného podkladu a kontroly rozložení. Náhled talentů nyní používá stejný moderní kontrakt; dřívější Classic maketa tuto chybu skrývala.

Aktualizace z 0.8.0 se načte příkazem `/reload`. Tyto opravy byly zkontrolované v kódu a oddělených náhledech; nové snímky přímo ze hry po jejich načtení zatím nejsou potvrzené.
