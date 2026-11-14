# Evertally 0.9.24 — kontrola instalace

Addon vyžaduje OpenMap a Windows Bridge 0.9.9 nebo novější. Dokud chybí načtený OpenMap nebo místní potvrzení instalace mostu, zůstává dostupná jen instalační kontrola a pomocné či vypínací příkazy. Průvodce, stránky, navigace, zaznamenávání a odesílání dat čekají na obě podmínky.

- **Stáhnout aplikaci** a **Získat OpenMap** jsou tlačítka. Hlavní obrazovka ani krok 8 průvodce nevypisují adresy. WoW neposkytuje běžnému addonu otevření libovolného webu: po kliknutí se otevře malé okno s vybranou adresou připravenou pro Ctrl+C. Ve Windows Web sync obě tlačítka otevírají prohlížeč přímo.
- **Ověřit instalaci** je dostupné stále: na úvodní kontrole, v kroku 8 průvodce, v Nastavení → Akce a přes `/etally install`. Zavření kontroly podmínky neobchází; **Pokračovat** funguje až po ověření obou.
- Windows Bridge vytváří datový soubor `BridgeInstallation.lua` pouze v nalezených složkách Evertally. Obsahuje verzi aplikace a čas vytvoření, žádné přihlašovací údaje. Vytvoření nevyžaduje připojení k webu ani párování. Aktualizátor a instalační skript soubor zachovávají.
- Potvrzení dokládá, že v dané složce kompatibilní Bridge alespoň jednou běžel. Nedokládá, že právě běží, a nepozná pozdější odinstalaci aplikace. WoW nemá přístup k procesům Windows. Addon potvrzení načte při načtení rozhraní; kliknutí na Ověřit samo nepřečte změněný soubor z disku.
- Po přidání nových souborů addonu nebo OpenMap WoW úplně ukonči a znovu spusť. Pokud se změnilo jen potvrzení mostu v již načítaném souboru, stačí `/reload`.
- Souhlas se sdílením, párování s účtem a jednotlivá oprávnění exportu zůstávají samostatné a dobrovolné. Kontrola instalace je nezapíná.

Automatické testy a izolované náhledy ověřují blokování, ovládání a rozvržení. Skutečný vzhled a načtení potvrzení v běžícím WoW se bez uživatelova restartu hry neověřují. Aktualizace neovládá herní okno ani neukončuje WoW.
