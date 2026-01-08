
local DailyRewards = {}
-- client exposed
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
