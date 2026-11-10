"use client";
import { useDeferredValue, useMemo, useState } from "react";
import { Icon } from "../ui";
import { ItemIcon } from "./icons";
import { ItemLink, Money, Section, TipBody, liteRows, useDb } from "./parts";
import { qualityClass, useItem, useRecipes, type Recipe, type RecipeBook } from "./store";
import { useS } from "./strings";

const PAGE = 40;

/** orange / yellow / green / grey skill thresholds, as the game colours a recipe's difficulty */
function Skill({ skill, compact = false }: { skill: Recipe["skill"]; compact?: boolean }) {
  const s = useS();
  const titles = [s.orange, s.yellow, s.green, s.grey];
  return <span className={`skill-chips ${compact ? "compact" : ""}`}>{skill.map((value, i) => <i key={i} className={`sk sk-${i}`} title={`${titles[i]} ${value}`}>{value}</i>)}</span>;
}

export function useRecipeIndex() {
  const recipes = useRecipes();
  const index = useMemo(() => {
    const byOutput = new Map<number, Recipe[]>(), byReagent = new Map<number, Recipe[]>();
    for (const recipe of recipes.data?.recipes ?? []) {
      if (recipe.out) byOutput.set(recipe.out, [...(byOutput.get(recipe.out) ?? []), recipe]);
      for (const [item] of recipe.reagents) byReagent.set(item, [...(byReagent.get(item) ?? []), recipe]);
    }
    return { byOutput, byReagent };
  }, [recipes.data]);
  return { ...recipes, ...index };
}

export function RecipeLink({ recipe }: { recipe: Recipe }) {
  return <a className="elink" href={`#database/recipes/${recipe.id}`}><span>{recipe.name}</span><small className="muted">{recipe.skill[1]}</small></a>;
}

export function RecipeDetailView({ id }: { id: number }) {
  const s = useS();
  const { index } = useDb();
  const book = useRecipes();
  const recipe = book.data?.recipes.find(entry => entry.id === id);
  const output = recipe?.out ? index?.items.get(recipe.out) : undefined;
  const detail = useItem(index, recipe?.out ?? null);
  if (!index || book.loading) return <p className="muted">{s.loading}</p>;
  if (!recipe) return <div className="notice error">{s.noResults} #{id}</div>;
  const profession = book.data?.professions[String(recipe.line)];
  const rows = detail.data?.tip?.length ? detail.data.tip : output ? liteRows(output[1], output[2], output[3], output[4], index.search.cats[output[5]]) : [];
  return (
    <article className="db-detail">
      <header className="db-head">
        {output ? <ItemIcon id={output[0]} quality={output[2]} category={index.search.cats[output[5]]} cached={output[8] === 0} size={64} /> : <span className="npc-portrait"><Icon name="anvil" size={30} /></span>}
        <div>
          <h2 className={output ? qualityClass(output[2]) : undefined}>{recipe.name}</h2>
          <div className="chips"><span className="chip mono">#{recipe.id}</span>{profession && <span className="chip">{profession}</span>}<Skill skill={recipe.skill} /></div>
        </div>
      </header>
      <div className="db-columns">
        <div className="db-stack">
          <Section title={s.reagents} count={recipe.reagents.length}>
            {recipe.reagents.length ? <ul className="plain-list">{recipe.reagents.map(([item, qty]) => <li key={item}><ItemLink id={item} count={<small className="muted"> × {qty}</small>} /></li>)}</ul> : <p className="muted">—</p>}
          </Section>
          {recipe.out && <Section title={s.makes}><ItemLink id={recipe.out} count={recipe.qty ? <small className="muted"> × {recipe.qty}</small> : undefined} /></Section>}
          <Section title={s.skillUp}>
            <ul className="plain-list skill-legend">
              {[s.orange, s.yellow, s.green, s.grey].map((label, i) => <li key={label}><i className={`sk sk-${i}`}>{recipe.skill[i]}</i> {label}</li>)}
            </ul>
          </Section>
        </div>
        <div className="db-stack">
          {(recipe.fee != null || recipe.scroll) && (
            <Section title={s.learnedFrom}>
              <ul className="plain-list">
                {recipe.fee != null && <li>{s.trainedBy}: <Money gold={Math.floor(recipe.fee / 10000)} silver={Math.floor(recipe.fee / 100) % 100} copper={recipe.fee % 100} /> · {s.required} {recipe.req}</li>}
                {recipe.scroll && <li><ItemLink id={recipe.scroll[0]} /> <small className="muted">{s.required} {recipe.scroll[1]}</small></li>}
              </ul>
            </Section>
          )}
          {rows.length > 0 && <Section title={output ? output[1] : s.makes}><TipBody rows={rows} /></Section>}
        </div>
      </div>
      <p className="fine-print">{s.recipesSource}</p>
    </article>
  );
}

export function RecipesList({ query, selected }: { query: string; selected: number | null }) {
  const s = useS();
  const { index } = useDb();
  const book = useRecipes();
  const [text, setText] = useState(query);
  const [line, setLine] = useState("");
  const [sort, setSort] = useState<"skill" | "name">("skill");
  const [page, setPage] = useState(0);
  const needle = useDeferredValue(text.trim().toLowerCase());
  const matches = useMemo<Recipe[]>(() => {
    const all = book.data?.recipes ?? [];
    const found = all.filter(recipe => (!line || String(recipe.line) === line) && (!needle || recipe.name.toLowerCase().includes(needle) || recipe.reagents.some(([item]) => index?.items.get(item)?.[1].toLowerCase().includes(needle))));
    return found.sort((a, b) => sort === "name" ? a.name.localeCompare(b.name) : a.skill[1] - b.skill[1] || a.name.localeCompare(b.name));
  }, [book.data, line, needle, sort, index]);
  const pages = Math.max(1, Math.ceil(matches.length / PAGE));
  const current = Math.min(page, pages - 1);
  const reset = <T,>(set: (value: T) => void) => (value: T) => { set(value); setPage(0); };
  if (!index || book.loading) return <p className="muted">{s.loading}</p>;
  const professions = Object.entries((book.data as RecipeBook).professions);
  return (
    <div className="db-list">
      <div className="db-filters">
        <label className="search"><Icon name="search" size={16} /><input value={text} onChange={e => reset(setText)(e.target.value)} placeholder={s.recipePlaceholder} aria-label={s.tabRecipes} /></label>
        <div className="filter-row">
          <label className="field"><span>{s.profession}</span><select value={line} onChange={e => reset(setLine)(e.target.value)}><option value="">{s.all}</option>{professions.map(([id, name]) => <option key={id} value={id}>{name}</option>)}</select></label>
          <label className="field"><span>{s.sortBy}</span><select value={sort} onChange={e => reset(setSort)(e.target.value as "skill" | "name")}><option value="skill">{s.skillUp}</option><option value="name">{s.name}</option></select></label>
        </div>
      </div>
      <p className="fine-print">{matches.length.toLocaleString()} {s.matches}</p>
      {matches.length ? <ul className="result-list">{matches.slice(current * PAGE, (current + 1) * PAGE).map(recipe => {
        const output = recipe.out ? index.items.get(recipe.out) : undefined;
        return (
          <li key={recipe.id}><a href={`#database/recipes/${recipe.id}`} className={selected === recipe.id ? "is-selected" : ""}>
            {output ? <ItemIcon id={output[0]} quality={output[2]} category={index.search.cats[output[5]]} cached={output[8] === 0} size={34} /> : <span className="item-icon q1" style={{ width: 34, height: 34 }}><Icon name="anvil" size={18} /></span>}
            <span className="rl-main"><strong className={output ? qualityClass(output[2]) : undefined}>{recipe.name}</strong><small>{book.data!.professions[String(recipe.line)]} · {recipe.reagents.length} {s.reagents.toLowerCase()}</small></span>
            <Skill skill={recipe.skill} compact />
          </a></li>
        );
      })}</ul> : <p className="muted">{s.noResults}</p>}
      <div className="pager"><button type="button" className="btn btn-ghost btn-sm" disabled={current === 0} onClick={() => setPage(current - 1)}>{s.previous}</button><span className="mono">{current + 1} / {pages}</span><button type="button" className="btn btn-ghost btn-sm" disabled={current + 1 >= pages} onClick={() => setPage(current + 1)}>{s.next}</button></div>
    </div>
  );
}
