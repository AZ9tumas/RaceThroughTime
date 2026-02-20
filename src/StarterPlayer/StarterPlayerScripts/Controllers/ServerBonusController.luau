--[[
	ServerBonusController - Client-side controller for server bonuses
	
	Maintains a local cache of bonuses for efficiency.
	Syncs with server via BonusUpdated signal.
	
	Usage:
	- ServerBonusController:IsBonusEnabled(BonusName) :: boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ServerBonusController = Knit.CreateController({
	Name = "ServerBonusController",
})

local ServerBonusService = nil

-- Local cache of bonuses for efficiency
local BonusCache: { [string]: boolean } = {}

--[[
	Check if a specific bonus is currently enabled.
	Reads from local cache for efficiency.
	
	@param BonusName string - The name of the bonus (e.g., "LuckParty")
	@return boolean - True if the bonus is enabled
]]
function ServerBonusController:IsBonusEnabled(BonusName: string): boolean
	return BonusCache[BonusName] == true
end

function ServerBonusController:KnitInit()
	ServerBonusService = Knit.GetService("ServerBonusService")
end

function ServerBonusController:KnitStart()
	-- Initial cache hydration from server
	ServerBonusService:GetBonuses():andThen(function(bonuses)
		if bonuses then
			BonusCache = bonuses
		end
	end):catch(warn)
	
	-- Listen for bonus updates from server to keep cache in sync
	ServerBonusService.BonusUpdated:Connect(function(BonusName: string, value: boolean)
		BonusCache[BonusName] = value
	end)
end

return ServerBonusController
