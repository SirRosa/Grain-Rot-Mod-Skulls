-- GrainRotSkulls v0.1.0-alpha. Native game integration MUST be verified live.
-- Authoritative host only; ExtraEnemy is the big RED skull.
local CFG = {
  ROT_SCALE=100, -- CurrentGrainRot 50 means 50%; change to 1 if game reports 0..1
  SKULL_NAME="ExtraEnemy", BLANK_NAME="Blank",
  TICK_MS=250, MAX_TICKS=32, VERBOSE=false,
}
local PREFIX="[GrainRotSkulls] "
local function log(s) print(PREFIX..tostring(s).."\n") end
local function get(o,k)
  if o==nil then return nil end
  local ok,v=pcall(function() return o[k] end)
  if ok then return v end
end
local function valid(o)
  if o==nil then return false end
  local ok,v=pcall(function() return o:IsValid() end)
  return ok and v==true
end
local function fullName(o)
  if o==nil then return "nil" end
  local ok,s=pcall(function() return o:GetFullName() end)
  return ok and tostring(s) or tostring(o)
end
local function live(o)
  return valid(o) and not fullName(o):find("Default__",1,true)
end
local function all(class)
  local ok,objs=pcall(FindAllOf,class)
  if not ok or objs==nil then return {} end
  local okN,n=pcall(function() return #objs end)
  if not okN or type(n)~="number" then return {} end
  local out={}
  for i=1,math.min(n,128) do
    local okV,v=pcall(function() return objs[i] end)
    if okV and live(v) then out[#out+1]=v end
  end
  return out
end
local function first(class)
  local a=all(class)
  if a[1] then return a[1] end
  local ok,v=pcall(FindFirstOf,class)
  if ok and live(v) then return v end
end
local function uint16(v)
  local n=tonumber(v)
  if n and n==n and n>=0 and n<=65535 and math.floor(n)==n then return n end
end

-- Probability rules are pure Lua, shared with executable CI tests.
local Core={}
function Core.percent(value,scale)
  local n=tonumber(value)
  if not n or n~=n or n==math.huge or n==-math.huge or not scale or scale<=0 then return nil end
  return math.max(0,math.min(100,100*n/scale))
end
function Core.plan(percentages,rng)
  local p={}
  for _,v in ipairs(percentages) do
    if type(v)=="number" then p[#p+1]=math.max(0,math.min(100,v)) end
  end
  table.sort(p,function(a,b) return a>b end)
  local slots={}
  for i=1,math.min(3,#p) do
    local roll=rng()
    assert(type(roll)=="number" and roll>=0 and roll<=1,"invalid RNG")
    slots[i]={chance=p[i],skull=roll<p[i]/100}
  end
  return slots
end
function Core.replace(original,slots,skullID,blankID)
  assert(uint16(skullID) and uint16(blankID) and skullID~=blankID,"invalid modifier IDs")
  local result={}
  for i=1,#original do result[i]=original[i] end
  for i=1,math.min(3,#slots) do
    if slots[i].skull then result[i]=skullID
    elseif result[i]==skullID then result[i]=blankID end
  end
  return result
end
_G.GrainRotSkullsCore=Core
if rawget(_G,"GRAINROT_SKULLS_TEST") then return end

local state={roll=0,pending=nil,ids=nil,warnings={}}
local function warn(key,s)
  if state.warnings[key] then return end
  state.warnings[key]=true
  log("WARNING "..s)
end
local function host()
  return first("HeldenGameMode")~=nil or first("GameModeBase")~=nil
end
local function corruption(pc)
  local ok,pawn=pcall(function() return pc:GetPawn() end)
  if not ok or not live(pawn) or not live(get(pawn,"CharacterStats")) then
    pawn=get(pc,"LastPlayerChar")
  end
  local stats=live(pawn) and get(pawn,"CharacterStats")
  if not live(stats) then return nil end
  return Core.percent(get(stats,"CurrentGrainRot"),CFG.ROT_SCALE)
end
local function squad()
  local values,seen={},{}
  for _,pc in ipairs(all("HeldenPlayerController")) do
    local key=fullName(pc)
    if not seen[key] then
      seen[key]=true
      local p=corruption(pc)
      if p then
        values[#values+1]=p
        if CFG.VERBOSE then log(key.." corruption="..p.."%") end
      else
        warn("rot:"..key,"cannot read CurrentGrainRot for player "..key)
      end
    end
  end
  return values
end

-- DataTable row IDs are different from EHeldenDungeonModiferImplementation.
-- Resolve both IDs by the game's real asset names; never guess constants.
local function textValue(value)
  if value==nil then return "" end
  local ok,s=pcall(function() return value:ToString() end)
  if ok and s then return tostring(s) end
  return tostring(value)
end
local function analyzeRow(found,row)
  local v=get(row,"Data") or row
  local id=uint16(get(v,"ModiferID"))
  if not id then return end
  local name=(textValue(get(v,"DataName")).." "..textValue(get(v,"DataAssetName"))):lower()
  local function add(key,needle)
    if not name:find(needle:lower(),1,true) then return end
    if found[key]~=nil and found[key]~=id then found[key]=false
    elseif found[key]==nil then
      found[key]=id
      found[key.."MaxCount"]=tonumber(get(v,"MaxCount"))
    end
  end
  add("skull",CFG.SKULL_NAME)
  add("blank",CFG.BLANK_NAME)
  -- Native selection may limit repeated skulls: increase only the identified
  -- ExtraEnemy row to three, and verify a real reflected row write.
  if name:find(CFG.SKULL_NAME:lower(),1,true) then
    local old=tonumber(get(v,"MaxCount"))
    if old and old>0 and old<3 then
      local success=pcall(function() v.MaxCount=3 end)
      local actual=tonumber(get(v,"MaxCount"))
      if success and actual==3 then
        found.skullMaxCount=3
        found.capRaised=true
      else
        found.capRaiseFailed=true
      end
    end
  end
end
local function examine(found,collection)
  if not collection then return end
  if type(collection)=="table" then
    for _,v in pairs(collection) do analyzeRow(found,v) end
    return
  end
  local ok,n=pcall(function() return #collection end)
  if not ok or type(n)~="number" then return end
  for i=1,math.min(n,1024) do
    local okItem,v=pcall(function() return collection[i] end)
    if okItem then analyzeRow(found,v) end
  end
end
local function resolve()
  if state.ids then return state.ids end
  local singleton=first("HeldenDataSingleton")
  local dt=singleton and get(singleton,"DungeonModiferDataTable")
  if not valid(dt) then
    warn("table","DungeonModiferDataTable unavailable; no modifier changes")
    return nil
  end
  local found={}
  -- ForEachRow is the documented working route in our GrainRotQOL mod;
  -- other UE4SS builds use the row map / GetAllRows alternatives.
  local okEach,errEach=pcall(function()
    dt:ForEachRow(function(_,row) analyzeRow(found,row) end)
  end)
  if not okEach and CFG.VERBOSE then log("ForEachRow unavailable: "..tostring(errEach)) end
  local ok,rows=pcall(function() return dt:GetAllRows() end)
  if ok then examine(found,rows) end
  if type(found.skull)~="number" or type(found.blank)~="number" then
    local okMap,m=pcall(function() return dt:GetRowMap() end)
    if okMap then examine(found,m) end
  end
  if type(found.skull)~="number" or type(found.blank)~="number" then
    local okNames,names=pcall(function() return dt:GetRowNames() end)
    if okNames and names then
      local okLen,n=pcall(function() return #names end)
      if okLen and type(n)=="number" then
        for i=1,math.min(n,1024) do
          local okName,name=pcall(function() return names[i] end)
          if okName then
            local okRow,row=pcall(function() return dt:FindRow(name) end)
            if okRow then analyzeRow(found,row) end
          end
        end
      end
    end
  end
  if type(found.skull)~="number" or type(found.blank)~="number" or found.skull==found.blank then
    warn("ids","ExtraEnemy/Blank ModiferIDs unresolved or ambiguous. No guess, no patch")
    return nil
  end
  state.ids=found
  log(string.format("DataTable IDs: ExtraEnemy=%d Blank=%d ExtraEnemy.MaxCount=%s",
    found.skull,found.blank,tostring(found.skullMaxCount)))
  if found.capRaised then log("raised live ExtraEnemy MaxCount to 3 (verified readback)") end
  if found.capRaiseFailed or (found.skullMaxCount and found.skullMaxCount<3) then
    warn("maxcount","could not raise native ExtraEnemy MaxCount to 3; repeated skull effects unverified")
  end
  return found
end
local function dungeon()
  local gs=first("HeldenGameState")
  local run=gs and get(gs,"CurrentDungeonRun")
  local d=run and get(run,"DungeonActor")
  if live(d) then return d end
  return first("HeldenDungeonActor")
end
local function seedIDs(d)
  if not live(d) then return nil end
  local seed=get(d,"CurrentSeed")
  local arr=get(seed,"ModiferIDs")
  if not arr then return nil end
  local ok,n=pcall(function() return #arr end)
  if not ok or n~=3 then return nil end
  local vals={}
  for i=1,3 do
    local success,v=pcall(function() return arr[i] end)
    if not success then return nil end
    vals[i]=uint16(v)
    if not vals[i] then return nil end
  end
  return vals,seed,arr
end
local function identity(d)
  if not live(d) then return "no-dungeon" end
  local vals=seedIDs(d)
  local seed=get(d,"CurrentSeed")
  return fullName(d)..":"..tostring(get(seed,"Seed"))..":"..table.concat(vals or {},",")
end
local function apply(d,expected)
  local _,seed,arr=seedIDs(d)
  if not arr then return false,"missing modifier array" end
  for i=1,3 do
    local ok,err=pcall(function() arr[i]=expected[i] end)
    if not ok then return false,"array write "..i..": "..tostring(err) end
  end
  -- Best-effort outer struct propagation; direct array assignments come first.
  pcall(function() seed.ModiferIDs=arr end)
  pcall(function() d.CurrentSeed=seed end)
  local readback=seedIDs(d)
  if not readback then return false,"readback missing" end
  for i=1,3 do
    if readback[i]~=expected[i] then return false,"readback mismatch at "..i end
  end
  return true
end
local function tryApply(when,d,force)
  local p=state.pending
  if not p or not host() then return end
  if not live(d) then d=dungeon() end
  if not live(d) then return end
  if not force and identity(d)==p.before then return end
  local before=seedIDs(d)
  if not before then return end
  local ids=resolve()
  if not ids then return end
  local after=Core.replace(before,p.slots,ids.skull,ids.blank)
  local different=false
  for i=1,3 do if before[i]~=after[i] then different=true end end
  if different then
    local ok,err=apply(d,after)
    if not ok then
      warn("write:"..p.number,"roll "..p.number.." could not apply native seed: "..tostring(err))
      return
    end
  end
  local labels={}
  for i=1,3 do
    local s=p.slots[i]
    labels[i]=s and string.format("%.1f%%=%s",s.chance,s.skull and "SKULL" or "native")
       or "unassigned"
  end
  log(string.format("roll %d APPLIED via %s: [%s] => [%s]; [%s]",
    p.number,when,table.concat(before,","),table.concat(after,","),table.concat(labels,"; ")))
  state.pending=nil
end
local function unwrap(v)
  local ok,result=pcall(function() return v:get() end)
  if ok and result then return result end
  return v
end
local function rollPre(machine)
  if not host() or not live(unwrap(machine)) then return end
  local values=squad()
  if not resolve() then return end
  if #values==0 then
    warn("empty","no valid player corruption readings; leaving vanilla roll intact")
    return
  end
  state.roll=state.roll+1
  state.pending={number=state.roll,ticks=0,before=identity(dungeon()),
    slots=Core.plan(values,math.random)}
  local labels={}
  for i=1,3 do
    local s=state.pending.slots[i]
    labels[i]=s and string.format("%.1f%%",s.chance) or "vanilla"
  end
  log("roll "..state.roll.." captured; chances: "..table.concat(labels,", "))
end
local function guarded(name,fn)
  return function(...)
    local ok,err=pcall(fn,...)
    if not ok then warn("callback:"..name,name.." callback failed: "..tostring(err)) end
  end
end
local function hook(path,pre,post)
  local ok,err=pcall(RegisterHook,path,
    pre and guarded(path..":pre",pre) or nil,
    post and guarded(path..":post",post) or nil)
  if ok then log("hook registered (callback not proven): "..path)
  else warn("hook:"..path,"register hook failed: "..tostring(err)) end
end
hook("/Script/Helden.HeldenElevatorMachine:StartDungeonRoll_Auth",
    rollPre,function() tryApply("roll-post",dungeon(),false) end)
hook("/Script/Helden.HeldenDungeonActor:RegenerateDungeon",
    function(d) tryApply("regenerate-pre",unwrap(d),true) end)
hook("/Script/Helden.HeldenElevatorMachine:StartSymbolAnimation_Multicast",
    function() tryApply("animation-pre",dungeon(),false) end)
local function tick()
  local p=state.pending
  if not p or not host() then return end
  p.ticks=p.ticks+1
  if p.ticks>CFG.MAX_TICKS then
    warn("timeout:"..p.number,"roll "..p.number.." expired without native seed patch; NOT verified")
    state.pending=nil
    return
  end
  tryApply("seed-poll",dungeon(),false)
end
local ok,err=pcall(LoopInGameThreadWithDelay,CFG.TICK_MS,guarded("tick",tick))
if not ok then warn("timer","game-thread loop unavailable: "..tostring(err)) end
pcall(function() math.randomseed(os.time()) end)
log("v0.1.0-alpha loaded; authority host only; skull=ExtraEnemy; scale="..CFG.ROT_SCALE)
