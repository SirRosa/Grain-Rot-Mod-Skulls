# GrainRotSkulls 0.2.0-alpha — ALWAYS THREE RED SKULLS

UE4SS Lua mod for GRAIN ROT. It **ignores all player Grain Rot values and player counts**. Goal: **ExtraEnemy / big red skull on all three elevator modifier slots for every descent**.

## How v0.2 differs from v0.1

v0.1 attempted to capture each player's Grain Rot only inside a native roll hook and apply a modifier patch after the native RNG. If the hook was not called or the row ID could not be resolved, absolutely nothing happened. v0.2 does NOT depend on that hook to start:

1. On host game thread, it locates the actual \`/Game/Data/DungeonModifers.DungeonModifers\` DataTable.
2. It resolves the **real** \`ModiferID\` for \`ExtraEnemy\` from its row (not the enum's underlying implementation value).
3. It writes \`RandomWeight=1000000\`, \`MaxCount=3\`, \`RequiredLevel=0\` to the skull modifier and \`RandomWeight=0\` to all others (before the elevator roll).
4. It additionally patches the first three elements of the actual \`HeldenDungeonActor.CurrentSeed.ModiferIDs\` to the three identical skull IDs, with a readback check. This happens on a low-frequency timer and on real engine hooks.
5. It NEVER calls the native world regeneration methods itself and NEVER edits saved files or the game binary.

## Install

Download \`GrainRotSkulls-v0.2.0-alpha\` from a **successful v0.2 GitHub Actions run** in the [Actions tab](https://github.com/SirRosa/Grain-Rot-Mod-Skulls/actions). Unzip directly into the game's **UE4SS root**, yielding \`Mods/GrainRotSkulls/Scripts/main.lua\` and \`Mods/GrainRotSkulls/enabled.txt\`. **Remove the old GrainRotSkulls folder first**. Install on the **host**. No extra DLL needed.

## What to look for in UE4SS.log

Log lines:
- \`v0.2.0-alpha LOADED\` — Lua mod actually started
- \`TABLE TUNED ... ExtraEnemy ID=<value>\` — verified DataTable writes completed
- \`SEED FORCED ... readback OK\` or \`SEED ALREADY TRIPLE-SKULL\` — the native seed has three matching IDs

Warnings are deliberately explicit. A readback is **not** equivalent to confirmed native gameplay/UI/client replication.

## Known limitations — do not confuse with working in-game behavior

- Tests check Lua logic and a **mock engine** (table and seed writes, no player), plus syntax. Real UE4SS/game multiplayer is **not yet verified**.
- Some game builds may roll fewer than three \`ModiferIDs\` and keep blank slots implicit. Since native TArray resizing in UE4SS 3.0.x can be unsafe, v0.2 only overwrites three already existing entries; if fewer, it emits \`ModiferIDs has N entries\` instead of potentially crashing the game. Table weights are still tuned.
- \`ExtraEnemy.MaxCount\` may not be the only native uniqueness restriction, and changing \`CurrentSeed\` after dungeon creation might not cause game effects to reapply. **Three skulls visible and active in the actual game remain unconfirmed until a real host run.**
- Table changes can affect all modifier rolls during this game process and reset after restart or unloading the mod. No intentional save modifications.

If it still shows vanilla symbols, provide the **UE4SS.log from the host** after one attempt so the startup logs / native hook activation / DataTable row discovery can be diagnosed rather than guessing another API.
