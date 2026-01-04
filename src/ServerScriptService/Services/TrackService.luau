--[[
	TrackService
	Handles track teleportation and player tracking for the racing system.
	Players request to start running on a track, get teleported to the closest gate,
	and are tracked while running.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

-- Track gate references
local TrackGates = Workspace:WaitForChild("RTT_Map_Final"):WaitForChild("Track_System"):WaitForChild("Track_Gates")

local TrackService = Knit.CreateService({
	Name = "TrackService",
	Client = {
		TrackStarted = Knit.CreateSignal(), -- Signal to notify client when track run starts
	},
})

-- Private state
local PlayersOnTrack = {} -- [Player.UserId] = { startTime, gateIndex, totalDistance }

-- Helper function for logging
local function Log(message: string)
	print(string.format("[TrackService]: %s", message))
end

-- Get all track gate positions
local function GetGatePositions(): { [string]: Vector3 }
	local gates = {}
	for i = 0, 3 do
		local gateName = "Gate_" .. i
		local gate = TrackGates:FindFirstChild(gateName)
		if gate then
			if gate:IsA("BasePart") then
				gates[gateName] = gate.Position
			elseif gate:IsA("Model") then
				local primaryPart = gate.PrimaryPart or gate:FindFirstChildWhichIsA("BasePart")
				if primaryPart then
					gates[gateName] = primaryPart.Position
				end
			end
		end
	end
	return gates
end

-- Find the closest gate to the player
local function FindClosestGate(playerPosition: Vector3): (string?, Vector3?, number?)
	local gates = GetGatePositions()
	local closestGate = nil
	local closestPosition = nil
	local closestDistance = math.huge

	for gateName, gatePosition in pairs(gates) do
		local distance = (playerPosition - gatePosition).Magnitude
		if distance < closestDistance then
			closestDistance = distance
			closestGate = gateName
			closestPosition = gatePosition
		end
	end

	return closestGate, closestPosition, closestDistance
end

-- Calculate the total distance to travel based on player's current fuel
local function CalculateTotalDistance(player: Player): number
	local DataService = Knit.GetService("DataService")
	local playerData = DataService:Get(player, "Stats")
	
	if not playerData then
		return 0
	end
	
	local fuel = playerData.Fuel or 0
	local speed = Stats.CalculateSpeedFromFuel(fuel, "Main")
	
	-- Distance is proportional to fuel consumed at calculated speed
	-- Using a base multiplier for track distance
	local distanceMultiplier = 10
	local totalDistance = fuel * distanceMultiplier
	
	return totalDistance
end

-- Check if a player is currently on the track
function TrackService:IsPlayerOnTrack(player: Player): boolean
	return PlayersOnTrack[player.UserId] ~= nil
end

-- Get track data for a player
function TrackService:GetPlayerTrackData(player: Player)
	return PlayersOnTrack[player.UserId]
end

-- Remove player from track
function TrackService:RemovePlayerFromTrack(player: Player)
	if PlayersOnTrack[player.UserId] then
		Log(string.format("Player %s removed from track", player.Name))
		PlayersOnTrack[player.UserId] = nil
	end
end

-- Client request to start running on the track
function TrackService.Client:RequestTrackStart(player: Player): (boolean, string?, number?)
	local userId = player.UserId
	
	-- Check if player is already on the track
	if PlayersOnTrack[userId] then
		return false, "Already on track", nil
	end
	
	-- Get player's character and position
	local character = player.Character
	if not character then
		return false, "No character", nil
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart", nil
	end
	
	local playerPosition = rootPart.Position
	
	-- Find the closest gate
	local closestGate, gatePosition, _ = FindClosestGate(playerPosition)
	if not closestGate or not gatePosition then
		return false, "No gates found", nil
	end
	
	-- Teleport player to the closest gate
	local teleportPosition = gatePosition + Vector3.new(0, 3, 0) -- Slightly above the gate
	rootPart.CFrame = CFrame.new(teleportPosition)
	
	-- Calculate total distance to travel
	local totalDistance = CalculateTotalDistance(player)
	
	-- Track the player as running on the track
	PlayersOnTrack[userId] = {
		startTime = tick(),
		gateIndex = tonumber(closestGate:match("%d+")),
		totalDistance = totalDistance,
	}
	
	Log(string.format("Player %s started track at %s, distance: %.2f", player.Name, closestGate, totalDistance))
	
	-- Fire signal to client that track has started
	TrackService.Client.TrackStarted:Fire(player, {
		gateName = closestGate,
		totalDistance = totalDistance,
	})
	
	return true, closestGate, totalDistance
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	PlayersOnTrack[player.UserId] = nil
	Log(string.format("Cleared track data for player %s", player.Name))
end

-- Knit lifecycle
function TrackService:KnitInit()
	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function TrackService:KnitStart()
	Log("TrackService started")
end

return TrackService
