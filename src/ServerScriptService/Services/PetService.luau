--[[
	PetService
	Handles pet inventory, equipping, spawning, and behavior.
	Pets are obtained directly from egg purchases and stored in player's inventory.
	Maximum 3 pets can be equipped at once.
	
	Server-side behavior:
	- Pets always roam/follow the player in formation
	- Arena status is tracked and notified to clients
	- Star collection requests from clients are validated for range
	
	Client-side behavior (PetController):
	- When in arena: pets roam around player and collect stars
	- Collection is validated on server (star within roam range from player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local PetMergeStats = require(ReplicatedStorage.Modules.PetMergeStats)

export type Pet = {
	Name: string,
	PetType: string?,
	Multiplier: number,
	FuelBonus: number?,
	PickupRangeBonus: number?,
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
		PetEquipped = Knit.CreateSignal(), -- Signal to notify client when a pet is equipped
		PetUnequipped = Knit.CreateSignal(), -- Signal to notify client when a pet is unequipped
		ArenaStatusChanged = Knit.CreateSignal(), -- Signal to notify client when arena status changes (for pet behavior)
		PetStarCollected = Knit.CreateSignal(), -- Signal to notify client when a pet star is collected
	},
})

-- Private state for runtime pet IDs (not persisted, regenerated each session)
-- [Player.UserId] = { petIndexToID: { [index] = id }, idToPetIndex: { [id] = index } }
local PlayerPetIDs = {}

-- Spawned pet models for each player
-- [Player.UserId] = { [petIndex] = { Model = Model, TargetStarID = string? } }
local SpawnedPets = {}

-- Arena status tracking for each player
-- [Player.UserId] = boolean
local PlayerArenaStatus = {}

-- Pet behavior update loop thread
local PetBehaviorThread = nil

-- Constants for pet behavior
local PET_FOLLOW_DISTANCE = 8 -- Distance behind player to follow
local PET_FOLLOW_OFFSET_SPACING = 5 -- Spacing between multiple pets
local ARENA_CHECK_INTERVAL = 0.1 -- How often to check arena status (seconds)
local PET_UPDATE_INTERVAL = 0.2 -- How often to update pet behavior (seconds)
local PetsCollisionGroupCreated = false -- Track if collision group was created
-- Note: RoamRange and StarCollectionRadius are now pet-specific stats stored in pet data

-- Constants for pet movers (AlignPosition/AlignOrientation)
local PET_ALIGN_MAX_FORCE = 100000
local PET_ALIGN_MAX_VELOCITY = 50
local PET_ALIGN_RESPONSIVENESS = 20
local PET_ALIGN_MAX_TORQUE = 100000
local PET_ALIGN_MAX_ANGULAR_VELOCITY = 20

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[PetService]: %s", message))
end

-- Generate a unique ID for pets
local function GeneratePetID(): string
	return HttpService:GenerateGUID(false)
end

-- Get the central arena part for a player's current world
local function GetCentralArenaForPlayer(player: Player): BasePart?
	local DataService = Knit.GetService("DataService")
	local worldName = DataService:GetPlayerWorld(player)
	
	local worldFolder = workspace:FindFirstChild(worldName)
	if worldFolder then
		local centralArena = worldFolder:FindFirstChild("1_Central_Arena")
		if centralArena and centralArena:IsA("BasePart") then
			return centralArena
		end
	end
	
	-- Fallback to Main world
	local mainWorld = workspace:FindFirstChild("Main")
	if mainWorld then
		local centralArena = mainWorld:FindFirstChild("1_Central_Arena")
		if centralArena and centralArena:IsA("BasePart") then
			return centralArena
		end
	end
	
	return nil
end

-- Check if a player is inside the arena
local function CheckPlayerInArena(player: Player): boolean
	local character = player.Character
	if not character then return false end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	
	local centralArena = GetCentralArenaForPlayer(player)
	if not centralArena then return false end
	
	local DataService = Knit.GetService("DataService")
	local worldName = DataService:GetPlayerWorld(player)
	local arenaRadius = Stats.ArenaRadius[worldName] or Stats.ArenaRadius.Main or 200
	
	-- Calculate horizontal distance (ignoring Y axis) from arena center to player
	local arenaCenter = centralArena.Position
	local playerPos = rootPart.Position
	local horizontalDistance = math.sqrt(
		(playerPos.X - arenaCenter.X)^2 + 
		(playerPos.Z - arenaCenter.Z)^2
	)
	
	return horizontalDistance <= arenaRadius
end

-- Update arena status for a player
local function UpdatePlayerArenaStatus(player: Player)
	local userId = player.UserId
	local wasInArena = PlayerArenaStatus[userId] or false
	local isInArena = CheckPlayerInArena(player)
	
	PlayerArenaStatus[userId] = isInArena
	
	-- Log state changes and notify client for debugging
	if wasInArena ~= isInArena then
		if isInArena then
			Log(string.format("Player %s entered arena", player.Name))
		else
			Log(string.format("Player %s left arena", player.Name))
		end
		-- Notify client of arena status change for pet behavior
		PetService.Client.ArenaStatusChanged:Fire(player, isInArena)
	end
	
	return isInArena
end

-- Check if player is in arena (public function)
function PetService:IsPlayerInArena(player: Player): boolean
	return PlayerArenaStatus[player.UserId] or false
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

-- Spawn a pet model for a player
local function SpawnPetModel(player: Player, petIndex: number, petData: { Name: string, PetType: string?, Multiplier: number })
	local userId = player.UserId
	
	-- Initialize spawned pets table for player if needed
	if not SpawnedPets[userId] then
		SpawnedPets[userId] = {}
	end
	
	-- Don't spawn if already spawned
	if SpawnedPets[userId][petIndex] then
		return
	end
	
	local petType = petData.PetType or "StandardPet"
	local petModel = GetPetModel(petType)
	
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
	
	-- Position near player
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local offset = Vector3.new(3 + (petIndex - 1) * PET_FOLLOW_OFFSET_SPACING, 0, 3)
			petModel:SetPrimaryPartCFrame(CFrame.new(rootPart.Position + offset))
		end
	end
	
	-- Create AlignPosition and AlignOrientation for smooth movement (replaces deprecated BodyPosition)
	local primaryPart = petModel.PrimaryPart
	if primaryPart then
		-- Create attachment for body movers
		local attachment = Instance.new("Attachment")
		attachment.Name = "PetAttachment"
		attachment.Parent = primaryPart
		
		-- Create AlignPosition for smooth position movement
		local alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "PetAlignPosition"
		alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPosition.Attachment0 = attachment
		alignPosition.MaxForce = PET_ALIGN_MAX_FORCE
		alignPosition.MaxVelocity = PET_ALIGN_MAX_VELOCITY
		alignPosition.Responsiveness = PET_ALIGN_RESPONSIVENESS
		alignPosition.Parent = primaryPart
		
		-- Create AlignOrientation for smooth rotation
		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "PetAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Attachment0 = attachment
		alignOrientation.MaxTorque = PET_ALIGN_MAX_TORQUE
		alignOrientation.MaxAngularVelocity = PET_ALIGN_MAX_ANGULAR_VELOCITY
		alignOrientation.Responsiveness = PET_ALIGN_RESPONSIVENESS
		alignOrientation.Parent = primaryPart
		
		-- Make pet not collide with players (only if collision group was created)
		if PetsCollisionGroupCreated then
			primaryPart.CollisionGroup = "Pets"
		else
			primaryPart.CanCollide = false
		end
	end
	
	petModel.Parent = workspace
	
	SpawnedPets[userId][petIndex] = {
		Model = petModel,
		TargetStarID = nil,
	}
	
	Log(string.format("Spawned pet %s for player %s", petData.Name, player.Name))
end

-- Despawn a pet model for a player
local function DespawnPetModel(player: Player, petIndex: number)
	local userId = player.UserId
	
	if not SpawnedPets[userId] then return end
	
	local petInfo = SpawnedPets[userId][petIndex]
	if petInfo and petInfo.Model then
		petInfo.Model:Destroy()
		SpawnedPets[userId][petIndex] = nil
		Log(string.format("Despawned pet at index %d for player %s", petIndex, player.Name))
	end
end

-- Despawn all pets for a player
local function DespawnAllPets(player: Player)
	local userId = player.UserId
	
	if not SpawnedPets[userId] then return end
	
	for petIndex, petInfo in pairs(SpawnedPets[userId]) do
		if petInfo.Model then
			petInfo.Model:Destroy()
		end
	end
	
	SpawnedPets[userId] = {}
	Log(string.format("Despawned all pets for player %s", player.Name))
end

-- Update pet behavior for a single player
-- On the server, pets ALWAYS roam around the player (follow mode)
-- Star collection in arena is handled by the client (PetController)
local function UpdatePetBehavior(player: Player)
	local userId = player.UserId
	local character = player.Character
	
	if not character or not SpawnedPets[userId] then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local petIndex = 0
	
	for index, petInfo in pairs(SpawnedPets[userId]) do
		petIndex = petIndex + 1
		local petModel = petInfo.Model
		if not petModel or not petModel.PrimaryPart then continue end
		
		local primaryPart = petModel.PrimaryPart
		local alignPosition = primaryPart:FindFirstChild("PetAlignPosition")
		local alignOrientation = primaryPart:FindFirstChild("PetAlignOrientation")
		if not alignPosition then continue end
		
		-- Server-side: pets always follow the player in formation
		local offset = Vector3.new(
			math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
			2,
			math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
		)
		alignPosition.Position = rootPart.Position + offset
		
		-- Orient pet to face the same direction as player
		if alignOrientation then
			alignOrientation.CFrame = rootPart.CFrame
		end
	end
end

-- Main pet behavior update loop
local function StartPetBehaviorLoop()
	if PetBehaviorThread then return end
	
	local lastArenaCheck = 0
	local lastPetUpdate = 0
	
	PetBehaviorThread = RunService.Heartbeat:Connect(function(deltaTime)
		lastArenaCheck = lastArenaCheck + deltaTime
		lastPetUpdate = lastPetUpdate + deltaTime
		
		-- Only update pet behavior at throttled interval for performance
		if lastPetUpdate < PET_UPDATE_INTERVAL then
			return
		end
		lastPetUpdate = 0
		
		for _, player in ipairs(Players:GetPlayers()) do
			-- Update arena status periodically
			if lastArenaCheck >= ARENA_CHECK_INTERVAL then
				UpdatePlayerArenaStatus(player)
			end
			
			-- Update pet behavior (spawned in separate task to avoid blocking)
			task.spawn(function()
				UpdatePetBehavior(player)
			end)
		end
		
		if lastArenaCheck >= ARENA_CHECK_INTERVAL then
			lastArenaCheck = 0
		end
	end)
	
	Log("Pet behavior loop started")
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
	
	-- Initialize arena status
	PlayerArenaStatus[userId] = false
	
	-- Get player's pet inventory from data store
	local inventory = DataService:Get(player, "Inventory")
	if inventory and inventory.PetInventory then
		-- Assign IDs to existing pets
		for index, petData in ipairs(inventory.PetInventory) do
			local petID = GeneratePetID()
			PlayerPetIDs[userId].petIndexToID[index] = petID
			PlayerPetIDs[userId].idToPetIndex[petID] = index
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
	print("request pet equip")
	
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
	
	-- Equip the pet (save to data)
	DataService:Update(player, "Inventory", function(inv)
		if not inv.EquippedPets then
			inv.EquippedPets = {}
		end
		table.insert(inv.EquippedPets, petIndex)
		return inv
	end)
	
	local petData = inventory.PetInventory[petIndex]
	Log(string.format("Player %s equipped %s", player.Name, petData.Name))
	
	-- Spawn the pet model
	SpawnPetModel(player, petIndex, petData)
	
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
	
	-- Despawn the pet model
	DespawnPetModel(player, petIndex)
	
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
				PetType = petData.PetType,
				Multiplier = petData.Multiplier,
				FuelBonus = petData.FuelBonus or 1.0,
				PickupRangeBonus = petData.PickupRangeBonus or 1.0,
				RoamRange = petData.RoamRange or 30,
				StarCollectionRadius = petData.StarCollectionRadius or 5,
				World = petData.World or "Main",
				Level = petData.Level or 1,
				TierLevel = petData.TierLevel or petData.Level or 1,
				TierName = petData.TierName or "Common",
				Rarity = petData.Rarity or "Standard",
				Equipped = equippedSet[index] == true,
			})
		end
	end
	
	return pets
end

-- Merge two pets to create a higher tier pet
-- Requires Gems based on the pet's current tier (from PetMergeStats config)
-- Both pets must be from the same world
-- Uses formula: NewStats = OldStats × (2 + RarityBonus)
function PetService:MergePets(player: Player, petID1: string, petID2: string): (boolean, string?, { Name: string, ID: string, Level: number }?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Get pet indices from IDs
	local petIndex1 = self:GetPetIndexByID(player, petID1)
	local petIndex2 = self:GetPetIndexByID(player, petID2)
	
	if not petIndex1 or not petIndex2 then
		NotificationService:SendNotification(
			player,
			"Invalid pet ID.",
			NotificationService.Category.Error
		)
		return false, "Invalid pet ID", nil
	end
	
	if petIndex1 == petIndex2 then
		NotificationService:SendNotification(
			player,
			"Cannot merge a pet with itself.",
			NotificationService.Category.Error
		)
		return false, "Cannot merge pet with itself", nil
	end
	
	-- Get player inventory
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory then
		NotificationService:SendNotification(
			player,
			"Inventory not found.",
			NotificationService.Category.Error
		)
		return false, "Inventory not found", nil
	end
	
	local pet1 = inventory.PetInventory[petIndex1]
	local pet2 = inventory.PetInventory[petIndex2]
	
	if not pet1 or not pet2 then
		NotificationService:SendNotification(
			player,
			"Pet not found in inventory.",
			NotificationService.Category.Error
		)
		return false, "Pet not found", nil
	end
	
	-- Check if pets are from the same world (required for merging)
	local world1 = pet1.World or "Main"
	local world2 = pet2.World or "Main"
	
	if PetMergeStats.WorldRestrictions.RequireSameWorld and world1 ~= world2 then
		NotificationService:SendNotification(
			player,
			"Pets must be from the same world to merge.",
			NotificationService.Category.Warning
		)
		return false, "Different worlds", nil
	end
	
	-- Get current tier level and check if at max
	local currentTierLevel = pet1.TierLevel or pet1.Level or 1
	
	if PetMergeStats.IsMaxTier(currentTierLevel) then
		NotificationService:SendNotification(
			player,
			"Pet is already at maximum tier.",
			NotificationService.Category.Warning
		)
		return false, "Max tier reached", nil
	end
	
	-- Get merge cost from PetMergeStats config
	local mergeCost = PetMergeStats.GetMergeCost(currentTierLevel)
	local currencies = DataService:Get(player, "Currencies")
	
	if not currencies or (currencies.Gems or 0) < mergeCost then
		NotificationService:SendNotification(
			player,
			string.format("Not enough Gems. Need %d Gems.", mergeCost),
			NotificationService.Category.Warning
		)
		return false, "Not enough Gems", nil
	end
	
	-- Check if either pet is equipped
	local equippedPets = inventory.EquippedPets or {}
	local pet1Equipped = false
	local pet2Equipped = false
	
	for _, equippedIndex in ipairs(equippedPets) do
		if equippedIndex == petIndex1 then pet1Equipped = true end
		if equippedIndex == petIndex2 then pet2Equipped = true end
	end
	
	-- Deduct Gems
	DataService:Update(player, "Currencies", function(curr)
		curr.Gems = (curr.Gems or 0) - mergeCost
		return curr
	end)
	
	-- Calculate new stats using PetMergeStats formula: NewStats = OldStats × (2 + RarityBonus)
	local newTierLevel = currentTierLevel + 1
	local oldStats = {
		Multiplier = pet1.Multiplier or 1.0,
		FuelBonus = pet1.FuelBonus or 1.0,
		PickupRangeBonus = pet1.PickupRangeBonus or 1.0,
		RoamRange = pet1.RoamRange or 30,
		StarCollectionRadius = pet1.StarCollectionRadius or 5,
	}
	local newStats = PetMergeStats.CalculateMergedStats(oldStats, currentTierLevel)
	local newTier = PetMergeStats.GetTierByLevel(newTierLevel)
	
	-- Despawn pet2 if equipped before removing from inventory
	if pet2Equipped then
		DespawnPetModel(player, petIndex2)
	end
	
	-- Update inventory: upgrade pet1 and remove pet2
	DataService:Update(player, "Inventory", function(inv)
		-- Upgrade pet1 with new tier and stats
		inv.PetInventory[petIndex1].Level = newTierLevel
		inv.PetInventory[petIndex1].TierLevel = newTierLevel
		inv.PetInventory[petIndex1].TierName = newTier.Name
		inv.PetInventory[petIndex1].Multiplier = newStats.Multiplier
		inv.PetInventory[petIndex1].FuelBonus = newStats.FuelBonus
		inv.PetInventory[petIndex1].PickupRangeBonus = newStats.PickupRangeBonus
		inv.PetInventory[petIndex1].RoamRange = newStats.RoamRange
		inv.PetInventory[petIndex1].StarCollectionRadius = newStats.StarCollectionRadius
		
		-- Remove pet2 from inventory
		table.remove(inv.PetInventory, petIndex2)
		
		-- Update equipped pets indices (since pet2 was removed)
		if inv.EquippedPets then
			local newEquipped = {}
			for _, equippedIndex in ipairs(inv.EquippedPets) do
				if equippedIndex ~= petIndex2 then
					-- Adjust index if it was after the removed pet
					if equippedIndex > petIndex2 then
						table.insert(newEquipped, equippedIndex - 1)
					else
						table.insert(newEquipped, equippedIndex)
					end
				end
			end
			inv.EquippedPets = newEquipped
		end
		
		return inv
	end)
	
	-- Update pet ID mappings (pet2 was removed, indices shifted)
	local userId = player.UserId
	if PlayerPetIDs[userId] then
		-- Regenerate ID mappings
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
	
	-- Get the new ID for the merged pet
	local newPetID = self:GetPetIDByIndex(player, petIndex1 > petIndex2 and petIndex1 - 1 or petIndex1)
	
	Log(string.format("Player %s merged pets to create %s tier %s (Level %d)", player.Name, newTier.Name, pet1.Name, newTierLevel))
	
	NotificationService:SendNotification(
		player,
		string.format("Merged! %s is now %s tier!", pet1.Name, newTier.Name),
		NotificationService.Category.Success
	)
	
	return true, nil, {
		Name = pet1.Name,
		ID = newPetID or petID1,
		Level = newTierLevel,
		TierLevel = newTierLevel,
		TierName = newTier.Name,
		Multiplier = newStats.Multiplier,
		FuelBonus = newStats.FuelBonus,
		PickupRangeBonus = newStats.PickupRangeBonus,
		RoamRange = newStats.RoamRange,
		StarCollectionRadius = newStats.StarCollectionRadius,
	}
end

-- Validate and process pet star collection from client
-- Validates that the star collection is within the allowed range from the player
-- Uses the maximum RoamRange and StarCollectionRadius from the player's equipped pets
function PetService:PetCollectStar(player: Player, starId: string, petPosition: Vector3): (boolean, string?)
	local character = player.Character
	if not character then
		return false, "No character"
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart"
	end
	
	-- Check if player is in arena (pets can only collect stars in arena)
	if not self:IsPlayerInArena(player) then
		return false, "Not in arena"
	end
	
	-- Get the maximum RoamRange and StarCollectionRadius from equipped pets
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	local maxRoamRange = 30 -- Default fallback
	local maxStarCollectionRadius = 5 -- Default fallback
	
	if inventory and inventory.PetInventory and inventory.EquippedPets then
		for _, petIndex in ipairs(inventory.EquippedPets) do
			local petData = inventory.PetInventory[petIndex]
			if petData then
				local roamRange = petData.RoamRange or 30
				local collectionRadius = petData.StarCollectionRadius or 5
				if roamRange > maxRoamRange then
					maxRoamRange = roamRange
				end
				if collectionRadius > maxStarCollectionRadius then
					maxStarCollectionRadius = collectionRadius
				end
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
	local fuelValue = StarService:CollectStarServer(player, starId)
	
	if not fuelValue then
		return false, "Collection failed"
	end
	
	-- Add fuel to player
	DataService:Update(player, "Stats", function(stats)
		stats.Fuel = stats.Fuel + fuelValue
		return stats
	end)
	
	Log(string.format("Pet collected star for player %s, gained %d fuel (client-requested)", player.Name, fuelValue))
	
	-- Notify client that star was collected
	self.Client.PetStarCollected:Fire(player, {
		StarId = starId,
		FuelValue = fuelValue,
	})
	
	return true, nil
end

-- Client request to equip a pet
function PetService.Client:RequestEquipPet(player: Player, petID: string): (boolean, string?)
	print("Here")
	return PetService:EquipPet(player, petID)
end

-- Client request to unequip a pet
function PetService.Client:RequestUnequipPet(player: Player, petID: string): (boolean, string?)
	return PetService:UnequipPet(player, petID)
end

-- Client request to merge two pets
function PetService.Client:RequestMergePets(player: Player, petID1: string, petID2: string)
	return PetService:MergePets(player, petID1, petID2)
end

-- Client request to get all pets
function PetService.Client:GetPets(player: Player)
	return PetService:GetPlayerPets(player)
end

-- Client request to check if player is in arena
function PetService.Client:GetArenaStatus(player: Player): boolean
	return PetService:IsPlayerInArena(player)
end

-- Client request for pet to collect a star (with range validation)
-- This validates that the star is within the pet's roam range from the player
function PetService.Client:RequestPetCollectStar(player: Player, starId: string, petPosition: Vector3): (boolean, string?)
	return PetService:PetCollectStar(player, starId, petPosition)
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	local userId = player.UserId
	
	-- Despawn all pets
	DespawnAllPets(player)
	
	-- Clean up data
	PlayerPetIDs[userId] = nil
	SpawnedPets[userId] = nil
	PlayerArenaStatus[userId] = nil
	
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
	
	Log("PetService initialized")
end

function PetService:KnitStart()
	-- Start the pet behavior loop
	StartPetBehaviorLoop()
	Log("PetService started")
end

return PetService
