--[[
	NotificationController
	Handles displaying notifications on the client side.
	Can show notifications from both server and client sources.
	
	Note: NotificationTemplate UI should be located at ReplicatedStorage.Assets.NotificationTemplate
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local NotificationController = Knit.CreateController({
	Name = "NotificationController",
})

-- Private state
local NotificationTemplate = nil
local NotificationContainer = nil
local ActiveNotifications = {} -- Array of active notification frames with cleanup data
local NotificationQueue = {} -- Queue for notifications waiting to be displayed
local MaxVisibleNotifications = 3 -- Maximum number of notifications shown at once

-- Configuration
local Config = {
	NotificationSpacing = 10, -- Vertical spacing between notifications
	AnimationDuration = 0.3, -- Duration of slide-in/out animations
	DefaultDuration = 3, -- Default notification display time
	TypeColors = {
		Info = Color3.fromRGB(52, 152, 219), -- Blue
		Success = Color3.fromRGB(46, 204, 113), -- Green
		Warning = Color3.fromRGB(241, 196, 15), -- Yellow/Orange
		Error = Color3.fromRGB(231, 76, 60), -- Red
	},
}

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[NotificationController]: %s", message))
end

-- Get or cache the notification template
local function GetNotificationTemplate()
	if NotificationTemplate then
		return NotificationTemplate
	end
	
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	if not assets then
		warn("[NotificationController]: Assets folder not found in ReplicatedStorage")
		return nil
	end
	
	NotificationTemplate = assets:WaitForChild("NotificationTemplate", 10)
	if not NotificationTemplate then
		warn("[NotificationController]: NotificationTemplate not found in ReplicatedStorage.Assets")
		return nil
	end
	
	return NotificationTemplate
end

-- Get or create the notification container in PlayerGui
local function GetNotificationContainer()
	if NotificationContainer and NotificationContainer.Parent then
		return NotificationContainer
	end
	
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Check if container already exists
	NotificationContainer = playerGui:FindFirstChild("NotificationContainer")
	if NotificationContainer then
		return NotificationContainer
	end
	
	-- Create new container
	NotificationContainer = Instance.new("ScreenGui")
	NotificationContainer.Name = "NotificationContainer"
	NotificationContainer.ResetOnSpawn = false
	NotificationContainer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	NotificationContainer.DisplayOrder = 10 -- High display order to appear above most UI
	
	-- Create a frame to hold notifications
	local listFrame = Instance.new("Frame")
	listFrame.Name = "NotificationList"
	listFrame.Size = UDim2.new(0, 300, 1, 0)
	listFrame.Position = UDim2.new(1, -320, 0, 20)
	listFrame.BackgroundTransparency = 1
	listFrame.Parent = NotificationContainer
	
	-- Add UIListLayout for automatic positioning
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, Config.NotificationSpacing)
	listLayout.Parent = listFrame
	
	NotificationContainer.Parent = playerGui
	
	return NotificationContainer
end

-- Update positions of all active notifications
local function UpdateNotificationPositions()
	-- Positions are automatically handled by UIListLayout
	-- No custom logic needed
end

-- Remove a notification from the display
local function RemoveNotification(notificationFrame: Frame, cleanupThread: thread?)
	if not notificationFrame or not notificationFrame.Parent then
		return
	end
	
	-- Cancel the auto-removal thread if it exists
	if cleanupThread and coroutine.status(cleanupThread) == "suspended" then
		task.cancel(cleanupThread)
	end
	
	-- Find and remove from active notifications
	for i, data in ipairs(ActiveNotifications) do
		if data.frame == notificationFrame then
			table.remove(ActiveNotifications, i)
			break
		end
	end
	
	-- Animate out
	local tweenInfo = TweenInfo.new(Config.AnimationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(notificationFrame, tweenInfo, {
		Position = UDim2.new(1, 20, notificationFrame.Position.Y.Scale, notificationFrame.Position.Y.Offset),
		BackgroundTransparency = 1,
	})
	
	-- Also tween text transparency
	local title = notificationFrame:FindFirstChild("Title")
	local message = notificationFrame:FindFirstChild("Message")
	if title then
		TweenService:Create(title, tweenInfo, { TextTransparency = 1 }):Play()
	end
	if message then
		TweenService:Create(message, tweenInfo, { TextTransparency = 1 }):Play()
	end
	
	tween.Completed:Connect(function()
		notificationFrame:Destroy()
		
		-- Process queue if there are waiting notifications
		if #NotificationQueue > 0 then
			local nextNotification = table.remove(NotificationQueue, 1)
			task.spawn(function()
				DisplayNotification(
					nextNotification.Title,
					nextNotification.Message,
					nextNotification.Duration,
					nextNotification.Type
				)
			end)
		end
	end)
	
	tween:Play()
end

-- Display a notification on screen
local function DisplayNotification(title: string, message: string, duration: number, notificationType: string)
	local template = GetNotificationTemplate()
	local container = GetNotificationContainer()
	
	if not template or not container then
		warn("[NotificationController]: Cannot display notification - template or container missing")
		return
	end
	
	-- Check if we've hit the max visible notifications
	if #ActiveNotifications >= MaxVisibleNotifications then
		table.insert(NotificationQueue, {
			Title = title,
			Message = message,
			Duration = duration,
			Type = notificationType,
		})
		return
	end
	
	local listFrame = container:FindFirstChild("NotificationList")
	if not listFrame then
		warn("[NotificationController]: NotificationList frame not found")
		return
	end
	
	-- Clone the template
	local notificationFrame = template:Clone()
	notificationFrame.Visible = true
	notificationFrame.LayoutOrder = #ActiveNotifications
	
	-- Set up the notification content
	local titleLabel = notificationFrame:FindFirstChild("Title")
	local messageLabel = notificationFrame:FindFirstChild("Message")
	local typeIndicator = notificationFrame:FindFirstChild("TypeIndicator")
	
	if titleLabel then
		titleLabel.Text = title
	end
	
	if messageLabel then
		messageLabel.Text = message
	end
	
	-- Set color based on type
	local typeColor = Config.TypeColors[notificationType] or Config.TypeColors.Info
	if typeIndicator then
		typeIndicator.BackgroundColor3 = typeColor
	elseif notificationFrame:IsA("Frame") then
		-- If no type indicator, color the border or background accent
		notificationFrame.BorderColor3 = typeColor
	end
	
	-- Store original position for animation
	local originalPosition = notificationFrame.Position
	notificationFrame.Position = UDim2.new(1, 20, originalPosition.Y.Scale, originalPosition.Y.Offset)
	notificationFrame.Parent = listFrame
	
	-- Animate in
	local tweenInfo = TweenInfo.new(Config.AnimationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(notificationFrame, tweenInfo, {
		Position = originalPosition,
	})
	tween:Play()
	
	-- Add to active notifications with cleanup tracking
	local cleanupThread = task.delay(duration, function()
		RemoveNotification(notificationFrame, nil)
	end)
	
	table.insert(ActiveNotifications, {
		frame = notificationFrame,
		cleanupThread = cleanupThread,
	})
	
	Log(string.format("Displayed notification: %s", title))
end

-- Handle server notification signal
local function OnServerNotification(notificationData: {Title: string, Message: string, Duration: number, Type: string})
	DisplayNotification(
		notificationData.Title,
		notificationData.Message,
		notificationData.Duration or Config.DefaultDuration,
		notificationData.Type or "Info"
	)
end

--[=[
	Show a notification on the client (local only).
	This can be called from any client script to display a notification.
	
	@param title string -- The title of the notification
	@param message string -- The message content of the notification
	@param duration number? -- Optional duration in seconds (defaults to 3)
	@param notificationType string? -- Optional type: "Info", "Success", "Warning", "Error" (defaults to "Info")
	
	Example usage from a client script:
	```lua
	local NotificationController = Knit.GetController("NotificationController")
	NotificationController:Show("Achievement Unlocked!", "You collected 100 stars!", 5, "Success")
	```
]=]
function NotificationController:Show(title: string, message: string, duration: number?, notificationType: string?)
	DisplayNotification(
		title or "Notification",
		message or "",
		duration or Config.DefaultDuration,
		notificationType or "Info"
	)
end

--[=[
	Shows an info notification (convenience method).
]=]
function NotificationController:ShowInfo(title: string, message: string, duration: number?)
	self:Show(title, message, duration, "Info")
end

--[=[
	Shows a success notification (convenience method).
]=]
function NotificationController:ShowSuccess(title: string, message: string, duration: number?)
	self:Show(title, message, duration, "Success")
end

--[=[
	Shows a warning notification (convenience method).
]=]
function NotificationController:ShowWarning(title: string, message: string, duration: number?)
	self:Show(title, message, duration, "Warning")
end

--[=[
	Shows an error notification (convenience method).
]=]
function NotificationController:ShowError(title: string, message: string, duration: number?)
	self:Show(title, message, duration, "Error")
end

--[=[
	Clears all active notifications immediately.
]=]
function NotificationController:ClearAll()
	for _, data in ipairs(ActiveNotifications) do
		if data.frame and data.frame.Parent then
			data.frame:Destroy()
		end
		if data.cleanupThread and coroutine.status(data.cleanupThread) == "suspended" then
			task.cancel(data.cleanupThread)
		end
	end
	ActiveNotifications = {}
	NotificationQueue = {}
	Log("Cleared all notifications")
end

-- Knit lifecycle
function NotificationController:KnitInit()
	-- Pre-cache the template
	GetNotificationTemplate()
	Log("NotificationController initialized")
end

function NotificationController:KnitStart()
	-- Set up container
	GetNotificationContainer()
	
	-- Listen for server notifications
	local NotificationService = Knit.GetService("NotificationService")
	NotificationService.ShowNotification:Connect(OnServerNotification)
	
	Log("NotificationController started")
end

return NotificationController
