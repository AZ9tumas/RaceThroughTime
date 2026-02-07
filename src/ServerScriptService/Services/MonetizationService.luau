local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GamePassIds = require(ReplicatedStorage.GamePassIds)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {},
})

local PlayerGamePasses = {}

local function CheckAllGamePasses(player: Player)
	local userId = player.UserId
	PlayerGamePasses[userId] = {}
	
	for gamePassName, gamePassId in pairs(GamePassIds) do
		local success, ownsGamePass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
		end)
		
		if success then
			PlayerGamePasses[userId][gamePassName] = ownsGamePass
		else
			PlayerGamePasses[userId][gamePassName] = false
		end
	end
end

function MonetizationService:HasGamePass(player: Player, gamePassName: string): boolean
	local userId = player.UserId
	if not PlayerGamePasses[userId] then
		return false
	end
	return PlayerGamePasses[userId][gamePassName] or false
end

function MonetizationService:GetStarsMultiplier(player: Player): number
	if self:HasGamePass(player, "DoubleStars") then
		return 2
	end
	return 1
end

function MonetizationService:HasInstantHatch(player: Player): boolean
	return self:HasGamePass(player, "InstantHatch")
end

function MonetizationService.Client:HasGamePassClient(player: Player, gamePassName: string): boolean
	return MonetizationService:HasGamePass(player, gamePassName)
end

function MonetizationService:KnitInit()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if wasPurchased then
			local userId = player.UserId
			if not PlayerGamePasses[userId] then
				PlayerGamePasses[userId] = {}
			end
			
			for gamePassName, id in pairs(GamePassIds) do
				if id == gamePassId then
					PlayerGamePasses[userId][gamePassName] = true
					break
				end
			end
		end
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		PlayerGamePasses[player.UserId] = nil
	end)
end

function MonetizationService:KnitStart()
	local DataService = Knit.GetService("DataService")
	
	DataService.DataReady:Connect(function(player)
		if not PlayerGamePasses[player.UserId] then
			CheckAllGamePasses(player)
		end
	end)
end

return MonetizationService
