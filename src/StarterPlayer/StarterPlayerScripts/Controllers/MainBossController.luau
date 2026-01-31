-- client handler for main boss (single global boss system)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

local starConnections = {}

local function TweenBar(progress: number)
	if not Unlockfill then return end
	local targetSize = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
	
	local tweenInfo = TweenInfo.new(
		0.5,
		Enum.EasingStyle.Elastic,
		Enum.EasingDirection.Out
	)
	
	local tween = TweenService:Create(Unlockfill, tweenInfo, {Size = targetSize})
	tween:Play()
end

function MainBossController:UpdateUnlockProgress()
	local unlockReq = Stats.BossUnlockRequirement.Stars or 10
	
	local starsCollectedFolder = ReplicatedStorage:FindFirstChild("StarsCollected")
	if not starsCollectedFolder then return end
	
	local totalStars = 0
	for _, worldValue in ipairs(starsCollectedFolder:GetChildren()) do
		if worldValue:IsA("IntValue") or worldValue:IsA("NumberValue") then
			totalStars = totalStars + worldValue.Value
		end
	end
	
	TweenBar(totalStars / unlockReq)
end

function MainBossController:SetupStarListeners()
	for _, conn in pairs(starConnections) do
		conn:Disconnect()
	end
	starConnections = {}
	
	local starsCollectedFolder = ReplicatedStorage:FindFirstChild("StarsCollected")
	if not starsCollectedFolder then return end
	
	for _, worldValue in ipairs(starsCollectedFolder:GetChildren()) do
		if worldValue:IsA("IntValue") or worldValue:IsA("NumberValue") then
			local conn = worldValue.Changed:Connect(function()
				self:UpdateUnlockProgress()
			end)
			table.insert(starConnections, conn)
		end
	end
	
	local childAddedConn = starsCollectedFolder.ChildAdded:Connect(function(child)
		if child:IsA("IntValue") or child:IsA("NumberValue") then
			local conn = child.Changed:Connect(function()
				self:UpdateUnlockProgress()
			end)
			table.insert(starConnections, conn)
			self:UpdateUnlockProgress()
		end
	end)
	table.insert(starConnections, childAddedConn)
end

function MainBossController:KnitInit()
	mainUi = PlayerGui:WaitForChild("RaceThroughTime_UI")
	topBar = mainUi:WaitForChild("TopInfo")
	serverBar = topBar:WaitForChild("ServerBar")
	Unlockfill = serverBar:WaitForChild("Fill")
end

function MainBossController:KnitStart()
	task.spawn(function()
		task.wait(1) 
		self:SetupStarListeners()
		self:UpdateUnlockProgress()
	end)
end

return MainBossController