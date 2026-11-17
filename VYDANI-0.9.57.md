# Evertally 0.9.57 (addon)

## Dungeon Journal na vlastních datech

- **Nepotřebuje addon ForeverDungeonJournal.** Dungeony, bossové a loot jsou z vlastního `DungeonData.lua` (generuje `tools/build_dungeon_data.py` z AtlasLoot Forever, QuestieDB, CMaNGOS ClassicDB, OpenMap a tabulek klienta z wago.tools), questy z `QuestGuideData.lua`, odměny z `GuideData.lua`.
- **44 dungeonů a raidů**, banner je loading screen instance (hra ho kreslí podle file ID).
- **Bossové:** úroveň a **portrét modelu** u 293 bossů (hra ho kreslí podle display ID), odkaz **Otevřít bosse v databázi**. U vlastních dungeonů Foreveru (Hall of Thanes, Krol'dok, Blackmaw Hold…) žádný veřejný zdroj úrovní není: addon si úroveň zapamatuje, až bosse uvidíš (target nebo myš).
- **Mapa:** Blizzardovy mapy pater u 25 instancí, **na místě bosse jeho portrét v kroužku** s číslem z pořadí, tlačítka pater; křídla (Scarlet Monastery, Dire Maul, Stratholme) ukážou jen svá patra. Záložka Mapa je jen tam, kde mapa je.
- **Questy:** kdo quest dává a kde se odevzdá i se zónou a tlačítkem na mapu, co splnit předtím, odměny a XP.
- Raidy mají úroveň 60, řazení od nejnižší úrovně.
- Žebříčky berou seznam dungeonů z vlastních dat.

## Chat

- Místnost **#Evertally** je jen pro oznámení: píšou do ní jen postavy autora, ostatní čtou.
- Pevné místnosti se nikdy nepřipojují s heslem; když je někdo heslem zamkne, okno s heslem se zavře a místnost se do konce sezení přeskočí.

**Přibyl soubor v TOC (`DungeonData.lua`): hru je potřeba úplně ukončit a spustit znovu, `/reload` nestačí.** Aplikace beze změny (0.9.17).

## Ověřeno

- Lua testy: 768 prošlo (Dungeon Journal na malé napodobenině i na skutečných datech).
- Pozice bossů zakreslené do obrázků pater (Deadmines, Molten Core) sedí na lebky v mapě.
- **Ve hře neověřeno**, hlavně portréty přes `SetPortraitTextureFromCreatureDisplayID` a kulatá maska (API je ve Foreveru deklarované, chování ne).
