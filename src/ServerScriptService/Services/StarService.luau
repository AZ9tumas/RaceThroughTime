--[[
	StarService
	Handles star spawning, tracking, and collection for players.
	Stars provide fuel bonuses when collected.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

-- base parts for reference
local SpawnLocation: SpawnLocation = workspace:FindFirstChild("RTT_Map_Final"):FindFirstChild("SpawnLocation")

local StarService = Knit.CreateService({
	Name = "StarService",
	Client = {
		SpawnStars = Knit.CreateSignal(), -- Signal to tell client to spawn stars
		RemoveStar = Knit.CreateSignal(), -- Signal to tell client to remove a collected star
	},
})

-- Private state
local UniversalTracker = {} -- [Player.UserId] = {StarInfo, StarInfo, ... 10 times}
local StarsFolder = nil

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[StarService]: %s", message))
end

-- Initialize the Stars folder in Workspace
local function InitializeStarsFolder()
	-- Find or create Stars folder
	StarsFolder = Workspace:FindFirstChild("Stars")
	if StarsFolder then
		-- Clear existing stars
		StarsFolder:ClearAllChildren()
		Log("Stars folder cleared")
	else
		StarsFolder = Instance.new("Folder")
		StarsFolder.Name = "Stars"
		StarsFolder.Parent = Workspace
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
	local spawnCenter = SpawnLocation.Position -- Default spawn center

	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			--spawnCenter = rootPart.Position
		end
	end

	print("Here, start service")

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
		local maxFuel = Stats.MaxBaseFuel
		finalVal = math.min(finalVal, maxFuel)
		stats.Fuel = finalVal
		return stats
	end)

	Log(string.format("Player %s collected %s, gained %d fuel", player.Name, starInfo.StarName, starInfo.FuelValue))

	-- Remove star from tracker
	local starInfoList = UniversalTracker[userId]
	if starInfoList then
		table.remove(starInfoList, index)
	end

	-- Notify client to remove the star
	StarService.Client.RemoveStar:Fire(player, starId)

	return true
end

-- Clean up player data when they leave
local function OnPlayerRemoving(player: Player)
	UniversalTracker[player.UserId] = nil
	Log(string.format("Cleared star data for player %s", player.Name))
end

-- Knit lifecycle
function StarService:KnitInit()
	-- Initialize Stars folder in Workspace
	InitializeStarsFolder()

	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function StarService:KnitStart()
	Log("StarService started")
end

return StarService
