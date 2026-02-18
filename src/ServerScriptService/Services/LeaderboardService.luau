local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {},
})

-- Configuration
local TOP_N = 10 -- Number of top entries to display
local REFRESH_INTERVAL = 30 * 60 -- Refresh every 30 minutes in seconds

-- OrderedDataStore instances
local RebirthsStore = DataStoreService:GetOrderedDataStore("Leaderboard_Rebirths")
local DistanceStore = DataStoreService:GetOrderedDataStore("Leaderboard_MaxDistance")
local CashStore = DataStoreService:GetOrderedDataStore("Leaderboard_Cash")

-- Cached leaderboard data
local CachedLeaderboards = {
	Rebirths = {},
	MaxDistance = {},
	Cash = {},
}

-- Helper function for logging
local function Log(message: string)
	print(string.format("[LeaderboardService]: %s", message))
end


local function SavePlayerToStores(player: Player)
	local DataService = Knit.GetService("DataService")

	local stats = DataService:Get(player, "Stats")
	local currencies = DataService:Get(player, "Currencies")
	if not stats or not currencies then
		return
	end

	local userId = player.UserId
	local key = tostring(userId)

	-- OrderedDataStores only accept positive integers
	local rebirths = math.max(0, math.floor(stats.Rebirths or 0))
	local maxDistance = math.max(0, math.floor(stats.MaxDistanceTraveled or 0))
	local cash = math.max(0, math.floor(currencies.Cash or 0))

	local success, err

	success, err = pcall(function()
		RebirthsStore:SetAsync(key, rebirths)
	end)
	if not success then
		warn(string.format("[LeaderboardService]: Failed to save Rebirths for %s: %s", player.Name, tostring(err)))
	end

	success, err = pcall(function()
		DistanceStore:SetAsync(key, maxDistance)
	end)
	if not success then
		warn(string.format("[LeaderboardService]: Failed to save MaxDistance for %s: %s", player.Name, tostring(err)))
	end

	success, err = pcall(function()
		CashStore:SetAsync(key, cash)
	end)
	if not success then
		warn(string.format("[LeaderboardService]: Failed to save Cash for %s: %s", player.Name, tostring(err)))
	end
end

local function FetchTopEntries(orderedStore, count: number): { { UserId: number, Name: string, Value: number } }
	local entries = {}

	local success, result = pcall(function()
		return orderedStore:GetSortedAsync(false, count)
	end)

	if not success or not result then
		warn(string.format("[LeaderboardService]: Failed to fetch sorted data: %s", tostring(result)))
		return entries
	end

	local page = result:GetCurrentPage()
	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		local value = entry.value

		-- Resolve player name
		local playerName = "Unknown"
		local nameSuccess, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if nameSuccess and name then
			playerName = name
		end

		table.insert(entries, {
			UserId = userId,
			Name = playerName,
			Value = value,
		})
	end

	return entries
end

--[[
	Refresh all cached leaderboards by fetching from ordered data stores.
]]
local function RefreshLeaderboards()
	Log("Refreshing leaderboards...")

	CachedLeaderboards.Rebirths = FetchTopEntries(RebirthsStore, TOP_N)
	CachedLeaderboards.MaxDistance = FetchTopEntries(DistanceStore, TOP_N)
	CachedLeaderboards.Cash = FetchTopEntries(CashStore, TOP_N)

	Log(string.format(
		"Leaderboards refreshed: %d rebirths, %d distance, %d cash entries",
		#CachedLeaderboards.Rebirths,
		#CachedLeaderboards.MaxDistance,
		#CachedLeaderboards.Cash
	))
end

function LeaderboardService:GetTopRebirths(): { { UserId: number, Name: string, Value: number } }
	return CachedLeaderboards.Rebirths
end

function LeaderboardService:GetTopDistance(): { { UserId: number, Name: string, Value: number } }
	return CachedLeaderboards.MaxDistance
end

function LeaderboardService:GetTopCash(): { { UserId: number, Name: string, Value: number } }
	return CachedLeaderboards.Cash
end

-- Client methods to fetch leaderboard data
function LeaderboardService.Client:GetTopRebirths(_player: Player): { { UserId: number, Name: string, Value: number } }
	return LeaderboardService:GetTopRebirths()
end

function LeaderboardService.Client:GetTopDistance(_player: Player): { { UserId: number, Name: string, Value: number } }
	return LeaderboardService:GetTopDistance()
end

function LeaderboardService.Client:GetTopCash(_player: Player): { { UserId: number, Name: string, Value: number } }
	return LeaderboardService:GetTopCash()
end

-- Knit lifecycle
function LeaderboardService:KnitInit()
	Log("LeaderboardService initialized")
end

function LeaderboardService:KnitStart()
	-- Update ordered data stores when a player joins (after their data is loaded)
	local DataService = Knit.GetService("DataService")

	Players.PlayerAdded:Connect(function(player)
		DataService:OnDataReady(player):andThen(function()
			SavePlayerToStores(player)
		end)
	end)

	-- Handle players who joined before the service started
	for _, player in ipairs(Players:GetPlayers()) do
		DataService:OnDataReady(player):andThen(function()
			SavePlayerToStores(player)
		end)
	end

	-- Update ordered data stores when a player leaves
	Players.PlayerRemoving:Connect(function(player)
		SavePlayerToStores(player)
	end)

	-- Initial leaderboard fetch
	task.spawn(RefreshLeaderboards)

	-- Periodic refresh loop
	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			RefreshLeaderboards()
		end
	end)

	Log("LeaderboardService started")
end

return LeaderboardService
