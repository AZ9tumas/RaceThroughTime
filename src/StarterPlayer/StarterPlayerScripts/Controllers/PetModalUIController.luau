--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Stats = require(Modules:WaitForChild("Stats"))
local PetMergeStats = require(Modules:WaitForChild("PetMergeStats"))

export type PetData = {
	ID: string,
	Name: string,
	Multiplier: number,
	PickupRangeBonus: number?,
	RoamRange: number?,
	StarCollectionRadius: number?,
	Velocity: number?,
	World: string?,
	Level: number?,
	TierLevel: number?,
	TierName: string?,
	Rarity: string?,
	Equipped: boolean?,
	Index: number,
}

export type MergeSelection = {
	ID: string,
	Index: number,
}

export type MergeState = {
	TargetPetID: string?,
	TargetPetName: string?,
	RequiredCopies: number,
	SelectedCount: number,
	SelectedPets: { [number]: MergeSelection },
}

export type DebounceState = {
	PetSelection: boolean,
	MergeExecution: boolean,
	EquipAction: boolean,
	SelectAll: boolean,
}

export type ControllerState = {
	SelectedPetData: PetData?,
	Merge: MergeState,
	Debounce: DebounceState,
}

export type UIComponents = {
	PetModal: {
		ScreenGui: ScreenGui,
		DarkOverlay: Frame,
		MainFrame: Frame,
		CloseButton: TextButton,
		EquipButton: TextButton,
		EquipEmoji: TextLabel,
		EquipLabel: TextLabel,
		MergeButton: TextButton,
		Multiplier: TextLabel,
	},
	Merge: {
		ScreenGui: ScreenGui,
		MainFrame: Frame,
		PetGrid: Frame,
		PetTemplate: TextButton,
		RightPanel: Frame,
		CountLabel: TextLabel,
		MergeButton: TextButton,
		SelectAllButton: TextButton,
		CloseButton: TextButton,
	},
}

export type UIColors = {
	Selected: Color3,
	NotSelected: Color3,
	StrokeSelected: Color3,
	StrokeDefault: Color3,
	EquipEnabled: Color3,
	EquipDisabled: Color3,
}

local PetModalUIController = Knit.CreateController({
	Name = "PetModalUIController",
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Colors: UIColors = {
	Selected = Color3.fromRGB(61, 61, 61),
	NotSelected = Color3.fromRGB(20, 23, 28),
	StrokeSelected = Color3.fromRGB(0, 255, 0),
	StrokeDefault = Color3.fromRGB(49, 49, 49),
	EquipEnabled = Color3.fromRGB(80, 200, 80),
	EquipDisabled = Color3.fromRGB(200, 80, 80),
}

local UI: UIComponents = {} :: UIComponents

local State: ControllerState = {
	SelectedPetData = nil,
	Merge = {
		TargetPetID = nil,
		TargetPetName = nil,
		RequiredCopies = 0,
		SelectedCount = 0,
		SelectedPets = {},
	},
	Debounce = {
		PetSelection = false,
		MergeExecution = false,
		EquipAction = false,
		SelectAll = false,
	},
}

local Connections: { [string]: RBXScriptConnection } = {}
local MergePetConnections: { RBXScriptConnection } = {}

local function GetServices()
	return {
		Pet = Knit.GetService("PetService"),
	}
end

local function GetControllers()
	return {
		UI = Knit.GetController("UIController"),
		Inventory = Knit.GetController("InventoryUIController"),
		Notification = Knit.GetController("NotificationController"),
	}
end

local function UpdateEquipButtonAppearance(isEquipped: boolean)
	if isEquipped then
		UI.PetModal.EquipEmoji.Text = "❌"
		UI.PetModal.EquipLabel.Text = "Unequip"
		UI.PetModal.EquipButton.BackgroundColor3 = Colors.EquipDisabled
	else
		UI.PetModal.EquipEmoji.Text = "✅"
		UI.PetModal.EquipLabel.Text = "Equip"
		UI.PetModal.EquipButton.BackgroundColor3 = Colors.EquipEnabled
	end
end

local function UpdateMergeCountLabel()
	UI.Merge.CountLabel.Text = State.Merge.SelectedCount .. "/" .. State.Merge.RequiredCopies
end

local function ClearMergePetConnections()
	for _, connection in ipairs(MergePetConnections) do
		connection:Disconnect()
	end
	MergePetConnections = {}
end

local function ClearMergePetGrid()
	for _, child in ipairs(UI.Merge.PetGrid:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" then
			if child:IsA("Frame") or child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end
end

local function ResetMergeState()
	State.Merge = {
		TargetPetID = nil,
		TargetPetName = nil,
		RequiredCopies = 0,
		SelectedCount = 0,
		SelectedPets = {},
	}
	State.Debounce.MergeExecution = false
	State.Debounce.PetSelection = false
	State.Debounce.SelectAll = false
end

local function TogglePetSelection(petIndex: number, petID: string, petFrame: TextButton)
	if State.Debounce.PetSelection then
		return
	end
	
	State.Debounce.PetSelection = true
	
	local existingSelection = State.Merge.SelectedPets[petIndex]
	
	if existingSelection then
		State.Merge.SelectedPets[petIndex] = nil
		State.Merge.SelectedCount = State.Merge.SelectedCount - 1
		petFrame.UIStroke.Color = Colors.StrokeDefault
	else
		if State.Merge.SelectedCount < State.Merge.RequiredCopies then
			State.Merge.SelectedPets[petIndex] = {
				ID = petID,
				Index = petIndex,
			}
			State.Merge.SelectedCount = State.Merge.SelectedCount + 1
			petFrame.UIStroke.Color = Colors.StrokeSelected
		end
	end
	
	UpdateMergeCountLabel()
	
	State.Debounce.PetSelection = false
end

local function UpdateMergeGridSelection()
	for _, child in ipairs(UI.Merge.PetGrid:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and child:IsA("TextButton") then
			local petIndex = tonumber(child.Name:match("MergePet_(%d+)"))
			if petIndex then
				local isSelected = State.Merge.SelectedPets[petIndex] ~= nil
				child.UIStroke.Color = isSelected and Colors.StrokeSelected or Colors.StrokeDefault
			end
		end
	end
end

local function SelectAllPets()
	if State.Debounce.SelectAll then
		return
	end
	
	State.Debounce.SelectAll = true
	
	State.Merge.SelectedPets = {}
	State.Merge.SelectedCount = 0
	
	local selectedSoFar = 0
	
	for _, child in ipairs(UI.Merge.PetGrid:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and child:IsA("TextButton") then
			if selectedSoFar < State.Merge.RequiredCopies then
				local petIndex = tonumber(child.Name:match("MergePet_(%d+)"))
				local petID = child:GetAttribute("PetID")
				
				if petIndex and petID then
					State.Merge.SelectedPets[petIndex] = {
						ID = petID,
						Index = petIndex,
					}
					State.Merge.SelectedCount = State.Merge.SelectedCount + 1
					selectedSoFar = selectedSoFar + 1
				end
			end
		end
	end
	
	UpdateMergeGridSelection()
	UpdateMergeCountLabel()
	
	State.Debounce.SelectAll = false
end

local function GetMatchingPetsForMerge(targetPetID: string): { { Index: number, PetData: PetData } }
	local controllers = GetControllers()
	local data = controllers.UI:GetData()
	local petInventory = data.Inventory.PetInventory
	
	local targetPet: PetData? = nil
	local targetIndex: number? = nil
	
	for index, petData in ipairs(petInventory) do
		if petData.ID == targetPetID then
			targetPet = petData
			targetIndex = index
			break
		end
	end
	
	if not targetPet then
		return {}
	end
	
	local matchingPets: { { Index: number, PetData: PetData } } = {}
	
	for index, petData in ipairs(petInventory) do
		if petData.TierLevel == targetPet.TierLevel then
			table.insert(matchingPets, {
				Index = index,
				PetData = {
					ID = petData.ID,
					Name = petData.Name or "Unknown Pet",
					Multiplier = petData.Multiplier or 1.0,
					PickupRangeBonus = petData.PickupRangeBonus,
					RoamRange = petData.RoamRange,
					StarCollectionRadius = petData.StarCollectionRadius,
					Velocity = petData.Velocity,
					World = petData.World,
					Level = petData.Level,
					TierLevel = petData.TierLevel,
					TierName = petData.TierName,
					Rarity = petData.Rarity,
					Equipped = petData.Equipped,
					Index = index,
				},
			})
		end
	end
	
	return matchingPets
end

local function CreateMergePetFrame(petInfo: { Index: number, PetData: PetData }): TextButton
	local petFrame = UI.Merge.PetTemplate:Clone()
	petFrame.Name = "MergePet_" .. petInfo.Index
	petFrame.Visible = true
	petFrame:SetAttribute("PetID", petInfo.PetData.ID)
	petFrame:SetAttribute("PetIndex", petInfo.Index)
	
	local nameLabel = petFrame:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = petInfo.PetData.Name
	end
	
	local multiplierLabel = petFrame:FindFirstChild("Multiplier")
	if multiplierLabel and multiplierLabel:IsA("TextLabel") then
		multiplierLabel.Text = "x" .. tostring(petInfo.PetData.Multiplier)
	end
	
	return petFrame
end

local function GetSelectedPetIndexes(): { number }
	local indexes: { number } = {}
	for index, _ in pairs(State.Merge.SelectedPets) do
		table.insert(indexes, index)
	end
	return indexes
end

local function GetSelectedPetIDs(): { string }
	local ids: { string } = {}
	for _, selection in pairs(State.Merge.SelectedPets) do
		table.insert(ids, selection.ID)
	end
	return ids
end

function PetModalUIController:OpenPetModal(petData: PetData)
	local UIFramesController = Knit.GetController("UIFramesController")
	State.SelectedPetData = petData
	UI.PetModal.Multiplier.Text = string.format("x%.1f Multiplier", petData.Multiplier or 1.0)
	UpdateEquipButtonAppearance(petData.Equipped or false)
	UIFramesController:OpenFrame("PetModal")
end

function PetModalUIController:ClosePetModal()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:CloseFrame("PetModal")
	State.SelectedPetData = nil
end

function PetModalUIController:GetSelectedPetData(): PetData?
	return State.SelectedPetData
end

function PetModalUIController:UpdateMergeUI(petID: string)
	local UIFramesController = Knit.GetController("UIFramesController")
	ClearMergePetConnections()
	ClearMergePetGrid()
	ResetMergeState()
	
	State.Merge.TargetPetID = petID
	
	local matchingPets = GetMatchingPetsForMerge(petID)
	
	if #matchingPets == 0 then
		return
	end
	
	local targetPet = matchingPets[1].PetData
	State.Merge.TargetPetName = targetPet.Name
	
	local tierLevel = targetPet.TierLevel or targetPet.Level or 1
	State.Merge.RequiredCopies = PetMergeStats.GetCopiesRequired(tierLevel)
	
	local gemCost = PetMergeStats.GetMergeCost(tierLevel)
	UI.Merge.MergeButton.Text = "MERGE\n(" .. gemCost .. " GEMS)"
	
	UpdateMergeCountLabel()
	
	for _, petInfo in ipairs(matchingPets) do
		local petFrame = CreateMergePetFrame(petInfo)
		
		local connection = petFrame.MouseButton1Click:Connect(function()
			TogglePetSelection(petInfo.Index, petInfo.PetData.ID, petFrame)
		end)
		
		table.insert(MergePetConnections, connection)
		petFrame.Parent = UI.Merge.PetGrid
	end
	
	UIFramesController:OpenFrame("Merge")
end

function PetModalUIController:CloseMergeUI()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:CloseFrame("Merge")
	ClearMergePetConnections()
	ResetMergeState()
end

function PetModalUIController:KnitInit()
	UI.PetModal = {
		ScreenGui = PlayerGui:WaitForChild("UI_PetModal"),
		DarkOverlay = nil :: any,
		MainFrame = nil :: any,
		CloseButton = nil :: any,
		EquipButton = nil :: any,
		EquipEmoji = nil :: any,
		EquipLabel = nil :: any,
		MergeButton = nil :: any,
		Multiplier = nil :: any,
	}
	
	UI.PetModal.DarkOverlay = UI.PetModal.ScreenGui:WaitForChild("DarkOverlay")
	UI.PetModal.MainFrame = UI.PetModal.DarkOverlay:WaitForChild("MainFrame")
	UI.PetModal.CloseButton = UI.PetModal.MainFrame:WaitForChild("CloseButton")
	UI.PetModal.EquipButton = UI.PetModal.MainFrame:WaitForChild("EquipButton")
	UI.PetModal.EquipEmoji = UI.PetModal.EquipButton:WaitForChild("Emoji")
	UI.PetModal.EquipLabel = UI.PetModal.EquipButton:WaitForChild("TextLabel")
	UI.PetModal.MergeButton = UI.PetModal.MainFrame:WaitForChild("MergeButton")
	UI.PetModal.Multiplier = UI.PetModal.MainFrame:WaitForChild("Multiplier")
	
	UI.Merge = {
		ScreenGui = PlayerGui:WaitForChild("UI_Merge"),
		MainFrame = nil :: any,
		PetGrid = nil :: any,
		PetTemplate = nil :: any,
		RightPanel = nil :: any,
		CountLabel = nil :: any,
		MergeButton = nil :: any,
		SelectAllButton = nil :: any,
		CloseButton = nil :: any,
	}
	
	UI.Merge.MainFrame = UI.Merge.ScreenGui:WaitForChild("MainFrame")
	UI.Merge.PetGrid = UI.Merge.MainFrame:WaitForChild("PetGrid")
	UI.Merge.PetTemplate = UI.Merge.PetGrid:WaitForChild("UIGridLayout"):WaitForChild("Template")
	UI.Merge.RightPanel = UI.Merge.MainFrame:WaitForChild("RightPanel")
	UI.Merge.CountLabel = UI.Merge.RightPanel:WaitForChild("MergeCount")
	UI.Merge.MergeButton = UI.Merge.RightPanel:WaitForChild("Merge")
	UI.Merge.SelectAllButton = UI.Merge.MainFrame:WaitForChild("SelectAll")
	UI.Merge.CloseButton = UI.Merge.MainFrame:WaitForChild("Close")
end

function PetModalUIController:KnitStart()
	local services = GetServices()
	local controllers = GetControllers()
	local UIFramesController = Knit.GetController("UIFramesController")
	
	Connections["PetModalClose"] = UI.PetModal.CloseButton.MouseButton1Click:Connect(function()
		self:ClosePetModal()
		UIFramesController:OpenFrame("Inventory")
		controllers.Inventory:UpdatePetsInventory()
	end)
	
	Connections["PetModalEquip"] = UI.PetModal.EquipButton.MouseButton1Click:Connect(function()
		if not State.SelectedPetData then
			return
		end
		
		if State.Debounce.EquipAction then
			return
		end
		
		State.Debounce.EquipAction = true
		
		local data = controllers.UI:GetData()
		
		if State.SelectedPetData.Equipped then
			services.Pet:RequestUnequipPet(State.SelectedPetData.ID):andThen(function(success, errorMsg)
				if success then
					State.SelectedPetData.Equipped = false
					UpdateEquipButtonAppearance(false)
					
					local equippedPets = data.Inventory.EquippedPets or {}
					for i, petIndex in ipairs(equippedPets) do
						if petIndex == State.SelectedPetData.Index then
							table.remove(data.Inventory.EquippedPets, i)
							break
						end
					end
					
					controllers.Inventory:UpdatePetsInventory()
				else
					controllers.Notification:ShowNotification(
						"Failed to unequip pet: " .. (errorMsg or "Unknown error"),
						controllers.Notification.Category.Error,
						3
					)
				end
				
				State.Debounce.EquipAction = false
			end)
		else
			services.Pet:RequestEquipPet(State.SelectedPetData.ID):andThen(function(success, errorMsg)
				if success then
					State.SelectedPetData.Equipped = true
					UpdateEquipButtonAppearance(true)
					
					if not data.Inventory.EquippedPets then
						data.Inventory.EquippedPets = {}
					end
					table.insert(data.Inventory.EquippedPets, State.SelectedPetData.Index)
					
					controllers.Inventory:UpdatePetsInventory()
				else
					controllers.Notification:ShowNotification(
						"Failed to equip pet: " .. (errorMsg or "Unknown error"),
						controllers.Notification.Category.Error,
						3
					)
				end
				
				State.Debounce.EquipAction = false
			end)
		end
	end)
	
	Connections["PetModalMerge"] = UI.PetModal.MergeButton.MouseButton1Click:Connect(function()
		if not State.SelectedPetData then
			return
		end
		
		self:UpdateMergeUI(State.SelectedPetData.ID)
	end)
	
	Connections["MergeSelectAll"] = UI.Merge.SelectAllButton.MouseButton1Click:Connect(function()
		SelectAllPets()
	end)
	
	Connections["MergeButton"] = UI.Merge.MergeButton.MouseButton1Click:Connect(function()
		if not State.Merge.TargetPetID then
			return
		end
		
		if State.Debounce.MergeExecution then
			return
		end
		
		if State.Merge.SelectedCount < State.Merge.RequiredCopies then
			controllers.Notification:ShowNotification(
				string.format("Need %d copies to merge, selected %d", State.Merge.RequiredCopies, State.Merge.SelectedCount),
				controllers.Notification.Category.Warning,
				3
			)
			return
		end
		
		State.Debounce.MergeExecution = true
		
		local selectedIndexes = GetSelectedPetIndexes()
		local selectedIDs = GetSelectedPetIDs()
		
		services.Pet:RequestMergePets(State.Merge.TargetPetID, selectedIndexes, selectedIDs):andThen(function(success, errorMsg, resultData)
			if success then
				UIFramesController:CloseAllFrames()
				
				controllers.Notification:ShowNotification(
					"Merge successful! Pet upgraded to " .. (resultData and resultData.TierName or "higher tier"),
					controllers.Notification.Category.Success,
					3
				)
				
				controllers.Inventory:UpdatePetsInventory()
				ResetMergeState()
			else
				controllers.Notification:ShowNotification(
					"Merge failed: " .. (errorMsg or "Unknown error"),
					controllers.Notification.Category.Error,
					3
				)
			end
			
			State.Debounce.MergeExecution = false
		end)
	end)
	
	Connections["MergeClose"] = UI.Merge.CloseButton.MouseButton1Click:Connect(function()
		self:CloseMergeUI()
	end)
end

return PetModalUIController
