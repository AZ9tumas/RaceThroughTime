--[[
	DailyRewards Module
	Contains daily reward configuration and IDs for client access.
	
	This module is accessible by clients but only exposes reward IDs.
	The actual reward data (items, quantities) is defined server-side in DailyRewardService.
	
	Developers can configure rewards by modifying this file:
	- Add new reward IDs to the RewardIDs table
	- The order of IDs determines the day sequence (Day 1, Day 2, etc.)
]]

local DailyRewards = {}

-- Reward IDs exposed to client
-- Developers set these manually - the order determines the day sequence
-- Day 1 = RewardIDs[1], Day 2 = RewardIDs[2], etc.
DailyRewards.RewardIDs = {
	"DAY_1_STARTER",
	"DAY_2_BONUS",
	"DAY_3_BOOST",
	"DAY_4_SPECIAL",
	"DAY_5_RARE",
	"DAY_6_EPIC",
	"DAY_7_LEGENDARY",
}

-- Total number of days in the reward cycle
function DailyRewards.GetTotalDays(): number
	return #DailyRewards.RewardIDs
end

-- Get reward ID for a specific day (1-indexed)
function DailyRewards.GetRewardIDForDay(day: number): string?
	if day < 1 or day > #DailyRewards.RewardIDs then
		return nil
	end
	return DailyRewards.RewardIDs[day]
end

return DailyRewards
