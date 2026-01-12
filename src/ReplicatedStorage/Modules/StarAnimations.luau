--[[
	StarAnimations Module
	Provides animation functions for stars including:
	- Size pulsing (increase/decrease size)
	- Jump animations for attention grabbing
	
	All animations are dynamic with randomized timing.
]]

local TweenService = game:GetService("TweenService")

local StarAnimations = {}

-- Configuration
local PULSE_SIZE_INCREASE = 1.15 -- 15% size increase during pulse
local PULSE_DURATION = 0.3 -- Duration of size increase
local PULSE_HOLD_TIME = 0.5 -- Time to hold the increased size
local PULSE_INTERVAL_MIN = 0.5 -- Minimum time between pulses (seconds)
local PULSE_INTERVAL_MAX = 1.5 -- Maximum time between pulses (seconds)

local JUMP_HEIGHT = 2 -- Studs to jump up
local JUMP_DURATION = 0.25 -- Time for one jump direction
local JUMP_INTERVAL_MIN = 1.0 -- Minimum time between jumps
local JUMP_INTERVAL_MAX = 3.0 -- Maximum time between jumps

-- Private state to track animated stars
local AnimatingStars = {} -- [starInstance] = { pulseThread, jumpThread, originalSize, originalPosition }

-- Helper function to get random interval
local function GetRandomInterval(minTime: number, maxTime: number): number
	return math.random() * (maxTime - minTime) + minTime
end

-- Create pulse animation for a star
local function CreatePulseAnimation(star: Instance, originalSize: Vector3)
	local targetPart = nil
	
	if star:IsA("BasePart") then
		targetPart = star
	elseif star:IsA("Model") then
		targetPart = star.PrimaryPart or star:FindFirstChildWhichIsA("BasePart")
	end
	
	if not targetPart then return end
	
	-- Increase size
	local increasedSize = originalSize * PULSE_SIZE_INCREASE
	local increaseTween = TweenService:Create(targetPart, TweenInfo.new(PULSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = increasedSize
	})
	
	-- Decrease size back
	local decreaseTween = TweenService:Create(targetPart, TweenInfo.new(PULSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = originalSize
	})
	
	-- Play sequence
	increaseTween:Play()
	increaseTween.Completed:Wait()
	
	task.wait(PULSE_HOLD_TIME)
	
	decreaseTween:Play()
	decreaseTween.Completed:Wait()
end

-- Create jump animation for a star
local function CreateJumpAnimation(star: Instance, originalPosition: Vector3)
	local targetPart = nil
	
	if star:IsA("BasePart") then
		targetPart = star
	elseif star:IsA("Model") then
		targetPart = star.PrimaryPart or star:FindFirstChildWhichIsA("BasePart")
	end
	
	if not targetPart then return end
	
	-- Jump up
	local jumpUpPosition = originalPosition + Vector3.new(0, JUMP_HEIGHT, 0)
	local jumpUpTween = TweenService:Create(targetPart, TweenInfo.new(JUMP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = jumpUpPosition
	})
	
	-- Fall down
	local jumpDownTween = TweenService:Create(targetPart, TweenInfo.new(JUMP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = originalPosition
	})
	
	-- Play sequence
	jumpUpTween:Play()
	jumpUpTween.Completed:Wait()
	
	jumpDownTween:Play()
	jumpDownTween.Completed:Wait()
end

-- Start pulse animation loop for a star
local function StartPulseLoop(star: Instance, originalSize: Vector3): thread
	return task.spawn(function()
		while star and star.Parent do
			-- Wait for random interval before next pulse
			task.wait(GetRandomInterval(PULSE_INTERVAL_MIN, PULSE_INTERVAL_MAX))
			
			if not star or not star.Parent then break end
			
			CreatePulseAnimation(star, originalSize)
		end
	end)
end

-- Start jump animation loop for a star
local function StartJumpLoop(star: Instance, originalPosition: Vector3): thread
	return task.spawn(function()
		while star and star.Parent do
			-- Wait for random interval before next jump
			task.wait(GetRandomInterval(JUMP_INTERVAL_MIN, JUMP_INTERVAL_MAX))
			
			if not star or not star.Parent then break end
			
			CreateJumpAnimation(star, originalPosition)
		end
	end)
end

--[[
	Start all animations for a star.
	
	@param star Instance - The star part or model to animate
]]
function StarAnimations.StartAnimations(star: Instance)
	if AnimatingStars[star] then
		-- Already animating, stop first
		StarAnimations.StopAnimations(star)
	end
	
	local targetPart = nil
	if star:IsA("BasePart") then
		targetPart = star
	elseif star:IsA("Model") then
		targetPart = star.PrimaryPart or star:FindFirstChildWhichIsA("BasePart")
	end
	
	if not targetPart then
		warn("[StarAnimations]: Could not find target part for star animation")
		return
	end
	
	local originalSize = targetPart.Size
	local originalPosition = targetPart.Position
	
	-- Start animation loops
	local pulseThread = StartPulseLoop(star, originalSize)
	local jumpThread = StartJumpLoop(star, originalPosition)
	
	-- Store references
	AnimatingStars[star] = {
		pulseThread = pulseThread,
		jumpThread = jumpThread,
		originalSize = originalSize,
		originalPosition = originalPosition,
	}
end

--[[
	Stop all animations for a star.
	
	@param star Instance - The star to stop animating
]]
function StarAnimations.StopAnimations(star: Instance)
	local animData = AnimatingStars[star]
	if not animData then return end
	
	-- Cancel threads
	if animData.pulseThread then
		task.cancel(animData.pulseThread)
	end
	if animData.jumpThread then
		task.cancel(animData.jumpThread)
	end
	
	-- Reset to original state
	local targetPart = nil
	if star:IsA("BasePart") then
		targetPart = star
	elseif star:IsA("Model") then
		targetPart = star.PrimaryPart or star:FindFirstChildWhichIsA("BasePart")
	end
	
	if targetPart then
		targetPart.Size = animData.originalSize
		targetPart.Position = animData.originalPosition
	end
	
	AnimatingStars[star] = nil
end

--[[
	Stop all running animations.
]]
function StarAnimations.StopAllAnimations()
	for star, _ in pairs(AnimatingStars) do
		StarAnimations.StopAnimations(star)
	end
end

--[[
	Check if a star is currently being animated.
	
	@param star Instance - The star to check
	@return boolean - True if the star is being animated
]]
function StarAnimations.IsAnimating(star: Instance): boolean
	return AnimatingStars[star] ~= nil
end

return StarAnimations
