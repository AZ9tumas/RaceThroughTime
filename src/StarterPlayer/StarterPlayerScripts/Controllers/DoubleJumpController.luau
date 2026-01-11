--[[
	DoubleJumpController
	Handles double jump mechanic that pushes players forward.
	The double jump is disabled when the player is on the track.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local DoubleJumpController = Knit.CreateController({
	Name = "DoubleJumpController",
})

-- Configuration
local DOUBLE_JUMP_POWER = 50 -- Upward velocity for double jump
local FORWARD_PUSH_FORCE = 30 -- Forward velocity push on double jump
local DOUBLE_JUMP_COOLDOWN = 0.3 -- Seconds between double jumps

-- Private state
local player = Players.LocalPlayer
local canDoubleJump = false
local hasDoubleJumped = false
local lastJumpTime = 0
local inputConnection = nil
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

-- Perform the double jump
local function PerformDoubleJump()
	-- Don't allow double jump while on track
	if IsPlayerOnTrack() then
		return
	end
	
	-- Check cooldown
	local currentTime = os.clock()
	if (currentTime - lastJumpTime) < DOUBLE_JUMP_COOLDOWN then
		return
	end
	
	-- Must have already jumped once and not double jumped yet
	if not canDoubleJump or hasDoubleJumped then
		return
	end
	
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not rootPart then return end
	
	-- Mark that we've used the double jump
	hasDoubleJumped = true
	canDoubleJump = false
	lastJumpTime = currentTime
	
	-- Get the player's look direction (forward direction)
	local lookVector = rootPart.CFrame.LookVector
	
	-- Calculate forward velocity
	local forwardVelocity = Vector3.new(lookVector.X, 0, lookVector.Z).Unit * FORWARD_PUSH_FORCE
	
	-- Apply velocity to root part (upward + forward push)
	rootPart.AssemblyLinearVelocity = Vector3.new(
		rootPart.AssemblyLinearVelocity.X + forwardVelocity.X,
		DOUBLE_JUMP_POWER, -- Set upward velocity
		rootPart.AssemblyLinearVelocity.Z + forwardVelocity.Z
	)
	
	-- Play a small animation or effect (change humanoid state)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	
	Log("Double jump performed!")
end

-- Handle humanoid state changes to track jump state
local function OnHumanoidStateChanged(newState: Enum.HumanoidStateType)
	if newState == Enum.HumanoidStateType.Jumping then
		-- After first jump, enable double jump possibility
		if not hasDoubleJumped then
			canDoubleJump = true
		end
	elseif newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
		-- Reset double jump when landed
		canDoubleJump = false
		hasDoubleJumped = false
	elseif newState == Enum.HumanoidStateType.Freefall then
		-- In freefall after initial jump, can double jump
		if not hasDoubleJumped then
			canDoubleJump = true
		end
	end
end

-- Handle jump input
local function OnInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then return end
	
	-- Check for jump key (Space or ButtonA on controller)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		-- Check if we're already in the air (can double jump)
		local character = player.Character
		if not character then return end
		
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		
		-- Only trigger double jump if in freefall or jumping state
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			PerformDoubleJump()
		end
	end
end

-- Setup connections for a character
local function SetupCharacter(character: Model)
	-- Clean up previous connections
	if stateConnection then
		stateConnection:Disconnect()
		stateConnection = nil
	end
	
	-- Wait for humanoid
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	
	-- Connect to state changes
	stateConnection = humanoid.StateChanged:Connect(function(_, newState)
		OnHumanoidStateChanged(newState)
	end)
	
	-- Reset state
	canDoubleJump = false
	hasDoubleJumped = false
	
	Log("Double jump setup for character")
end

-- Knit lifecycle
function DoubleJumpController:KnitInit()
	-- Controller initialization
end

function DoubleJumpController:KnitStart()
	-- Connect to input and store connection
	inputConnection = UserInputService.InputBegan:Connect(OnInputBegan)
	
	-- Setup for current character
	if player.Character then
		SetupCharacter(player.Character)
	end
	
	-- Setup for future characters
	player.CharacterAdded:Connect(SetupCharacter)
	
	Log("DoubleJumpController started")
end

return DoubleJumpController
