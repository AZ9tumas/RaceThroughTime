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
local healthConnection = nil
local bossFightConnection = nil

local COLOR_HEALTH_ACTIVE = Color3.fromRGB(46, 204, 113)
local COLOR_INACTIVE = Color3.fromRGB(255, 100, 50)

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

local function SetBarColor(color: Color3)
	if Unlockfill then
		Unlockfill.BackgroundColor3 = color
	end
end

function MainBossController:IsBossFightActive()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			return bossFight.Value
		end
	end
	return false
end

function MainBossController:UpdateHealthDisplay()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then return end
	
	local bossHealth = statsFolder:FindFirstChild("BossHealth")
	if not bossHealth then return end
	
	local maxHealth = Stats.BossMaxHealth or 100
	local currentHealth = bossHealth.Value
	
	SetBarColor(COLOR_HEALTH_ACTIVE)
	TweenBar(currentHealth / maxHealth)
end

function MainBossController:UpdateUnlockProgress()
	if self:IsBossFightActive() then
		self:UpdateHealthDisplay()
		return
	end
	
	SetBarColor(COLOR_INACTIVE)
	
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

function MainBossController:SetupHealthListener()
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then return end
	
	local bossHealth = statsFolder:FindFirstChild("BossHealth")
	if bossHealth and bossHealth:IsA("NumberValue") then
		healthConnection = bossHealth.Changed:Connect(function()
			if self:IsBossFightActive() then
				self:UpdateHealthDisplay()
			end
		end)
	end
end

function MainBossController:SetupBossFightListener()
	if bossFightConnection then
		bossFightConnection:Disconnect()
		bossFightConnection = nil
	end
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then return end
	
	local bossFight = statsFolder:FindFirstChild("BossFight")
	if bossFight and bossFight:IsA("BoolValue") then
		bossFightConnection = bossFight.Changed:Connect(function()
			self:UpdateUnlockProgress()
		end)
	end
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
		self:SetupHealthListener()
		self:SetupBossFightListener()
		self:UpdateUnlockProgress()
	end)
end

return MainBossController