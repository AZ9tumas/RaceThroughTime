--[[
	EggService
	Handles egg purchasing for players.
	When an egg is purchased, the pet hatches immediately and is added to inventory.
	No eggs are stored - only the resulting pets are persisted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local EggService = Knit.CreateService({
	Name = "EggService",
	Client = {
		PetObtained = Knit.CreateSignal(), -- Signal to notify client when a pet is obtained from egg purchase
	},
})

-- Helper function for logging
local function Log(message: string)
	print(string.format("[EggService]: %s", message))
end

-- Generate a unique ID for pets
local function GeneratePetID(): string
	return HttpService:GenerateGUID(false)
end

--[[
	Purchase an egg and immediately hatch it to get a pet.
	The egg is not stored - the resulting pet is added directly to inventory.
	@param player Player - The player purchasing the egg
	@param eggType string - The type of egg to purchase (e.g., "StandardEgg")
	@return (boolean, string?, { Name: string, ID: string, Multiplier: number }?) - Success status, error message if failed, pet info if successful
]]
function EggService:PurchaseEgg(player: Player, eggType: string): (boolean, string?, { Name: string, ID: string, Multiplier: number }?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	local PetService = Knit.GetService("PetService")
	
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
	
	-- Get pet type from egg
	local petType = eggConfig.Pet
	local petConfig = Stats.Pets[petType]
	if not petConfig then
		NotificationService:SendNotification(
			player,
			"Pet configuration not found.",
			NotificationService.Category.Error
		)
		return false, "Pet config not found", nil
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
	
	-- Generate pet ID and add pet to inventory immediately
	local petID = GeneratePetID()
	local newPetIndex = nil
	
	DataService:Update(player, "Inventory", function(inventory)
		if not inventory.PetInventory then
			inventory.PetInventory = {}
		end
		
		-- Add pet with name and multiplier
		local petEntry = {
			PetType = petType,
			Name = petConfig.Name,
			Multiplier = petConfig.Multiplier,
			ObtainedAt = os.time(),
		}
		table.insert(inventory.PetInventory, petEntry)
		newPetIndex = #inventory.PetInventory
		
		return inventory
	end)
	
	-- Register the runtime pet ID with PetService
	PetService:RegisterPetID(player, newPetIndex, petID)
	
	Log(string.format("Player %s purchased %s and obtained %s (ID: %s) for %d %s", 
		player.Name, eggType, petConfig.Name, petID, cost, currencyType))
	
	NotificationService:SendNotification(
		player,
		string.format("Obtained %s!", petConfig.Name),
		NotificationService.Category.Success
	)
	
	local petInfo = {
		Name = petConfig.Name,
		ID = petID,
		Multiplier = petConfig.Multiplier,
	}
	
	-- Fire signal to client
	EggService.Client.PetObtained:Fire(player, petInfo)
	
	return true, nil, petInfo
end

-- Client request to purchase an egg (immediately hatches to pet)
function EggService.Client:RequestPurchaseEgg(player: Player, eggType: string): (boolean, string?, { Name: string, ID: string, Multiplier: number }?)
	return EggService:PurchaseEgg(player, eggType)
end

-- Knit lifecycle
function EggService:KnitInit()
	Log("EggService initialized")
end

function EggService:KnitStart()
	Log("EggService started")
end

return EggService
