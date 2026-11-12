"use client";
// Makes a floating map panel movable: drag its header anywhere, double-click the header to put it back. The place is
// remembered per panel in this browser. It wraps the panel without touching it, so it works for every panel that has a
// `<header>` as a direct child of `.people-panel`; buttons, links and fields inside the header still work as before.
import { useEffect, useRef, useState, type PointerEvent, type ReactNode } from "react";
import { clampDrag, outOfReach, parseOffset, type Offset } from "./panelDrag";

const KEY = (id: string) => `evertally.map.panel.${id}`;
const INTERACTIVE = "button, a, input, select, textarea, label, summary";

/** The panel's own header, unless the pointer is on something clickable in it. */
function ownHeader(target: EventTarget | null): HTMLElement | null {
  const node = target instanceof Element ? target : null;
  const header = node?.closest("header") ?? null;
  return header && header.parentElement?.classList.contains("people-panel") && !node?.closest(INTERACTIVE) ? header : null;
}
// the panels sit in a fixed stack on narrow screens, where moving them would only get in the way
const narrow = () => window.matchMedia("(max-width: 1000px)").matches;

export function Movable({ id, children }: { id: string; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [offset, setOffset] = useState<Offset>({ x: 0, y: 0 });
  const [moving, setMoving] = useState(false);
  const latest = useRef<Offset>({ x: 0, y: 0 });
  const drag = useRef<{ pointer: number; x: number; y: number; base: Offset; rect: DOMRect; capture: HTMLElement } | null>(null);

  useEffect(() => {
    // one-time client-side restore: localStorage does not exist while rendering on the server
    try {
      const saved = parseOffset(window.localStorage.getItem(KEY(id)));
      if (saved) {
        latest.current = saved;
        // eslint-disable-next-line react-hooks/set-state-in-effect
        setOffset(saved);
      }
    } catch { /* storage unavailable */ }
  }, [id]);

  useEffect(() => {
    // a window made smaller must not leave a panel where it cannot be grabbed
    const check = () => {
      const element = ref.current;
      if (!element || (latest.current.x === 0 && latest.current.y === 0)) return;
      if (outOfReach(element.getBoundingClientRect(), { width: window.innerWidth, height: window.innerHeight })) {
        latest.current = { x: 0, y: 0 };
        setOffset({ x: 0, y: 0 });
      }
    };
    window.addEventListener("resize", check);
    return () => window.removeEventListener("resize", check);
  }, []);

  const down = (event: PointerEvent<HTMLDivElement>) => {
    const header = ownHeader(event.target);
    if (event.button !== 0 || narrow() || !header || !ref.current) return;
    drag.current = { pointer: event.pointerId, x: event.clientX, y: event.clientY, base: latest.current, rect: ref.current.getBoundingClientRect(), capture: header };
    // Capture on the header: capturing on the wrapper retargets dblclick there too,
    // which would make reset() reject a genuine double-click on the header.
    try { header.setPointerCapture(event.pointerId); } catch { /* the drag still works while the pointer stays over the panel */ }
    setMoving(true);
  };
  const move = (event: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || d.pointer !== event.pointerId) return;
    const next = clampDrag(d.base, event.clientX - d.x, event.clientY - d.y, d.rect, { width: window.innerWidth, height: window.innerHeight });
    latest.current = next;
    setOffset(next);
  };
  const end = (event: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || d.pointer !== event.pointerId) return;
    drag.current = null;
    setMoving(false);
    try { d.capture.releasePointerCapture(event.pointerId); } catch { /* the capture is already gone */ }
    try { window.localStorage.setItem(KEY(id), JSON.stringify(latest.current)); } catch { /* storage unavailable */ }
  };
  const reset = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!ownHeader(event.target)) return;
    latest.current = { x: 0, y: 0 };
    setOffset({ x: 0, y: 0 });
    try { window.localStorage.removeItem(KEY(id)); } catch { /* storage unavailable */ }
  };

  const moved = offset.x !== 0 || offset.y !== 0;
  return (
    <div ref={ref} className={`movable${moving ? " moving" : ""}${moved ? " moved" : ""}`} style={moved ? { transform: `translate(${offset.x}px, ${offset.y}px)` } : undefined}
      onPointerDown={down} onPointerMove={move} onPointerUp={end} onPointerCancel={end} onDoubleClick={reset}>
      {children}
    </div>
  );
}
