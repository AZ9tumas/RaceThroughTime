--[[
	PotionsController - Client-side controller for checking potion effects
]]

local PotionsController = {
	Name = "PotionsController",
}

local Knit
local PotionsService

function PotionsController:HasActivePotion(potionName: string): boolean
	return PotionsService:HasActivePotion(potionName)
end

function PotionsController:GetProbabilityKey(): string?
	return PotionsService:GetProbabilityKey()
end

function PotionsController:GetPotionMultiplier(): number
	return PotionsService:GetPotionMultiplier()
end

function PotionsController:GetRemainingTime(potionName: string): number
	return PotionsService:GetRemainingTime(potionName)
end

function PotionsController:KnitInit()
	Knit = require(game.ReplicatedStorage.Packages.Knit)
end

function PotionsController:KnitStart()
	PotionsService = Knit.GetService("PotionsService")
end

return PotionsController
