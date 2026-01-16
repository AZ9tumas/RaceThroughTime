--[[
	RebirthStats Module
	Configuration for the Rebirth system including requirements, bonuses, and pet rewards.
	
	The Rebirth system grants permanent bonuses after players reach significant milestones.
	
	Trigger:
	- Players can perform a Rebirth after accumulating enough Cash
	
	Effect:
	- Resets personal stars (fuel currency)
	- Keeps acquired pets
	- Grants permanent bonuses (cash multiplier, pet, speed boost multiplier)
]]

local RebirthStats = {}

-- Rebirth levels configuration
-- CashRequired: Total cash needed to unlock this rebirth level (cash is spent on rebirth)
-- CashMultiplierBonus: Permanent increase to cash earned per star collected
-- SpeedBoostMultiplier: Permanent increase to running speed multiplier
-- PetReward: Pet type to grant (consistent with world progression)
RebirthStats.RebirthLevels = {
	{
		Level = 1,
		CashRequired = 100000, -- 100K cash required for first rebirth
		CashMultiplierBonus = 0.1, -- +10% cash
		SpeedBoostMultiplier = 0.05, -- +5% speed
		PetReward = "StandardPet", -- Pet from Main world
		World = "Main",
	},
	{
		Level = 2,
		CashRequired = 1000000, -- 1M cash required for second rebirth
		CashMultiplierBonus = 0.15, -- +15% cash (total +25%)
		SpeedBoostMultiplier = 0.08, -- +8% speed (total +13%)
		PetReward = "StandardPet", -- Pet from StoneAge world
		World = "StoneAge",
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

-- Check if player can rebirth based on current rebirth level and cash
-- @param currentRebirthLevel number - Current rebirth level
-- @param currentCash number - Current cash amount
-- @return boolean, table? - Can rebirth, next rebirth config if can
function RebirthStats.CanRebirth(currentRebirthLevel: number, currentCash: number): (boolean, any?)
	local nextRebirth = RebirthStats.GetNextRebirth(currentRebirthLevel)
	
	if not nextRebirth then
		return false, nil -- Already at max level
	end
	
	if currentCash >= nextRebirth.CashRequired then
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
-- @param currentCash number - Current cash amount
-- @return number, number - Progress percentage (0-100), cash remaining
function RebirthStats.GetRebirthProgress(currentRebirthLevel: number, currentCash: number): (number, number)
	local nextRebirth = RebirthStats.GetNextRebirth(currentRebirthLevel)
	
	if not nextRebirth then
		return 100, 0 -- At max level
	end
	
	local progress = math.clamp((currentCash / nextRebirth.CashRequired) * 100, 0, 100)
	local remaining = math.max(0, nextRebirth.CashRequired - currentCash)
	
	return progress, remaining
end

return RebirthStats
