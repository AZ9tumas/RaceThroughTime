--[[
	Main Game Loop
	This module is called after Knit is fully initialized with all services loaded.
	Structure your main game logic here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Main game loop function
local function Main()
	print("[Main]: Game loop starting...")

	local DataService = Knit.GetService("DataService")
	local StarService = Knit.GetService("StarService")
	local PetService = Knit.GetService("PetService")

	-- Set up session ready handler for each player
	local function OnPlayerSessionReady(player: Player)
		print("[Main]: Waiting for player session to be ready - " .. player.Name)
		DataService:OnSessionReady(player):andThen(function()
			print(string.format("[Main]: Player %s session fully initialized", player.Name))

			-- Initialize pet IDs for the player (IDs are session-only, not persisted)
			PetService:InitializePets(player)

			-- Start star automated spawning
			StarService:Start(player)

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