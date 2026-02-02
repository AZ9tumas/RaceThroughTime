local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local BossService = Knit.CreateService({
	Name = "BossService",
	Client = {},
})

local CurrentBossIndex = 0
local SpawnedBosses = {}
local CurrentBossKey = nil

local function AnchorAndDisableCollision(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

function BossService:SpawnBoss()
	CurrentBossIndex = CurrentBossIndex + 1
	if CurrentBossIndex > #Stats.BossList then
		CurrentBossIndex = 1
	end
	
	local bossKey = Stats.BossList[CurrentBossIndex]
	CurrentBossKey = bossKey
	local bossInfo = Stats.Bosses[bossKey]
	if not bossInfo then
		warn("[BossService] Boss info not found for:", bossKey)
		return
	end
	
	local bossAssets = ServerStorage:FindFirstChild("Assets")
	if not bossAssets then
		warn("[BossService] ServerStorage.Assets not found")
		return
	end
	
	local bossesFolder = bossAssets:FindFirstChild("Bosses")
	if not bossesFolder then
		warn("[BossService] ServerStorage.Assets.Bosses not found")
		return
	end
	
	local bossModel = bossesFolder:FindFirstChild(bossKey)
	if not bossModel then
		warn("[BossService] Boss model not found:", bossKey)
		return
	end
	
	for _, existingBoss in ipairs(SpawnedBosses) do
		if existingBoss and existingBoss.Parent then
			existingBoss:Destroy()
		end
	end
	SpawnedBosses = {}
	
	for _, world in ipairs(workspace:GetChildren()) do
		local spawnLocation = world:FindFirstChild("SpawnLocation")
		if spawnLocation and spawnLocation:IsA("BasePart") then
			local bossClone = bossModel:Clone() :: Model
			bossClone.Name = bossKey
			
			AnchorAndDisableCollision(bossClone)
			
			if bossClone.PrimaryPart then
				bossClone:PivotTo(spawnLocation.CFrame + Vector3.new(0, bossClone.PrimaryPart.Size.Y / 2, 0))
			elseif bossClone:FindFirstChild("HumanoidRootPart") then
				bossClone.HumanoidRootPart.CFrame = spawnLocation.CFrame
			else
				local firstPart = bossClone:FindFirstChildWhichIsA("BasePart")
				if firstPart then
					firstPart.CFrame = spawnLocation.CFrame
				end
			end
			
			bossClone.Parent = world
			table.insert(SpawnedBosses, bossClone)
		end
	end
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			bossFight.Value = true
		end
		
		local bossHealth = statsFolder:FindFirstChild("BossHealth")
		if bossHealth and bossHealth:IsA("NumberValue") then
			bossHealth.Value = Stats.GetBossHealth(bossKey)
		end
		
		local currentBossValue = statsFolder:FindFirstChild("CurrentBoss")
		if not currentBossValue then
			currentBossValue = Instance.new("StringValue")
			currentBossValue.Name = "CurrentBoss"
			currentBossValue.Parent = statsFolder
		end
		currentBossValue.Value = bossKey
	end
	
	return bossKey
end

function BossService:GetCurrentBossName()
	return CurrentBossKey
end

function BossService:GetCurrentBossHealth(): number
	if CurrentBossKey then
		return Stats.GetBossHealth(CurrentBossKey)
	end
	return 100
end

function BossService:IsBossFightActive()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			return bossFight.Value
		end
	end
	return false
end

function BossService:DamageBoss(damage: number)
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then return end
	
	local bossHealth = statsFolder:FindFirstChild("BossHealth")
	if not bossHealth or not bossHealth:IsA("NumberValue") then return end
	
	bossHealth.Value = math.max(0, bossHealth.Value - damage)
	
	-- Check if boss is dead
	if bossHealth.Value <= 0 then
		self:EndBossFight()
	end
end

function BossService:EndBossFight()
	for _, existingBoss in ipairs(SpawnedBosses) do
		if existingBoss and existingBoss.Parent then
			existingBoss:Destroy()
		end
	end
	SpawnedBosses = {}
	CurrentBossKey = nil
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			bossFight.Value = false
		end
		
		local bossHealth = statsFolder:FindFirstChild("BossHealth")
		if bossHealth and bossHealth:IsA("NumberValue") then
			bossHealth.Value = 0
		end
		
		local currentBossValue = statsFolder:FindFirstChild("CurrentBoss")
		if currentBossValue and currentBossValue:IsA("StringValue") then
			currentBossValue.Value = ""
		end
	end
	
	-- Reset server stars - get StarService and reset
	local StarService = Knit.GetService("StarService")
	if StarService and StarService.ResetAllStars then
		StarService:ResetAllStars()
	end
end

function BossService:KnitStart()
end

function BossService:KnitInit()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then
		statsFolder = Instance.new("Folder")
		statsFolder.Name = "Stats"
		statsFolder.Parent = ReplicatedStorage
	end
	
	local bossFight = statsFolder:FindFirstChild("BossFight")
	if not bossFight then
		bossFight = Instance.new("BoolValue")
		bossFight.Name = "BossFight"
		bossFight.Value = false
		bossFight.Parent = statsFolder
	end
	
	local bossHealth = statsFolder:FindFirstChild("BossHealth")
	if not bossHealth then
		bossHealth = Instance.new("NumberValue")
		bossHealth.Name = "BossHealth"
		bossHealth.Value = 0
		bossHealth.Parent = statsFolder
	end
end

return BossService
