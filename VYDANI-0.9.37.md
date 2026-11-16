# Evertally 0.9.37

## Výbava do prázdných slotů v taškách

- Předmět v tašce dostane **modrý okraj a záři**, když jde do slotu, který postava zatím nemá obsazený (boty, prsten, štít…), a postava si ho **může obléct hned teď**: úroveň, typ zbroje nebo zbraně, třída, dual wield. Rozhoduje stejná kontrola jako porovnání výbavy (`Gear.CanUse`).
- U prstenů a trinketů stačí jeden volný slot. Štít nebo off-hand se nezvýrazní, když je v hlavní ruce obouruční zbraň.
- Košile a tabard se nezvýrazňují: nemají statistiky a prázdný slot je u nich volba, ne mezera.
- Funguje v původních taškách Blizzardu i v bag addonech (Bagnon, AdiBags, ArkInventory, Baganator…): tlačítko předmětu se pozná podle toho, co o sobě prozradí (taška a slot nebo odkaz na předmět), ne podle konkrétního addonu. Do cizích tlačítek se jen přidá textura, nic se do nich nezapisuje.
- **Nastavení → Rozhraní → Zvýraznit v taškách výbavu do prázdných slotů**, ve výchozím stavu zapnuto.

## Evertally chat

- Nové **tlačítko vpravo od tlačítka Social** u chatu (bublina). Ukazuje počet nepřečtených zpráv; kliknutím otevře okno.
- **Okno chatu**: vlevo seznam konverzací, vpravo otevřená konverzace a pole pro psaní (Enter odešle). Každý, kdo ti napíše whisper, má vlastní konverzaci; „Jméno“, „Jméno-Realm“ i „Jméno Realm“ jsou jedna konverzace.
- Nová konverzace: napiš jméno postavy do pole vlevo dole a klikni **Whisper**.
- **Místnosti**: napiš název (2–24 písmen nebo číslic) a případně za mezerou heslo, klikni **Založit / připojit**. Kdo vejde první, ten místnost založí. **Opustit místnost** je nahoře nad konverzací. Místnosti si addon pamatuje a po přihlášení se do nich znovu připojí.
- Místnosti jsou **vlastní chatové kanály hry**: členství a heslo drží server, přežijí relog a psát do nich můžou i hráči bez Evertally (přes `/join název`). Hra dovolí najednou nejvýš deset kanálů včetně General a Trade.
- Historie zpráv je **jen v paměti** do odhlášení nebo `/reload`. Soukromé zprávy se nezapisují do uložených dat, která čte aplikace.
- **Nastavení → Rozhraní**:
  - **Evertally chat**: zapne nebo vypne celou funkci (tlačítko, okno, zachytávání). Výchozí: zapnuto.
  - **…whispery a místnosti ukazovat jen tam, ne v hlavním chatu**: výchozí vypnuto, takže whispery jsou dál vidět v hlavním chatu a navíc v okně Evertally. Po zapnutí zmizí z hlavního chatu, okno se při novém whisperu samo otevře (v boji ne, jen zazní zvuk a naskočí počet na tlačítku).
  - Whisper od GM se z hlavního chatu neskrývá nikdy.

## Co nebylo ověřeno ve hře

Ověřeno testy (`tests/lua/test_bag_highlight.py`, `tests/lua/test_chat.py`) s napodobeným klientem, ne ve skutečné hře:

- Funkce `ChatFrame_AddMessageEventFilter`, `JoinChannelByName`, `LeaveChannelByName`, `GetChannelName` a tlačítka `QuickJoinToastButton` / `FriendsMicroButton` nejsou v offline katalogu API Forever (ten pokrývá jen C API). Addon je volá jen tehdy, když existují.
- Rozpoznání tlačítek v Bagnonu, AdiBags, ArkInventory a Baganatoru vychází z jejich zvyklostí, ve hře s nimi vyzkoušené není.
- Odpověď klávesou R funguje jen na whispery, které zůstaly v hlavním chatu.

Nové soubory v TOC (`BagHighlight.lua`, `Chat.lua`, `ChatUI.lua`): po aktualizaci je potřeba **restart hry**, `/reload` nestačí.
