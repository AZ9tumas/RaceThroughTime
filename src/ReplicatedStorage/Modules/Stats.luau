--[[
	Stats Module
	Contains game statistics, star spawn probabilities, and fuel values.
]]

local Stats = {}

Stats.BaseSpeed = 50

-- World efficiency values for speed calculation
Stats.WorldEfficiency = {
	Main = 1,
	StoneAge = 1.2, -- StoneAge has 20% higher efficiency than Main
}

-- World radius values for track movement (distance from center)
Stats.WorldRadius = {
	Main = 205,
	StoneAge = 205, -- Same radius as Main
}

Stats.FuelConsumptionRate = {
	Main = 25, -- Fuel consumed per second on the Main world
	StoneAge = 28, -- Slightly higher fuel consumption in StoneAge
}

Stats.WorldCashRates = {
	Main = 150, -- Cash per 1000 distance
	StoneAge = 180, -- 20% higher cash rate in StoneAge
}

-- World unlock requirements (required distance traveled at once to unlock next world)
-- Players need to accumulate this much fuel throughout their gameplay
Stats.WorldUnlockRequirements = {
	-- Main is unlocked by default
	StoneAge = 10510,        -- 10.51k distance to unlock StoneAge from Main
	AncientEgypt = 110110,   -- 110.11k distance to unlock AncientEgypt from StoneAge
	Medieval = 250000,       -- 250k distance to unlock Medieval from AncientEgypt
	Industrial = 550000,     -- 550k distance to unlock Industrial from Medieval
	Neon = 1500000,          -- 1.5M distance to unlock Neon from Industrial
}

-- World progression order (for reference)
Stats.WorldOrder = {
	"Main",
	"StoneAge",
	"AncientEgypt",
	"Medieval",
	"Industrial",
	"Neon",
}

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
	YellowStar = 100,     -- Low fuel bonus
	BlueStar = 250,       -- Medium fuel bonus
	PurpleStar = 500,     -- High fuel bonus
	WhiteStar = 1000,     -- Very high fuel bonus
}

-- Star spawn configuration
Stats.StarConfig = {
	SpawnCount = 10,                  -- Number of stars to spawn per player
	SpawnRadius = 140,                -- Radius around player spawn point for star placement
	MinDistanceBetweenStars = 15, 	  -- Minimum distance between spawned stars
	CollectionRadius = 15,             -- Distance within which a star can be collected
}

-- Track/Gate configuration
Stats.GateProximityDistance = 10 -- studs - distance player must be from gate to start track
Stats.MaxGateIndex = 3 -- Gates are numbered 0 to MaxGateIndex (0, 1, 2, 3)

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

-- Calculate the total distance a player can travel based on fuel and world
-- Uses CalculateSpeedFromFuel internally for speed calculation
-- @param fuel number - The current fuel amount
-- @param worldName string? - The world name (default: "Main")
-- @return number - The calculated total distance (floored to integer)
function Stats.CalculateDistanceFromFuel(fuel: number, worldName: string?): number
	local world = worldName or "Main"
	local speed = Stats.CalculateSpeedFromFuel(fuel, world)
	local fuelConsumptionRate = Stats.FuelConsumptionRate[world] or Stats.FuelConsumptionRate.Main
	
	-- Time = Fuel / FuelConsumptionRate
	-- Distance = Speed * Time
	local timeLeft = fuel / fuelConsumptionRate
	local totalDistance = speed * timeLeft
	
	return math.floor(totalDistance)
end

return Stats