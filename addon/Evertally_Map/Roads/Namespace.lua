local _, M = ...
-- A private copy of SPF's GPL collision solver. Never shares a journey or cache
-- with the installed SPF addon; all bundled chunks receive this namespace.
M._roadEngine = {NavData = {}}
