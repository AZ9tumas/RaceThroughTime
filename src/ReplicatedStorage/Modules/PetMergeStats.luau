--[[
	PetMergeStats
	Configuration for pet merging system including rarity tiers, grind wall mechanics,
	and stat bonuses. These values are NOT hardcoded and can be balanced as needed.
	
	Merge Formula: NewStats = OldStats × (2 + RarityBonus)
	
	The "grind wall" is an intentional economy sink that sharply increases
	the number of copies required at higher rarity levels to:
	- Prevent speed inflation in mid-game
	- Maintain trading value of high-tier pets
]]

local PetMergeStats = {}

-- Rarity Tiers with their configurations
-- CopiesRequired: Number of copies needed to merge to next tier (grind wall)
-- RarityBonus: Bonus percentage applied when merging (used in formula: NewStats = OldStats × (2 + RarityBonus))
-- FinalMultiplier: Target multiplier for pets at this rarity tier
PetMergeStats.RarityTiers = {
	-- Tier 1: Common (easy to obtain, low grind)
	{
		Name = "Common",
		TierLevel = 1,
		CopiesRequired = 3, -- Need 3 copies to merge
		RarityBonus = 0.0, -- +0% bonus
		FinalMultiplier = 2.0, -- x2.0
		GemCost = 10,
		Color = Color3.fromRGB(128, 128, 128), -- Gray
	},
	-- Tier 2: Uncommon
	{
		Name = "Uncommon",
		TierLevel = 2,
		CopiesRequired = 3, -- Need 3 copies to merge
		RarityBonus = 0.0, -- +0% bonus
		FinalMultiplier = 2.0, -- x2.0
		GemCost = 25,
		Color = Color3.fromRGB(76, 175, 80), -- Green
	},
	-- Tier 3: Rare
	{
		Name = "Rare",
		TierLevel = 3,
		CopiesRequired = 3, -- Need 3 copies to merge
		RarityBonus = 0.10, -- +10% bonus
		FinalMultiplier = 2.1, -- x2.1
		GemCost = 50,
		Color = Color3.fromRGB(33, 150, 243), -- Blue
	},
	-- Tier 4: Epic (GRIND WALL STARTS HERE)
	{
		Name = "Epic",
		TierLevel = 4,
		CopiesRequired = 8, -- GRIND WALL: Jump from 3 to 8
		RarityBonus = 0.30, -- +30% bonus
		FinalMultiplier = 2.3, -- x2.3
		GemCost = 100,
		Color = Color3.fromRGB(156, 39, 176), -- Purple
	},
	-- Tier 5: Legendary
	{
		Name = "Legendary",
		TierLevel = 5,
		CopiesRequired = 10, -- Need 10 copies to merge
		RarityBonus = 0.60, -- +60% bonus
		FinalMultiplier = 2.6, -- x2.6
		GemCost = 250,
		Color = Color3.fromRGB(255, 152, 0), -- Orange
	},
	-- Tier 6: Mythic
	{
		Name = "Mythic",
		TierLevel = 6,
		CopiesRequired = 12, -- Need 12 copies to merge
		RarityBonus = 1.00, -- +100% bonus
		FinalMultiplier = 3.0, -- x3.0
		GemCost = 500,
		Color = Color3.fromRGB(244, 67, 54), -- Red
	},
	-- Tier 7: Divine (Max Tier)
	{
		Name = "Divine",
		TierLevel = 7,
		CopiesRequired = 15, -- Need 15 copies (if there were higher tier)
		RarityBonus = 2.00, -- +200% bonus
		FinalMultiplier = 4.0, -- x4.0
		GemCost = 1000,
		Color = Color3.fromRGB(255, 215, 0), -- Gold
	},
}

-- Get tier configuration by tier level
function PetMergeStats.GetTierByLevel(tierLevel: number)
	for _, tier in ipairs(PetMergeStats.RarityTiers) do
		if tier.TierLevel == tierLevel then
			return tier
		end
	end
	return PetMergeStats.RarityTiers[1] -- Default to Common
end

-- Get tier configuration by name
function PetMergeStats.GetTierByName(tierName: string)
	for _, tier in ipairs(PetMergeStats.RarityTiers) do
		if tier.Name == tierName then
			return tier
		end
	end
	return PetMergeStats.RarityTiers[1] -- Default to Common
end

-- Get the next tier after the given tier level
function PetMergeStats.GetNextTier(currentTierLevel: number)
	local nextLevel = currentTierLevel + 1
	return PetMergeStats.GetTierByLevel(nextLevel)
end

-- Get maximum tier level
function PetMergeStats.GetMaxTierLevel(): number
	return #PetMergeStats.RarityTiers
end

-- Check if a tier level is the maximum
function PetMergeStats.IsMaxTier(tierLevel: number): boolean
	return tierLevel >= PetMergeStats.GetMaxTierLevel()
end

-- Calculate new stats after merging using the formula: NewStats = OldStats × (2 + RarityBonus)
function PetMergeStats.CalculateMergedStats(oldStats: { Multiplier: number, FuelBonus: number, PickupRangeBonus: number }, tierLevel: number)
	local tier = PetMergeStats.GetTierByLevel(tierLevel)
	local formula = 2 + tier.RarityBonus
	
	return {
		Multiplier = oldStats.Multiplier * formula,
		FuelBonus = oldStats.FuelBonus * formula,
		PickupRangeBonus = oldStats.PickupRangeBonus * formula,
	}
end

-- Get the number of copies required to merge at a specific tier level
function PetMergeStats.GetCopiesRequired(tierLevel: number): number
	local tier = PetMergeStats.GetTierByLevel(tierLevel)
	return tier.CopiesRequired
end

-- Get the Gem cost to merge at a specific tier level
function PetMergeStats.GetMergeCost(tierLevel: number): number
	local tier = PetMergeStats.GetTierByLevel(tierLevel)
	return tier.GemCost
end

-- Get the rarity bonus for a specific tier level
function PetMergeStats.GetRarityBonus(tierLevel: number): number
	local tier = PetMergeStats.GetTierByLevel(tierLevel)
	return tier.RarityBonus
end

-- Stat bonus configuration (per tier level increase)
-- These are additive bonuses applied on top of the multiplicative formula
PetMergeStats.TierBonuses = {
	MultiplierBonus = 0.05, -- +5% base multiplier per tier
	FuelBonusIncrease = 0.05, -- +5% fuel bonus per tier
	PickupRangeBonusIncrease = 0.10, -- +10% pickup range per tier
}

-- World-specific merge restrictions
-- Pets must be from the same world to merge
PetMergeStats.WorldRestrictions = {
	RequireSameWorld = true, -- Must be from same world
	AllowCrossWorldMerge = false, -- Cannot merge pets from different worlds
}

-- Merge progress tracking configuration
-- Used for UI to show progress towards next merge
PetMergeStats.ProgressTracking = {
	ShowCopyProgress = true, -- Show "3/8 copies" in UI
	ShowGemRequirement = true, -- Show gem cost in UI
	ShowNextTierPreview = true, -- Preview stats of next tier
}

return PetMergeStats
