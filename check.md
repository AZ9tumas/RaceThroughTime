

  

Audit all pet creation/modification paths

Searched for regex `.` (`**/src/ServerScriptService/Services/PetService.luau`), 5 results

Searched for regex `.` (`**/src/ServerScriptService/Services/EggService.luau`), 5 results

Searched for regex `.` (`**/src/ServerScriptService/Services/TradeService.luau`), 5 results

Searched for regex `.` (`**/src/ServerScriptService/Services/DataService.luau`), 5 results

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/PetService.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/EggService.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/TradeService.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/DataService.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/RebirthService.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/DailyRewardService.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/RedeemCodeService.luau)

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Modules/DevProducts.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ReplicatedStorage/Modules/Stats.luau#1-1), lines 1 to 200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/PetService.luau#200-200), lines 200 to 500

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/EggService.luau#200-200), lines 200 to 413

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/TradeService.luau#200-200), lines 200 to 500

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/DataService.luau#200-200), lines 200 to 492

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ReplicatedStorage/Modules/Stats.luau#200-200), lines 200 to 562

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Modules/DevProducts.luau#200-200), lines 200 to 323

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/RebirthService.luau#200-200), lines 200 to 520

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/DailyRewardService.luau#200-200), lines 200 to 371

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/PetService.luau#500-500), lines 500 to 900

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/TradeService.luau#500-500), lines 500 to 980

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/PetService.luau#900-900), lines 900 to 1200

Read [](file:///c%3A/Users/rouna/Desktop/RaceThroughTime/src/ServerScriptService/Services/PetService.luau#1200-1200), lines 1200 to 1688

Read [](file:///c%3A/Users/rouna/AppData/Roaming/Code/User/workspaceStorage/bc907311e3dc1bf7457ced57b75dd4ae/GitHub.copilot-chat/chat-session-resources/6c2fab8c-0312-485f-b50d-f58016237825/toolu_0154L5UFz6D8t7rJLP1ykADr__vscode-1771410898111/content.txt)

Here's the full audit of every code path where pets enter or are modified in a player's inventory:

---

## Pet Creation Paths & Properties Set

### 1. Egg Hatch / Purchase (EggService.luau)

Both `HatchEgg` and `PurchaseEgg` shallow-copy from `Stats.Pets[petType]` then set:
- All base stats from config (`Name`, `PetType`, `Multiplier`, `PickupRangeBonus`, `RoamRange`, `StarCollectionRadius`, `Velocity`, `World`, `TierLevel`, `Rarity`, `BaseTierLevel`, etc.)
- `ObtainedAt = os.time()` 
- `Locked = false` 
- Runtime ID via `PetService:RegisterPetID()` (not persisted — correct)
- `FireDataReady` called 

**Issues:** `Level` and `TierName` are not explicitly set. `Egg` array from config is unnecessarily persisted.

---

### 2. MergePets (PetService.luau)

Manually constructs new pet entry with: `Name`, `PetType`, `World`, `Level`, `TierLevel`, `TierName`, `Multiplier`, `PickupRangeBonus`, `RoamRange`, `StarCollectionRadius`, `Velocity`, `Equipped = false`, `Locked = false`.

**Issues:**
- **`ObtainedAt` is NOT set** — merged pets have no acquisition timestamp
- **`Rarity` is NOT set** — lost during merge
- **`ID = GeneratePetID()` is persisted** — stale GUID in datastore (runtime IDs are regenerated after, so this is just dirty data)

---

### 3. MergePetsWithException (PetService.luau)

Identical structure to MergePets — **same 3 issues** (missing `ObtainedAt`, missing `Rarity`, stale persisted `ID`).

---

### 4. Rebirth Pet Reward (RebirthService.luau)

Both `PerformRebirth` and `ForceRebirth` construct pet with: `PetType`, `Name` (with " (Rebirth)" suffix), `Multiplier`, `PickupRangeBonus`, `RoamRange`, `StarCollectionRadius`, `Velocity`, `World`, `Level`, `TierLevel`, `TierName = "Common"`, `Rarity = "Rebirth"`, `ObtainedAt = os.time()`.

**Issues:**
- **`Locked` is NOT set** — will be `nil` (functionally behaves as unlocked, but inconsistent)

---

### 5. Daily Reward Pet (DailyRewardService.luau)

Shallow-copies from `Stats.Pets[petId]` then sets `ObtainedAt = os.time()`.

**Issues:**
- **`Locked` is NOT set**
- **No `PetService:RegisterPetID()` call** — pet has no runtime ID until rejoin
- **No `FireDataReady` call** — client won't see the new pet until another data refresh

---

### 6. Trade (Received Pets) (TradeService.luau)

`CopyPetDataForTrade` does a deep copy of all original properties, then sets `ObtainedAt = os.time()` and `Locked = false`. Runtime IDs are regenerated via `PetService:InitializePets()`. `FireDataReady` called for both players. **This path is clean.**

---

## Pet Modification Paths

| Operation | What changes | Persisted? | FireDataReady? |
|---|---|---|---|
| **EquipPet** | Adds index to `EquippedPets` array | Yes | No (uses signals) |
| **UnequipPet** | Removes index from `EquippedPets` | Yes | No (uses signals) |
| **ToggleLockPet** | Toggles `Locked` on pet entry | Yes | **No** — client won't see change |
| **DeletePet** | Removes pet from `PetInventory`, adjusts indexes | Yes | Via signals |
| **Rebirth (wipe)** | Sets `PetInventory = {}`, `EquippedPets = {}` | Yes | Yes |

---

## Summary of Issues Found

### Critical

| # | Issue | Where |
|---|---|---|
| 1 | **`ObtainedAt` missing on merged pets** | `MergePets`, `MergePetsWithException` |
| 2 | **`Rarity` missing on merged pets** | `MergePets`, `MergePetsWithException` |
| 3 | **Daily reward pets: no `RegisterPetID` or `FireDataReady`** | `DailyRewardService` |
| 4 | **`InitializePets` sets expired pets to `nil` (creates array holes)** instead of using `table.remove` | `PetService:InitializePets` |

### Moderate

| # | Issue | Where |
|---|---|---|
| 5 | `Locked` not set on rebirth pets | `RebirthService` |
| 6 | `Locked` not set on daily reward pets | `DailyRewardService` |
| 7 | `ToggleLockPet` doesn't call `FireDataReady` | `PetService` |
| 8 | Stale `ID` GUID persisted in merged pet entries | `MergePets`, `MergePetsWithException` |
| 9 | `Equipped = false` unnecessarily persisted in merged pets | `MergePets`, `MergePetsWithException` |

### Property Presence Matrix

| Property | Egg | Merge | Rebirth | DailyReward | Trade |
|---|---|---|---|---|---|
| `ObtainedAt` | ✅ | **missing** | ✅ | ✅ | ✅ (reset) |
| `Locked` | ✅ | ✅ | **missing** | **missing** | ✅ |
| `Rarity` | ✅ | **missing** | ✅ | ✅ | ✅ |
| `TierName` | missing | ✅ | ✅ | missing | deep copy |
| `Level` | missing | ✅ | ✅ | missing | deep copy |
| `RegisterPetID` | ✅ | ✅ | ✅ | **missing** | ✅ |
| `FireDataReady` | ✅ | ✅ | ✅ | **missing** | ✅ |

Want me to fix all these issues?