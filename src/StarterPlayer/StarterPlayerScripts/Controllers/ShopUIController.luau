local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		}
	},
}


export type ShopUIStructure = typeof(UI)
local _connections = {}

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
		-- auto hatch, etc. look into egg controller.
		EggService:PurchaseEgg("BestFriendEgg")
	end)


	-- currency purchases
	_connections["MediumCashPack"] = UI.Frames.Currency.MediumCashPack.TextButton.MouseButton1Click:Connect(function()
		-- dev product purchase
	end)
end

return ShopUIController
