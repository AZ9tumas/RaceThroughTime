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

local function Log(message: string)
	print(string.format("[DailyRewardService]: %s", message))
end

local function GetCurrentDayRewardID(streak: number): string?
	local totalDays = DailyRewardsConfig.GetTotalDays()
	if totalDays == 0 then return nil end
	
	local dayIndex = ((streak - 1) % totalDays) + 1
	return DailyRewardsConfig.GetRewardIDForDay(dayIndex)
end

local function CanCollectReward(lastClaim: number): boolean
	local currentTime = os.time()
	return (currentTime - lastClaim) >= SECONDS_IN_DAY
end

-- Check if streak should reset (missed more than 48 hours)
local function ShouldResetStreak(lastClaim: number): boolean
	local currentTime = os.time()
	return (currentTime - lastClaim) >= (SECONDS_IN_DAY * 2)
end

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

function DailyRewardService:GetCollectedRewards(player: Player): { [string]: boolean }
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.CollectedRewards then
		return meta.CollectedRewards
	end
	return {}
end

function DailyRewardService:GetStreak(player: Player): number
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.DailyStreak then
		return meta.DailyStreak
	end
	return 0
end

function DailyRewardService:GetLastClaimTime(player: Player): number
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.LastClaim then
		return meta.LastClaim
	end
	return 0
end

function DailyRewardService:CanCollect(player: Player): boolean
	local lastClaim = self:GetLastClaimTime(player)
	return CanCollectReward(lastClaim)
end

function DailyRewardService:CollectReward(player: Player): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
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
	
	if lastClaim > 0 and ShouldResetStreak(lastClaim) then
		streak = 0
		Log(string.format("Streak reset for %s (missed more than 48 hours)", player.Name))
	end
	
	streak = streak + 1
	
	-- Get reward
	local rewardID = GetCurrentDayRewardID(streak)
	if not rewardID then
		return false, "No reward configured"
	end
	
	local rewardData = REWARD_DATA[rewardID]
	if not rewardData then
		return false, "Reward data not found"
	end

	ApplyRewardItems(player, rewardData.items)
	
	DataService:Update(player, "Meta", function(metaData)
		metaData.DailyStreak = streak
		metaData.LastClaim = os.time()
		
		if not metaData.CollectedRewards then
			metaData.CollectedRewards = {}
		end
		metaData.CollectedRewards[rewardID] = true
		
		return metaData
	end)
	
	local rewardName = rewardData.Name
	NotificationService:SendNotification(
		player,
		string.format("Collected: %s (Day %d)", rewardName, streak),
		NotificationService.Category.Success
	)
	
	Log(string.format("%s collected reward '%s' (Day %d streak)", player.Name, rewardName, streak))
	
	return true, rewardName
end

function DailyRewardService.Client:RequestCollectReward(player: Player): (boolean, string?)
	return DailyRewardService:CollectReward(player)
end

function DailyRewardService.Client:GetRewardStatus(player: Player): { canCollect: boolean, streak: number, timeUntilNext: number?, currentRewardID: string? }
	local lastClaim = DailyRewardService:GetLastClaimTime(player)
	local streak = DailyRewardService:GetStreak(player)
	local canCollect = DailyRewardService:CanCollect(player)
	
	local timeUntilNext = nil
	if not canCollect then
		timeUntilNext = SECONDS_IN_DAY - (os.time() - lastClaim)
	end

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

function DailyRewardService.Client:GetCollectedRewards(player: Player): { [string]: boolean }
	return DailyRewardService:GetCollectedRewards(player)
end

function DailyRewardService:KnitInit()
	Log("DailyRewardService initialized")
end

function DailyRewardService:KnitStart()
	Log("DailyRewardService started")
end

return DailyRewardService