--[[
	LapService
	Tracks lap information for players during track runs.
	Uses ReplicatedStorage NumberValues for efficient replication (no RemoteEvents).
	Server calculates lap percentage based on elapsed time and track parameters.
	
	USAGE EXAMPLES:
	
	-- From client (reading from ReplicatedStorage):
	local playerLapsFolder = ReplicatedStorage:FindFirstChild("PlayerLaps")
	local lapValue = playerLapsFolder and playerLapsFolder:FindFirstChild(tostring(player.UserId))
	if lapValue then
	    local percentage = lapValue.Value
	    local launchWorld = lapValue:GetAttribute("LaunchWorldName")
	    local targetWorld = lapValue:GetAttribute("TargetWorldName")
	end
	
	-- From client (via service):
	local LapService = Knit.GetService("LapService")
	local lapInfo = LapService:GetLapInfo(player)
	
	-- From server:
	local LapService = Knit.GetService("LapService")
	local lapInfo = LapService:GetLapInfoForPlayer(player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

export type LapInfo = {
	LaunchWorldName: string,
	TargetWorldName: string,
	LapPercentage: number,
	Player: Player,
}

export type TrackingData = {
	player: Player,
	launchWorld: string,
	targetWorld: string,
	startTime: number,
	startAngle: number,
	initialSpeed: number,
	acceleration: number,
	maxSpeed: number,
	worldRadius: number,
}

local LapService = Knit.CreateService({
	Name = "LapService",
	Client = {},
})

local PlayerLapsFolder: Folder = nil
local TrackedPlayers: { [number]: TrackingData } = {}

local function GetOrCreatePlayerLapsFolder(): Folder
	if PlayerLapsFolder then
		return PlayerLapsFolder
	end
	
	PlayerLapsFolder = ReplicatedStorage:FindFirstChild("PlayerLaps")
	if not PlayerLapsFolder then
		PlayerLapsFolder = Instance.new("Folder")
		PlayerLapsFolder.Name = "PlayerLaps"
		PlayerLapsFolder.Parent = ReplicatedStorage
	end
	
	return PlayerLapsFolder
end

local function GetPlayerLapValue(player: Player): NumberValue?
	local folder = GetOrCreatePlayerLapsFolder()
	return folder:FindFirstChild(tostring(player.UserId))
end

local function CalculateLapPercentage(data: TrackingData): number
	local elapsedTime = tick() - data.startTime
	
	local totalAngle = 0
	local timeStep = 0.1
	local t = 0
	
	while t < elapsedTime do
		local currentSpeed = Stats.CalculateCurrentSpeed(
			data.initialSpeed,
			data.acceleration,
			data.maxSpeed,
			t
		)
		local physicalSpeed = math.min(currentSpeed, Stats.MaxPhysicalSpeed)
		local angularVelocity = Stats.LinearSpeedToAngularVelocity(physicalSpeed, data.worldRadius)
		
		local dt = math.min(timeStep, elapsedTime - t)
		totalAngle = totalAngle + (angularVelocity * dt)
		t = t + timeStep
	end
	
	local angleIntoCurrentLap = totalAngle % (2 * math.pi)
	return math.clamp(angleIntoCurrentLap / (2 * math.pi), 0, 1)
end

function LapService:StartTracking(player: Player, launchWorld: string, targetWorld: string, trackData: TrackingData?)
	local folder = GetOrCreatePlayerLapsFolder()
	
	local existing = folder:FindFirstChild(tostring(player.UserId))
	if existing then
		existing:Destroy()
	end
	
	local lapValue = Instance.new("NumberValue")
	lapValue.Name = tostring(player.UserId)
	lapValue.Value = 0
	lapValue:SetAttribute("LaunchWorldName", launchWorld)
	lapValue:SetAttribute("TargetWorldName", targetWorld)
	lapValue:SetAttribute("PlayerName", player.Name)
	lapValue.Parent = folder
	
	if trackData then
		TrackedPlayers[player.UserId] = trackData
	end
end

function LapService:SetTrackingData(player: Player, trackData: TrackingData)
	TrackedPlayers[player.UserId] = trackData
end

function LapService:StopTracking(player: Player)
	TrackedPlayers[player.UserId] = nil
	
	local lapValue = GetPlayerLapValue(player)
	if lapValue then
		lapValue.Value = 0
		local currentWorld = player:GetAttribute("CurrentWorld") or "Main"
		lapValue:SetAttribute("LaunchWorldName", currentWorld)
		lapValue:SetAttribute("TargetWorldName", currentWorld)
	end
end

function LapService:CreatePlayerLapValue(player: Player)
	local folder = GetOrCreatePlayerLapsFolder()
	local existing = folder:FindFirstChild(tostring(player.UserId))
	if existing then return end
	
	local currentWorld = player:GetAttribute("CurrentWorld") or "Main"
	local lapValue = Instance.new("NumberValue")
	lapValue.Name = tostring(player.UserId)
	lapValue.Value = 0
	lapValue:SetAttribute("LaunchWorldName", currentWorld)
	lapValue:SetAttribute("TargetWorldName", currentWorld)
	lapValue:SetAttribute("PlayerName", player.Name)
	lapValue.Parent = folder
end

function LapService:RemovePlayerLapValue(player: Player)
	local lapValue = GetPlayerLapValue(player)
	if lapValue then
		lapValue:Destroy()
	end
	TrackedPlayers[player.UserId] = nil
end

function LapService:GetLapInfoForPlayer(player: Player): LapInfo?
	local lapValue = GetPlayerLapValue(player)
	if not lapValue then
		return nil
	end
	
	return {
		LaunchWorldName = lapValue:GetAttribute("LaunchWorldName") or "",
		TargetWorldName = lapValue:GetAttribute("TargetWorldName") or "",
		LapPercentage = lapValue.Value,
		Player = player,
	}
end

function LapService.Client:GetLapInfo(_player: Player, targetPlayer: Player): LapInfo?
	return LapService:GetLapInfoForPlayer(targetPlayer)
end

function LapService:KnitInit()
	GetOrCreatePlayerLapsFolder()
	
	local function SetupPlayerWorldListener(plr: Player)
		plr:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
			if not TrackedPlayers[plr.UserId] then
				local lapValue = GetPlayerLapValue(plr)
				if lapValue then
					local currentWorld = plr:GetAttribute("CurrentWorld") or "Main"
					lapValue:SetAttribute("LaunchWorldName", currentWorld)
					lapValue:SetAttribute("TargetWorldName", currentWorld)
				end
			end
		end)
	end
	
	for _, plr in ipairs(Players:GetPlayers()) do
		self:CreatePlayerLapValue(plr)
		SetupPlayerWorldListener(plr)
	end
	
	Players.PlayerAdded:Connect(function(plr)
		task.spawn(function()
			plr:GetAttributeChangedSignal("CurrentWorld"):Wait()
			LapService:CreatePlayerLapValue(plr)
			SetupPlayerWorldListener(plr)
		end)
	end)
	
	Players.PlayerRemoving:Connect(function(plr)
		LapService:RemovePlayerLapValue(plr)
	end)
end

function LapService:KnitStart()
	RunService.Heartbeat:Connect(function()
		for userId, data in pairs(TrackedPlayers) do
			local lapValue = GetPlayerLapValue(data.player)
			if lapValue then
				local percentage = CalculateLapPercentage(data)
				lapValue.Value = percentage
			end
		end
	end)
end

return LapService
