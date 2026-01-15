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
	Shows loading screen during teleport.
	
	@param player Player - The player to teleport
	@param worldName string - The world name to teleport to
	@return boolean, string? - Success status and optional error message
]]
function WorldService:TeleportPlayerToWorld(player: Player, worldName: string): (boolean, string?)
	if not player or not player:IsDescendantOf(Players) then
		warn("[WorldService]: Invalid player provided")
		return false, "Invalid player"
	end
	
	-- Check if player has access to this world
	if not self:PlayerHasWorld(player, worldName) then
		return false, "World not unlocked"
	end
	
	-- Get the world folder
	local worldFolder = GetWorldFolder(worldName)
	if not worldFolder then
		return false, "World does not exist"
	end
	
	-- Get spawn location for the world
	local spawnLocation = GetSpawnLocationForWorld(worldName)
	if not spawnLocation then
		return false, "No spawn location in world"
	end
	
	-- Get player's character
	local character = player.Character
	if not character then
		return false, "No character"
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart"
	end
	
	-- Show loading screen
	local LoadingScreenService = Knit.GetService("LoadingScreenService")
	LoadingScreenService:ShowLoadingScreen(player, 0.5) -- Show for 0.5 seconds
	
	-- Wait a moment for loading screen to fade in
	task.wait(0.2)
	
	-- Teleport player to spawn location
	local spawnCFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0) -- Slightly above spawn
	rootPart.CFrame = spawnCFrame
	
	-- Update player's current world in data
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Progression", function(progression)
		progression.CurrentWorld = worldName
		return progression
	end)
	
	Log(string.format("Teleported player %s to world %s", player.Name, worldName))
	
	-- Fire signal to client
	self.Client.WorldChanged:Fire(player, worldName)
	
	return true, nil
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

-- Knit lifecycle
function WorldService:KnitInit()
	-- Service initialization
end

function WorldService:KnitStart()
	Log("WorldService started")
end

return WorldService
