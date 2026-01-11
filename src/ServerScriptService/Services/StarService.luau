--[[
	StarService
	Handles star spawning, tracking, and collection for players.
	Stars provide fuel bonuses when collected.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local StarService = Knit.CreateService({
	Name = "StarService",
	Client = {
		SpawnStars = Knit.CreateSignal(), -- Signal to tell client to spawn stars
		SpawnStar = Knit.CreateSignal(), -- Signal to tell client to spawn a single star (for continuous spawning)
		RemoveStar = Knit.CreateSignal(), -- Signal to tell client to remove a collected star
	},
})

-- Private state
local UniversalTracker = {} -- [Player.UserId] = {StarInfo, StarInfo, ... 10 times}
local StarsFolder = nil
local TotalStarsCollected = 0 -- Counter for total stars collected by all players in the server
local StarSpawnLoops = {} -- [Player.UserId] = true/false (whether spawn loop is active)

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[StarService]: %s", message))
end

-- Get SpawnLocation from the player's current world
local function GetSpawnLocationForPlayer(player: Player): SpawnLocation?
	local DataService = Knit.GetService("DataService")
	local worldName = DataService:GetPlayerWorld(player)
	
	-- World folders are named directly in workspace (e.g., "Main", "StoneAge")
	local worldFolder = workspace:FindFirstChild(worldName)
	print("World folder for star spawning:", worldFolder)
	if worldFolder then
		local spawnLocation = worldFolder:FindFirstChild("SpawnLocation")
		if spawnLocation then
			return spawnLocation
		end
	end
	
	-- Fallback to Main world if the specified world is not found
	local mainWorld = workspace:FindFirstChild("Main")
	if mainWorld then
		return mainWorld:FindFirstChild("SpawnLocation")
	end
	
	return nil
end

-- Initialize the Stars folder in workspace
local function InitializeStarsFolder()
	-- Find or create Stars folder
	StarsFolder = workspace:FindFirstChild("Stars")
	if StarsFolder then
		-- Clear existing stars
		StarsFolder:ClearAllChildren()
		Log("Stars folder cleared")
	else
		StarsFolder = Instance.new("Folder")
		StarsFolder.Name = "Stars"
		StarsFolder.Parent = workspace
		Log("Stars folder created")
	end
end

-- Get a random star type based on probability weights
local function GetRandomStarType(): string
	local random = math.random()
	local cumulativeProbability = 0

	for starName, probability in pairs(Stats.StarProbabilities) do
		cumulativeProbability = cumulativeProbability + probability
		if random <= cumulativeProbability then
			return starName
		end
	end

	-- Fallback to YellowStar (shouldn't happen if probabilities sum to 1.0)
	return "YellowStar"
end

-- Generate a unique ID for a star
local function GenerateStarId(): string
	return HttpService:GenerateGUID(false)
end

-- Generate random position within spawn radius
local function GenerateRandomPosition(centerPosition: Vector3, existingPositions: { Vector3 }): Vector3?
	local config = Stats.StarConfig
	local maxAttempts = 50

	for _ = 1, maxAttempts do
		local offsetX = math.random(-config.SpawnRadius, config.SpawnRadius)
		local offsetZ = math.random(-config.SpawnRadius, config.SpawnRadius)
		local newPosition = Vector3.new(
			centerPosition.X + offsetX,
			centerPosition.Y + 5, -- Slightly above ground level
			centerPosition.Z + offsetZ
		)

		-- Check minimum distance from existing positions
		local isValidPosition = true
		for _, existingPos in ipairs(existingPositions) do
			if (newPosition - existingPos).Magnitude < config.MinDistanceBetweenStars then
				isValidPosition = false
				break
			end
		end

		if isValidPosition then
			return newPosition
		end
	end

	-- Could not find valid position after max attempts
	return nil
end

-- Generate star information for a player
function StarService:GenerateStarInformation(player: Player)
	local userId = player.UserId
	local character = player.Character
	
	-- Get SpawnLocation from the player's current world
	local spawnLocation = GetSpawnLocationForPlayer(player)
	if not spawnLocation then
		warn(string.format("[StarService]: No SpawnLocation found for player %s's world", player.Name))
		return {}
	end
	
	local spawnCenter = spawnLocation.Position -- Default spawn center

	local starInfoList = {}
	local existingPositions = {}
	local config = Stats.StarConfig

	for i = 1, config.SpawnCount do
		local position = GenerateRandomPosition(spawnCenter, existingPositions)
		if position then
			table.insert(existingPositions, position)

			local starName = GetRandomStarType()
			local starInfo = {
				Position = position,
				ID = GenerateStarId(),
				StarName = starName,
				FuelValue = Stats.StarFuelValues[starName],
				Index = i,
			}
			table.insert(starInfoList, starInfo)
		end
	end

	UniversalTracker[userId] = starInfoList
	Log(string.format("Generated %d stars for player %s", #starInfoList, player.Name))

	return starInfoList
end

-- Get star information for a player
function StarService:GetStarInformation(player: Player)
	return UniversalTracker[player.UserId]
end

-- Spawn stars for a player (sends data to client)
function StarService:SpawnStarsForPlayer(player: Player)
	local userId = player.UserId
	local starInfoList = UniversalTracker[userId]

	if not starInfoList or #starInfoList == 0 then
		warn(string.format("[StarService]: No star information found for player %s. Generate star information first.", player.Name))
		return
	end

	-- Send star information to the client
	self.Client.SpawnStars:Fire(player, starInfoList)
	Log(string.format("Sent %d stars to player %s for spawning", #starInfoList, player.Name))
end

-- Find star info by ID in player's tracker
local function FindStarById(userId: number, starId: string):
	({ Position: Vector3, ID: string, StarName: string, FuelValue: number, Index: number }?, number?)
	local starInfoList = UniversalTracker[userId]
	if not starInfoList then
		return nil, nil
	end

	for index, starInfo in ipairs(starInfoList) do
		if starInfo.ID == starId then
			return starInfo, index
		end
	end

	return nil, nil
end

-- Verify and process star collection
function StarService.Client:CollectStar(player: Player, starId: string): boolean
	local userId = player.UserId
	local starInfo, index = FindStarById(userId, starId)

	if not starInfo then
		warn(string.format("[StarService]: Star %s not found for player %s", starId, player.Name))
		return false
	end

	-- Verify player position is close to star position
	local character = player.Character
	if not character then
		warn(string.format("[StarService]: Player %s has no character", player.Name))
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		warn(string.format("[StarService]: Player %s has no HumanoidRootPart", player.Name))
		return false
	end

	local distance = (rootPart.Position - starInfo.Position).Magnitude
	if distance > Stats.StarConfig.CollectionRadius then
		warn(string.format("[StarService]: Player %s is too far from star (distance: %.2f)", player.Name, distance))
		return false
	end

	-- Star collection verified - add fuel to player
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Stats", function(stats)
		local finalVal = starInfo.FuelValue + stats.Fuel
		stats.Fuel = finalVal
		return stats
	end)

	Log(string.format("Player %s collected %s, gained %d fuel", player.Name, starInfo.StarName, starInfo.FuelValue))

	-- Increment total stars collected counter
	TotalStarsCollected = TotalStarsCollected + 1
	Log(string.format("Total stars collected on server: %d", TotalStarsCollected))

	-- Remove star from tracker
	local starInfoList = UniversalTracker[userId]
	if starInfoList then
		table.remove(starInfoList, index)
	end

	-- Notify client to remove the star
	StarService.Client.RemoveStar:Fire(player, starId)

	return true
end

-- Get the total number of stars collected by all players on the server
function StarService:GetTotalStarsCollected(): number
	return TotalStarsCollected
end

-- Generate a single star for a player (used for continuous spawning)
local function GenerateSingleStar(player: Player): ({ Position: Vector3, ID: string, StarName: string, FuelValue: number, Index: number }?)
	local userId = player.UserId
	local starInfoList = UniversalTracker[userId]
	
	if not starInfoList then
		starInfoList = {}
		UniversalTracker[userId] = starInfoList
	end
	
	-- Check if we're at max stars
	local config = Stats.StarConfig
	if #starInfoList >= config.MaxStars then
		return nil -- Max stars reached
	end
	
	-- Get SpawnLocation from the player's current world
	local spawnLocation = GetSpawnLocationForPlayer(player)
	if not spawnLocation then
		return nil
	end
	
	local spawnCenter = spawnLocation.Position
	
	-- Collect existing positions
	local existingPositions = {}
	for _, starInfo in ipairs(starInfoList) do
		table.insert(existingPositions, starInfo.Position)
	end
	
	-- Generate position for new star
	local position = GenerateRandomPosition(spawnCenter, existingPositions)
	if not position then
		return nil -- Could not find valid position
	end
	
	local starName = GetRandomStarType()
	local starInfo = {
		Position = position,
		ID = GenerateStarId(),
		StarName = starName,
		FuelValue = Stats.StarFuelValues[starName],
		Index = #starInfoList + 1,
	}
	
	table.insert(starInfoList, starInfo)
	Log(string.format("Generated new star for player %s (total: %d)", player.Name, #starInfoList))
	
	return starInfo
end

-- Start continuous star spawning loop for a player
function StarService:StartContinuousSpawning(player: Player)
	local userId = player.UserId
	
	-- Don't start if already running
	if StarSpawnLoops[userId] then
		return
	end
	
	StarSpawnLoops[userId] = true
	Log(string.format("Started continuous star spawning for player %s", player.Name))
	
	task.spawn(function()
		local config = Stats.StarConfig
		
		while StarSpawnLoops[userId] and player:IsDescendantOf(Players) do
			-- Wait for spawn interval
			task.wait(config.SpawnInterval)
			
			-- Check if still active
			if not StarSpawnLoops[userId] or not player:IsDescendantOf(Players) then
				break
			end
			
			-- Try to spawn a star if below max
			local starInfoList = UniversalTracker[userId]
			if starInfoList and #starInfoList < config.MaxStars then
				local newStar = GenerateSingleStar(player)
				if newStar then
					-- Notify client to spawn the new star
					StarService.Client.SpawnStar:Fire(player, newStar)
				end
			end
		end
		
		StarSpawnLoops[userId] = nil
		Log(string.format("Stopped continuous star spawning for player %s", player.Name))
	end)
end

-- Stop continuous star spawning for a player
function StarService:StopContinuousSpawning(player: Player)
	StarSpawnLoops[player.UserId] = nil
end

-- Clean up player data when they leave
local function OnPlayerRemoving(player: Player)
	StarSpawnLoops[player.UserId] = nil
	UniversalTracker[player.UserId] = nil
	Log(string.format("Cleared star data for player %s", player.Name))
end

-- Knit lifecycle
function StarService:KnitInit()
	-- Initialize Stars folder in workspace
	InitializeStarsFolder()

	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function StarService:KnitStart()
	Log("StarService started")
end

return StarService
