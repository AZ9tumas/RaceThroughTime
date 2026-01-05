--[[
	NotificationController
	Handles displaying notifications on the client side.
	Supports both server-triggered and local notifications.
	
	USAGE EXAMPLES:
	
	-- From another client controller:
	local NotificationController = Knit.GetController("NotificationController")
	
	-- Send a notification with a category
	NotificationController:ShowNotification("You picked up an item!", NotificationController.Category.Success)
	
	-- Send a notification with default category (no sound)
	NotificationController:ShowNotification("Something happened", NotificationController.Category.Default)
	
	-- Send an error notification
	NotificationController:ShowNotification("Connection failed!", NotificationController.Category.Error)
	
	-- Send a warning notification
	NotificationController:ShowNotification("Low fuel!", NotificationController.Category.Warning)
	
	-- Send an alert notification
	NotificationController:ShowNotification("New event available!", NotificationController.Category.Alert)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Knit = require(ReplicatedStorage.Packages.Knit)

local NotificationController = Knit.CreateController({
	Name = "NotificationController",
})

-- Notification categories (enum-like)
NotificationController.Category = {
	Default = { name = "Default", sound = nil, icon = "ℹ️" },
	Alert = { name = "Alert", sound = "AlertSound", icon = "🔔" },
	Warning = { name = "Warning", sound = "WarningSound", icon = "⚠️" },
	Error = { name = "Error", sound = "ErrorSound", icon = "❌" },
	Success = { name = "Success", sound = "SuccessSound", icon = "✅" },
	Failure = { name = "Failure", sound = "FailureSound", icon = "❌" },
}

-- Private state
local Player = Players.LocalPlayer
local PlayerGui = nil
local NotificationTemplate = nil
local NotificationContainer = nil

-- Settings
local DEFAULT_DURATION = 4
local FADE_TIME = 0.5
local SPAWN_ANIMATION_TIME = 0.15
local MAX_VISIBLE_NOTIFICATIONS = 5
local NOTIFICATION_SPACING = 8

-- Active notifications for stacking
local ActiveNotifications = {}

-- Get or create the notification container
local function GetNotificationContainer(): Frame?
	if NotificationContainer and NotificationContainer.Parent then
		return NotificationContainer
	end
	
	PlayerGui = Player:WaitForChild("PlayerGui", 10)
	if not PlayerGui then
		warn("[NotificationController]: PlayerGui not found")
		return nil
	end
	
	-- Find or create notification ScreenGui
	local screenGui = PlayerGui:WaitForChild("Essentials")
	
	-- Find or create container frame
	NotificationContainer = screenGui:WaitForChild("Notifications")
	
	return NotificationContainer
end

-- Get the notification template from ReplicatedStorage
local function GetNotificationTemplate(): GuiObject?
	if NotificationTemplate then
		return NotificationTemplate
	end
	
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	if not assets then
		warn("[NotificationController]: Assets folder not found in ReplicatedStorage")
		return nil
	end
	
	NotificationTemplate = assets:FindFirstChild("NotificationTemplate")
	if not NotificationTemplate then
		warn("[NotificationController]: NotificationTemplate not found in Assets")
		return nil
	end
	
	return NotificationTemplate
end

-- Play notification sound
local function PlaySound(soundName: string?, soundProperties: {}?)
	-- Default to a notification sound
	local effectiveSoundName = soundName or "NotificationSound"
	
	-- Try to find sound in SoundService or Assets
	local sound = SoundService:FindFirstChild(effectiveSoundName)
	if not sound then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			local sounds = assets:FindFirstChild("Sounds")
			if sounds then
				sound = sounds:FindFirstChild(effectiveSoundName)
			end
		end
	end
	
	if sound and sound:IsA("Sound") then
		local soundClone = sound:Clone()
		
		-- Apply custom properties
		if soundProperties then
			for property, value in pairs(soundProperties) do
				pcall(function()
					soundClone[property] = value
				end)
			end
		end
		
		soundClone.Parent = SoundService
		soundClone:Play()
		Debris:AddItem(soundClone, soundClone.TimeLength + 1)
	end
end

-- Remove oldest notifications if we exceed max visible
local function TrimNotifications()
	while #ActiveNotifications > MAX_VISIBLE_NOTIFICATIONS do
		local oldest = table.remove(ActiveNotifications, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
end

--[[
	Show a notification on the client.
	Can be called directly from other controllers for local notifications.
	
	@param message string - The notification message text
	@param category table - The notification category (use NotificationController.Category.X)
	@param duration number? - Optional override for duration (default: 4 seconds)
]]
function NotificationController:ShowNotification(
	message: string,
	category: { name: string, sound: string?, icon: string? }?,
	duration: number?
)
	local template = GetNotificationTemplate()
	local container = GetNotificationContainer()
	
	if not template or not container then
		warn("[NotificationController]: Failed to show notification - missing template or container")
		return
	end
	
	-- Default to Default category if not provided
	local effectiveCategory = category or NotificationController.Category.Default
	local effectiveDuration = duration or DEFAULT_DURATION
	
	-- Clone and setup notification
	local notification = template:Clone()
	
	-- Find TextLabel in notification
	local textLabel = notification:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		-- Add icon from category
		local displayText = message
		if effectiveCategory.icon then
			displayText = effectiveCategory.icon .. " " .. message
		end
		textLabel.Text = displayText
	end
	
	-- Set layout order for stacking (newer notifications appear at bottom)
	notification.LayoutOrder = os.clock() * 1000
	
	-- Initial state for spawn animation (scaled down)
	if notification:IsA("CanvasGroup") or notification:FindFirstChildWhichIsA("CanvasGroup") then
		local canvasGroup = notification:IsA("CanvasGroup") and notification or notification:FindFirstChildWhichIsA("CanvasGroup")
		if canvasGroup then
			canvasGroup.GroupTransparency = 1
		end
	end
	
	-- Scale animation setup
	local originalSize = notification.Size
	notification.Size = UDim2.new(originalSize.X.Scale * 0.8, originalSize.X.Offset, originalSize.Y.Scale * 0.8, originalSize.Y.Offset)
	
	notification.Parent = container
	
	-- Track active notification
	table.insert(ActiveNotifications, notification)
	TrimNotifications()
	
	-- Play sound from category (only if category has a sound, Default has no sound)
	if effectiveCategory.sound then
		PlaySound(effectiveCategory.sound, nil)
	end
	
	-- Spawn animation (scale up and fade in)
	task.spawn(function()
		-- Fade in and scale up
		local spawnTweenInfo = TweenInfo.new(SPAWN_ANIMATION_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local sizeTween = TweenService:Create(notification, spawnTweenInfo, { Size = originalSize })
		sizeTween:Play()
		
		-- Fade in if it's a CanvasGroup
		if notification:IsA("CanvasGroup") then
			local fadeTween = TweenService:Create(notification, TweenInfo.new(SPAWN_ANIMATION_TIME), { GroupTransparency = 0 })
			fadeTween:Play()
		end
		
		-- Wait for display duration
		task.wait(effectiveDuration - FADE_TIME)
		
		-- Fade out animation
		if notification and notification.Parent then
			local fadeOutTweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			
			if notification:IsA("CanvasGroup") then
				local fadeOutTween = TweenService:Create(notification, fadeOutTweenInfo, { GroupTransparency = 1 })
				fadeOutTween:Play()
				fadeOutTween.Completed:Wait()
			else
				task.wait(FADE_TIME)
			end
			
			-- Remove from active list
			local index = table.find(ActiveNotifications, notification)
			if index then
				table.remove(ActiveNotifications, index)
			end
			
			-- Destroy notification
			if notification and notification.Parent then
				notification:Destroy()
			end
		end
	end)
end

-- Map category name string to category enum
local function GetCategoryByName(categoryName: string?)
	if not categoryName then return NotificationController.Category.Default end
	
	for _, category in pairs(NotificationController.Category) do
		if category.name == categoryName then
			return category
		end
	end
	
	return NotificationController.Category.Default
end

-- Handle notification from server
local function OnServerNotification(notificationData: {
	message: string,
	category: string?,
	duration: number?,
})
	local category = GetCategoryByName(notificationData.category)
	NotificationController:ShowNotification(
		notificationData.message,
		category,
		notificationData.duration
	)
end

-- Knit lifecycle
function NotificationController:KnitInit()
	-- Pre-cache references
	GetNotificationTemplate()
	GetNotificationContainer()
end

function NotificationController:KnitStart()
	-- Listen for server notifications
	local NotificationService = Knit.GetService("NotificationService")
	NotificationService.ShowNotification:Connect(OnServerNotification)
end

return NotificationController
