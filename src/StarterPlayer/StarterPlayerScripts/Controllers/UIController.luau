local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))
local rebirthStatsM = require(modules:WaitForChild("RebirthStats"))

local UIController = Knit.CreateController({
	Name = "UIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

export type UIReference = {
	Gui: ScreenGui?,
	MainFrame: Frame?,
	[string]: any,
}

local UI = {
	Main = nil :: ScreenGui?,
	DailyFrame = nil :: Frame?,
	Shop = {
		Gui = nil :: ScreenGui?,
		MainFrame = nil :: Frame?,
	} :: UIReference,
	Inventory = {
		Gui = nil :: ScreenGui?,
		MainFrame = nil :: Frame?,
	} :: UIReference,
	PetModal = {
		Gui = nil :: ScreenGui?,
		DarkOverlay = nil :: Frame?,
	} :: UIReference,
	Merge = {
		Gui = nil :: ScreenGui?,
	} :: UIReference,
	Trading = {
		Gui = nil :: ScreenGui?,
		PlayerListFrame = nil :: Frame?,
	} :: UIReference,
	Settings = {
		Gui = nil :: ScreenGui?,
		MainFrame = nil :: Frame?,
	} :: UIReference,
	RebirthMenu = nil :: Frame?,
	WorldMenu = nil :: Frame?,
}

local GATE_PROXIMITY_DISTANCE = statsM.GateProximityDistance
local MAX_GATE_INDEX = statsM.MaxGateIndex

local isRequestingTrack = false
local buttonPressed = false

local data = {
	Currencies = { Cash = 0, Gems = 0 },
	Stats = { TotalDistance = 0, Points = 0, Rebirths = 0, Fuel = 100, Stars = 0 },
	Progression = { CurrentWorld = "Main", UnlockedWorlds = { "Main" } },
	Inventory = { PetInventory = {}, EquippedPets = {}, Potions = {} },
	Meta = { DailyStreak = 0, LastClaim = 0, CollectedRewards = {}, UpdateVersion = 0, Settings = { Music = true, SFX = true, HidePets = false, TradingEnabled = true } },
}

function UIController:GetData()
	return data
end

function UIController:SetData(newData)
	if newData then
		data = newData
	end
end

function UIController:UpdateData(partialData)
	if partialData then
		for key, value in pairs(partialData) do
			if type(value) == "table" and type(data[key]) == "table" then
				for subKey, subValue in pairs(value) do
					data[key][subKey] = subValue
				end
			else
				data[key] = value
			end
		end
	end
end

local function GetTrackGatesForCurrentWorld(): Folder?
	local currentWorld = data.Progression.CurrentWorld
	local worldFolder = Workspace:FindFirstChild(currentWorld)
	if worldFolder then
		local trackSystem = worldFolder:FindFirstChild("Track_System")
		if trackSystem then
			return trackSystem:FindFirstChild("Track_Gates")
		end
	end
	local mainWorld = Workspace:FindFirstChild("Main")
	if mainWorld then
		local trackSystem = mainWorld:FindFirstChild("Track_System")
		if trackSystem then
			return trackSystem:FindFirstChild("Track_Gates")
		end
	end
	return nil
end

function UIController:IsPlayerNearGate(): boolean
	local character = player.Character
	if not character then return false end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	local playerPosition = rootPart.Position
	local trackGates = GetTrackGatesForCurrentWorld()
	if not trackGates then return false end
	for i = 0, MAX_GATE_INDEX do
		local gateName = "Gate_" .. i
		local gate = trackGates:FindFirstChild(gateName)
		if gate then
			local gatePosition: Vector3
			if gate:IsA("BasePart") then
				gatePosition = gate.Position
			elseif gate:IsA("Model") then
				local primaryPart = gate.PrimaryPart or gate:FindFirstChildWhichIsA("BasePart")
				if primaryPart then
					gatePosition = primaryPart.Position
				end
			end
			if gatePosition then
				local distance = (playerPosition - gatePosition).Magnitude
				if distance <= GATE_PROXIMITY_DISTANCE then
					return true
				end
			end
		end
	end
	return false
end

function UIController:IsPlayerNearWorldPad(): boolean
	local character = player.Character
	if not character then return false end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	local playerPosition = rootPart.Position
	local currentWorld = player:GetAttribute("CurrentWorld")
	local worldFolder = Workspace:FindFirstChild(currentWorld)
	if not worldFolder then return false end
	local pad = worldFolder:FindFirstChild("WorldSelectPad")
	if pad and pad:IsA("BasePart") then
		local distance = (playerPosition - pad.Position).Magnitude
		if distance <= GATE_PROXIMITY_DISTANCE then
			return true
		end
	end
	return false
end

function UIController:IsPlayerNearRebirthArea(): boolean
	local character = player.Character
	if not character then return false end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	local playerPosition = rootPart.Position
	local currentWorld = player:GetAttribute("CurrentWorld")
	local worldFolder = Workspace:FindFirstChild(currentWorld)
	if not worldFolder then return false end
	local pad = worldFolder:FindFirstChild("Rebirth_Altar")
	if pad and pad:IsA("BasePart") then
		local distance = (playerPosition - pad.Position).Magnitude
		if distance <= GATE_PROXIMITY_DISTANCE then
			return true
		end
	end
	return false
end

function UIController:GetButtonPressed(): boolean
	return buttonPressed
end

function UIController:SetButtonPressed(value: boolean)
	buttonPressed = value
end

function UIController:IsRequestingTrack(): boolean
	return isRequestingTrack
end

function UIController:SetRequestingTrack(value: boolean)
	isRequestingTrack = value
end

function UIController:ResetTrackDebounce()
	isRequestingTrack = false
end

function UIController:TruncateNumber(n: number): string
	if (n <= 1000) then return string.format("%.0f", n) end
	if n >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.2fK", n / 1e3)
	end
	return tostring(n)
end

function UIController:CloseAllFrames(exceptFrame: Frame?)
	local old = exceptFrame and exceptFrame.Visible
	if UI.DailyFrame then UI.DailyFrame.Visible = false end
	if UI.Shop.MainFrame then UI.Shop.MainFrame.Visible = false end
	if UI.Inventory.MainFrame then UI.Inventory.MainFrame.Visible = false end
	if UI.PetModal.DarkOverlay then UI.PetModal.DarkOverlay.Visible = false end
	if UI.RebirthMenu then UI.RebirthMenu.Visible = false end
	if UI.Trading.PlayerListFrame then UI.Trading.PlayerListFrame.Visible = false end
	if UI.Settings.MainFrame then UI.Settings.MainFrame.Visible = false end
	if exceptFrame then exceptFrame.Visible = old end
end

function UIController:GetUIReferences()
	return {
		MainUI = UI.Main,
		ShopUI = UI.Shop.Gui,
		InventoryUI = UI.Inventory.Gui,
		PetModalUI = UI.PetModal.Gui,
		MergeUI = UI.Merge.Gui,
		TradingUI = UI.Trading.Gui,
		RebirthMenu = UI.RebirthMenu,
		WorldMenu = UI.WorldMenu,
		DailyFrame = UI.DailyFrame,
	}
end

function UIController:CalculateTotalMultiplier(): number
	local currentRebirthLevel = data.Stats.Rebirths or 0
	local rebirthBonus = rebirthStatsM.CalculateTotalMultiplier(currentRebirthLevel)
	local equippedPetsList = {}
	if data.Inventory and data.Inventory.EquippedPets and data.Inventory.PetInventory then
		for _, petIndex in ipairs(data.Inventory.EquippedPets) do
			local pet = data.Inventory.PetInventory[petIndex]
			if pet then
				table.insert(equippedPetsList, pet)
			end
		end
	end
	local petBonus = statsM.CalculateFuelMultiplier(equippedPetsList)
	local otherBonus = statsM.CalculateOtherBonus()
	local totalBonuses = petBonus + rebirthBonus + otherBonus
	return totalBonuses > 0 and totalBonuses or 1
end

function UIController:KnitInit()
	UI.Main = PlayerGui:WaitForChild("RaceThroughTime_UI")

	local shopGui = PlayerGui:WaitForChild("UI_Shop")
	UI.Shop.Gui = shopGui
	UI.Shop.MainFrame = shopGui:WaitForChild("MainFrame")

	local invGui = PlayerGui:WaitForChild("UI_Inventory")
	UI.Inventory.Gui = invGui
	UI.Inventory.MainFrame = invGui:WaitForChild("MainFrame")

	local petModalGui = PlayerGui:WaitForChild("UI_PetModal")
	UI.PetModal.Gui = petModalGui
	UI.PetModal.DarkOverlay = petModalGui:WaitForChild("DarkOverlay")

	UI.Merge.Gui = PlayerGui:WaitForChild("UI_Merge")

	local tradingGui = PlayerGui:WaitForChild("TradingSuite")
	UI.Trading.Gui = tradingGui
	UI.Trading.PlayerListFrame = tradingGui:WaitForChild("PlayerListFrame")

	local settingsGui = PlayerGui:WaitForChild("SettingsUI")
	UI.Settings.Gui = settingsGui
	UI.Settings.MainFrame = settingsGui:WaitForChild("MainFrame")

	local simulatorPopups = PlayerGui:WaitForChild("SimulatorPopups")
	UI.RebirthMenu = simulatorPopups:WaitForChild("RebirthMenu")
	UI.WorldMenu = simulatorPopups:WaitForChild("WorldMenu")

	local otherFrames = UI.Main:WaitForChild("OtherFrames")
	UI.DailyFrame = otherFrames:WaitForChild("DailyFrame")
end

function UIController:KnitStart()
	local DataService = Knit.GetService("DataService")
	DataService.DataReady:Connect(function(newData)
		self:SetData(newData)
		local CurrencyUIController = Knit.GetController("CurrencyUIController")
		local DailyRewardsUIController = Knit.GetController("DailyRewardsUIController")
		local ShopUIController = Knit.GetController("ShopUIController")
		local WorldUIController = Knit.GetController("WorldUIController")
		local MainBossController = Knit.GetController("MainBossController")
		local TrackController = Knit.GetController("TrackController")
		local InventoryUIController = Knit.GetController("InventoryUIController")
		if InventoryUIController then InventoryUIController:UpdatePetsInventory() end
		if CurrencyUIController then CurrencyUIController:UpdateAllDisplays() end
		if DailyRewardsUIController then DailyRewardsUIController:UpdateRewardsStatus() end
		if ShopUIController then ShopUIController:UpdateShopUI() end
		if WorldUIController then WorldUIController:UpdateWorlds() end
		if MainBossController then MainBossController:UpdateUnlockProgress() end
		if TrackController then TrackController:UpdateWorldFrameColors() end
	end)

	RunService.RenderStepped:Connect(function()
		local CurrencyUIController = Knit.GetController("CurrencyUIController")
		local RunButtonUIController = Knit.GetController("RunButtonUIController")
		local WorldUIController = Knit.GetController("WorldUIController")
		local RebirthUIController = Knit.GetController("RebirthUIController")
		local MainBossController = Knit.GetController("MainBossController")
		if CurrencyUIController then CurrencyUIController:UpdateFromLeaderstats() end
		if RunButtonUIController then RunButtonUIController:UpdateVisibility() end
		if WorldUIController then WorldUIController:UpdateMenuVisibility() end
		if RebirthUIController then RebirthUIController:UpdateMenuVisibility() end
		if MainBossController then MainBossController:UpdateUnlockProgress() end
	end)
end

return UIController
