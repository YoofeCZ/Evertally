local _, M = ...
local ns = M._roadEngine
local Path = ns.Path
local P = {version = "SPF v1.35.0", source = "collision-8yd", budget = 2}
M.RoadPath = P

-- Route selection and smoothing use the same road flags/costs. A stable profile
-- key lets the solver reuse exact costs without sharing another addon's state.
local ROADS = {
    key = "evertally-roads-v1", roads = true,
    Point = function() return 1 end,
    Charged = function() return false end,
    Near = function() return false end,
    Chord = function() return 1 end,
}
local scheduled = {}
Path.after = function(callback) scheduled[#scheduled + 1] = callback end
Path.budget = P.budget

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function metric(a, b)
    local x, y = a[1] - b[1], a[2] - b[2]
    return math.sqrt(x * x + y * y)
end
function P.HasData(map)
    return finite(map) and Path.HasData(map) or false
end
function P.Begin(map, x, y, tx, ty, options)
    options = options or {}
    local data = ns.NavData[map]
    local job = {state = "pending", provider = "roads", steps = 0, expanded = 0, discovered = 0,
        map = {id = map, cell = data and (1600 / 3) / data.cells or 8}, from = {x, y}, to = {tx, ty}}
    if not P.HasData(map) then job.state, job.reason = "failed", "uncovered_map"; return job end
    if not (finite(x) and finite(y) and finite(tx) and finite(ty)) then job.state, job.reason = "failed", "invalid_position"; return job end
    if not (C_EncodingUtil and C_EncodingUtil.DecodeBase64 and C_EncodingUtil.DecompressString and Enum and Enum.CompressionMethod) then
        job.state, job.reason = "failed", "decoder_unavailable"; return job
    end
    local from = {map = map, x = x, y = y, z = finite(options.fromZ) and options.fromZ or nil}
    local to = {map = map, x = tx, y = ty, z = finite(options.toZ) and options.toZ or nil}
    local profile
    if options.roads ~= false then profile = ROADS end
    job.handle = Path.Find(map, from, to, function(points, cost, handle)
        if job.state ~= "pending" then return end
        job.expanded = handle.expansions or 0
        if not points or #points < 2 then job.state, job.reason = "failed", type(cost) == "string" and cost or "no_path"; return end
        local line, tails = {}, {}
        for _, point in ipairs(points) do line[#line + 1] = {point.x, point.y, point.z} end
        tails[#line] = 0
        for i = #line - 1, 1, -1 do tails[i] = tails[i + 1] + metric(line[i], line[i + 1]) end
        job.result = {points = line, tails = tails, yards = tails[1], cost = cost, mapId = map,
            snapped = metric(line[1], job.from) > 1 or metric(line[#line], job.to) > 1,
            roads = options.roads ~= false, validated = true, source = P.source}
        job.state = "ready"
    end, options.waterWalking == true, profile)
    return job
end

-- PathJobs owns per-search scratch, cancellation and fair round-robin scheduling.
-- Its original scheduler is replaced by this next-frame queue, retaining its 2ms
-- shared deadline. Step also works in offline replay without a game timer.
local driverActive, frame, lastFrame = false, 0, nil
function P.Step(job)
    if not job or job.state ~= "pending" then return job and job.state or "failed" end
    if driverActive and lastFrame == frame then return job.state, job.result, job.reason end
    lastFrame = frame
    local callback = table.remove(scheduled, 1)
    if callback then callback() end
    job.steps = job.steps + 1
    job.expanded = job.handle and job.handle.expansions or job.expanded
    return job.state, job.result, job.reason
end
function P.Cancel(job)
    if not job then return end
    if job.handle then Path.Cancel(job.handle) end
    job.state, job.reason, job.result = "cancelled", "cancelled", nil
end

-- A collision-aware connection must not be declared clear merely because both
-- 16-yard cells were standable. Arrival checks can use the actual <3yd endpoint.
function P.Clear() return false end

if type(CreateFrame) == "function" then
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function()
        driverActive, frame = true, frame + 1
        if #scheduled > 0 then
            local callback = table.remove(scheduled, 1)
            lastFrame = frame
            callback()
        end
    end)
end
