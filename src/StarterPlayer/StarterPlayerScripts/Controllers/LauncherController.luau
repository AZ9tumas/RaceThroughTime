--[[
	LauncherController
	Client-side controller for displaying launcher upgrade progress in 3D world UI.
	
	Updates the LauncherZone BillboardGui in each world showing:
	- Current level and multiplier
	- Target level multiplier
	- Progress towards next level
	- Required max distance
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LauncherController = Knit.CreateController({
	Name = "LauncherController",
})

-- Launcher multiplier constants (must match LauncherService)
local BASE_MULTIPLIER = 1.1
local MULTIPLIER_GROWTH_RATE = 1.523

-- Private state
local Player = Players.LocalPlayer
local LauncherService = nil
local DataService = nil
local NotificationController = nil
local CurrentWorldName = "Main"

-- UI references (cached per world)
local CurrentLevelLabel = nil
local CurrentMultiplierLabel = nil
local TargetMultiplierLabel = nil
local PercentageLabel = nil
local ProgressLabel = nil
local ProgressFrame = nil

-- Touch connections (cached per world for cleanup)
local CurrentBaseTouchConnection = nil
local UpgradeDebounce = false
local UPGRADE_DEBOUNCE_TIME = 1 -- Seconds between upgrade attempts

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[LauncherController]: %s", message))
end

-- Get the current world name from player attribute or data
local function GetCurrentWorld(): string
	local worldAttr = Player:GetAttribute("CurrentWorld")
	if worldAttr then
		return worldAttr
	end
	return CurrentWorldName
end

-- Find the LauncherZone folder in a world
local function GetLauncherZone(worldName: string): Folder?
	local worldFolder = Workspace:FindFirstChild(worldName)
	if not worldFolder then
		return nil
	end
	return worldFolder:FindFirstChild("LauncherZone")
end

-- Handle touch on CurrentBase to upgrade launcher
local function OnCurrentBaseTouched(hit: BasePart)
	-- Check if it's the local player's character
	local character = Player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- Check if the hit part belongs to the player's character
	if not hit:IsDescendantOf(character) then return end
	
	-- Debounce to prevent spam
	if UpgradeDebounce then return end
	UpgradeDebounce = true
	
	-- Request upgrade from server
	if LauncherService then
		local success, errorMsg, _resultData = LauncherService:RequestUpgrade()
		
		-- If failed and no notification was sent by server, show client-side notification
		if not success and NotificationController then
			-- Server already sends notifications, but we can add additional feedback if needed
			Log(string.format("Upgrade failed: %s", errorMsg or "Unknown error"))
		end
	end
	
	-- Reset debounce after delay
	task.delay(UPGRADE_DEBOUNCE_TIME, function()
		UpgradeDebounce = false
	end)
end

-- Setup touch event for CurrentBase in the launcher zone
local function SetupCurrentBaseTouch(worldName: string)
	-- Disconnect existing connection if any
	if CurrentBaseTouchConnection then
		CurrentBaseTouchConnection:Disconnect()
		CurrentBaseTouchConnection = nil
	end
	
	local launcherZone = GetLauncherZone(worldName)
	if not launcherZone then
		Log(string.format("LauncherZone not found in world %s for touch setup", worldName))
		return false
	end
	
	-- Find CurrentBase part
	local currentBase = launcherZone:FindFirstChild("CurrentBase")
	if not currentBase or not currentBase:IsA("BasePart") then
		Log(string.format("CurrentBase not found in LauncherZone for world %s", worldName))
		return false
	end
	
	-- Connect touch event
	CurrentBaseTouchConnection = currentBase.Touched:Connect(OnCurrentBaseTouched)
	Log(string.format("Setup CurrentBase touch for world %s", worldName))
	return true
end

-- Cache UI references for the current world
local function CacheUIReferences(worldName: string)
	local launcherZone = GetLauncherZone(worldName)
	if not launcherZone then
		Log(string.format("LauncherZone not found in world %s", worldName))
		CurrentLevelLabel = nil
		CurrentMultiplierLabel = nil
		TargetMultiplierLabel = nil
		PercentageLabel = nil
		ProgressLabel = nil
		ProgressFrame = nil
		return false
	end
	
	-- Get Current section
	local currentSection = launcherZone:FindFirstChild("Current")
	if currentSection then
		local uiPart = currentSection:FindFirstChild("UIPart")
		if uiPart then
			local billboardGui = uiPart:FindFirstChild("BillboardGui")
			if billboardGui then
				CurrentLevelLabel = billboardGui:FindFirstChild("Level")
				CurrentMultiplierLabel = billboardGui:FindFirstChild("Multiplier")
			end
		end
	end
	
	-- Get Target section
	local targetSection = launcherZone:FindFirstChild("Target")
	if targetSection then
		local uiPart = targetSection:FindFirstChild("UIPart")
		if uiPart then
			local billboardGui = uiPart:FindFirstChild("BillboardGui")
			if billboardGui then
				TargetMultiplierLabel = billboardGui:FindFirstChild("Multiplier")
				PercentageLabel = billboardGui:FindFirstChild("Percentage")
				ProgressLabel = billboardGui:FindFirstChild("ProgressLabel")
				ProgressFrame = billboardGui:FindFirstChild("Progress")
			end
		end
	end
	
	-- Setup touch event for CurrentBase
	SetupCurrentBaseTouch(worldName)
	
	Log(string.format("Cached UI references for world %s", worldName))
	return true
end

-- Format multiplier for display
local function FormatMultiplier(multiplier: number): string
	return string.format("x%.2f", multiplier)
end

-- Format percentage for display
local function FormatPercentage(progress: number): string
	return string.format("%.1f%%", progress * 100)
end

-- Format distance for display
local function FormatDistance(distance: number): string
	if distance >= 1000000 then
		return string.format("%.2fM", distance / 1000000)
	elseif distance >= 1000 then
		return string.format("%.1fK", distance / 1000)
	else
		return string.format("%.0f", distance)
	end
end

-- Update the launcher UI with current data
function LauncherController:UpdateLauncherUI()
	if not LauncherService then
		Log("LauncherService not available")
		return
	end
	
	-- Get launcher info from server
	local success, launcherInfo = pcall(function()
		return LauncherService:GetLauncherInfo()
	end)
	
	if not success or not launcherInfo then
		Log("Failed to get launcher info")
		return
	end
	
	self:UpdateLauncherUIFromInfo(launcherInfo)
end

-- Update the launcher UI with provided launcher info (called from UpdateLauncherClient signal)
function LauncherController:UpdateLauncherUIFromInfo(launcherInfo)
	if not launcherInfo then
		Log("No launcher info provided")
		return
	end
	
	local level = launcherInfo.Level or 1
	local multiplier = launcherInfo.Multiplier or BASE_MULTIPLIER
	local maxDistance = launcherInfo.MaxDistance or 0
	local nextRequirement = launcherInfo.NextRequirement or 1000
	local progress = launcherInfo.Progress or 0
	
	-- Calculate target level multiplier
	local targetLevel = level + 1
	local targetMultiplier = BASE_MULTIPLIER * math.pow(MULTIPLIER_GROWTH_RATE, targetLevel - 1)
	
	-- Update Current section UI
	if CurrentLevelLabel and CurrentLevelLabel:IsA("TextLabel") then
		CurrentLevelLabel.Text = tostring(level)
	end
	
	if CurrentMultiplierLabel and CurrentMultiplierLabel:IsA("TextLabel") then
		CurrentMultiplierLabel.Text = FormatMultiplier(multiplier)
	end
	
	-- Update Target section UI
	if TargetMultiplierLabel and TargetMultiplierLabel:IsA("TextLabel") then
		TargetMultiplierLabel.Text = FormatMultiplier(targetMultiplier)
	end
	
	if PercentageLabel and PercentageLabel:IsA("TextLabel") then
		PercentageLabel.Text = FormatPercentage(progress)
	end
	
	if ProgressLabel and ProgressLabel:IsA("TextLabel") then
		ProgressLabel.Text = "Reach " .. FormatDistance(nextRequirement)
	end
	
	-- Update progress bar if it exists
	if ProgressFrame and ProgressFrame:IsA("Frame") then
		-- Look for a fill frame inside Progress
		local fillFrame = ProgressFrame:FindFirstChild("Fill")
		if fillFrame and fillFrame:IsA("Frame") then
			fillFrame.Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
		end
	end
	
	Log(string.format("Updated launcher UI - Level: %d, Multiplier: %.2f, Progress: %.1f%%", level, multiplier, progress * 100))
end

-- Handle world change
function LauncherController:OnWorldChanged(newWorldName: string)
	CurrentWorldName = newWorldName
	CacheUIReferences(newWorldName)
	self:UpdateLauncherUI()
end

-- Knit lifecycle
function LauncherController:KnitInit()
	Log("LauncherController initialized")
end

function LauncherController:KnitStart()
	LauncherService = Knit.GetService("LauncherService")
	DataService = Knit.GetService("DataService")
	NotificationController = Knit.GetController("NotificationController")
	
	-- Get initial world
	CurrentWorldName = GetCurrentWorld()
	CacheUIReferences(CurrentWorldName)
	
	-- Listen for UpdateLauncherClient signal from server (fires after any data update)
	LauncherService.UpdateLauncherClient:Connect(function(launcherInfo)
		self:UpdateLauncherUIFromInfo(launcherInfo)
	end)
	
	-- Listen for world change attribute to re-cache UI references
	Player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		local newWorld = Player:GetAttribute("CurrentWorld")
		if newWorld and newWorld ~= CurrentWorldName then
			self:OnWorldChanged(newWorld)
		end
	end)
	
	-- Listen for launcher upgrades (still useful for immediate feedback)
	LauncherService.LauncherUpgraded:Connect(function(_resultData)
		self:UpdateLauncherUI()
	end)
	
	-- Initial UI update
	task.defer(function()
		self:UpdateLauncherUI()
	end)
	
	Log("LauncherController started")
end

return LauncherController
