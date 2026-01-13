--[[
	EggService
	Handles egg purchasing and tracking for players.
	Only one egg per kind can be purchased. Eggs have unique IDs assigned on purchase.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local EggService = Knit.CreateService({
	Name = "EggService",
	Client = {
		EggPurchased = Knit.CreateSignal(), -- Signal to notify client when an egg is purchased
	},
})

-- Private state
-- [Player.UserId] = { [EggType] = { id = string, purchased = boolean } }
local PlayerEggs = {}

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[EggService]: %s", message))
end

-- Generate a unique ID for eggs
local function GenerateEggID(): string
	return HttpService:GenerateGUID(false)
end

-- Initialize eggs for a player (called after data is loaded)
function EggService:InitializeEggs(player: Player)
	local userId = player.UserId
	
	-- Initialize player egg storage if not exists
	if not PlayerEggs[userId] then
		PlayerEggs[userId] = {}
	end
	
	Log(string.format("Initialized eggs for player %s", player.Name))
end

-- Get all eggs for a player
function EggService:GetPlayerEggs(player: Player): { [string]: { id: string, purchased: boolean } }
	return PlayerEggs[player.UserId] or {}
end

-- Check if player has purchased a specific egg type
function EggService:HasEgg(player: Player, eggType: string): boolean
	local eggs = PlayerEggs[player.UserId]
	if not eggs then return false end
	
	local egg = eggs[eggType]
	return egg ~= nil and egg.purchased == true
end

-- Get egg data for a specific egg type
function EggService:GetEgg(player: Player, eggType: string): { id: string, purchased: boolean }?
	local eggs = PlayerEggs[player.UserId]
	if not eggs then return nil end
	
	return eggs[eggType]
end

-- Purchase an egg for the player
function EggService:PurchaseEgg(player: Player, eggType: string): (boolean, string?, { id: string }?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Check if egg type exists
	local eggConfig = Stats.Eggs[eggType]
	if not eggConfig then
		NotificationService:SendNotification(
			player,
			"Invalid egg type.",
			NotificationService.Category.Error
		)
		return false, "Invalid egg type", nil
	end
	
	-- Check if player already has this egg
	if self:HasEgg(player, eggType) then
		NotificationService:SendNotification(
			player,
			"You already own this egg!",
			NotificationService.Category.Warning
		)
		return false, "Already owned", nil
	end
	
	-- Get player currencies
	local currencies = DataService:Get(player, "Currencies")
	if not currencies then
		NotificationService:SendNotification(
			player,
			"Data not loaded yet. Please try again.",
			NotificationService.Category.Error
		)
		return false, "Data not loaded", nil
	end
	
	-- Check if player has enough currency
	local currencyType = eggConfig.Currency
	local cost = eggConfig.Cost
	local currentAmount = currencies[currencyType] or 0
	
	if currentAmount < cost then
		NotificationService:SendNotification(
			player,
			string.format("Not enough %s! Need %d, have %d.", currencyType, cost, currentAmount),
			NotificationService.Category.Warning
		)
		return false, "Insufficient funds", nil
	end
	
	-- Deduct currency
	DataService:Update(player, "Currencies", function(curr)
		curr[currencyType] = (curr[currencyType] or 0) - cost
		return curr
	end)
	
	-- Generate unique ID and store egg
	local eggID = GenerateEggID()
	local userId = player.UserId
	
	if not PlayerEggs[userId] then
		PlayerEggs[userId] = {}
	end
	
	PlayerEggs[userId][eggType] = {
		id = eggID,
		purchased = true,
	}
	
	Log(string.format("Player %s purchased %s (ID: %s) for %d %s", 
		player.Name, eggType, eggID, cost, currencyType))
	
	NotificationService:SendNotification(
		player,
		string.format("Purchased %s!", eggType),
		NotificationService.Category.Success
	)
	
	-- Fire signal to client
	EggService.Client.EggPurchased:Fire(player, {
		eggType = eggType,
		id = eggID,
	})
	
	return true, nil, { id = eggID }
end

-- Remove egg after hatching (called by PetService)
function EggService:RemoveEgg(player: Player, eggType: string): boolean
	local userId = player.UserId
	local eggs = PlayerEggs[userId]
	
	if not eggs or not eggs[eggType] then
		return false
	end
	
	eggs[eggType] = nil
	Log(string.format("Removed egg %s from player %s", eggType, player.Name))
	
	return true
end

-- Get egg type by ID
function EggService:GetEggTypeByID(player: Player, eggID: string): string?
	local eggs = PlayerEggs[player.UserId]
	if not eggs then return nil end
	
	for eggType, eggData in pairs(eggs) do
		if eggData.id == eggID then
			return eggType
		end
	end
	
	return nil
end

-- Client request to purchase an egg
function EggService.Client:RequestPurchaseEgg(player: Player, eggType: string): (boolean, string?, { id: string }?)
	return EggService:PurchaseEgg(player, eggType)
end

-- Client request to get owned eggs
function EggService.Client:GetOwnedEggs(player: Player): { [string]: { id: string, purchased: boolean } }
	return EggService:GetPlayerEggs(player)
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	PlayerEggs[player.UserId] = nil
	Log(string.format("Cleared egg data for player %s", player.Name))
end

-- Knit lifecycle
function EggService:KnitInit()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	Log("EggService initialized")
end

function EggService:KnitStart()
	Log("EggService started")
end

return EggService
