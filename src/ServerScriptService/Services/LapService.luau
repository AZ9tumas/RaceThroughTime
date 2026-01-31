--[[
	LapService
	Tracks lap information for players during track runs.
	Exposes lap data publicly so other services and clients can access it.
	
	USAGE EXAMPLES:
	
	-- From client:
	local LapService = Knit.GetService("LapService")
	local lapInfo = LapService:GetLapInfo(player)
	-- lapInfo = { LaunchWorldName = "Main", TargetWorldName = "StoneAge", LapPercentage = 0.5, Player = player }
	
	-- From server:
	local LapService = Knit.GetService("LapService")
	local lapInfo = LapService:GetLapInfoForPlayer(player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

export type LapInfo = {
	LaunchWorldName: string,
	TargetWorldName: string,
	LapPercentage: number,
	Player: Player,
}

local LapService = Knit.CreateService({
	Name = "LapService",
	Client = {},
})

local PlayerLapInfo: { [number]: LapInfo } = {}

function LapService:StartTracking(player: Player, launchWorld: string, targetWorld: string)
	PlayerLapInfo[player.UserId] = {
		LaunchWorldName = launchWorld,
		TargetWorldName = targetWorld,
		LapPercentage = 0,
		Player = player,
	}
end

function LapService:UpdateLapPercentage(player: Player, percentage: number)
	local info = PlayerLapInfo[player.UserId]
	if info then
		info.LapPercentage = math.clamp(percentage, 0, 1)
	end
end

function LapService:StopTracking(player: Player)
	PlayerLapInfo[player.UserId] = nil
end

function LapService:GetLapInfoForPlayer(player: Player): LapInfo?
	return PlayerLapInfo[player.UserId]
end

function LapService.Client:GetLapInfo(player: Player, targetPlayer: Player): LapInfo?
	return LapService:GetLapInfoForPlayer(targetPlayer)
end

function LapService.Client:UpdateLapPercentage(player: Player, percentage: number)
	LapService:UpdateLapPercentage(player, percentage)
end

function LapService:KnitInit()
	Players.PlayerRemoving:Connect(function(player)
		PlayerLapInfo[player.UserId] = nil
	end)
end

function LapService:KnitStart()
end

return LapService
