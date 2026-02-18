-- client handler for main boss (single global boss system)

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local summonButton: TextButton

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

function MainBossController:GetCurrentBossMaxHealth()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local currentBoss = statsFolder:FindFirstChild("CurrentBoss")
		if currentBoss and currentBoss:IsA("StringValue") and currentBoss.Value ~= "" then
			return Stats.GetBossHealth(currentBoss.Value)
		end
	end
	return 100
end

function MainBossController:UpdateHealthDisplay()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then return end
	
	local bossHealth = statsFolder:FindFirstChild("BossHealth")
	if not bossHealth then return end
	
	local maxHealth = self:GetCurrentBossMaxHealth()
	local currentHealth = bossHealth.Value
	
	SetBarColor(COLOR_HEALTH_ACTIVE)
	TweenBar(currentHealth / maxHealth)
end

local playerInArena = false
local lastArenaPart = nil
local originalArenaColor = nil
local originalArenaMaterial = nil

function MainBossController:IsPlayerInArena()
	return playerInArena
end

function MainBossController:SetInArena(inArena: boolean, arenaPart: BasePart?)
	if playerInArena == inArena and lastArenaPart == arenaPart then return end
	
	playerInArena = inArena
	
	if inArena and arenaPart then
		if lastArenaPart and lastArenaPart ~= arenaPart then
			-- Restore previous part if different
			lastArenaPart.Material = originalArenaMaterial
			lastArenaPart.Color = originalArenaColor
		end
		
		if lastArenaPart ~= arenaPart then
			lastArenaPart = arenaPart
			originalArenaMaterial = arenaPart.Material
			originalArenaColor = arenaPart.Color
		end
		
		arenaPart.Material = Enum.Material.Neon
		arenaPart.Color = Color3.fromRGB(255, 255, 0) -- Yellow
	else
		-- Restore
		if lastArenaPart then
			lastArenaPart.Material = originalArenaMaterial
			lastArenaPart.Color = originalArenaColor
			lastArenaPart = nil
		end
	end
end

local function CheckArenaOverlap()
	if not MainBossController:IsBossFightActive() then
		if playerInArena then
			MainBossController:SetInArena(false)
		end
		return
	end

	local char = player.Character
	if not char then return end
	
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local currentWorld = player:GetAttribute("CurrentWorld")
	if not currentWorld then return end
	
	local worldFolder = workspace:FindFirstChild(currentWorld)
	if not worldFolder then return end
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then return end
	
	local currentBossVal = statsFolder:FindFirstChild("CurrentBoss")
	local bossName = currentBossVal and currentBossVal.Value
	
	if not bossName or bossName == "" then return end
	
	local bossModel = worldFolder:FindFirstChild(bossName)
	if not bossModel then return end
	
	local bossArena = bossModel:FindFirstChild("BossArena")
	if not bossArena or not bossArena:IsA("BasePart") then return end
	
	-- Check bounds
	-- "cylinder which has been flattened" - assume largest dimension is Diameter
	local size = bossArena.Size
	local diameter = math.max(size.X, size.Z)
	local radius = diameter / 2
	
	local dist = (root.Position * Vector3.new(1,0,1) - bossArena.Position * Vector3.new(1,0,1)).Magnitude
	
	-- Vertical check - allow some height above/below
	local vertDist = math.abs(root.Position.Y - bossArena.Position.Y)
	
	if dist <= radius and vertDist <= 20 then
		MainBossController:SetInArena(true, bossArena)
	else
		MainBossController:SetInArena(false)
	end
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
	summonButton = topBar:WaitForChild("Summon")
end

function MainBossController:KnitStart()
	task.spawn(function()
		task.wait(1) 
		self:SetupStarListeners()
		self:SetupHealthListener()
		self:SetupBossFightListener()
		self:UpdateUnlockProgress()
	end)

	summonButton.MouseButton1Click:Connect(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetDevProductId("SummonBoss"):andThen(function(productId)
			if productId then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end)
	end)

	RunService.RenderStepped:Connect(CheckArenaOverlap)
end

return MainBossController