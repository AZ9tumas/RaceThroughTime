--[[
	LoadingScreenController
	Handles the loading screen UI fade-in/fade-out and coordinates with data loading.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LoadingScreenController = Knit.CreateController({
	Name = "LoadingScreenController",
})

-- Private state
local IsDataReady = false
local IsAssetsReady = false
local LoadingFrame = nil

-- Tween settings
local FADE_IN_TIME = 0.5
local FADE_OUT_TIME = 0.5

-- Get the loading frame
local function GetLoadingFrame()
	local playerGui = Knit.Player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[LoadingScreenController]: PlayerGui not found")
		return nil
	end

	local loadingGui = playerGui:WaitForChild("Loading", 10)
	if not loadingGui then
		warn("[LoadingScreenController]: Loading GUI not found")
		return nil
	end

	local whiteFrame = loadingGui:WaitForChild("WhiteFrame", 10)
	if not whiteFrame then
		warn("[LoadingScreenController]: WhiteFrame not found")
		return nil
	end

	return whiteFrame
end

-- Fade in the loading screen
local function FadeIn(frame)
	if not frame then return end

	-- Make visible first, then fade in
	frame.Visible = true
	frame.BackgroundTransparency = 1

	local tweenInfo = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(frame, tweenInfo, {
		BackgroundTransparency = 0
	})
	tween:Play()
	tween.Completed:Wait()
end

-- Fade out the loading screen
local function FadeOut(frame)
	if not frame then return end

	local tweenInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(frame, tweenInfo, {
		BackgroundTransparency = 1
	})
	tween:Play()
	tween.Completed:Wait()

	frame.Visible = false
end

-- Check if loading is complete and fade out if so
local function TryCompleteLoading()
	if IsDataReady and IsAssetsReady then
		FadeOut(LoadingFrame)

		-- Request character spawn from server
		local DataService = Knit.GetService("DataService")
		DataService:SignalReady()
		
		-- Show welcome notification when session is ready
		local NotificationController = Knit.GetController("NotificationController")
		NotificationController:ShowNotification("Welcome! Your session is ready.", 4, nil, {
			icon = "🎮"
		})
	end
end

-- Mark data as ready
function LoadingScreenController:SetDataReady()
	IsDataReady = true
	TryCompleteLoading()
end

-- Mark assets as ready
function LoadingScreenController:SetAssetsReady()
	IsAssetsReady = true
	TryCompleteLoading()
end

-- Check if loading is complete
function LoadingScreenController:IsLoadingComplete(): boolean
	return IsDataReady and IsAssetsReady
end

-- Knit lifecycle
function LoadingScreenController:KnitInit()
	-- Get loading frame reference
	LoadingFrame = GetLoadingFrame()
end

function LoadingScreenController:KnitStart()
	-- Immediately fade in the loading screen when player joins
	task.spawn(function()
		if LoadingFrame then
			FadeIn(LoadingFrame)
		end
	end)

	-- Listen for DataReady signal from server
	local DataService = Knit.GetService("DataService")
	DataService.DataReady:Connect(function()
		self:SetDataReady()
	end)
end

return LoadingScreenController
