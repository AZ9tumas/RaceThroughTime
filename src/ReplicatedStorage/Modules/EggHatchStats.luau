--[[
	EggHatchStats Module
	Configuration for egg hatching animations including timing, shaking, and visual effects.
	
	The egg shake animation starts slow and gradually increases in frequency and intensity
	towards the end of the hatch time.
]]

local EggHatchStats = {}

-- Main hatching configuration
EggHatchStats.HatchTime = 3.0 -- Total time in seconds for the egg to hatch

-- Shake configuration
EggHatchStats.Shake = {
	-- Initial shake parameters (start of animation)
	InitialFrequency = 5, -- Shakes per second at the start
	InitialIntensity = 2, -- Rotation angle in degrees at start
	
	-- Final shake parameters (end of animation)
	FinalFrequency = 25, -- Shakes per second at the end
	FinalIntensity = 15, -- Rotation angle in degrees at end
	
	-- Rate of change
	-- How the shake accelerates from initial to final (0 = linear, higher = more exponential)
	AccelerationCurve = 2.0, -- Exponential acceleration factor
}

-- Camera configuration for ViewportFrame
EggHatchStats.Camera = {
	FieldOfView = 50,
	Distance = 8, -- Distance from egg center
	Height = 2, -- Camera height offset
	Angle = 15, -- Tilt angle in degrees
}

-- Visual effects
EggHatchStats.Effects = {
	-- Egg scale animation on spawn
	SpawnScaleDuration = 0.4,
	SpawnScaleStart = 0.1,
	SpawnScaleEnd = 1.0,
	
	-- Flash on hatch
	FlashDuration = 0.15,
	
	-- Result display time
	ResultDisplayTime = 2.5,
	
	-- Fade out duration
	FadeOutDuration = 0.5,
}

-- Sound configuration
EggHatchStats.Sounds = {
	Equip = "rbxassetid://244655616",
	Crack = "rbxassetid://4819098925",
	Explode = "rbxassetid://2801263161",
	Tada = "rbxassetid://6042054019",
	
	-- Crack sound probability during shake
	CrackProbability = 0.02, -- 2% chance per frame
}

-- Helper function to calculate shake parameters at a given progress (0 to 1)
-- Returns frequency and intensity based on progress through the animation
function EggHatchStats.GetShakeParams(progress: number): (number, number)
	local shake = EggHatchStats.Shake
	
	-- Apply acceleration curve for non-linear progression
	local curvedProgress = math.pow(progress, shake.AccelerationCurve)
	
	-- Interpolate between initial and final values
	local frequency = shake.InitialFrequency + (shake.FinalFrequency - shake.InitialFrequency) * curvedProgress
	local intensity = shake.InitialIntensity + (shake.FinalIntensity - shake.InitialIntensity) * curvedProgress
	
	return frequency, intensity
end

-- Helper function to calculate shake rotation at a given time and progress
-- Returns X and Z rotation angles in radians
function EggHatchStats.CalculateShakeRotation(time: number, progress: number): (number, number)
	local frequency, intensity = EggHatchStats.GetShakeParams(progress)
	
	-- Use sine and cosine for smooth oscillation
	local rotX = math.sin(time * frequency * math.pi * 2) * math.rad(intensity)
	local rotZ = math.cos(time * frequency * math.pi * 2 * 0.8) * math.rad(intensity * 0.7)
	
	return rotX, rotZ
end

return EggHatchStats
