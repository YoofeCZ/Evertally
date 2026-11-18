local _, A = ...
-- Shared visual contract for every Evertally window: "night and gold".
-- A window is a night ground under a band of night sky, edged with 1px lines, a gold rim along its top with a soft light
-- under it and a small gold jewel in each corner (Evertally's own mark). Cards, fields and buttons inside are rounded.
-- The player picks how deep the night runs (a colour scheme: Night, Dusk or Graphite, Settings > Interface); the gold,
-- the status colours and the text ladder are the same in every scheme, so text never changes its contrast.
-- The band, the glow and the line glyphs are Polestar's art (GPL-3.0, Media/NOTICE-Polestar.txt).
local MEDIA = "Interface\\AddOns\\Evertally\\Media\\"
local ART = MEDIA .. "Polestar\\"

-- Colours every scheme shares: the accent, the status colours and the text ladder.
local SHARED = {
    text = {0.950, 0.945, 0.925}, mist = {0.720, 0.745, 0.800}, faint = {0.545, 0.580, 0.660},
    gold = {0.835, 0.690, 0.400}, bright = {0.965, 0.870, 0.640}, lilac = {0.835, 0.690, 0.400},
    violet = {0.330, 0.255, 0.120}, green = {0.40, 0.80, 0.58}, peach = {0.94, 0.68, 0.36},
    red = {0.90, 0.38, 0.38}, sky = {0.45, 0.70, 0.92}, silver = {0.76, 0.81, 0.83}, bronze = {0.72, 0.47, 0.27},
    haze = {0.36, 0.42, 0.72, 0.30}, rule = {1, 1, 1, 0.07},
}
-- The grounds of each scheme. canvas: the window; header/dome: the band's sky; side: the menu; card/well/raised:
-- panels, readers and quiet buttons; line: the 1px outline of a panel; off: an unlit control.
local SCHEMES = {
    night = {
        canvas = {0.040, 0.052, 0.088}, header = {0.058, 0.076, 0.132}, side = {0.030, 0.039, 0.068},
        card = {0.060, 0.078, 0.126}, well = {0.048, 0.062, 0.104}, raised = {0.082, 0.104, 0.164},
        dome = {0.110, 0.150, 0.290}, off = {0.150, 0.180, 0.255}, line = {0.420, 0.380, 0.300, 0.45},
    },
    dusk = {
        canvas = {0.095, 0.115, 0.178}, header = {0.120, 0.145, 0.222}, side = {0.072, 0.088, 0.140},
        card = {0.118, 0.141, 0.212}, well = {0.104, 0.125, 0.190}, raised = {0.148, 0.176, 0.262},
        dome = {0.190, 0.235, 0.385}, off = {0.205, 0.240, 0.330}, line = {0.500, 0.460, 0.380, 0.45},
    },
    graphite = {
        canvas = {0.131, 0.137, 0.146}, header = {0.158, 0.165, 0.176}, side = {0.104, 0.109, 0.116},
        card = {0.152, 0.158, 0.168}, well = {0.140, 0.146, 0.155}, raised = {0.190, 0.197, 0.210},
        dome = {0.230, 0.245, 0.275}, off = {0.235, 0.245, 0.262}, line = {0.520, 0.500, 0.460, 0.40},
    },
}
-- "guide": the colours of Evertally Guide's skin (the Evertally_Guide add-ons, from Polestar), worked out from its
-- palette whenever it changes (T.GuideColors), so Evertally's pages in its hub wear the same skin and accent.
SCHEMES.guide = {}
local ORDER = {"guide", "night", "dusk", "graphite"}
local DEFAULT = "night"

local function guideTheme()
    local g = rawget(_G, "EvertallyGuide")
    local th = type(g) == "table" and g.Theme
    if type(th) == "table" and type(th.Palette) == "function" then return th end
    return nil
end

local function rgb(c, fallback)
    if type(c) ~= "table" or type(c[1]) ~= "number" then return fallback end
    return {c[1], c[2], c[3], c[4]}
end
-- top laid over under by top's alpha: an opaque colour.
local function over(top, under)
    local a = top[4] or 1
    return {top[1] * a + under[1] * (1 - a), top[2] * a + under[2] * (1 - a), top[3] * a + under[3] * (1 - a)}
end
local function mix(a, b, t) return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t} end
local WHITE, BLACK = {1, 1, 1}, {0, 0, 0}

--- The guide's palette as Evertally's palette names. -> table, or nil without the guide.
local function guideColors()
    local th = guideTheme()
    if not th then return nil end
    local ok, pal = pcall(th.Palette)
    if not ok or type(pal) ~= "table" then return nil end
    local bg = rgb(pal.bg, {0.04, 0.05, 0.09}); bg = {bg[1], bg[2], bg[3]}
    local card = pal.panel and over(rgb(pal.panel), bg) or mix(bg, WHITE, 0.03)
    local accent = rgb(pal.accent, {0.835, 0.690, 0.400}); accent = {accent[1], accent[2], accent[3]}
    local border = rgb(pal.border, {1, 1, 1, 0.14})
    local text = rgb(pal.text, SHARED.text)
    return {
        canvas = bg, header = pal.sky and over(rgb(pal.sky), bg) or mix(bg, WHITE, 0.04),
        side = pal.sidebar and over(rgb(pal.sidebar), bg) or mix(bg, BLACK, 0.2),
        card = card, well = mix(card, BLACK, 0.18),
        raised = pal.panelAlt and over(rgb(pal.panelAlt), card) or mix(card, WHITE, 0.06),
        dome = mix(bg, accent, 0.18), off = over(border, card), line = {border[1], border[2], border[3], border[4] or 0.14},
        rule = rgb(pal.divider, {1, 1, 1, 0.07}),
        text = {text[1], text[2], text[3]}, mist = rgb(pal.textDim, SHARED.mist), faint = rgb(pal.textMuted, SHARED.faint),
        gold = accent, lilac = accent, bright = mix(accent, WHITE, 0.45), violet = mix(accent, BLACK, 0.6),
    }
end

local T = {id = "night-gold", colors = {}, schemes = SCHEMES, SCHEME_ORDER = ORDER, DEFAULT_SCHEME = DEFAULT,
    metrics = {width = 1120, height = 740, header = 64, sidebar = 236, rail = 40, navRow = 34, body = 13, title = 24}}
A.Theme = T
T.GuideTheme, T.GuideColors = guideTheme, guideColors
local C = T.colors
-- The palette tables are made once and only ever filled in place: pages keep references to them (kit.C, A.Theme.colors).
local function fillPalette(key)
    if key == "guide" then
        local colors = T.GuideColors()
        if colors then SCHEMES.guide = colors else key = DEFAULT end
    end
    local scheme = SCHEMES[key] or SCHEMES[DEFAULT]
    for _, source in ipairs({SHARED, scheme}) do
        for name, c in pairs(source) do
            local into = C[name]
            if not into then into = {}; C[name] = into end
            into[1], into[2], into[3], into[4] = c[1], c[2], c[3], c[4]
        end
    end
end
fillPalette(DEFAULT)
local PALETTE = {}
for _, c in pairs(C) do PALETTE[c] = true end
T.reader = {ink = C.text, mutedInk = C.mist, heading = C.bright}

-- Rounded shapes: white textures from Media (tools/make_shapes.py) tinted with the theme colours and stretched with
-- 9-slice margins, so a corner keeps its radius at any size. Without 9-slice in the client every shape stays square.
local SHAPES = {round = {file = "ShapeRound", margins = {8, 8, 8, 8}}, ring = {file = "ShapeRing", margins = {8, 8, 8, 8}},
    pill = {file = "ShapePill", margins = {16, 0, 16, 0}}, dot = {file = "ShapeDot"}}
function T.Shapes(tex)
    if tex then return type(tex.SetTextureSliceMargins) == "function" end
    if T.shapesSupported == nil then
        local probe = type(CreateFrame) == "function" and CreateFrame("Frame")
        local t = probe and probe.CreateTexture and probe:CreateTexture()
        T.shapesSupported = t ~= nil and type(t.SetTextureSliceMargins) == "function"
    end
    return T.shapesSupported
end
function T.Shape(tex, kind)
    -- The guide's look is square: panels, fields and buttons with 1px lines (a dot stays round).
    if T.scheme == "guide" and kind ~= "dot" then return false end
    local shape = SHAPES[kind]; if not shape or not tex or type(tex.SetTexture) ~= "function" then return false end
    if shape.margins and not T.Shapes(tex) then return false end
    if tex:SetTexture(MEDIA .. shape.file) == false then return false end
    if shape.margins then
        if not pcall(tex.SetTextureSliceMargins, tex, unpack(shape.margins)) then return false end
        local mode = type(Enum) == "table" and type(Enum.UITextureSliceMode) == "table" and Enum.UITextureSliceMode.Stretched or 0
        if type(tex.SetTextureSliceMode) == "function" then pcall(tex.SetTextureSliceMode, tex, mode) end
    end
    if type(tex.SetTexCoord) == "function" then tex:SetTexCoord(0, 1, 0, 1) end
    tex.evertallyShape = kind
    return true
end

-- Every texture painted with a palette colour is remembered (weakly), so a new scheme repaints it in place.
local painted = setmetatable({}, {__mode = "k"})
local function paint(tex, c, alpha)
    if PALETTE[c] then painted[tex] = {c, alpha} elseif painted[tex] then painted[tex] = nil end
    local a = alpha or c[4] or 1
    -- A shaped texture or a piece of art keeps its image and takes the colour as a tint.
    if tex.evertallyShape or tex.evertallyArt then tex:SetVertexColor(c[1], c[2], c[3], a); return end
    if tex.SetColorTexture then tex:SetColorTexture(c[1], c[2], c[3], a)
    else tex:SetTexture("Interface\\Buttons\\WHITE8X8"); tex:SetVertexColor(c[1], c[2], c[3], a) end
end
local function gradient(tex, top, bottom)
    if PALETTE[top] and PALETTE[bottom] then painted[tex] = {top, nil, bottom} end
    if type(CreateColor) == "function" and type(tex.SetGradient) == "function" then
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1)) then return true end
    end
    if type(tex.SetGradientAlpha) == "function" and pcall(tex.SetGradientAlpha, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], 1, top[1], top[2], top[3], 1) then return true end
    paint(tex, bottom)
    return false
end
T.paint, T.gradient = paint, gradient

--- A texture from Media/Polestar (a line glyph or a piece of the band), tinted with a palette colour.
function T.Art(tex, name, c, alpha)
    if not tex or tex:SetTexture(ART .. name) == false then return false end
    tex.evertallyArt = name
    if type(tex.SetTexCoord) == "function" then tex:SetTexCoord(0, 1, 0, 1) end
    if c then paint(tex, c, alpha) end
    return true
end
function T.Glyph(parent, name, size, c, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetSize(size or 16, size or 16); T.Art(tex, name, c or C.mist)
    return tex
end
T.ART = ART

-- The schemes: the one in use, its choices and the switch. A new scheme fills the palette in place and repaints
-- what was painted with it; pages draw their text again on the next refresh.
function T.SchemeKey()
    local s = A.db and A.db.settings
    local key = s and s.uiScheme
    -- With the guide loaded its colours are the default; a scheme chosen by hand stays.
    if key == "guide" or key == nil then return guideTheme() and "guide" or DEFAULT end
    return SCHEMES[key] and key or DEFAULT
end
--- Whether Evertally draws in the guide's look (its colours, square shapes, underlined tabs).
function T.Flat() return T.scheme == "guide" end
function T.ApplyScheme(key)
    key = SCHEMES[key] and key or T.SchemeKey()
    T.scheme = key
    fillPalette(key)
    for tex, how in pairs(painted) do
        if how[3] then gradient(tex, how[1], how[3]) else paint(tex, how[1], how[2]) end
    end
    return key
end
function T.SetScheme(key)
    if not SCHEMES[key] or not A.db then return false end
    if key == "guide" and not guideTheme() then return false end
    A.db.settings.uiScheme = key
    T.ApplyScheme(key)
    if A.RefreshUI then A.RefreshUI() end
    return true
end
if type(A.On) == "function" then A.On("PLAYER_LOGIN", function()
    T.ApplyScheme()
    -- A new skin, accent or font in the guide: Evertally follows while it draws in the guide's look.
    local th = guideTheme()
    if th and type(th.OnChanged) == "function" and not T.followsGuide then
        T.followsGuide = true
        th.OnChanged(function()
            if T.scheme ~= "guide" then return end
            T.ApplyScheme("guide")
            if A.ApplyFonts then A.ApplyFonts() end
            if A.RefreshUI then A.RefreshUI() end
        end)
    end
end) end

-- The night band: the sky (a white mask fading downwards, tinted with the scheme's dome colour) with a faint haze.
-- No stars: the band stays a calm gradient. The art is 1024x128 drawn 1:1 (T.FitBand shows its top-left corner).
local BAND_W, BAND_H = 1024, 128
function T.Band(parent, height, layer)
    local sky = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 2)
    T.Art(sky, "band", C.dome, 1)
    sky:SetHeight(height or 72)
    local haze = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 4)
    T.Art(haze, "glow", C.haze); haze:SetPoint("TOP", sky, "TOP", 0, 0); haze:SetHeight(math.min(110, (height or 72) * 1.4))
    if type(haze.SetTexCoord) == "function" then haze:SetTexCoord(0, 1, 0.5, 1) end
    return {sky = sky, haze = haze, height = height or 72}
end
function T.FitBand(band, width)
    if not band then return end
    width = math.max(1, tonumber(width) or 640)
    local x1, y1 = math.min(1, width / BAND_W), math.min(1, band.height / BAND_H)
    for _, tex in ipairs({band.sky}) do if type(tex.SetTexCoord) == "function" then tex:SetTexCoord(0, x1, 0, y1) end end
    band.haze:SetWidth(width * 0.8)
end

local function line(parent, pointA, pointB, c, size, inset, alpha, layer)
    local tex = parent:CreateTexture(nil, layer or "BORDER")
    local a = pointA:find("LEFT") and inset or -inset
    local b = pointB:find("LEFT") and inset or -inset
    local ay = pointA:find("TOP") and -inset or inset
    local by = pointB:find("TOP") and -inset or inset
    tex:SetPoint(pointA, parent, pointA, a, ay); tex:SetPoint(pointB, parent, pointB, b, by)
    if pointA:find("TOP") and pointB:find("BOTTOM") then tex:SetWidth(size) else tex:SetHeight(size) end
    paint(tex, c, alpha)
    return tex
end
T.Line = line

-- The window: square, 1px lines, the band, the gold rim with its light and the corner jewels.
local function windowSurface(frame, skin)
    skin.base:Show(); paint(skin.base, C.canvas, 1)
    skin.band = T.Band(frame, 76)
    skin.band.sky:SetPoint("TOPLEFT", 1, -1); skin.band.sky:SetPoint("TOPRIGHT", -1, -1)
    T.FitBand(skin.band, (tonumber(frame:GetWidth()) or 640) - 2)
    for _, p in ipairs({{"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"}, {"TOPLEFT", "BOTTOMLEFT"}, {"TOPRIGHT", "BOTTOMRIGHT"}}) do
        skin.lines[#skin.lines + 1] = line(frame, p[1], p[2], C.line, 1, 0)
    end
    -- the gold rim and the light it throws into the band
    skin.rim = line(frame, "TOPLEFT", "TOPRIGHT", C.gold, 1, 0, 0.9, "ARTWORK")
    skin.throw = frame:CreateTexture(nil, "BORDER")
    T.Art(skin.throw, "glow", C.gold, 0.22)
    if type(skin.throw.SetTexCoord) == "function" then skin.throw:SetTexCoord(0, 1, 0.5, 1) end
    skin.throw:SetPoint("TOPLEFT", 40, -1); skin.throw:SetPoint("TOPRIGHT", -40, -1); skin.throw:SetHeight(26)
    skin.corners = {}
    for _, corner in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
        local x = corner:find("LEFT") and 3 or -3; local y = corner:find("TOP") and -3 or 3
        local jewel = frame:CreateTexture(nil, "OVERLAY"); jewel:SetSize(7, 7); jewel:SetPoint("CENTER", frame, corner, x, y); paint(jewel, C.gold, 1)
        if type(jewel.SetRotation) == "function" then pcall(jewel.SetRotation, jewel, math.pi / 4) end
        local core = frame:CreateTexture(nil, "OVERLAY"); core:SetSize(3, 3); core:SetPoint("CENTER", jewel, "CENTER"); paint(core, C.bright, 1)
        skin.corners[#skin.corners + 1] = {jewel, core}
    end
    return skin
end

function T.Surface(frame, role)
    if frame.evertallySkin then return frame.evertallySkin end
    local fillColor = role == "window" and C.canvas or role == "reader" and C.well or C.card
    local skin = {role = role, lines = {}}
    frame.evertallySkin = skin
    skin.base = frame:CreateTexture(nil, "BACKGROUND"); skin.base:SetAllPoints(frame)
    if role == "window" then return windowSurface(frame, skin) end
    if T.Shape(skin.base, "round") then
        -- Rounded: one opaque tinted body and a thin outline, nothing else.
        skin.shaped = true; paint(skin.base, fillColor, 1)
        skin.top = frame:CreateTexture(nil, "BACKGROUND"); skin.top:SetPoint("TOPLEFT"); skin.top:SetPoint("TOPRIGHT"); skin.top:SetHeight(28)
        T.Shape(skin.top, "round"); paint(skin.top, fillColor, 1); skin.top:Hide()
        skin.ring = frame:CreateTexture(nil, "BORDER"); skin.ring:SetAllPoints(frame); T.Shape(skin.ring, "ring")
        if role == "primary" then paint(skin.ring, C.bright, 0.35) else paint(skin.ring, C.line) end
        skin.lines[1] = skin.ring
        return skin
    end
    -- Without 9-slice: a square body with 1px lines (the native backdrop remains a fallback without colour textures).
    if type(frame.SetBackdrop) ~= "function" and type(BackdropTemplateMixin) == "table" and type(Mixin) == "function" then pcall(Mixin, frame, BackdropTemplateMixin) end
    if type(frame.SetBackdrop) == "function" then
        pcall(frame.SetBackdrop, frame, {bgFile = "Interface\\Buttons\\WHITE8X8", tile = false, insets = {left = 0, right = 0, top = 0, bottom = 0}})
        if type(frame.SetBackdropColor) == "function" then pcall(frame.SetBackdropColor, frame, fillColor[1], fillColor[2], fillColor[3], 1) end
    end
    paint(skin.base, fillColor, 1)
    skin.top = frame:CreateTexture(nil, "BACKGROUND"); skin.top:SetPoint("TOPLEFT", 1, -1); skin.top:SetPoint("TOPRIGHT", -1, -1); skin.top:SetHeight(28)
    paint(skin.top, fillColor, 1)
    for _, p in ipairs({{"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"}, {"TOPLEFT", "BOTTOMLEFT"}, {"TOPRIGHT", "BOTTOMRIGHT"}}) do
        skin.lines[#skin.lines + 1] = line(frame, p[1], p[2], C.line, 1, 0)
    end
    return skin
end

--- A button's ground: gold for the main action, a quiet raised panel for the rest.
function T.Button(button, primary)
    local skin = T.Surface(button, primary and "primary" or "button")
    paint(skin.base, primary and C.gold or C.raised, 1)
    if skin.top then skin.top:Hide() end
    -- (square, the guide's look: the backdrop Surface gave it is in the card's colour and can cover the body; the body is
    -- the button's whole colour)
    if not skin.shaped and type(button.SetBackdropColor) == "function" then pcall(button.SetBackdropColor, button, 0, 0, 0, 0) end
    return skin.base
end
