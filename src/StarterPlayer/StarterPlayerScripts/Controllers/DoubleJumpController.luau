--[[
	DoubleJumpController
	Handles double jump mechanic that pushes players forward.
	The double jump is disabled when the player is on the track.
	
	Based on standard Roblox double jump pattern using JumpRequest.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local DoubleJumpController = Knit.CreateController({
	Name = "DoubleJumpController",
})

-- Configuration
local TIME_BETWEEN_JUMPS = 0.2 -- Time to wait before enabling double jump
local DOUBLE_JUMP_POWER_MULTIPLIER = 2 -- Multiplier for jump power on double jump
local FORWARD_IMPULSE_FORCE = 500 -- Forward impulse force on double jump

-- Private state
local localPlayer = Players.LocalPlayer
local character = nil
local humanoid = nil
local canDoubleJump = false
local hasDoubleJumped = false
local oldPower = nil
local stateConnection = nil

-- Helper function for logging
local function Log(message: string)
	print(string.format("[DoubleJumpController]: %s", message))
end

-- Check if player is on the track (disable double jump on track)
local function IsPlayerOnTrack(): boolean
	local TrackController = Knit.GetController("TrackController")
	if TrackController then
		return TrackController:IsOnTrack()
	end
	return false
end

-- Handle jump request
local function onJumpRequest()
	-- Don't allow double jump while on track
	if IsPlayerOnTrack() then
		return
	end
	
	if not character or not humanoid or not character:IsDescendantOf(workspace) or
		humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return
	end
	
	if canDoubleJump and not hasDoubleJumped then
		hasDoubleJumped = true
		humanoid.JumpPower = oldPower * DOUBLE_JUMP_POWER_MULTIPLIER
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		
		-- Apply forward impulse
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local lookVector = rootPart.CFrame.LookVector
			local forwardImpulse = Vector3.new(lookVector.X, 0, lookVector.Z).Unit * FORWARD_IMPULSE_FORCE
			rootPart:ApplyImpulse(forwardImpulse)
		end
		
		Log("Double jump performed!")
	end
end

-- Setup character connections
local function characterAdded(newCharacter: Model)
	-- Clean up previous state connection
	if stateConnection then
		stateConnection:Disconnect()
		stateConnection = nil
	end
	
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	hasDoubleJumped = false
	canDoubleJump = false
	oldPower = humanoid.JumpPower
	
	stateConnection = humanoid.StateChanged:Connect(function(old, new)
		if new == Enum.HumanoidStateType.Landed then
			canDoubleJump = false
			hasDoubleJumped = false
			humanoid.JumpPower = oldPower
		elseif new == Enum.HumanoidStateType.Freefall then
			task.spawn(function()
				task.wait(TIME_BETWEEN_JUMPS)
				canDoubleJump = true
			end)
		end
	end)
	
	-- Ensure JumpPower is reset if character is removed
	newCharacter.AncestryChanged:Connect(function(_, parent)
		if parent == nil and humanoid then
			humanoid.JumpPower = oldPower
		end
	end)
	
	Log("Double jump setup for character")
end

-- Knit lifecycle
function DoubleJumpController:KnitInit()
	-- Controller initialization
end

function DoubleJumpController:KnitStart()
	-- Setup for current character
	if localPlayer.Character then
		characterAdded(localPlayer.Character)
	end
	
	-- Setup for future characters
	localPlayer.CharacterAdded:Connect(characterAdded)
	
	-- Connect to jump request
	UserInputService.JumpRequest:Connect(onJumpRequest)
	
	Log("DoubleJumpController started")
end

return DoubleJumpController
