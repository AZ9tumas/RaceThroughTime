--[[
	PetController
	Handles client-side pet behavior for star collection in the arena.
	
	When the player is in the arena:
	- Pets roam around the player within their range
	- Pets target and collect nearby stars
	- Collection requests are validated on the server
	
	When the player is outside the arena:
	- Pets follow the player (handled by server)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local PetController = Knit.CreateController({
	Name = "PetController",
})

-- Private state
local Player = Players.LocalPlayer
local IsInArena = false
local PetService = nil
local StarService = nil
local EquippedPetStats = {} -- Cache of equipped pet stats: { RoamRange, StarCollectionRadius }

-- Arena checking state
local lastArenaCheckTime = 0
local ARENA_CHECK_INTERVAL = 0.1 -- Check arena status every 0.1 seconds for performance

-- Pet behavior state
local PetTargets = {} -- [petModel] = { TargetStarID = string?, TargetPosition = Vector3? }
local SpawnedStars = {} -- Cache of spawned star references from workspace

-- Constants
local PET_UPDATE_INTERVAL = 0.1 -- Client updates pet behavior faster for smoother movement
local PET_FOLLOW_DISTANCE = 8

-- Pet behavior loop connection
local PetBehaviorConnection = nil

-- Helper function for logging
local function Log(message: string)
	-- Uncomment for debugging
	-- print(string.format("[PetController]: %s", message))
end

-- Get the current world name by checking which world folder the player is in
local function GetCurrentWorld(): string
	local character = Player.Character
	if not character then return "Main" end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return "Main" end
	
	-- Check which world the player is in based on proximity to world spawn/arena
	-- For simplicity, check if Main or StoneAge arena is closest
	local mainWorld = Workspace:FindFirstChild("Main")
	local stoneAgeWorld = Workspace:FindFirstChild("StoneAge")
	
	if mainWorld and stoneAgeWorld then
		local mainArena = mainWorld:FindFirstChild("1_Central_Arena")
		local stoneAgeArena = stoneAgeWorld:FindFirstChild("1_Central_Arena")
		
		if mainArena and stoneAgeArena then
			local playerPos = rootPart.Position
			local distToMain = (playerPos - mainArena.Position).Magnitude
			local distToStoneAge = (playerPos - stoneAgeArena.Position).Magnitude
			
			if distToStoneAge < distToMain then
				return "StoneAge"
			end
		end
	end
	
	return "Main"
end

-- Get the Central Arena part for the current world
local function GetCentralArenaForCurrentWorld(): BasePart?
	local currentWorld = GetCurrentWorld()
	local worldFolder = Workspace:FindFirstChild(currentWorld)
	if worldFolder then
		local centralArena = worldFolder:FindFirstChild("1_Central_Arena")
		if centralArena and centralArena:IsA("BasePart") then
			return centralArena
		end
	end
	
	-- Fallback to Main world
	local mainWorld = Workspace:FindFirstChild("Main")
	if mainWorld then
		local centralArena = mainWorld:FindFirstChild("1_Central_Arena")
		if centralArena and centralArena:IsA("BasePart") then
			return centralArena
		end
	end
	
	return nil
end

-- Check if player is inside the arena based on distance from center
local function CheckPlayerInArena(): boolean
	local character = Player.Character
	if not character then return false end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	
	local centralArena = GetCentralArenaForCurrentWorld()
	if not centralArena then return false end
	
	local currentWorld = GetCurrentWorld()
	local arenaRadius = Stats.ArenaRadius[currentWorld] or Stats.ArenaRadius.Main or 200
	
	-- Calculate horizontal distance (ignoring Y axis) from arena center to player
	local arenaCenter = centralArena.Position
	local playerPos = rootPart.Position
	local horizontalDistance = math.sqrt(
		(playerPos.X - arenaCenter.X)^2 + 
		(playerPos.Z - arenaCenter.Z)^2
	)
	
	return horizontalDistance <= arenaRadius
end

-- Update arena status with throttling for performance
local function UpdateArenaStatus()
	local currentTime = tick()
	if currentTime - lastArenaCheckTime < ARENA_CHECK_INTERVAL then
		return -- Use cached value if not enough time has passed
	end
	lastArenaCheckTime = currentTime
	
	local wasInArena = IsInArena
	IsInArena = CheckPlayerInArena()
	
	-- Log state change for debugging
	if wasInArena ~= IsInArena then
		if IsInArena then
			Log("Player entered arena - pets will now collect stars")
			-- Clear all pet targets when entering arena to re-evaluate
			for _, petData in pairs(PetTargets) do
				petData.TargetStarID = nil
				petData.TargetPosition = nil
			end
		else
			Log("Player left arena - pets will follow player")
			-- Clear all pet targets when leaving arena
			for _, petData in pairs(PetTargets) do
				petData.TargetStarID = nil
				petData.TargetPosition = nil
			end
		end
	end
end

-- Public function to check if player is in arena
function PetController:IsPlayerInArena(): boolean
	return IsInArena
end

-- Get the maximum RoamRange and StarCollectionRadius from equipped pets
local function GetMaxPetStats(): (number, number)
	local maxRoamRange = 30 -- Default fallback
	local maxStarCollectionRadius = 5 -- Default fallback
	
	for _, stats in pairs(EquippedPetStats) do
		if stats.RoamRange and stats.RoamRange > maxRoamRange then
			maxRoamRange = stats.RoamRange
		end
		if stats.StarCollectionRadius and stats.StarCollectionRadius > maxStarCollectionRadius then
			maxStarCollectionRadius = stats.StarCollectionRadius
		end
	end
	
	return maxRoamRange, maxStarCollectionRadius
end

-- Refresh equipped pet stats from server
local function RefreshEquippedPetStats()
	if not PetService then return end
	
	local pets = PetService:GetPets()
	EquippedPetStats = {}
	
	for _, pet in ipairs(pets) do
		if pet.Equipped then
			EquippedPetStats[pet.ID] = {
				RoamRange = pet.RoamRange or 30,
				StarCollectionRadius = pet.StarCollectionRadius or 5,
			}
		end
	end
	
	local maxRoam, maxCollection = GetMaxPetStats()
	Log(string.format("Refreshed pet stats: MaxRoamRange=%.2f, MaxStarCollectionRadius=%.2f", maxRoam, maxCollection))
end

-- Get the player's character root part
local function GetPlayerRootPart(): BasePart?
	local character = Player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

-- Get all spawned pet models for the player from workspace
local function GetSpawnedPetModels(): { Model }
	local pets = {}
	
	-- Look for pet models in workspace that belong to this player
	-- Pets are spawned by the server with BodyPosition constraints
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.PrimaryPart then
			local bodyPosition = child.PrimaryPart:FindFirstChild("BodyPosition")
			if bodyPosition and bodyPosition:IsA("BodyPosition") then
				-- This is likely a pet model
				table.insert(pets, child)
			end
		end
	end
	
	return pets
end

-- Get spawned stars from the Stars folder in workspace
local function GetSpawnedStarsFolder(): Folder?
	return Workspace:FindFirstChild("Stars")
end

-- Find the nearest available star for a pet to target
local function FindNearestAvailableStar(petPosition: Vector3, playerPosition: Vector3): (BasePart?, { Position: Vector3, ID: string }?)
	local starsFolder = GetSpawnedStarsFolder()
	if not starsFolder then return nil, nil end
	
	local nearestStar = nil
	local nearestStarInfo = nil
	local nearestDistance = math.huge
	
	-- Get the maximum roam range from equipped pets
	local maxRoamRange, _ = GetMaxPetStats()
	
	-- Get already targeted stars
	local targetedStars = {}
	for _, petData in pairs(PetTargets) do
		if petData.TargetStarID then
			targetedStars[petData.TargetStarID] = true
		end
	end
	
	for _, star in ipairs(starsFolder:GetChildren()) do
		local starPart = nil
		if star:IsA("BasePart") then
			starPart = star
		elseif star:IsA("Model") then
			starPart = star.PrimaryPart or star:FindFirstChildWhichIsA("BasePart")
		end
		
		if starPart then
			local starId = star.Name
			
			-- Skip if already targeted by another pet
			if targetedStars[starId] then
				continue
			end
			
			local starPosition = starPart.Position
			
			-- Check if star is within roam range from player
			local distanceFromPlayer = (starPosition - playerPosition).Magnitude
			if distanceFromPlayer > maxRoamRange then
				continue
			end
			
			-- Find nearest star to this pet
			local distanceFromPet = (starPosition - petPosition).Magnitude
			if distanceFromPet < nearestDistance then
				nearestDistance = distanceFromPet
				nearestStar = starPart
				nearestStarInfo = {
					Position = starPosition,
					ID = starId,
				}
			end
		end
	end
	
	return nearestStar, nearestStarInfo
end

-- Request server to collect a star via pet
local function RequestPetCollectStar(starId: string, petPosition: Vector3): boolean
	if not PetService then return false end
	
	local success, errorMsg = PetService:RequestPetCollectStar(starId, petPosition)
	
	if success then
		Log(string.format("Pet collected star: %s", starId))
	else
		Log(string.format("Pet failed to collect star: %s - %s", starId, errorMsg or "unknown"))
	end
	
	return success
end

-- Check if a pet is close enough to collect a star
local function IsPetCloseToStar(petPosition: Vector3, starPosition: Vector3): boolean
	local _, maxStarCollectionRadius = GetMaxPetStats()
	local distance = (petPosition - starPosition).Magnitude
	return distance <= maxStarCollectionRadius
end

-- Update behavior for a single pet
local function UpdateSinglePetBehavior(petModel: Model, petIndex: number, playerPosition: Vector3)
	if not petModel or not petModel.PrimaryPart then return end
	
	local primaryPart = petModel.PrimaryPart
	local bodyPosition = primaryPart:FindFirstChild("BodyPosition")
	if not bodyPosition then return end
	
	local petPosition = primaryPart.Position
	
	-- Initialize pet target data if needed
	if not PetTargets[petModel] then
		PetTargets[petModel] = {
			TargetStarID = nil,
			TargetPosition = nil,
		}
	end
	
	local petData = PetTargets[petModel]
	
	if IsInArena then
		-- In arena: try to collect stars
		if petData.TargetStarID then
			-- Check if target star still exists
			local starsFolder = GetSpawnedStarsFolder()
			local targetStar = starsFolder and starsFolder:FindFirstChild(petData.TargetStarID)
			
			if targetStar then
				local starPart = targetStar:IsA("BasePart") and targetStar or (targetStar:IsA("Model") and (targetStar.PrimaryPart or targetStar:FindFirstChildWhichIsA("BasePart")))
				
				if starPart then
					local starPosition = starPart.Position
					
					-- Move towards target star
					bodyPosition.Position = starPosition
					
					-- Check if close enough to collect
					if IsPetCloseToStar(petPosition, starPosition) then
						-- Try to collect the star
						local success = RequestPetCollectStar(petData.TargetStarID, petPosition)
						if success then
							petData.TargetStarID = nil
							petData.TargetPosition = nil
						end
					end
				else
					-- Star part not found, clear target
					petData.TargetStarID = nil
					petData.TargetPosition = nil
				end
			else
				-- Target star no longer exists, clear target
				petData.TargetStarID = nil
				petData.TargetPosition = nil
			end
		else
			-- Find a new star to target
			local _, nearestStarInfo = FindNearestAvailableStar(petPosition, playerPosition)
			
			if nearestStarInfo then
				petData.TargetStarID = nearestStarInfo.ID
				petData.TargetPosition = nearestStarInfo.Position
				Log(string.format("Pet targeting star: %s", nearestStarInfo.ID))
			else
				-- No stars available, roam around player
				local offset = Vector3.new(
					math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
					2,
					math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
				)
				bodyPosition.Position = playerPosition + offset
			end
		end
	else
		-- Not in arena: clear targets and let server handle following
		petData.TargetStarID = nil
		petData.TargetPosition = nil
		-- Server handles pet following when not in arena
	end
end

-- Main pet behavior update loop (client-side)
local function UpdatePetBehavior()
	-- Update arena status first
	UpdateArenaStatus()
	
	local rootPart = GetPlayerRootPart()
	if not rootPart then return end
	
	local playerPosition = rootPart.Position
	local petModels = GetSpawnedPetModels()
	
	for index, petModel in ipairs(petModels) do
		task.spawn(function()
			UpdateSinglePetBehavior(petModel, index, playerPosition)
		end)
	end
end

-- Start the pet behavior loop
local function StartPetBehaviorLoop()
	if PetBehaviorConnection then return end
	
	local lastUpdate = 0
	
	PetBehaviorConnection = RunService.Heartbeat:Connect(function(deltaTime)
		lastUpdate = lastUpdate + deltaTime
		
		if lastUpdate < PET_UPDATE_INTERVAL then
			return
		end
		lastUpdate = 0
		
		UpdatePetBehavior()
	end)
	
	Log("Pet behavior loop started")
end

-- Stop the pet behavior loop
local function StopPetBehaviorLoop()
	if PetBehaviorConnection then
		PetBehaviorConnection:Disconnect()
		PetBehaviorConnection = nil
		Log("Pet behavior loop stopped")
	end
end

-- Handle pet equipped signal
local function OnPetEquipped(petInfo: { ID: string, Name: string })
	Log(string.format("Pet equipped: %s", petInfo.Name))
	-- Refresh pet stats when a pet is equipped
	RefreshEquippedPetStats()
end

-- Handle pet unequipped signal
local function OnPetUnequipped(petInfo: { ID: string })
	Log(string.format("Pet unequipped: %s", petInfo.ID))
	
	-- Remove from cached stats
	EquippedPetStats[petInfo.ID] = nil
	
	-- Clean up pet target data for unequipped pets
	for petModel, _ in pairs(PetTargets) do
		if not petModel or not petModel.Parent then
			PetTargets[petModel] = nil
		end
	end
end

-- Handle pet star collected notification
local function OnPetStarCollected(collectionInfo: { StarId: string, FuelValue: number })
	Log(string.format("Pet collected star %s for %d fuel", collectionInfo.StarId, collectionInfo.FuelValue))
end

-- Knit lifecycle
function PetController:KnitInit()
	Log("PetController initializing")
end

function PetController:KnitStart()
	-- Get service references
	PetService = Knit.GetService("PetService")
	StarService = Knit.GetService("StarService")
	
	-- Initialize equipped pet stats from server
	RefreshEquippedPetStats()
	
	-- Arena status starts as false and will be updated in the behavior loop
	-- This avoids race conditions during initialization
	IsInArena = false
	
	-- Listen for signals from server (pet equip/unequip and star collection)
	PetService.PetEquipped:Connect(OnPetEquipped)
	PetService.PetUnequipped:Connect(OnPetUnequipped)
	PetService.PetStarCollected:Connect(OnPetStarCollected)
	
	-- Start the pet behavior loop (handles arena detection and pet behavior)
	StartPetBehaviorLoop()
	
	Log("PetController started")
end

return PetController
