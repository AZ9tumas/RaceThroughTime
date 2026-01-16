--[[
	RebirthStats Module
	Configuration for the Rebirth system including requirements, bonuses, and pet rewards.
	
	The Rebirth system grants permanent bonuses after players reach significant milestones.
	
	Trigger:
	- Players can perform a Rebirth after reaching high milestones (distance/points)
	
	Effect:
	- Resets personal stars (fuel currency)
	- Keeps acquired pets
	- Grants permanent bonuses (cash multiplier, pet, speed boost multiplier)
]]

local RebirthStats = {}

-- Rebirth levels configuration
-- DistanceRequired: Total distance needed to unlock this rebirth level
-- CashMultiplierBonus: Permanent increase to cash earned per star collected
-- SpeedBoostMultiplier: Permanent increase to running speed multiplier
-- PetReward: Pet type to grant (consistent with world progression)
RebirthStats.RebirthLevels = {
	{
		Level = 1,
		DistanceRequired = 50000, -- 50k total distance
		CashMultiplierBonus = 0.1, -- +10% cash
		SpeedBoostMultiplier = 0.05, -- +5% speed
		PetReward = "StandardPet", -- Pet from Main world
		World = "Main",
	},
	{
		Level = 2,
		DistanceRequired = 150000, -- 150k total distance
		CashMultiplierBonus = 0.15, -- +15% cash (total +25%)
		SpeedBoostMultiplier = 0.08, -- +8% speed (total +13%)
		PetReward = "StandardPet", -- Pet from StoneAge world
		World = "StoneAge",
	},
	{
		Level = 3,
		DistanceRequired = 350000, -- 350k total distance
		CashMultiplierBonus = 0.20, -- +20% cash (total +45%)
		SpeedBoostMultiplier = 0.10, -- +10% speed (total +23%)
		PetReward = "StandardPet", -- Pet from AncientEgypt world
		World = "AncientEgypt",
	},
	{
		Level = 4,
		DistanceRequired = 750000, -- 750k total distance
		CashMultiplierBonus = 0.25, -- +25% cash (total +70%)
		SpeedBoostMultiplier = 0.12, -- +12% speed (total +35%)
		PetReward = "StandardPet", -- Pet from Medieval world
		World = "Medieval",
	},
	{
		Level = 5,
		DistanceRequired = 1500000, -- 1.5M total distance
		CashMultiplierBonus = 0.30, -- +30% cash (total +100%)
		SpeedBoostMultiplier = 0.15, -- +15% speed (total +50%)
		PetReward = "StandardPet", -- Pet from Industrial world
		World = "Industrial",
	},
	{
		Level = 6,
		DistanceRequired = 3000000, -- 3M total distance
		CashMultiplierBonus = 0.50, -- +50% cash (total +150%)
		SpeedBoostMultiplier = 0.20, -- +20% speed (total +70%)
		PetReward = "StandardPet", -- Pet from Neon world
		World = "Neon",
	},
}

-- Get maximum rebirth level available
function RebirthStats.GetMaxRebirthLevel(): number
	return #RebirthStats.RebirthLevels
end

-- Get rebirth configuration by level
function RebirthStats.GetRebirthByLevel(level: number)
	for _, rebirth in ipairs(RebirthStats.RebirthLevels) do
		if rebirth.Level == level then
			return rebirth
		end
	end
	return nil
end

-- Get the next available rebirth level for a player
-- @param currentRebirthLevel number - Current rebirth level (0 means no rebirth yet)
-- @return table? - Next rebirth configuration or nil if at max level
function RebirthStats.GetNextRebirth(currentRebirthLevel: number)
	local nextLevel = currentRebirthLevel + 1
	return RebirthStats.GetRebirthByLevel(nextLevel)
end

-- Check if player can rebirth based on current rebirth level and distance
-- @param currentRebirthLevel number - Current rebirth level
-- @param totalDistance number - Total distance traveled
-- @return boolean, table? - Can rebirth, next rebirth config if can
function RebirthStats.CanRebirth(currentRebirthLevel: number, totalDistance: number): (boolean, any?)
	local nextRebirth = RebirthStats.GetNextRebirth(currentRebirthLevel)
	
	if not nextRebirth then
		return false, nil -- Already at max level
	end
	
	if totalDistance >= nextRebirth.DistanceRequired then
		return true, nextRebirth
	end
	
	return false, nil
end

-- Calculate total cash multiplier from all rebirth levels
-- @param rebirthLevel number - Current rebirth level
-- @return number - Total cash multiplier (1.0 base + accumulated bonuses)
function RebirthStats.CalculateTotalCashMultiplier(rebirthLevel: number): number
	local totalMultiplier = 1.0
	
	for _, rebirth in ipairs(RebirthStats.RebirthLevels) do
		if rebirth.Level <= rebirthLevel then
			totalMultiplier = totalMultiplier + rebirth.CashMultiplierBonus
		end
	end
	
	return totalMultiplier
end

-- Calculate total speed boost multiplier from all rebirth levels
-- @param rebirthLevel number - Current rebirth level
-- @return number - Total speed multiplier (1.0 base + accumulated bonuses)
function RebirthStats.CalculateTotalSpeedMultiplier(rebirthLevel: number): number
	local totalMultiplier = 1.0
	
	for _, rebirth in ipairs(RebirthStats.RebirthLevels) do
		if rebirth.Level <= rebirthLevel then
			totalMultiplier = totalMultiplier + rebirth.SpeedBoostMultiplier
		end
	end
	
	return totalMultiplier
end

-- Get progress toward next rebirth
-- @param currentRebirthLevel number - Current rebirth level
-- @param totalDistance number - Total distance traveled
-- @return number, number - Progress percentage (0-100), distance remaining
function RebirthStats.GetRebirthProgress(currentRebirthLevel: number, totalDistance: number): (number, number)
	local nextRebirth = RebirthStats.GetNextRebirth(currentRebirthLevel)
	
	if not nextRebirth then
		return 100, 0 -- At max level
	end
	
	local progress = math.clamp((totalDistance / nextRebirth.DistanceRequired) * 100, 0, 100)
	local remaining = math.max(0, nextRebirth.DistanceRequired - totalDistance)
	
	return progress, remaining
end

return RebirthStats
