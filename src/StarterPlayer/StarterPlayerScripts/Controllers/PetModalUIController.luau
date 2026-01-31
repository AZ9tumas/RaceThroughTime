local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))
local petMergeStatsM = require(modules:WaitForChild("PetMergeStats"))

local PetModalUIController = Knit.CreateController({
	Name = "PetModalUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local DefaultBackgroundColorSelected = Color3.fromRGB(61, 61, 61)
local DefaultBackgroundColorNotSelected = Color3.fromRGB(20, 23, 28)

local uiPetModal: ScreenGui
local petModalDarkOverlay: Frame
local petModalMainFrame: Frame
local petModalCloseButton: TextButton
local petModalEquipButton: TextButton
local petModalEquipEmoji: TextLabel
local petModalEquipLabel: TextLabel
local petModalMergeButton: TextButton
local petModalMultiplier: TextLabel

local uiMerge: ScreenGui
local mergeMainFrame: Frame
local mergePetGrid: Frame
local mergePetTemplate: TextButton
local mergeRightPanel: Frame
local mergeCountLabel: TextLabel
local mergeButton: TextButton
local selectAllButton: TextButton
local mergeCloseButton: TextButton

local mergeSelectedPetID: string? = nil
local mergeSelectedPets: { [number]: boolean } = {}
local mergeSelectedCount: number = 0
local mergeRequiredCopies: number = 0
local mergePetName: string? = nil
local mergePetConnections: { RBXScriptConnection } = {}

local selectedPetData = nil
local _connections = {}

local function UpdatePetModalEquipButton(isEquipped: boolean)
	if isEquipped then
		petModalEquipEmoji.Text = "❌"
		petModalEquipLabel.Text = "Unequip"
		petModalEquipButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
	else
		petModalEquipEmoji.Text = "✅"
		petModalEquipLabel.Text = "Equip"
		petModalEquipButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	end
end

function PetModalUIController:OpenPetModal(petData)
	selectedPetData = petData
	petModalMultiplier.Text = string.format("x%.1f Multiplier", petData.Multiplier or 1.0)
	UpdatePetModalEquipButton(petData.Equipped or false)
	petModalDarkOverlay.Visible = true
end

function PetModalUIController:ClosePetModal()
	petModalDarkOverlay.Visible = false
	selectedPetData = nil
end

function PetModalUIController:GetSelectedPetData()
	return selectedPetData
end

local function UpdateMergeCountLabel()
	mergeCountLabel.Text = mergeSelectedCount .. "/" .. mergeRequiredCopies
end

local function ToggleMergePetSelection(petIndex: number, petFrame: TextButton)
	if mergeSelectedPets[petIndex] then
		mergeSelectedPets[petIndex] = nil
		mergeSelectedCount = mergeSelectedCount - 1
		petFrame.UIStroke.Color = Color3.fromRGB(49, 49, 49)
	else
		if mergeSelectedCount < mergeRequiredCopies then
			mergeSelectedPets[petIndex] = true
			mergeSelectedCount = mergeSelectedCount + 1
			petFrame.UIStroke.Color = Color3.fromRGB(0, 255, 0)
		end
	end
	UpdateMergeCountLabel()
end

function PetModalUIController:UpdateMergeUI(petID: string)
	for _, connection in ipairs(mergePetConnections) do
		connection:Disconnect()
	end
	mergePetConnections = {}
	for _, child in ipairs(mergePetGrid:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and (child:IsA("Frame") or child:IsA("TextButton")) then
			child:Destroy()
		end
	end
	mergeSelectedPets = {}
	mergeSelectedCount = 0
	mergeSelectedPetID = petID
	local UIController = Knit.GetController("UIController")
	local data = UIController:GetData()
	local petInventory = data.Inventory.PetInventory
	local targetPet = nil
	for _, petData in ipairs(petInventory) do
		if petData.ID == petID then
			targetPet = petData
			break
		end
	end
	if not targetPet then
		return
	end
	mergePetName = targetPet.Name
	local matchingPets = {}
	for index, petData in ipairs(petInventory) do
		if petData.TierLevel == targetPet.TierLevel then
			table.insert(matchingPets, { index = index, petData = petData })
		end
	end
	local tierLevel = targetPet.TierLevel or targetPet.Level or 1
	mergeRequiredCopies = petMergeStatsM.GetCopiesRequired(tierLevel)
	local gemCost = petMergeStatsM.GetMergeCost(tierLevel)
	mergeButton.Text = "MERGE\n(" .. gemCost .. " GEMS)"
	UpdateMergeCountLabel()
	for _, petInfo in ipairs(matchingPets) do
		local petFrame = mergePetTemplate:Clone()
		petFrame.Name = "MergePet_" .. petInfo.index
		petFrame.Visible = true
		local nameLabel = petFrame:FindFirstChild("Name")
		if nameLabel then
			nameLabel.Text = petInfo.petData.Name or "Unknown Pet"
		end
		local multiplier: TextLabel = petFrame:FindFirstChild("Multiplier")
		if multiplier then
			multiplier.Text = "x" .. petInfo.petData.Multiplier
		end
		local petIndex = petInfo.index
		if petFrame:IsA("TextButton") then
			local connection = petFrame.MouseButton1Click:Connect(function()
				ToggleMergePetSelection(petIndex, petFrame)
			end)
			table.insert(mergePetConnections, connection)
		end
		petFrame.Parent = mergePetGrid
	end
	uiMerge.Enabled = true
	mergeMainFrame.Visible = true
end

local function SelectAllMergePets()
	mergeSelectedPets = {}
	mergeSelectedCount = 0
	local selectedSoFar = 0
	for _, child in ipairs(mergePetGrid:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and child:IsA("TextButton") then
			if selectedSoFar < mergeRequiredCopies then
				local petIndex = tonumber(child.Name:match("MergePet_(%d+)"))
				if petIndex then
					mergeSelectedPets[petIndex] = true
					mergeSelectedCount = mergeSelectedCount + 1
					selectedSoFar = selectedSoFar + 1
				end
			end
		end
	end
	UpdateMergeCountLabel()
end

function PetModalUIController:CloseMergeUI()
	uiMerge.Enabled = false
	mergeMainFrame.Visible = false
end

function PetModalUIController:KnitInit()
	uiPetModal = PlayerGui:WaitForChild("UI_PetModal")
	petModalDarkOverlay = uiPetModal:WaitForChild("DarkOverlay")
	petModalMainFrame = petModalDarkOverlay:WaitForChild("MainFrame")
	petModalCloseButton = petModalMainFrame:WaitForChild("CloseButton")
	petModalEquipButton = petModalMainFrame:WaitForChild("EquipButton")
	petModalEquipEmoji = petModalEquipButton:WaitForChild("Emoji")
	petModalEquipLabel = petModalEquipButton:WaitForChild("TextLabel")
	petModalMergeButton = petModalMainFrame:WaitForChild("MergeButton")
	petModalMultiplier = petModalMainFrame:WaitForChild("Multiplier")
	uiMerge = PlayerGui:WaitForChild("UI_Merge")
	mergeMainFrame = uiMerge:WaitForChild("MainFrame")
	mergePetGrid = mergeMainFrame:WaitForChild("PetGrid")
	mergePetTemplate = mergePetGrid:WaitForChild("UIGridLayout"):WaitForChild("Template")
	mergeRightPanel = mergeMainFrame:WaitForChild("RightPanel")
	mergeCountLabel = mergeRightPanel:WaitForChild("MergeCount")
	mergeButton = mergeRightPanel:WaitForChild("Merge")
	selectAllButton = mergeMainFrame:WaitForChild("SelectAll")
	mergeCloseButton = mergeMainFrame:WaitForChild("Close")
end

function PetModalUIController:KnitStart()
	local PetService = Knit.GetService("PetService")
	local UIController = Knit.GetController("UIController")
	local InventoryUIController = Knit.GetController("InventoryUIController")
	local NotificationController = Knit.GetController("NotificationController")
	local inventoryMainFrame = UIController:GetUIReferences().InventoryUI:WaitForChild("MainFrame")

	_connections["PetModalClose"] = petModalCloseButton.MouseButton1Click:Connect(function()
		petModalDarkOverlay.Visible = false
		selectedPetData = nil
		inventoryMainFrame.Visible = true
	end)

	_connections["PetModalEquip"] = petModalEquipButton.MouseButton1Click:Connect(function()
		if not selectedPetData then return end
		local data = UIController:GetData()
		if selectedPetData.Equipped then
			PetService:RequestUnequipPet(selectedPetData.ID):andThen(function(success, errorMsg)
				if success then
					selectedPetData.Equipped = false
					UpdatePetModalEquipButton(false)
					local equippedPets = data.Inventory.EquippedPets or {}
					for i, petIndex in ipairs(equippedPets) do
						if petIndex == selectedPetData.Index then
							table.remove(data.Inventory.EquippedPets, i)
							break
						end
					end
					InventoryUIController:UpdatePetsInventory()
				else
					NotificationController:ShowNotification(
						"Failed to unequip pet: " .. (errorMsg or "Unknown error"),
						NotificationController.Category.Error,
						3
					)
				end
			end)
		else
			PetService:RequestEquipPet(selectedPetData.ID):andThen(function(success, errorMsg)
				if success then
					selectedPetData.Equipped = true
					UpdatePetModalEquipButton(true)
					if not data.Inventory.EquippedPets then
						data.Inventory.EquippedPets = {}
					end
					table.insert(data.Inventory.EquippedPets, selectedPetData.Index)
					InventoryUIController:UpdatePetsInventory()
				else
					NotificationController:ShowNotification(
						"Failed to equip pet: " .. (errorMsg or "Unknown error"),
						NotificationController.Category.Error,
						3
					)
				end
			end)
		end
	end)

	_connections["PetModalMerge"] = petModalMergeButton.MouseButton1Click:Connect(function()
		if not selectedPetData then return end
		self:UpdateMergeUI(selectedPetData.ID)
		petModalDarkOverlay.Visible = false
	end)

	_connections["MergeSelectAll"] = selectAllButton.MouseButton1Click:Connect(function()
		SelectAllMergePets()
	end)

	_connections["MergeButton"] = mergeButton.MouseButton1Click:Connect(function()
		if not mergeSelectedPetID then return end
		if mergeSelectedCount < mergeRequiredCopies then
			NotificationController:ShowNotification(
				string.format("Need %d copies to merge, selected %d", mergeRequiredCopies, mergeSelectedCount),
				NotificationController.Category.Warning,
				3
			)
			return
		end
		PetService:RequestMergePets(mergeSelectedPetID, mergeSelectedCount):andThen(function(success, errorMsg, resultData)
			if success then
				uiMerge.Enabled = false
				mergeMainFrame.Visible = false
				petModalDarkOverlay.Visible = false
				NotificationController:ShowNotification(
					"Merge successful! Pet upgraded to " .. (resultData and resultData.TierName or "higher tier"),
					NotificationController.Category.Success,
					3
				)
				InventoryUIController:UpdatePetsInventory()
			else
				NotificationController:ShowNotification(
					"Merge failed: " .. (errorMsg or "Unknown error"),
					NotificationController.Category.Error,
					3
				)
			end
		end)
	end)

	_connections["MergeClose"] = mergeCloseButton.MouseButton1Click:Connect(function()
		self:CloseMergeUI()
	end)
end

return PetModalUIController
