-- This addon owns only the explicitly allowed web outbox. It makes no requests.
local version = type(EvertallyExportDB) == "table" and EvertallyExportDB.schemaVersion
if version ~= 1 then
    EvertallyExportDB = { schemaVersion = 1, enabled = false, producerId = "", consentEpoch = 0,
        since = 0, scopes = {}, events = {} }
end
