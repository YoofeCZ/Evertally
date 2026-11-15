# Evertally 0.9.31

Kronika se zapisuje i z toho, co se děje na cestě, a hráč ji může sdílet veřejně. Funkce 0.9.30 zůstávají.

## Co se mění

- **Záznam cesty** (`Journey.lua`): zabití (ze zprávy o zkušenostech), zisk a útrata peněz, zlepšení dovedností (i s maximem), smrt, vstup do skupiny a odchod z ní, let. Zapisuje se po dávkách (jedna událost `journey.chunk` na několik minut hraní) pod souhlasem „Moje trasa“; do místní historie nic nepřibývá.
- **Kvalita předmětu** u lootu (z barvy odkazu), aby web uměl filtrovat a barvit.
- **Volba „…s mou kronikou“** v Nastavení pod volbou žebříčku: trasa a co postava dělala se na webu ukáže jako přehratelná cesta. Zapnout ji lze, jen když je postava ve veřejném žebříčku; vypnutí se na webu projeví ihned.

## Nasazení (pořadí je důležité)

1. Migrace `0014_public_chronicle.sql` na produkční D1 (přidá sloupec `show_chronicle`).
2. Web (nový kontrakt přijímá `journey.chunk`, `quality`, `showChronicle`).
3. Teprve potom addon: starý server by nové události odmítl (striktní schéma).

Přibyl soubor `Journey.lua` v TOC, proto **WoW úplně ukonči a znovu spusť**. Windows Bridge addon aktualizuje sám.

## Kontroly této verze

- Lua testy (614) a webové testy (310) prošly.
- **Neověřeno ve hře:** zprávy o zkušenostech a dovednostech, `UnitOnTaxi` a `GetSkillLineInfo` na Forever. Zabití, peníze a lety tedy mohou na skutečném klientovi chybět, dokud se nezkusí hrou.
- PvP se zatím nezapisuje.
- Stránku Kronika s veřejnými kronikami jsem viděl jen na ukázkových datech; na produkčních datech ji uvidíme až po nasazení.
