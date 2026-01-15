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
		Fuel = 100, -- Starting fuel for players
	},
	Progression = {
		CurrentWorld = "Main",
		UnlockedWorlds = { "Main" },
	},
	Inventory = {
		-- PetInventory stores full pet data:
		-- { Name: string, PetType: string, Multiplier: number, ObtainedAt: number }
		PetInventory = {},
		EquippedPets = {}, -- Indices of equipped pets (max 3)
		Potions = {},
	},
	Meta = {
		DailyStreak = 0,
		LastClaim = 0,
		CollectedRewards = {}, -- Tracks which daily reward IDs have been collected
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
	--print(string.format("[DataService | %s]: %s", player.Name, message))
end

-- Initialize leaderstats for a player
local function InitializeLeaderstats(player: Player, playerData: typeof(Template))
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = playerData.Currencies.Cash
	cashValue.Parent = leaderstats

	local gemsValue = Instance.new("IntValue")
	gemsValue.Name = "Gems"
	gemsValue.Value = playerData.Currencies.Gems
	gemsValue.Parent = leaderstats

	local statsFolder = Instance.new("Folder", player)
	statsFolder.Name = "Stats"

	local fuelValue: NumberValue = Instance.new("NumberValue", statsFolder)
	fuelValue.Name = "Fuel"
	fuelValue.Value = playerData.Stats.Fuel
end

-- Sync currency values to leaderstats (if they exist)
local function SyncLeaderstats(player: Player, playerData: typeof(Template))
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local cashValue = leaderstats:FindFirstChild("Cash")
	if cashValue then
		cashValue.Value = playerData.Currencies.Cash
	end

	local gemsValue = leaderstats:FindFirstChild("Gems")
	if gemsValue then
		gemsValue.Value = playerData.Currencies.Gems
	end

	local statsFolder = player:FindFirstChild("Stats")
	local fuelVal : NumberValue = statsFolder and statsFolder:FindFirstChild("Fuel")
	if fuelVal then fuelVal.Value = playerData.Stats.Fuel end
end


local function setupPets(player: Player, data: typeof(Template))
	-- Initialize pets BEFORE sending data to client so IDs are available
	local PetService = Knit.GetService("PetService")
	PetService:InitializePets(player)
	
	-- Create a copy of the data to avoid modifying the persistent profile
	-- Deep copy PetInventory to inject session-only IDs, other fields are shallow copied
	-- (safe since client can't modify server's profile.Data)
	local dataToSend = {}
	for key, value in pairs(data) do
		if key == "Inventory" then
			-- Deep copy inventory to safely inject pet IDs
			local inventoryCopy = {}
			for invKey, invValue in pairs(value) do
				if invKey == "PetInventory" then
					-- Deep copy pet inventory with IDs injected
					local petInventoryCopy = {}
					for index, petData in ipairs(invValue) do
						local petCopy = {}
						for petKey, petValue in pairs(petData) do
							petCopy[petKey] = petValue
						end
						-- Inject the runtime session ID
						local petID = PetService:GetPetIDByIndex(player, index)
						if petID then
							petCopy.ID = petID
						end
						petInventoryCopy[index] = petCopy
					end
					inventoryCopy[invKey] = petInventoryCopy
				else
					inventoryCopy[invKey] = invValue
				end
			end
			dataToSend[key] = inventoryCopy
		else
			dataToSend[key] = value
		end
	end

	return dataToSend
end

-- Check if both data and client are ready, then resolve session
local function TryResolveSession(player: Player)
	local profile = PlayerProfiles[player]
	local clientReady = ClientStatus[player]
	local sessionPromise = SessionReadyPromises[player]
	
	if profile and clientReady and sessionPromise and sessionPromise.resolve then
		print(player, "Session Initialized")
		
		local dataToSend = setupPets(player, profile.Data)
		
		DataService.Client.DataReady:Fire(player, dataToSend)
		sessionPromise.resolve()
		sessionPromise.resolve = nil -- Prevent double resolution
	end
end

-- Initialize player data when they join
local function OnPlayerAdded(player: Player)
	-- Get or create data ready promise
	if not DataReadyPromises[player] then
		local dataResolve
		local dataPromise = Promise.new(function(resolve)
			dataResolve = resolve
		end)
		DataReadyPromises[player] = { resolve = dataResolve, promise = dataPromise }
	end

	-- Get or create session ready promise
	if not SessionReadyPromises[player] then
		local sessionResolve
		local sessionPromise = Promise.new(function(resolve)
			sessionResolve = resolve
		end)
		SessionReadyPromises[player] = { resolve = sessionResolve, promise = sessionPromise }
	end

	-- Initialize client status as not ready
	ClientStatus[player] = false

	-- Load profile
	local profile = GameProfileStore:StartSessionAsync("Player_" .. player.UserId)

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		PlayerProfiles[player] = profile

		print(player, "Data Loaded")

		local worldName = profile.Data.Progression.CurrentWorld or "Main"
		local folder = workspace:FindFirstChild(worldName)
		-- in case there is an invalid world we default to main
		if not folder then
			folder = workspace:FindFirstChild("Main")
			--profile.Data.Progression.CurrentWorld = "Main"
		end
		local spawnLocation = folder:FindFirstChild("SpawnLocation")
		player.RespawnLocation = spawnLocation
		player:LoadCharacterAsync()

		task.spawn(function()
			local hrp = player.Character and player.Character:WaitForChild("HumanoidRootPart")
			hrp:PivotTo(spawnLocation.CFrame + Vector3.new(0, 5, 0))
		end)

		-- Initialize leaderstats after data is ready
		InitializeLeaderstats(player, profile.Data)

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

		player:SetAttribute("CurrentWorld", worldName)

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
		print(player, "Client Assets Ready")
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

	SyncLeaderstats(player, profile.Data)
end

-- Returns a promise that resolves when the player's profile is loaded
function DataService:OnDataReady(player: Player)
	local entry = DataReadyPromises[player]
	if not entry then
		if not player:IsDescendantOf(Players) then
			return Promise.reject("Player not found or has left")
		end

		local resolve
		local promise = Promise.new(function(r) resolve = r end)
		entry = { resolve = resolve, promise = promise }
		DataReadyPromises[player] = entry
	end

	return entry.promise
end

-- Returns a "Gatekeeper" promise that resolves when data is ready AND client has signaled ready
function DataService:OnSessionReady(player: Player)
	local entry = SessionReadyPromises[player]
	if not entry then
		if not player:IsDescendantOf(Players) then
			return Promise.reject("Player not found or has left")
		end

		local resolve
		local promise = Promise.new(function(r) resolve = r end)
		entry = { resolve = resolve, promise = promise }
		SessionReadyPromises[player] = entry
	end

	return entry.promise
end

-- Get the player's profile (for advanced use cases)
function DataService:GetProfile(player: Player)
	return PlayerProfiles[player]
end

-- Valid world names that exist in the game configuration
local VALID_WORLDS = { "Main", "StoneAge" } -- Add more worlds here as they are added to the game

-- Get the player's current world (defaults to "Main" if not set or invalid)
function DataService:GetPlayerWorld(player: Player): string
	local profile = PlayerProfiles[player]
	if not profile then
		return "Main"
	end
	
	local progression = profile.Data.Progression
	if not progression or not progression.CurrentWorld then
		return "Main"
	end
	
	-- Validate that the world name exists in game configuration
	local worldName = progression.CurrentWorld
	for _, validWorld in ipairs(VALID_WORLDS) do
		if worldName == validWorld then
			return worldName
		end
	end
	
	-- Invalid world, return default
	return "Main"
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
