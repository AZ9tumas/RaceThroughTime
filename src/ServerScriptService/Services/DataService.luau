--[[
	DataService
	Persistent data management with session locking and client sync.
	Uses Knit framework and ProfileStore for data persistence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Promise = require(ReplicatedStorage.Packages.Promise)
local ProfileStore = require(script.Parent.Parent.Modules.ProfileStore)

-- Data Template
local Template = {
	Currencies = {
		Cash = 0,
		Gems = 0,
	},
	Stats = {
		TotalDistance = 0,
		Points = 0,
		Rebirths = 0,
	},
	Progression = {
		CurrentWorld = "Stone Age",
		UnlockedWorlds = { "Stone Age" },
	},
	Inventory = {
		PetInventory = {},
		EquippedPets = {},
		Potions = {},
	},
	Meta = {
		DailyStreak = 0,
		LastClaim = 0,
		UpdateVersion = 0,
		Settings = {
			Music = true,
			SFX = true,
		},
	},
}

local DataService = Knit.CreateService({
	Name = "DataService",
	Client = {
		DataReady = Knit.CreateSignal(), -- Signal to notify client when data is loaded
	},
})

-- Private state
local PlayerProfiles = {} -- [Player] = Profile
local ClientStatus = {} -- [Player] = boolean (true when client has finished loading assets)
local DataReadyPromises = {} -- [Player] = {resolve, promise}
local SessionReadyPromises = {} -- [Player] = {resolve, promise}

-- ProfileStore instance
local GameProfileStore = ProfileStore.New("RaceThroughTime_v1", Template)

-- Helper function for logging
local function Log(player: Player, message: string)
	print(string.format("[DataService | %s]: %s", player.Name, message))
end

-- Initialize leaderstats for a player
local function InitializeLeaderstats(player: Player, currencies: { Cash: number, Gems: number })
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = currencies.Cash
	cashValue.Parent = leaderstats

	local gemsValue = Instance.new("IntValue")
	gemsValue.Name = "Gems"
	gemsValue.Value = currencies.Gems
	gemsValue.Parent = leaderstats

	Log(player, "Leaderstats Initialized")
end

-- Sync currency values to leaderstats (if they exist)
local function SyncLeaderstats(player: Player, currencies: { Cash: number, Gems: number })
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return -- Leaderstats not yet created or player disconnected
	end

	local cashValue = leaderstats:FindFirstChild("Cash")
	if cashValue then
		cashValue.Value = currencies.Cash
	end

	local gemsValue = leaderstats:FindFirstChild("Gems")
	if gemsValue then
		gemsValue.Value = currencies.Gems
	end
end

-- Check if both data and client are ready, then resolve session
local function TryResolveSession(player: Player)
	local profile = PlayerProfiles[player]
	local clientReady = ClientStatus[player]
	local sessionPromise = SessionReadyPromises[player]

	if profile and clientReady and sessionPromise and sessionPromise.resolve then
		Log(player, "Session Initialized")
		sessionPromise.resolve()
		sessionPromise.resolve = nil -- Prevent double resolution
	end
end

-- Initialize player data when they join
local function OnPlayerAdded(player: Player)
	-- Create data ready promise
	local dataResolve
	local dataPromise = Promise.new(function(resolve)
		dataResolve = resolve
	end)
	DataReadyPromises[player] = { resolve = dataResolve, promise = dataPromise }

	-- Create session ready promise
	local sessionResolve
	local sessionPromise = Promise.new(function(resolve)
		sessionResolve = resolve
	end)
	SessionReadyPromises[player] = { resolve = sessionResolve, promise = sessionPromise }

	-- Initialize client status as not ready
	ClientStatus[player] = false

	-- Load profile
	local profile = GameProfileStore:StartSessionAsync("Player_" .. player.UserId)

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		PlayerProfiles[player] = profile

		Log(player, "Data Loaded")

		-- Initialize leaderstats after data is ready
		InitializeLeaderstats(player, profile.Data.Currencies)

		-- Add save logging for debugging
		profile.OnSave:Connect(function()
			Log(player, "Data Saving...")
		end)

		profile.OnAfterSave:Connect(function(lastSavedData)
			Log(player, "Data Saved Successfully")
		end)

		-- Resolve data ready promise
		if DataReadyPromises[player] and DataReadyPromises[player].resolve then
			DataReadyPromises[player].resolve()
			DataReadyPromises[player].resolve = nil
		end

		-- Fire DataReady signal to client
		DataService.Client.DataReady:Fire(player)

		-- Check if session is ready to initialize
		TryResolveSession(player)

		-- Handle session end (e.g., when profile is stolen by another server)
		profile.OnSessionEnd:Connect(function()
			if player:IsDescendantOf(Players) then
				player:Kick("Your data session has ended. Please rejoin.")
			end
		end)
	else
		-- Failed to load profile
		player:Kick("Failed to load your data. Please try again later.")
	end
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	local profile = PlayerProfiles[player]
	if profile then
		Log(player, "Ending Session and Saving Data...")
		profile:EndSession()
	end

	PlayerProfiles[player] = nil
	ClientStatus[player] = nil
	DataReadyPromises[player] = nil
	SessionReadyPromises[player] = nil
end

-- Client calls this when assets are loaded
function DataService.Client:SignalReady(player: Player)
	if ClientStatus[player] == false then
		ClientStatus[player] = true
		Log(player, "Client Assets Ready")
		TryResolveSession(player)
	end
end

-- Get a value from player's data
function DataService:Get(player: Player, key: string): any
	local profile = PlayerProfiles[player]
	if not profile then
		warn(string.format("[DataService]: No profile found for %s", player.Name))
		return nil
	end

	if key == nil then return profile.Data end
	return profile.Data[key]
end

-- Atomic update via callback
function DataService:Update(player: Player, key: string, callback: (any) -> any)
	local profile = PlayerProfiles[player]
	if not profile then
		warn(string.format("[DataService]: No profile found for %s", player.Name))
		return
	end

	local currentValue = profile.Data[key]
	local newValue = callback(currentValue)
	profile.Data[key] = newValue

	-- Sync leaderstats if Currencies were updated
	if key == "Currencies" then
		SyncLeaderstats(player, newValue)
	end
end

-- Returns a promise that resolves when the player's profile is loaded
function DataService:OnDataReady(player: Player)
	local entry = DataReadyPromises[player]
	if entry then
		return entry.promise
	end

	-- If player already has a profile, resolve immediately
	if PlayerProfiles[player] then
		return Promise.resolve()
	end

	-- No entry found, player may have left
	return Promise.reject("Player not found or has left")
end

-- Returns a "Gatekeeper" promise that resolves when data is ready AND client has signaled ready
function DataService:OnSessionReady(player: Player)
	local entry = SessionReadyPromises[player]
	if entry then
		return entry.promise
	end

	-- If both conditions are already met, resolve immediately
	if PlayerProfiles[player] and ClientStatus[player] then
		return Promise.resolve()
	end

	-- No entry found, player may have left
	return Promise.reject("Player not found or has left")
end

-- Get the player's profile (for advanced use cases)
function DataService:GetProfile(player: Player)
	return PlayerProfiles[player]
end

-- Knit lifecycle
function DataService:KnitInit()

	-- Set up player connections
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Handle players who joined before the service started
	for _, player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, player)
	end
end

function DataService:KnitStart()
	-- Service is fully started
end

return DataService
