--[[
	ServerBonusService
	Manages global server bonuses that affect gameplay mechanics.
	
	Usage:
	- ServerBonusService:IsBonusEnabled(BonusName) :: boolean
	- ServerBonusService:UpdateBonus(BonusName, value) :: updates the bonus and notifies clients
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ServerBonusService = Knit.CreateService({
	Name = "ServerBonusService",
	Client = {
		BonusUpdated = Knit.CreateSignal(), -- Signal to notify clients when a bonus changes
	},
})

-- Global bonuses table
local Bonuses: { [string]: boolean } = {
	LuckParty = false,
}

-- Helper function for logging
local function Log(message: string)
	print(string.format("[ServerBonusService]: %s", message))
end

--[[
	Check if a specific bonus is currently enabled.
	
	@param BonusName string - The name of the bonus (e.g., "LuckParty")
	@return boolean - True if the bonus is enabled
]]
function ServerBonusService:IsBonusEnabled(BonusName: string): boolean
	return Bonuses[BonusName] == true
end

--[[
	Update a bonus value and notify all clients.
	
	@param BonusName string - The name of the bonus (e.g., "LuckParty")
	@param value boolean - Whether the bonus should be enabled or disabled
]]
function ServerBonusService:UpdateBonus(BonusName: string, value: boolean)
	Bonuses[BonusName] = value
	Log(string.format("Bonus '%s' updated to %s", BonusName, tostring(value)))
	
	-- Notify all clients about the bonus change
	ServerBonusService.Client.BonusUpdated:FireAll(BonusName, value)
end

-- Client method to get all current bonuses (for initial cache hydration)
function ServerBonusService.Client:GetBonuses(_player: Player): { [string]: boolean }
	return Bonuses
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
