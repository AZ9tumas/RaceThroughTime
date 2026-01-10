--[[
	DailyRewards Module
	Contains daily reward configuration exposed to both client and server.
	
	Developers can configure rewards by modifying the Rewards table below.
	Each reward entry:
	- ID: Unique identifier for the reward
	- Name: Display name shown to player when collected
	- Day: The day number (1-5) this reward is for
	- items: Array of items to give
	  - ItemType: "Cash" | "Gems" | "Fuel" | "Pet"
	  - Quantity: Amount to give (for Cash/Gems/Fuel)
	  - PetId: (for Pet type) The pet identifier to give
]]

local DailyRewards = {}

-- Full reward data exposed to client (5 days to match UI)
DailyRewards.Rewards = {
	{
		ID = "DAY_1_STARTER",
		Name = "Starter Pack",
		Day = 1,
		items = {
			{ ItemType = "Cash", Quantity = 100 },
		},
	},
	{
		ID = "DAY_2_BONUS",
		Name = "Bonus Cash",
		Day = 2,
		items = {
			{ ItemType = "Cash", Quantity = 250 },
		},
	},
	{
		ID = "DAY_3_BOOST",
		Name = "Fuel Boost",
		Day = 3,
		items = {
			{ ItemType = "Cash", Quantity = 150 },
			{ ItemType = "Fuel", Quantity = 50 },
		},
	},
	{
		ID = "DAY_4_SPECIAL",
		Name = "Special Gems",
		Day = 4,
		items = {
			{ ItemType = "Gems", Quantity = 10 },
		},
	},
	{
		ID = "DAY_5_LEGENDARY",
		Name = "Legendary Treasure",
		Day = 5,
		items = {
			{ ItemType = "Cash", Quantity = 1000 },
			{ ItemType = "Gems", Quantity = 50 },
			{ ItemType = "Fuel", Quantity = 200 },
		},
	},
}

-- Total number of days in the reward cycle
function DailyRewards.GetTotalDays(): number
	return #DailyRewards.Rewards
end

-- Get reward ID for a specific day (1-indexed)
function DailyRewards.GetRewardIDForDay(day: number): string?
	if day < 1 or day > #DailyRewards.Rewards then
		return nil
	end
	return DailyRewards.Rewards[day].ID
end

-- Get full reward data for a specific day (1-indexed)
function DailyRewards.GetRewardForDay(day: number)
	if day < 1 or day > #DailyRewards.Rewards then
		return nil
	end
	return DailyRewards.Rewards[day]
end

-- Get reward data by ID
function DailyRewards.GetRewardByID(rewardID: string)
	for _, reward in ipairs(DailyRewards.Rewards) do
		if reward.ID == rewardID then
			return reward
		end
	end
	return nil
end

return DailyRewards
