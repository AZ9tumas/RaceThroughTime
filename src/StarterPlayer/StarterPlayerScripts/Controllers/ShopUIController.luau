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

local shopButton: TextButton
local shopMain: Frame
local shopCloseButton: TextButton
local standardEggBuy: TextButton
local eggHatchScreenGui: ScreenGui
local eggHatchDimmer: Frame
local eggviewport: ViewportFrame
local eggHatchFlash: Frame?

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
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local uiShop: ScreenGui = PlayerGui:WaitForChild("UI_Shop")
	local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
	shopButton = leftPanel:WaitForChild("ShopButton")
	shopMain = uiShop:WaitForChild("MainFrame")
	shopCloseButton = shopMain:WaitForChild("Close")
	local shopEggsContainer = shopMain:WaitForChild("ScrollingFrame"):WaitForChild("Eggs"):WaitForChild("MainFrame")
	standardEggBuy = shopEggsContainer:WaitForChild("StandardEgg"):WaitForChild("Buy")
	eggHatchScreenGui = PlayerGui:WaitForChild("EggHatchScreen")
	eggHatchDimmer = eggHatchScreenGui:WaitForChild("Dimmer")
	eggviewport = eggHatchDimmer:WaitForChild("Viewport")
	eggHatchFlash = eggHatchScreenGui:FindFirstChild("Flash")
end

function ShopUIController:KnitStart()
	local EggService = Knit.GetService("EggService")
	local UIController = Knit.GetController("UIController")
	local InventoryUIController = Knit.GetController("InventoryUIController")
	local UIFramesController = Knit.GetController("UIFramesController")
	local MonetizationController = Knit.GetController("MonetizationController")

	_connections["ShopButton"] = shopButton.MouseButton1Click:Connect(function()
		self:ToggleShop()
	end)

	_connections["ShopClose"] = shopCloseButton.MouseButton1Click:Connect(function()
		self:CloseShop()
	end)

	_connections["StandardEggBuy"] = standardEggBuy.MouseButton1Click:Connect(function()
		if EggHatchAnimation.IsPlaying() then
			return
		end
		
		local hasInstantHatch = MonetizationController and MonetizationController:HasGamePass("InstantHatch")
		
		if hasInstantHatch then
			EggService:RequestPurchaseEgg("StandardEgg"):andThen(function(success, errorMsg, petInfo)
				if success and petInfo then
					local data = UIController:GetData()
					if not data.Inventory.PetInventory then
						data.Inventory.PetInventory = {}
					end
					table.insert(data.Inventory.PetInventory, petInfo)
					if InventoryUIController then
						InventoryUIController:UpdatePetsInventory()
					end
				end
			end)
		else
			UIFramesController:DisableFrames(true)
			eggviewport.Parent.Visible = true
			EggHatchAnimation.PlayHatch(
				eggviewport,
				"StandardEgg",
				eggHatchDimmer,
				eggHatchFlash,
				function(animationSuccess)
					if animationSuccess then
						EggService:RequestPurchaseEgg("StandardEgg"):andThen(function(success, errorMsg, petInfo)
							if success and petInfo then
								local data = UIController:GetData()
								if not data.Inventory.PetInventory then
									data.Inventory.PetInventory = {}
								end
								table.insert(data.Inventory.PetInventory, petInfo)
								if InventoryUIController then
									InventoryUIController:UpdatePetsInventory()
								end
							end
						end)
					end
					eggviewport.Parent.Visible = false
					UIFramesController:DisableFrames(false)
				end
			)
		end
	end)
end

return ShopUIController
