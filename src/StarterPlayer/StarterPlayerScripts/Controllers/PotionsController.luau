--[[
	PotionsController - Client-side controller for checking potion effects
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PotionsController = Knit.CreateController({
	Name = "PotionsController",
})

local PotionsService

function PotionsController:HasActivePotion(potionName: string)
	return PotionsService:HasActivePotion(potionName)
end

function PotionsController:GetProbabilityKey()
	return PotionsService:GetProbabilityKey()
end

function PotionsController:GetPotionMultiplier()
	return PotionsService:GetPotionMultiplier()
end

function PotionsController:GetRemainingTime(potionName: string)
	return PotionsService:GetRemainingTime(potionName)
end

function PotionsController:KnitInit()
	
end

function PotionsController:KnitStart()
	PotionsService = Knit.GetService("PotionsService")
end

return PotionsController
