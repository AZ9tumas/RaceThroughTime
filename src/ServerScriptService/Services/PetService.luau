--[[
	PetService
	Handles pet inventory, equipping, spawning, and behavior.
	Pets are obtained directly from egg purchases and stored in player's inventory.
	Maximum 3 pets can be equipped at once.
	Equipped pets follow the player and collect stars when in the arena.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

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
local PET_STAR_COLLECTION_RADIUS = 5 -- Distance from star to collect it
local ARENA_CHECK_INTERVAL = 0.1 -- How often to check arena status (seconds)
local PET_UPDATE_INTERVAL = 0.2 -- How often to update pet behavior (seconds)
local PetsCollisionGroupCreated = false -- Track if collision group was created

-- Helper function for logging
local function Log(message: string)
	print(string.format("[PetService]: %s", message))
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
	
	-- Log state changes for debugging
	if wasInArena ~= isInArena then
		if isInArena then
			Log(string.format("Player %s entered arena", player.Name))
		else
			Log(string.format("Player %s left arena", player.Name))
		end
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
	
	-- Create a BodyPosition to make the pet float/follow
	local primaryPart = petModel.PrimaryPart
	if primaryPart then
		local bodyPosition = Instance.new("BodyPosition")
		bodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bodyPosition.D = 1000
		bodyPosition.P = 10000
		bodyPosition.Parent = primaryPart
		
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

-- Get all currently targeted star IDs for a player's pets
local function GetTargetedStarIDs(userId: number): { [string]: boolean }
	local targeted = {}
	
	if not SpawnedPets[userId] then return targeted end
	
	for _, petInfo in pairs(SpawnedPets[userId]) do
		if petInfo.TargetStarID then
			targeted[petInfo.TargetStarID] = true
		end
	end
	
	return targeted
end

-- Find nearest available star for a pet to collect
local function FindNearestAvailableStar(player: Player, petPosition: Vector3): ({ Position: Vector3, ID: string, StarName: string, FuelValue: number }?, number?)
	local StarService = Knit.GetService("StarService")
	local starInfo = StarService:GetStarInformation(player)
	
	if not starInfo or #starInfo == 0 then
		return nil, nil
	end
	
	local targetedStars = GetTargetedStarIDs(player.UserId)
	local nearestStar = nil
	local nearestDistance = math.huge
	local nearestIndex = nil
	
	for index, star in ipairs(starInfo) do
		-- Skip if already targeted by another pet
		if not targetedStars[star.ID] then
			local distance = (petPosition - star.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestStar = star
				nearestIndex = index
			end
		end
	end
	
	return nearestStar, nearestIndex
end

-- Collect a star via pet (server-side collection)
local function CollectStarViaPet(player: Player, starId: string): boolean
	local StarService = Knit.GetService("StarService")
	
	-- Use StarService's server-side collection method
	local fuelValue = StarService:CollectStarServer(player, starId)
	
	if not fuelValue then
		return false
	end
	
	-- Add fuel to player
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Stats", function(stats)
		stats.Fuel = stats.Fuel + fuelValue
		return stats
	end)
	
	Log(string.format("Pet collected star for player %s, gained %d fuel", player.Name, fuelValue))
	
	return true
end

-- Update pet behavior for a single player
local function UpdatePetBehavior(player: Player)
	local userId = player.UserId
	local character = player.Character
	
	if not character or not SpawnedPets[userId] then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local isInArena = PlayerArenaStatus[userId] or false
	local petIndex = 0
	
	for index, petInfo in pairs(SpawnedPets[userId]) do
		petIndex = petIndex + 1
		local petModel = petInfo.Model
		if not petModel or not petModel.PrimaryPart then continue end
		
		local primaryPart = petModel.PrimaryPart
		local bodyPosition = primaryPart:FindFirstChild("BodyPosition")
		if not bodyPosition then continue end
		
		local petPosition = primaryPart.Position
		
		if isInArena then
			-- In arena: try to collect stars
			if petInfo.TargetStarID then
				-- Check if target star still exists
				local StarService = Knit.GetService("StarService")
				local starInfoList = StarService:GetStarInformation(player)
				local targetFound = false
				local targetStar = nil
				
				if starInfoList then
					for _, star in ipairs(starInfoList) do
						if star.ID == petInfo.TargetStarID then
							targetFound = true
							targetStar = star
							break
						end
					end
				end
				
				if targetFound and targetStar then
					-- Move towards target star
					bodyPosition.Position = targetStar.Position
					
					-- Check if close enough to collect
					local distance = (petPosition - targetStar.Position).Magnitude
					if distance < PET_STAR_COLLECTION_RADIUS then
						-- Collect the star
						if CollectStarViaPet(player, petInfo.TargetStarID) then
							petInfo.TargetStarID = nil
						end
					end
				else
					-- Target star no longer exists, clear target
					petInfo.TargetStarID = nil
				end
			else
				-- Find a new star to target
				local nearestStar, _ = FindNearestAvailableStar(player, petPosition)
				if nearestStar then
					petInfo.TargetStarID = nearestStar.ID
				else
					-- No stars available, follow player
					local offset = Vector3.new(
						math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
						2,
						math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
					)
					bodyPosition.Position = rootPart.Position + offset
				end
			end
		else
			-- Not in arena: follow the player
			petInfo.TargetStarID = nil -- Clear any star targets
			
			local offset = Vector3.new(
				math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
				2,
				math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
			)
			bodyPosition.Position = rootPart.Position + offset
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
				World = petData.World or "Main",
				Level = petData.Level or 1,
				Rarity = petData.Rarity or "Standard",
				Equipped = equippedSet[index] == true,
			})
		end
	end
	
	return pets
end

-- Merge two pets of the same type and world to create a higher level pet
-- Requires Gems based on the pet's current level
-- Both pets must be from the same world and at least one must be the same PetType
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
	
	if world1 ~= world2 then
		NotificationService:SendNotification(
			player,
			"Pets must be from the same world to merge.",
			NotificationService.Category.Warning
		)
		return false, "Different worlds", nil
	end
	
	-- Check if pet is already at max level
	local currentLevel = pet1.Level or 1
	local petConfig = Stats.Pets[pet1.PetType] or Stats.Pets.StandardPet
	local maxLevel = petConfig.MaxLevel or 10
	
	if currentLevel >= maxLevel then
		NotificationService:SendNotification(
			player,
			"Pet is already at maximum level.",
			NotificationService.Category.Warning
		)
		return false, "Max level reached", nil
	end
	
	-- Check if player has enough Gems
	local mergeCost = Stats.MergeCost[currentLevel] or 10
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
	
	-- Calculate new stats
	local newLevel = currentLevel + 1
	local newMultiplier = (pet1.Multiplier or 1.1) + Stats.MergeBonus.MultiplierPerLevel
	local newFuelBonus = (pet1.FuelBonus or 1.1) + Stats.MergeBonus.FuelBonusPerLevel
	local newPickupRangeBonus = (pet1.PickupRangeBonus or 1.0) + Stats.MergeBonus.PickupRangeBonusPerLevel
	
	-- Despawn pet2 if equipped before removing from inventory
	if pet2Equipped then
		DespawnPetModel(player, petIndex2)
	end
	
	-- Update inventory: upgrade pet1 and remove pet2
	DataService:Update(player, "Inventory", function(inv)
		-- Upgrade pet1
		inv.PetInventory[petIndex1].Level = newLevel
		inv.PetInventory[petIndex1].Multiplier = newMultiplier
		inv.PetInventory[petIndex1].FuelBonus = newFuelBonus
		inv.PetInventory[petIndex1].PickupRangeBonus = newPickupRangeBonus
		
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
	
	Log(string.format("Player %s merged pets to create Level %d %s", player.Name, newLevel, pet1.Name))
	
	NotificationService:SendNotification(
		player,
		string.format("Merged! %s is now Level %d!", pet1.Name, newLevel),
		NotificationService.Category.Success
	)
	
	return true, nil, {
		Name = pet1.Name,
		ID = newPetID or petID1,
		Level = newLevel,
		Multiplier = newMultiplier,
		FuelBonus = newFuelBonus,
		PickupRangeBonus = newPickupRangeBonus,
	}
end

-- Client request to equip a pet
function PetService.Client:RequestEquipPet(player: Player, petID: string): (boolean, string?)
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
