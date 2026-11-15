# Evertally Bridge 0.9.11

Živá poloha se už neposílá každé dvě sekundy. Limit bezplatné databáze (100 000 zapsaných řádků denně) se 14. 11. 2026 vyčerpal právě tím.

## Co se mění

- **Poloha jen při události.** Most dál každých 10 s čte značku z obrazovky, ale pošle polohu jen při první známé poloze, při změně mapy nebo postavy, po 5 minutách nebo když o ni web požádá.
- **Žádost „Kde jsi?“.** Když web požádá o tvou polohu, most si žádost vyzvedne při nejbližším dotazu na fórum (každé 3 minuty) a pošle jednu aktuální polohu. Aby odpověď přišla, musí Bridge běžet a WoW být vidět v levém horním rohu obrazovky.
- Web odpoví na žádost jen tomu, komu to tvé nastavení sdílení dovoluje (všem, přihlášeným, nebo potvrzeným přátelům).

## Co se nemění

Párování, nastavení i data zůstávají. Aktualizace mostu nevyžaduje restart WoW.

## Neověřeno

Změna je pokrytá automatickými testy webu (297) a mostu, ale **ve hře ani s živým serverem nebyla vyzkoušena**: skutečné kolečko „žádost z webu → Bridge → poloha na webu“ je potřeba projít ručně.
