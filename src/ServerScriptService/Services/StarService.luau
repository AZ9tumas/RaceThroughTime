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

local RebirthStats = require(ReplicatedStorage.Modules.RebirthStats)

local StarService = Knit.CreateService({
	Name = "StarService",
	Client = {
		SpawnStars = Knit.CreateSignal(), -- Signal to tell client to spawn stars
		SpawnStar = Knit.CreateSignal(), -- Signal to tell client to spawn a single star (for continuous spawning)
		RemoveStar = Knit.CreateSignal(), -- Signal to tell client to remove a collected star
		RemoveAllStars = Knit.CreateSignal(), -- Signal to tell client to remove all stars
	},
})

-- Private state
local UniversalTracker = {} -- [Player.UserId] = {StarInfo, StarInfo, ... 10 times}
local StarsFolder = nil
local TotalStarsCollected = 0 -- Counter for total stars collected by all players in the server
local StarSpawnLoops = {} -- [Player.UserId] = thread (spawn loop thread)

-- Helper function to get total fuel multiplier for player
-- Used for Gems calculation with multipliers
-- If all bonuses are 0, returns 1. Otherwise returns the sum of all bonuses.
local function GetFuelMultiplierForPlayer(player: Player): number
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	local stats = DataService:Get(player, "Stats")
	
	-- Calculate pet bonus (0 if no pets equipped)
	local petBonus = 0
	if inventory and inventory.PetInventory and inventory.EquippedPets then
		local equippedPets = {}
		for _, petIndex in ipairs(inventory.EquippedPets) do
			local petData = inventory.PetInventory[petIndex]
			if petData then
				table.insert(equippedPets, petData)
			end
		end
		petBonus = Stats.CalculateFuelMultiplier(equippedPets)
	end
	
	-- Get rebirth bonus (0 if no rebirths)
	local rebirthLevel = (stats and stats.Rebirths) or 0
	local rebirthBonus = RebirthStats.CalculateTotalMultiplier(rebirthLevel)
	
	-- Get other bonuses (VIP, boosts, etc.)
	local otherBonus = Stats.CalculateOtherBonus()
	
	-- Return total multiplier: if all bonuses are 0, use 1; otherwise sum of all bonuses
	local totalBonuses = petBonus + rebirthBonus + otherBonus
	return totalBonuses > 0 and totalBonuses or 1
end

-- Recalculate and update the player's fuel based on their Stars and multipliers
-- This should be called whenever multipliers change (pet equip/unequip, rebirth, etc.)
local function RecalculateFuelForPlayer(player: Player)
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	local stats = DataService:Get(player, "Stats")
	
	if not stats then return end
	
	local stars = stats.Stars or 0
	
	-- Calculate pet bonus (0 if no pets equipped)
	local petBonus = 0
	if inventory and inventory.PetInventory and inventory.EquippedPets then
		local equippedPets = {}
		for _, petIndex in ipairs(inventory.EquippedPets) do
			local petData = inventory.PetInventory[petIndex]
			if petData then
				table.insert(equippedPets, petData)
			end
		end
		petBonus = Stats.CalculateFuelMultiplier(equippedPets)
	end
	
	-- Get rebirth bonus (0 if no rebirths)
	local rebirthLevel = stats.Rebirths or 0
	local rebirthBonus = RebirthStats.CalculateTotalMultiplier(rebirthLevel)
	
	-- Get other bonuses (VIP, boosts, etc.)
	local otherBonus = Stats.CalculateOtherBonus()
	
	-- Calculate new fuel: Stars * (1 + petBonus + rebirthBonus + otherBonus)
	local newFuel = Stats.CalculateFuelFromStars(stars, petBonus, rebirthBonus, otherBonus)
	
	-- Update fuel in player stats
	DataService:Update(player, "Stats", function(currentStats)
		currentStats.Fuel = newFuel
		return currentStats
	end)
end

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

-- Get star information for a player
function StarService:GetStarInformation(player: Player)
	return UniversalTracker[player.UserId]
end

-- Find star info by ID in player's tracker
-- Note: Uses player's CurrentWorld attribute for world info if needed
local function FindStarById(userId: number, starId: string):
	({ Position: Vector3, ID: string, StarName: string, Index: number }?, number?)
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

-- Server-side star collection (for pets, no distance check)
-- Returns the star equivalent value if successful, nil otherwise
function StarService:CollectStarServer(player: Player, starId: string): number?
	local userId = player.UserId
	local starInfo, index = FindStarById(userId, starId)
	
	if not starInfo then
		return nil
	end
	
	local starEquivalent = Stats.StarEquivalents[starInfo.StarName] or 0
	
	-- Remove star from tracker
	local starInfoList = UniversalTracker[userId]
	if starInfoList then
		table.remove(starInfoList, index)
	end
	
	-- Notify client to remove the star
	self.Client.RemoveStar:Fire(player, starId)
	
	Log(string.format("Server collected star %s for player %s, star equivalent: %d", starInfo.StarName, player.Name, starEquivalent))
	
	return starEquivalent
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

	-- Use StarCollectionPlayerRadius for player collection distance check
	local distance = (rootPart.Position - starInfo.Position).Magnitude
	if distance > Stats.MaxStarCollectionPlayerRadius then
		warn(string.format("[StarService]: Player %s is too far from star (distance: %.2f, max: %.2f)", player.Name, distance, Stats.MaxStarCollectionPlayerRadius))
		return false
	end

	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Check if this is a Gems star
	if starInfo.StarName == "Gems" then
		-- Calculate gems with multiplier
		local fuelMultiplier = GetFuelMultiplierForPlayer(player)
		local baseGemValue = Stats.StarGemValues.Gems or 5
		local finalGemValue = math.floor(baseGemValue * fuelMultiplier)
		
		-- Add gems to player
		DataService:Update(player, "Currencies", function(currencies)
			currencies.Gems = (currencies.Gems or 0) + finalGemValue
			return currencies
		end)
		
		Log(string.format("Player %s collected Gems, gained %d gems (multiplier: %.2f)", player.Name, finalGemValue, fuelMultiplier))
		
		-- Show notification for gem collection
		NotificationService:SendNotification(player, "Gems collected! 💎 +" .. finalGemValue .. " Gems", {
			icon = "💎", sound = "CollectStar", name = "Custom"
		}, 2)
	else
		-- Regular star - get the star equivalent value
		local starEquivalent = Stats.StarEquivalents[starInfo.StarName] or 0

		-- Star collection verified - add star equivalents to player's Stars count
		DataService:Update(player, "Stats", function(currentStats)
			currentStats.Stars = (currentStats.Stars or 0) + starEquivalent
			return currentStats
		end)
		
		-- Recalculate fuel based on new Stars count and current multipliers
		RecalculateFuelForPlayer(player)
		
		-- Get updated stats for notification
		local updatedStats = DataService:Get(player, "Stats")
		local newFuel = updatedStats and updatedStats.Fuel or 0

		Log(string.format("Player %s collected %s, gained %d star equivalents (new fuel: %d)", player.Name, starInfo.StarName, starEquivalent, newFuel))
		
		-- Show notification for star collection
		NotificationService:SendNotification(player, "Star collected! ⭐ +" .. starEquivalent .. " Stars", {
			icon = "⭐", sound = "CollectStar", name = "Custom"
		}, 2)
	end

	DataService:FireDataReady(player)

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

-- Remove all stars for a player
function StarService:RemoveAllStarsForPlayer(player: Player)
	local userId = player.UserId
	
	-- Clear tracker data
	if UniversalTracker[userId] then
		UniversalTracker[userId] = {}
	end
	
	-- Notify client to clear visuals
	self.Client.RemoveAllStars:Fire(player)
	Log(string.format("Removed all stars for player %s", player.Name))
end

-- Get the total number of stars collected by all players on the server
function StarService:GetTotalStarsCollected(): number
	return TotalStarsCollected
end

-- Generate a single star for a player
local function GenerateStar(player: Player)
	local userId = player.UserId
	
	-- Initialize tracker if needed
	if not UniversalTracker[userId] then
		UniversalTracker[userId] = {}
	end
	
	local starInfoList = UniversalTracker[userId]
	
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
		Index = #starInfoList + 1,
	}

	table.insert(starInfoList, starInfo)
	return starInfo
end

-- Start star spawning logic for a player
function StarService:Start(player: Player)
	local userId = player.UserId

	-- Cancel existing loop if any
	if StarSpawnLoops[userId] then
		task.cancel(StarSpawnLoops[userId])
	end

	StarSpawnLoops[userId] = task.spawn(function()
		Log(string.format("Started star loop for %s", player.Name))
		
		while player:IsDescendantOf(Players) do
			local config = Stats.StarConfig
			-- Wait for spawn interval
			task.wait(config.SpawnInterval)
			
			local starInfoList = UniversalTracker[userId] or {}
			local count = #starInfoList
			local target = config.MaxStars
			
			-- Check if below MaxStars
			if count < target then
				local newStars = {}
				
				-- Generate stars until we reach MaxStars
				while #starInfoList < target do
					local star = GenerateStar(player)
					if star then
						table.insert(newStars, star)
						starInfoList = UniversalTracker[userId] -- Update reference
					else
						break -- No valid positions or error
					end
				end
				
				-- Send to client after generation is done
				if #newStars > 0 then
					self.Client.SpawnStars:Fire(player, newStars)
					Log(string.format("Spawned %d new stars for %s", #newStars, player.Name))
				end
			end
		end
		
		StarSpawnLoops[userId] = nil
	end)
end

-- Clean up player data when they leave
local function OnPlayerRemoving(player: Player)
	if StarSpawnLoops[player.UserId] then
		task.cancel(StarSpawnLoops[player.UserId])
		StarSpawnLoops[player.UserId] = nil
	end
	UniversalTracker[player.UserId] = nil
	Log(string.format("Cleared star data for player %s", player.Name))
end

-- Public function to recalculate fuel for a player
-- Should be called when multipliers change (pet equip/unequip, rebirth, etc.)
function StarService:RecalculateFuel(player: Player)
	RecalculateFuelForPlayer(player)
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
