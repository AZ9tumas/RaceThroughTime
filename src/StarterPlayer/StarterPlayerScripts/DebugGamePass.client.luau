--[[
	Debug Gamepass UI
	This client script creates a debug UI for toggling gamepass ownership in Studio.
	Set DEBUG_ENABLED to false to disable this feature.
]]

local DEBUG_ENABLED = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Only run in Studio when debug is enabled
if not DEBUG_ENABLED or not RunService:IsStudio() then
	return
end

local Knit = require(ReplicatedStorage.Packages.Knit)
local GamePassIds = require(ReplicatedStorage.GamePassIds)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- UI Constants
local UI_COLORS = {
	Background = Color3.fromRGB(30, 30, 35),
	Header = Color3.fromRGB(40, 40, 50),
	ItemBackground = Color3.fromRGB(45, 45, 55),
	EnabledButton = Color3.fromRGB(60, 180, 75),
	DisabledButton = Color3.fromRGB(180, 60, 60),
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(180, 180, 180),
}

-- Create the debug UI
local function CreateDebugUI()
	-- Main ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DebugGamePassUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 1000
	screenGui.Parent = PlayerGui

	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 280, 0, 350)
	mainFrame.Position = UDim2.new(1, -290, 0, 10)
	mainFrame.BackgroundColor3 = UI_COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.ZIndex = 1000
	mainFrame.Active = true
	mainFrame.Draggable = true
	mainFrame.Parent = screenGui

	-- Corner rounding
	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 8)
	mainCorner.Parent = mainFrame

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 40)
	header.BackgroundColor3 = UI_COLORS.Header
	header.BorderSizePixel = 0
	header.Parent = mainFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = header

	-- Fix bottom corners of header
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 10)
	headerFix.Position = UDim2.new(0, 0, 1, -10)
	headerFix.BackgroundColor3 = UI_COLORS.Header
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header

	-- Header title
	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Size = UDim2.new(1, -10, 1, 0)
	headerTitle.Position = UDim2.new(0, 10, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "🔧 Debug GamePasses"
	headerTitle.TextColor3 = UI_COLORS.TextColor
	headerTitle.TextSize = 16
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = header

	-- Scrolling Frame
	local scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "GamePassList"
	scrollingFrame.Size = UDim2.new(1, -16, 1, -56)
	scrollingFrame.Position = UDim2.new(0, 8, 0, 48)
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.ScrollBarThickness = 4
	scrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollingFrame.Parent = mainFrame

	-- UIListLayout for scrolling frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.Name = "ListLayout"
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = scrollingFrame

	-- UIPadding for scrolling frame
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 4)
	listPadding.PaddingBottom = UDim.new(0, 4)
	listPadding.Parent = scrollingFrame

	return screenGui, scrollingFrame
end

-- Create a template item for a gamepass
local function CreateGamePassItem(parent: ScrollingFrame, gamePassName: string, gamePassId: number)
	-- Item Frame
	local itemFrame = Instance.new("Frame")
	itemFrame.Name = gamePassName
	itemFrame.Size = UDim2.new(1, -8, 0, 50)
	itemFrame.BackgroundColor3 = UI_COLORS.ItemBackground
	itemFrame.BorderSizePixel = 0
	itemFrame.Parent = parent

	local itemCorner = Instance.new("UICorner")
	itemCorner.CornerRadius = UDim.new(0, 6)
	itemCorner.Parent = itemFrame

	-- Text Label (left side)
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "GamePassName"
	textLabel.Size = UDim2.new(1, -90, 0, 24)
	textLabel.Position = UDim2.new(0, 10, 0, 6)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = gamePassName
	textLabel.TextColor3 = UI_COLORS.TextColor
	textLabel.TextSize = 14
	textLabel.Font = Enum.Font.GothamMedium
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextTruncate = Enum.TextTruncate.AtEnd
	textLabel.Parent = itemFrame

	-- ID Label (below name)
	local idLabel = Instance.new("TextLabel")
	idLabel.Name = "GamePassId"
	idLabel.Size = UDim2.new(1, -90, 0, 16)
	idLabel.Position = UDim2.new(0, 10, 0, 28)
	idLabel.BackgroundTransparency = 1
	idLabel.Text = "ID: " .. tostring(gamePassId)
	idLabel.TextColor3 = UI_COLORS.SubTextColor
	idLabel.TextSize = 11
	idLabel.Font = Enum.Font.Gotham
	idLabel.TextXAlignment = Enum.TextXAlignment.Left
	idLabel.Parent = itemFrame

	-- Toggle Button (right side)
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleButton"
	toggleButton.Size = UDim2.new(0, 70, 0, 30)
	toggleButton.Position = UDim2.new(1, -80, 0.5, -15)
	toggleButton.BackgroundColor3 = UI_COLORS.DisabledButton
	toggleButton.BorderSizePixel = 0
	toggleButton.Text = "OFF"
	toggleButton.TextColor3 = UI_COLORS.TextColor
	toggleButton.TextSize = 12
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.Parent = itemFrame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 4)
	buttonCorner.Parent = toggleButton

	return itemFrame, toggleButton
end

-- Update button appearance based on state
local function UpdateButtonState(button: TextButton, enabled: boolean)
	if enabled then
		button.BackgroundColor3 = UI_COLORS.EnabledButton
		button.Text = "ON"
	else
		button.BackgroundColor3 = UI_COLORS.DisabledButton
		button.Text = "OFF"
	end
end

-- Main initialization
Knit.OnStart():andThen(function()
	local MonetizationController = Knit.GetController("MonetizationController")
	
	-- Create the UI
	local screenGui, scrollingFrame = CreateDebugUI()
	
	-- Count gamepasses and create items
	local gamePassCount = 0
	for gamePassName, gamePassId in pairs(GamePassIds) do
		gamePassCount = gamePassCount + 1
		local itemFrame, toggleButton = CreateGamePassItem(scrollingFrame, gamePassName, gamePassId)
		
		-- Initialize button state (default to off/disabled)
		local currentState = false
		UpdateButtonState(toggleButton, currentState)
		
		-- Handle toggle button click
		toggleButton.MouseButton1Click:Connect(function()
			currentState = not currentState
			UpdateButtonState(toggleButton, currentState)
			
			-- Update the MonetizationController debug override
			MonetizationController:SetDebugGamePass(gamePassName, currentState)
			
			print(string.format("[DebugGamePass]: %s set to %s", gamePassName, tostring(currentState)))
		end)
	end
	
	print("[DebugGamePass]: Debug UI initialized with", gamePassCount, "gamepasses")
end):catch(function(err)
	warn("[DebugGamePass]: Failed to initialize -", err)
end)
