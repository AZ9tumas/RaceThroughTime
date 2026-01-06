--[[
	DailyRewardService
	Handles daily reward collection and tracking.
	
	Developers can configure rewards by modifying the REWARD_DATA table below.
	Each reward must have:
	- ID: Unique identifier (must match IDs in ReplicatedStorage.Modules.DailyRewards)
	- Name: Display name shown to player when collected
	- items: Table of items to award { ItemType = "Cash" | "Pet" | "Gems" | "Fuel", Quantity = number, PetId = string? }
	
	USAGE:
	From server - collect reward for a player:
	  local DailyRewardService = Knit.GetService("DailyRewardService")
	  local success, message = DailyRewardService:CollectReward(player)
	
	From client - request to collect reward:
	  local DailyRewardService = Knit.GetService("DailyRewardService")
	  local success, message = DailyRewardService:RequestCollectReward():await()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DailyRewardsConfig = require(ReplicatedStorage.Modules.DailyRewards)

local DailyRewardService = Knit.CreateService({
	Name = "DailyRewardService",
	Client = {},
})

-- Private constants
local SECONDS_IN_DAY = 86400 -- 24 hours in seconds

--[[
	REWARD DATA CONFIGURATION
	Developers: Modify this table to set what rewards players receive.
	
	Each reward entry:
	- ID: Must match an ID from ReplicatedStorage.Modules.DailyRewards.RewardIDs
	- Name: Display name shown when reward is collected
	- items: Array of items to give
	  - ItemType: "Cash" | "Gems" | "Fuel" | "Pet"
	  - Quantity: Amount to give (for Cash/Gems/Fuel)
	  - PetId: (for Pet type) The pet identifier to give
]]
local REWARD_DATA = {
	DAY_1_STARTER = {
		ID = "DAY_1_STARTER",
		Name = "Starter Pack",
		items = {
			{ ItemType = "Cash", Quantity = 100 },
		},
	},
	DAY_2_BONUS = {
		ID = "DAY_2_BONUS",
		Name = "Bonus Cash",
		items = {
			{ ItemType = "Cash", Quantity = 250 },
		},
	},
	DAY_3_BOOST = {
		ID = "DAY_3_BOOST",
		Name = "Fuel Boost",
		items = {
			{ ItemType = "Cash", Quantity = 150 },
			{ ItemType = "Fuel", Quantity = 50 },
		},
	},
	DAY_4_SPECIAL = {
		ID = "DAY_4_SPECIAL",
		Name = "Special Gems",
		items = {
			{ ItemType = "Gems", Quantity = 10 },
		},
	},
	DAY_5_RARE = {
		ID = "DAY_5_RARE",
		Name = "Rare Bundle",
		items = {
			{ ItemType = "Cash", Quantity = 500 },
			{ ItemType = "Gems", Quantity = 15 },
		},
	},
	DAY_6_EPIC = {
		ID = "DAY_6_EPIC",
		Name = "Epic Rewards",
		items = {
			{ ItemType = "Cash", Quantity = 750 },
			{ ItemType = "Fuel", Quantity = 100 },
		},
	},
	DAY_7_LEGENDARY = {
		ID = "DAY_7_LEGENDARY",
		Name = "Legendary Treasure",
		items = {
			{ ItemType = "Cash", Quantity = 1000 },
			{ ItemType = "Gems", Quantity = 50 },
			{ ItemType = "Fuel", Quantity = 200 },
		},
	},
}

-- Helper function for logging
local function Log(message: string)
	print(string.format("[DailyRewardService]: %s", message))
end

-- Get the current day's reward based on player's streak
local function GetCurrentDayRewardID(streak: number): string?
	local totalDays = DailyRewardsConfig.GetTotalDays()
	if totalDays == 0 then return nil end
	
	-- Cycle through rewards (streak wraps around)
	local dayIndex = ((streak - 1) % totalDays) + 1
	return DailyRewardsConfig.GetRewardIDForDay(dayIndex)
end

-- Check if a reward can be collected (24 hours since last claim)
local function CanCollectReward(lastClaim: number): boolean
	local currentTime = os.time()
	return (currentTime - lastClaim) >= SECONDS_IN_DAY
end

-- Check if streak should reset (missed more than 48 hours)
local function ShouldResetStreak(lastClaim: number): boolean
	local currentTime = os.time()
	return (currentTime - lastClaim) >= (SECONDS_IN_DAY * 2)
end

-- Apply reward items to player
local function ApplyRewardItems(player: Player, items: { { ItemType: string, Quantity: number?, PetId: string? } })
	local DataService = Knit.GetService("DataService")
	
	for _, item in ipairs(items) do
		local itemType = item.ItemType
		local quantity = item.Quantity or 0
		
		if itemType == "Cash" then
			DataService:Update(player, "Currencies", function(currencies)
				currencies.Cash = (currencies.Cash or 0) + quantity
				return currencies
			end)
		elseif itemType == "Gems" then
			DataService:Update(player, "Currencies", function(currencies)
				currencies.Gems = (currencies.Gems or 0) + quantity
				return currencies
			end)
		elseif itemType == "Fuel" then
			local Stats = require(ReplicatedStorage.Modules.Stats)
			DataService:Update(player, "Stats", function(stats)
				local maxFuel = Stats.FuelMultiplier()
				stats.Fuel = math.min((stats.Fuel or 0) + quantity, maxFuel)
				return stats
			end)
		elseif itemType == "Pet" and item.PetId then
			DataService:Update(player, "Inventory", function(inventory)
				if not inventory.PetInventory then
					inventory.PetInventory = {}
				end
				-- Add pet with unique ID
				local petEntry = {
					PetId = item.PetId,
					ObtainedAt = os.time(),
				}
				table.insert(inventory.PetInventory, petEntry)
				return inventory
			end)
		end
	end
end

-- Get collected reward IDs for a player
function DailyRewardService:GetCollectedRewards(player: Player): { [string]: boolean }
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.CollectedRewards then
		return meta.CollectedRewards
	end
	return {}
end

-- Get the player's current streak
function DailyRewardService:GetStreak(player: Player): number
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.DailyStreak then
		return meta.DailyStreak
	end
	return 0
end

-- Get the player's last claim time
function DailyRewardService:GetLastClaimTime(player: Player): number
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.LastClaim then
		return meta.LastClaim
	end
	return 0
end

-- Check if player can collect a reward
function DailyRewardService:CanCollect(player: Player): boolean
	local lastClaim = self:GetLastClaimTime(player)
	return CanCollectReward(lastClaim)
end

-- Collect the daily reward for a player
function DailyRewardService:CollectReward(player: Player): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Check if data is loaded
	local meta = DataService:Get(player, "Meta")
	if not meta then
		return false, "Data not loaded"
	end
	
	local lastClaim = meta.LastClaim or 0
	local streak = meta.DailyStreak or 0
	
	-- Check if can collect
	if not CanCollectReward(lastClaim) then
		local timeUntilNext = SECONDS_IN_DAY - (os.time() - lastClaim)
		local hoursLeft = math.floor(timeUntilNext / 3600)
		local minutesLeft = math.floor((timeUntilNext % 3600) / 60)
		return false, string.format("Come back in %dh %dm", hoursLeft, minutesLeft)
	end
	
	-- Check if streak should reset
	if lastClaim > 0 and ShouldResetStreak(lastClaim) then
		streak = 0
		Log(string.format("Streak reset for %s (missed more than 48 hours)", player.Name))
	end
	
	-- Increment streak
	streak = streak + 1
	
	-- Get reward for current day
	local rewardID = GetCurrentDayRewardID(streak)
	if not rewardID then
		return false, "No reward configured"
	end
	
	local rewardData = REWARD_DATA[rewardID]
	if not rewardData then
		return false, "Reward data not found"
	end
	
	-- Apply reward items
	ApplyRewardItems(player, rewardData.items)
	
	-- Update player's meta data
	DataService:Update(player, "Meta", function(metaData)
		metaData.DailyStreak = streak
		metaData.LastClaim = os.time()
		
		-- Track collected rewards
		if not metaData.CollectedRewards then
			metaData.CollectedRewards = {}
		end
		metaData.CollectedRewards[rewardID] = true
		
		return metaData
	end)
	
	-- Notify player
	local rewardName = rewardData.Name
	NotificationService:SendNotification(
		player,
		string.format("Collected: %s (Day %d)", rewardName, streak),
		NotificationService.Category.Success
	)
	
	Log(string.format("%s collected reward '%s' (Day %d streak)", player.Name, rewardName, streak))
	
	return true, rewardName
end

-- Client request to collect reward
function DailyRewardService.Client:RequestCollectReward(player: Player): (boolean, string?)
	return DailyRewardService:CollectReward(player)
end

-- Client request to get current reward status
function DailyRewardService.Client:GetRewardStatus(player: Player): { canCollect: boolean, streak: number, timeUntilNext: number?, currentRewardID: string? }
	local lastClaim = DailyRewardService:GetLastClaimTime(player)
	local streak = DailyRewardService:GetStreak(player)
	local canCollect = DailyRewardService:CanCollect(player)
	
	local timeUntilNext = nil
	if not canCollect then
		timeUntilNext = SECONDS_IN_DAY - (os.time() - lastClaim)
	end
	
	-- Check if streak would reset
	local effectiveStreak = streak
	if lastClaim > 0 and ShouldResetStreak(lastClaim) then
		effectiveStreak = 0
	end
	
	local nextDayStreak = effectiveStreak + 1
	local currentRewardID = GetCurrentDayRewardID(nextDayStreak)
	
	return {
		canCollect = canCollect,
		streak = effectiveStreak,
		timeUntilNext = timeUntilNext,
		currentRewardID = currentRewardID,
	}
end

-- Client request to get collected rewards (IDs only)
function DailyRewardService.Client:GetCollectedRewards(player: Player): { [string]: boolean }
	return DailyRewardService:GetCollectedRewards(player)
end

-- Knit lifecycle
function DailyRewardService:KnitInit()
	Log("DailyRewardService initialized")
end

function DailyRewardService:KnitStart()
	Log("DailyRewardService started")
end

return DailyRewardService
