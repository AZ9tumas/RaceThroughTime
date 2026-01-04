--[[
	NotificationService
	Handles sending notifications to clients from the server.
	Works with NotificationController to display UI notifications.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local NotificationService = Knit.CreateService({
	Name = "NotificationService",
	Client = {
		ShowNotification = Knit.CreateSignal(), -- Signal to show notification on client
	},
})

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[NotificationService]: %s", message))
end

--[=[
	Sends a notification to a specific player from the server.
	
	@param player Player -- The player to send the notification to
	@param title string -- The title of the notification
	@param message string -- The message content of the notification
	@param duration number? -- Optional duration in seconds (defaults to 3)
	@param notificationType string? -- Optional type: "Info", "Success", "Warning", "Error" (defaults to "Info")
	
	Example usage:
	```lua
	local NotificationService = Knit.GetService("NotificationService")
	NotificationService:Notify(player, "Welcome!", "Thanks for playing Race Through Time!", 5, "Success")
	```
]=]
function NotificationService:Notify(player: Player, title: string, message: string, duration: number?, notificationType: string?)
	if not player or not player:IsDescendantOf(game.Players) then
		warn("[NotificationService]: Invalid player provided")
		return
	end
	
	local notificationData = {
		Title = title or "Notification",
		Message = message or "",
		Duration = duration or 3,
		Type = notificationType or "Info",
	}
	
	self.Client.ShowNotification:Fire(player, notificationData)
	Log(string.format("Sent notification to %s: %s", player.Name, title))
end

--[=[
	Sends a notification to all players on the server.
	
	@param title string -- The title of the notification
	@param message string -- The message content of the notification
	@param duration number? -- Optional duration in seconds (defaults to 3)
	@param notificationType string? -- Optional type: "Info", "Success", "Warning", "Error" (defaults to "Info")
	
	Example usage:
	```lua
	local NotificationService = Knit.GetService("NotificationService")
	NotificationService:NotifyAll("Server Update", "The server will restart in 5 minutes!", 10, "Warning")
	```
]=]
function NotificationService:NotifyAll(title: string, message: string, duration: number?, notificationType: string?)
	local notificationData = {
		Title = title or "Notification",
		Message = message or "",
		Duration = duration or 3,
		Type = notificationType or "Info",
	}
	
	self.Client.ShowNotification:FireAll(notificationData)
	Log(string.format("Sent notification to all players: %s", title))
end

--[=[
	Sends a notification to multiple specific players.
	
	@param players {Player} -- Array of players to send the notification to
	@param title string -- The title of the notification
	@param message string -- The message content of the notification
	@param duration number? -- Optional duration in seconds (defaults to 3)
	@param notificationType string? -- Optional type: "Info", "Success", "Warning", "Error" (defaults to "Info")
	
	Example usage:
	```lua
	local NotificationService = Knit.GetService("NotificationService")
	local team = {player1, player2, player3}
	NotificationService:NotifyMultiple(team, "Team Alert", "Your team won the race!", 5, "Success")
	```
]=]
function NotificationService:NotifyMultiple(players: {Player}, title: string, message: string, duration: number?, notificationType: string?)
	local notificationData = {
		Title = title or "Notification",
		Message = message or "",
		Duration = duration or 3,
		Type = notificationType or "Info",
	}
	
	for _, player in ipairs(players) do
		if player and player:IsDescendantOf(game.Players) then
			self.Client.ShowNotification:Fire(player, notificationData)
		end
	end
	
	Log(string.format("Sent notification to %d players: %s", #players, title))
end

-- Knit lifecycle
function NotificationService:KnitInit()
	Log("NotificationService initialized")
end

function NotificationService:KnitStart()
	Log("NotificationService started")
end

return NotificationService
