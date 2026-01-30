-- client handler for main boss

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local Stats = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Stats"))

local MainBossController = Knit.CreateController({
	Name = "MainBossController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local mainUi: ScreenGui
local topBar: Frame
local serverBar: Frame
local Unlockfill: Frame

local currentWorld = nil
local starsCollectedFolder = ReplicatedStorage:WaitForChild("StarsCollected")
local starConnection = nil

local function TweenBar(progress: number)
	if not Unlockfill then return end
	local targetSize = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
	
	local tweenInfo = TweenInfo.new(
		0.5, -- Duration
		Enum.EasingStyle.Elastic, -- Quirky tween
		Enum.EasingDirection.Out
	)
	
	local tween = TweenService:Create(Unlockfill, tweenInfo, {Size = targetSize})
	tween:Play()
end

function MainBossController:UpdateUnlockProgress()
	local UIController = Knit.GetController("UIController")
	if not UIController then return end
	
	local data = UIController:GetData()
	local newWorld = data.Progression and data.Progression.CurrentWorld
	
	-- Handle World Change
	if newWorld ~= currentWorld then
		currentWorld = newWorld
		self:SetupWorldListener(currentWorld)
	end
	
	if not currentWorld then return end
	
	local unlockReq = Stats.MainBoss[currentWorld] or 10 -- Default fallback
	local collectedVal = starsCollectedFolder:FindFirstChild(currentWorld)
	local collected = collectedVal and collectedVal.Value or 0
	
	TweenBar(collected / unlockReq)
end

function MainBossController:SetupWorldListener(worldName: string)
	if starConnection then
		starConnection:Disconnect()
		starConnection = nil
	end
	
	local collectedVal = starsCollectedFolder:FindFirstChild(worldName)
	if collectedVal then
		starConnection = collectedVal.Changed:Connect(function()
			self:UpdateUnlockProgress()
		end)
	end
end

function MainBossController:KnitInit()
	mainUi = PlayerGui:WaitForChild("RaceThroughTime_UI")
	topBar = mainUi:WaitForChild("TopInfo")
	serverBar = topBar:WaitForChild("ServerBar")
	Unlockfill = serverBar:WaitForChild("Fill")
end

function MainBossController:KnitStart()
	-- Initial update
	task.spawn(function()
		-- Wait for data to be ready (usually signaled via UIController or just ready after start)
		task.wait(1) 
		self:UpdateUnlockProgress()
	end)
end

return MainBossController