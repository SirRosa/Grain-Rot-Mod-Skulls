_G.GRAINROT_SKULLS_TEST=true
dofile("ue4ss/Mods/GrainRotSkulls/Scripts/main.lua")
local c=assert(GrainRotSkullsCore)
local count=0
local function eq(got,expected,label)
  count=count+1
  assert(got==expected,(label or "test")..": expected "..tostring(expected).." got "..tostring(got))
end
local function rng(sequence)
  local i=0
  return function()
    i=i+1
    return assert(sequence[i],"extra draw")
  end
end
eq(c.percent(50,100),50,"50%")
eq(c.percent(20,100),20,"20%")
eq(c.percent(100,100),100,"100%")
eq(c.percent(1,1),100,"fractional 100%")
eq(c.percent(0.5,1),50,"fractional 50%")
eq(c.percent(-50,100),0,"lower clamp")
eq(c.percent(150,100),100,"upper clamp")
eq(c.percent(0/0,100),nil,"NaN")
eq(c.percent("unknown",100),nil,"unavailable level")
local p=c.plan({50,20},rng({0.49,0.19}))
eq(p[1].skull,true,"50 hit")
eq(p[2].skull,true,"20 hit")
eq(p[3],nil,"two players don't fill 3")
p=c.plan({50,20},rng({0.50,0.20}))
eq(p[1].skull,false,"50 boundary")
eq(p[2].skull,false,"20 boundary")
p=c.plan({100,100,100},rng({0.05,0.50,0.999}))
eq(#p,3,"three players have three slots")
for i=1,3 do eq(p[i].skull,true,"100% guarantees "..i) end
local patch=c.replace({1,2,3},p,77,88)
for i=1,3 do eq(patch[i],77,"three skull IDs "..i) end
local zero=c.plan({0,0,0},rng({0,0.5,0.9}))
for i=1,3 do eq(zero[i].skull,false,"zero percent "..i) end
patch=c.replace({77,12,77},zero,77,88)
eq(patch[1],88,"vanilla skull cleared when miss")
eq(patch[2],12,"native non-skull retained")
eq(patch[3],88,"third skull cleared when miss")
local sorted=c.plan({20,100,50},rng({0.1,0.1,0.1}))
eq(sorted[1].chance,100,"sort first")
eq(sorted[2].chance,50,"sort second")
eq(sorted[3].chance,20,"sort third")
eq(#c.plan({100,100,100,100},rng({0.1,0.1,0.1})),3,"max three slots")
patch=c.replace({1,2,3},c.plan({100},rng({0.1})),77,88)
eq(patch[1],77,"one player's slot")
eq(patch[2],2,"second unassigned")
eq(patch[3],3,"third unassigned")
local ok=pcall(c.replace,{1,2,3},p,77,77)
eq(ok,false,"skull and blank IDs must differ")
ok=pcall(c.replace,{1,2,3},p,-1,88)
eq(ok,false,"negative ID invalid")
ok=pcall(c.replace,{1,2,3},p,65536,88)
eq(ok,false,"out of uint16 ID invalid")
print("PASS "..count.." assertions (pure Lua mocks, not UE4SS runtime)")
