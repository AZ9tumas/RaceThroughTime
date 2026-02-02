--[[
	TrackService
	Handles track validation and reward processing for the racing system.
	Players request to start running on a track, get teleported to the closest gate,
	and movement is handled client-side using BindToRenderStep. Server validates
	and processes rewards when client requests to end track run.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local RebirthStats = require(ReplicatedStorage.Modules.RebirthStats)

local TrackService = Knit.CreateService({
	Name = "TrackService",
	Client = {
		TrackStarted = Knit.CreateSignal(), -- Signal to notify client when track run starts
		TrackEnded = Knit.CreateSignal(), -- Signal to notify client when track run ends
	},
})

-- Private state
local PlayersOnTrack = {} -- [Player.UserId] = { player, worldName, startTime, totalDistance, initialSpeed, acceleration, maxSpeed, totalTime, startAngle, worldRadius, trackCenter }
local PlayerRequestDebounce = {} -- [Player.UserId] = lastRequestTime (for rate limiting)
local DEBOUNCE_COOLDOWN = 1 -- Minimum seconds between requests

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[TrackService]: %s", message))
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

-- Calculate track parameters (initial speed, acceleration, max speed) based on fuel
local function CalculateTrackParameters(player: Player, worldName: string):
	{ initialSpeed: number, acceleration: number, maxSpeed: number, totalTime: number, totalDistance: number }
	local DataService = Knit.GetService("DataService")
	local playerData = DataService:Get(player, "Stats")
	
	if not playerData then
		return {
			initialSpeed = Stats.BaseSpeed,
			acceleration = Stats.BaseAcceleration,
			maxSpeed = Stats.BaseSpeed * 2,
			totalTime = 1,
			totalDistance = Stats.BaseSpeed,
		}
	end
	
	local fuel = playerData.Fuel or 0
	local trackParams = Stats.CalculateTrackParameters(fuel, worldName)
	
	-- Apply rebirth speed multiplier
	local rebirthLevel = playerData.Rebirths or 0
	local rebirthSpeedMultiplier = RebirthStats.CalculateTotalSpeedMultiplier(rebirthLevel)
	
	-- Scale speed values by rebirth multiplier
	trackParams.initialSpeed = trackParams.initialSpeed * rebirthSpeedMultiplier
	trackParams.maxSpeed = trackParams.maxSpeed * rebirthSpeedMultiplier
	
	return trackParams
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

-- Pet weld constants (same as PetController's PET_FOLLOW_DISTANCE)
local PET_FOLLOW_DISTANCE = 8
local PET_FOLLOW_HEIGHT = 2

-- Setup weld constraints to attach pets to the player during track run
-- This ensures pets stay alongside the player without using body movers
local function SetupPetWeldsForTrack(player: Player)
	local character = player.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	-- Get PetService and spawned pets
	local PetService = Knit.GetService("PetService")
	local spawnedPets = PetService:GetSpawnedPets(player)
	
	-- Counter for positioning pets in formation
	local petCounter = 0
	
	for petIndex, petModel in pairs(spawnedPets) do
		if petModel and petModel.PrimaryPart then
			local primaryPart = petModel.PrimaryPart
			petCounter = petCounter + 1
			
			-- Calculate the offset for this pet (same formula as PetController)
			-- Use petIndex for the angle calculation to match client-side behavior
			local offset = Vector3.new(
				math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
				PET_FOLLOW_HEIGHT,
				math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
			)
			
			-- Disable the pet's body movers during track run
			local alignPos = primaryPart:FindFirstChild("PetAlignPosition")
			local alignOri = primaryPart:FindFirstChild("PetAlignOrientation")
			
			if alignPos then
				alignPos.Enabled = false
			end
			if alignOri then
				alignOri.Enabled = false
			end
			
			-- Position the pet at the correct offset from the player
			local targetCFrame = rootPart.CFrame * CFrame.new(offset)
			petModel:PivotTo(targetCFrame)
			
			-- Create a weld constraint to attach the pet to the player
			local weld = Instance.new("WeldConstraint")
			weld.Name = "TrackPetWeld"
			weld.Part0 = rootPart
			weld.Part1 = primaryPart
			weld.Parent = primaryPart
			
			Log(string.format("Welded pet %d to player %s for track run", petIndex, player.Name))
		end
	end
end

-- Cleanup pet weld constraints when track run ends
local function CleanupPetWeldsForTrack(player: Player)
	-- Get PetService and spawned pets
	local PetService = Knit.GetService("PetService")
	local spawnedPets = PetService:GetSpawnedPets(player)
	
	for petIndex, petModel in pairs(spawnedPets) do
		if petModel and petModel.PrimaryPart then
			local primaryPart = petModel.PrimaryPart
			
			-- Remove the weld constraint
			local weld = primaryPart:FindFirstChild("TrackPetWeld")
			if weld then
				weld:Destroy()
			end
			
			-- Re-enable the pet's body movers
			local alignPos = primaryPart:FindFirstChild("PetAlignPosition")
			local alignOri = primaryPart:FindFirstChild("PetAlignOrientation")
			
			if alignPos then
				alignPos.Enabled = true
			end
			if alignOri then
				alignOri.Enabled = true
			end
			
			Log(string.format("Unwelded pet %d from player %s after track run", petIndex, player.Name))
		end
	end
end

-- Check if a player is currently on the track
function TrackService:IsPlayerOnTrack(player: Player): boolean
	return PlayersOnTrack[player.UserId] ~= nil
end

-- Get track data for a player
function TrackService:GetPlayerTrackData(player: Player)
	return PlayersOnTrack[player.UserId]
end

-- End track run for a player (called by server or via RequestTrackEnd from client)
-- distanceTraveled is provided by the client but validated against server-side parameters
function TrackService:EndTrackRun(player: Player, clientDistanceTraveled: number?, worldUnlocked: boolean?)
	local userId = player.UserId
	local trackData = PlayersOnTrack[userId]
	
	if not trackData then return end
	
	-- Clean up body movers
	local character = player.Character
	if character then
		CleanupBodyMovers(character)
	end
	
	-- Cleanup pet weld constraints
	CleanupPetWeldsForTrack(player)
	
	-- Validate client-provided distance against server-side maximum
	-- The client cannot claim more distance than what's possible given the track parameters
	local maxPossibleDistance = trackData.totalDistance
	local distanceTraveled = clientDistanceTraveled or 0
	
	-- Clamp distance to the maximum possible (prevents cheating)
	distanceTraveled = math.clamp(distanceTraveled, 0, maxPossibleDistance)
	
	local worldName = trackData.worldName
	
	-- Get rebirth cash multiplier
	local DataService = Knit.GetService("DataService")
	local playerStats = DataService:Get(player, "Stats")
	local rebirthLevel = (playerStats and playerStats.Rebirths) or 0
	local rebirthCashMultiplier = RebirthStats.CalculateTotalCashMultiplier(rebirthLevel)
	
	-- Calculate cash earned based on WorldCashRate (per 1000 distance) with rebirth multiplier
	local cashRate = Stats.WorldCashRates[worldName] or Stats.WorldCashRates.Main
	local baseCashEarned = (distanceTraveled / 1000) * cashRate
	local cashEarned = math.floor(baseCashEarned * rebirthCashMultiplier)
	
	Log(string.format("Player %s ended track run in %s, distance traveled: %.2f, cash earned: %d (rebirth multiplier: %.2fx)", player.Name, worldName, distanceTraveled, cashEarned, rebirthCashMultiplier))
	
	-- Update player data: add cash
	if cashEarned > 0 then
		DataService:Update(player, "Currencies", function(currencies)
			currencies.Cash = (currencies.Cash or 0) + cashEarned
			return currencies
		end)
	end
	
	-- Calculate percentage to next world
	local WorldService = Knit.GetService("WorldService")
	local nextWorld = WorldService:GetNextWorld(worldName)
	local unlockRequirement = nextWorld and Stats.GetWorldDistanceRequirement(nextWorld) or nil
	local rebirthRequirement = nextWorld and Stats.GetWorldRebirthRequirement(nextWorld) or nil
	
	local percentageToNextWorld = 0
	if unlockRequirement and unlockRequirement > 0 then
		percentageToNextWorld = math.clamp((distanceTraveled / unlockRequirement) * 100, 0, 100)
	end
	
	-- Check if player reached world unlock threshold (only if world exists in workspace)
	-- Must meet both distance AND rebirth requirements (if applicable)
	local worldExistsInWorkspace = nextWorld and Workspace:FindFirstChild(nextWorld)
	local meetsRequirements = worldUnlocked and nextWorld and WorldService:PlayerMeetsUnlockRequirements(player, nextWorld, distanceTraveled)
	local shouldUnlockWorld = meetsRequirements and worldExistsInWorkspace
	
	-- Clear player from track
	PlayersOnTrack[userId] = nil
	
	-- Stop lap tracking
	local LapService = Knit.GetService("LapService")
	LapService:StopTracking(player)
	
	-- Fire signal to client that track has ended
	TrackService.Client.TrackEnded:Fire(player, {
		distanceTraveled = distanceTraveled,
		cashEarned = cashEarned,
		percentageToNextWorld = percentageToNextWorld,
		unlockRequirement = unlockRequirement,
		rebirthRequirement = rebirthRequirement,
	})

	-- clear all stars
	local StarService = Knit.GetService("StarService")
	StarService:RemoveAllStarsForPlayer(player)
	StarService:Start(player)
	
	-- Handle world unlock if applicable
	if shouldUnlockWorld then
		Log(string.format("Player %s unlocked world %s with distance %.2f", player.Name, nextWorld, distanceTraveled))
		
		-- Unlock the new world for the player (this also teleports and updates client data)
		WorldService:GiveWorldToPlayer(player, nextWorld)
		
		-- Send notification about world unlock
		local NotificationService = Knit.GetService("NotificationService")
		NotificationService:SendNotification(
			player,
			string.format("🌟 Congratulations! You unlocked %s! 🌟", nextWorld),
			NotificationService.Category.Success,
			5
		)
	else
		-- Teleport player back to spawn area in current world (if not unlocking new world)
		local spawnLocation = GetSpawnLocationForWorld(worldName)
		if spawnLocation and character then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				-- Teleport slightly above spawn to prevent clipping
				local spawnCFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
				rootPart.CFrame = spawnCFrame
				Log(string.format("Teleported player %s back to spawn in %s", player.Name, worldName))
			end
		end
	end
end

-- Remove player from track (alias for EndTrackRun)
function TrackService:RemovePlayerFromTrack(player: Player)
	self:EndTrackRun(player)
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
	
	-- Calculate track parameters with acceleration using player's world and fuel
	local trackParams = CalculateTrackParameters(player, worldName)
	
	-- Track the player as running on the track (store player reference and world for efficient heartbeat loop)
	PlayersOnTrack[userId] = {
		player = player,
		worldName = worldName,
		startTime = tick(),
		gateIndex = tonumber(closestGate:match("%d+")),
		totalDistance = trackParams.totalDistance,
		currentAngle = initialAngle,
		startAngle = initialAngle, -- Store starting angle for lap detection
		initialSpeed = trackParams.initialSpeed,
		acceleration = trackParams.acceleration,
		maxSpeed = trackParams.maxSpeed,
		totalTime = trackParams.totalTime,
		distanceTraveled = 0,
		elapsedTime = 0, -- Track elapsed time for acceleration calculations
		lapCount = 0, -- Track number of completed laps
	}
	
	-- Get next world unlock requirement to send to client
	local WorldService = Knit.GetService("WorldService")
	local nextWorld = WorldService:GetNextWorld(worldName)
	local unlockRequirement = nextWorld and Stats.GetWorldDistanceRequirement(nextWorld) or nil
	local rebirthRequirement = nextWorld and Stats.GetWorldRebirthRequirement(nextWorld) or nil
	
	-- Start lap tracking with full track data for server-side percentage calculation
	local LapService = Knit.GetService("LapService")
	LapService:StartTracking(player, worldName, nextWorld or worldName, {
		player = player,
		launchWorld = worldName,
		targetWorld = nextWorld or worldName,
		startTime = tick(),
		startAngle = initialAngle,
		initialSpeed = trackParams.initialSpeed,
		acceleration = trackParams.acceleration,
		maxSpeed = trackParams.maxSpeed,
		worldRadius = radius,
	})
	
	-- Setup weld constraints to attach pets to the player during track run
	SetupPetWeldsForTrack(player)
	
	-- Fire signal to client that track has started (client will handle movement and effects)
	TrackService.Client.TrackStarted:Fire(player, {
		gateName = closestGate,
		totalDistance = trackParams.totalDistance,
		initialSpeed = trackParams.initialSpeed,
		acceleration = trackParams.acceleration,
		maxSpeed = trackParams.maxSpeed,
		totalTime = trackParams.totalTime,
		startAngle = initialAngle,
		worldName = worldName,
		worldRadius = radius,
		trackCenter = center,
		maxPhysicalSpeed = Stats.MaxPhysicalSpeed,
		nextWorld = nextWorld,
		unlockRequirement = unlockRequirement,
		rebirthRequirement = rebirthRequirement,
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
	
	-- Cleanup pet weld constraints
	CleanupPetWeldsForTrack(player)
	
	-- DO NOT reset fuel on cancellation
	
	-- Clear player from track
	PlayersOnTrack[userId] = nil
	
	-- Stop lap tracking
	local LapService = Knit.GetService("LapService")
	LapService:StopTracking(player)
	
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

-- Client request to end track run (with distance traveled and world unlock info)
function TrackService.Client:RequestTrackEnd(player: Player, distanceTraveled: number, worldUnlocked: boolean): (boolean, string?)
	local userId = player.UserId
	local trackData = PlayersOnTrack[userId]
	
	-- Check if player is on the track
	if not trackData then
		return false, "Not currently on track"
	end
	
	-- Validate distance is a number and log suspicious requests
	if type(distanceTraveled) ~= "number" then
		warn(string.format("[TrackService]: Player %s sent invalid distance type: %s", player.Name, type(distanceTraveled)))
		distanceTraveled = 0
	elseif distanceTraveled < 0 then
		warn(string.format("[TrackService]: Player %s sent negative distance: %.2f", player.Name, distanceTraveled))
		distanceTraveled = 0
	elseif distanceTraveled > trackData.totalDistance * 1.1 then
		-- Allow small tolerance (10%) but log if significantly over
		warn(string.format("[TrackService]: Player %s sent suspicious distance: %.2f (max expected: %.2f)", player.Name, distanceTraveled, trackData.totalDistance))
	end
	
	Log(string.format("Player %s requested track end with distance: %.2f, worldUnlocked: %s", player.Name, distanceTraveled, tostring(worldUnlocked)))
	
	-- Call EndTrackRun with the client-provided distance (validated inside)
	TrackService:EndTrackRun(player, distanceTraveled, worldUnlocked)
	
	return true, nil
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	local character = player.Character
	if character then
		CleanupBodyMovers(character)
	end
	-- Cleanup pet weld constraints if player was on track
	if PlayersOnTrack[player.UserId] then
		CleanupPetWeldsForTrack(player)
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
	-- Movement is now handled client-side via BindToRenderStep
	Log("TrackService started")
end

return TrackService
