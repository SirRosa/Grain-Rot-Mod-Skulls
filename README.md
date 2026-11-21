# GrainRotSkulls v0.1.0-alpha

An experimental UE4SS Lua mod for GRAIN ROT, targeting the **big red skull** modifier (`ExtraEnemy`) in each of the three elevator symbols.

## Rules

The host reads each active player's `HeldenCharacter.CharacterStats.CurrentGrainRot` at elevator roll time. Players are sorted from highest to lowest percentage and assigned one per slot (up to three). Slots roll independently.

| Players' Grain Rot | Slot 1 | Slot 2 | Slot 3 |
| --- | --- | --- | --- |
| 50%, 20% | 50% skull | 20% skull | vanilla |
| 100% | 100% skull | vanilla | vanilla |
| 100%, 100%, 100% | 100% skull | 100% skull | 100% skull |
| 0%, 0%, 0% | 0% skull | 0% skull | 0% skull |

For an assigned slot, failing the chance leaves any pre-existing non-skull modifier as normal; an already-rolled skull is replaced with the game's `Blank` modifier to ensure the precise probability. With fewer than three players, unassigned slots stay vanilla.

## Install

Go to [Actions](https://github.com/SirRosa/Grain-Rot-Mod-Skulls/actions), open the latest successful **GrainRotSkulls - test and package** run, download the `GrainRotSkulls-v0.1.0-alpha` artifact, extract the ZIP into the **UE4SS root** so it creates `Mods/GrainRotSkulls/Scripts/main.lua` and `Mods/GrainRotSkulls/enabled.txt`. Install on the multiplayer **host**.

## How it works

Uses verified types and native function names in `SirRosa/Grain-Rot-Mod-Data-Base` (2026-11-20 USMAP / ObjectDump):

- `HeldenElevatorMachine:StartDungeonRoll_Auth` (roll hook)
- `HeldenDungeonActor.CurrentSeed.ModiferIDs` (three uint16 modifier IDs used for generation)
- `HeldenDungeonActor:RegenerateDungeon` (generation hook)
- `HeldenElevatorMachine:StartSymbolAnimation_Multicast`
- `HeldenStatsComponent.CurrentGrainRot` (per-player source)
- `HeldenDataSingleton.DungeonModiferDataTable` (dynamic `ExtraEnemy` and `Blank` IDs)

IDs are looked up from rows by `DataName/DataAssetName`. **Never substitute the ExtraEnemy implementation enum value (2) as a modifier row ID.** If rows cannot be resolved, the code logs a warning and leaves the native roll unchanged. Mod runs only in authoritative host/game-thread callbacks, not per-frame animation ticks, and does not directly edit player stats or saves.

## IMPORTANT: alpha / not game-tested

- GitHub Actions checks syntax and **simulated** probability rules. Native hook activation, timing, seed replication and correct symbol display at clients are not yet demonstrated in a real session.
- The native game can restrict repeated `ExtraEnemy` IDs with `MaxCount`. The mod attempts to raise the actual table row to `MaxCount=3`, verifies the write and logs the result. Three 100% players are guaranteed by Lua probability rules, but the game may still deduplicate or ignore repeated effects; this needs live verification.
- `CurrentGrainRot` defaults to a 0–100 scale. If a real log proves the game uses 0–1, change `ROT_SCALE` at the top of `main.lua` from 100 to 1.
- Successful hook registration does not prove a callback was invoked. A log line `roll N APPLIED` confirms only a Lua-side modifier-array readback, not that the UI, level generation, Steam achievement or multiplayer client obeyed it.

### Live verification

Test with two players at 100% and 0% (host/client) and then three players at 100%. Examine whether all three visible symbols and **actual effects** agree; check `UE4SS.log` for `roll captured`, `DataTable IDs`, `APPLIED`, any `MaxCount`, `expired`, or `unresolved` lines. Provide the log for follow-up corrections.
