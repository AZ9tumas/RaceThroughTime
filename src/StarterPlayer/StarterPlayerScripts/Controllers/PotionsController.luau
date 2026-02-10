--[[
	PotionsController - Client-side controller for checking potion effects
	
	Follows the same pattern as MonetizationController:
	- Caches active potions locally
	- Provides HasPotionEffect(potionName) for checking potion status
	- Syncs with server on data updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)

local PotionsController = Knit.CreateController({
	Name = "PotionsController",
})

local PotionsService
local DataService
local Player = Players.LocalPlayer

-- Local cache of active potions (similar to MonetizationController.OwnedPasses)
local ActivePotions = {}

local function GetPotionsService()
	if not PotionsService then
		PotionsService = Knit.GetService("PotionsService")
	end
	return PotionsService
end

local function GetDataService()
	if not DataService then
		DataService = Knit.GetService("DataService")
	end
	return DataService
end

-- Refresh active potions from server
local function RefreshPotions()
	GetPotionsService():GetPlayerPotions():andThen(function(potions)
		if potions then
			ActivePotions = potions
		end
	end):catch(warn)
end

--[[
	Check if player has a specific potion effect active.
	This is the primary method other controllers should use.
	
	@param potionName string - The name of the potion (e.g., "SuperLuck", "FuelBoost")
	@return boolean - True if the potion effect is currently active
]]
function PotionsController:HasPotionEffect(potionName: string): boolean
	return ActivePotions[potionName] ~= nil
end

-- Legacy compatibility method
function PotionsController:HasActivePotion(potionName: string): boolean
	return self:HasPotionEffect(potionName)
end

--[[
	Get remaining time for a specific potion.
	
	@param potionName string - The name of the potion
	@return number - Remaining time in seconds (0 if expired, -1 if infinite)
]]
function PotionsController:GetRemainingTime(potionName: string): number
	local potion = ActivePotions[potionName]
	if not potion then
		return 0
	end

	if potion.Expiry == 0 then
		return -1 -- Infinite
	end

	local currentTime = os.time()
	local expiresAt = potion.UsedAt + potion.Expiry
	local remaining = expiresAt - currentTime

	return math.max(0, remaining)
end

--[[
	Get all currently active potions.
	
	@return {[string]: Potion} - Map of potion names to potion data
]]
function PotionsController:GetActivePotions()
	return ActivePotions
end

function PotionsController:KnitInit()
	GetPotionsService()
	GetDataService()
end

function PotionsController:KnitStart()
	-- Initial fetch
	RefreshPotions()
	
	-- Update potions when data changes (similar to MonetizationController pattern)
	GetDataService().DataReady:Connect(function(_newData)
		RefreshPotions()
	end)
end

return PotionsController
