--[[
	PotionsController - Client-side controller for checking potion effects
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PotionsController = Knit.CreateController({
	Name = "PotionsController",
})

local PotionsService

local function GetPotionsService()
	if not PotionsService then
		PotionsService = Knit.GetService("PotionsService")
	end
	return PotionsService
end

function PotionsController:HasActivePotion(potionName: string)
	return GetPotionsService():HasActivePotion(potionName)
end

function PotionsController:GetProbabilityKey()
	return GetPotionsService():GetProbabilityKey()
end

function PotionsController:GetPotionMultiplier()
	return GetPotionsService():GetPotionMultiplier()
end

function PotionsController:GetRemainingTime(potionName: string)
	return GetPotionsService():GetRemainingTime(potionName)
end

function PotionsController:KnitInit()
	GetPotionsService()
end

function PotionsController:KnitStart()
	
end

return PotionsController
