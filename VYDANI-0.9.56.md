# Evertally 0.9.56 (addon)

- **Oprava: záložka „Co se můžu naučit?“ ve spellbooku, Profily a Import / Export v okně talentů a Dungeon Journal v Looking For Group se v 0.9.55 vůbec neukázaly.** Tyhle okna hry jsou addony Blizzardu, které se načtou až při prvním otevření, a Evertally zprávu o jejich načtení (`ADDON_LOADED`) nepředával dál. Teď ji předává a moduly se napojí při načtení kteréhokoli okna. Nový test prochází skutečnou cestou události (s kódem 0.9.55 selže).

Aplikace beze změny (0.9.17). Bez nového souboru v TOC: stačí `/reload`.

## Oznámení aplikace ve Windows (zjištěno, nic se neměnilo)

Aplikace oznámení posílá a Windows je přijímá: všech 12 oznámení od Evertally (instalace addonu, „Evertally slyší hru“, „Hotovo…“) leží v centru oznámení. **Nevyskočí, protože Windows 11 při hraní hry nebo při aplikaci na celou obrazovku zapnou Nerušit** a oznámení jen uloží. Řešení je v Nastavení Windows (Systém > Oznámení), viz zpráva hráčům.

## Ověřeno

- Lua testy: 762 prošlo.
- Ve hře neověřeno.
