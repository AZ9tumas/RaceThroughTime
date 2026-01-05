--[[
	TrackService
	Handles track teleportation and player tracking for the racing system.
	Players request to start running on a track, get teleported to the closest gate,
	and are tracked while running. Uses circular movement with body movers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

-- Track gate references
local TrackGates = Workspace:WaitForChild("RTT_Map_Final"):WaitForChild("Track_System"):WaitForChild("Track_Gates")
local SpawnLocation = Workspace:WaitForChild("RTT_Map_Final"):WaitForChild("SpawnLocation")

local TrackService = Knit.CreateService({
	Name = "TrackService",
	Client = {
		TrackStarted = Knit.CreateSignal(), -- Signal to notify client when track run starts
		TrackEnded = Knit.CreateSignal(), -- Signal to notify client when track run ends
	},
})

-- Private state
local PlayersOnTrack = {} -- [Player.UserId] = { player, startTime, gateIndex, totalDistance, currentAngle, speed, distanceTraveled }
local PlayerRequestDebounce = {} -- [Player.UserId] = lastRequestTime (for rate limiting)
local HeartbeatConnection = nil -- Note: Connection persists for service lifetime, no cleanup needed
local DEBOUNCE_COOLDOWN = 1 -- Minimum seconds between requests

-- Helper function for logging
local function Log(message: string)
	print(string.format("[TrackService]: %s", message))
end

-- Get the center position for circular movement (SpawnLocation position)
local function GetTrackCenter(): Vector3
	return SpawnLocation.Position
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

-- Calculate the initial angle based on player's position relative to center
local function CalculateInitialAngle(position: Vector3, center: Vector3): number
	local dx = position.X - center.X
	local dz = position.Z - center.Z
	return math.atan2(dz, dx)
end

-- Calculate the total distance to travel based on player's current fuel
local function CalculateTotalDistance(player: Player, speed: number): number
	local DataService = Knit.GetService("DataService")
	local playerData = DataService:Get(player, "Stats")
	
	if not playerData then
		return 0
	end
	
	local fuel = playerData.Fuel or 0
	
	-- Total distance is based on fuel - more fuel = more distance on the track
	local timeLeft = fuel / Stats.FuelConsumptionRate.Main
	local totalDistance = speed * timeLeft
	
	return totalDistance
end

-- Calculate the player's speed based on their fuel
local function CalculatePlayerSpeed(player: Player): number
	local DataService = Knit.GetService("DataService")
	local playerData = DataService:Get(player, "Stats")
	
	if not playerData then
		return Stats.BaseSpeed
	end
	
	local fuel = playerData.Fuel or 0
	return Stats.CalculateSpeedFromFuel(fuel, "Main")
end

-- Update circular position using polar to cartesian conversion
local function UpdateCircularPosition(center: Vector3, radius: number, angle: number, y: number): (CFrame, Vector3)
	-- Polar to Cartesian conversion
	local x = center.X + radius * math.cos(angle)
	local z = center.Z + radius * math.sin(angle)
	
	local targetPosition = Vector3.new(x, y, z)
	
	-- Calculate orientation (tangential direction - looking forward along the path)
	local lookAtPos = targetPosition + Vector3.new(
		-math.sin(angle), -- Derivative of cos
		0,
		math.cos(angle)   -- Derivative of sin
	)
	
	local finalCFrame = CFrame.lookAt(targetPosition, lookAtPos)
	
	return finalCFrame, targetPosition
end

-- Setup body movers for smooth movement
local function SetupBodyMovers(character: Model): (AlignPosition?, AlignOrientation?)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil, nil end
	
	-- Create or get attachment for body movers
	local attachment = rootPart:FindFirstChild("TrackAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "TrackAttachment"
		attachment.Parent = rootPart
	end
	
	-- Create AlignPosition for smooth position movement
	local alignPosition = rootPart:FindFirstChild("TrackAlignPosition")
	if not alignPosition then
		alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "TrackAlignPosition"
		alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPosition.Attachment0 = attachment
		alignPosition.MaxForce = 100000
		alignPosition.MaxVelocity = 500
		alignPosition.Responsiveness = 50
		alignPosition.Parent = rootPart
	end
	
	-- Create AlignOrientation for smooth rotation
	local alignOrientation = rootPart:FindFirstChild("TrackAlignOrientation")
	if not alignOrientation then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "TrackAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Attachment0 = attachment
		alignOrientation.MaxTorque = 100000
		alignOrientation.MaxAngularVelocity = 50
		alignOrientation.Responsiveness = 50
		alignOrientation.Parent = rootPart
	end
	
	-- Create NumberValue for distance tracking (client reads this for visual feedback)
	local distanceValue = rootPart:FindFirstChild("TrackDistanceTraveled")
	if not distanceValue then
		distanceValue = Instance.new("NumberValue")
		distanceValue.Name = "TrackDistanceTraveled"
		distanceValue.Value = 0
		distanceValue.Parent = rootPart
	end
	
	return alignPosition, alignOrientation
end

-- Clean up body movers when track ends
local function CleanupBodyMovers(character: Model)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local alignPosition = rootPart:FindFirstChild("TrackAlignPosition")
	if alignPosition then alignPosition:Destroy() end
	
	local alignOrientation = rootPart:FindFirstChild("TrackAlignOrientation")
	if alignOrientation then alignOrientation:Destroy() end
	
	local attachment = rootPart:FindFirstChild("TrackAttachment")
	if attachment then attachment:Destroy() end
	
	local distanceValue = rootPart:FindFirstChild("TrackDistanceTraveled")
	if distanceValue then distanceValue:Destroy() end
end

-- Check if a player is currently on the track
function TrackService:IsPlayerOnTrack(player: Player): boolean
	return PlayersOnTrack[player.UserId] ~= nil
end

-- Get track data for a player
function TrackService:GetPlayerTrackData(player: Player)
	return PlayersOnTrack[player.UserId]
end

-- End track run for a player
function TrackService:EndTrackRun(player: Player)
	local userId = player.UserId
	local trackData = PlayersOnTrack[userId]
	
	if not trackData then return end
	
	-- Clean up body movers
	local character = player.Character
	if character then
		CleanupBodyMovers(character)
	end
	
	-- Calculate rewards based on distance traveled
	local distanceTraveled = trackData.distanceTraveled or 0
	
	-- Calculate cash earned based on WorldCashRate (per 1000 distance)
	local cashRate = Stats.WorldCashRates.Main
	local cashEarned = math.floor((distanceTraveled / 1000) * cashRate)
	
	Log(string.format("Player %s ended track run, distance traveled: %.2f, cash earned: %d", player.Name, distanceTraveled, cashEarned))
	
	-- Update player data: set fuel to 0 and add cash
	local DataService = Knit.GetService("DataService")
	
	-- Set fuel to 0
	DataService:Update(player, "Stats", function(stats)
		stats.Fuel = 0
		return stats
	end)
	
	-- Add cash earned
	if cashEarned > 0 then
		DataService:Update(player, "Currencies", function(currencies)
			currencies.Cash = (currencies.Cash or 0) + cashEarned
			return currencies
		end)
	end
	
	-- Clear player from track
	PlayersOnTrack[userId] = nil
	
	-- Fire signal to client that track has ended
	TrackService.Client.TrackEnded:Fire(player, {
		distanceTraveled = distanceTraveled,
		cashEarned = cashEarned,
	})
end

-- Remove player from track (alias for EndTrackRun)
function TrackService:RemovePlayerFromTrack(player: Player)
	self:EndTrackRun(player)
end

-- Main heartbeat update for all players on track
local function OnHeartbeat(dt: number)
	local center = GetTrackCenter()
	local radius = Stats.WorldRadius.Main
	
	for userId, trackData in pairs(PlayersOnTrack) do
		local player = trackData.player
		if not player or not player:IsDescendantOf(Players) then
			PlayersOnTrack[userId] = nil
			continue
		end
		
		local character = player.Character
		if not character then continue end
		
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end
		
		-- Get body movers
		local alignPosition = rootPart:FindFirstChild("TrackAlignPosition")
		local alignOrientation = rootPart:FindFirstChild("TrackAlignOrientation")
		
		if not alignPosition or not alignOrientation then continue end
		
		-- Calculate angular velocity (w = v / r)
		local speed = trackData.speed
		local angularVelocity = speed / radius
		
		-- Update angle based on time delta
		trackData.currentAngle = trackData.currentAngle + (angularVelocity * dt)
		
		-- Calculate distance traveled this frame
		local distanceThisFrame = speed * dt
		trackData.distanceTraveled = trackData.distanceTraveled + distanceThisFrame
		
		-- Update distance NumberValue for client feedback
		local distanceValue = rootPart:FindFirstChild("TrackDistanceTraveled")
		if distanceValue then
			distanceValue.Value = trackData.distanceTraveled
		end
		
		-- Check if player has completed their run
		if trackData.distanceTraveled >= trackData.totalDistance then
			TrackService:EndTrackRun(player)
			continue
		end
		
		-- Calculate new position and orientation
		local targetCFrame, targetPosition = UpdateCircularPosition(center, radius, trackData.currentAngle, center.Y + 5)
		
		-- Update body mover targets
		alignPosition.Position = targetPosition
		alignOrientation.CFrame = targetCFrame
	end
end

-- Client request to start running on the track
function TrackService.Client:RequestTrackStart(player: Player): (boolean, string?, number?)
	local userId = player.UserId
	local currentTime = tick()
	
	-- Check rate limiting debounce
	local lastRequestTime = PlayerRequestDebounce[userId]
	if lastRequestTime and (currentTime - lastRequestTime) < DEBOUNCE_COOLDOWN then
		local remainingTime = DEBOUNCE_COOLDOWN - (currentTime - lastRequestTime)
		return false, string.format("Request too fast, wait %.1f seconds", remainingTime), nil
	end
	
	-- Update last request time
	PlayerRequestDebounce[userId] = currentTime
	
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
	
	-- Get track center and radius
	local center = GetTrackCenter()
	local radius = Stats.WorldRadius.Main
	
	-- Calculate initial angle based on gate position
	local initialAngle = CalculateInitialAngle(gatePosition, center)
	
	-- Teleport player to the gate position on the track
	local teleportCFrame, _ = UpdateCircularPosition(center, radius, initialAngle, center.Y + 5)
	rootPart.CFrame = teleportCFrame
	
	-- Setup body movers for smooth movement
	local alignPosition, alignOrientation = SetupBodyMovers(character)
	if not alignPosition or not alignOrientation then
		return false, "Failed to setup body movers", nil
	end
	
	-- Calculate speed and total distance
	local speed = CalculatePlayerSpeed(player)
	local totalDistance = CalculateTotalDistance(player, speed)
	
	-- Track the player as running on the track (store player reference for efficient heartbeat loop)
	PlayersOnTrack[userId] = {
		player = player,
		startTime = tick(),
		gateIndex = tonumber(closestGate:match("%d+")),
		totalDistance = totalDistance,
		currentAngle = initialAngle,
		speed = speed,
		distanceTraveled = 0,
	}
	
	Log(string.format("Player %s started track at %s, speed: %.2f, distance: %.2f", player.Name, closestGate, speed, totalDistance))
	
	-- Fire signal to client that track has started
	TrackService.Client.TrackStarted:Fire(player, {
		gateName = closestGate,
		totalDistance = totalDistance,
		speed = speed,
	})
	
	return true, closestGate, totalDistance
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	local character = player.Character
	if character then
		CleanupBodyMovers(character)
	end
	PlayersOnTrack[player.UserId] = nil
	PlayerRequestDebounce[player.UserId] = nil
	Log(string.format("Cleared track data for player %s", player.Name))
end

-- Knit lifecycle
function TrackService:KnitInit()
	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function TrackService:KnitStart()
	-- Start the heartbeat loop for circular movement
	HeartbeatConnection = RunService.Heartbeat:Connect(OnHeartbeat)
	Log("TrackService started")
end

return TrackService
