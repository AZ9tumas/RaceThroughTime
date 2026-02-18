--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Stats = require(Modules:WaitForChild("Stats"))
local PetMergeStats = require(Modules:WaitForChild("PetMergeStats"))

export type PetData = {
	ID: string,
	Name: string,
	PetType: string?,
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
	TierLevel: number?,
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

local DEBUG_COLORS = {
	Background = Color3.fromRGB(30, 30, 35),
	Header = Color3.fromRGB(40, 40, 50),
	RowEven = Color3.fromRGB(38, 38, 45),
	RowOdd = Color3.fromRGB(45, 45, 55),
	Key = Color3.fromRGB(130, 200, 255),
	Value = Color3.fromRGB(255, 255, 255),
}

local debugFrame: Frame? = nil

local UI: UIComponents = {} :: UIComponents

local State: ControllerState = {
	SelectedPetData = nil,
	Merge = {
		TierLevel = nil,
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
		TierLevel = nil,
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

-- Check if two pets share at least one egg in common via Stats.Pets
local function SharesEgg(petTypeA: string, petTypeB: string): boolean
	local statsA = Stats.Pets[petTypeA]
	local statsB = Stats.Pets[petTypeB]
	if not statsA or not statsB then
		warn(string.format("[PetModalUIController] Missing Stats.Pets entry: %s or %s", tostring(petTypeA), tostring(petTypeB)))
		return false
	end
	local eggsA = statsA.Egg
	local eggsB = statsB.Egg
	if not eggsA or not eggsB then return false end
	for _, egg1 in ipairs(eggsA) do
		for _, egg2 in ipairs(eggsB) do
			if egg1 == egg2 then
				return true
			end
		end
	end
	return false
end

local function GetMatchingPetsForMerge(tierLevel: number, petType: string, world: string): { { Index: number, PetData: PetData } }
	local controllers = GetControllers()
	local data = controllers.UI:GetData()
	local petInventory = data.Inventory.PetInventory
	
	local matchingPets: { { Index: number, PetData: PetData } } = {}
	
	for index, petData in ipairs(petInventory) do
		-- Must match: same tier level, same world, and at least one egg in common
		if petData.TierLevel == tierLevel
			and petData.World == world
			and petData.PetType
			and SharesEgg(petType, petData.PetType)
		then
			table.insert(matchingPets, {
				Index = index,
				PetData = {
					ID = petData.ID,
					Name = petData.Name,
					PetType = petData.PetType,
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

local function FormatValue(value: any): string
	if type(value) == "table" then
		local parts = {}
		for _, v in ipairs(value) do
			table.insert(parts, tostring(v))
		end
		return table.concat(parts, ", ")
	elseif type(value) == "boolean" then
		return value and "true" or "false"
	else
		return tostring(value)
	end
end

local function CreateDebugInfoFrame(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "PetDebugInfo"
	frame.Size = UDim2.new(0, 320, 0, 400)
	frame.Position = UDim2.new(0.5, -160, 0.5, -200)
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundColor3 = DEBUG_COLORS.Background
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Draggable = true
	frame.ZIndex = 1100

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 90)
	stroke.Thickness = 1
	stroke.Parent = frame

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = DEBUG_COLORS.Header
	header.BorderSizePixel = 0
	header.ZIndex = 1101
	header.Parent = frame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = header

	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 10)
	headerFix.Position = UDim2.new(0, 0, 1, -10)
	headerFix.BackgroundColor3 = DEBUG_COLORS.Header
	headerFix.BorderSizePixel = 0
	headerFix.ZIndex = 1101
	headerFix.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Size = UDim2.new(1, -40, 1, 0)
	headerTitle.Position = UDim2.new(0, 10, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "🐾 Pet Debug Info"
	headerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	headerTitle.TextSize = 14
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.ZIndex = 1102
	headerTitle.Parent = header

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 14
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.ZIndex = 1102
	closeBtn.Parent = header

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	-- Scrolling content
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Size = UDim2.new(1, -12, 1, -44)
	scroll.Position = UDim2.new(0, 6, 0, 40)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 1101
	scroll.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = scroll

	closeBtn.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)

	return frame
end

local function PopulateDebugFrame(petData: PetData)
	if not debugFrame then return end

	local scroll = debugFrame:FindFirstChild("Content") :: ScrollingFrame
	if not scroll then return end

	-- Clear existing rows
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Build a sorted list of keys from petData
	-- Also pull in Stats.Pets values for the PetType as fallback/extra info
	local displayData: { { Key: string, Value: string } } = {}
	local seenKeys: { [string]: boolean } = {}

	-- First add all petData fields
	for key, value in pairs(petData :: any) do
		table.insert(displayData, { Key = tostring(key), Value = FormatValue(value) })
		seenKeys[tostring(key)] = true
	end

	-- Then add any extra fields from Stats.Pets[PetType] that aren't already shown
	local petType = petData.PetType
	if petType then
		local statsPet = Stats.Pets[petType]
		if statsPet then
			for key, value in pairs(statsPet) do
				local keyStr = tostring(key)
				if not seenKeys[keyStr] then
					table.insert(displayData, { Key = keyStr .. " (Stats)", Value = FormatValue(value) })
					seenKeys[keyStr] = true
				end
			end
		end
	end

	-- Sort alphabetically by key
	table.sort(displayData, function(a, b)
		return a.Key < b.Key
	end)

	-- Create rows
	for i, entry in ipairs(displayData) do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. entry.Key
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundColor3 = if i % 2 == 0 then DEBUG_COLORS.RowEven else DEBUG_COLORS.RowOdd
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 1102
		row.Parent = scroll

		local keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "Key"
		keyLabel.Size = UDim2.new(0.45, -4, 1, 0)
		keyLabel.Position = UDim2.new(0, 8, 0, 0)
		keyLabel.BackgroundTransparency = 1
		keyLabel.Text = entry.Key .. ":"
		keyLabel.TextColor3 = DEBUG_COLORS.Key
		keyLabel.TextSize = 12
		keyLabel.Font = Enum.Font.GothamMedium
		keyLabel.TextXAlignment = Enum.TextXAlignment.Left
		keyLabel.TextTruncate = Enum.TextTruncate.AtEnd
		keyLabel.ZIndex = 1103
		keyLabel.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.Size = UDim2.new(0.55, -8, 1, 0)
		valueLabel.Position = UDim2.new(0.45, 0, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = entry.Value
		valueLabel.TextColor3 = DEBUG_COLORS.Value
		valueLabel.TextSize = 12
		valueLabel.Font = Enum.Font.Gotham
		valueLabel.TextXAlignment = Enum.TextXAlignment.Left
		valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
		valueLabel.ZIndex = 1103
		valueLabel.Parent = row
	end
end

function PetModalUIController:OpenPetModal(petData: PetData)
	local UIFramesController = Knit.GetController("UIFramesController")
	State.SelectedPetData = petData
	UI.PetModal.Multiplier.Text = string.format("x%.1f Multiplier", petData.Multiplier)
	UpdateEquipButtonAppearance(petData.Equipped or false)
	UIFramesController:OpenFrame("PetModal")
end

function PetModalUIController:ClosePetModal()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:CloseFrame("PetModal")
	State.SelectedPetData = nil
	if debugFrame then
		debugFrame.Visible = false
	end
end

function PetModalUIController:GetSelectedPetData(): PetData?
	return State.SelectedPetData
end

function PetModalUIController:UpdateMergeUI(tierLevel: number, petType: string, world: string)
	local UIFramesController = Knit.GetController("UIFramesController")
	ClearMergePetConnections()
	ClearMergePetGrid()
	ResetMergeState()
	
	State.Merge.TierLevel = tierLevel
	State.Merge.RequiredCopies = PetMergeStats.GetCopiesRequired(tierLevel)
	
	local matchingPets = GetMatchingPetsForMerge(tierLevel, petType, world)
	
	if #matchingPets == 0 then
		return
	end
	
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

	-- Debug button already exists in the MainFrame
	UI.PetModal.DebugButton = UI.PetModal.MainFrame:WaitForChild("Debug")

	-- Create the debug info frame (parented to ScreenGui so it floats)
	debugFrame = CreateDebugInfoFrame()
	debugFrame.Visible = false
	debugFrame.Parent = UI.PetModal.ScreenGui

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
		
		local tierLevel = State.SelectedPetData.TierLevel or State.SelectedPetData.Level or 1
		local petType = State.SelectedPetData.PetType
		local world = State.SelectedPetData.World
		if not petType or not world then
			warn("[PetModalUIController] Cannot open merge: missing PetType or World on selected pet")
			return
		end
		self:UpdateMergeUI(tierLevel, petType, world)
	end)

	Connections["PetModalDebug"] = UI.PetModal.DebugButton.MouseButton1Click:Connect(function()
		if not State.SelectedPetData then
			return
		end

		if debugFrame then
			PopulateDebugFrame(State.SelectedPetData)
			debugFrame.Visible = not debugFrame.Visible
		end
	end)
	
	Connections["MergeSelectAll"] = UI.Merge.SelectAllButton.MouseButton1Click:Connect(function()
		SelectAllPets()
	end)
	
	Connections["MergeButton"] = UI.Merge.MergeButton.MouseButton1Click:Connect(function()
		if not State.Merge.TierLevel then
			return
		end
		
		if State.Debounce.MergeExecution then
			return
		end
		
		-- Check if exactly 1 pet short - prompt Missing Merge dev product
		if State.Merge.SelectedCount == State.Merge.RequiredCopies - 1 then
			-- Only support Missing Merge for tiers 1, 2, 3 (creating tiers 2, 3, 4)
			local tierLevel = State.Merge.TierLevel
			if tierLevel >= 1 and tierLevel <= 3 then
				State.Debounce.MergeExecution = true
				
				local selectedIndexes = GetSelectedPetIndexes()
				local selectedIDs = GetSelectedPetIDs()
				
				-- Store pending merge data on server
				services.Pet:StorePendingMerge(tierLevel, selectedIndexes, selectedIDs):andThen(function(stored)
					if stored then
						-- Get the appropriate dev product ID
						local MonetizationService = Knit.GetService("MonetizationService")
						local productName = "MissingMergeStage" .. tierLevel
						
						MonetizationService:GetDevProductId(productName):andThen(function(productId)
							if productId then
								-- Prompt purchase - the dev product OnPurchase will handle the merge
								MarketplaceService:PromptProductPurchase(Player, productId)
							else
								controllers.Notification:ShowNotification(
									"Missing Merge product not available",
									controllers.Notification.Category.Error,
									3
								)
							end
							State.Debounce.MergeExecution = false
						end)
					else
						controllers.Notification:ShowNotification(
							"Failed to prepare merge data",
							controllers.Notification.Category.Error,
							3
						)
						State.Debounce.MergeExecution = false
					end
				end)
			else
				controllers.Notification:ShowNotification(
					string.format("Need %d copies to merge, selected %d", State.Merge.RequiredCopies, State.Merge.SelectedCount),
					controllers.Notification.Category.Warning,
					3
				)
			end
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
		
		services.Pet:RequestMergePets(selectedIndexes, selectedIDs):andThen(function(success, errorMsg, resultData)
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
