--[[
	ServerBonusService
	Manages global server bonuses that affect gameplay mechanics.
	
	Bonuses are defined in ServerBonusService.Bonuses (similar to DevProducts pattern).
	Each bonus has a Name, Duration (expiry in seconds), and an Enabled state.
	
	Usage:
	- ServerBonusService:EnableBonus(ServerBonusService.Bonuses.LuckParty)
	- ServerBonusService:DisableBonus(ServerBonusService.Bonuses.LuckParty)
	- ServerBonusService:IsBonusEnabled("LuckParty") :: boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ServerBonusService = Knit.CreateService({
	Name = "ServerBonusService",
	Client = {
		BonusUpdated = Knit.CreateSignal(), -- Signal to notify clients when a bonus changes
	},
})

-- Helper function for logging
local function Log(message: string)
	print(string.format("[ServerBonusService]: %s", message))
end

-- Bonus definitions (similar to DevProducts/PotionDefinitions pattern)
ServerBonusService.Bonuses = {
	LuckParty = {
		Name = "Server Luck Party",
		Duration = 2 * 60, -- 2 minutes in seconds
		OnEnabled = function()
			local def = ServerBonusService.Bonuses.LuckParty
			Log(string.format("%s enabled! Will expire in %d seconds.", def.Name, def.Duration))
			
			-- Cancel any existing timer to prevent overlapping expiries
			NextTimerId = NextTimerId + 1
			local timerId = NextTimerId
			ExpiryTimers["LuckParty"] = timerId
			
			task.delay(def.Duration, function()
				if ExpiryTimers["LuckParty"] == timerId and ServerBonusService:IsBonusEnabled("LuckParty") then
					ServerBonusService:DisableBonus(ServerBonusService.Bonuses.LuckParty)
				end
			end)
		end,
	},
	PointsParty = {
		Name = "Server Points Party",
		Duration = 2 * 60, -- 2 minutes in seconds
		OnEnabled = function()
			local def = ServerBonusService.Bonuses.PointsParty
			Log(string.format("%s enabled! Will expire in %d seconds.", def.Name, def.Duration))
			
			-- Cancel any existing timer to prevent overlapping expiries
			NextTimerId = NextTimerId + 1
			local timerId = NextTimerId
			ExpiryTimers["PointsParty"] = timerId
			
			task.delay(def.Duration, function()
				if ExpiryTimers["PointsParty"] == timerId and ServerBonusService:IsBonusEnabled("PointsParty") then
					ServerBonusService:DisableBonus(ServerBonusService.Bonuses.PointsParty)
				end
			end)
		end,
	},
}

-- Active bonus states (runtime)
local ActiveBonuses: { [string]: boolean } = {}

-- Track expiry timers to prevent race conditions from overlapping enables
local ExpiryTimers: { [string]: number } = {}
local NextTimerId = 0

-- Helper to find bonus key from bonus definition
local function GetBonusKey(bonusDef: { Name: string }): string?
	for key, def in pairs(ServerBonusService.Bonuses) do
		if def == bonusDef then
			return key
		end
	end
	return nil
end

--[[
	Check if a specific bonus is currently enabled.
	
	@param BonusName string - The key name of the bonus (e.g., "LuckParty")
	@return boolean - True if the bonus is enabled
]]
function ServerBonusService:IsBonusEnabled(BonusName: string): boolean
	return ActiveBonuses[BonusName] == true
end

--[[
	Enable a bonus and notify all clients.
	
	@param bonusDef table - The bonus definition from ServerBonusService.Bonuses
]]
function ServerBonusService:EnableBonus(bonusDef: { Name: string, Duration: number, OnEnabled: (() -> ())? })
	local key = GetBonusKey(bonusDef)
	if not key then
		warn("[ServerBonusService]: Unknown bonus definition passed to EnableBonus")
		return
	end
	
	ActiveBonuses[key] = true
	Log(string.format("Bonus '%s' (%s) enabled", key, bonusDef.Name))
	
	-- Notify all clients about the bonus change
	ServerBonusService.Client.BonusUpdated:FireAll(key, true)
	
	-- Run OnEnabled callback if defined
	if bonusDef.OnEnabled then
		bonusDef.OnEnabled()
	end
end

--[[
	Disable a bonus and notify all clients.
	
	@param bonusDef table - The bonus definition from ServerBonusService.Bonuses
]]
function ServerBonusService:DisableBonus(bonusDef: { Name: string, Duration: number })
	local key = GetBonusKey(bonusDef)
	if not key then
		warn("[ServerBonusService]: Unknown bonus definition passed to DisableBonus")
		return
	end
	
	ActiveBonuses[key] = false
	Log(string.format("Bonus '%s' (%s) disabled", key, bonusDef.Name))
	
	-- Notify all clients about the bonus change
	ServerBonusService.Client.BonusUpdated:FireAll(key, false)
end

-- Client method to get all current bonus states (for initial cache hydration)
function ServerBonusService.Client:GetBonuses(_player: Player): { [string]: boolean }
	return ActiveBonuses
end

-- Client method to check if a bonus is enabled
function ServerBonusService.Client:IsBonusEnabled(_player: Player, BonusName: string): boolean
	return ServerBonusService:IsBonusEnabled(BonusName)
end

-- Knit lifecycle
function ServerBonusService:KnitInit()
	Log("ServerBonusService initialized")
end

function ServerBonusService:KnitStart()
	Log("ServerBonusService started")
end

return ServerBonusService
