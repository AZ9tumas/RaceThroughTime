--[[
	DataService
	Persistent data management with session locking and client sync.
	Uses Knit framework and ProfileStore for data persistence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

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
		Points = 0,
		Rebirths = 0,
		Fuel = 0, -- Starting fuel for players
		Stars = 0,  -- Total star equivalents collected (used to calculate fuel)
		LauncherLevel = 1, -- Launcher level for fuel-to-distance multiplier
		MaxDistanceTraveled = 0, -- Maximum distance ever traveled in a single track run
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
		ConsumedPotions = {},
		-- Potions stores collectible potion items:
		-- { PotionKey: string, Quantity: number }
		Potions = {},
	},
	Meta = {
		DailyStreak = 0,
		LastClaim = 0,
		CollectedRewards = {}, -- Tracks which daily reward IDs have been collected
		RedeemedCodes = {}, -- Tracks which codes have been redeemed by the player
		UpdateVersion = 0,
		Settings = {
			Music = true,
			SFX = true,
			HidePets = false,
			TradingEnabled = true,
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
	-- PetService:InitializePets(player) -- Respawns pets, moved to TryResolveSession
	
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
						
						-- Cap max velocity on load
						petCopy.Velocity = math.min(petCopy.Velocity or 20, statsM.MaxPetSpeed)

						-- Cap max roam range on load
						petCopy.RoamRange = math.min(petCopy.RoamRange or 30, statsM.MaxPetRoamRange)

						-- Cap max pickup range bonus on load
						petCopy.PickupRangeBonus = math.min(petCopy.PickupRangeBonus or 1.0, statsM.MaxPickupRangeBonus)

						-- Cap max star collection radius on load
						petCopy.StarCollectionRadius = math.min(petCopy.StarCollectionRadius or 5, statsM.MaxStarCollectionRadius)
						
						
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

		-- Initialize pets once when session is resolved
		local PetService = Knit.GetService("PetService")
		PetService:InitializePets(player)
		
		-- Initialize consumed potions and potion inventory from saved data
		local PotionsService = Knit.GetService("PotionsService")
		local potionsData = profile.Data.Inventory and profile.Data.Inventory.ConsumedPotions
		PotionsService:InitializePotions(player, potionsData)
		local potionInventoryData = profile.Data.Inventory and profile.Data.Inventory.Potions
		PotionsService:InitializePotionInventory(player, potionInventoryData)

		local dataToSend = setupPets(player, profile.Data)
		
		DataService.Client.DataReady:Fire(player, dataToSend)
		sessionPromise.resolve()
		sessionPromise.resolve = nil -- Prevent double resolution

		local LauncherService = Knit.GetService("LauncherService")
		LauncherService:FireUpdateLauncherClient(player)
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

		local worldName = profile.Data.Progression.CurrentWorld
		local folder = workspace:FindFirstChild(worldName)
		-- in case there is an invalid world we default to main
		if not folder then
			folder = workspace:FindFirstChild("Main")
			profile.Data.Progression.CurrentWorld = "Main"
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

-- Get the player's current world (defaults to nil)
function DataService:GetPlayerWorld(player: Player): string
	local profile = PlayerProfiles[player]
	if not profile then
		return nil
	end
	
	local progression = profile.Data.Progression
	if not progression or not progression.CurrentWorld then
		return nil
	end
	
	-- Validate that the world name exists in game configuration
	return progression.CurrentWorld
end

-- Deep copy helper function for creating read-only data copies
local function DeepCopy(original)
	if type(original) ~= "table" then
		return original
	end
	
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = DeepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

--[[
	Get a deep copy of the player's data (for sending to client or world switching).
	This includes pet IDs injected for the client.
	
	@param player Player - The player to get data for
	@return table? - A deep copy of the player's data, or nil if no profile
]]
function DataService:GetPlayerData(player: Player): any?
	local profile = PlayerProfiles[player]
	if not profile then
		return nil
	end
	
	-- Use setupPets to create the data copy with pet IDs injected
	return setupPets(player, profile.Data)
end

--[[
	Fire the DataReady signal to the client with properly prepared data.
	This function automatically loads pet information (including IDs) and
	sends the complete data to the client.
	
	Use this function instead of directly calling DataReady:Fire() to ensure
	pet IDs and other session-specific data are always included.
	
	@param player Player - The player to send data to
	@return boolean - True if data was sent successfully, false if no profile found
]]
function DataService:FireDataReady(player: Player): boolean
	local dataToSend = self:GetPlayerData(player)
	if not dataToSend then
		warn(string.format("[DataService]: Cannot fire DataReady for %s - no profile found", player.Name))
		return false
	end
	
	self.Client.DataReady:Fire(player, dataToSend)
	
	-- Also fire UpdateLauncherClient to update launcher UI
	local LauncherService = Knit.GetService("LauncherService")
	if LauncherService then
		LauncherService:FireUpdateLauncherClient(player)
	end
	
	return true
end

--[[
	Client request to fetch their own data (read-only deep copy).
	Clients can only fetch their own data.
	
	@param player Player - The player requesting their data
	@return table? - A deep copy of the player's data, or nil if not loaded
]]
function DataService.Client:FetchData(player: Player): any?
	return DataService:GetPlayerData(player)
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
