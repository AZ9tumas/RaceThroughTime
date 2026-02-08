local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

local InventoryUIController = Knit.CreateController({
	Name = "InventoryUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local DefaultBackgroundColorSelected = Color3.fromRGB(61, 61, 61)
local DefaultBackgroundColorNotSelected = Color3.fromRGB(20, 23, 28)

local petsButton: TextButton
local inventoryMainFrame: Frame
local inventoryPetCount: TextLabel
local inventoryItemCount: TextLabel
local inventoryScrollingFrame: ScrollingFrame
local inventoryPetTemplate: Frame
local inventoryCloseButton: TextButton

local _connections = {}

function InventoryUIController:GetBackgroundColors()
	return {
		Selected = DefaultBackgroundColorSelected,
		NotSelected = DefaultBackgroundColorNotSelected,
	}
end

function InventoryUIController:UpdatePetsInventory()
	for _, child in ipairs(inventoryScrollingFrame:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and (child:IsA("Frame") or child:IsA("TextButton")) then
			child:Destroy()
		end
	end
	local UIController = Knit.GetController("UIController")
	local PetModalUIController = Knit.GetController("PetModalUIController")
	local MonetizationController = Knit.GetController("MonetizationController")
	local data = UIController:GetData()
	local petInventory = data.Inventory.PetInventory
	local equippedPets = data.Inventory.EquippedPets or {}
	local equippedSet = {}
	for _, petIndex in ipairs(equippedPets) do
		equippedSet[petIndex] = true
	end
	-- Calculate max equipped pets based on gamepass
	local maxEquipped = statsM.MaxEquippedPets
	warn(MonetizationController:HasGamePass("ExtraPets"), "ExtraPets")
	if MonetizationController:HasGamePass("ExtraPets") then
		maxEquipped = maxEquipped + statsM.ExtraPetsBonus
	end
	inventoryPetCount.Count.Text = #equippedPets .. "/" .. maxEquipped
	
	-- Update inventory item count (total pets in inventory)
	local maxInventory = statsM.MaxPetInventory
	if MonetizationController:HasGamePass("ExtraSlots") then
		maxInventory = maxInventory + statsM.ExtraSlotsBonus
	end
	inventoryItemCount.Count.Text = #petInventory .. "/" .. maxInventory
	for index, petData in ipairs(petInventory) do
		local petFrame = inventoryPetTemplate:Clone()
		petFrame.Name = "Pet_" .. index
		petFrame.Visible = true
		local nameLabel = petFrame:FindFirstChild("PetName")
		if nameLabel then
			nameLabel.Text = petData.Name or "Unknown Pet"
		end
		local multiplierFrame = petFrame:FindFirstChild("Multiplier")
		if multiplierFrame then
			local multiplierLabel = multiplierFrame:FindFirstChild("TextLabel")
			if multiplierLabel then
				multiplierLabel.Text = string.format("x%.1f", petData.Multiplier or 1.0)
			end
		end
		local isEquipped = equippedSet[index] == true
		petFrame.UIStroke.Color = statsM.TierColors[petData.TierLevel]
		if isEquipped then
			petFrame.BackgroundColor3 = DefaultBackgroundColorSelected
		else
			petFrame.BackgroundColor3 = DefaultBackgroundColorNotSelected
		end
		local fullPetData = {
			ID = petData.ID,
			Name = petData.Name,
			Multiplier = petData.Multiplier,
			PickupRangeBonus = petData.PickupRangeBonus,
			RoamRange = petData.RoamRange,
			StarCollectionRadius = petData.StarCollectionRadius,
			Velocity = petData.Velocity,
			World = petData.World,
			Level = petData.Level,
			TierLevel = petData.TierLevel,
			TierName = petData.TierName,
			Rarity = petData.Rarity,
			Equipped = isEquipped,
			Index = index,
		}
		if petFrame:IsA("TextButton") then
			petFrame.MouseButton1Click:Connect(function()
				if PetModalUIController then
					PetModalUIController:OpenPetModal(fullPetData)
				end
			end)
		end
		petFrame.Parent = inventoryScrollingFrame
	end
end

function InventoryUIController:ToggleInventory()
	local UIFramesController = Knit.GetController("UIFramesController")
	local wasOpen = UIFramesController:IsFrameOpen("Inventory")
	
	if wasOpen then
		UIFramesController:CloseFrame("Inventory")
	else
		UIFramesController:OpenFrame("Inventory")
		self:UpdatePetsInventory()
	end
end

function InventoryUIController:CloseInventory()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:CloseFrame("Inventory")
end

function InventoryUIController:IsVisible(): boolean
	local UIFramesController = Knit.GetController("UIFramesController")
	return UIFramesController:IsFrameOpen("Inventory")
end

function InventoryUIController:KnitInit()
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local uiInventory: ScreenGui = PlayerGui:WaitForChild("UI_Inventory")
	local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
	petsButton = leftPanel:WaitForChild("PetsButton")
	inventoryMainFrame = uiInventory:WaitForChild("MainFrame")
	inventoryPetCount = inventoryMainFrame:WaitForChild("PetCount")
	inventoryItemCount = inventoryMainFrame:WaitForChild("ItemCount")
	inventoryScrollingFrame = inventoryMainFrame:WaitForChild("ScrollingFrame")
	inventoryPetTemplate = inventoryScrollingFrame:WaitForChild("UIGridLayout"):WaitForChild("Template")
	inventoryCloseButton = inventoryMainFrame:WaitForChild("CloseButton")
end

function InventoryUIController:KnitStart()
	_connections["PetsButton"] = petsButton.MouseButton1Click:Connect(function()
		self:ToggleInventory()
	end)
	_connections["InventoryClose"] = inventoryCloseButton.MouseButton1Click:Connect(function()
		self:CloseInventory()
	end)
end

return InventoryUIController
