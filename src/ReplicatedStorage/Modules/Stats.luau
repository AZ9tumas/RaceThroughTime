--[[
	Stats Module
	Contains game statistics, star spawn probabilities, and fuel values.
]]

local Stats = {}

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

return Stats
