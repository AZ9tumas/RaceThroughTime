--[[
	LoadingScreenService
	Handles sending loading screen signals to clients from the server.
	Uses Knit framework for client-server communication.
	
	USAGE EXAMPLES:
	
	-- From another server service:
	local LoadingScreenService = Knit.GetService("LoadingScreenService")
	
	-- Show loading screen for a player with default duration (0.2s)
	LoadingScreenService:ShowLoadingScreen(player)
	
	-- Show loading screen for a player with custom duration
	LoadingScreenService:ShowLoadingScreen(player, 0.5)
	
	-- Hide loading screen for a player
	LoadingScreenService:HideLoadingScreen(player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LoadingScreenService = Knit.CreateService({
	Name = "LoadingScreenService",
	Client = {
		ShowLoadingScreen = Knit.CreateSignal(), -- Signal to tell client to show loading screen
		HideLoadingScreen = Knit.CreateSignal(), -- Signal to tell client to hide loading screen
	},
})

-- Default loading screen display time
local DEFAULT_TIME_FRAME = 0.2

--[[
	Show loading screen for a specific player.
	
	@param player Player - The player to show the loading screen to
	@param timeFrame number? - Duration to show loading screen (default: 0.2 seconds)
]]
function LoadingScreenService:ShowLoadingScreen(player: Player, timeFrame: number?)
	if not player or not player:IsDescendantOf(Players) then
		warn("[LoadingScreenService]: Invalid player provided")
		return
	end
	
	local duration = timeFrame or DEFAULT_TIME_FRAME
	
	self.Client.ShowLoadingScreen:Fire(player, duration)
end

--[[
	Hide loading screen for a specific player.
	
	@param player Player - The player to hide the loading screen for
]]
function LoadingScreenService:HideLoadingScreen(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		warn("[LoadingScreenService]: Invalid player provided")
		return
	end
	
	self.Client.HideLoadingScreen:Fire(player)
end

--[[
	Broadcast loading screen show to all connected players.
	
	@param timeFrame number? - Duration to show loading screen (default: 0.2 seconds)
]]
function LoadingScreenService:BroadcastShowLoadingScreen(timeFrame: number?)
	for _, player in Players:GetPlayers() do
		self:ShowLoadingScreen(player, timeFrame)
	end
end

--[[
	Broadcast loading screen hide to all connected players.
]]
function LoadingScreenService:BroadcastHideLoadingScreen()
	for _, player in Players:GetPlayers() do
		self:HideLoadingScreen(player)
	end
end

-- Knit lifecycle
function LoadingScreenService:KnitInit()
	-- Service initialization
end

function LoadingScreenService:KnitStart()
	-- Service started
end

return LoadingScreenService
