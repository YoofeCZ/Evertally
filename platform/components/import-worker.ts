import { parseExport } from "../lib/import";
self.onmessage = (event: MessageEvent<{ text: string }>) => {
  try { self.postMessage({ ok: true, data: parseExport(event.data.text) }); }
  catch (error) { self.postMessage({ ok: false, error: error instanceof Error ? error.message : "Soubor nelze přečíst." }); }
};
