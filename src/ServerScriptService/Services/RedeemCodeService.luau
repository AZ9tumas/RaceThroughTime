--[[
	RedeemCodeService
	Manages redeemable codes that give players in-game items and currencies.
	
	Codes are defined in RedeemCodeService.Codes (similar to DevProducts pattern).
	Each code has a Name and an OnTrigger function that applies the reward.
	Redeemed codes are persisted in the player's data to prevent re-redemption.
	
	Usage:
	- RedeemCodeService:RedeemCode(player, "ZACH")
	- Client calls RedeemCodeService:RedeemCode("ZACH") via Knit
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local RedeemCodeService = Knit.CreateService({
	Name = "RedeemCodeService",
	Client = {},
})

-- Helper function for logging
local function Log(message: string)
	print(string.format("[RedeemCodeService]: %s", message))
end

-- Code definitions (similar to DevProducts/ServerBonusService.Bonuses pattern)
RedeemCodeService.Codes = {
	ZACH = {
		Name = "ZACH",
		OnTrigger = function(player: Player)
			local DataService = Knit.GetService("DataService")
			local NotificationService = Knit.GetService("NotificationService")

			DataService:Update(player, "Currencies", function(currencies)
				currencies.Cash = (currencies.Cash or 0) + 1500000
				return currencies
			end)

			NotificationService:SendNotification(
				player,
				"Code redeemed! You received 1,500,000 Cash!",
				NotificationService.Category.Success
			)

			DataService:FireDataReady(player)
		end,
	},
}

--[[
	Redeem a code for a player.
	Validates the code exists, checks it hasn't been redeemed before,
	then triggers the reward and saves the redemption.
	
	@param player Player - The player redeeming the code
	@param code string - The code string to redeem
	@return (boolean, string?) - Success status and error message if failed
]]
function RedeemCodeService:RedeemCode(player: Player, code: string): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")

	-- Normalize code to uppercase for case-insensitive matching
	local normalizedCode = string.upper(code)

	-- Check if code exists
	local codeDef = self.Codes[normalizedCode]
	if not codeDef then
		NotificationService:SendNotification(
			player,
			"Invalid code.",
			NotificationService.Category.Error
		)
		return false, "Invalid code"
	end

	-- Check if already redeemed
	local meta = DataService:Get(player, "Meta")
	if not meta then
		NotificationService:SendNotification(
			player,
			"Data not loaded yet. Please try again.",
			NotificationService.Category.Error
		)
		return false, "Data not loaded"
	end

	local redeemedCodes = meta.RedeemedCodes or {}
	if redeemedCodes[normalizedCode] then
		NotificationService:SendNotification(
			player,
			"You have already redeemed this code.",
			NotificationService.Category.Warning
		)
		return false, "Already redeemed"
	end

	-- Trigger the code reward
	local success, err = pcall(function()
		codeDef.OnTrigger(player)
	end)

	if not success then
		warn(string.format("[RedeemCodeService]: Error triggering code '%s' for %s: %s", normalizedCode, player.Name, tostring(err)))
		NotificationService:SendNotification(
			player,
			"Failed to redeem code. Please try again.",
			NotificationService.Category.Error
		)
		return false, "Code trigger failed"
	end

	-- Mark code as redeemed in player data
	DataService:Update(player, "Meta", function(metaData)
		if not metaData.RedeemedCodes then
			metaData.RedeemedCodes = {}
		end
		metaData.RedeemedCodes[normalizedCode] = true
		return metaData
	end)

	Log(string.format("Player %s redeemed code '%s'", player.Name, normalizedCode))

	return true, nil
end

-- Client method to redeem a code
function RedeemCodeService.Client:RedeemCode(player: Player, code: string): (boolean, string?)
	return RedeemCodeService:RedeemCode(player, code)
end

-- Knit lifecycle
function RedeemCodeService:KnitInit()
	Log("RedeemCodeService initialized")
end

function RedeemCodeService:KnitStart()
	Log("RedeemCodeService started")
end

return RedeemCodeService
