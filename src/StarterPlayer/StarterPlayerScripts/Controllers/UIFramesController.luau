--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

export type FrameName = 
	"Shop" | 
	"Inventory" | 
	"PetModal" | 
	"Merge" | 
	"Settings" | 
	"DailyRewards" | 
	"Rebirth" | 
	"World" | 
	"TradePlayerList" | 
	"TradeMain" |
	"RaceHUD"

export type FrameEntry = {
	Frame: Frame,
	ScreenGui: ScreenGui?,
	IsRaceHUD: boolean,
}

export type ControllerState = {
	CurrentOpenFrame: FrameName?,
	FramesDisabled: boolean,
	IsRaceActive: boolean,
}

export type AnimationConfig = {
	FadeInTime: number,
	FadeOutTime: number,
	UseAnimation: boolean,
}

local UIFramesController = Knit.CreateController({
	Name = "UIFramesController",
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local MainFrames: { [FrameName]: FrameEntry } = {}

local State: ControllerState = {
	CurrentOpenFrame = nil,
	FramesDisabled = false,
	IsRaceActive = false,
}

local AnimConfig: AnimationConfig = {
	FadeInTime = 0.2,
	FadeOutTime = 0.15,
	UseAnimation = false,
}

local function SetFrameVisible(entry: FrameEntry, visible: boolean)
	if entry.ScreenGui then
		entry.ScreenGui.Enabled = visible
	end
	entry.Frame.Visible = visible
end

local function HideAllMainFrames()
	for frameName, entry in pairs(MainFrames) do
		if not entry.IsRaceHUD then
			SetFrameVisible(entry, false)
		end
	end
end

local function ShowRaceHUD()
	local raceHUDEntry = MainFrames["RaceHUD"]
	if raceHUDEntry then
		SetFrameVisible(raceHUDEntry, true)
	end
end

local function HideRaceHUD()
	local raceHUDEntry = MainFrames["RaceHUD"]
	if raceHUDEntry then
		SetFrameVisible(raceHUDEntry, false)
	end
end

function UIFramesController:OpenFrame(frameName: FrameName): boolean
	if State.FramesDisabled then
		return false
	end
	
	local entry = MainFrames[frameName]
	if not entry then
		warn("[UIFramesController] Unknown frame: " .. tostring(frameName))
		return false
	end
	
	if State.CurrentOpenFrame == frameName then
		return true
	end
	
	HideAllMainFrames()
	HideRaceHUD()
	
	SetFrameVisible(entry, true)
	State.CurrentOpenFrame = frameName
	
	return true
end

function UIFramesController:CloseFrame(frameName: FrameName): boolean
	local entry = MainFrames[frameName]
	if not entry then
		return false
	end
	
	SetFrameVisible(entry, false)
	
	if State.CurrentOpenFrame == frameName then
		State.CurrentOpenFrame = nil
		
		if not State.FramesDisabled and not State.IsRaceActive then
			ShowRaceHUD()
		end
	end
	
	return true
end

function UIFramesController:CloseCurrentFrame()
	if State.CurrentOpenFrame then
		self:CloseFrame(State.CurrentOpenFrame)
	end
end

function UIFramesController:CloseAllFrames()
	HideAllMainFrames()
	State.CurrentOpenFrame = nil
	
	if not State.FramesDisabled and not State.IsRaceActive then
		ShowRaceHUD()
	end
end

function UIFramesController:ToggleFrame(frameName: FrameName): boolean
	if State.FramesDisabled then
		return false
	end
	
	if State.CurrentOpenFrame == frameName then
		self:CloseFrame(frameName)
		return false
	else
		self:OpenFrame(frameName)
		return true
	end
end

function UIFramesController:IsFrameOpen(frameName: FrameName): boolean
	return State.CurrentOpenFrame == frameName
end

function UIFramesController:GetCurrentOpenFrame(): FrameName?
	return State.CurrentOpenFrame
end

function UIFramesController:DisableFrames(disabled: boolean)
	State.FramesDisabled = disabled
	
	if disabled then
		HideAllMainFrames()
		HideRaceHUD()
		State.CurrentOpenFrame = nil
	else
		if not State.IsRaceActive then
			ShowRaceHUD()
		end
	end
end

function UIFramesController:IsDisabled(): boolean
	return State.FramesDisabled
end

function UIFramesController:SetRaceActive(active: boolean)
	State.IsRaceActive = active
	
	if active then
		HideAllMainFrames()
		State.CurrentOpenFrame = nil
	else
		if not State.FramesDisabled then
			ShowRaceHUD()
		end
	end
end

function UIFramesController:IsRaceActive(): boolean
	return State.IsRaceActive
end

function UIFramesController:GetFrameEntry(frameName: FrameName): FrameEntry?
	return MainFrames[frameName]
end

function UIFramesController:SetAnimationConfig(config: AnimationConfig)
	AnimConfig = config
end

function UIFramesController:GetAnimationConfig(): AnimationConfig
	return AnimConfig
end

function UIFramesController:KnitInit()
	local mainUI = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local uiShop = PlayerGui:WaitForChild("UI_Shop")
	local uiInventory = PlayerGui:WaitForChild("UI_Inventory")
	local uiPetModal = PlayerGui:WaitForChild("UI_PetModal")
	local uiMerge = PlayerGui:WaitForChild("UI_Merge")
	local tradingScreenGui = PlayerGui:WaitForChild("TradingSuite")
	local uiSettings = PlayerGui:WaitForChild("SettingsUI")
	local simulatorPopups = PlayerGui:WaitForChild("SimulatorPopups")
	local raceHUD = PlayerGui:WaitForChild("RaceHUD")
	local otherFrames = mainUI:WaitForChild("OtherFrames")
	
	MainFrames["Shop"] = {
		Frame = uiShop:WaitForChild("MainFrame"),
		ScreenGui = uiShop,
		IsRaceHUD = false,
	}
	
	MainFrames["Inventory"] = {
		Frame = uiInventory:WaitForChild("MainFrame"),
		ScreenGui = uiInventory,
		IsRaceHUD = false,
	}
	
	MainFrames["PetModal"] = {
		Frame = uiPetModal:WaitForChild("DarkOverlay"),
		ScreenGui = uiPetModal,
		IsRaceHUD = false,
	}
	
	MainFrames["Merge"] = {
		Frame = uiMerge:WaitForChild("MainFrame"),
		ScreenGui = uiMerge,
		IsRaceHUD = false,
	}
	
	MainFrames["Settings"] = {
		Frame = uiSettings:WaitForChild("MainFrame"),
		ScreenGui = uiSettings,
		IsRaceHUD = false,
	}
	
	MainFrames["DailyRewards"] = {
		Frame = otherFrames:WaitForChild("DailyFrame"),
		ScreenGui = nil,
		IsRaceHUD = false,
	}
	
	MainFrames["Rebirth"] = {
		Frame = simulatorPopups:WaitForChild("RebirthMenu"),
		ScreenGui = nil,
		IsRaceHUD = false,
	}
	
	MainFrames["World"] = {
		Frame = simulatorPopups:WaitForChild("WorldMenu"),
		ScreenGui = nil,
		IsRaceHUD = false,
	}
	
	MainFrames["TradePlayerList"] = {
		Frame = tradingScreenGui:WaitForChild("PlayerListFrame"),
		ScreenGui = nil,
		IsRaceHUD = false,
	}
	
	MainFrames["TradeMain"] = {
		Frame = tradingScreenGui:WaitForChild("MainTradeFrame"),
		ScreenGui = nil,
		IsRaceHUD = false,
	}
	
	MainFrames["RaceHUD"] = {
		Frame = raceHUD:WaitForChild("MainFrame"),
		ScreenGui = raceHUD,
		IsRaceHUD = true,
	}
end

function UIFramesController:KnitStart()
	ShowRaceHUD()
end

return UIFramesController
