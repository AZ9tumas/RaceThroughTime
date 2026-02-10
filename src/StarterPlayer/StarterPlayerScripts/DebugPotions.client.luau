--[[
	Debug Potions UI
	This client script creates a debug UI for viewing active potion effects in Studio.
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

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- UI Constants
local UI_COLORS = {
	Background = Color3.fromRGB(30, 30, 35),
	Header = Color3.fromRGB(35, 45, 60),
	ItemBackground = Color3.fromRGB(45, 45, 55),
	ActiveBadge = Color3.fromRGB(60, 180, 75),
	ExpiredBadge = Color3.fromRGB(180, 60, 60),
	NoPotionText = Color3.fromRGB(120, 120, 130),
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(180, 180, 180),
	TimeColor = Color3.fromRGB(100, 200, 255),
}

local REFRESH_INTERVAL = 1 -- seconds between UI refreshes

-- Create the debug UI
local function CreateDebugUI()
	-- Main ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DebugPotionsUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 1001
	screenGui.Parent = PlayerGui

	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 280, 0, 300)
	mainFrame.Position = UDim2.new(1, -290, 0, 370)
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
	headerTitle.Text = "🧪 Active Potions"
	headerTitle.TextColor3 = UI_COLORS.TextColor
	headerTitle.TextSize = 16
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = header

	-- Scrolling Frame
	local scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "PotionList"
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

	-- "No active potions" placeholder label
	local noDataLabel = Instance.new("TextLabel")
	noDataLabel.Name = "NoDataLabel"
	noDataLabel.Size = UDim2.new(1, -16, 0, 40)
	noDataLabel.BackgroundTransparency = 1
	noDataLabel.Text = "No active potions"
	noDataLabel.TextColor3 = UI_COLORS.NoPotionText
	noDataLabel.TextSize = 14
	noDataLabel.Font = Enum.Font.GothamMedium
	noDataLabel.Parent = scrollingFrame

	return screenGui, scrollingFrame, noDataLabel
end

-- Format seconds into a readable string (e.g. "4m 32s" or "∞")
local function FormatTime(seconds: number): string
	if seconds < 0 then
		return "∞"
	end

	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)

	if mins > 0 then
		return string.format("%dm %02ds", mins, secs)
	end
	return string.format("%ds", secs)
end

-- Create a single potion info item
local function CreatePotionItem(parent: ScrollingFrame, potionName: string)
	-- Item Frame
	local itemFrame = Instance.new("Frame")
	itemFrame.Name = potionName
	itemFrame.Size = UDim2.new(1, -8, 0, 56)
	itemFrame.BackgroundColor3 = UI_COLORS.ItemBackground
	itemFrame.BorderSizePixel = 0
	itemFrame.Parent = parent

	local itemCorner = Instance.new("UICorner")
	itemCorner.CornerRadius = UDim.new(0, 6)
	itemCorner.Parent = itemFrame

	-- Status badge (left side indicator bar)
	local statusBadge = Instance.new("Frame")
	statusBadge.Name = "StatusBadge"
	statusBadge.Size = UDim2.new(0, 4, 1, -12)
	statusBadge.Position = UDim2.new(0, 6, 0, 6)
	statusBadge.BackgroundColor3 = UI_COLORS.ActiveBadge
	statusBadge.BorderSizePixel = 0
	statusBadge.Parent = itemFrame

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 2)
	badgeCorner.Parent = statusBadge

	-- Potion Name Label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PotionName"
	nameLabel.Size = UDim2.new(1, -24, 0, 22)
	nameLabel.Position = UDim2.new(0, 18, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = potionName
	nameLabel.TextColor3 = UI_COLORS.TextColor
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = itemFrame

	-- Time Remaining Label
	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeRemaining"
	timeLabel.Size = UDim2.new(1, -24, 0, 18)
	timeLabel.Position = UDim2.new(0, 18, 0, 28)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = "Remaining: --"
	timeLabel.TextColor3 = UI_COLORS.TimeColor
	timeLabel.TextSize = 12
	timeLabel.Font = Enum.Font.Gotham
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Parent = itemFrame

	return itemFrame, statusBadge, timeLabel
end

-- Main initialization
Knit.OnStart():andThen(function()
	local PotionsController = Knit.GetController("PotionsController")
	local DataService = Knit.GetService("DataService")

	-- Create the UI
	local screenGui, scrollingFrame, noDataLabel = CreateDebugUI()

	-- Cache of created item frames: { [potionName] = { frame, badge, timeLabel } }
	local itemCache = {}

	-- Update the UI with current potion data
	local function RefreshUI()
		local activePotions = PotionsController:GetActivePotions()

		-- Determine which potions are currently active
		local activeNames = {}
		for potionName, _ in pairs(activePotions) do
			activeNames[potionName] = true
		end

		-- Remove items that are no longer active
		for potionName, entry in pairs(itemCache) do
			if not activeNames[potionName] then
				entry.frame:Destroy()
				itemCache[potionName] = nil
			end
		end

		-- Add / update items for each active potion
		local count = 0
		for potionName, _ in pairs(activePotions) do
			count = count + 1

			-- Create item if it doesn't exist yet
			if not itemCache[potionName] then
				local frame, badge, timeLabel = CreatePotionItem(scrollingFrame, potionName)
				itemCache[potionName] = { frame = frame, badge = badge, timeLabel = timeLabel }
			end

			-- Update remaining time
			local entry = itemCache[potionName]
			local ok, remaining = pcall(function()
				return PotionsController:GetRemainingTime(potionName)
			end)

            print(remaining)

			if ok and remaining then
				entry.timeLabel.Text = "Remaining: " .. FormatTime(remaining)

				-- Flash badge to warn when low
				if remaining > 0 and remaining < 60 then
					entry.badge.BackgroundColor3 = Color3.fromRGB(255, 170, 50) -- orange warning
				else
					entry.badge.BackgroundColor3 = UI_COLORS.ActiveBadge
				end
			else
				entry.timeLabel.Text = "Remaining: --"
				entry.badge.BackgroundColor3 = UI_COLORS.ActiveBadge
			end
		end

		-- Toggle placeholder visibility
		noDataLabel.Visible = (count == 0)
	end

	-- Initial refresh
	RefreshUI()

	-- Refresh immediately when server fires DataReady (potion added/expired/data changed)
	DataService.DataReady:Connect(function(_newData)
		RefreshUI()
	end)

	-- Periodic refresh loop (keeps countdown timers ticking between data changes)
	task.spawn(function()
		while screenGui and screenGui.Parent do
			task.wait(REFRESH_INTERVAL)
			RefreshUI()
		end
	end)

	print("[DebugPotions]: Debug UI initialized")
end):catch(function(err)
	warn("[DebugPotions]: Failed to initialize -", err)
end)
