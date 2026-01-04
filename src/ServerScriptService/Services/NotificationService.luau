--[[
	NotificationService
	Handles sending notifications to clients from the server.
	Uses Knit framework for client-server communication.
	
	USAGE EXAMPLES:
	
	-- From another server service:
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Send a simple notification to a player
	NotificationService:SendNotification(player, "Welcome to the game!")
	
	-- Send a notification with custom duration (in seconds)
	NotificationService:SendNotification(player, "You earned 100 coins!", 5)
	
	-- Send a notification with custom sound
	NotificationService:SendNotification(player, "Achievement Unlocked!", 4, "AchievementSound")
	
	-- Send a notification with icon (emoji or text)
	NotificationService:SendNotification(player, "Level Up!", 4, nil, {
		icon = "🎉",
		iconColor = Color3.fromRGB(255, 215, 0)
	})
	
	-- Broadcast to all players
	NotificationService:BroadcastNotification("Server shutting down in 5 minutes!")
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

-- Default notification settings
local DEFAULT_DURATION = 4

--[[
	Send a notification to a specific player.
	
	@param player Player - The player to send the notification to
	@param text string - The notification message text
	@param duration number? - How long the notification stays visible (default: 4 seconds)
	@param sound string? - Optional sound name to play
	@param options table? - Additional options:
		- icon: string - An icon/emoji to display
		- iconColor: Color3 - Color for the icon
		- soundProperties: table - Properties for the sound
]]
function NotificationService:SendNotification(
	player: Player,
	text: string,
	duration: number?,
	sound: string?,
	options: { icon: string?, iconColor: Color3?, soundProperties: {}? }?
)
	if not player or not player:IsDescendantOf(Players) then
		warn("[NotificationService]: Invalid player provided")
		return
	end
	
	local notificationData = {
		text = text,
		duration = duration or DEFAULT_DURATION,
		sound = sound,
		icon = options and options.icon,
		iconColor = options and options.iconColor,
		soundProperties = options and options.soundProperties,
	}
	
	self.Client.ShowNotification:Fire(player, notificationData)
end

--[[
	Broadcast a notification to all connected players.
	
	@param text string - The notification message text
	@param duration number? - How long the notification stays visible (default: 4 seconds)
	@param sound string? - Optional sound name to play
	@param options table? - Additional options (same as SendNotification)
]]
function NotificationService:BroadcastNotification(
	text: string,
	duration: number?,
	sound: string?,
	options: { icon: string?, iconColor: Color3?, soundProperties: {}? }?
)
	for _, player in Players:GetPlayers() do
		self:SendNotification(player, text, duration, sound, options)
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
