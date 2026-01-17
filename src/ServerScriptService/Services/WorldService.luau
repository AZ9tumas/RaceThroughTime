--[[
	WorldService
	Handles world switching and player teleportation between worlds.
	Uses Knit framework for client-server communication.
	
	USAGE EXAMPLES:
	
	-- From another server service:
	local WorldService = Knit.GetService("WorldService")
	
	-- Teleport player to a specific world
	WorldService:TeleportPlayerToWorld(player, "StoneAge")
	
	-- Give/unlock a world for a player (without teleporting)
	WorldService:GiveWorldToPlayer(player, "StoneAge")
	
	-- Check if player has access to a world
	local hasAccess = WorldService:PlayerHasWorld(player, "StoneAge")
	
	-- From client:
	local WorldService = Knit.GetService("WorldService")
	WorldService:RequestTeleportToWorld("StoneAge")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local WorldService = Knit.CreateService({
	Name = "WorldService",
	Client = {
		WorldChanged = Knit.CreateSignal(), -- Signal to notify client when world changes
		DataUpdated = Knit.CreateSignal(), -- Signal to send updated data after world change
	},
})

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[WorldService]: %s", message))
end

-- Get the world folder from workspace
local function GetWorldFolder(worldName: string): Folder?
	return Workspace:FindFirstChild(worldName)
end

-- Get the SpawnLocation for a world
local function GetSpawnLocationForWorld(worldName: string): SpawnLocation?
	local worldFolder = GetWorldFolder(worldName)
	if worldFolder then
		return worldFolder:FindFirstChild("SpawnLocation")
	end
	return nil
end

--[[
	Check if a player has unlocked/owns a specific world.
	
	@param player Player - The player to check
	@param worldName string - The world name to check
	@return boolean - True if player has access to the world
]]
function WorldService:PlayerHasWorld(player: Player, worldName: string): boolean
	local DataService = Knit.GetService("DataService")
	local progression = DataService:Get(player, "Progression")
	
	if not progression then
		return worldName == "Main" -- Main is always available
	end
	
	local unlockedWorlds = progression.UnlockedWorlds or { "Main" }
	
	for _, world in ipairs(unlockedWorlds) do
		if world == worldName then
			return true
		end
	end
	
	return false
end

--[[
	Give/unlock a world for a player without teleporting them.
	
	@param player Player - The player to give the world to
	@param worldName string - The world name to unlock
	@return boolean - True if world was successfully unlocked
]]
function WorldService:GiveWorldToPlayer(player: Player, worldName: string): boolean
	if not player or not player:IsDescendantOf(Players) then
		warn("[WorldService]: Invalid player provided")
		return false
	end
	
	-- Check if world exists
	local worldFolder = GetWorldFolder(worldName)
	if not worldFolder then
		warn(string.format("[WorldService]: World '%s' does not exist in Workspace", worldName))
		return false
	end
	
	-- Check if player already has this world
	if self:PlayerHasWorld(player, worldName) then
		Log(string.format("Player %s already has world %s", player.Name, worldName))
		return true
	end
	
	-- Add world to player's unlocked worlds
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Progression", function(progression)
		progression.UnlockedWorlds = progression.UnlockedWorlds or { "Main" }
		table.insert(progression.UnlockedWorlds, worldName)
		return progression
	end)

	player:SetAttribute("CurrentWorld", worldName)
	
	Log(string.format("Unlocked world '%s' for player %s", worldName, player.Name))
	
	return true
end

--[[
	Teleport a player to a specific world.
	Shows loading screen during teleport, despawns/respawns pets and stars.
	
	@param player Player - The player to teleport
	@param worldName string - The world name to teleport to
	@return boolean, string?, table? - Success status, optional error message, updated data
]]
function WorldService:TeleportPlayerToWorld(player: Player, worldName: string): (boolean, string?, any?)
	if not player or not player:IsDescendantOf(Players) then
		warn("[WorldService]: Invalid player provided")
		return false, "Invalid player", nil
	end
	
	-- 1. Check if player owns/has unlocked the world
	if not self:PlayerHasWorld(player, worldName) then
		return false, "World not unlocked", nil
	end
	
	-- Get the world folder
	local worldFolder = GetWorldFolder(worldName)
	if not worldFolder then
		return false, "World does not exist", nil
	end
	
	-- Get spawn location for the world
	local spawnLocation = GetSpawnLocationForWorld(worldName)
	if not spawnLocation then
		return false, "No spawn location in world", nil
	end
	
	-- Get player's character
	local character = player.Character
	if not character then
		return false, "No character", nil
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart", nil
	end
	
	-- 2. Show loading screen (white frame)
	local LoadingScreenService = Knit.GetService("LoadingScreenService")
	LoadingScreenService:ShowLoadingScreen(player, 2) -- Show for 2 seconds (long enough for operations)
	
	-- Wait a moment for loading screen to fade in
	task.wait(0.3)
	
	-- 3. Update the data stores, set current world
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Progression", function(progression)
		progression.CurrentWorld = worldName
		return progression
	end)
	
	-- 4. Update player attribute CurrentWorld (for world params initialization)
	player:SetAttribute("CurrentWorld", worldName)
	
	-- 5. Despawn pets
	local PetService = Knit.GetService("PetService")
	PetService:DespawnAllPetsForPlayer(player)
	
	-- 6. Despawn stars
	local StarService = Knit.GetService("StarService")
	StarService:RemoveAllStarsForPlayer(player)
	
	-- 7. Teleport player to spawn location
	local spawnCFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0) -- Slightly above spawn
	rootPart.CFrame = spawnCFrame
	
	-- Set respawn location for this world
	player.RespawnLocation = spawnLocation
	
	-- 8. Respawn pets for the new world
	PetService:RespawnEquippedPets(player)
	
	-- 9. Respawn stars for the new world
	StarService:Start(player)
	
	Log(string.format("Teleported player %s to world %s", player.Name, worldName))
	
	-- 10. Get updated data to send back to client (deep copy like InitUI expects)
	local updatedData = DataService:GetPlayerData(player)
	
	-- 11. Fire signal to client with new world and data
	self.Client.WorldChanged:Fire(player, worldName)
	self.Client.DataUpdated:Fire(player, updatedData)
	
	-- 12. Hide loading screen
	task.wait(0.5) -- Wait a moment for things to settle
	LoadingScreenService:HideLoadingScreen(player)
	
	return true, nil, updatedData
end

--[[
	Get the next world in progression order.
	
	@param currentWorld string - The current world name
	@return string? - The next world name, or nil if at the end
]]
function WorldService:GetNextWorld(currentWorld: string): string?
	local worldOrder = Stats.WorldOrder
	
	for i, world in ipairs(worldOrder) do
		if world == currentWorld and i < #worldOrder then
			return worldOrder[i + 1]
		end
	end
	
	return nil
end

--[[
	Get the fuel requirement to unlock a specific world.
	
	@param worldName string - The world name to check
	@return number? - The fuel requirement, or nil if world is Main or doesn't exist
]]
function WorldService:GetWorldUnlockRequirement(worldName: string): number?
	return Stats.WorldUnlockRequirements[worldName]
end

--[[
	Client request to teleport to a world.
	Validates that the player owns the world before teleporting.
	
	@param player Player - The player requesting teleport
	@param worldName string - The world name to teleport to
	@return boolean, string?, table? - Success status, optional error message, updated data
]]
function WorldService.Client:RequestTeleportToWorld(player: Player, worldName: string): (boolean, string?, any?)
	return WorldService:TeleportPlayerToWorld(player, worldName)
end

-- Knit lifecycle
function WorldService:KnitInit()
	-- Service initialization
end

function WorldService:KnitStart()
	Log("WorldService started")
end

return WorldService
