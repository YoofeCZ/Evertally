# Evertally 0.9.39

## Nový vzhled celého addonu

Barvy zůstávají: námořnická modř se zlatou. Mění se tvary a čistota, po vzoru moderních nastavení (QuestMaster):

- **Zaoblené plochy** u okna, karet, tlačítek, štítků i položek navigace. Všechno je plné, nic není průhledné.
- **Tlačítka**: hlavní akce zlatá s tmavým textem, ostatní klidná tmavá s tenkým obrysem.
- **Přepínače** jsou posuvné „pilulky“: zlatá zapnuto, tmavá vypnuto. V Nastavení je popisek vlevo a přepínač vpravo, řádek se při najetí jemně zvýrazní.
- **Nadpisy sekcí** v Nastavení: malé verzálky se zlatou svislou čárkou.
- **Navigace**: vybraná položka má zaoblený podklad a zlatou značku.
- Zaoblení dělají vlastní malé textury (`Media/Shape*.tga`, kreslí je `tools/make_shapes.py`) obarvené barvami motivu a natažené přes 9-slice (`SetTextureSliceMargins`). Klient, který 9-slice nemá, ukáže dřívější hranatý vzhled.

## Evertally chat ve stylu Evertally

- Okno už nepoužívá šablony Blizzardu. Ty se roztáhly přes celou obrazovku a jejich font neuměl „ř“.
- Nově: hlavička s logem, vlevo seznam konverzací (počáteční písmeno nebo #, jméno, poslední zpráva, modrý počet nepřečtených, zlatá značka u vybrané), vpravo konverzace na tmavém podkladu, dole pole „Napiš zprávu…“ a zlaté tlačítko **Odeslat**.
- Opraveno: jméno s diakritikou (např. „Řehoř“) se jako whisper do okna vůbec nedostalo.

## Porovnání výbavy

- Tooltip má po vzoru Pawnu jasný řádek: **▲ lepší / ▼ horší pro Protection (+0.8)** a změnu item levelu (Item level 8 → 12).
- Výbava, kterou postava nemůže nasadit (např. obouruční meč bez dovednosti), píše **„tohle nemůžeš nasadit“** místo ticha.
- Když mají dva kusy stejné statistiky pro roli, rozhodne **vyšší item level**.
- Šipka „lepší“ v taškách je teď nativní zelená šipka vylepšení z tašek Blizzardu (`bags-greenarrow`), větší a nad ostatními vrstvami tlačítka.
- Pro jistotu: řádky „Arms 0.9 ⬆ upgrade“ v tooltipu píše Pawn, ne Evertally.

Ve hře zatím vyzkoušené není. Vzhled jsem kontroloval jen v náhledovém modelu (`tools/ui_preview`), který kreslí rozložení, ne skutečné pixely hry.

Nové soubory: jen textury v `Media`. Pro jistotu restartuj hru, `/reload` je nemusí načíst.
