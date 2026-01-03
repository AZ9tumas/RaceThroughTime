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