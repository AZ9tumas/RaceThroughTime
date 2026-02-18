local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local handler = {}

function handler.UpdateDataOnClient(newData)
	local UIController = Knit.GetController("UIController")
	if UIController then
		UIController:SetData(newData)
	end
	local CurrencyUIController = Knit.GetController("CurrencyUIController")
	local DailyRewardsUIController = Knit.GetController("DailyRewardsUIController")
	local ShopUIController = Knit.GetController("ShopUIController")
	local WorldUIController = Knit.GetController("WorldUIController")
	if CurrencyUIController then CurrencyUIController:UpdateAllDisplays() end
	if DailyRewardsUIController then DailyRewardsUIController:UpdateRewardsStatus() end
	if ShopUIController then ShopUIController:UpdateShopUI() end
	if WorldUIController then WorldUIController:UpdateWorlds() end
end

function handler.UpdatePetsInventory()
	local InventoryUIController = Knit.GetController("InventoryUIController")
	if InventoryUIController then
		InventoryUIController:UpdatePetsInventory()
	end
end

function handler.UpdateMergedUI(tierLevel: number, petType: string, world: string)
	local PetModalUIController = Knit.GetController("PetModalUIController")
	if PetModalUIController then
		PetModalUIController:UpdateMergeUI(tierLevel, petType, world)
	end
end

function handler.UpdateWorlds()
	local WorldUIController = Knit.GetController("WorldUIController")
	if WorldUIController then
		WorldUIController:UpdateWorlds()
	end
end

function handler.UpdateStar(amount: number)
	local CurrencyUIController = Knit.GetController("CurrencyUIController")
	if CurrencyUIController then
		CurrencyUIController:UpdateStarCount(amount)
	end
end

function handler.UpdateFuelUI(amount: number)
	local CurrencyUIController = Knit.GetController("CurrencyUIController")
	if CurrencyUIController then
		CurrencyUIController:UpdateFuelUI(amount)
	end
end

function handler.UpdateCashUI(amount: number)
	local CurrencyUIController = Knit.GetController("CurrencyUIController")
	if CurrencyUIController then
		CurrencyUIController:UpdateCashUI(amount)
	end
end

function handler.UpdateGemsUI(amount: number)
	local CurrencyUIController = Knit.GetController("CurrencyUIController")
	if CurrencyUIController then
		CurrencyUIController:UpdateGemsUI(amount)
	end
end

function handler.UpdateShopUI()
	local ShopUIController = Knit.GetController("ShopUIController")
	if ShopUIController then
		ShopUIController:UpdateShopUI()
	end
end

function handler.UpdateRewardsStatus()
	local DailyRewardsUIController = Knit.GetController("DailyRewardsUIController")
	if DailyRewardsUIController then
		DailyRewardsUIController:UpdateRewardsStatus()
	end
end

function handler.ResetTrackDebounce()
	local UIController = Knit.GetController("UIController")
	if UIController then
		UIController:ResetTrackDebounce()
	end
end

setmetatable(handler, {
	__index = function(_, key)
		if key == "data" then
			local UIController = Knit.GetController("UIController")
			if UIController then
				return UIController:GetData()
			end
			return {}
		end
		return nil
	end,
	__newindex = function(_, key, value)
		if key == "data" then
			local UIController = Knit.GetController("UIController")
			if UIController then
				UIController:SetData(value)
			end
		end
	end
})

return handler
