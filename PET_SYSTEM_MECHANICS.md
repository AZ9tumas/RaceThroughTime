# Pet System Mechanics

This document details the technical implementation of the Pet System in Race Through Time, covering equipping, movement behaviors, and the merging mechanics.

## 1. Pet Equipping System

The equipping system bridges the persistent data layer with the physical game world.

### Equipping Process (`PetService.luau`)

1.  **Validation**:
    *   Checks if the player owns the pet (Inventory check).
    *   Checks if the pet is already equipped.
    *   Verifies against `Stats.MaxEquippedPets` limit.
2.  **Data Persistence**:
    *   Updates the `EquippedPets` array in the player's `Inventory` data profile.
3.  **Physical Spawning**:
    *   Calls `SpawnPetModel` to create the visual representation.
    *   Initializes `BodyPosition` constraints for physics-based movement.
    *   Registers the pet in the `SpawnedPets` session table.

### Unequipping

*   Removes the pet index from the `EquippedPets` data array.
*   Calls `DespawnPetModel` to destroy the physical model and clean up session data.

## 2. Pet Movement & Positioning

Pets use a physics-based movement system managed by `BodyPosition` constraints, updated via a heartbeat loop (`RunService.Heartbeat`).

### The Behavior Loop

The `UpdatePetBehavior` function runs approximately every 0.2 seconds (`PET_UPDATE_INTERVAL`) to determine where pets should move.

### State 1: Follow Mode (Default)

When the player is outside the Arena area, pets enter a formation behind the player.

**Formula for Positioning:**
The system uses trigonometric functions to distribute pets in a circle segment behind/around the player based on their `petIndex`.

$$
\vec{\text{Offset}} = \begin{bmatrix}
\cos\left(\text{index} \cdot \frac{\pi}{2}\right) \cdot D_{\text{follow}} \\
2 \\
\sin\left(\text{index} \cdot \frac{\pi}{2}\right) \cdot D_{\text{follow}}
\end{bmatrix}
$$

**Code Implementation:**
```lua
local offset = Vector3.new(
    math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
    2,
    math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
)
bodyPosition.Position = rootPart.Position + offset
```

*   `PET_FOLLOW_DISTANCE` is typically 8 studs.
*   The `BodyPosition` constraint interpolates the pet's position to this target, creating a smooth "floating" follow effect rather than a rigid attachment.

### State 2: Arena Mode (Collection)

When the player enters an arena (`CheckPlayerInArena` returns true):

1.  **Star Targeting**:
    *   The system searches for the nearest uncollected star that isn't already targeted by another pet.
2.  **Movement**:
    *   `BodyPosition.Position` is updated to the `TargetStar.Position`.
3.  **Collection**:
    *   If the distance to the star is less than `PET_STAR_COLLECTION_RADIUS` (5 studs), the star is collected server-side.

## 3. Pet Merging Mechanics

Merging allows players to combine two pets of the same tier to create a stronger version.

### Merge Logic (`PetService:MergePets`)

*   **Requirements**:
    *   Two pets of the same world and tier.
    *   Sufficient Gem currency.
*   **Outcome**:
    *   One pet is consumed (removed).
    *   One pet is upgraded (level/tier increased).

### Stat Growth Formula

The new stats are calculated using a multiplicative formula based on the rarity bonus defined in `PetMergeStats`.

$$
\text{NewStats} = \text{OldStats} \times (2 + \text{RarityBonus})
$$

Where:
*   **OldStats**: The current multiplier/fuel bonus of the base pet.
*   **2**: Base multiplier for merging (doubling power).
*   **RarityBonus**: Extra percentage based on tier (e.g., 0.10 for Rare, 0.30 for Epic).

**Code Reference (`PetMergeStats.luau`):**

```lua
-- Rarity Tiers Configuration
PetMergeStats.RarityTiers = {
    { Name = "Common", RarityBonus = 0.0, ... },
    { Name = "Rare",   RarityBonus = 0.10, ... },
    { Name = "Epic",   RarityBonus = 0.30, ... },
    -- ...
}
```

This geometric growth ensures that higher-tier pets become exponentially more powerful than their lower-tier counterparts, justifying the increasing "Grind Wall" (copies required) at higher levels.
