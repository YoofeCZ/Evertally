# Náhled rozložení addonu bez spuštěné hry

`preview.py` spustí Lua addonu nad `layout_mock.lua`, spočítá kotvy rámů a převede viditelné prvky do HTML. `capture.cjs` je vyfotí v samostatném headless Edge. Neotevírá okna, nepřipojuje se k osobnímu prohlížeči a neovládá WoW.

Vyžaduje Python s Lupa (Lua 5.1), Node a modul `playwright` dostupný přes `NODE_PATH` nebo `PLAYWRIGHT_MODULE`. Lupa lze dodat přes `PYTHONPATH`; `tests/lua/test_addon.py` také podporuje dosavadní lokální vendor. Microsoft Edge musí být nainstalovaný.

Z kořene projektu například:

```powershell
python tools/ui_preview/preview.py overview --tab activity --size 960x620
python tools/ui_preview/preview.py settings --size 700x460
python tools/ui_preview/preview.py viewer --tab equipped
python tools/ui_preview/preview.py setup --tab 1
python tools/ui_preview/preview.py guides --no-shots
```

Výchozí výstup je `output/ui-preview`; `--out` vybere jiný adresář. `--openmap` vloží testovací rozhraní OpenMap. Selhání snímání skončí chybou.

Náhledy ověřují rozložení, ořezání a přesahy na modelu rámů. Fonty a herní textury jsou náhrady. Neprokazují skutečný vzhled, tooltipy, výkon ve hře ani přenos mezi skutečnými hráči.
