local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GamePassIds = require(ReplicatedStorage.GamePassIds)

local MonetizationController = Knit.CreateController({
	Name = "MonetizationController",
})

-- Expose Passes table for easy access
MonetizationController.Passes = GamePassIds

local MonetizationService
local Player = Players.LocalPlayer

function MonetizationController:HasGamePass(gamePassName: string): boolean
	if not MonetizationService then
		return false
	end
	
	local success, result = pcall(function()
		return MonetizationService:HasGamePassClient(gamePassName)
	end)
	
	if success then
		return result
	end
	return false
end

function MonetizationController:PromptPurchase(gamePassName: string)
	local gamePassId = GamePassIds[gamePassName]
	if gamePassId then
		MarketplaceService:PromptGamePassPurchase(Player, gamePassId)
	end
end

function MonetizationController:KnitInit()
end

function MonetizationController:KnitStart()
	MonetizationService = Knit.GetService("MonetizationService")
end

return MonetizationController
