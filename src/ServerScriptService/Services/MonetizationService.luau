local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GamePassIds = require(ReplicatedStorage.GamePassIds)
local DevProducts = require(ServerScriptService.Modules.DevProducts)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {},
})

-- Expose Passes table for both server and client usage
MonetizationService.Passes = GamePassIds
MonetizationService.DevProducts = DevProducts.Ids

local PlayerGamePasses = {}
local DebugOverrides = {} -- [UserId] = { [gamePassName] = boolean } - Debug overrides for Studio testing

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

	print(PlayerGamePasses[userId], "monetization, assets")
end

function MonetizationService:HasGamePass(player: Player, gamePassName: string): boolean
	local userId = player.UserId

	if not PlayerGamePasses[userId] then
		warn("PlayerGamePasses not initialized for userId:", userId)
		CheckAllGamePasses(player)
	end

	local debugPanel = DebugOverrides[userId] and DebugOverrides[userId][gamePassName]
	local actual = PlayerGamePasses[userId][gamePassName] or false
	
	-- In Studio, check debug overrides first
	if RunService:IsStudio() then
		return if debugPanel == true then debugPanel else actual
	end

	return actual
end

function MonetizationService:GetStarsMultiplier(player: Player): number
	if self:HasGamePass(player, "DoubleStars") then
		return 2
	end
	return 1
end

function MonetizationService.Client:HasGamePassClient(player: Player, gamePassName: string): boolean
	return MonetizationService:HasGamePass(player, gamePassName)
end

function MonetizationService.Client:GetPlayerPasses(player: Player)
	local userId = player.UserId
	if not PlayerGamePasses[userId] then
		CheckAllGamePasses(player)
	end
	return PlayerGamePasses[userId] or {}
end

-- Debug function to set gamepass ownership (only works in Studio)
function MonetizationService.Client:SetDebugGamePass(player: Player, gamePassName: string, owned: boolean)
	if RunService:IsStudio() then
		local userId = player.UserId
		if not DebugOverrides[userId] then
			DebugOverrides[userId] = {}
		end
		DebugOverrides[userId][gamePassName] = owned
		print("[MonetizationService]: ", DebugOverrides)
		
		-- Fire DataReady to update client UI when gamepass ownership changes
		local DataService = Knit.GetService("DataService")
		if DataService then
			DataService:FireDataReady(player)
		end
	end
end

function MonetizationService.Client:IsStudio(player: Player)
	return RunService:IsStudio()
end

function MonetizationService.Client:GetDevProductId(player: Player, productName: string): number?
	print(DevProducts.GetProductId(productName), "monetization, product id")
	return DevProducts.GetProductId(productName)
end

function MonetizationService:KnitInit()
	-- Initialize DevProducts module with Knit services
	DevProducts.Initialize(Knit)
	
	-- Handle game pass purchases
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if wasPurchased then
			local userId = player.UserId
			if not PlayerGamePasses[userId] then
				PlayerGamePasses[userId] = {}
			end
			
			for gamePassName, id in pairs(GamePassIds) do
				if id == gamePassId then
					PlayerGamePasses[userId][gamePassName] = true
					
					-- Fire DataReady to update client UI when gamepass is purchased
					local DataService = Knit.GetService("DataService")
					if DataService then
						DataService:FireDataReady(player)
					end
					break
				end
			end
		end
	end)
	
	-- Handle dev product purchases
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		
		local productId = receiptInfo.ProductId
		local purchaseHandler = DevProducts.GetHandler(productId)
		
		if purchaseHandler then
			local success, result = pcall(function()
				return purchaseHandler.OnPurchase(player)
			end)
			
			if success and result then
				print(string.format("[MonetizationService] Player %s purchased %s", player.Name, purchaseHandler.Name))
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				warn(string.format("[MonetizationService] Failed to process purchase for %s: %s", player.Name, tostring(result)))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		else
			warn(string.format("[MonetizationService] Unknown product ID: %d", productId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	
	Players.PlayerRemoving:Connect(function(player)
		PlayerGamePasses[player.UserId] = nil
		DebugOverrides[player.UserId] = nil
	end)
end

function MonetizationService:KnitStart()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(CheckAllGamePasses, player)
	end

	Players.PlayerAdded:Connect(CheckAllGamePasses)
end

return MonetizationService
