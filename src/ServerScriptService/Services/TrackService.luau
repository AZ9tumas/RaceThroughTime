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

local TrackService = Knit.CreateService({
	Name = "TrackService",
	Client = {
		TrackStarted = Knit.CreateSignal(), -- Signal to notify client when track run starts
		TrackEnded = Knit.CreateSignal(), -- Signal to notify client when track run ends
		LapCompleted = Knit.CreateSignal(), -- Signal to notify client when a lap is completed
	},
})

-- Private state
local PlayersOnTrack = {} -- [Player.UserId] = { player, worldName, startTime, gateIndex, totalDistance, currentAngle, speed, distanceTraveled, startAngle, lapCount }
local PlayerRequestDebounce = {} -- [Player.UserId] = lastRequestTime (for rate limiting)
local HeartbeatConnection = nil -- Note: Connection persists for service lifetime, no cleanup needed
local DEBOUNCE_COOLDOWN = 1 -- Minimum seconds between requests
local TrackOriginalProperties = {} -- [worldName] = { Material, Transparency, ... } - Store original track properties
local TrackFireEffects = {} -- [worldName] = { Fire, Smoke } - Store fire/smoke effects per world

-- Helper function for logging
local function Log(message: string)
	print(string.format("[TrackService]: %s", message))
end

-- Get the world folder for a player's current world
local function GetWorldFolder(worldName: string): Folder?
	-- World folders are named directly in workspace (e.g., "Main", "StoneAge")
	local worldFolder = Workspace:FindFirstChild(worldName)
	if worldFolder then
		return worldFolder
	end
	
	-- Fallback to Main world if the specified world is not found
	return Workspace:FindFirstChild("Main")
end

-- Get SpawnLocation from the player's current world
local function GetSpawnLocationForWorld(worldName: string): SpawnLocation?
	local worldFolder = GetWorldFolder(worldName)
	if worldFolder then
		return worldFolder:FindFirstChild("SpawnLocation")
	end
	return nil
end

-- Get TrackGates from the player's current world
local function GetTrackGatesForWorld(worldName: string): Folder?
	local worldFolder = GetWorldFolder(worldName)
	if worldFolder then
		local trackSystem = worldFolder:FindFirstChild("Track_System")
		if trackSystem then
			return trackSystem:FindFirstChild("Track_Gates")
		end
	end
	return nil
end

-- Get VisualTrack from the player's current world
local function GetVisualTrackForWorld(worldName: string): BasePart?
	local worldFolder = GetWorldFolder(worldName)
	if worldFolder then
		local trackSystem = worldFolder:FindFirstChild("Track_System")
		if trackSystem then
			return trackSystem:FindFirstChild("Visual_Track")
		end
	end
	return nil
end

-- Apply neon effect to track when player starts running
local function ApplyNeonEffectToTrack(worldName: string)
	local visualTrack = GetVisualTrackForWorld(worldName)
	if not visualTrack then return end
	
	-- Store original properties if not already stored
	if not TrackOriginalProperties[worldName] then
		TrackOriginalProperties[worldName] = {
			Material = visualTrack.Material,
			Transparency = visualTrack.Transparency,
		}
	end
	
	-- Apply neon effect
	visualTrack.Material = Enum.Material.Neon
	visualTrack.Transparency = 0
	
	-- Add PointLight for glow effect if it doesn't exist
	local pointLight = visualTrack:FindFirstChild("TrackGlow")
	if not pointLight then
		pointLight = Instance.new("PointLight")
		pointLight.Name = "TrackGlow"
		pointLight.Color = visualTrack.Color
		pointLight.Brightness = 2
		pointLight.Range = 30
		pointLight.Parent = visualTrack
	end
	pointLight.Enabled = true
	
	Log(string.format("Applied neon effect to track in world %s", worldName))
end

-- Remove neon effect from track when player stops running
local function RemoveNeonEffectFromTrack(worldName: string)
	local visualTrack = GetVisualTrackForWorld(worldName)
	if not visualTrack then return end
	
	-- Restore original properties
	local originalProps = TrackOriginalProperties[worldName]
	if originalProps then
		visualTrack.Material = originalProps.Material
		visualTrack.Transparency = originalProps.Transparency
	end
	
	-- Disable PointLight
	local pointLight = visualTrack:FindFirstChild("TrackGlow")
	if pointLight then
		pointLight.Enabled = false
	end
	
	Log(string.format("Removed neon effect from track in world %s", worldName))
end

-- Apply or update fire and smoke effects on track based on progress percentage
-- progressPercent: 0.0 to 1.0+ representing progress toward world unlock
local function UpdateFireEffectOnTrack(worldName: string, progressPercent: number)
	local visualTrack = GetVisualTrackForWorld(worldName)
	if not visualTrack then return end
	
	-- Fire only activates at 50% or above progress
	if progressPercent < 0.5 then
		-- Remove fire if exists and progress dropped below 50%
		local effects = TrackFireEffects[worldName]
		if effects then
			if effects.Fire then effects.Fire:Destroy() end
			if effects.Smoke then effects.Smoke:Destroy() end
			TrackFireEffects[worldName] = nil
		end
		return
	end
	
	-- Calculate intensity based on progress (50% to 100% maps to 0 to 1)
	local intensityFactor = math.clamp((progressPercent - 0.5) / 0.5, 0, 1)
	
	-- Check if fire already exists
	local effects = TrackFireEffects[worldName]
	if not effects then
		-- Create Fire effect
		local fire = Instance.new("Fire")
		fire.Name = "TrackFire"
		fire.Heat = 5 + (intensityFactor * 10) -- 5 to 15
		fire.Size = 5 + (intensityFactor * 10) -- 5 to 15
		fire.Parent = visualTrack
		
		-- Create Smoke effect
		local smoke = Instance.new("Smoke")
		smoke.Name = "TrackSmoke"
		smoke.Size = 2 + (intensityFactor * 5) -- 2 to 7
		smoke.Opacity = 0.3 + (intensityFactor * 0.4) -- 0.3 to 0.7
		smoke.RiseVelocity = 5 + (intensityFactor * 10) -- 5 to 15
		smoke.Parent = visualTrack
		
		TrackFireEffects[worldName] = {
			Fire = fire,
			Smoke = smoke,
		}
		effects = TrackFireEffects[worldName]
		
		Log(string.format("Created fire effect on track in world %s at %.0f%% progress", worldName, progressPercent * 100))
	end
	
	-- Update fire properties based on progress
	if effects.Fire then
		effects.Fire.Heat = 5 + (intensityFactor * 10)
		effects.Fire.Size = 5 + (intensityFactor * 10)
		
		-- Color changes to purple at >90% progress
		if progressPercent >= 0.9 then
			effects.Fire.Color = Color3.fromRGB(128, 0, 255) -- Purple
			effects.Fire.SecondaryColor = Color3.fromRGB(75, 0, 130) -- Indigo
		else
			effects.Fire.Color = Color3.fromRGB(255, 165, 0) -- Orange
			effects.Fire.SecondaryColor = Color3.fromRGB(255, 69, 0) -- Orange-Red
		end
	end
	
	-- Update smoke properties
	if effects.Smoke then
		effects.Smoke.Size = 2 + (intensityFactor * 5)
		effects.Smoke.Opacity = 0.3 + (intensityFactor * 0.4)
		effects.Smoke.RiseVelocity = 5 + (intensityFactor * 10)
		
		-- Smoke color matches fire
		if progressPercent >= 0.9 then
			effects.Smoke.Color = Color3.fromRGB(75, 0, 130) -- Dark purple
		else
			effects.Smoke.Color = Color3.fromRGB(50, 50, 50) -- Dark gray
		end
	end
end

-- Remove fire and smoke effects from track
local function RemoveFireEffectFromTrack(worldName: string)
	local effects = TrackFireEffects[worldName]
	if effects then
		if effects.Fire then effects.Fire:Destroy() end
		if effects.Smoke then effects.Smoke:Destroy() end
		TrackFireEffects[worldName] = nil
		Log(string.format("Removed fire effect from track in world %s", worldName))
	end
end

-- Check if any player is on track in a specific world
local function IsAnyPlayerOnTrackInWorld(worldName: string): boolean
	for _, trackData in pairs(PlayersOnTrack) do
		if trackData.worldName == worldName then
			return true
		end
	end
	return false
end

-- Get the center position for circular movement (SpawnLocation position)
local function GetTrackCenterForWorld(worldName: string): Vector3?
	local spawnLocation = GetSpawnLocationForWorld(worldName)
	if spawnLocation then
		return spawnLocation.Position
	end
	return nil
end

-- Get all track gate positions for a specific world
local function GetGatePositionsForWorld(worldName: string): { [string]: Vector3 }
	local gates = {}
	local trackGates = GetTrackGatesForWorld(worldName)
	if not trackGates then
		return gates
	end
	
	for i = 0, 3 do
		local gateName = "Gate_" .. i
		local gate = trackGates:FindFirstChild(gateName)
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

-- Find the closest gate to the player in a specific world
local function FindClosestGate(playerPosition: Vector3, worldName: string): (string?, Vector3?, number?)
	local gates = GetGatePositionsForWorld(worldName)
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
local function CalculateTotalDistance(player: Player, speed: number, worldName: string): number
	local DataService = Knit.GetService("DataService")
	local playerData = DataService:Get(player, "Stats")
	
	if not playerData then
		return 0
	end
	
	local fuel = playerData.Fuel or 0
	
	-- Total distance is based on fuel - more fuel = more distance on the track
	local fuelConsumptionRate = Stats.FuelConsumptionRate[worldName] or Stats.FuelConsumptionRate.Main
	local timeLeft = fuel / fuelConsumptionRate
	local totalDistance = speed * timeLeft
	
	return math.floor(totalDistance)
end

-- Calculate the player's speed based on their fuel
local function CalculatePlayerSpeed(player: Player, worldName: string): number
	local DataService = Knit.GetService("DataService")
	local playerData = DataService:Get(player, "Stats")
	
	if not playerData then
		return Stats.BaseSpeed
	end
	
	local fuel = playerData.Fuel or 0
	return Stats.CalculateSpeedFromFuel(fuel, worldName)
end

-- Raycast parameters for ground detection
local RAYCAST_HEIGHT_OFFSET = 50 -- Start raycast from this height above the fallback Y
local RAYCAST_DISTANCE = 100 -- Maximum raycast distance downward
local GROUND_OFFSET = 3 -- Height offset above ground for player placement (approximate hip height)

-- Create raycast params for a specific world's visual track
local function CreateRaycastParamsForWorld(worldName: string): RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	
	local visualTrack = GetVisualTrackForWorld(worldName)
	if visualTrack then
		raycastParams.FilterDescendantsInstances = { visualTrack }
	else
		raycastParams.FilterDescendantsInstances = {}
	end
	
	return raycastParams
end

-- Update circular position using polar to cartesian conversion with ground detection
local function UpdateCircularPosition(center: Vector3, radius: number, angle: number, fallbackY: number, worldName: string): (CFrame, Vector3)
	-- Polar to Cartesian conversion
	local x = center.X + radius * math.cos(angle)
	local z = center.Z + radius * math.sin(angle)
	
	-- Raycast only hits Visual_Track part (excludes characters and other objects)
	local rayOrigin = Vector3.new(x, fallbackY + RAYCAST_HEIGHT_OFFSET, z)
	local rayDirection = Vector3.new(0, -RAYCAST_DISTANCE, 0)
	
	-- Create world-specific raycast params
	local raycastParams = CreateRaycastParamsForWorld(worldName)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	local groundY = fallbackY -- Default to fallback if raycast fails
	if raycastResult then
		-- Place player at ground position plus offset for character height
		groundY = raycastResult.Position.Y-- + GROUND_OFFSET
	end
	
	local targetPosition = Vector3.new(x, groundY, z)
	
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
	local worldName = trackData.worldName or "Main"
	
	-- Calculate cash earned based on WorldCashRate (per 1000 distance)
	local cashRate = Stats.WorldCashRates[worldName] or Stats.WorldCashRates.Main
	local cashEarned = math.floor((distanceTraveled / 1000) * cashRate)
	
	Log(string.format("Player %s ended track run in %s, distance traveled: %.2f, cash earned: %d", player.Name, worldName, distanceTraveled, cashEarned))
	
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
	
	-- Remove neon effect and fire effect from track if no other players are on track in this world
	if not IsAnyPlayerOnTrackInWorld(worldName) then
		RemoveNeonEffectFromTrack(worldName)
		RemoveFireEffectFromTrack(worldName)
	end
	
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
		
		-- Get world-specific values
		local worldName = trackData.worldName or "Main"
		local radius = Stats.WorldRadius[worldName] or Stats.WorldRadius.Main
		local center = GetTrackCenterForWorld(worldName)
		
		if not center then continue end
		
		-- Calculate angular velocity (w = v / r)
		local speed = trackData.speed
		local angularVelocity = speed / radius
		
		-- Store previous angle for lap detection
		local previousAngle = trackData.currentAngle
		
		-- Update angle based on time delta
		trackData.currentAngle = trackData.currentAngle + (angularVelocity * dt)
		
		-- Calculate distance traveled this frame
		local distanceThisFrame = speed * dt
		trackData.distanceTraveled = trackData.distanceTraveled + distanceThisFrame
		
		-- Check for lap completion (crossed the starting angle after completing a full circle)
		-- A lap is complete when the angle has increased by 2*PI from the start
		local startAngle = trackData.startAngle
		local lapThreshold = startAngle + (2 * math.pi * (trackData.lapCount + 1))
		if trackData.currentAngle >= lapThreshold then
			trackData.lapCount = trackData.lapCount + 1
			TrackService.Client.LapCompleted:Fire(player, {
				lapNumber = trackData.lapCount,
			})
			Log(string.format("Player %s completed lap %d", player.Name, trackData.lapCount))
		end
		
		-- Update distance NumberValue for client feedback
		local distanceValue = rootPart:FindFirstChild("TrackDistanceTraveled")
		if distanceValue then
			distanceValue.Value = trackData.distanceTraveled
		end
		
		-- Get next world and unlock requirement for fire effects and auto-unlock
		local WorldService = Knit.GetService("WorldService")
		local nextWorld = WorldService:GetNextWorld(worldName)
		local unlockRequirement = nextWorld and Stats.WorldUnlockRequirements[nextWorld] or nil
		
		-- Calculate progress toward world unlock and update fire effects
		if unlockRequirement then
			local progressPercent = trackData.distanceTraveled / unlockRequirement
			
			-- Update fire effects based on progress (activates at 50%+)
			UpdateFireEffectOnTrack(worldName, progressPercent)
			
			-- Check if player has reached world unlock threshold
			if trackData.distanceTraveled >= unlockRequirement then
				Log(string.format("Player %s unlocked world %s with distance %.2f", player.Name, nextWorld, trackData.distanceTraveled))
				
				-- End the track run first (this cleans up body movers, effects, etc.)
				TrackService:EndTrackRun(player)
				
				-- Unlock the new world for the player
				WorldService:GiveWorldToPlayer(player, nextWorld)
				
				-- Teleport player to the new world
				task.spawn(function()
					local success, err = WorldService:TeleportPlayerToWorld(player, nextWorld)
					if success then
						-- Send notification about world unlock
						local NotificationService = Knit.GetService("NotificationService")
						NotificationService:SendNotification(
							player,
							string.format("🌟 Congratulations! You unlocked %s! 🌟", nextWorld),
							NotificationService.Category.Success,
							5
						)
					else
						warn(string.format("[TrackService]: Failed to teleport player %s to %s: %s", player.Name, nextWorld, err or "unknown error"))
					end
				end)
				
				continue
			end
		end
		
		-- Check if player has completed their run (fuel ran out)
		if trackData.distanceTraveled >= trackData.totalDistance then
			TrackService:EndTrackRun(player)
			continue
		end
		
		-- Calculate new position and orientation
		local targetCFrame, targetPosition = UpdateCircularPosition(center, radius, trackData.currentAngle, center.Y + 5, worldName)
		
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
		return false, string.format("Request too fast, wait %.1f seconds", remainingTime)
	end
	
	-- Update last request time
	PlayerRequestDebounce[userId] = currentTime
	
	-- Check if player is already on the track
	if PlayersOnTrack[userId] then
		return false, "Already on track"
	end
	
	-- Get player's character and position
	local character = player.Character
	if not character then
		return false, "No character"
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart"
	end

	-- Get player's current world and data
	local DataService = Knit.GetService("DataService")
	local worldName = DataService:GetPlayerWorld(player)
	
	-- Get world-specific stats
	local fuelConsumptionRate = Stats.FuelConsumptionRate[worldName] or Stats.FuelConsumptionRate.Main
	local radius = Stats.WorldRadius[worldName] or Stats.WorldRadius.Main

	local fuel = DataService:Get(player, "Stats").Fuel
	if fuel <= fuelConsumptionRate then 
		return false, string.format("Not enough fuel, need at least %d fuel/sec", fuelConsumptionRate) 
	end
	
	local playerPosition = rootPart.Position
	
	-- Find the closest gate and check proximity
	local closestGate, gatePosition, gateDistance = FindClosestGate(playerPosition, worldName)
	if not closestGate or not gatePosition then
		return false, "No gates found"
	end
	
	-- Verify player is near the gate (no teleporting)
	local gateProximityDistance = Stats.GateProximityDistance
	if gateDistance > gateProximityDistance then
		return false, string.format("Must be within %d studs of a gate (currently %.1f studs away)", gateProximityDistance, gateDistance)
	end
	
	-- Get track center for player's world
	local center = GetTrackCenterForWorld(worldName)
	if not center then
		return false, "No track center found for world"
	end
	
	-- Calculate initial angle based on player's actual position (not gate position)
	local initialAngle = CalculateInitialAngle(playerPosition, center)
	
	-- Position player on the track at their current angle (no teleporting, just align to track)
	local teleportCFrame, _ = UpdateCircularPosition(center, radius, initialAngle, center.Y + 5, worldName)
	rootPart.CFrame = teleportCFrame
	
	-- Setup body movers for smooth movement
	local alignPosition, alignOrientation = SetupBodyMovers(character)
	if not alignPosition or not alignOrientation then
		return false, "Failed to setup body movers"
	end
	
	-- Calculate speed and total distance using player's world
	local speed = CalculatePlayerSpeed(player, worldName)
	local totalDistance = CalculateTotalDistance(player, speed, worldName)
	
	-- Track the player as running on the track (store player reference and world for efficient heartbeat loop)
	PlayersOnTrack[userId] = {
		player = player,
		worldName = worldName,
		startTime = tick(),
		gateIndex = tonumber(closestGate:match("%d+")),
		totalDistance = totalDistance,
		currentAngle = initialAngle,
		startAngle = initialAngle, -- Store starting angle for lap detection
		speed = speed,
		distanceTraveled = 0,
		lapCount = 0, -- Track number of completed laps
	}
	
	Log(string.format("Player %s started track at %s in world %s, speed: %.2f, distance: %.2f", player.Name, closestGate, worldName, speed, totalDistance))
	
	-- Apply neon effect to track
	ApplyNeonEffectToTrack(worldName)
	
	-- Fire signal to client that track has started
	TrackService.Client.TrackStarted:Fire(player, {
		gateName = closestGate,
		totalDistance = totalDistance,
		speed = speed,
		startAngle = initialAngle,
	})
	
	return true, nil
end

-- Client request to cancel current track run (no rewards on cancellation)
function TrackService.Client:CancelTrackRun(player: Player): (boolean, string?, { distanceTraveled: number? }?)
	local userId = player.UserId
	local trackData = PlayersOnTrack[userId]
	
	-- Check if player is on the track
	if not trackData then
		return false, "Not currently on track", nil
	end
	
	local distanceTraveled = trackData.distanceTraveled or 0
	local worldName = trackData.worldName or "Main"
	
	Log(string.format("Player %s cancelled track run in %s, distance traveled: %.2f (no rewards)", player.Name, worldName, distanceTraveled))
	
	-- Clean up body movers
	local character = player.Character
	if character then
		CleanupBodyMovers(character)
	end
	
	-- Update player data: set fuel to 0 (no cash reward on cancellation)
	local DataService = Knit.GetService("DataService")
	
	-- Set fuel to 0
	DataService:Update(player, "Stats", function(stats)
		stats.Fuel = 0
		return stats
	end)
	
	-- Clear player from track
	PlayersOnTrack[userId] = nil
	
	-- Remove neon effect and fire effect from track if no other players are on track in this world
	if not IsAnyPlayerOnTrackInWorld(worldName) then
		RemoveNeonEffectFromTrack(worldName)
		RemoveFireEffectFromTrack(worldName)
	end
	
	-- Fire signal to client that track has ended (cancelled, no rewards)
	TrackService.Client.TrackEnded:Fire(player, {
		distanceTraveled = distanceTraveled,
		cashEarned = 0,
		cancelled = true,
	})
	
	return true, nil, {
		distanceTraveled = distanceTraveled,
	}
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
