--[[
	Stats Module
	Contains game statistics, star spawn probabilities, and fuel values.
]]

local Stats = {}

export type Pet = {
	Name: string,
	PetType: string?,
	Multiplier: number,
	FuelBonus: number?,
	PickupRangeBonus: number?,
	RoamRange: number?,
	StarCollectionRadius: number?,
	Velocity: number?,
	World: string?,
	Level: number?,
	TierLevel: number?,
	TierName: string?,
	Rarity: string?,
	ID: string?,
	Equipped: boolean?,
}

-- Player star collection radius (studs) - player can collect stars within this distance
Stats.MaxStarCollectionPlayerRadius = 30
Stats.MinStarCollectionPlayerRadius = 20
Stats.BaseSpeed = 50 -- base track speed

-- pet max limits
Stats.MaxPetSpeed = 35
Stats.MaxPetRoamRange = 150
Stats.MaxPickupRangeBonus = 3
Stats.MaxStarCollectionRadius = 25

-- Starting fuel for new players and after rebirth
Stats.StartingFuel = 100

-- Maximum track run time in seconds
Stats.MaxTrackTime = 20

-- Maximum physical speed limit (for body movers and lap detection)
-- Calculated speed can exceed this for stats/distance tracking, but physical movement is capped
Stats.MaxPhysicalSpeed = 180

-- Base acceleration for track movement (studs/sec²)
Stats.BaseAcceleration = 20

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

-- Arena radius values for each world (radius of the 1_Central_Arena part)
-- Used to determine if player is inside the arena
Stats.ArenaRadius = {
	Main = 200,
	StoneAge = 200,
}

Stats.FuelConsumptionRate = {
	Main = 150, -- Fuel consumed per second on the Main world
	StoneAge = 200, -- Slightly higher fuel consumption in StoneAge
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
-- Gems: Rare, gives gems instead of fuel
Stats.StarProbabilities = {
	YellowStar = 0.60,   -- 60% chance (Common)
	BlueStar = 0.28,     -- 28% chance (Uncommon)
	PurpleStar = 0.06,   -- 6% chance (Rare)
	WhiteStar = 0.02,    -- 2% chance (Legendary)
	Gems = 0.04,         -- 4% chance (Rare gem)
}

-- Star equivalents for fuel calculation (1 star = 1 unit of fuel base)
-- Total fuel = Stars * multipliers (pet + rebirth + other multipliers)
Stats.StarEquivalents = {
	YellowStar = 1,       -- Common star equivalent
	BlueStar = 2,         -- Uncommon star equivalent
	PurpleStar = 3,       -- Rare star equivalent
	WhiteStar = 5,        -- Legendary star equivalent
	Gems = 0,             -- Gems don't contribute to fuel
}

-- Gem values for gem-type stars
Stats.StarGemValues = {
	Gems = 5,             -- Base gem value for collecting a Gems star
}

-- Star spawn configuration
Stats.StarConfig = {
	MaxStars = 15,                    -- Maximum number of stars that can exist at once per player
	SpawnRadius = 130,                -- Radius around player spawn point for star placement
	MinDistanceBetweenStars = 15, 	  -- Minimum distance between spawned stars
	CollectionRadius = 15,            -- Distance within which a star can be collected
	SpawnInterval = 3,                -- Seconds between spawning new stars (continuous spawning rate)
}

-- Track/Gate configuration
Stats.GateProximityDistance = 10 -- studs - distance player must be from gate to start track
Stats.MaxGateIndex = 3 -- Gates are numbered 0 to MaxGateIndex (0, 1, 2, 3)

-- Calculate multipliers from pets, rebirths, and boosts
-- Formula: Σ(M_pets + M_rebirth + M_boosts)
-- @param rebirthSpeedMultiplier number? - Speed multiplier from rebirth bonuses (default: 1.0)
-- @return number - Total multiplier
-- Note: Rebirth multipliers should be fetched from RebirthService on the server
-- and passed to this function for accurate calculations.
function Stats.CalculateMultipliers(rebirthSpeedMultiplier: number?): number
	-- multiplier from pets is handled separately
	-- here dev products, vip access and rebirths can be added
	-- also rebirth speed multiplier is used to increase speed in track run, thereby increasing distance covered
	local baseMultiplier = 1.0
	local rebirthMultiplier = rebirthSpeedMultiplier or 1.0
	
	return baseMultiplier * rebirthMultiplier
end

-- Calculate base speed from fuel using the formula:
-- Note: This returns base speed without rebirth bonuses. Rebirth speed multipliers
-- should be applied by the caller (e.g., TrackService) after getting track parameters.
-- @param fuel number - The current fuel amount
-- @param worldName string? - The world name to get efficiency for (default: "Main")
-- @return number - The calculated base speed component from fuel
function Stats.CalculateSpeedFromFuel(fuel: number, worldName: string?): number
	local baseSpeed = Stats.BaseSpeed
	local worldEfficiency = Stats.WorldEfficiency[worldName or "Main"] or 1
	local multipliers = Stats.CalculateMultipliers()
	
	local fuelComponent = math.pow(fuel, 0.3) * worldEfficiency
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

-- Calculate track parameters with acceleration and 30s max time limit
-- This calculates optimal speed and acceleration to cover required distance within max time
-- @param fuel number - The current fuel amount
-- @param worldName string? - The world name (default: "Main")
-- @return table - { initialSpeed, acceleration, maxSpeed, totalTime, totalDistance }
function Stats.CalculateTrackParameters(fuel: number, worldName: string?): { initialSpeed: number, acceleration: number, maxSpeed: number, totalTime: number, totalDistance: number }
	local world = worldName or "Main"
	local fuelConsumptionRate = Stats.FuelConsumptionRate[world] or Stats.FuelConsumptionRate.Main
	
	-- Calculate base values
	local baseSpeedFromFuel = Stats.CalculateSpeedFromFuel(fuel, world)
	local baseTime = fuel / fuelConsumptionRate
	
	-- Cap time at MaxTrackTime (30 seconds)
	local actualTime = math.min(baseTime, Stats.MaxTrackTime)
	
	-- Calculate distance that would be covered with base speed
	local baseDistance = baseSpeedFromFuel * baseTime
	
	-- Now we need to cover baseDistance in actualTime
	-- Using kinematics: d = v0*t + 0.5*a*t^2
	-- If time is limited, we need to adjust acceleration to cover the distance
	
	local initialSpeed, acceleration, maxSpeed
	
	if actualTime >= baseTime then
		-- No time limit hit, use base calculations with gentle acceleration
		initialSpeed = baseSpeedFromFuel * 0.5 -- Start at 50% of final speed
		acceleration = Stats.BaseAcceleration
		maxSpeed = baseSpeedFromFuel
	else
		-- Time is capped, need to adjust to cover distance in limited time
		-- Average speed needed = distance / time
		local avgSpeedNeeded = baseDistance / actualTime
		
		-- Start at 30% of average, accelerate to cover distance
		initialSpeed = avgSpeedNeeded * 0.3
		
		-- With constant acceleration: d = v0*t + 0.5*a*t^2
		-- Solve for a: a = 2*(d - v0*t) / t^2
		acceleration = 2 * (baseDistance - initialSpeed * actualTime) / (actualTime * actualTime)
		
		-- Cap acceleration to prevent unrealistic values
		acceleration = math.max(acceleration, Stats.BaseAcceleration)
		
		-- Max speed = v0 + a*t
		maxSpeed = initialSpeed + acceleration * actualTime
	end
	
	-- Ensure minimum values
	initialSpeed = math.max(initialSpeed, Stats.BaseSpeed)
	acceleration = math.max(acceleration, 0)
	maxSpeed = math.max(maxSpeed, initialSpeed)
	
	return {
		initialSpeed = initialSpeed,
		acceleration = acceleration,
		maxSpeed = maxSpeed,
		totalTime = actualTime,
		totalDistance = baseDistance,
	}
end

-- Calculate current speed based on elapsed time using acceleration
-- v = v0 + a*t (capped at maxSpeed)
-- @param initialSpeed number - The starting speed
-- @param acceleration number - The acceleration rate
-- @param maxSpeed number - Maximum speed cap
-- @param elapsedTime number - Time elapsed since track start
-- @return number - Current speed
function Stats.CalculateCurrentSpeed(initialSpeed: number, acceleration: number, maxSpeed: number, elapsedTime: number): number
	local speed = initialSpeed + acceleration * elapsedTime
	return math.min(speed, maxSpeed)
end

-- Convert cartesian speed to angular velocity for polar coordinate movement
-- ω = v / r (angular velocity = linear velocity / radius)
-- @param linearSpeed number - Speed in cartesian coordinates (studs/sec)
-- @param radius number - Radius of circular path (must be > 0)
-- @return number - Angular velocity in radians/sec
function Stats.LinearSpeedToAngularVelocity(linearSpeed: number, radius: number): number
	if radius <= 0 then
		return 0 -- Prevent division by zero
	end
	return linearSpeed / radius
end

-- Calculate position in cartesian from polar coordinates
-- x = center.X + r * cos(θ)
-- z = center.Z + r * sin(θ)
-- @param centerX number - X coordinate of center
-- @param centerZ number - Z coordinate of center
-- @param radius number - Distance from center
-- @param angle number - Angle in radians
-- @return (number, number) - X and Z coordinates
function Stats.PolarToCartesian(centerX: number, centerZ: number, radius: number, angle: number): (number, number)
	local x = centerX + radius * math.cos(angle)
	local z = centerZ + radius * math.sin(angle)
	return x, z
end

-- Egg Configuration
-- Egg types with their costs and the pets they can produce (with probabilities)
Stats.Eggs = {
	StandardEgg = {
		Cost = 500,
		Tier = "Basic",
		Currency = "Cash",
		World = "Main",
		-- Pets array contains possible pets with their spawn probabilities (must sum to 1.0)
		Pets = {
			{ Pet = "StandardPet", Probability = 0.70 }, -- 70% chance
			{ Pet = "StandardPet", Probability = 0.30 }, -- 30% chance (same pet, for testing)
		},
	},
}

Stats.TierColors = setmetatable({
	[1] = Color3.fromRGB(255, 255, 255), -- Standard - White
	[2] = Color3.fromRGB(0, 255, 255),   -- Premium - Cyan
	[3] = Color3.fromRGB(255, 215, 0),   -- Limited Time - Gold
	[4] = Color3.fromRGB(255, 0, 255),   -- Exclusive - Magenta
}, {
	__index = function()
		warn("Could not find tier color, defaulting to White")
		return Color3.fromRGB(255, 255, 255) -- Default to White
	end,
})

-- Pet Configuration
-- Pet types with their base stats
Stats.Pets = {
	StandardPet = {
		Name = "Standard Pet",
		TierLevel = 1, -- Required especially during merging pets
		Multiplier = 1.1, -- 10% boost to earnings
		FuelBonus = 1.1, -- 10% fuel collection increase
		PickupRangeBonus = 1.0, -- No range extension (base range)
		RoamRange = 150, -- Maximum range pets can roam from player when collecting stars in arena
		StarCollectionRadius = 10, -- Distance from star to collect it
		Velocity = 20, -- Pet movement speed (studs/sec)
		World = "Main", -- Associated world for merging
		BaseTierLevel = 1, -- Starting tier level
		Rarity = "Standard", -- Standard, Premium, or LimitedTime
	},
}

-- Calculate total fuel multiplier from all equipped pets
-- Returns the sum of all equipped pets' multipliers (default 1.0 if no pets equipped)
-- @param equippedPets table? - Array of equipped pet data { Multiplier: number, ... }
-- @return number - Total fuel multiplier (sum of all pet multipliers)
function Stats.CalculateFuelMultiplier(equippedPets: {any}?): number
	if not equippedPets or #equippedPets == 0 then
		return 1.0
	end
	
	local totalMultiplier = 0
	for _, pet in ipairs(equippedPets) do
		totalMultiplier = totalMultiplier + (pet.Multiplier or 1.0)
	end
	
	return totalMultiplier
end

-- Note: Merge costs, bonuses, and grind wall configuration are now in PetMergeStats.luau
-- See ReplicatedStorage.Modules.PetMergeStats for merge system configuration

-- Maximum number of pets that can be equipped at once
Stats.MaxEquippedPets = 3

-- Calculate total fuel from collected stars and multipliers
-- Total fuel = Stars * (petMultiplier + rebirthMultiplier + baseMultiplier)
-- @param stars number - Total star equivalents collected by the player
-- @param petMultiplier number - Fuel multiplier from equipped pets
-- @param rebirthMultiplier number - Fuel multiplier from rebirth bonuses  
-- @param otherMultiplier number? - Other multipliers (VIP, boosts, etc.) defaults to 1.0
-- @return number - The calculated total fuel
function Stats.CalculateFuelFromStars(stars: number, petMultiplier: number, rebirthMultiplier: number, otherMultiplier: number?): number
	local baseMultiplier = otherMultiplier or 1.0
	local totalMultiplier = petMultiplier + rebirthMultiplier + baseMultiplier
	return math.floor(stars * totalMultiplier)
end

return Stats