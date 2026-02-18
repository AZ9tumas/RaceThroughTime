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
		PlayHatchAnimation = Knit.CreateSignal(), -- Signal to trigger hatch animation on client
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
	Hatch an egg for a player without charging currency.
	Useful for dev products, rewards, etc.
	@param player Player - The player hatching the egg
	@param eggType string - The type of egg to hatch
	@return (boolean, string?, { Name: string, ID: string, Multiplier: number }?) - Success status, error message if failed, pet info if successful
]]
function EggService:HatchEgg(player: Player, eggType: string): (boolean, string?, { Name: string, ID: string, Multiplier: number }?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	local PetService = Knit.GetService("PetService")
	local MonetizationService = Knit.GetService("MonetizationService")
	
	-- Check if egg type exists
	local eggConfig = Stats.Eggs[eggType]
	if not eggConfig then
		if NotificationService then
			NotificationService:SendNotification(
				player,
				"Invalid egg type.",
				NotificationService.Category.Error
			)
		end
		return false, "Invalid egg type", nil
	end
	
	-- Check if player has space in inventory
	local inventory = DataService:Get(player, "Inventory")
	local currentPetCount = inventory and inventory.PetInventory and #inventory.PetInventory or 0
	local maxInventory = Stats.MaxPetInventory
	if MonetizationService:HasGamePass(player, "ExtraSlots") then
		maxInventory = maxInventory + Stats.ExtraSlotsBonus
	end
	if currentPetCount >= maxInventory then
		if NotificationService then
			NotificationService:SendNotification(
				player,
				string.format("Inventory full! Maximum %d pets allowed.", maxInventory),
				NotificationService.Category.Warning
			)
		end
		return false, "Inventory full", nil
	end
	
	-- Get pet type from egg based on probability
	local petType = nil
	
	-- Support both old format (single Pet) and new format (Pets array with probabilities)
	if eggConfig.Pets and #eggConfig.Pets > 0 then
		-- New format: select pet based on probability
		-- Determine which probability distributions are available
		local hasLuck = MonetizationService:HasGamePass(player, "Luck")
		local ServerBonusService = Knit.GetService("ServerBonusService")
		if not hasLuck then hasLuck = ServerBonusService:IsBonusEnabled("LuckParty") end
		
		local hasSuperLuck = MonetizationService:HasGamePass(player, "SuperLuck")
		local PotionsService = Knit.GetService("PotionsService")
		if not hasSuperLuck then hasSuperLuck = PotionsService:HasPotionEffect(player, "SuperLuck") end
		
		local random = math.random()
		local cumulativeProbability = 0
		
		for _, petOption in ipairs(eggConfig.Pets) do
			local probability = Stats.CalculateStackedProbability(
				petOption.Probability,
				petOption.LuckProbability or petOption.Probability,
				petOption.SuperLuckProbability or petOption.Probability,
				hasLuck,
				hasSuperLuck
			)
			cumulativeProbability = cumulativeProbability + probability
			if random <= cumulativeProbability then
				petType = petOption.Pet
				break
			end
		end
		
		-- Fallback to first pet if probabilities don't sum to 1.0
		if not petType then
			petType = eggConfig.Pets[1].Pet
		end
	else
		-- Old format: single Pet field
		petType = eggConfig.Pet
	end
	
	local petConfig = Stats.Pets[petType]
	if not petConfig then
		if NotificationService then
			NotificationService:SendNotification(
				player,
				"Pet configuration not found.",
				NotificationService.Category.Error
			)
		end
		return false, "Pet config not found", nil
	end
	
	-- Generate pet ID and add pet to inventory immediately
	local petID = GeneratePetID()
	local newPetIndex = nil

	local finalPetEntry = {}
	for key, val in pairs(petConfig) do
		finalPetEntry[key] = val
	end

	finalPetEntry.ObtainedAt = os.time()
	finalPetEntry.Locked = false
	
	DataService:Update(player, "Inventory", function(inventory)
		if not inventory.PetInventory then
			inventory.PetInventory = {}
		end
		
		-- Add pet with all stats from config
		table.insert(inventory.PetInventory, finalPetEntry)
		newPetIndex = #inventory.PetInventory
		
		return inventory
	end)
	
	-- Register the runtime pet ID with PetService
	PetService:RegisterPetID(player, newPetIndex, petID)
	
	Log(string.format("Player %s hatched %s and obtained %s (ID: %s)", 
		player.Name, eggType, petConfig.Name, petID))
	
	if NotificationService then
		NotificationService:SendNotification(
			player,
			string.format("Obtained %s!", petConfig.Name),
			NotificationService.Category.Success
		)
	end
	
	-- Fire signal to trigger hatch animation on client
	EggService.Client.PlayHatchAnimation:Fire(player, eggType, finalPetEntry)
	
	-- Fire signal to client
	EggService.Client.PetObtained:Fire(player, finalPetEntry)
	DataService:FireDataReady(player)
	
	return true, nil, finalPetEntry
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
	
	-- Get pet type from egg based on probability
	local petType = nil
	
	-- Support both old format (single Pet) and new format (Pets array with probabilities)
	if eggConfig.Pets and #eggConfig.Pets > 0 then
		-- New format: select pet based on probability
		-- Determine which probability distributions are available
		local MonetizationService = Knit.GetService("MonetizationService")
		local hasLuck = MonetizationService:HasGamePass(player, "Luck")
		local ServerBonusService = Knit.GetService("ServerBonusService")
		if not hasLuck then hasLuck = ServerBonusService:IsBonusEnabled("LuckParty") end
		
		local hasSuperLuck = MonetizationService:HasGamePass(player, "SuperLuck")
		local PotionsService = Knit.GetService("PotionsService")
		if not hasSuperLuck then hasSuperLuck = PotionsService:HasPotionEffect(player, "SuperLuck") end
		
		local random = math.random()
		local cumulativeProbability = 0
		
		for _, petOption in ipairs(eggConfig.Pets) do
			local probability = Stats.CalculateStackedProbability(
				petOption.Probability,
				petOption.LuckProbability or petOption.Probability,
				petOption.SuperLuckProbability or petOption.Probability,
				hasLuck,
				hasSuperLuck
			)
			cumulativeProbability = cumulativeProbability + probability
			if random <= cumulativeProbability then
				petType = petOption.Pet
				break
			end
		end
		
		-- Fallback to first pet if probabilities don't sum to 1.0
		if not petType then
			petType = eggConfig.Pets[1].Pet
		end
	else
		-- Old format: single Pet field
		petType = eggConfig.Pet
	end
	
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
	
	-- Check if player has space in inventory
	local inventory = DataService:Get(player, "Inventory")
	local currentPetCount = inventory and inventory.PetInventory and #inventory.PetInventory or 0
	local MonetizationService = Knit.GetService("MonetizationService")
	local maxInventory = Stats.MaxPetInventory
	if MonetizationService:HasGamePass(player, "ExtraSlots") then
		maxInventory = maxInventory + Stats.ExtraSlotsBonus
	end
	if currentPetCount >= maxInventory then
		NotificationService:SendNotification(
			player,
			string.format("Inventory full! Maximum %d pets allowed.", maxInventory),
			NotificationService.Category.Warning
		)
		return false, "Inventory full", nil
	end
	
	-- Deduct currency
	DataService:Update(player, "Currencies", function(curr)
		curr[currencyType] = (curr[currencyType] or 0) - cost
		return curr
	end)
	
	-- Generate pet ID and add pet to inventory immediately
	local petID = GeneratePetID()
	local newPetIndex = nil

	local finalPetEntry = {}
	for key, val in pairs(petConfig) do
		finalPetEntry[key] = val
	end

	finalPetEntry.ObtainedAt = os.time()
	finalPetEntry.Locked = false
	
	DataService:Update(player, "Inventory", function(inventory)
		if not inventory.PetInventory then
			inventory.PetInventory = {}
		end
		
		-- Add pet with all stats from config
		table.insert(inventory.PetInventory, finalPetEntry)
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
	
	-- Fire signal to client
	EggService.Client.PetObtained:Fire(player, finalPetEntry)
	DataService:FireDataReady(player)
	
	return true, nil, finalPetEntry
end

-- Client request to purchase an egg (immediately hatches to pet)
function EggService.Client:RequestPurchaseEgg(player: Player, eggType: string): (boolean, string?, { Name: string, ID: string, Multiplier: number }?)
	return EggService:PurchaseEgg(player, eggType)
end

-- Client request to purchase multiple eggs at once
function EggService.Client:RequestPurchaseMultipleEggs(player: Player, eggType: string, count: number): (number, { any })
	local purchasedCount = 0
	local pets = {}
	
	count = math.min(count, 10)
	
	for _ = 1, count do
		local success, _errorMsg, petInfo = EggService:PurchaseEgg(player, eggType)
		if success and petInfo then
			purchasedCount = purchasedCount + 1
			table.insert(pets, petInfo)
		else
			break
		end
	end
	
	return purchasedCount, pets
end

-- Get egg information for display
function EggService.Client:GetEggInfo(player: Player, eggType: string): { Cost: number, Currency: string, Pets: { { Pet: string, Probability: number } } }?
	local eggConfig = Stats.Eggs[eggType]
	if not eggConfig then
		return nil
	end
	
	return {
		Cost = eggConfig.Cost,
		Currency = eggConfig.Currency,
		Tier = eggConfig.Tier,
		World = eggConfig.World,
		Pets = eggConfig.Pets,
	}
end

-- Validate if player can use auto-hatch (requires AutoHatch gamepass)
function EggService.Client:CanUseAutoHatch(player: Player): boolean
	local MonetizationService = Knit.GetService("MonetizationService")
	return MonetizationService:HasGamePass(player, "AutoHatch")
end

-- Knit lifecycle
function EggService:KnitInit()
	Log("EggService initialized")
end

function EggService:KnitStart()
	Log("EggService started")
end

return EggService
