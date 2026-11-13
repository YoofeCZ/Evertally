local _, M = ...
-- Facade over the collision/roads provider. The old 2-bit search remains for legacy
-- data and isolated grids; its standable cells do not prove a wall or cliff is passable.
local T={maps=M.terrainMaps or {},BATCH=192,MAX_NODES=32000,MAX_HEAP=64000}
M.Terrain=T
-- Keep identities, not a second alias of the mutable map table: callers and tests
-- can install a different grid without accidentally searching the real world map.
local bundledMaps={}
for id,map in pairs(T.maps) do bundledMaps[id]=map end
local function roadProvider(mapId)
    local R=M.RoadPath
    if type(R)~="table" or type(R.HasData)~="function" then return nil end
    if bundledMaps[mapId]~=nil then
        if T.maps[mapId]~=bundledMaps[mapId] then return nil end
    elseif T.maps[mapId]~=nil then return nil end
    if R.HasData(mapId)==true then return R end
end
function T.RoadBacked(mapId) return roadProvider(mapId)~=nil end
local floor,sqrt,abs,min,max=math.floor,math.sqrt,math.abs,math.min,math.max
local ALPHABET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local lookup={};for i=1,#ALPHABET do lookup[ALPHABET:byte(i)]=i-1 end
local POW={16,4,1};local SQRT2=sqrt(2)
local DX,DY={1,-1,0,0,1,1,-1,-1},{0,0,1,-1,1,-1,1,-1}
local function finite(n) return type(n)=="number" and n==n and abs(n)<1000000000 end
function T.Cell(map,x,y)
    if not map or x<0 or y<0 or x>=map.nx or y>=map.ny then return 0 end
    local at=x*map.ny+y;local value=lookup[map.data:byte(floor(at/3)+1)]
    return value and floor(value/POW[at%3+1])%4 or 0
end
local function cell(map,x,y) return floor((x-map.x0)/map.cell),floor((y-map.y0)/map.cell) end
local function centre(map,x,y) return {map.x0+(x+0.5)*map.cell,map.y0+(y+0.5)*map.cell} end
local function distance(a,b) local x,y=a[1]-b[1],a[2]-b[2];return sqrt(x*x+y*y) end
-- Supercover-like Bresenham: a diagonal cannot squeeze through a blocked corner.
local function clear(map,ax,ay,bx,by,dry,check)
    local dx,dy=abs(bx-ax),abs(by-ay);local sx,sy=ax<bx and 1 or -1,ay<by and 1 or -1;local err=dx-dy
    local function open(x,y) local value=T.Cell(map,x,y);return value~=0 and (not dry or value==1) end
    while true do
        if check then check() end
        if not open(ax,ay) then return false end
        if ax==bx and ay==by then return true end
        local e2=err*2
        if e2>-dy and e2<dx and (not open(ax+sx,ay) or not open(ax,ay+sy)) then return false end
        if e2>-dy then err=err-dy;ax=ax+sx end
        if e2<dx then err=err+dx;ay=ay+sy end
    end
end
function T.Clear(map,x,y,tx,ty,dry)
    if not map then return false end
    local R=roadProvider(map.id)
    if R then
        -- Arrival must not accept the coarse mask's apparent shortcut through a
        -- collision wall. Without a full-provider chord query, stay conservative.
        return type(R.Clear)=="function" and R.Clear(map.id,x,y,tx,ty,dry)==true or false
    end
    local ax,ay=cell(map,x,y);local bx,by=cell(map,tx,ty)
    return clear(map,ax,ay,bx,by,dry)
end
local function heapPush(heap,p,key)
    if heap.size>=T.MAX_HEAP then return false end
    local i=heap.size+1;heap.size=i
    while i>1 do local parent=floor(i/2);if heap.p[parent]<=p then break end;heap.p[i],heap.n[i]=heap.p[parent],heap.n[parent];i=parent end
    heap.p[i],heap.n[i]=p,key;return true
end
local function heapPop(heap)
    local key=heap.n[1];local p,n=heap.p[heap.size],heap.n[heap.size]
    heap.p[heap.size],heap.n[heap.size]=nil,nil;heap.size=heap.size-1
    if heap.size==0 then return key end
    local i=1
    while true do
        local child=i*2;if child>heap.size then break end
        if child<heap.size and heap.p[child+1]<heap.p[child] then child=child+1 end
        if heap.p[child]>=p then break end
        heap.p[i],heap.n[i]=heap.p[child],heap.n[child];i=child
    end
    heap.p[i],heap.n[i]=p,n;return key
end
local function checkpoint(job)
    job.work=job.work+1
    if job.work>=job.budget or (job.work%16==0 and job.deadline and debugprofilestop()>=job.deadline) then
        job.work=0;coroutine.yield()
    end
end
local function snap(map,x,y,check)
    if T.Cell(map,x,y)~=0 then return x,y end
    -- A small endpoint correction accommodates the mask's coarse cells. Never snap off-map locations.
    if x<0 or y<0 or x>=map.nx or y>=map.ny then return nil end
    for r=1,6 do
        local bx,by,bd
        for dx=-r,r do for dy=-r,r do
            if max(abs(dx),abs(dy))==r then
                check();local d=dx*dx+dy*dy
                if (not bd or d<bd) and T.Cell(map,x+dx,y+dy)~=0 then bx,by,bd=x+dx,y+dy,d end
            end
        end end
        if bx then return bx,by end
    end
end
local function solve(job)
    local map=job.map;local check=function() checkpoint(job) end
    local fx,fy=cell(map,job.from[1],job.from[2]);local tx,ty=cell(map,job.to[1],job.to[2])
    local ax,ay=snap(map,fx,fy,check);local bx,by=snap(map,tx,ty,check)
    if not ax or not bx then return nil,"blocked_endpoint" end
    local snapped=ax~=fx or ay~=fy or bx~=tx or by~=ty
    local start,goal=ax*map.ny+ay+1,bx*map.ny+by+1
    local scores,previous,closed={[start]=0},{},{}
    local heap={p={},n={},size=0};job.discovered=1
    local function heuristic(x,y) local dx,dy=abs(x-bx),abs(y-by);return dx+dy+(SQRT2-2)*min(dx,dy) end
    heapPush(heap,heuristic(ax,ay),start)
    local found=false
    while heap.size>0 do
        check();local here=heapPop(heap)
        if not closed[here] then
            closed[here]=true;job.expanded=job.expanded+1
            if here==goal then found=true;break end
            local x,y=floor((here-1)/map.ny),(here-1)%map.ny
            for d=1,8 do
                local nx,ny=x+DX[d],y+DY[d];local value=T.Cell(map,nx,ny)
                if value~=0 and (d<=4 or (T.Cell(map,nx,y)~=0 and T.Cell(map,x,ny)~=0)) then
                    local nextKey=nx*map.ny+ny+1
                    if not closed[nextKey] then
                        local cost=scores[here]+(d>4 and SQRT2 or 1)*(value==2 and 3 or 1)
                        if not scores[nextKey] or cost<scores[nextKey] then
                            if not scores[nextKey] then job.discovered=job.discovered+1;if job.discovered>job.limit then return nil,"node_limit" end end
                            scores[nextKey],previous[nextKey]=cost,here
                            if not heapPush(heap,cost+heuristic(nx,ny),nextKey) then return nil,"frontier_limit" end
                        end
                    end
                end
            end
        end
    end
    if not found then return nil,"no_path" end
    local reverse={};local here=goal
    while here do check();reverse[#reverse+1]={floor((here-1)/map.ny),(here-1)%map.ny};here=previous[here] end
    local cells={};for i=#reverse,1,-1 do check();cells[#cells+1]=reverse[i] end
    local points={centre(map,cells[1][1],cells[1][2])};local anchor=1
    -- Dry-land string pulling retains every bend required by the mask. Water keeps grid points.
    for i=3,#cells do
        local a,b=cells[anchor],cells[i]
        if not clear(map,a[1],a[2],b[1],b[2],true,check) then
            local c=cells[i-1];points[#points+1]=centre(map,c[1],c[2]);anchor=i-1
        end
    end
    points[#points+1]=centre(map,bx,by)
    if snapped then table.insert(points,1,job.from);points[#points+1]=job.to else points[1]=job.from;points[#points]=job.to end
    local tails={};tails[#points]=0
    for i=#points-1,1,-1 do check();tails[i]=tails[i+1]+distance(points[i],points[i+1]) end
    return {points=points,tails=tails,yards=tails[1],cost=scores[goal]*map.cell,snapped=snapped,mapId=map.id}
end
function T.Begin(mapId,x,y,tx,ty,options)
    options=options or {}
    local R=roadProvider(mapId)
    if R then
        local roadOptions={}
        for key,value in pairs(options) do roadOptions[key]=value end
        if roadOptions.roads==nil then roadOptions.roads=true end
        local job=R.Begin(mapId,x,y,tx,ty,roadOptions)
        job.provider,job._roadProvider="roads",R
        return job
    end
    local job={state="pending",map=T.maps[mapId],from={x,y},to={tx,ty},expanded=0,discovered=0,work=0,budget=T.BATCH,limit=min(T.MAX_NODES,max(1,tonumber(options.maxNodes) or T.MAX_NODES)),steps=0}
    if not job.map then job.state,job.reason="failed","uncovered_map"
    elseif not (finite(x) and finite(y) and finite(tx) and finite(ty)) then job.state,job.reason="failed","invalid_position"
    else job.co=coroutine.create(function() return solve(job) end) end
    return job
end
function T.Step(job,budget)
    if job and job.provider=="roads" then return job._roadProvider.Step(job,budget) end
    if not job or job.state~="pending" then return job and job.state or "failed" end
    job.budget=min(512,max(1,floor(tonumber(budget) or T.BATCH)));job.work=0;job.steps=job.steps+1
    job.deadline=type(debugprofilestop)=="function" and debugprofilestop()+2 or nil
    local ok,result,reason=coroutine.resume(job.co)
    if not ok then job.state,job.reason,job.co="failed","search_error",nil
    elseif coroutine.status(job.co)=="dead" then
        job.result,job.reason,job.state,job.co=result,reason,result and "ready" or "failed",nil
    end
    return job.state,job.result,job.reason
end
function T.Cancel(job)
    if job and job.provider=="roads" then return job._roadProvider.Cancel(job) end
    if job then job.state,job.reason,job.co,job.result="cancelled","cancelled",nil,nil end
end
