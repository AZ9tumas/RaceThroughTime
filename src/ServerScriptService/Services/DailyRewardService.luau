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

local function Log(message: string)
	--print(string.format("[DailyRewardService]: %s", message))
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
			-- In the new system, fuel is calculated from Stars
			-- Fuel rewards now add to Stars count and recalculate fuel
			DataService:Update(player, "Stats", function(stats)
				stats.Stars = (stats.Stars or 0) + quantity
				return stats
			end)
			-- Recalculate fuel based on new Stars count
			local StarService = Knit.GetService("StarService")
			StarService:RecalculateFuel(player)
		elseif itemType == "Pet" and item.PetId then
			local Stats = require(ReplicatedStorage.Modules.Stats)
			local petConfig = Stats.Pets[item.PetId]
			
			if petConfig then
				DataService:Update(player, "Inventory", function(inventory)
					if not inventory.PetInventory then
						inventory.PetInventory = {}
					end
					-- Add pet with unique ID and full stats
					local petEntry = {}

					for key, val in ipairs(petConfig) do
						petEntry[key] = val
					end

					petEntry.ObtainedAt = os.time()
					table.insert(inventory.PetInventory, petEntry)
					return inventory
				end)
			end
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
		NotificationService:SendNotification(
			player,
			"Data not loaded yet. Please try again.",
			NotificationService.Category.Error
		)
		return false, "Data not loaded"
	end
	
	local lastClaim = meta.LastClaim or 0
	local streak = meta.DailyStreak or 0
	
	-- Check if can collect
	if not CanCollectReward(lastClaim) then
		local timeUntilNext = SECONDS_IN_DAY - (os.time() - lastClaim)
		local hoursLeft = math.floor(timeUntilNext / 3600)
		local minutesLeft = math.floor((timeUntilNext % 3600) / 60)
		NotificationService:SendNotification(
			player,
			string.format("Come back in %dh %dm to claim your next reward!", hoursLeft, minutesLeft),
			NotificationService.Category.Warning
		)
		return false, string.format("Come back in %dh %dm", hoursLeft, minutesLeft)
	end
	
	if lastClaim > 0 and ShouldResetStreak(lastClaim) then
		streak = 0
		Log(string.format("Streak reset for %s (missed more than 48 hours)", player.Name))
	end
	
	streak = streak + 1
	
	-- Get reward from shared config
	local rewardID = GetCurrentDayRewardID(streak)
	if not rewardID then
		NotificationService:SendNotification(
			player,
			"No reward configured for this day.",
			NotificationService.Category.Error
		)
		return false, "No reward configured"
	end
	
	local rewardData = DailyRewardsConfig.GetRewardByID(rewardID)
	if not rewardData then
		NotificationService:SendNotification(
			player,
			"Reward data not found.",
			NotificationService.Category.Error
		)
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

-- Client request to collect reward for a specific day (server handles everything including notifications)
function DailyRewardService.Client:RequestCollectReward(player: Player, requestedDay: number)
	return DailyRewardService:CollectRewardForDay(player, requestedDay)
end

-- Collect reward for a specific day (validates the request)
function DailyRewardService:CollectRewardForDay(player: Player, requestedDay: number): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Validate requestedDay
	if not requestedDay or type(requestedDay) ~= "number" then
		NotificationService:SendNotification(
			player,
			"Invalid reward request.",
			NotificationService.Category.Error
		)
		return false, "Invalid request"
	end
	
	local totalDays = DailyRewardsConfig.GetTotalDays()
	if requestedDay < 1 or requestedDay > totalDays then
		NotificationService:SendNotification(
			player,
			string.format("Invalid day. Choose between 1 and %d.", totalDays),
			NotificationService.Category.Error
		)
		return false, "Invalid day"
	end
	
	local meta = DataService:Get(player, "Meta")
	if not meta then
		NotificationService:SendNotification(
			player,
			"Data not loaded yet. Please try again.",
			NotificationService.Category.Error
		)
		return false, "Data not loaded"
	end
	
	local lastClaim = meta.LastClaim or 0
	local streak = meta.DailyStreak or 0
	
	-- Check if already collected this reward
	local rewardID = DailyRewardsConfig.GetRewardIDForDay(requestedDay)
	if meta.CollectedRewards and meta.CollectedRewards[rewardID] then
		NotificationService:SendNotification(
			player,
			string.format("Day %d reward already redeemed!", requestedDay),
			NotificationService.Category.Warning
		)
		return false, "Already redeemed"
	end
	
	-- Check if can collect (24 hours passed)
	if not CanCollectReward(lastClaim) then
		local timeUntilNext = SECONDS_IN_DAY - (os.time() - lastClaim)
		local hoursLeft = math.floor(timeUntilNext / 3600)
		local minutesLeft = math.floor((timeUntilNext % 3600) / 60)
		NotificationService:SendNotification(
			player,
			string.format("Come back in %dh %dm to claim your next reward!", hoursLeft, minutesLeft),
			NotificationService.Category.Warning
		)
		return false, string.format("Come back in %dh %dm", hoursLeft, minutesLeft)
	end
	
	-- Check if streak should reset
	if lastClaim > 0 and ShouldResetStreak(lastClaim) then
		streak = 0
		Log(string.format("Streak reset for %s (missed more than 48 hours)", player.Name))
	end
	
	-- Calculate expected day (streak + 1)
	local expectedDay = ((streak) % totalDays) + 1
	
	-- Validate that the requested day matches the expected day
	if requestedDay ~= expectedDay then
		NotificationService:SendNotification(
			player,
			string.format("You can only claim Day %d reward right now.", expectedDay),
			NotificationService.Category.Warning
		)
		return false, string.format("Can only claim Day %d", expectedDay)
	end
	
	-- Get reward data
	local rewardData = DailyRewardsConfig.GetRewardForDay(requestedDay)
	if not rewardData then
		NotificationService:SendNotification(
			player,
			"Reward data not found.",
			NotificationService.Category.Error
		)
		return false, "Reward data not found"
	end

	-- Apply reward items
	ApplyRewardItems(player, rewardData.items)
	
	-- Update streak and claim time
	streak = streak + 1
	
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
		string.format("Collected: %s (Day %d)", rewardName, requestedDay),
		NotificationService.Category.Success
	)
	
	Log(string.format("%s collected reward '%s' (Day %d)", player.Name, rewardName, requestedDay))
	
	return true, rewardName
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