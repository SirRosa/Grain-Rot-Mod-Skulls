-- Mock UE4SS end-to-end: no players, no Grain Rot, three skulls.
local callbacks={}
local loop=nil
local function obj(name,fields)
  fields=fields or {}
  function fields:IsValid() return true end
  function fields:GetFullName() return name end
  return fields
end
local skull=obj("Row.Skull",{ModiferID=31,DataName="ExtraEnemy",DataAssetName="ExtraEnemy_DungeonMod",RandomWeight=0.1,MaxCount=1,RequiredLevel=20})
local map=obj("Row.Map",{ModiferID=15,DataName="ShowMap",DataAssetName="Map_DungeonMod",RandomWeight=10,MaxCount=1})
local darkness=obj("Row.Dark",{ModiferID=9,DataName="Darkness",DataAssetName="Darkness_DungeonMod",RandomWeight=5,MaxCount=1})
local datatable=obj("DataTable /Game/Data/DungeonModifers.DungeonModifers",{})
function datatable:ForEachRow(fn)
  fn("ExtraEnemy",skull);fn("ShowMap",map);fn("Darkness",darkness)
end
local data=obj("HeldenDataSingleton /Script/Helden.GameData",{DungeonModiferDataTable=datatable})
local gm=obj("HeldenGameMode /Game/Test.GameMode",{})
local seed={Seed=300,Level=12,ModiferIDs={15,9,15}}
local dungeon=obj("HeldenDungeonActor /Game/Test.Dungeon",{CurrentSeed=seed})
local gs=obj("HeldenGameState /Game/Test.GameState",{CurrentDungeonRun={DungeonActor=dungeon}})
local db={
  HeldenGameMode={gm},
  GameModeBase={gm},
  HeldenDataSingleton={data},
  HeldenGameState={gs},
  HeldenDungeonActor={dungeon},
  DataTable={datatable},
  HeldenPlayerController={}, -- vital: players are irrelevant
}
function FindAllOf(class) return db[class] or {} end
function FindFirstOf(class) return (db[class] or {})[1] end
function RegisterHook(name,pre,post)
  callbacks[name]={pre=pre,post=post}
  return 1,2
end
function LoopInGameThreadWithDelay(ms,fn) loop=fn;return 1 end
dofile("ue4ss/Mods/GrainRotSkulls/Scripts/main.lua")
assert(type(loop)=="function","timer must be active")
loop()
assert(skull.MaxCount==3 and skull.RandomWeight==1000000 and skull.RequiredLevel==0,
  "skull row not tuned")
assert(map.RandomWeight==0 and darkness.RandomWeight==0,"other weights not suppressed")
for i=1,3 do assert(seed.ModiferIDs[i]==31,"seed slot "..i.." not forced") end
local roll=assert(callbacks["/Script/Helden.HeldenElevatorMachine:StartDungeonRoll_Auth"])
seed.Seed=301
seed.ModiferIDs={9,15,9}
roll.pre(gm)
roll.post(gm)
for i=1,3 do assert(seed.ModiferIDs[i]==31,"new roll slot "..i.." not forced") end
print("PASS mocked engine interaction: DataTable weight patch, 3 native seed slots, second roll, zero players")
