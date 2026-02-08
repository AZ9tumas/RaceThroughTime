local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GamePassIds = require(ReplicatedStorage.GamePassIds)

local MonetizationController = Knit.CreateController({
	Name = "MonetizationController",
})

-- Expose Passes table for easy access
MonetizationController.Passes = GamePassIds

local MonetizationService
local OwnedPasses = {}
local DebugOverrides = {} -- Debug overrides for Studio testing
local Player = Players.LocalPlayer

function MonetizationController:HasGamePass(gamePassName: string): boolean
	-- In Studio, check debug overrides first
	if RunService:IsStudio() and DebugOverrides[gamePassName] ~= nil then
		return DebugOverrides[gamePassName]
	end
	return OwnedPasses[gamePassName] or false
end

-- Debug function to set gamepass ownership (only works in Studio)
function MonetizationController:SetDebugGamePass(gamePassName: string, owned: boolean)
	if RunService:IsStudio() then
		DebugOverrides[gamePassName] = owned
	end
end

-- Debug function to get current debug override state
function MonetizationController:GetDebugGamePass(gamePassName: string): boolean?
	if RunService:IsStudio() then
		return DebugOverrides[gamePassName]
	end
	return nil
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
