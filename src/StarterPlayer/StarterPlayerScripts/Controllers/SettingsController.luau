local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local SettingsController = Knit.CreateController({
	Name = "SettingsController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local SettingsUI: ScreenGui
local mainFrame: Frame
local closeButton: TextButton
local contentFrame: Frame
local hidePets: TextButton
local musicVolume: TextButton
local soundEffects: TextButton
local tradingEnabled: TextButton
local settingsButton: TextButton

local localSettings = {
	Music = true,
	SFX = true,
	HidePets = false,
	TradingEnabled = true,
}

local _connections = {}

local function UpdateButtonAppearance(button: TextButton, isEnabled: boolean)
	if isEnabled then
		button.Text = "On"
		button.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
	else
		button.Text = "Off"
		button.BackgroundColor3 = Color3.fromRGB(244, 67, 54)
	end
end

local function ApplyMusicSetting(enabled: boolean)
	local musicGroup = SoundService:FindFirstChild("Music")
	if musicGroup then
		musicGroup.Volume = enabled and 0.5 or 0
	end
	for _, sound in ipairs(SoundService:GetDescendants()) do
		if sound:IsA("Sound") and sound:GetAttribute("IsMusic") then
			sound.Volume = enabled and sound:GetAttribute("OriginalVolume") or 0
		end
	end
end

local function ApplySFXSetting(enabled: boolean)
	local sfxGroup = SoundService:FindFirstChild("SFX")
	if sfxGroup then
		sfxGroup.Volume = enabled and 0.5 or 0
	end
end

local function ApplyHidePetsSetting(enabled: boolean)
	local PetController = Knit.GetController("PetController")
	if PetController and PetController.SetHideOtherPets then
		PetController:SetHideOtherPets(enabled)
	end
end

local function ApplyTradingSetting(enabled: boolean)
	local TradeController = Knit.GetController("TradeController")
	if TradeController and TradeController.SetTradingEnabled then
		TradeController:SetTradingEnabled(enabled)
	end
end

local function ApplyAllSettings()
	ApplyMusicSetting(localSettings.Music)
	ApplySFXSetting(localSettings.SFX)
	ApplyHidePetsSetting(localSettings.HidePets)
	ApplyTradingSetting(localSettings.TradingEnabled)
end

local function UpdateAllButtons()
	UpdateButtonAppearance(musicVolume, localSettings.Music)
	UpdateButtonAppearance(soundEffects, localSettings.SFX)
	UpdateButtonAppearance(hidePets, localSettings.HidePets)
	UpdateButtonAppearance(tradingEnabled, localSettings.TradingEnabled)
end

function SettingsController:GetSetting(key: string): any
	return localSettings[key]
end

function SettingsController:ToggleSetting(key: string)
	if localSettings[key] == nil then return end
	local newValue = not localSettings[key]
	localSettings[key] = newValue
	local SettingsService = Knit.GetService("SettingsService")
	SettingsService:UpdateSetting(key, newValue)
	if key == "Music" then
		ApplyMusicSetting(newValue)
		UpdateButtonAppearance(musicVolume, newValue)
	elseif key == "SFX" then
		ApplySFXSetting(newValue)
		UpdateButtonAppearance(soundEffects, newValue)
	elseif key == "HidePets" then
		ApplyHidePetsSetting(newValue)
		UpdateButtonAppearance(hidePets, newValue)
	elseif key == "TradingEnabled" then
		ApplyTradingSetting(newValue)
		UpdateButtonAppearance(tradingEnabled, newValue)
	end
end

function SettingsController:ToggleSettingsMenu()
	local UIController = Knit.GetController("UIController")
	if UIController then
		UIController:CloseAllFrames()
	end
	mainFrame.Visible = not mainFrame.Visible
end

function SettingsController:CloseSettingsMenu()
	mainFrame.Visible = false
end

function SettingsController:KnitInit()
	SettingsUI = PlayerGui:WaitForChild("SettingsUI")
	mainFrame = SettingsUI:WaitForChild("MainFrame")
	closeButton = mainFrame:WaitForChild("Header"):WaitForChild("TextButton")
	contentFrame = mainFrame:WaitForChild("Frame")
	hidePets = contentFrame:WaitForChild("Hide Pets"):WaitForChild("TextButton")
	musicVolume = contentFrame:WaitForChild("Music Volume"):WaitForChild("TextButton")
	soundEffects = contentFrame:WaitForChild("Sound Effects"):WaitForChild("TextButton")
	tradingEnabled = contentFrame:WaitForChild("Trading"):WaitForChild("TextButton")
	local mainUI = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local leftPanel = mainUI:WaitForChild("LeftPanel")
	settingsButton = leftPanel:WaitForChild("SettingsButton")
end

function SettingsController:KnitStart()
	local UIController = Knit.GetController("UIController")
	local data = UIController:GetData()
	if data and data.Meta and data.Meta.Settings then
		for key, value in pairs(data.Meta.Settings) do
			if localSettings[key] ~= nil then
				localSettings[key] = value
			end
		end
	end
	UpdateAllButtons()
	ApplyAllSettings()

	_connections["SettingsButton"] = settingsButton.MouseButton1Click:Connect(function()
		self:ToggleSettingsMenu()
	end)

	_connections["CloseButton"] = closeButton.MouseButton1Click:Connect(function()
		self:CloseSettingsMenu()
	end)

	_connections["MusicVolume"] = musicVolume.MouseButton1Click:Connect(function()
		self:ToggleSetting("Music")
	end)

	_connections["SoundEffects"] = soundEffects.MouseButton1Click:Connect(function()
		self:ToggleSetting("SFX")
	end)

	_connections["HidePets"] = hidePets.MouseButton1Click:Connect(function()
		self:ToggleSetting("HidePets")
	end)

	_connections["TradingEnabled"] = tradingEnabled.MouseButton1Click:Connect(function()
		self:ToggleSetting("TradingEnabled")
	end)
end

return SettingsController
