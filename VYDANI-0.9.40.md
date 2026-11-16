# Evertally 0.9.40

## Evertally chat: místnosti v kategoriích

- Vlevo jsou dvě záložky: **Místnosti** a **Whispery**, u každé počet nepřečtených.
- Místnosti jsou ve skupinách:
  - **Podpora:** **#Evertally**. Připojí se do ní každý s Evertally.
  - **Obecné:** **General**. Také se připojí automaticky.
  - **Jazyky:** Čeština, Slovenčina, English, Deutsch, Polski, Français, Español, Русский. Do místnosti vstoupíš kliknutím, dokud v ní nejsi, je ztlumená.
  - **Vlastní:** tvoje místnosti a položka **Procházet a založit místnost**.
- **Procházení**: seznam veřejných místností s vyhledáváním (kdo ji naposledy ohlásil, před kolika minutami) a tlačítkem **Připojit**. Pod ním formulář: název, nepovinné heslo a volba **Veřejná** (uvidí ji všichni) nebo **Soukromá** (jen podle názvu).
- **Sdílet**: u vlastní místnosti pošle do General pozvánku „Pojďte do mé místnosti #Název“.
- Pevné místnosti mají kanály s předponou (`EtGeneral`, `EtCestina`…), aby se nepotkaly s cizími kanály. Ukazuje se jejich hezký název. Pevnou místnost, kterou opustíš, addon po přihlášení znovu nepřipojí.
- Hra sama seznam vlastních kanálů nenabízí. Veřejné místnosti si proto addony ohlašují **neviditelnou addon zprávou v #Evertally** (každých 5 minut, zapomenou se po 20 minutách bez ohlášení). Soukromé se neohlašují nikdy.
- **Správce kanálu** ve hře je ten, kdo do něj vejde první. Aby byl majitel Evertally moderátorem #Evertally, musí se připojit dřív než ostatní.
- Pozor na limit hry: najednou nejvýš 10 chatových kanálů včetně General, Trade a dalších herních.

## Okno chatu

- **Velikost jde měnit** tahem za pravý dolní roh (600×400 až 1400×1000) a addon si ji pamatuje.
- Popisek pod názvem konverzace už nepřetéká pod tlačítko „Opustit místnost“.
- Opraveno: do pevných místností (General a další) by nešlo psát. Zpráva se posílala podle zobrazovaného názvu místo názvu kanálu.

## Šipka „lepší“ v taškách

- Zelená šipka, kterou bylo vidět u meče, je od Pawnu. Šipka Evertally se ve hře nezobrazovala vůbec: atlas `bags-greenarrow` v klientu chybí a kvůli chybě v kontrole se nepoužila náhradní textura.
- Šipka je teď **vlastní textura addonu** (`Media/ShapeArrow.tga`), v **pravém horním rohu** (Pawn kreslí do levého). Šipka i modrý okraj jsou na vlastním rámečku nad tlačítkem, aby je nepřekryly prvky bag addonu.
- Když něco nebude sedět, `/etally bags` vypíše u každého kusu výbavy, proč šipku nebo okraj má, nebo nemá.

Ve hře zatím vyzkoušené není. Nový soubor je jen textura v `Media`, takže radši restartuj hru.
