import manifest from "../public/media/maps/manifest.json";
import type {MapKey} from "./chronicle-build";

/** The map keys a recording may use and the game's uiMapIDs they stand for: the website's own catalogue. */
export const CHRONICLE_MAPS:MapKey[]=manifest.maps.map(m=>({key:m.key,uiMapIds:m.uiMapIds}));
