--[[
	NotificationService
	Handles sending notifications to clients from the server.
	Uses Knit framework for client-server communication.
	
	USAGE EXAMPLES:
	
	-- From another server service:
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Send a notification with a category
	NotificationService:SendNotification(player, "Welcome to the game!", NotificationService.Category.Success)
	
	-- Send a notification with default category (no sound)
	NotificationService:SendNotification(player, "Something happened", NotificationService.Category.Default)
	
	-- Send an error notification
	NotificationService:SendNotification(player, "Connection failed!", NotificationService.Category.Error)
	
	-- Send a warning notification
	NotificationService:SendNotification(player, "Low fuel!", NotificationService.Category.Warning)
	
	-- Broadcast to all players
	NotificationService:BroadcastNotification("Server shutting down in 5 minutes!", NotificationService.Category.Alert)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local NotificationService = Knit.CreateService({
	Name = "NotificationService",
	Client = {
		ShowNotification = Knit.CreateSignal(), -- Signal to tell client to show a notification
	},
})

-- Notification categories (enum-like) - mirrors client-side categories
NotificationService.Category = {
	Default = { name = "Default" },
	Alert = { name = "Alert" },
	Warning = { name = "Warning" },
	Error = { name = "Error" },
	Success = { name = "Success" },
	Failure = { name = "Failure" },
}

-- Default notification settings
local DEFAULT_DURATION = 4

--[[
	Send a notification to a specific player.
	
	@param player Player - The player to send the notification to
	@param message string - The notification message text
	@param category table - The notification category (use NotificationService.Category.X)
	@param duration number? - Optional override for duration (default: 4 seconds)
]]
function NotificationService:SendNotification(
	player: Player,
	message: string,
	category: { name: string }?,
	duration: number?
)
	if not player or not player:IsDescendantOf(Players) then
		warn("[NotificationService]: Invalid player provided")
		return
	end
	
	local effectiveCategory = category or NotificationService.Category.Default
	
	local notificationData = {
		message = message,
		category = effectiveCategory.name,
		duration = duration or DEFAULT_DURATION,
	}
	
	self.Client.ShowNotification:Fire(player, notificationData)
end

--[[
	Broadcast a notification to all connected players.
	
	@param message string - The notification message text
	@param category table - The notification category (use NotificationService.Category.X)
	@param duration number? - Optional override for duration (default: 4 seconds)
]]
function NotificationService:BroadcastNotification(
	message: string,
	category: { name: string }?,
	duration: number?
)
	for _, player in Players:GetPlayers() do
		self:SendNotification(player, message, category, duration)
	end
end

-- Knit lifecycle
function NotificationService:KnitInit()
	-- Service initialization
end

function NotificationService:KnitStart()
	-- Service started
end

return NotificationService
