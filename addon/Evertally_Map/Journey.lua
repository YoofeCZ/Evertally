local _, M = ...
-- Lazy shortest-path validation: unknown walks are lower bounds, never an
-- itinerary we tell the player to follow. Resolve the selected walks and search
-- again until no cheaper untested alternative beats the fully searched journey.
local J = {cache = {}, order = {}, limit = 192}
M.Journey = J

local function complete(job)
    if job.onDone then local callback=job.onDone;job.onDone=nil;callback(job) end
    return job.state
end

function J.Available()
    return M.RoadPath and M.Terrain and M.Terrain.RoadBacked and M.Terrain.RoadBacked(0) and M.Terrain.RoadBacked(1)
end

local function remember(key, value)
    if J.cache[key] == nil then J.order[#J.order + 1] = key end
    J.cache[key] = value
    while #J.order > J.limit do J.cache[table.remove(J.order, 1)] = nil end
end

function J.Cancel(job)
    if not job then return end
    for _, pending in pairs(job.pending or {}) do M.RoadPath.Cancel(pending.search) end
    job.pending, job.state = {}, "cancelled"
end

local function startWalk(job, step, geometry)
    local key = step.walkKey
    if not key then return false end
    local c,x,y = M.ToYards(step.fu,step.fv)
    local other,tx,ty = M.ToYards(step.tu,step.tv)
    if c ~= other or not M.RoadPath.HasData(c) then job.costs[key] = false; return false end
    local z = math.abs(step.fu-job.from.u)<0.0000001 and math.abs(step.fv-job.from.v)<0.0000001 and job.options.fromZ or nil
    local cacheKey = key .. (z and (":z" .. string.format("%.0f", z)) or "")
    local record = J.cache[cacheKey]
    if record ~= nil and (not geometry or record==false or record.path) then job.costs[key] = record; return false end
    if (x-tx)^2+(y-ty)^2 < 0.0001 then
        record = {cost=0,path={{step.fu,step.fv},{step.tu,step.tv}}}
        remember(cacheKey,record);job.costs[key]=record;return false
    end
    job.pending[key] = {search=M.RoadPath.Begin(c,x,y,tx,ty,{fromZ=z,roads=true,costOnly=not geometry}),continent=c,cacheKey=cacheKey}
    return true
end

function J.Begin(from, to, options)
    local opts={};for key,value in pairs(options or {}) do opts[key]=value end
    local job = {from=from,to=to,options=opts,state="pending",costs={},pending={},rounds=0}
    return job
end

function J.Step(job)
    if not job or job.state ~= "pending" then return job and job.state end
    local waiting = false
    for key, pending in pairs(job.pending) do
        local search = pending.search
        if search.state == "pending" then M.RoadPath.Step(search) end
        if search.state == "pending" then waiting = true
        else
            local record = false
            if search.state == "ready" and search.result then
                local frame = M.data.yards[pending.continent]
                local path = search.result.points and {} or nil
                for _,p in ipairs(search.result.points or {}) do path[#path+1]={frame[1]+p[2]*frame[2],frame[3]+p[1]*frame[4],p[3]} end
                record={cost=search.result.cost or search.result.yards,path=path}
            elseif search.reason == "decoder_unavailable" or search.reason == "error" then
                job.reason=search.reason;J.Cancel(job);job.state="failed";return complete(job)
            end
            remember(pending.cacheKey,record);job.costs[key]=record;job.pending[key]=nil
        end
    end
    if waiting then return job.state end
    -- Limit purely arithmetic replans in one frame; collision jobs share the
    -- provider's existing 2ms budget with the arrow and map previews.
    for _=1,4 do
        job.options.validateWalks,job.options.walkCosts=true,job.costs
        local plan=M.PlanJourney(job.from,job.to,job.options)
        job.rounds=job.rounds+1
        if not plan then job.state,job.reason="failed","no_route";return complete(job) end
        local untested=false
        for _,step in ipairs(plan.steps) do
            if step.needsValidation then
                untested=true
                if not job.pending[step.walkKey] then startWalk(job,step) end
            end
        end
        if not untested then
            local missingGeometry=false
            for _,step in ipairs(plan.steps) do
                if step.mode=="walk" and step.walkKey and not step.routePath then
                    missingGeometry=true
                    if not job.pending[step.walkKey] then startWalk(job,step,true) end
                end
            end
            if not missingGeometry then job.plan,job.state=plan,"ready";return complete(job) end
        end
        if next(job.pending) then return job.state end
    end
    return job.state
end

local driver=CreateFrame("Frame")
J.active=setmetatable({},{__mode="k"})
local begin=J.Begin
function J.Begin(...)
    local job=begin(...);J.active[job]=true;return job
end
driver:SetScript("OnUpdate",function()
    for job in pairs(J.active) do
        if job.state=="pending" then J.Step(job) else J.active[job]=nil end
    end
end)
