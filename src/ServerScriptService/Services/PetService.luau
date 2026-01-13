--[[
	PetService
	Handles pet inventory and equipping.
	Pets are obtained directly from egg purchases and stored in player's inventory.
	Maximum 3 pets can be equipped at once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local PetService = Knit.CreateService({
	Name = "PetService",
	Client = {
		PetEquipped = Knit.CreateSignal(), -- Signal to notify client when a pet is equipped
		PetUnequipped = Knit.CreateSignal(), -- Signal to notify client when a pet is unequipped
	},
})

-- Private state for runtime pet IDs (not persisted, regenerated each session)
-- [Player.UserId] = { petIndexToID: { [index] = id }, idToPetIndex: { [id] = index } }
local PlayerPetIDs = {}

-- Helper function for logging
local function Log(message: string)
	print(string.format("[PetService]: %s", message))
end

-- Generate a unique ID for pets
local function GeneratePetID(): string
	return HttpService:GenerateGUID(false)
end

-- Initialize pet IDs for a player (called after data is loaded)
function PetService:InitializePets(player: Player)
	local userId = player.UserId
	local DataService = Knit.GetService("DataService")
	
	-- Initialize player pet ID storage
	PlayerPetIDs[userId] = {
		petIndexToID = {},
		idToPetIndex = {},
	}
	
	-- Get player's pet inventory from data store
	local inventory = DataService:Get(player, "Inventory")
	if inventory and inventory.PetInventory then
		-- Assign IDs to existing pets
		for index, petData in ipairs(inventory.PetInventory) do
			local petID = GeneratePetID()
			PlayerPetIDs[userId].petIndexToID[index] = petID
			PlayerPetIDs[userId].idToPetIndex[petID] = index
		end
	end
	
	Log(string.format("Initialized pets for player %s", player.Name))
end

--[[
	Register a pet ID mapping (called by EggService when a pet is obtained).
	This associates a runtime session ID with a pet's inventory index.
	@param player Player - The player who owns the pet
	@param petIndex number - The index of the pet in the inventory
	@param petID string - The unique runtime ID for the pet
]]
function PetService:RegisterPetID(player: Player, petIndex: number, petID: string)
	local userId = player.UserId
	
	if not PlayerPetIDs[userId] then
		PlayerPetIDs[userId] = {
			petIndexToID = {},
			idToPetIndex = {},
		}
	end
	
	PlayerPetIDs[userId].petIndexToID[petIndex] = petID
	PlayerPetIDs[userId].idToPetIndex[petID] = petIndex
end

-- Get pet ID by inventory index
function PetService:GetPetIDByIndex(player: Player, index: number): string?
	local petIDs = PlayerPetIDs[player.UserId]
	if not petIDs then return nil end
	
	return petIDs.petIndexToID[index]
end

-- Get pet index by ID
function PetService:GetPetIndexByID(player: Player, petID: string): number?
	local petIDs = PlayerPetIDs[player.UserId]
	if not petIDs then return nil end
	
	return petIDs.idToPetIndex[petID]
end

-- Equip a pet
function PetService:EquipPet(player: Player, petID: string): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Get pet index from ID
	local petIndex = self:GetPetIndexByID(player, petID)
	if not petIndex then
		NotificationService:SendNotification(
			player,
			"Invalid pet ID.",
			NotificationService.Category.Error
		)
		return false, "Invalid pet ID"
	end
	
	-- Get player inventory
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory or not inventory.PetInventory[petIndex] then
		NotificationService:SendNotification(
			player,
			"Pet not found in inventory.",
			NotificationService.Category.Error
		)
		return false, "Pet not found"
	end
	
	-- Check if already equipped
	if inventory.EquippedPets then
		for _, equippedIndex in ipairs(inventory.EquippedPets) do
			if equippedIndex == petIndex then
				NotificationService:SendNotification(
					player,
					"Pet is already equipped.",
					NotificationService.Category.Warning
				)
				return false, "Already equipped"
			end
		end
	end
	
	-- Check max equipped limit
	local equippedCount = inventory.EquippedPets and #inventory.EquippedPets or 0
	if equippedCount >= Stats.MaxEquippedPets then
		NotificationService:SendNotification(
			player,
			string.format("Maximum %d pets can be equipped.", Stats.MaxEquippedPets),
			NotificationService.Category.Warning
		)
		return false, "Max equipped"
	end
	
	-- Equip the pet
	DataService:Update(player, "Inventory", function(inv)
		if not inv.EquippedPets then
			inv.EquippedPets = {}
		end
		table.insert(inv.EquippedPets, petIndex)
		return inv
	end)
	
	local petData = inventory.PetInventory[petIndex]
	Log(string.format("Player %s equipped %s", player.Name, petData.Name))
	
	-- Fire signal to client
	PetService.Client.PetEquipped:Fire(player, {
		ID = petID,
		Name = petData.Name,
	})
	
	return true, nil
end

-- Unequip a pet
function PetService:UnequipPet(player: Player, petID: string): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Get pet index from ID
	local petIndex = self:GetPetIndexByID(player, petID)
	if not petIndex then
		NotificationService:SendNotification(
			player,
			"Invalid pet ID.",
			NotificationService.Category.Error
		)
		return false, "Invalid pet ID"
	end
	
	-- Get player inventory
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.EquippedPets then
		NotificationService:SendNotification(
			player,
			"No pets are equipped.",
			NotificationService.Category.Warning
		)
		return false, "No pets equipped"
	end
	
	-- Find and remove from equipped
	local found = false
	DataService:Update(player, "Inventory", function(inv)
		if inv.EquippedPets then
			for i, equippedIndex in ipairs(inv.EquippedPets) do
				if equippedIndex == petIndex then
					table.remove(inv.EquippedPets, i)
					found = true
					break
				end
			end
		end
		return inv
	end)
	
	if not found then
		NotificationService:SendNotification(
			player,
			"Pet is not equipped.",
			NotificationService.Category.Warning
		)
		return false, "Pet not equipped"
	end
	
	Log(string.format("Player %s unequipped pet at index %d", player.Name, petIndex))
	
	-- Fire signal to client
	PetService.Client.PetUnequipped:Fire(player, {
		ID = petID,
	})
	
	return true, nil
end

-- Get all pets for a player (with runtime IDs)
function PetService:GetPlayerPets(player: Player): { { ID: string, Name: string, Multiplier: number, Equipped: boolean } }
	local DataService = Knit.GetService("DataService")
	local pets = {}
	
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory then
		return pets
	end
	
	local equippedSet = {}
	if inventory.EquippedPets then
		for _, equippedIndex in ipairs(inventory.EquippedPets) do
			equippedSet[equippedIndex] = true
		end
	end
	
	for index, petData in ipairs(inventory.PetInventory) do
		local petID = self:GetPetIDByIndex(player, index)
		if petID then
			table.insert(pets, {
				ID = petID,
				Name = petData.Name,
				Multiplier = petData.Multiplier,
				Equipped = equippedSet[index] == true,
			})
		end
	end
	
	return pets
end

-- Client request to equip a pet
function PetService.Client:RequestEquipPet(player: Player, petID: string): (boolean, string?)
	return PetService:EquipPet(player, petID)
end

-- Client request to unequip a pet
function PetService.Client:RequestUnequipPet(player: Player, petID: string): (boolean, string?)
	return PetService:UnequipPet(player, petID)
end

-- Client request to get all pets
function PetService.Client:GetPets(player: Player): { { ID: string, Name: string, Multiplier: number, Equipped: boolean } }
	return PetService:GetPlayerPets(player)
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	PlayerPetIDs[player.UserId] = nil
	Log(string.format("Cleared pet data for player %s", player.Name))
end

-- Knit lifecycle
function PetService:KnitInit()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	Log("PetService initialized")
end

function PetService:KnitStart()
	Log("PetService started")
end

return PetService
