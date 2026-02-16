--[[
	PetService
	Handles pet inventory, equipping, spawning, and despawning.
	Pets are obtained directly from egg purchases and stored in player's inventory.
	Maximum 3 pets can be equipped at once.
	
	Server-side:
	- Only spawns and despawns pet models (no position updates)
	- Validates star collection requests from clients
	- Pet models are replicated to clients who control their positions
	
	Client-side (PetController):
	- Handles ALL pet position updates for all players in same world
	- Local player's pets can collect stars when in arena
	- Other players' pets just follow their owners
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local PetMergeStats = require(ReplicatedStorage.Modules.PetMergeStats)
local RebirthStats = require(ReplicatedStorage.Modules.RebirthStats)

export type Pet = {
	Name: string,
	PetType: string?,
	Multiplier: number,
	PickupRangeBonus: number?,
	RoamRange: number?,
	StarCollectionRadius: number?,
	Velocity: number?,
	World: string?,
	Level: number?,
	TierLevel: number?,
	TierName: string?,
	Rarity: string?,
	ID: string?,
	Equipped: boolean?,
}

local PetService = Knit.CreateService({
	Name = "PetService",
	Client = {
		PetEquipped = Knit.CreateSignal(), -- Signal to notify clients when a pet is equipped
		PetUnequipped = Knit.CreateSignal(), -- Signal to notify clients when a pet is unequipped
		--PetStarCollected = Knit.CreateSignal(), -- Signal to notify client when a pet star is collected
	},
})

-- Private state for runtime pet IDs (not persisted, regenerated each session)
-- [Player.UserId] = { petIndexToID: { [index] = id }, idToPetIndex: { [id] = index } }
local PlayerPetIDs = {}

-- Spawned pet models for each player
-- [Player.UserId] = { [petIndex] = Model }
local SpawnedPets = {}

-- Pending merge data for Missing Merge dev products
-- [Player.UserId] = { tierLevel: number, selectedIndexes: {number}, selectedIDs: {string} }
local PendingMergeData = {}

-- Track if collision group was created
local PetsCollisionGroupCreated = false

-- Constants
local PET_FOLLOW_OFFSET_SPACING = 5 -- Spacing between multiple pets when spawning

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[PetService]: %s", message))
end

-- Generate a unique ID for pets
local function GeneratePetID(): string
	return HttpService:GenerateGUID(false)
end

-- Get a pet model from ServerStorage
local function GetPetModel(petType: string): Model?
	local assetsFolder = ServerStorage:FindFirstChild("Assets")
	if not assetsFolder then
		warn("[PetService]: Assets folder not found in ServerStorage")
		return nil
	end
	
	local petModelsFolder = assetsFolder:FindFirstChild("PetModels")
	if not petModelsFolder then
		warn("[PetService]: PetModels folder not found in ServerStorage.Assets")
		return nil
	end
	
	local petModel = petModelsFolder:FindFirstChild(petType)
	if not petModel then
		warn(string.format("[PetService]: Pet model '%s' not found", petType))
		return nil
	end
	
	return petModel:Clone()
end

-- Spawn a pet model for a player (no position updates, just spawn)
local function SpawnPetModel(player: Player, petIndex: number, petData: Pet)
	local userId = player.UserId
	
	-- Initialize spawned pets table for player if needed
	if not SpawnedPets[userId] then
		SpawnedPets[userId] = {}
	end
	
	-- Respawn if already spawned
	if SpawnedPets[userId][petIndex] then
		--error("Respawning pet that is already spawned!", 3)
		if SpawnedPets[userId][petIndex]:IsA("Model") then SpawnedPets[userId][petIndex]:Destroy() end
		warn("Spawning again.")
	end
	
	local petType = petData.PetType or "StandardPet"
	local petModel = GetPetModel(petType)
	
	-- Get pet stats from Stats.Pets (petData may not have these values saved)
	local petStats = Stats.Pets[petType] or Stats.Pets.StandardPet
	local roamRange = petData.RoamRange or petStats.RoamRange or 30
	local starCollectionRadius = petData.StarCollectionRadius or petStats.StarCollectionRadius or 5
	local petVelocity = petData.Velocity or petStats.Velocity or 20
	
	-- Cap velocity to 50
	petVelocity = math.min(petVelocity or 20, Stats.MaxPetSpeed)

	-- Cap roam range
	roamRange = math.min(roamRange or 30, Stats.MaxPetRoamRange)

	-- Cap star collection radius
	starCollectionRadius = math.min(starCollectionRadius or 5, Stats.MaxStarCollectionRadius)
	
	local multiplier = petData.Multiplier or petStats.Multiplier or 1.0
	
	if not petModel then
		-- Create a simple placeholder if model not found
		petModel = Instance.new("Model")
		petModel.Name = petData.Name or "Pet"
		
		local part = Instance.new("Part")
		part.Name = "PetPart"
		part.Size = Vector3.new(2, 2, 2)
		part.BrickColor = BrickColor.new("Bright yellow")
		part.Anchored = false
		part.CanCollide = false
		part.Parent = petModel
		petModel.PrimaryPart = part
	end
	
	-- Position near player initially
	local world = player:GetAttribute("CurrentWorld")
	local spawnPart = workspace:FindFirstChild(world):FindFirstChild("SpawnLocation")
	print(spawnPart)
	petModel:PivotTo(CFrame.new(spawnPart.Position))

	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local offset = Vector3.new(3 + (petIndex - 1) * PET_FOLLOW_OFFSET_SPACING, 0, 3)
			--petModel:PivotTo(CFrame.new(rootPart.Position + offset))
		end
	end
	
	local primaryPart = petModel.PrimaryPart
	if primaryPart then
		-- Create attachment for body movers (used by client for movement)
		local attachment = Instance.new("Attachment")
		attachment.Name = "PetAttachment"
		attachment.Parent = primaryPart
		
		-- Create AlignPosition for smooth position movement (controlled by client)
		local alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "PetAlignPosition"
		alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPosition.Attachment0 = attachment
		alignPosition.MaxForce = math.huge
		alignPosition.MaxVelocity = petVelocity
		alignPosition.Responsiveness = petVelocity
		-- IMPORTANT: Set initial position to current pet position (not 0,0,0)
		alignPosition.Position = spawnPart.Position
		alignPosition.Parent = primaryPart
		
		-- Create AlignOrientation for smooth rotation (controlled by client)
		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "PetAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Attachment0 = attachment
		alignOrientation.MaxTorque = math.huge
		alignOrientation.MaxAngularVelocity = 20
		alignOrientation.Responsiveness = 20
		-- IMPORTANT: Set initial CFrame to current pet orientation (not 0,0,0)
		alignOrientation.CFrame = primaryPart.CFrame
		alignOrientation.Parent = primaryPart
		
		-- Make pet not collide with players
		if PetsCollisionGroupCreated then
			primaryPart.CollisionGroup = "Pets"
		else
			primaryPart.CanCollide = false
		end
	end
	
	-- Store owner info for clients to identify
	-- Use values from Stats.Pets when petData doesn't have them
	petModel:SetAttribute("OwnerUserId", userId)
	petModel:SetAttribute("PetIndex", petIndex)
	petModel:SetAttribute("PetName", petData.Name)
	petModel:SetAttribute("PetType", petType)
	petModel:SetAttribute("Multiplier", multiplier)
	petModel:SetAttribute("RoamRange", roamRange)
	petModel:SetAttribute("StarCollectionRadius", starCollectionRadius)
	petModel:SetAttribute("Velocity", petVelocity)
	
	petModel.Parent = workspace
	
	-- Set network ownership to the player so client can control pet position
	if primaryPart then
		local success, err = pcall(function()
			primaryPart:SetNetworkOwner(player)
		end)
		if not success then
			warn(string.format("[PetService]: Failed to set network owner: %s", tostring(err)))
		end
	end
	
	SpawnedPets[userId][petIndex] = petModel
	
	Log(string.format("Spawned pet %s for player %s", petData.Name, player.Name))
end

-- Despawn a pet model for a player
local function DespawnPetModel(player: Player, petIndex: number)
	local userId = player.UserId
	
	if not SpawnedPets[userId] then return end
	
	local petModel = SpawnedPets[userId][petIndex]
	if petModel then
		petModel:Destroy()
		SpawnedPets[userId][petIndex] = nil
		Log(string.format("Despawned pet at index %d for player %s", petIndex, player.Name))
	end
end

-- Despawn all pets for a player
local function DespawnAllPets(player: Player)
	local userId = player.UserId
	
	if not SpawnedPets[userId] then return end
	
	for _, petModel in pairs(SpawnedPets[userId]) do
		if petModel then
			petModel:Destroy()
		end
	end
	
	SpawnedPets[userId] = {}
	Log(string.format("Despawned all pets for player %s", player.Name))
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
		for index, petdata in ipairs(inventory.PetInventory) do
			local petID = GeneratePetID()
			PlayerPetIDs[userId].petIndexToID[index] = petID
			PlayerPetIDs[userId].idToPetIndex[petID] = index

			-- for those pets that have an expiry date and have expired, remove.
			if petdata.ExpireLength ~= nil and petdata.ObtainedAt + petdata.ExpireLength < os.time() then
				print("removed", petdata)
				inventory.PetInventory[index] = nil
			end
		end
		
		-- Spawn equipped pets
		if inventory.EquippedPets then
			for _, petIndex in ipairs(inventory.EquippedPets) do
				local petData = inventory.PetInventory[petIndex]
				if petData then
					SpawnPetModel(player, petIndex, petData)
				end
			end
		end
	end
	
	Log(string.format("Initialized pets for player %s", player.Name))
end

-- Register a pet ID mapping (called by EggService when a pet is obtained)
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
		NotificationService:SendNotification(player, "Invalid pet ID.", NotificationService.Category.Error)
		return false, "Invalid pet ID"
	end
	
	-- Get player inventory
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory or not inventory.PetInventory[petIndex] then
		NotificationService:SendNotification(player, "Pet not found in inventory.", NotificationService.Category.Error)
		return false, "Pet not found"
	end
	
	-- Check if already equipped
	if inventory.EquippedPets then
		for _, equippedIndex in ipairs(inventory.EquippedPets) do
			if equippedIndex == petIndex then
				NotificationService:SendNotification(player, "Pet is already equipped.", NotificationService.Category.Warning)
				return false, "Already equipped"
			end
		end
	end
	
	-- Check max equipped limit
	local MonetizationService = Knit.GetService("MonetizationService")
	local maxPets = Stats.MaxEquippedPets
	if MonetizationService:HasGamePass(player, "ExtraPets") then
		maxPets = maxPets + Stats.ExtraPetsBonus
	end
	local equippedCount = inventory.EquippedPets and #inventory.EquippedPets or 0
	if equippedCount >= maxPets then
		NotificationService:SendNotification(player, string.format("Maximum %d pets can be equipped.", maxPets), NotificationService.Category.Warning)
		return false, "Max equipped"
	end

	-- check if expired
	local petData = inventory.PetInventory[petIndex]
	if petData.ExpireLength ~= nil and petData.ObtainedAt + petData.ExpireLength < os.time() then
		NotificationService:SendNotification(player, "This pet has expired and cannot be equipped.", NotificationService.Category.Warning)
		return false, "Pet expired"
	end
	
	-- Equip the pet (save to data)
	DataService:Update(player, "Inventory", function(inv)
		if not inv.EquippedPets then
			inv.EquippedPets = {}
		end
		table.insert(inv.EquippedPets, petIndex)
		return inv
	end)
	
	Log(string.format("Player %s equipped %s", player.Name, petData.Name))
	
	-- Get pet stats from Stats.Pets (petData may not have these values saved)
	local petType = petData.PetType or "StandardPet"
	local petStats = Stats.Pets[petType] or Stats.Pets.StandardPet
	local roamRange = petData.RoamRange or petStats.RoamRange or 30
	local starCollectionRadius = petData.StarCollectionRadius or petStats.StarCollectionRadius or 5
	local velocity = petData.Velocity or petStats.Velocity or 20
	local multiplier = petData.Multiplier or petStats.Multiplier or 1.0
	
	-- Spawn the pet model
	SpawnPetModel(player, petIndex, petData)
	
	-- Fire signal to ALL clients (so they can start managing this pet)
	for _, p in ipairs(Players:GetPlayers()) do
		PetService.Client.PetEquipped:Fire(p, {
			OwnerUserId = player.UserId,
			OwnerName = player.Name,
			ID = petID,
			PetIndex = petIndex,
			Name = petData.Name,
			PetType = petType,
			Multiplier = multiplier,
			RoamRange = roamRange,
			StarCollectionRadius = starCollectionRadius,
			Velocity = velocity,
		})
	end
	
	-- Recalculate fuel since multiplier has changed
	local StarService = Knit.GetService("StarService")
	StarService:RecalculateFuel(player)
	
	return true, nil
end

-- Unequip a pet
function PetService:UnequipPet(player: Player, petID: string): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Get pet index from ID
	local petIndex = self:GetPetIndexByID(player, petID)
	if not petIndex then
		NotificationService:SendNotification(player, "Invalid pet ID.", NotificationService.Category.Error)
		return false, "Invalid pet ID"
	end
	
	-- Get player inventory
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.EquippedPets then
		NotificationService:SendNotification(player, "No pets are equipped.", NotificationService.Category.Warning)
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
		NotificationService:SendNotification(player, "Pet is not equipped.", NotificationService.Category.Warning)
		return false, "Pet not equipped"
	end
	
	Log(string.format("Player %s unequipped pet at index %d", player.Name, petIndex))
	
	-- Despawn the pet model
	DespawnPetModel(player, petIndex)
	
	-- Fire signal to ALL clients
	for _, p in ipairs(Players:GetPlayers()) do
		PetService.Client.PetUnequipped:Fire(p, {
			OwnerUserId = player.UserId,
			ID = petID,
			PetIndex = petIndex,
		})
	end
	
	-- Recalculate fuel since multiplier has changed
	local StarService = Knit.GetService("StarService")
	StarService:RecalculateFuel(player)
	
	return true, nil
end

-- Unequip a pet by inventory index (used internally by TradeService)
function PetService:UnequipPetByIndex(player: Player, petIndex: number): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	
	-- Get player inventory
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.EquippedPets then
		return false, "No pets equipped"
	end
	
	-- Check if this pet is equipped
	local found = false
	for _, equippedIndex in ipairs(inventory.EquippedPets) do
		if equippedIndex == petIndex then
			found = true
			break
		end
	end
	
	if not found then
		return true, nil -- Pet not equipped, nothing to do
	end
	
	-- Get pet ID for signaling
	local petID = self:GetPetIDByIndex(player, petIndex)
	
	-- Remove from equipped
	DataService:Update(player, "Inventory", function(inv)
		if inv.EquippedPets then
			for i, equippedIdx in ipairs(inv.EquippedPets) do
				if equippedIdx == petIndex then
					table.remove(inv.EquippedPets, i)
					break
				end
			end
		end
		return inv
	end)
	
	Log(string.format("Player %s unequipped pet at index %d (by index)", player.Name, petIndex))
	
	-- Despawn the pet model
	DespawnPetModel(player, petIndex)
	
	-- Fire signal to ALL clients
	for _, p in ipairs(Players:GetPlayers()) do
		PetService.Client.PetUnequipped:Fire(p, {
			OwnerUserId = player.UserId,
			ID = petID or "",
			PetIndex = petIndex,
		})
	end
	
	-- Recalculate fuel since multiplier has changed
	local StarService = Knit.GetService("StarService")
	StarService:RecalculateFuel(player)
	
	return true, nil
end

-- Get all pets for a player (with runtime IDs)
function PetService:GetPlayerPets(player: Player): { Pet }
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
			-- Get pet stats from Stats.Pets (petData may not have these values saved)
			local petType = petData.PetType or "StandardPet"
			local petStats = Stats.Pets[petType] or Stats.Pets.StandardPet
			
			table.insert(pets, {
				ID = petID,
				Name = petData.Name,
				PetType = petType,
				Multiplier = petData.Multiplier or petStats.Multiplier or 1.0,
				PickupRangeBonus = petData.PickupRangeBonus or petStats.PickupRangeBonus or 1.0,
				RoamRange = petData.RoamRange or petStats.RoamRange or 30,
				StarCollectionRadius = petData.StarCollectionRadius or petStats.StarCollectionRadius or 5,
				Velocity = petData.Velocity or petStats.Velocity or 20,
				World = petData.World or petStats.World or "Main",
				Level = petData.Level or 1,
				TierLevel = petData.TierLevel or petData.Level or 1,
				TierName = petData.TierName or "Common",
				Rarity = petData.Rarity or petStats.Rarity or "Standard",
				Equipped = equippedSet[index] == true,
			})
		end
	end
	
	return pets
end

-- Merge pets of the same tier level to create a higher tier pet
-- @param player Player - The player performing the merge
-- @param targetPetID string - The ID of the pet to merge into (will be upgraded)
-- @param selectedIndexes { number }? - Optional array of selected pet indexes to merge
-- @param selectedIDs { string }? - Optional array of selected pet IDs (must match indexes)
function PetService:MergePets(player: Player, selectedIndexes: { number }?, selectedIDs: { string }?): (boolean, string?, { Name: string, ID: string, Level: number }?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	if not selectedIndexes or not selectedIDs then
		NotificationService:SendNotification(player, "No pets selected for merge.", NotificationService.Category.Error)
		return false, "No pets selected", nil
	end
	
	if #selectedIndexes == 0 or #selectedIDs == 0 then
		NotificationService:SendNotification(player, "No pets selected for merge.", NotificationService.Category.Error)
		return false, "No pets selected", nil
	end
	
	if #selectedIndexes ~= #selectedIDs then
		NotificationService:SendNotification(player, "Invalid selection data.", NotificationService.Category.Error)
		return false, "Mismatched indexes and IDs", nil
	end
	
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory then
		NotificationService:SendNotification(player, "Inventory not found.", NotificationService.Category.Error)
		return false, "Inventory not found", nil
	end
	
	local firstPetIndex = selectedIndexes[1]
	local firstPet = inventory.PetInventory[firstPetIndex]
	
	if not firstPet then
		NotificationService:SendNotification(player, "Selected pet not found.", NotificationService.Category.Error)
		return false, "Pet not found", nil
	end
	
	local tierLevel = firstPet.TierLevel or firstPet.Level or 1
	local petName = firstPet.Name
	local petType = firstPet.PetType
	local world = firstPet.World
	
	if PetMergeStats.IsMaxTier(tierLevel) then
		NotificationService:SendNotification(player, "Pets are already at maximum tier.", NotificationService.Category.Warning)
		return false, "Max tier reached", nil
	end
	
	local copiesRequired = PetMergeStats.GetCopiesRequired(tierLevel)
	
	if #selectedIndexes ~= copiesRequired then
		NotificationService:SendNotification(player, string.format("Need exactly %d copies to merge at tier %d. Selected %d.", copiesRequired, tierLevel, #selectedIndexes), NotificationService.Category.Warning)
		return false, "Incorrect number of pets selected", nil
	end
	
	for i, petIndex in ipairs(selectedIndexes) do
		local expectedID = self:GetPetIDByIndex(player, petIndex)
		if expectedID ~= selectedIDs[i] then
			NotificationService:SendNotification(player, "Pet selection has changed. Please try again.", NotificationService.Category.Error)
			return false, "Pet ID mismatch - inventory may have changed", nil
		end
		
		local pet = inventory.PetInventory[petIndex]
		if not pet then
			NotificationService:SendNotification(player, "Selected pet no longer exists.", NotificationService.Category.Error)
			return false, "Pet not found at index", nil
		end
		
		local petTierLevel = pet.TierLevel or pet.Level
		if petTierLevel ~= tierLevel then
			NotificationService:SendNotification(player, "Selected pets must all be the same tier.", NotificationService.Category.Error)
			return false, "Tier level mismatch", nil
		end
	end
	
	local mergeCost = PetMergeStats.GetMergeCost(tierLevel)
	local currencies = DataService:Get(player, "Currencies")
	
	if not currencies or (currencies.Gems or 0) < mergeCost then
		NotificationService:SendNotification(player, string.format("Not enough Gems. Need %d Gems.", mergeCost), NotificationService.Category.Warning)
		return false, "Not enough Gems", nil
	end
	
	local equippedPets = inventory.EquippedPets or {}
	local petsToUnequip = {}
	
	for _, equippedIndex in ipairs(equippedPets) do
		for _, selectedIndex in ipairs(selectedIndexes) do
			if equippedIndex == selectedIndex then
				table.insert(petsToUnequip, selectedIndex)
			end
		end
	end
	
	DataService:Update(player, "Currencies", function(curr)
		curr.Gems = (curr.Gems or 0) - mergeCost
		return curr
	end)
	
	for _, petIndexToRemove in ipairs(petsToUnequip) do
		DespawnPetModel(player, petIndexToRemove)
	end
	
	local newTierLevel = tierLevel + 1
	local oldStats = {
		Multiplier = firstPet.Multiplier or 1.0,
		PickupRangeBonus = firstPet.PickupRangeBonus or 1.0,
		RoamRange = firstPet.RoamRange or 30,
		StarCollectionRadius = firstPet.StarCollectionRadius or 5,
		Velocity = firstPet.Velocity or 20,
	}
	local newStats = PetMergeStats.CalculateMergedStats(oldStats, tierLevel)
	local newTier = PetMergeStats.GetTierByLevel(newTierLevel)
	
	local indicesToRemove = {}
	for _, idx in ipairs(selectedIndexes) do
		table.insert(indicesToRemove, idx)
	end
	table.sort(indicesToRemove, function(a, b) return a > b end)
	
	DataService:Update(player, "Inventory", function(inv)
		for _, indexToRemove in ipairs(indicesToRemove) do
			table.remove(inv.PetInventory, indexToRemove)
		end
		
		local newPet = {
			ID = GeneratePetID(),
			Name = petName,
			PetType = petType,
			World = world,
			Level = newTierLevel,
			TierLevel = newTierLevel,
			TierName = newTier.Name,
			Multiplier = newStats.Multiplier,
			PickupRangeBonus = newStats.PickupRangeBonus,
			RoamRange = newStats.RoamRange,
			StarCollectionRadius = newStats.StarCollectionRadius,
			Velocity = newStats.Velocity,
			Equipped = false,
		}
		table.insert(inv.PetInventory, newPet)
		
		if inv.EquippedPets then
			local newEquipped = {}
			for _, equippedIndex in ipairs(inv.EquippedPets) do
				local isRemoved = false
				for _, removedIndex in ipairs(indicesToRemove) do
					if equippedIndex == removedIndex then
						isRemoved = true
						break
					end
				end
				
				if not isRemoved then
					local adjustedIndex = equippedIndex
					for _, removedIndex in ipairs(indicesToRemove) do
						if removedIndex < equippedIndex then
							adjustedIndex = adjustedIndex - 1
						end
					end
					table.insert(newEquipped, adjustedIndex)
				end
			end
			inv.EquippedPets = newEquipped
		end
		
		return inv
	end)
	
	local userId = player.UserId
	if PlayerPetIDs[userId] then
		PlayerPetIDs[userId] = {
			petIndexToID = {},
			idToPetIndex = {},
		}
		
		local newInventory = DataService:Get(player, "Inventory")
		if newInventory and newInventory.PetInventory then
			for index, _ in ipairs(newInventory.PetInventory) do
				local petID = GeneratePetID()
				PlayerPetIDs[userId].petIndexToID[index] = petID
				PlayerPetIDs[userId].idToPetIndex[petID] = index
			end
		end
	end
	
	local newInventory = DataService:Get(player, "Inventory")
	local newPetID = self:GetPetIDByIndex(player, #newInventory.PetInventory)
	
	Log(string.format("Player %s merged %d copies to create %s tier %s (Level %d)", player.Name, copiesRequired, newTier.Name, petName, newTierLevel))
	
	NotificationService:SendNotification(player, string.format("Merged! %s is now %s tier!", petName, newTier.Name), NotificationService.Category.Success)
	
	DataService:FireDataReady(player)
	
	return true, nil, {
		Name = petName,
		ID = newPetID or "",
		Level = newTierLevel,
		TierLevel = newTierLevel,
		TierName = newTier.Name,
		Multiplier = newStats.Multiplier,
		PickupRangeBonus = newStats.PickupRangeBonus,
		RoamRange = newStats.RoamRange,
		StarCollectionRadius = newStats.StarCollectionRadius,
		Velocity = newStats.Velocity,
	}
end

-- Validate and process pet star collection from client
-- Client must be the local player and pet must be within range
function PetService:PetCollectStar(player: Player, starId: string, petPosition: Vector3): (boolean, string?)
	local character = player.Character
	if not character then
		return false, "No character"
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart"
	end
	
	-- Get the maximum RoamRange and StarCollectionRadius from equipped pets
	-- Also collect equipped pet data for fuel multiplier calculation
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	local maxRoamRange = 30
	local maxStarCollectionRadius = 5
	local equippedPets = {}
	
	if inventory and inventory.PetInventory and inventory.EquippedPets then
		for _, petIndex in ipairs(inventory.EquippedPets) do
			local petData = inventory.PetInventory[petIndex]
			if petData then
				-- Get pet stats from Stats.Pets (petData may not have these values saved)
				local petType = petData.PetType or "StandardPet"
				local petStats = Stats.Pets[petType] or Stats.Pets.StandardPet
				local roamRange = petData.RoamRange or petStats.RoamRange or 30
				local starCollectionRadius = petData.StarCollectionRadius or petStats.StarCollectionRadius or 5
				
				maxRoamRange = math.max(maxRoamRange, roamRange)
				maxStarCollectionRadius = math.max(maxStarCollectionRadius, starCollectionRadius)
				
				-- Create pet data with proper stats for multiplier calculation
				table.insert(equippedPets, {
					Multiplier = petData.Multiplier or petStats.Multiplier or 1.0,
				})
			end
		end
	end
	
	-- Get star information from StarService
	local StarService = Knit.GetService("StarService")
	local starInfoList = StarService:GetStarInformation(player)
	
	if not starInfoList then
		return false, "No star information"
	end
	
	-- Find the target star
	local targetStar = nil
	for _, star in ipairs(starInfoList) do
		if star.ID == starId then
			targetStar = star
			break
		end
	end
	
	if not targetStar then
		return false, "Star not found"
	end
	
	-- Validate that the star is within the pet's roam range from the player
	local playerPosition = rootPart.Position
	local distanceFromPlayer = (targetStar.Position - playerPosition).Magnitude
	
	if distanceFromPlayer > maxRoamRange then
		Log(string.format("Pet star collection rejected: star too far from player (%.2f > %.2f)", distanceFromPlayer, maxRoamRange))
		return false, "Star out of range"
	end
	
	-- Validate that the pet position is close enough to the star
	local distanceFromPet = (targetStar.Position - petPosition).Magnitude
	if distanceFromPet > maxStarCollectionRadius then
		Log(string.format("Pet star collection rejected: pet too far from star (%.2f > %.2f)", distanceFromPet, maxStarCollectionRadius))
		return false, "Pet not close enough to star"
	end
	
	-- Use existing star collection logic
	local starEquivalent = StarService:CollectStarServer(player, starId)
	
	if not starEquivalent then
		return false, "Collection failed"
	end
	
	-- Add star equivalents to player's Stars count and recalculate fuel
	DataService:Update(player, "Stats", function(currentStats)
		currentStats.Stars = (currentStats.Stars or 0) + starEquivalent
		return currentStats
	end)
	
	-- Recalculate fuel based on new Stars count and current multipliers
	StarService:RecalculateFuel(player)
	
	
	-- Notify client that star was collected
	--[[
	self.Client.PetStarCollected:Fire(player, {
		StarId = starId,
		StarEquivalent = starEquivalent,
	})]]
	
	return true, nil
end

-- Client request to equip a pet
function PetService.Client:RequestEquipPet(player: Player, petID: string): (boolean, string?)
	return PetService:EquipPet(player, petID)
end

-- Client request to unequip a pet
function PetService.Client:RequestUnequipPet(player: Player, petID: string): (boolean, string?)
	return PetService:UnequipPet(player, petID)
end

function PetService.Client:RequestMergePets(player: Player, selectedIndexes: { number }?, selectedIDs: { string }?)
	return PetService:MergePets(player, selectedIndexes, selectedIDs)
end

-- Client request to get all pets
function PetService.Client:GetPets(player: Player)
	return PetService:GetPlayerPets(player)
end

-- Client request for pet to collect a star (with range validation)
function PetService.Client:RequestPetCollectStar(player: Player, starId: string, petPosition: Vector3): (boolean, string?)
	return PetService:PetCollectStar(player, starId, petPosition)
end

function PetService.Client:RequestPetAttackBoss(player: Player): (boolean, string?)
	return PetService:PetAttackBoss(player)
end

-- Handle pet attacking boss (damage 1 HP per attack)
function PetService:PetAttackBoss(player: Player): (boolean, string?)
	local BossService = Knit.GetService("BossService")
	if not BossService then
		return false, "BossService not available"
	end
	
	if not BossService:IsBossFightActive() then
		return false, "No boss fight active"
	end
	
	-- Each pet attack does 1 damage
	BossService:DamageBoss(1)
	return true, nil
end

--[[
	Despawn all pets for a player (public method for world switching).
	Call this before teleporting to a new world.
	
	@param player Player - The player whose pets to despawn
]]
function PetService:DespawnAllPetsForPlayer(player: Player)
	DespawnAllPets(player)
end

--[[
	Respawn all equipped pets for a player (public method for world switching).
	Call this after teleporting to a new world.
	
	@param player Player - The player whose pets to respawn
]]
function PetService:RespawnEquippedPets(player: Player)
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	
	if inventory and inventory.PetInventory and inventory.EquippedPets then
		for _, petIndex in ipairs(inventory.EquippedPets) do
			local petData = inventory.PetInventory[petIndex]
			if petData then
				SpawnPetModel(player, petIndex, petData)
			end
		end
	end
	
	Log(string.format("Respawned equipped pets for player %s", player.Name))
end

--[[
	Get all spawned pet models for a player.
	Returns a table of { [petIndex] = Model }
	
	@param player Player - The player whose pets to get
	@return { [number]: Model } - Table of pet models keyed by pet index
]]
function PetService:GetSpawnedPets(player: Player): { [number]: Model }
	local userId = player.UserId
	return SpawnedPets[userId] or {}
end

-- Store pending merge data for Missing Merge dev product purchases
-- Called when client detects they're 1 pet short before prompting purchase
function PetService:StorePendingMerge(player: Player, tierLevel: number, selectedIndexes: { number }, selectedIDs: { string }): boolean
	local userId = player.UserId
	
	-- Validate the data
	if not tierLevel or tierLevel < 1 or tierLevel > 3 then
		return false
	end
	
	if not selectedIndexes or not selectedIDs then
		return false
	end
	
	PendingMergeData[userId] = {
		tierLevel = tierLevel,
		selectedIndexes = selectedIndexes,
		selectedIDs = selectedIDs,
		timestamp = os.time(),
	}
	
	Log(string.format("Stored pending merge for player %s: tier %d with %d pets", player.Name, tierLevel, #selectedIndexes))
	return true
end

-- Get pending merge data for a player
function PetService:GetPendingMergeData(player: Player)
	local userId = player.UserId
	return PendingMergeData[userId]
end

-- Clear pending merge data for a player
function PetService:ClearPendingMerge(player: Player)
	local userId = player.UserId
	PendingMergeData[userId] = nil
end

-- Merge pets with exception (1 pet short) - called from dev product OnPurchase
-- targetTierLevel: 1 = create Tier 2, 2 = create Tier 3, 3 = create Tier 4
function PetService:MergePetsWithException(player: Player, targetTierLevel: number): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	local userId = player.UserId
	local pendingData = PendingMergeData[userId]
	
	if not pendingData then
		return false, "No pending merge data"
	end
	
	-- Validate that pending data matches the purchased tier
	if pendingData.tierLevel ~= targetTierLevel then
		PendingMergeData[userId] = nil
		return false, "Pending merge tier mismatch"
	end
	
	-- Check if data is too old (5 minutes max)
	if os.time() - pendingData.timestamp > 300 then
		PendingMergeData[userId] = nil
		return false, "Pending merge expired"
	end
	
	local selectedIndexes = pendingData.selectedIndexes
	local selectedIDs = pendingData.selectedIDs
	local tierLevel = pendingData.tierLevel
	
	-- Clear pending data
	PendingMergeData[userId] = nil
	
	if not selectedIndexes or not selectedIDs or #selectedIndexes == 0 then
		return false, "Invalid pending merge data"
	end
	
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory then
		return false, "Inventory not found"
	end
	
	local firstPetIndex = selectedIndexes[1]
	local firstPet = inventory.PetInventory[firstPetIndex]
	
	if not firstPet then
		return false, "Selected pet not found"
	end
	
	-- Verify the pet's tier matches what we expect
	local petTierLevel = firstPet.TierLevel or firstPet.Level or 1
	if petTierLevel ~= tierLevel then
		return false, "Pet tier mismatch"
	end
	
	local petName = firstPet.Name
	local petType = firstPet.PetType
	local world = firstPet.World
	
	if PetMergeStats.IsMaxTier(tierLevel) then
		return false, "Max tier reached"
	end
	
	local copiesRequired = PetMergeStats.GetCopiesRequired(tierLevel)
	
	-- For exception merge, we allow 1 less pet than required
	if #selectedIndexes ~= copiesRequired - 1 then
		return false, string.format("Expected %d pets for exception merge, got %d", copiesRequired - 1, #selectedIndexes)
	end
	
	-- Validate all selected pets
	for i, petIndex in ipairs(selectedIndexes) do
		local expectedID = self:GetPetIDByIndex(player, petIndex)
		if expectedID ~= selectedIDs[i] then
			return false, "Pet ID mismatch - inventory may have changed"
		end
		
		local pet = inventory.PetInventory[petIndex]
		if not pet then
			return false, "Pet not found at index"
		end
		
		local currentTierLevel = pet.TierLevel or pet.Level
		if currentTierLevel ~= tierLevel then
			return false, "Tier level mismatch"
		end
	end
	
	-- Check gem cost (same as normal merge)
	local mergeCost = PetMergeStats.GetMergeCost(tierLevel)
	local currencies = DataService:Get(player, "Currencies")
	
	if not currencies or (currencies.Gems or 0) < mergeCost then
		return false, string.format("Not enough Gems. Need %d Gems.", mergeCost)
	end
	
	-- Unequip any selected pets that are equipped
	local equippedPets = inventory.EquippedPets or {}
	local petsToUnequip = {}
	
	for _, equippedIndex in ipairs(equippedPets) do
		for _, selectedIndex in ipairs(selectedIndexes) do
			if equippedIndex == selectedIndex then
				table.insert(petsToUnequip, selectedIndex)
			end
		end
	end
	
	-- Deduct gems
	DataService:Update(player, "Currencies", function(curr)
		curr.Gems = (curr.Gems or 0) - mergeCost
		return curr
	end)
	
	-- Despawn equipped pets that will be merged
	for _, petIndexToRemove in ipairs(petsToUnequip) do
		DespawnPetModel(player, petIndexToRemove)
	end
	
	-- Calculate new pet stats
	local newTierLevel = tierLevel + 1
	local oldStats = {
		Multiplier = firstPet.Multiplier or 1.0,
		PickupRangeBonus = firstPet.PickupRangeBonus or 1.0,
		RoamRange = firstPet.RoamRange or 30,
		StarCollectionRadius = firstPet.StarCollectionRadius or 5,
		Velocity = firstPet.Velocity or 20,
	}
	local newStats = PetMergeStats.CalculateMergedStats(oldStats, tierLevel)
	local newTier = PetMergeStats.GetTierByLevel(newTierLevel)
	
	-- Remove old pets and add new merged pet
	local indicesToRemove = {}
	for _, idx in ipairs(selectedIndexes) do
		table.insert(indicesToRemove, idx)
	end
	table.sort(indicesToRemove, function(a, b) return a > b end)
	
	DataService:Update(player, "Inventory", function(inv)
		for _, indexToRemove in ipairs(indicesToRemove) do
			table.remove(inv.PetInventory, indexToRemove)
		end
		
		local newPet = {
			ID = GeneratePetID(),
			Name = petName,
			PetType = petType,
			World = world,
			Level = newTierLevel,
			TierLevel = newTierLevel,
			TierName = newTier.Name,
			Multiplier = newStats.Multiplier,
			PickupRangeBonus = newStats.PickupRangeBonus,
			RoamRange = newStats.RoamRange,
			StarCollectionRadius = newStats.StarCollectionRadius,
			Velocity = newStats.Velocity,
			Equipped = false,
		}
		table.insert(inv.PetInventory, newPet)
		
		-- Update equipped indexes
		if inv.EquippedPets then
			local newEquipped = {}
			for _, equippedIndex in ipairs(inv.EquippedPets) do
				local isRemoved = false
				for _, removedIndex in ipairs(indicesToRemove) do
					if equippedIndex == removedIndex then
						isRemoved = true
						break
					end
				end
				
				if not isRemoved then
					local adjustedIndex = equippedIndex
					for _, removedIndex in ipairs(indicesToRemove) do
						if removedIndex < equippedIndex then
							adjustedIndex = adjustedIndex - 1
						end
					end
					table.insert(newEquipped, adjustedIndex)
				end
			end
			inv.EquippedPets = newEquipped
		end
		
		return inv
	end)
	
	-- Regenerate pet IDs
	if PlayerPetIDs[userId] then
		PlayerPetIDs[userId] = {
			petIndexToID = {},
			idToPetIndex = {},
		}
		
		local newInventory = DataService:Get(player, "Inventory")
		if newInventory and newInventory.PetInventory then
			for index, _ in ipairs(newInventory.PetInventory) do
				local petID = GeneratePetID()
				PlayerPetIDs[userId].petIndexToID[index] = petID
				PlayerPetIDs[userId].idToPetIndex[petID] = index
			end
		end
	end
	
	Log(string.format("Player %s used Missing Merge to create %s tier %s (Level %d)", player.Name, newTier.Name, petName, newTierLevel))
	
	DataService:FireDataReady(player)
	
	return true, nil
end

-- Client function to store pending merge data
function PetService.Client:StorePendingMerge(player: Player, tierLevel: number, selectedIndexes: { number }, selectedIDs: { string }): boolean
	return PetService:StorePendingMerge(player, tierLevel, selectedIndexes, selectedIDs)
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	local userId = player.UserId
	
	-- Despawn all pets
	DespawnAllPets(player)
	
	-- Clean up data
	PlayerPetIDs[userId] = nil
	SpawnedPets[userId] = nil
	PendingMergeData[userId] = nil
	
	Log(string.format("Cleared pet data for player %s", player.Name))
end

-- Knit lifecycle
function PetService:KnitInit()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	
	-- Create collision group for pets
	local PhysicsService = game:GetService("PhysicsService")
	
	local success = pcall(function()
		PhysicsService:RegisterCollisionGroup("Pets")
		PhysicsService:CollisionGroupSetCollidable("Pets", "Default", false)
	end)
	
	PetsCollisionGroupCreated = success
	if success then
		Log("Created Pets collision group")
	else
		Log("Failed to create Pets collision group, using CanCollide=false fallback")
	end

	-- a thread that executes every one minute to check for expired pets and unequip them (and remove them)
	task.spawn(function()
		while true do
			task.wait(1)
			
			for _, player in ipairs(Players:GetPlayers()) do
				local DataService = Knit.GetService("DataService")
				local NotificationService = Knit.GetService("NotificationService")

				if not DataService or not NotificationService then
					continue
				end
				
				local inventory = DataService:Get(player, "Inventory")
				if inventory and inventory.PetInventory and inventory.EquippedPets then
					local equippedPets = inventory.EquippedPets
					local petInventory = inventory.PetInventory
					local hasExpiredPets = false
					
					for i = #equippedPets, 1, -1 do
						local petIndex = equippedPets[i]
						local petData = petInventory[petIndex]
						
						if petData and petData.ExpireLength and petData.ObtainedAt and (petData.ObtainedAt + petData.ExpireLength < os.time()) then
							-- This pet has expired - unequip it
							DespawnPetModel(player, petIndex)
							table.remove(equippedPets, i)
							table.remove(petInventory, petIndex) -- Remove the expired pet from inventory
							hasExpiredPets = true
						end
					end
					
					if hasExpiredPets then
						-- Update inventory with expired pets removed from equipped list
						DataService:Update(player, "Inventory", function(inv)
							inv.EquippedPets = equippedPets
							inv.PetInventory = petInventory
							return inv
						end)
						
						NotificationService:SendNotification(player, "One or more of your pets have expired and were unequipped.", NotificationService.Category.Warning)
						
						-- Recalculate fuel since multiplier may have changed
						local StarService = Knit.GetService("StarService")
						StarService:RecalculateFuel(player)

						DataService:FireDataReady(player) -- Refresh client data to reflect changes
					end
				end
			end
		end
	end)
	
	Log("PetService initialized")
end

function PetService:KnitStart()
	-- No behavior loop needed - clients handle all pet positions
	Log("PetService started")
end

return PetService
