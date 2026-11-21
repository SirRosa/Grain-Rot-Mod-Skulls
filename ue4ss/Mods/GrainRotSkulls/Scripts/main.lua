-- GrainRotSkulls v0.2.0-alpha: always force 3 ExtraEnemy (red skull) elevator modifiers.
-- UE4SS Lua, authoritative host only. Never edits save files.
local CFG = {
    SKULL_ASSET = "ExtraEnemy",    -- confirmed in game ObjectDump (ExtraEnemy_DungeonMod)
    SKULL_WEIGHT = 1000000,
    FORCE_MODIFIER_COUNT = 3,
    TICK_MS = 500,
    RETUNE_EVERY_TICKS = 20,
    MAX_SCAN_ROWS = 256,
    DIAGNOSTICS = true,
}
local TAG="[GrainRotSkulls] "
local function log(message) print(TAG..tostring(message).."\n") end
local function get(o,key)
    if o==nil then return nil end
    local ok,r=pcall(function() return o[key] end)
    if ok then return r end
end
local function valid(o)
    if o==nil then return false end
    local ok,r=pcall(function() return o:IsValid() end)
    return ok and r==true
end
local function fullname(o)
    if o==nil then return "nil" end
    local ok,r=pcall(function() return o:GetFullName() end)
    return ok and tostring(r) or tostring(o)
end
local function isCDO(o)
    return fullname(o):find("Default__",1,true)~=nil
end
local function unwrap(x)
    if x==nil then return nil end
    local ok,r=pcall(function() return x:get() end)
    if ok and r~=nil then return r end
    return x
end
local function ueName(x)
    x=unwrap(x)
    if x==nil then return "" end
    local ok,r=pcall(function() return x:ToString() end)
    if ok and r then return tostring(r) end
    return tostring(x)
end
local function number(x)
    local v=tonumber(unwrap(x))
    if v and v==v and v~=math.huge and v~=-math.huge then return v end
end
local function uint16(x)
    local n=number(x)
    if n and n>=0 and n<=65535 and n==math.floor(n) then return n end
end
local function all(class,includeCDO)
    local ok,list=pcall(FindAllOf,class)
    if not ok or not list then return {} end
    local okN,n=pcall(function() return #list end)
    if not okN or type(n)~="number" then return {} end
    local out={}
    for i=1,math.min(n,256) do
        local okItem,item=pcall(function() return list[i] end)
        if okItem and valid(item) and (includeCDO or not isCDO(item)) then
            out[#out+1]=item
        end
    end
    return out
end
local function first(class,includeCDO)
    local values=all(class,includeCDO)
    if values[1] then return values[1] end
    local ok,v=pcall(FindFirstOf,class)
    if ok and valid(v) and (includeCDO or not isCDO(v)) then return v end
end

-- Pure, testable policy. The ExtraEnemy implementation enum (2) is NOT its row ID.
local Core={}
function Core.matchSkull(rowName,assetName,dataName)
    local text=(ueName(rowName).."|"..ueName(assetName).."|"..ueName(dataName)):lower()
    return text:find("extraenemy",1,true)~=nil
end
function Core.values(isSkull)
    if isSkull then
        return {RandomWeight=CFG.SKULL_WEIGHT,MaxCount=3,RequiredLevel=0}
    end
    return {RandomWeight=0}
end
function Core.force(ids,skullId)
    assert(uint16(skullId),"invalid skull modifier ID")
    return {skullId,skullId,skullId}
end
_G.GrainRotSkullsCore=Core
if rawget(_G,"GRAINROT_SKULLS_TEST") then return end

local S={
    ticks=0,rolls=0,skullId=nil,tableRef=nil,lastTableSignature=nil,
    warnings={},seenSeeds={},loggedHooks={},liveChanges=0,
}
local function warnOnce(key,message)
    if S.warnings[key] then return end
    S.warnings[key]=true
    log("WARNING: "..message)
end
local function host()
    return first("HeldenGameMode",false)~=nil or first("GameModeBase",false)~=nil
end
local function selectedDataTable()
    if valid(S.tableRef) then return S.tableRef end
    local candidates=all("HeldenDataSingleton",true)
    local f=first("HeldenDataSingleton",true)
    if f then candidates[#candidates+1]=f end
    for _,singleton in ipairs(candidates) do
        local table=get(singleton,"DungeonModiferDataTable")
        if valid(table) then
            S.tableRef=table
            log("DataTable found through HeldenDataSingleton: "..fullname(table))
            return table
        end
    end
    -- The actual asset is present in the verified ObjectDump, even if the
    -- singleton is a CDO or not instantiated yet.
    for _,table in ipairs(all("DataTable",true)) do
        if fullname(table):find("DungeonModifers.DungeonModifers",1,true) then
            S.tableRef=table
            log("DataTable found via object registry: "..fullname(table))
            return table
        end
    end
end
local function rowRecords(dt)
    local found,seen={},{}
    local function add(name,row)
        if row==nil then return end
        local v=unwrap(get(row,"Data") or row)
        local id=uint16(get(v,"ModiferID"))
        if not id then return end
        local key=ueName(name)..":"..tostring(id)
        if seen[key] then return end
        seen[key]=true
        if #found<CFG.MAX_SCAN_ROWS then
            found[#found+1]={
                name=ueName(name),id=id,row=v,
                skull=Core.matchSkull(name,get(v,"DataAssetName"),get(v,"DataName")),
            }
        end
    end
    local ok,err=pcall(function()
        dt:ForEachRow(function(name,row) add(name,row) end)
    end)
    if #found==0 then
        local okMap,map=pcall(function() return dt:GetRowMap() end)
        if okMap and type(map)=="table" then
            for name,row in pairs(map) do add(name,row) end
        end
    end
    if #found==0 then
        local okRows,rows=pcall(function() return dt:GetAllRows() end)
        if okRows and type(rows)=="table" then
            for _,entry in ipairs(rows) do
                local name=get(entry,"Name")
                local okRef,ref=pcall(function() return dt:FindRow(ueName(name)) end)
                add(name,(okRef and ref) or get(entry,"Data"))
            end
        end
    end
    if #found==0 then
        warnOnce("rows","modifier DataTable rows inaccessible (ForEachRow: "..tostring(err)..")")
    end
    return found
end
local function writeProperty(obj,key,value)
    local old=get(obj,key)
    if old==value then return true,false end
    local ok=pcall(function() obj[key]=value end)
    if not ok then return false,false end
    return get(obj,key)==value,true
end
local function tuneTable(origin)
    if not host() then return nil end
    local dt=selectedDataTable()
    if not valid(dt) then
        warnOnce("table","DungeonModiferDataTable not yet available on host")
        return nil
    end
    local rows=rowRecords(dt)
    local chosen=nil
    for _,entry in ipairs(rows) do
        if entry.skull then
            if chosen and chosen.id~=entry.id then
                warnOnce("ambiguous","multiple ExtraEnemy modifier IDs; refusing unsafe override")
                return nil
            end
            chosen=entry
        end
    end
    if not chosen then
        local sample={}
        for i=1,math.min(12,#rows) do sample[#sample+1]=rows[i].name.."="..rows[i].id end
        warnOnce("skullMissing","ExtraEnemy not found in table; seen "..#rows.." rows: "..table.concat(sample,", "))
        return nil
    end
    S.skullId=chosen.id
    local correct,failed=0,0
    local written=0
    for _,entry in ipairs(rows) do
        local desired=Core.values(entry.skull)
        for field,value in pairs(desired) do
            local ok,changed=writeProperty(entry.row,field,value)
            if ok then
                correct=correct+1
                if changed then written=written+1 end
            else
                failed=failed+1
            end
        end
    end
    if failed>0 then
        warnOnce("weights","DataTable changes did not persist for "..failed.." row fields")
    end
    if written>0 or S.lastTableSignature~=fullname(dt)..":"..chosen.id then
        log(string.format("TABLE %s origin=%s; rows=%d, fields OK=%d, failed=%d, changed=%d, ExtraEnemy ID=%d; target MaxCount=3, Weight=%d",
            (failed==0 and "TUNED" or "PARTIAL"),origin,#rows,correct,failed,written,
            chosen.id,CFG.SKULL_WEIGHT))
    end
    S.lastTableSignature=fullname(dt)..":"..chosen.id
    return S.skullId
end

local function activeDungeon()
    local gs=first("HeldenGameState",false)
    local run=gs and get(gs,"CurrentDungeonRun")
    local actor=run and get(run,"DungeonActor")
    if valid(actor) and not isCDO(actor) then return actor end
    return first("HeldenDungeonActor",false)
end
local function seedInfo(actor)
    if not valid(actor) or isCDO(actor) then return nil end
    local seed=get(actor,"CurrentSeed")
    local ids=seed and get(seed,"ModiferIDs")
    if ids==nil then return nil end
    local okN,n=pcall(function() return #ids end)
    if not okN or type(n)~="number" then return nil end
    local values={}
    for i=1,math.min(n,12) do
        local ok,v=pcall(function() return ids[i] end)
        values[i]=ok and uint16(v) or nil
    end
    return seed,ids,n,values
end
local function forceSeed(origin,actor)
    if not host() then return false end
    local id=S.skullId or tuneTable(origin)
    if not id then return false end
    actor=actor and unwrap(actor) or activeDungeon()
    if not valid(actor) or isCDO(actor) then return false end
    local seed,arr,count,old=seedInfo(actor)
    if not seed then return false end
    local key=fullname(actor)..":"..tostring(get(seed,"Seed"))..":"..tostring(get(seed,"Level"))
    if count<CFG.FORCE_MODIFIER_COUNT then
        -- UE4SS TArray is 1-indexed and supports indexed writes. The old v3.0.0
        -- append bug was patched upstream; verify each append and fail closed
        -- rather than calling Empty() or rebuilding a live native array.
        for index=count+1,CFG.FORCE_MODIFIER_COUNT do
            local success,err=pcall(function() arr[index]=id end)
            if not success then
                warnOnce("grow:"..key,
                    "native TArray append failed at slot "..index..": "..tostring(err))
                return false
            end
            local _,_,now=seedInfo(actor)
            if not now or now<index then
                warnOnce("grow:"..key,
                    "native TArray did not grow to slot "..index.."; table weights remain active")
                return false
            end
        end
        -- Reacquire the native array after potential buffer reallocation.
        seed,arr,count,old=seedInfo(actor)
        if not seed or count<3 then return false end
    end
    local forced=Core.force(old,id)
    if old[1]==id and old[2]==id and old[3]==id then
        if not S.seenSeeds[key] then
            S.seenSeeds[key]=true
            log("SEED ALREADY TRIPLE-SKULL via "..origin.." id="..id.." seed="..key)
        end
        return true
    end
    for i=1,3 do
        local ok,err=pcall(function() arr[i]=forced[i] end)
        if not ok then
            warnOnce("seedwrite:"..key,"native modifier array write failed: "..tostring(err))
            return false
        end
    end
    -- Nested reflected properties may require a write-through to UPROPERTY.
    pcall(function() seed.ModiferIDs=arr end)
    pcall(function() actor.CurrentSeed=seed end)
    local _,_,n,actual=seedInfo(actor)
    if n and n>=3 and actual[1]==id and actual[2]==id and actual[3]==id then
        S.liveChanges=S.liveChanges+1
        log(string.format("SEED FORCED via %s: [%s,%s,%s] -> [%d,%d,%d], readback OK, seed=%s",
            origin,tostring(old[1]),tostring(old[2]),tostring(old[3]),id,id,id,key))
        S.seenSeeds[key]=true
        return true
    end
    warnOnce("readback:"..key,"seed write not reflected in readback; no proof of change")
    return false
end
local function guard(label,fn)
    return function(...)
        local ok,err=pcall(fn,...)
        if not ok then warnOnce("error:"..label,"callback "..label.." failed: "..tostring(err)) end
    end
end
local function register(path,pre,post)
    local ok,err=pcall(RegisterHook,path,pre and guard(path.." PRE",pre) or nil,
        post and guard(path.." POST",post) or nil)
    if ok then
        log("registered native hook (execution not yet confirmed) "..path)
    else
        warnOnce("hook:"..path,"hook registration failed: "..tostring(err))
    end
end
local function beforeRoll(self)
    if not host() then return end
    S.rolls=S.rolls+1
    log("ROLL EVENT #"..S.rolls.." - forcing ExtraEnemy on host")
    tuneTable("roll-pre")
    forceSeed("roll-pre")
end
register("/Script/Helden.HeldenElevatorMachine:StartDungeonRoll_Auth",
    beforeRoll,function() forceSeed("roll-post") end)
register("/Script/Helden.HeldenElevatorMachine:OnStartPreSequence_Auth",
    function() tuneTable("presequence") end)
register("/Script/Helden.HeldenElevatorMachine:StartSymbolAnimation_Multicast",
    function() forceSeed("symbol-pre") end)
register("/Script/Helden.HeldenDungeonActor:RegenerateDungeon",
    function(actor) forceSeed("generate-pre",actor) end,
    function(actor) forceSeed("generate-post",actor) end)
register("/Script/Helden.HeldenElevatorMachine:OnFinishedSymbolAnimation",
    function() forceSeed("symbol-end") end)
local function tick()
    if not host() then return end
    S.ticks=S.ticks+1
    if S.skullId==nil or S.ticks==1 or S.ticks%CFG.RETUNE_EVERY_TICKS==0 then
        tuneTable("timer")
    end
    if S.skullId~=nil then forceSeed("timer") end
end
local ok,handle=pcall(LoopInGameThreadWithDelay,CFG.TICK_MS,guard("timer",tick))
if ok and handle~=nil then
    log("game-thread loop started: "..CFG.TICK_MS.." ms (no per-frame hook)")
else
    warnOnce("noLoop","LoopInGameThreadWithDelay unavailable: "..tostring(handle).."; native hooks only")
end
log("v0.2.0-alpha LOADED; always force 3 ExtraEnemy skulls; corruption and player count IGNORED")
