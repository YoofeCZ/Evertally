local _, A = ...
-- A bounded data-only JSON codec; no code execution, library or network dependency.
local function escape(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        local e = { ['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
        return e[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end
function A.Encode(value)
    local seen, budget = {}, 0
    local function encode(v, depth)
        if depth > 14 then error("depth_limit") end
        budget = budget + 1
        if budget > 50000 then error("node_limit") end
        if A.Plain then v = A.Plain(v) end
        local t = type(v)
        if t == "nil" then return "null" end
        if t == "boolean" then return v and "true" or "false" end
        if t == "number" then
            if v ~= v or v == math.huge or v == -math.huge then error("non_finite") end
            return string.format("%.14g", v)
        end
        if t == "string" then return escape(v) end
        if t ~= "table" or seen[v] then error("unsupported_value") end
        seen[v] = true
        local length, count, array = #v, 0, true
        for k in pairs(v) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k > length or k ~= math.floor(k) then array = false end
        end
        if count ~= length then array = false end
        local out = {}
        if array then
            for i = 1, length do out[i] = encode(v[i], depth + 1) end
        else
            local keys = {}
            for k in pairs(v) do if type(k) ~= "string" then error("non_string_key") end; keys[#keys+1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do out[#out+1] = escape(k) .. ":" .. encode(v[k], depth + 1) end
        end
        seen[v] = nil
        return (array and "[" or "{") .. table.concat(out, ",") .. (array and "]" or "}")
    end
    local ok, result = pcall(encode, value, 0)
    if not ok then return nil, "invalid_data" end
    if #result > 1048576 then return nil, "size_limit" end
    return result
end

function A.Decode(text, maxBytes)
    if type(text) ~= "string" or #text > (maxBytes or 16384) then return nil, "size_limit" end
    local p, nodes, n = 1, 0, #text
    local function ws() local _, e = text:find("^[ \n\r\t]*", p); p = (e or p-1) + 1 end
    local function utf8(code)
        if code < 128 then return string.char(code) end
        if code < 2048 then return string.char(192+math.floor(code/64),128+code%64) end
        return string.char(224+math.floor(code/4096),128+math.floor(code/64)%64,128+code%64)
    end
    local function str()
        if text:sub(p,p) ~= '"' then error("string") end
        p=p+1; local out={}
        while p<=n do
            local c=text:sub(p,p);p=p+1
            if c=='"' then return table.concat(out) end
            if c=='\\' then
                local e=text:sub(p,p);p=p+1
                local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
                if e=='u' then
                    local hex=text:sub(p,p+3)
                    if #hex~=4 or not hex:match('^%x%x%x%x$') then error("unicode") end
                    local code=tonumber(hex,16);p=p+4
                    if code>=55296 and code<=57343 then error("surrogate_not_supported") end
                    out[#out+1]=utf8(code)
                elseif escapes[e] then out[#out+1]=escapes[e] else error("escape") end
            else
                if c:byte()<32 then error("control") end
                out[#out+1]=c
            end
        end
        error("unclosed_string")
    end
    local value
    value=function(depth)
        if depth>12 then error("depth_limit") end
        nodes=nodes+1;if nodes>10000 then error("node_limit") end
        ws();local c=text:sub(p,p)
        if c=='"' then return str() end
        if c=='{' or c=='[' then
            local object=c=='{';local finish=object and '}' or ']';p=p+1;ws();local out={};local seen={}
            if text:sub(p,p)==finish then p=p+1;return out end
            local i=1
            while true do
                ws();local key=i
                if object then
                    key=str();if seen[key] or key=='__proto__' or key=='constructor' or key=='prototype' then error("key") end
                    seen[key]=true;ws();if text:sub(p,p)~=':' then error("colon") end;p=p+1
                end
                out[key]=value(depth+1);i=i+1;ws();local nextc=text:sub(p,p);p=p+1
                if nextc==finish then return out end
                if nextc~=',' then error("comma") end
            end
        end
        for _, literal in ipairs({"true","false","null"}) do
            if text:sub(p,p+#literal-1)==literal then p=p+#literal;if literal=="null" then return nil end;return literal=="true" end
        end
        local token=text:match('^-?%d+%.?%d*[eE]?[+-]?%d*',p)
        if not token or not (token:match('^-?%d+$') or token:match('^-?%d+%.%d+$') or token:match('^-?%d+%.?%d*[eE][+-]?%d+$')) then error("number") end
        if token:match('^-?0%d') then error("leading_zero") end
        local number=tonumber(token);if not number or number~=number or number==math.huge or number==-math.huge then error("number") end
        p=p+#token;return number
    end
    local ok,result=pcall(value,0)
    if not ok then return nil,"invalid_json" end
    ws();if p<=n then return nil,"trailing_data" end
    return result
end
