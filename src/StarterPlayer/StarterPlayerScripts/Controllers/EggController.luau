local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local Stats = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Stats"))

local EggController = Knit.CreateController({
	Name = "EggController",
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local EggService = nil
local DataService = nil
local NotificationController = nil
local UIFramesController = nil

local CurrentWorldName = "Main"
local EggConnections: { [string]: { RBXScriptConnection } } = {}
local AutoHatchActive: { [string]: boolean } = {}
local IsHatching = false
local IsSettingUp = false

local MULTI_HATCH_COUNT = 4
local AUTO_HATCH_DELAY = 0.5

local function GetCurrentWorld(): string
	local worldAttr = Player:GetAttribute("CurrentWorld")
	if worldAttr then
		return worldAttr
	end
	return CurrentWorldName
end

local function GetEggShopStands(worldName: string): Folder?
	local worldFolder = Workspace:FindFirstChild(worldName)
	if not worldFolder then
		return nil
	end
	return worldFolder:FindFirstChild("EggShop_Stands")
end

local function GetEggConfig(eggName: string): { Cost: number, Currency: string, Pets: { { Pet: string, Probability: number } } }?
	return Stats.Eggs[eggName]
end

local function GetPetConfig(petName: string): { Name: string, Rarity: string? }?
	return Stats.Pets[petName]
end

local function ClearEggConnections(eggName: string?)
	if eggName then
		local connections = EggConnections[eggName]
		if connections then
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
			EggConnections[eggName] = nil
		end
		AutoHatchActive[eggName] = false
	else
		for name, connections in pairs(EggConnections) do
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
			EggConnections[name] = nil
			AutoHatchActive[name] = false
		end
	end
end

local function FormatPercentage(probability: number): string
	return string.format("%.1f%%", probability * 100)
end

local function UpdateBillboardAdornees(worldName: string)
	local eggShopStands = GetEggShopStands(worldName)
	if not eggShopStands then
		return
	end

	for _, child in ipairs(eggShopStands:GetChildren()) do
		if child:IsA("Model") then
			local eggName = child.Name
			local eggRoot = child:FindFirstChild("EggRoot")
			if eggRoot then
				local billboardGui = PlayerGui:FindFirstChild(eggName .. "_HatchBoard")
				if not billboardGui then
					billboardGui = PlayerGui:FindFirstChild("EggHatchBoard_" .. eggName)
				end
				if not billboardGui then
					for _, gui in ipairs(PlayerGui:GetChildren()) do
						if gui:IsA("BillboardGui") and gui.Name:find(eggName) then
							billboardGui = gui
							break
						end
					end
				end

				if billboardGui and billboardGui:IsA("BillboardGui") then
					billboardGui.Adornee = eggRoot
				end
			end
		end
	end
end

local function SetupPetTemplates(mainBoard: Frame, eggName: string)
	local eggConfig = GetEggConfig(eggName)
	if not eggConfig or not eggConfig.Pets then
		return
	end

	local contentFrame = mainBoard:FindFirstChild("Frame")
	if not contentFrame then
		return
	end

	local gridLayout = contentFrame:FindFirstChild("UIGridLayout")
	local template = gridLayout and gridLayout:FindFirstChild("Template")
	if not template then
		template = contentFrame:FindFirstChild("Template")
	end

	if not template then
		return
	end

	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Template" and child ~= gridLayout and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	for i, petOption in ipairs(eggConfig.Pets) do
		local petName = petOption.Pet
		local probability = petOption.Probability
		local petConfig = GetPetConfig(petName)

		local newTemplate = template:Clone()
		newTemplate.Name = "Pet_" .. i
		newTemplate.Visible = true
		newTemplate.Parent = contentFrame

		local rarityLabel = newTemplate:FindFirstChild("Rarity")
		if rarityLabel and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = FormatPercentage(probability)
		end

		local nameLabel = newTemplate:FindFirstChild("Name") or newTemplate:FindFirstChild("PetName")
		if nameLabel and nameLabel:IsA("TextLabel") and petConfig then
			nameLabel.Text = petConfig.Name or petName
		end
	end

	template.Visible = false
end

local function PurchaseSingleEgg(eggName: string)
	if IsHatching then return end
	IsHatching = true

	local success, errorMsg, _petInfo = EggService:RequestPurchaseEgg(eggName)

	if not success and NotificationController then
		NotificationController:ShowNotification(
			errorMsg or "Failed to purchase egg",
			NotificationController.Category.Warning,
			3
		)
	end

	IsHatching = false
end

local function PurchaseMultipleEggs(eggName: string, count: number)
	if IsHatching then return end
	IsHatching = true

	local purchasedCount = 0
	for _ = 1, count do
		local success, _errorMsg, _petInfo = EggService:RequestPurchaseEgg(eggName)
		if success then
			purchasedCount = purchasedCount + 1
		else
			break
		end
		task.wait(0.1)
	end

	if purchasedCount > 0 and NotificationController then
		NotificationController:ShowNotification(
			string.format("Hatched %d eggs!", purchasedCount),
			NotificationController.Category.Success,
			3
		)
	end

	IsHatching = false
end

local function StartAutoHatch(eggName: string)
	if AutoHatchActive[eggName] then
		return
	end

	AutoHatchActive[eggName] = true

	task.spawn(function()
		while AutoHatchActive[eggName] do
			if IsHatching then
				task.wait(AUTO_HATCH_DELAY)
				continue
			end

			IsHatching = true
			local success, _errorMsg, _petInfo = EggService:RequestPurchaseEgg(eggName)
			IsHatching = false

			if not success then
				AutoHatchActive[eggName] = false
				if NotificationController then
					NotificationController:ShowNotification(
						"Auto-hatch stopped: Not enough currency",
						NotificationController.Category.Warning,
						3
					)
				end
				break
			end

			task.wait(AUTO_HATCH_DELAY)
		end
	end)
end

local function StopAutoHatch(eggName: string)
	AutoHatchActive[eggName] = false
end

local function ToggleAutoHatch(eggName: string)
	if AutoHatchActive[eggName] then
		StopAutoHatch(eggName)
	else
		StartAutoHatch(eggName)
	end
end

local function SetupEggStand(eggStandModel: Model, eggName: string)
	ClearEggConnections(eggName)
	EggConnections[eggName] = {}

	local eggRoot = eggStandModel:FindFirstChild("EggRoot")
	if not eggRoot then
		return
	end

	local uiHatchBoard = eggRoot:FindFirstChild("UI_HatchBoard")
	if not uiHatchBoard then
		return
	end

	local container = uiHatchBoard:FindFirstChild("Container")
	if not container then
		return
	end

	local mainBoard = container:FindFirstChild("MainBoard")
	if not mainBoard then
		return
	end

	local actionButtons = mainBoard:FindFirstChild("ActionButtons")
	if not actionButtons then
		return
	end

	SetupPetTemplates(mainBoard, eggName)

	local btnHatch = actionButtons:FindFirstChild("Btn_Hatch")
	if btnHatch and btnHatch:IsA("TextButton") then
		local conn = btnHatch.MouseButton1Click:Connect(function()
			PurchaseSingleEgg(eggName)
		end)
		table.insert(EggConnections[eggName], conn)

		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnHatch)
		end
	end

	local btnMulti = actionButtons:FindFirstChild("Btn_Multi")
	if btnMulti and btnMulti:IsA("TextButton") then
		local conn = btnMulti.MouseButton1Click:Connect(function()
			PurchaseMultipleEggs(eggName, MULTI_HATCH_COUNT)
		end)
		table.insert(EggConnections[eggName], conn)

		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnMulti)
		end
	end

	local btnAuto = actionButtons:FindFirstChild("Btn_Auto")
	if btnAuto and btnAuto:IsA("TextButton") then
		local conn = btnAuto.MouseButton1Click:Connect(function()
			ToggleAutoHatch(eggName)
		end)
		table.insert(EggConnections[eggName], conn)

		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnAuto)
		end
	end
end

local function SetupEggStandsForWorld(worldName: string)
	if IsSettingUp then
		return
	end
	IsSettingUp = true

	ClearEggConnections()

	UpdateBillboardAdornees(worldName)

	local eggShopStands = GetEggShopStands(worldName)
	if not eggShopStands then
		IsSettingUp = false
		return
	end

	for _, child in ipairs(eggShopStands:GetChildren()) do
		if child:IsA("Model") then
			local eggName = child.Name
			SetupEggStand(child, eggName)
		end
	end

	IsSettingUp = false
end

function EggController:UpdateEggUI()
	local worldName = GetCurrentWorld()
	UpdateBillboardAdornees(worldName)
	SetupEggStandsForWorld(worldName)
end

function EggController:OnWorldChanged(newWorldName: string)
	for eggName, _ in pairs(AutoHatchActive) do
		StopAutoHatch(eggName)
	end

	CurrentWorldName = newWorldName
	UpdateBillboardAdornees(newWorldName)
	SetupEggStandsForWorld(newWorldName)
end

function EggController:KnitInit()
end

function EggController:KnitStart()
	EggService = Knit.GetService("EggService")
	DataService = Knit.GetService("DataService")
	NotificationController = Knit.GetController("NotificationController")
	UIFramesController = Knit.GetController("UIFramesController")

	CurrentWorldName = GetCurrentWorld()
	SetupEggStandsForWorld(CurrentWorldName)

	DataService.DataReady:Connect(function(_newData)
		self:UpdateEggUI()
	end)

	Player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		local newWorld = Player:GetAttribute("CurrentWorld")
		if newWorld and newWorld ~= CurrentWorldName then
			self:OnWorldChanged(newWorld)
		end
	end)

	EggService.PetObtained:Connect(function(petInfo)
		if NotificationController and petInfo then
			NotificationController:ShowNotification(
				string.format("🥚 Hatched: %s!", petInfo.Name or "Unknown Pet"),
				NotificationController.Category.Success,
				3
			)
		end
	end)
end

return EggController
