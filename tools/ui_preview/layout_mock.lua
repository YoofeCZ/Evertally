-- A small model of WoW's frames with REAL anchoring, so the add-on's windows can be laid out and drawn without the game.
-- It resolves SetPoint/SetSize/SetAllPoints into rectangles, measures text roughly, fires OnSizeChanged the way the client does and
-- exports every visible object for tools/ui_preview/preview.py to draw. Used only for previews; the unit tests keep their simple mock.
-- Text widths are estimates (0.55 em per character); the real fonts differ a little, overlaps and spills are real.
local SCREEN_W, SCREEN_H = SCREEN_W or 1600, SCREEN_H or 900
local VERSION = 0
local function dirty() VERSION = VERSION + 1 end
local COUNTER = 0
local FX = {TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = .5, CENTER = .5, BOTTOM = .5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1}
local FY = {TOPLEFT = 0, TOP = 0, TOPRIGHT = 0, LEFT = .5, CENTER = .5, RIGHT = .5, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1}
local LAYER = {BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5}

local O = {}
local mt = {__index = function(t, k)
    local m = O[k]
    if m ~= nil then return m end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end}
local ALL = {}

local function new(kind, parent, name)
    COUNTER = COUNTER + 1
    local o = setmetatable({_kind = kind, _parentFrame = parent, _id = COUNTER, _points = {}, _shown = true, _alpha = 1, _scripts = {}, _children = {}, _regions = {},
        _text = "", _fontSize = 12, _color = {1, 1, 1, 1}, _wrap = true, _justify = "CENTER", _level = parent and ((parent._level or 1) + 1) or 1, _lastW = 0, _lastH = 0}, mt)
    if name then _G[name] = o; o._name = name end
    ALL[#ALL + 1] = o
    return o
end
local function isRegion(o) return o._kind == "Texture" or o._kind == "FontString" end

-- ---------------------------------------------------------------- text
local function plainText(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|")) end
local function chars(s) return select(2, s:gsub("[^\128-\191]", "")) end
local function lineWidth(o, s)   -- capitals are wider than small letters
    local capitals = select(2, s:gsub("%u", ""))
    return ((chars(s) - capitals) * 0.53 + capitals * 0.68) * (o._fontSize or 12)
end
local function textWidth(o)
    local best = 0
    for line in (plainText(o._text) .. "\n"):gmatch("(.-)\n") do best = math.max(best, lineWidth(o, line)) end
    return best
end
local function lineCount(o, width)
    local n = 0
    for line in (plainText(o._text) .. "\n"):gmatch("(.-)\n") do
        local w = lineWidth(o, line)
        n = n + ((o._wrap and width and width > 1) and math.max(1, math.ceil(w / width - 1e-6)) or 1)
    end
    return math.max(1, n)
end

-- ---------------------------------------------------------------- layout
local function effScale(o)
    local s, f = 1, o
    while f do s = s * (f._scale or 1); f = f._parentFrame end
    return s
end
local rectOf
local function compute(o)
    if o == UIParent then return 0, 0, SCREEN_W, SCREEN_H end
    local pts = o._points
    local es = effScale(o)
    local intrinsicW = ((o._kind == "FontString") and textWidth(o) or 0) * es
    if #pts == 0 then
        local sp = o._scrollParent
        if sp then
            local sl, st = rectOf(sp)
            return sl, st - (sp._vscroll or 0), (o._w or 0) * es, (o._h or 0) * es
        end
        o._unanchored = true
        local pl, pt = rectOf(o._parentFrame or UIParent)
        local w = o._w and o._w * es or intrinsicW
        return pl, pt, w, o._h and o._h * es or (o._kind == "FontString" and lineCount(o, w / es) * o._fontSize * 1.25 * es or 0)
    end
    local left, right, cx, top, bottom, cy
    for _, p in ipairs(pts) do
        local rel = p.rel or o._parentFrame or UIParent
        local rl, rt, rw, rh = rectOf(rel)
        local ax = rl + FX[p.relPoint or p.point] * rw + p.x * es
        local ay = rt + FY[p.relPoint or p.point] * rh - p.y * es
        local fx, fy = FX[p.point], FY[p.point]
        if fx == 0 then left = ax elseif fx == 1 then right = ax else cx = ax end
        if fy == 0 then top = ay elseif fy == 1 then bottom = ay else cy = ay end
    end
    local w = o._w and o._w * es
    local x0, width
    if left and right then x0, width = left, right - left
    elseif left then width = w or intrinsicW; x0 = left
    elseif right then width = w or intrinsicW; x0 = right - width
    elseif cx then width = w or intrinsicW; x0 = cx - width / 2
    else local pl = rectOf(o._parentFrame or UIParent); width = w or intrinsicW; x0 = pl end
    width = math.max(0, width)
    local h = o._h and o._h * es
    if o._kind == "FontString" and not h then h = lineCount(o, width / es) * o._fontSize * 1.25 * es end
    local y0, height
    if top and bottom then y0, height = top, bottom - top
    elseif top then height = h or 0; y0 = top
    elseif bottom then height = h or 0; y0 = bottom - height
    elseif cy then height = h or 0; y0 = cy - height / 2
    else local _, pt = rectOf(o._parentFrame or UIParent); height = h or 0; y0 = pt end
    return x0, y0, width, math.max(0, height)
end
rectOf = function(o)
    if o._ver == VERSION then return o._l, o._t, o._w, o._h end
    if o._busy then return 0, 0, 0, 0 end
    o._busy = true
    local l, t, w, h = compute(o)
    o._busy = false
    o._ver, o._l, o._t, o._w, o._h = VERSION, l, t, w, h
    return l, t, w, h
end

-- ---------------------------------------------------------------- methods
local function parsePoint(self, point, a, b, c, d)
    local rel, relPoint, x, y
    if a == nil or type(a) == "number" then x, y = a or 0, b or 0
    else
        rel = a
        if type(rel) == "string" then rel = _G[rel] end
        if type(b) == "string" then relPoint = b; x, y = c or 0, d or 0 else x, y = b or 0, c or 0 end
    end
    for i, p in ipairs(self._points) do if p.point == point then table.remove(self._points, i) break end end
    self._points[#self._points + 1] = {point = point, rel = rel, relPoint = relPoint, x = x, y = y}
    dirty()
end
function O.SetPoint(self, point, a, b, c, d) parsePoint(self, point, a, b, c, d) end
function O.ClearAllPoints(self) self._points = {}; dirty() end
function O.SetAllPoints(self, rel)
    if rel == nil or rel == true then rel = self._parentFrame end
    self._points = {{point = "TOPLEFT", rel = rel, x = 0, y = 0}, {point = "BOTTOMRIGHT", rel = rel, x = 0, y = 0}}
    dirty()
end
function O.SetSize(self, w, h) self._w, self._h = w, h; dirty() end
function O.SetWidth(self, w) self._w = w; dirty() end
function O.SetHeight(self, h) self._h = h; dirty() end
function O.GetWidth(self) local _, _, w = rectOf(self); return w end
function O.GetHeight(self) local _, _, _, h = rectOf(self); return h end
function O.GetSize(self) local _, _, w, h = rectOf(self); return w, h end
function O.GetParent(self) return self._parentFrame end
function O.SetParent(self, p) self._parentFrame = p; dirty() end
-- (the client runs OnShow and OnHide when a frame's visibility changes)
local function setShown(self, v)
    v = v and true or false
    local was = self._shown
    self._shown = v
    dirty()
    if v ~= was then
        local fn = self._scripts[v and "OnShow" or "OnHide"]
        if fn then fn(self) end
    end
end
function O.SetShown(self, v) setShown(self, v) end
function O.Show(self) setShown(self, true) end
function O.Hide(self) setShown(self, false) end
function O.IsShown(self) return self._shown end
function O.IsVisible(self)
    local o = self
    while o do if not o._shown then return false end; o = o._parentFrame end
    return true
end
function O.SetAlpha(self, a) self._alpha = a end
function O.GetAlpha(self) return self._alpha end
function O.SetFrameLevel(self, l) self._level = l end
function O.GetFrameLevel(self) return self._level end
function O.SetScript(self, k, fn) self._scripts[k] = fn end
function O.GetScript(self, k) return self._scripts[k] end
function O.HasScript(self, k) return self._scripts[k] ~= nil end
function O.SetScale(self, s) self._scale = s; dirty() end
function O.GetScale(self) return self._scale or 1 end
function O.GetEffectiveScale(self) return effScale(self) end
function O.SetClipsChildren(self, v) self._clip = v and true or false end
function O.GetLeft(self) local l = rectOf(self); return l end
function O.GetTop(self) local _, t = rectOf(self); return t end
function O.SetRotation(self, r) self._rotation = r end
function GetCursorPosition() return CURSOR_X or 0, CURSOR_Y or 0 end
function O.GetName(self) return self._name end
-- text
function O.SetText(self, v) self._text = v == nil and "" or tostring(v); dirty() end
function O.SetBackdrop(self, spec) self._backdrop = spec end
function O.SetBackdropColor(self, r, g, b, a)
    if not self._backdrop then return end
    if not self._backdropTexture then self._backdropTexture = self:CreateTexture(nil, "BACKGROUND"); self._backdropTexture:SetAllPoints(self) end
    self._backdropTexture:SetColorTexture(r, g, b, a or 1)
end
function O.GetText(self) return self._text end
function O.SetFont(self, path, size) self._fontPath = path; self._fontSize = size or 12; dirty(); return true end
function O.GetFont(self) return self._fontPath, self._fontSize end
function O.SetTextColor(self, r, g, b, a) self._color = {r, g, b, a or 1} end
function O.SetJustifyH(self, v) self._justify = v end
function O.SetJustifyV(self, v) self._justifyV = v end
function O.SetWordWrap(self, v) self._wrap = v and true or false; dirty() end
function O.GetStringWidth(self) return textWidth(self) end
function O.GetStringHeight(self) local _, _, w = rectOf(self); return lineCount(self, w) * self._fontSize * 1.25 end
-- textures
function O.SetTexture(self, a, g, b, c)
    if type(a) == "number" and g ~= nil and type(g) == "number" then self._rgba = {a, g, b, c or 1}; self._path = nil
    else self._path = a; self._rgba = nil end
    return true
end
function O.SetColorTexture(self, r, g, b, a) self._rgba = {r, g, b, a or 1}; self._path = nil end
function O.SetVertexColor(self, r, g, b, a) self._tint = {r, g, b, a or 1} end
function O.SetTexCoord(self, ...) self._coords = {...} end
function O.SetGradient(self, orientation, c1, c2) self._gradient = {orientation, c1, c2} end
function O.SetGradientAlpha(self, orientation, r1, g1, b1, a1, r2, g2, b2, a2) self._gradient = {orientation, {r = r1, g = g1, b = b1, a = a1}, {r = r2, g = g2, b = b2, a = a2}} end
function CreateColor(r, g, b, a) return {r = r, g = g, b = b, a = a or 1} end
function O.GetTexture(self) return self._path end
-- buttons
function O.SetNormalTexture(self, path) self._normalPath = path end
function O.SetHighlightTexture() end
function O.SetPushedTexture() end
function O.GetNormalTexture() return nil end
-- scroll frames
function O.SetScrollChild(self, child) self._scrollChild = child; child._scrollParent = self; child._parentFrame = self; dirty() end
function O.GetVerticalScroll(self) return self._vscroll or 0 end
function O.SetVerticalScroll(self, v) self._vscroll = v; dirty() end
function O.GetVerticalScrollRange(self) local sc = self._scrollChild; if not sc then return 0 end; return math.max(0, (sc._h or 0) - (self._h or select(4, rectOf(self)))) end
function O.EnableMouseWheel() end
-- edit boxes
function O.SetNumeric() end
function O.SetMaxLetters() end
function O.HighlightText() end
function O.ClearFocus() end
-- creation
function O.CreateTexture(self, name, layer)
    local t = new("Texture", self, name); t._layer = LAYER[layer or "ARTWORK"] or 3; t._layerName = layer or "ARTWORK"
    self._regions[#self._regions + 1] = t; return t
end
function O.CreateFontString(self, name, layer)
    local t = new("FontString", self, name); t._layer = LAYER[layer or "OVERLAY"] or 4; t._layerName = layer or "OVERLAY"
    self._regions[#self._regions + 1] = t; return t
end
function O.CreateLine(self) return O.CreateTexture(self) end

function CreateFrame(kind, name, parent, template)
    parent = parent or UIParent
    local f = new(kind or "Frame", parent, name)
    f._template = template
    if f._kind == "ScrollFrame" then f._clip = true end
    if parent then parent._children[#parent._children + 1] = f end
    return f
end
UIParent = new("Frame", nil, "UIParent")
UIParent.w, UIParent.h = SCREEN_W, SCREEN_H
UISpecialFrames = {}
function IsControlKeyDown() return false end

-- ---------------------------------------------------------------- events the client sends and the export
-- OnSizeChanged fires for visible frames whose size changed; the add-on reacts by re-laying out, so repeat until nothing changes.
function PREVIEW_SETTLE()
    for _ = 1, 12 do
        local changed = false
        for _, o in ipairs(ALL) do
            if not isRegion(o) and o._scripts.OnSizeChanged and o:IsVisible() then
                local _, _, w, h = rectOf(o)
                if math.abs(w - o._lastW) > 0.01 or math.abs(h - o._lastH) > 0.01 then
                    o._lastW, o._lastH = w, h
                    o._scripts.OnSizeChanged(o, w, h)
                    changed = true
                end
            end
        end
        if not changed then return end
    end
end

local function describe(o, clipIn, alphaIn, out, order)
    local l, t, w, h = rectOf(o)
    local node = {kind = o._kind, l = l, t = t, w = w, h = h, alpha = alphaIn * (o._alpha or 1), order = order, unanchored = o._unanchored}
    if o._kind == "Texture" then
        node.rgba, node.path, node.tint, node.gradient, node.layerName = o._rgba, o._path, o._tint, o._gradient, o._layerName
        if o._gradient then
            local g = o._gradient
            node.gradient = {g[1], {g[2].r, g[2].g, g[2].b, g[2].a or 1}, {g[3].r, g[3].g, g[3].b, g[3].a or 1}}
        end
    elseif o._kind == "FontString" then
        node.text, node.size, node.color, node.justify, node.wrap, node.fontPath = plainText(o._text) ~= "" and o._text or "", o._fontSize, o._color, o._justify, o._wrap, o._fontPath
    else
        node.template, node.text, node.name, node.hasClick = o._template, o._text, o._name, o._scripts.OnClick ~= nil
        local caption = rawget(o, "text")   -- the add-on's own buttons keep their caption as .text (a FontString)
        if type(caption) == "table" and caption._kind == "FontString" then node.hasCaption, node.captionEmpty = true, plainText(caption._text) == "" end
        node.normalPath = o._normalPath
    end
    node.clip = clipIn
    out[#out + 1] = node
    return node
end

local function walk(f, clipIn, alphaIn, out, counter)
    if not f._shown then return end
    counter.n = counter.n + 1
    local node = describe(f, clipIn, alphaIn, out, counter.n)
    local clip = clipIn
    if f._clip then
        local l, t, w, h = rectOf(f)
        if clipIn then
            local nl, nt = math.max(l, clipIn[1]), math.max(t, clipIn[2])
            local nr, nb = math.min(l + w, clipIn[1] + clipIn[3]), math.min(t + h, clipIn[2] + clipIn[4])
            clip = {nl, nt, math.max(0, nr - nl), math.max(0, nb - nt)}
        else clip = {l, t, w, h} end
    end
    local alpha = alphaIn * (f._alpha or 1)
    local regions = {}
    for _, r in ipairs(f._regions) do if r._shown and r._layer ~= 5 then regions[#regions + 1] = r end end
    table.sort(regions, function(a, b) if a._layer ~= b._layer then return a._layer < b._layer end return a._id < b._id end)
    for _, r in ipairs(regions) do counter.n = counter.n + 1; describe(r, clip, alpha, out, counter.n) end
    local kids = {}
    for _, c in ipairs(f._children) do kids[#kids + 1] = c end
    if f._scrollChild then local present = false; for _, c in ipairs(kids) do if c == f._scrollChild then present = true end end; if not present then kids[#kids + 1] = f._scrollChild end end
    table.sort(kids, function(a, b) if (a._level or 1) ~= (b._level or 1) then return (a._level or 1) < (b._level or 1) end return a._id < b._id end)
    for _, c in ipairs(kids) do walk(c, clip, alpha, out, counter) end
end

--- Every visible object under the given frame (default: all of UIParent) in drawing order, as plain tables.
function PREVIEW_EXPORT(root)
    PREVIEW_SETTLE()
    local out = {}
    walk(root or UIParent, nil, 1, out, {n = 0})
    return out
end
function PREVIEW_UNANCHORED()
    local list = {}
    for _, o in ipairs(ALL) do
        if o._kind ~= "Texture" and o._kind ~= "FontString" or o._text ~= "" or o._path or o._rgba then
            if #o._points == 0 and o ~= UIParent and not o._scrollParent and o:IsVisible() and (isRegion(o) or o._w or o._h) then list[#list + 1] = (o._name or o._kind) .. "#" .. o._id end
        end
    end
    return list
end
