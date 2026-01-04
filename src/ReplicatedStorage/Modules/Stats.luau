--[[
	Stats Module
	Contains game statistics, star spawn probabilities, and fuel values.
]]

local Stats = {}

Stats.MaxBaseFuel = 1500
Stats.BaseSpeed = 50

-- World efficiency values for speed calculation
Stats.WorldEfficiency = {
	Main = 1,
}

-- World radius values for track movement (distance from center)
Stats.WorldRadius = {
	Main = 160,
}

-- Returns the maximum fuel value with multipliers applied
-- Currently returns base value * 1, can be extended for upgrades/boosts
function Stats.FuelMultiplier(): number
	return Stats.MaxBaseFuel * 1
end

-- Star Tiers and their spawn probabilities (must sum to 1.0)
-- Yellow (Common): Most frequent, low fuel bonus
-- Blue (Uncommon): Moderate spawn rate, medium fuel bonus
-- Purple (Rare): Low spawn rate, high fuel bonus
-- White (Legendary): Extremely rare, very high fuel bonus
Stats.StarProbabilities = {
	YellowStar = 0.60,   -- 60% chance (Common)
	BlueStar = 0.25,     -- 25% chance (Uncommon)
	PurpleStar = 0.12,   -- 12% chance (Rare)
	WhiteStar = 0.03,    -- 3% chance (Legendary)
}

-- Fuel bonuses for each star type
Stats.StarFuelValues = {
	YellowStar = 10,     -- Low fuel bonus
	BlueStar = 25,       -- Medium fuel bonus
	PurpleStar = 50,     -- High fuel bonus
	WhiteStar = 100,     -- Very high fuel bonus
}

-- Star spawn configuration
Stats.StarConfig = {
	SpawnCount = 10,                  -- Number of stars to spawn per player
	SpawnRadius = 140,                -- Radius around player spawn point for star placement
	MinDistanceBetweenStars = 15, 	  -- Minimum distance between spawned stars
	CollectionRadius = 10,             -- Distance within which a star can be collected
}

-- Calculate multipliers from pets, rebirths, and boosts
-- Formula: Σ(M_pets + M_rebirth + M_boosts)
-- Returns 1 for now, can be extended for actual multiplier calculations
function Stats.CalculateMultipliers(): number
	return 1
end

-- Calculate speed from fuel using the formula:
-- V_total = (V_base + F^0.7 * E_world) * Σ(M_pets + M_rebirth + M_boosts)
-- @param fuel number - The current fuel amount
-- @param worldName string? - The world name to get efficiency for (default: "Main")
-- @return number - The calculated total speed
function Stats.CalculateSpeedFromFuel(fuel: number, worldName: string?): number
	local baseSpeed = Stats.BaseSpeed
	local worldEfficiency = Stats.WorldEfficiency[worldName or "Main"] or 1
	local multipliers = Stats.CalculateMultipliers()
	
	local fuelComponent = math.pow(fuel, 0.7) * worldEfficiency
	local totalSpeed = (baseSpeed + fuelComponent) * multipliers
	
	return totalSpeed
end

return Stats
