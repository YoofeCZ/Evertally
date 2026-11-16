# Evertally 0.9.38

Opravy po prvním vyzkoušení 0.9.37 ve hře.

## Mikrozáseky

- Zvýraznění v taškách při otevřených taškách **každé 3 sekundy procházelo všechny rámce rozhraní** a u každého volalo několik metod. S více addony to jsou desítky tisíc rámců, odtud pravidelné mikrozáseky. Příčina je odvozená z kódu, ve hře změřená není.
- Teď se celé rozhraní prochází jen při otevření nebo změně tašek a nejvýš jednou za 2,5 s. Rámec, který nevypadá jako tlačítko tašky, stojí jedno přečtení pole, žádné volání. Časovač každou sekundu jen překreslí už nalezená tlačítka.
- Na `GET_ITEM_INFO_RECEIVED` (ostatní addony se ptají na předměty pořád) se reaguje jen tehdy, když zvýraznění na nějaký předmět opravdu čeká.

## Tašky nic neoznačovaly

- **Baganator**: jeho tlačítka nemusí prozradit tašku a slot. Předmět se teď čte z jeho vlastního odkazu (`BGR.itemLink`) a navíc z `GetItemLocation`.
- **Kontrola nositelnosti**: `IsUsableItem` může u obyčejné zbroje bez efektu „Use:“ vracet „nelze použít“. Rozhoduje teď tooltip předmětu (červený řádek s požadavkem). `IsUsableItem` platí jen tehdy, když tooltip přečíst nejde. Týká se i stránky Výbava.
- **Nově i lepší předměty**: modrý okraj = předmět jde do prázdného slotu, **zelená šipka** = předmět je podle vah tvé role lepší než to, co máš na sobě.
- **`/etally bags`** vypíše, kolik rámců prošel, kolik tlačítek našel a kolik označil (i s časem v ms), a u každého kusu výbavy v taškách proč ano nebo ne. Stejné řádky uloží do diagnostického logu.

## Vzhled chatu

- Okno je postavené z prvků hry: zlatý dialogový rám (`DialogBorderTranslucentTemplate`, stejný jako Edit Mode), červené tlačítko zavření, herní tlačítka a pole pro text, font chatu. Řádky konverzací mají ikonu whisperu nebo místnosti a zvýraznění jako quest log.
- Šířka tlačítek se řídí textem, „Založit / připojit“ už nepřetéká.
- Tlačítko u Social používá stejnou kresbu jako tlačítko menu chatu.

Ve hře zatím vyzkoušené není. Rámec, tlačítka a pole jsou šablony Blizzardu podle zdrojů klienta Forever 1.60.1. Kdyby některá šablona chyběla, okno se postaví z vlastních prvků (pokryto testem).

Bez nového souboru v TOC: stačí `/reload`.
