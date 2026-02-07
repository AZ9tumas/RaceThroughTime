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
local OwnedPasses = {}
local Player = Players.LocalPlayer

function MonetizationController:HasGamePass(gamePassName: string): boolean
	return OwnedPasses[gamePassName] or false
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
	
	-- Initial fetch
	MonetizationService:GetPlayerPasses():andThen(function(passes)
		if passes then
			OwnedPasses = passes
		end
	end):catch(warn)
	
	-- Update on purchase
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if player == Players.LocalPlayer and wasPurchased then
			for name, id in pairs(GamePassIds) do
				if id == gamePassId then
					OwnedPasses[name] = true
					-- Also refresh from server to be safe
					MonetizationService:GetPlayerPasses():andThen(function(passes)
						if passes then
							OwnedPasses = passes
						end
					end)
					break
				end
			end
		end
	end)
end

return MonetizationController
