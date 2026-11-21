-- Tests of v0.2 production logic, including independent-of-players requirement.
_G.GRAINROT_SKULLS_TEST=true
dofile("ue4ss/Mods/GrainRotSkulls/Scripts/main.lua")
local C=assert(_G.GrainRotSkullsCore)
local n=0
local function eq(got,want,what)
    n=n+1
    assert(got==want,(what or "assert").." expected "..tostring(want).." got "..tostring(got))
end
local function force(original,id)
    local result=C.force(original,id)
    eq(#result,3,"three slots exactly")
    for i=1,3 do eq(result[i],id,"skull slot "..i) end
    return result
end
force({},42)
force({1},42)
force({1,2},42)
force({1,2,3},42)
force({1,2,3,4,5},42)
force({42,42,42},42)
force({0,0,0},0)
force({65535,0,18},65535)
eq(C.matchSkull("ExtraEnemy",nil,nil),true,"row by name")
eq(C.matchSkull("Whatever","ExtraEnemy_DungeonMod",nil),true,"row by asset")
eq(C.matchSkull("Whatever",nil,"ExtraEnemy"),true,"row by data")
eq(C.matchSkull("ExtraGold","Money_DungeonMod",nil),false,"gold != skull")
eq(C.matchSkull("Blank",nil,nil),false,"blank != skull")
eq(C.values(true).RandomWeight,1000000,"boost skull probability")
eq(C.values(true).MaxCount,3,"3 repeats allowed")
eq(C.values(true).RequiredLevel,0,"all levels")
eq(C.values(false).RandomWeight,0,"suppress other modifiers")
eq(C.values(false).MaxCount,nil,"don't alter other max count")
local ok=pcall(C.force,{},-1)
eq(ok,false,"invalid negative ID")
ok=pcall(C.force,{},65536)
eq(ok,false,"overflow ID")
ok=pcall(C.force,{},"invalid")
eq(ok,false,"invalid string")
print("PASS "..n.." policy assertions (mock, not actual game)")
