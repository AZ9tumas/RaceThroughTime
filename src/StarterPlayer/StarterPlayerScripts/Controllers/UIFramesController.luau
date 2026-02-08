--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

export type AnimationType = "None" | "SlideBottom" | "SlideLeft"

export type FrameEntry = {
	Frame: Frame,
	ScreenGui: ScreenGui?,
	AnimationType: AnimationType,
	OriginalPosition: UDim2?,
}

export type ControllerState = {
	CurrentOpenFrame: FrameName?,
	FramesDisabled: boolean,
	IsRaceActive: boolean,
	AnimatingFrames: { [FrameName]: boolean },
}

export type AnimationConfig = {
	SlideInTime: number,
	SlideOutTime: number,
	UseSlideAnimation: boolean,
}

export type ButtonAnimationConfig = {
	ScaleNormal: number,
	ScaleHover: number,
	ScalePressed: number,
	TweenTime: number,
}

local TWEEN_INFO_SLIDE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_INFO_SLIDE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_INFO_SLIDE_LEFT_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_INFO_SLIDE_LEFT_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_INFO_BUTTON = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BUTTON_SCALE_NORMAL = 1
local BUTTON_SCALE_HOVER = 1.1
local BUTTON_SCALE_PRESSED = 0.9

local SLIDE_OUT_POSITION_BOTTOM = UDim2.fromScale(0.5, 1.5)
local SLIDE_OUT_POSITION_RIGHT = UDim2.fromScale(1.5, 0.5)

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
	AnimatingFrames = {},
}

local AnimConfig: AnimationConfig = {
	SlideInTime = 0.3,
	SlideOutTime = 0.25,
	UseSlideAnimation = true,
}

local ButtonConfig: ButtonAnimationConfig = {
	ScaleNormal = BUTTON_SCALE_NORMAL,
	ScaleHover = BUTTON_SCALE_HOVER,
	ScalePressed = BUTTON_SCALE_PRESSED,
	TweenTime = 0.2,
}

local RegisteredButtons: { [GuiButton]: { Connections: { RBXScriptConnection } } } = {}

local function IsRaceHUDFrame(frameName: string): boolean
	return string.find(frameName, "RaceHUD") ~= nil
end

local function SlideInBottom(frame: Frame, originalPosition: UDim2)
	frame.Position = SLIDE_OUT_POSITION_BOTTOM
	frame.Visible = true
	local tween = TweenService:Create(frame, TWEEN_INFO_SLIDE_IN, { Position = originalPosition })
	tween:Play()
	return tween
end

local function SlideOutBottom(frame: Frame, callback: (() -> ())?)
	local tween = TweenService:Create(frame, TWEEN_INFO_SLIDE_OUT, { Position = SLIDE_OUT_POSITION_BOTTOM })
	tween:Play()
	tween.Completed:Connect(function()
		if frame.Position.Y.Scale >= 1.4 then
			frame.Visible = false
		end
		if callback then
			callback()
		end
	end)
	return tween
end

local function SlideInLeft(frame: Frame, originalPosition: UDim2)
	frame.Position = SLIDE_OUT_POSITION_RIGHT
	frame.Visible = true
	local tween = TweenService:Create(frame, TWEEN_INFO_SLIDE_LEFT_IN, { Position = originalPosition })
	tween:Play()
	return tween
end

local function SlideOutRight(frame: Frame, callback: (() -> ())?)
	local tween = TweenService:Create(frame, TWEEN_INFO_SLIDE_LEFT_OUT, { Position = SLIDE_OUT_POSITION_RIGHT })
	tween:Play()
	tween.Completed:Connect(function()
		if frame.Position.X.Scale >= 1.4 then
			frame.Visible = false
		end
		if callback then
			callback()
		end
	end)
	return tween
end

local function SetFrameVisible(entry: FrameEntry, visible: boolean, animate: boolean?, frameName: FrameName?)
	if entry.ScreenGui then
		entry.ScreenGui.Enabled = visible or (animate and AnimConfig.UseSlideAnimation)
	end
	
	local animType = entry.AnimationType
	
	if animate and AnimConfig.UseSlideAnimation and entry.OriginalPosition and frameName and animType ~= "None" then
		if visible then
			State.AnimatingFrames[frameName] = true
			local tween
			if animType == "SlideLeft" then
				tween = SlideInLeft(entry.Frame, entry.OriginalPosition)
			else
				tween = SlideInBottom(entry.Frame, entry.OriginalPosition)
			end
			tween.Completed:Connect(function()
				State.AnimatingFrames[frameName] = nil
			end)
		else
			State.AnimatingFrames[frameName] = true
			local slideOutCallback = function()
				State.AnimatingFrames[frameName] = nil
				if entry.ScreenGui then
					entry.ScreenGui.Enabled = false
				end
			end
			if animType == "SlideLeft" then
				SlideOutRight(entry.Frame, slideOutCallback)
			else
				SlideOutBottom(entry.Frame, slideOutCallback)
			end
		end
	else
		entry.Frame.Visible = visible
	end
end

local function SetFrameVisibleImmediate(entry: FrameEntry, visible: boolean)
	if entry.ScreenGui then
		entry.ScreenGui.Enabled = visible
	end
	entry.Frame.Visible = visible
end

local function HideAllMainFrames(animate: boolean?)
	for frameName, entry in pairs(MainFrames) do
		if not IsRaceHUDFrame(frameName) then
			if animate then
				SetFrameVisible(entry, false, true, frameName)
			else
				SetFrameVisibleImmediate(entry, false)
			end
		end
	end
end

local function ShowRaceHUD()
	local raceHUDEntry = MainFrames["RaceHUD"]
	if raceHUDEntry then
		SetFrameVisible(raceHUDEntry, true, true, "RaceHUD")
	end
end

local function HideRaceHUD()
	local raceHUDEntry = MainFrames["RaceHUD"]
	if raceHUDEntry then
		SetFrameVisible(raceHUDEntry, false, true, "RaceHUD")
	end
end

function UIFramesController:OpenFrame(frameName: FrameName): boolean
	if State.FramesDisabled then
		return false
	end
	
	if State.AnimatingFrames[frameName] then
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
	
	HideAllMainFrames(false)
	HideRaceHUD()
	
	SetFrameVisible(entry, true, true, frameName)
	State.CurrentOpenFrame = frameName
	
	return true
end

function UIFramesController:CloseFrame(frameName: FrameName): boolean
	local entry = MainFrames[frameName]
	if not entry then
		return false
	end
	
	if State.AnimatingFrames[frameName] then
		return false
	end
	
	SetFrameVisible(entry, false, true, frameName)
	
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
	HideAllMainFrames(true)
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
	warn("Disable frames")
	State.FramesDisabled = disabled
	
	if disabled then
		HideAllMainFrames(false)
		HideRaceHUD()
		State.CurrentOpenFrame = nil
	else
		if not State.IsRaceActive then
			ShowRaceHUD()
		end
	end
end

function UIFramesController:DisableFramesWithExceptions(disabled: boolean, exceptions: { FrameName })
	warn("Disable frames with exceptions: " .. tostring(exceptions))
	State.FramesDisabled = disabled
	
	local exceptionsSet: { [FrameName]: boolean } = {}
	for _, frameName in ipairs(exceptions) do
		exceptionsSet[frameName] = true
	end
	
	if disabled then
		for frameName, entry in pairs(MainFrames) do
			if not exceptionsSet[frameName] then
				SetFrameVisibleImmediate(entry, false)
			end
		end
		State.CurrentOpenFrame = nil
		
		for _, exceptionFrameName in ipairs(exceptions) do
			local exceptionEntry = MainFrames[exceptionFrameName]
			if exceptionEntry then
				SetFrameVisible(exceptionEntry, true, true, exceptionFrameName)
			end
		end
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
		HideAllMainFrames(false)
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

function UIFramesController:SetButtonAnimationConfig(config: ButtonAnimationConfig)
	ButtonConfig = config
end

function UIFramesController:GetButtonAnimationConfig(): ButtonAnimationConfig
	return ButtonConfig
end

function UIFramesController:SetupButtonAnimation(button: GuiButton)
	if RegisteredButtons[button] then
		return
	end
	
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = button
	end
	
	local connections: { RBXScriptConnection } = {}
	
	table.insert(connections, button.MouseEnter:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO_BUTTON, { Scale = ButtonConfig.ScaleHover }):Play()
	end))
	
	table.insert(connections, button.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO_BUTTON, { Scale = ButtonConfig.ScaleNormal }):Play()
	end))
	
	table.insert(connections, button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO_BUTTON, { Scale = ButtonConfig.ScalePressed }):Play()
	end))
	
	table.insert(connections, button.MouseButton1Up:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO_BUTTON, { Scale = ButtonConfig.ScaleHover }):Play()
	end))
	
	RegisteredButtons[button] = { Connections = connections }
end

function UIFramesController:RemoveButtonAnimation(button: GuiButton)
	local entry = RegisteredButtons[button]
	if not entry then
		return
	end
	
	for _, connection in ipairs(entry.Connections) do
		connection:Disconnect()
	end
	
	RegisteredButtons[button] = nil
end

function UIFramesController:SetupButtonAnimationsInFrame(frame: Frame)
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			self:SetupButtonAnimation(descendant)
		end
	end
end

function UIFramesController:EnableSlideAnimations(enabled: boolean)
	AnimConfig.UseSlideAnimation = enabled
end

function UIFramesController:IsSlideAnimationsEnabled(): boolean
	return AnimConfig.UseSlideAnimation
end

function UIFramesController:SetFrameAnimationType(frameName: FrameName, animType: AnimationType)
	local entry = MainFrames[frameName]
	if entry then
		entry.AnimationType = animType
	end
end

function UIFramesController:GetFrameAnimationType(frameName: FrameName): AnimationType?
	local entry = MainFrames[frameName]
	if entry then
		return entry.AnimationType
	end
	return nil
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
	
	local shopFrame = uiShop:WaitForChild("MainFrame")
	MainFrames["Shop"] = {
		Frame = shopFrame,
		ScreenGui = uiShop,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = shopFrame.Position,
	}
	
	local inventoryFrame = uiInventory:WaitForChild("MainFrame")
	MainFrames["Inventory"] = {
		Frame = inventoryFrame,
		ScreenGui = uiInventory,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = inventoryFrame.Position,
	}
	
	local petModalFrame = uiPetModal:WaitForChild("DarkOverlay")
	MainFrames["PetModal"] = {
		Frame = petModalFrame,
		ScreenGui = uiPetModal,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = petModalFrame.Position,
	}
	
	local mergeFrame = uiMerge:WaitForChild("MainFrame")
	MainFrames["Merge"] = {
		Frame = mergeFrame,
		ScreenGui = uiMerge,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = mergeFrame.Position,
	}
	
	local settingsFrame = uiSettings:WaitForChild("MainFrame")
	MainFrames["Settings"] = {
		Frame = settingsFrame,
		ScreenGui = uiSettings,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = settingsFrame.Position,
	}
	
	local dailyFrame = otherFrames:WaitForChild("DailyFrame")
	MainFrames["DailyRewards"] = {
		Frame = dailyFrame,
		ScreenGui = nil,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = dailyFrame.Position,
	}
	
	local rebirthFrame = simulatorPopups:WaitForChild("RebirthMenu")
	MainFrames["Rebirth"] = {
		Frame = rebirthFrame,
		ScreenGui = nil,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = rebirthFrame.Position,
	}
	
	local worldFrame = simulatorPopups:WaitForChild("WorldMenu")
	MainFrames["World"] = {
		Frame = worldFrame,
		ScreenGui = nil,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = worldFrame.Position,
	}
	
	local tradePlayerListFrame = tradingScreenGui:WaitForChild("PlayerListFrame")
	MainFrames["TradePlayerList"] = {
		Frame = tradePlayerListFrame,
		ScreenGui = nil,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = tradePlayerListFrame.Position,
	}
	
	local tradeMainFrame = tradingScreenGui:WaitForChild("MainTradeFrame")
	MainFrames["TradeMain"] = {
		Frame = tradeMainFrame,
		ScreenGui = nil,
		AnimationType = "SlideBottom" :: AnimationType,
		OriginalPosition = tradeMainFrame.Position,
	}
	
	local raceHUDFrame = raceHUD:WaitForChild("MainFrame")
	MainFrames["RaceHUD"] = {
		Frame = raceHUDFrame,
		ScreenGui = raceHUD,
		AnimationType = "SlideLeft" :: AnimationType,
		OriginalPosition = raceHUDFrame.Position,
	}
	
	for _, entry in pairs(MainFrames) do
		self:SetupButtonAnimationsInFrame(entry.Frame)
	end
	
	local leftPanel = mainUI:WaitForChild("LeftPanel")
	self:SetupButtonAnimationsInFrame(leftPanel)
end

function UIFramesController:KnitStart()
	ShowRaceHUD()
end

return UIFramesController
