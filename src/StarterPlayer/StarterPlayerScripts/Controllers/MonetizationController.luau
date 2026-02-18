local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GamePassIds = require(ReplicatedStorage.GamePassIds)
local Signal = require(ReplicatedStorage.Packages.Signal)

local MonetizationController = Knit.CreateController({
	Name = "MonetizationController",
})

-- Signal fired whenever gamepass ownership changes (name: string, owned: boolean)
MonetizationController.GamePassChanged = Signal.new()

-- Expose Passes table for easy access
MonetizationController.Passes = GamePassIds

local MonetizationService
local OwnedPasses = {}
local DebugOverrides = {} -- Debug overrides for Studio testing
local Player = Players.LocalPlayer
local isstudio = nil

function IsStudio()
	if isstudio == nil then
		if MonetizationService then
			MonetizationService:IsStudio(Player):andThen(function(result)
				isstudio = result
			end):catch(function(err)
				warn("Failed to get Studio status from server:", err)
			end)
		end
	end
	return isstudio
end

function MonetizationController:HasGamePass(gamePassName: string): boolean
	-- Server is the single source of truth. OwnedPasses is kept in sync
	-- via GamePassOwnershipChanged signal (fires on purchase + debug toggle).
	return OwnedPasses[gamePassName] == true
end

-- Debug function to set gamepass ownership (only works in Studio)
function MonetizationController:SetDebugGamePass(gamePassName: string, owned: boolean)
	if IsStudio() then
		DebugOverrides[gamePassName] = owned
		-- Notify server — it will fire GamePassOwnershipChanged signal back
		-- with the combined (debug OR actual) result, updating OwnedPasses
		if MonetizationService then
			MonetizationService:SetDebugGamePass(gamePassName, owned)
		end
	end
end

-- Debug function to get current debug override state
function MonetizationController:GetDebugGamePass(gamePassName: string): boolean?
	if IsStudio() then
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
	
	-- Listen for server-authoritative ownership changes (purchase + debug toggle).
	-- Server fires this signal whenever HasGamePass result changes for this player.
	MonetizationService.GamePassOwnershipChanged:Connect(function(gamePassName, owned)
		OwnedPasses[gamePassName] = owned
		MonetizationController.GamePassChanged:Fire(gamePassName, owned)
	end)
end

return MonetizationController
