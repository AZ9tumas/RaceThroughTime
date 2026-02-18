local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local EggHatchAnimation = require(modules:WaitForChild("EggHatchAnimation"))

local ShopUIController = Knit.CreateController({
	Name = "ShopUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local UI = {
	Buttons = {
		Open = nil,
		Close = nil,
	},
	Frames = {
		Main = nil,
		ScrollingFrame = nil,

		Potions = {
			Frame = nil,
			SuperLuck = nil,
			PointsOverload = nil,
			MagnetPulse = nil,
		},

		EggHatch = {
			Gui = nil,
			Dimmer = nil,
			Viewport = nil,
			Flash = nil,
		},

		Gamepasses = {
			Frame = nil,
			VIPFrame = nil,
			MagnetFrame = nil,
			LuckFrame = nil,
		},

		Currency = {
			Frame = nil,
			-- cash
			MediumCashPack = nil,
			HugeCashPack = nil,

			-- gems
			LargeGemPack = nil,
		},

		Eggs = {
			Frame = nil,

			BestFriendEggFrame = nil,
			PremiumWorldEgg = nil,
			GoldenChronoEgg = nil,
			LimitedHistoricalEgg = nil
		},

		Redeem = {
			Frame = nil,

			RedeemButton = nil,
			TextBox = nil
		}
	},
}


export type ShopUIStructure = typeof(UI)
local _connections = {}

-- Helper: get quantity of a potion from inventory data (Potions array)
local function GetPotionQuantity(potionsArray: {{PotionKey: string, Quantity: number}}?, potionKey: string): number
	if not potionsArray then return 0 end
	for _, entry in ipairs(potionsArray) do
		if entry.PotionKey == potionKey then
			return entry.Quantity or 0
		end
	end
	return 0
end

-- Update all potion UseButton labels from the given inventory data
local function UpdatePotionUseButtons(potionsArray: {{PotionKey: string, Quantity: number}}?)
	local potionFrames = {
		{ key = "SuperLuck",      frame = UI.Frames.Potions.SuperLuck },
		{ key = "PointsOverload", frame = UI.Frames.Potions.PointsOverload },
		{ key = "MagnetPulse",    frame = UI.Frames.Potions.MagnetPulse },
	}
	for _, info in ipairs(potionFrames) do
		local qty = GetPotionQuantity(potionsArray, info.key)
		local useBtn = info.frame and info.frame:FindFirstChild("UseButton")
		if useBtn then
			useBtn.Text = "USE (" .. qty .. ")"
		end
	end
end

function ShopUIController:UpdateShopUI()
end

function ShopUIController:ToggleShop()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:ToggleFrame("Shop")
end

function ShopUIController:CloseShop()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:CloseFrame("Shop")
end

function ShopUIController:KnitInit()
	local mainUi = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local uiShop = PlayerGui:WaitForChild("UI_Shop")
	local leftPanel = mainUi:WaitForChild("LeftPanel")

	UI.Buttons.Open = leftPanel:WaitForChild("ShopButton")
	UI.Frames.Main = uiShop:WaitForChild("MainFrame")
	UI.Frames.ScrollingFrame = UI.Frames.Main:WaitForChild("ScrollingFrame")
	UI.Buttons.Close = UI.Frames.Main:WaitForChild("Close")

	UI.Frames.EggHatch.Gui = PlayerGui:WaitForChild("EggHatchScreen")
	UI.Frames.EggHatch.Dimmer = UI.Frames.EggHatch.Gui:WaitForChild("Dimmer")
	UI.Frames.EggHatch.Viewport = UI.Frames.EggHatch.Dimmer:WaitForChild("Viewport")
	UI.Frames.EggHatch.Flash = UI.Frames.EggHatch.Gui:FindFirstChild("Flash")

	-- init gamepasses
	UI.Frames.Gamepasses.Frame = UI.Frames.ScrollingFrame:WaitForChild("Gamepasses"):WaitForChild("MainFrame")
	UI.Frames.Gamepasses.VIPFrame = UI.Frames.Gamepasses.Frame:WaitForChild("VIP")
	UI.Frames.Gamepasses.MagnetFrame = UI.Frames.Gamepasses.Frame:WaitForChild("Magnet")
	UI.Frames.Gamepasses.LuckFrame = UI.Frames.Gamepasses.Frame:WaitForChild("Luck")

	-- currency
	UI.Frames.Currency.Frame = UI.Frames.ScrollingFrame:WaitForChild("Currency"):WaitForChild("MainFrame")
	UI.Frames.Currency.MediumCashPack = UI.Frames.Currency.Frame:WaitForChild("MediumCashPack")
	UI.Frames.Currency.HugeCashPack = UI.Frames.Currency.Frame:WaitForChild("HugeCashPack")
	UI.Frames.Currency.LargeGemPack = UI.Frames.Currency.Frame:WaitForChild("LargeGemPack")

	-- eggs
	UI.Frames.Eggs.Frame = UI.Frames.ScrollingFrame:WaitForChild("Eggs"):WaitForChild("MainFrame")
	UI.Frames.Eggs.BestFriendEggFrame = UI.Frames.Eggs.Frame:WaitForChild("BestFriendEgg")
	UI.Frames.Eggs.PremiumWorldEgg = UI.Frames.Eggs.Frame:WaitForChild("PremiumWorldEgg")
	UI.Frames.Eggs.GoldenChronoEgg = UI.Frames.Eggs.Frame:WaitForChild("GoldenChronoEgg")
	UI.Frames.Eggs.LimitedHistoricalEgg = UI.Frames.Eggs.Frame:WaitForChild("LimitedHistoricalEgg")

	-- potions
	UI.Frames.Potions.Frame = UI.Frames.ScrollingFrame:WaitForChild("Potions"):WaitForChild("MainFrame")
	UI.Frames.Potions.SuperLuck = UI.Frames.Potions.Frame:WaitForChild("SuperLuck")
	UI.Frames.Potions.PointsOverload = UI.Frames.Potions.Frame:WaitForChild("PointsOverload")
	UI.Frames.Potions.MagnetPulse = UI.Frames.Potions.Frame:WaitForChild("MagnetPulse")

	-- redeem
	UI.Frames.Redeem.Frame = UI.Frames.ScrollingFrame:WaitForChild("Redeem"):WaitForChild("MainFrame")
	UI.Frames.Redeem.RedeemButton = UI.Frames.Redeem.Frame:WaitForChild("RedeemButton")
	UI.Frames.Redeem.TextBox = UI.Frames.Redeem.Frame:WaitForChild("CodeTextBox")
end

function ShopUIController:KnitStart()
	local EggService = Knit.GetService("EggService")
	local UIController = Knit.GetController("UIController")
	local InventoryUIController = Knit.GetController("InventoryUIController")
	local UIFramesController = Knit.GetController("UIFramesController")
	local MonetizationController = Knit.GetController("MonetizationController")

	_connections["ShopButton"] = UI.Buttons.Open.MouseButton1Click:Connect(function()
		self:ToggleShop()
	end)

	_connections["ShopClose"] = UI.Buttons.Close.MouseButton1Click:Connect(function()
		self:CloseShop()
	end)

	-- all the egg frames work the same way
	_connections["BestFriendEgg"] = UI.Frames.Eggs.BestFriendEggFrame.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("BestFriendEgg"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["LimitedHistoricalEgg"] = UI.Frames.Eggs.LimitedHistoricalEgg.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("LimitedHistoricalEgg"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["PremiumWorldEgg"] = UI.Frames.Eggs.PremiumWorldEgg.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("PremiumWorldEgg"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["GoldenChronoEgg"] = UI.Frames.Eggs.GoldenChronoEgg.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("GoldenChronoEgg"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	-- currency purchases
	_connections["MediumCashPack"] = UI.Frames.Currency.MediumCashPack.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("MediumCashPack"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["HugeCashPack"] = UI.Frames.Currency.HugeCashPack.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("HugeCashPack"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["LargeGemPack"] = UI.Frames.Currency.LargeGemPack.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("LargeGemPack"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["SuperLuck"] = UI.Frames.Potions.SuperLuck.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("SuperLuck"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["UseSuperLuck"] = UI.Frames.Potions.SuperLuck.UseButton.MouseButton1Click:Connect(function()
		local PotionsService = Knit.GetService("PotionsService")
		PotionsService:ConsumePotion("SuperLuck")
	end)

	_connections["PointsOverload"] = UI.Frames.Potions.PointsOverload.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("PointsOverload"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["MagnetPulse"] = UI.Frames.Potions.MagnetPulse.TextButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("MagnetPulse"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	_connections["UsePointsOverload"] = UI.Frames.Potions.PointsOverload.UseButton.MouseButton1Click:Connect(function()
		local PotionsService = Knit.GetService("PotionsService")
		PotionsService:ConsumePotion("PointsOverload")
	end)

	_connections["UseMagnetPulse"] = UI.Frames.Potions.MagnetPulse.UseButton.MouseButton1Click:Connect(function()
		local PotionsService = Knit.GetService("PotionsService")
		PotionsService:ConsumePotion("MagnetPulse")
	end)

	-- redeem button setup
	_connections["RedeemButton"] = UI.Frames.Redeem.RedeemButton.MouseButton1Click:Connect(function()
		local text = UI.Frames.Redeem.TextBox.Text
		if text == "" then return end

		local RedeemCodeService = Knit.GetService("RedeemCodeService")
		RedeemCodeService:RedeemCode(text)
		UI.Frames.Redeem.TextBox.Text = ""
	end)

	-- get gamepasses
	_connections["VIPGamepass"] = UI.Frames.Gamepasses.VIPFrame.TextButton.MouseButton1Click:Connect(function()
		MonetizationController:PromptPurchase("VIP")
	end)

	_connections["MagnetGamepass"] = UI.Frames.Gamepasses.MagnetFrame.TextButton.MouseButton1Click:Connect(function()
		MonetizationController:PromptPurchase("Magnet")
	end)

	_connections["LuckGamepass"] = UI.Frames.Gamepasses.LuckFrame.TextButton.MouseButton1Click:Connect(function()
		MonetizationController:PromptPurchase("Luck")
	end)

	-- Listen for data updates to refresh potion UseButton labels
	local DataService = Knit.GetService("DataService")
	_connections["PotionDataReady"] = DataService.DataReady:Connect(function(newData)
		local potionsArray = newData and newData.Inventory and newData.Inventory.Potions
		UpdatePotionUseButtons(potionsArray)
	end)

	-- Initial update from cached data
	local data = UIController:GetData()
	if data and data.Inventory then
		UpdatePotionUseButtons(data.Inventory.Potions)
	end
end

return ShopUIController