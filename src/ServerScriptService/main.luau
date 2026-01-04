--[[
	Main Game Loop
	This module is called after Knit is fully initialized with all services loaded.
	Structure your main game logic here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local function checkPrerequisites()
	local SpawnLocation: SpawnLocation = workspace:WaitForChild("RTT_Map_Final", 10):WaitForChild("SpawnLocation", 10)
	if not SpawnLocation then error("Expected a SpawnLocation under RTT_Map_Final in the workspace.", 3) end
end

--[[
    Circular Movement Logic (Polar to Cartesian)
    Use Case: "Race Through Time" Circular Track

local RunService = game:GetService("RunService")

-- Configuration
local center = Vector3.new(0, 5, 0) -- Center of the arena
local radius = 150                -- Distance from the center
local speed = 100                 -- Studs per second (Linear Speed)
local currentAngle = 0            -- Initial angle in radians (0 to 2*PI)

-- Function to update position
local function updateCircularPosition(dt)
    -- 1. Calculate Angular Velocity (w = v / r)
    -- This converts our linear "speed" into "radians per second"
	-- Center position = spawnlocation position
	-- (for more info look into star service get random locations)
    local angularVelocity = speed / radius

    -- 2. Update the Angle based on time delta
    currentAngle = currentAngle + (angularVelocity * dt)

    -- 3. Polar to Cartesian Conversion
    -- x = center.x + r * cos(theta)
    -- z = center.z + r * sin(theta)
    local x = center.X + radius * math.cos(currentAngle)
    local z = center.Z + radius * math.sin(currentAngle)
    local y = center.Y -- Height stays constant

    local targetPosition = Vector3.new(x, y, z)

    -- 4. Calculate Orientation (Tangential direction)
    -- We want the character to look forward along the path.
    -- The tangent is always perpendicular to the radius.
    local lookAtPos = targetPosition + Vector3.new(
        -math.sin(currentAngle), -- Derivative of cos
        0,
        math.cos(currentAngle)  -- Derivative of sin
    )

    local finalCFrame = CFrame.lookAt(targetPosition, lookAtPos)

    return finalCFrame
end

-- Simulated loop for testing (standard Roblox pattern)
RunService.Heartbeat:Connect(function(dt)
    local newCFrame = updateCircularPosition(dt)
    -- In your real code, you would apply this to an AlignPosition target 
    -- or directly to the character's HumanoidRootPart.CFrame.
    
    -- print("Current Position:", newCFrame.Position)
end)

return updateCircularPosition
]]

-- Main game loop function
local function Main()
	print("[Main]: Game loop starting...")

	-- check some prerequisites
	checkPrerequisites()

	local DataService = Knit.GetService("DataService")
	local StarService = Knit.GetService("StarService")

	-- Set up session ready handler for each player
	local function OnPlayerSessionReady(player: Player)
		print("[Main]: Waiting for player session to be ready - " .. player.Name)
		DataService:OnSessionReady(player):andThen(function()
			print(string.format("[Main]: Player %s session fully initialized", player.Name))

			-- Generate and spawn stars for this player
			StarService:GenerateStarInformation(player)
			StarService:SpawnStarsForPlayer(player)

			-- Additional game initialization for this player can go here
			-- Example: Initialize player's game state, start tutorials, etc.
		end):catch(function(err)
			warn(string.format("[Main]: Failed to initialize session for %s - %s", player.Name, tostring(err)))
		end)
	end
	
	-- Handle new players joining
	Players.PlayerAdded:Connect(OnPlayerSessionReady)
	
	-- Handle players who are already in the game
	for _, player in Players:GetPlayers() do
		task.spawn(OnPlayerSessionReady, player)
	end

	print("[Main]: Game loop initialized successfully")
end

return Main