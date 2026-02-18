local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local Stats = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Stats"))
local EggHatchAnimation = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EggHatchAnimation"))

local EggController = Knit.CreateController({
	Name = "EggController",
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local EggService = nil
local DataService = nil
local NotificationController = nil
local UIFramesController = nil
local UIController = nil
local InventoryUIController = nil
local MonetizationController = nil

local eggHatchScreenGui: ScreenGui = nil
local eggHatchDimmer: Frame = nil
local eggviewport: ViewportFrame = nil
local eggHatchFlash: Frame? = nil

local CurrentWorldName = "Main"
local EggConnections: { [string]: { RBXScriptConnection } } = {}
local AutoHatchActive: { [string]: boolean } = {}
local IsHatching = false

-- Hatch animation queue system
local HatchAnimationQueue: { { eggName: string, petInfo: any } } = {}
local IsPlayingQueuedAnimation = false

local MULTI_HATCH_COUNT = 4
local AUTO_HATCH_DELAY = 0.5
local AUTO_HATCH_RANGE = 30

-- Process the hatch animation queue
local function ProcessHatchAnimationQueue()
	if IsPlayingQueuedAnimation then
		return
	end
	
	if #HatchAnimationQueue == 0 then
		return
	end
	
	IsPlayingQueuedAnimation = true
	
	-- Get next item from queue
	local queueItem = table.remove(HatchAnimationQueue, 1)
	if not queueItem then
		IsPlayingQueuedAnimation = false
		return
	end
	
	local eggName = queueItem.eggName
	local petInfo = queueItem.petInfo
	
	-- Check if we have InstantHatch gamepass
	local hasInstantHatch = MonetizationController and MonetizationController:HasGamePass("InstantHatch")
	
	if hasInstantHatch then
		-- Skip animation, just update UI
		if InventoryUIController then
			InventoryUIController:UpdatePetsInventory()
		end
		IsPlayingQueuedAnimation = false
		-- Process next in queue
		task.defer(ProcessHatchAnimationQueue)
	else
		-- Play hatch animation
		if UIFramesController then
			UIFramesController:DisableFrames(true)
		end
		eggviewport.Parent.Visible = true
		
		EggHatchAnimation.PlayHatch(
			eggviewport,
			eggName,
			eggHatchDimmer,
			eggHatchFlash,
			function(_animationSuccess)
				eggviewport.Parent.Visible = false
				if UIFramesController then
					UIFramesController:DisableFrames(false)
				end
				
				-- Update inventory UI
				if InventoryUIController then
					InventoryUIController:UpdatePetsInventory()
				end
				
				IsPlayingQueuedAnimation = false
				-- Process next in queue after a small delay
				task.delay(0.1, ProcessHatchAnimationQueue)
			end
		)
	end
end

-- Add hatch animation request to queue
local function QueueHatchAnimation(eggName: string, petInfo: any)
	table.insert(HatchAnimationQueue, {
		eggName = eggName,
		petInfo = petInfo,
	})
	
	-- Start processing if not already
	ProcessHatchAnimationQueue()
end

local function GetCurrentWorld(): string
	local worldAttr = Player:GetAttribute("CurrentWorld")
	if worldAttr then
		return worldAttr
	end
	return CurrentWorldName
end

local function GetEggConfig(eggName: string): { Cost: number, Currency: string, Pets: { { Pet: string, Probability: number } } }?
	return Stats.Eggs[eggName]
end

local function GetPetConfig(petName: string): { Name: string, Rarity: string? }?
	return Stats.Pets[petName]
end

local function FormatPercentage(probability: number): string
	return string.format("%.1f%%", probability * 100)
end

local function GetCurrentEggRoot(): BasePart?
	local worldFolder = Workspace:FindFirstChild(CurrentWorldName)
	if not worldFolder then
		return nil
	end
	
	local eggShopStands = worldFolder:FindFirstChild("EggShop_Stands")
	if not eggShopStands then
		return nil
	end
	
	local standardEgg = eggShopStands:FindFirstChild("StandardEgg")
	if not standardEgg then
		return nil
	end
	
	return standardEgg:FindFirstChild("EggRoot")
end

local function IsPlayerInRange(): boolean
	local eggRoot = GetCurrentEggRoot()
	if not eggRoot then
		return false
	end
	
	local character = Player.Character
	if not character then
		return false
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end
	
	local distance = (humanoidRootPart.Position - eggRoot.Position).Magnitude
	return distance <= AUTO_HATCH_RANGE
end

local function SetupPetTemplates(mainBoard: Frame, eggName: string)
	local eggConfig = GetEggConfig(eggName)
	if not eggConfig or not eggConfig.Pets then
		return
	end

	local contentFrame = mainBoard:FindFirstChild("Frame")
	if not contentFrame then
		return
	end

	local gridLayout = contentFrame:FindFirstChild("UIGridLayout")
	local template = gridLayout and gridLayout:FindFirstChild("Template")
	if not template then
		template = contentFrame:FindFirstChild("Template")
	end

	if not template then
		return
	end

	-- Determine which probability distributions are available
	local hasLuck = MonetizationController and MonetizationController:HasGamePass("Luck")
	local ServerBonusController = Knit.GetController("ServerBonusController")
	if not hasLuck then hasLuck = ServerBonusController and ServerBonusController:IsBonusEnabled("LuckParty") end

	local hasSuperLuck = MonetizationController and MonetizationController:HasGamePass("SuperLuck")
	local PotionsController = Knit.GetController("PotionsController")
	if not hasSuperLuck then hasSuperLuck = PotionsController and PotionsController:HasPotionEffect("SuperLuck") end

	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Template" and child ~= gridLayout and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	for i, petOption in ipairs(eggConfig.Pets) do
		local petName = petOption.Pet
		local probability = Stats.CalculateStackedProbability(
			petOption.Probability,
			petOption.LuckProbability or petOption.Probability,
			petOption.SuperLuckProbability or petOption.Probability,
			hasLuck,
			hasSuperLuck
		)
		local petConfig = GetPetConfig(petName)

		local newTemplate = template:Clone()
		newTemplate.Name = "Pet_" .. i
		newTemplate.Visible = true
		newTemplate.Parent = contentFrame

		local rarityLabel = newTemplate:FindFirstChild("Rarity")
		if rarityLabel and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = FormatPercentage(probability)
		end

		local nameLabel = newTemplate:FindFirstChild("Name") or newTemplate:FindFirstChild("PetName")
		if nameLabel and nameLabel:IsA("TextLabel") and petConfig then
			nameLabel.Text = petConfig.Name or petName
		end
	end

	template.Visible = false
end

local function PurchaseSingleEgg(eggName: string)
	if IsHatching then return end
	if EggHatchAnimation.IsPlaying() then return end
	
	IsHatching = true
	
	local hasInstantHatch = MonetizationController and MonetizationController:HasGamePass("InstantHatch")
	
	if hasInstantHatch then
		EggService:RequestPurchaseEgg(eggName):andThen(function(success, errorMsg, petInfo)
			if success and petInfo then
				local data = UIController:GetData()
				if not data.Inventory.PetInventory then
					data.Inventory.PetInventory = {}
				end
				table.insert(data.Inventory.PetInventory, petInfo)
				if InventoryUIController then
					InventoryUIController:UpdatePetsInventory()
				end
			elseif not success and NotificationController then
				NotificationController:ShowNotification(
					errorMsg or "Failed to purchase egg",
					NotificationController.Category.Warning,
					3
				)
			end
			IsHatching = false
		end)
	else
		UIFramesController:DisableFrames(true)
		eggviewport.Parent.Visible = true
		
		EggHatchAnimation.PlayHatch(
			eggviewport,
			eggName,
			eggHatchDimmer,
			eggHatchFlash,
			function(animationSuccess)
				if animationSuccess then
					EggService:RequestPurchaseEgg(eggName):andThen(function(success, errorMsg, petInfo)
						if success and petInfo then
							local data = UIController:GetData()
							if not data.Inventory.PetInventory then
								data.Inventory.PetInventory = {}
							end
							table.insert(data.Inventory.PetInventory, petInfo)
							if InventoryUIController then
								InventoryUIController:UpdatePetsInventory()
							end
						elseif not success and NotificationController then
							NotificationController:ShowNotification(
								errorMsg or "Failed to purchase egg",
								NotificationController.Category.Warning,
								3
							)
						end
					end)
				end
				eggviewport.Parent.Visible = false
				UIFramesController:DisableFrames(false)
				IsHatching = false
			end
		)
	end
end

local function PurchaseMultipleEggs(eggName: string, count: number)
	if IsHatching then return end
	if EggHatchAnimation.IsPlaying() then return end
	
	IsHatching = true
	
	local hasInstantHatch = MonetizationController and MonetizationController:HasGamePass("InstantHatch")
	
	if hasInstantHatch then
		-- No animation, batch purchase all at once from server
		EggService:RequestPurchaseMultipleEggs(eggName, count):andThen(function(purchasedCount, pets)
			if purchasedCount > 0 then
				local data = UIController:GetData()
				if not data.Inventory.PetInventory then
					data.Inventory.PetInventory = {}
				end
				for _, petInfo in ipairs(pets) do
					table.insert(data.Inventory.PetInventory, petInfo)
				end
				if InventoryUIController then
					InventoryUIController:UpdatePetsInventory()
				end
			end
			IsHatching = false
		end)
		return
	end
	
	-- Play animation ONCE, then batch purchase all eggs from server
	UIFramesController:DisableFrames(true)
	eggviewport.Parent.Visible = true
	
	EggHatchAnimation.PlayHatch(
		eggviewport,
		eggName,
		eggHatchDimmer,
		eggHatchFlash,
		function(animationSuccess)
			if animationSuccess then
				EggService:RequestPurchaseMultipleEggs(eggName, count):andThen(function(purchasedCount, pets)
					if purchasedCount > 0 then
						local data = UIController:GetData()
						if not data.Inventory.PetInventory then
							data.Inventory.PetInventory = {}
						end
						for _, petInfo in ipairs(pets) do
							table.insert(data.Inventory.PetInventory, petInfo)
						end
						if InventoryUIController then
							InventoryUIController:UpdatePetsInventory()
						end
					end
				end)
			end
			eggviewport.Parent.Visible = false
			UIFramesController:DisableFrames(false)
			IsHatching = false
		end
	)
end

local function StartAutoHatch(eggName: string)
	if AutoHatchActive[eggName] then
		return
	end
	
	-- Check if player owns AutoHatch gamepass
	local hasAutoHatchPass = MonetizationController and MonetizationController:HasGamePass("AutoHatch")
	if not hasAutoHatchPass then
		-- Prompt purchase
		if MonetizationController then
			MonetizationController:PromptPurchase("AutoHatch")
		end
		return
	end
	
	if not IsPlayerInRange() then
		if NotificationController then
			NotificationController:ShowNotification(
				"Move closer to the egg to auto-hatch!",
				NotificationController.Category.Warning,
				3
			)
		end
		return
	end

	AutoHatchActive[eggName] = true
	
	local hasInstantHatch = MonetizationController and MonetizationController:HasGamePass("InstantHatch")

	task.spawn(function()
		while AutoHatchActive[eggName] do
			if not IsPlayerInRange() then
				AutoHatchActive[eggName] = false
				if NotificationController then
					NotificationController:ShowNotification(
						"Auto-hatch stopped: Too far from egg",
						NotificationController.Category.Warning,
						3
					)
				end
				break
			end
			
			if IsHatching or (not hasInstantHatch and EggHatchAnimation.IsPlaying()) then
				task.wait(AUTO_HATCH_DELAY)
				continue
			end

			IsHatching = true
			local continueAutoHatch = true
			
			if hasInstantHatch then
				EggService:RequestPurchaseEgg(eggName):andThen(function(success, _errorMsg, petInfo)
					if success and petInfo then
						local data = UIController:GetData()
						if not data.Inventory.PetInventory then
							data.Inventory.PetInventory = {}
						end
						table.insert(data.Inventory.PetInventory, petInfo)
						if InventoryUIController then
							InventoryUIController:UpdatePetsInventory()
						end
					else
						continueAutoHatch = false
						AutoHatchActive[eggName] = false
						if NotificationController then
							NotificationController:ShowNotification(
								"Auto-hatch stopped: Not enough currency",
								NotificationController.Category.Warning,
								3
							)
						end
					end
					IsHatching = false
				end)
			else
				UIFramesController:DisableFrames(true)
				eggviewport.Parent.Visible = true
				
				EggHatchAnimation.PlayHatch(
					eggviewport,
					eggName,
					eggHatchDimmer,
					eggHatchFlash,
					function(animationSuccess)
						if animationSuccess then
							EggService:RequestPurchaseEgg(eggName):andThen(function(success, _errorMsg, petInfo)
								if success and petInfo then
									local data = UIController:GetData()
									if not data.Inventory.PetInventory then
										data.Inventory.PetInventory = {}
									end
									table.insert(data.Inventory.PetInventory, petInfo)
									if InventoryUIController then
										InventoryUIController:UpdatePetsInventory()
									end
								else
									continueAutoHatch = false
									AutoHatchActive[eggName] = false
									if NotificationController then
										NotificationController:ShowNotification(
											"Auto-hatch stopped: Not enough currency",
											NotificationController.Category.Warning,
											3
										)
									end
								end
							end)
						else
							continueAutoHatch = false
						end
						eggviewport.Parent.Visible = false
						UIFramesController:DisableFrames(false)
						IsHatching = false
					end
				)
			end
			
			while IsHatching do
				task.wait(0.1)
			end
			
			if not continueAutoHatch then
				break
			end

			task.wait(hasInstantHatch and 0.1 or AUTO_HATCH_DELAY)
		end
	end)
end

local function StopAutoHatch(eggName: string)
	AutoHatchActive[eggName] = false
end

local function ToggleAutoHatch(eggName: string)
	if AutoHatchActive[eggName] then
		StopAutoHatch(eggName)
	else
		StartAutoHatch(eggName)
	end
end

local function SetupUIButtons()
	local uiHatchBoard = PlayerGui:FindFirstChild("UI_HatchBoard")
	if not uiHatchBoard then
		return
	end
	
	local container = uiHatchBoard:FindFirstChild("Container")
	if not container then
		return
	end
	
	local mainBoard = container:FindFirstChild("MainBoard")
	if not mainBoard then
		return
	end
	
	local actionButtons = mainBoard:FindFirstChild("ActionButtons")
	if not actionButtons then
		return
	end
	
	local eggName = "StandardEgg"
	EggConnections[eggName] = EggConnections[eggName] or {}

	for i, _conn in pairs(EggConnections[eggName]) do
		if _conn and _conn.Disconnect then
			_conn:Disconnect()
		end
	end
	
	local btnHatch = actionButtons:FindFirstChild("Btn_Hatch")
	if btnHatch and btnHatch:IsA("TextButton") then
		local conn = btnHatch.MouseButton1Click:Connect(function()
			PurchaseSingleEgg(eggName)
		end)
		table.insert(EggConnections[eggName], conn)
		
		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnHatch)
		end
	end
	
	local btnMulti = actionButtons:FindFirstChild("Btn_Multi")
	if btnMulti and btnMulti:IsA("TextButton") then
		local conn = btnMulti.MouseButton1Click:Connect(function()
			PurchaseMultipleEggs(eggName, MULTI_HATCH_COUNT)
		end)
		table.insert(EggConnections[eggName], conn)
		
		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnMulti)
		end
	end
	
	local btnAuto = actionButtons:FindFirstChild("Btn_Auto")
	if btnAuto and btnAuto:IsA("TextButton") then
		local conn = btnAuto.MouseButton1Click:Connect(function()
			ToggleAutoHatch(eggName)
		end)
		table.insert(EggConnections[eggName], conn)
		
		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnAuto)
		end
	end
	
	SetupPetTemplates(mainBoard, eggName)
end

local function UpdateBillboardAdornees(worldName: string)
	local worldFolder = Workspace:FindFirstChild(worldName)
	if not worldFolder then
		return
	end
	
	local eggShopStands = worldFolder:FindFirstChild("EggShop_Stands")
	if not eggShopStands then
		return
	end
	
	local standardEgg = eggShopStands:FindFirstChild("StandardEgg")
	if not standardEgg then
		return
	end
	
	local eggRoot = standardEgg:FindFirstChild("EggRoot")
	if not eggRoot then
		return
	end
	
	local uiHatchBoard = PlayerGui:FindFirstChild("UI_HatchBoard") :: BillboardGui
	if uiHatchBoard and uiHatchBoard:IsA("BillboardGui") then
		uiHatchBoard.Adornee = eggRoot
		uiHatchBoard.Enabled = true
	end

	SetupUIButtons()
end

function EggController:UpdateEggUI()
	local worldName = GetCurrentWorld()
	UpdateBillboardAdornees(worldName)
end

function EggController:OnWorldChanged(newWorldName: string)
	for eggName, _ in pairs(AutoHatchActive) do
		StopAutoHatch(eggName)
	end

	CurrentWorldName = newWorldName
	UpdateBillboardAdornees(newWorldName)
end

function EggController:KnitInit()
	UIFramesController = Knit.GetController("UIFramesController")
	UIController = Knit.GetController("UIController")
	InventoryUIController = Knit.GetController("InventoryUIController")
	MonetizationController = Knit.GetController("MonetizationController")
	
	eggHatchScreenGui = PlayerGui:WaitForChild("EggHatchScreen")
	eggHatchDimmer = eggHatchScreenGui:WaitForChild("Dimmer")
	eggviewport = eggHatchDimmer:WaitForChild("Viewport")
	eggHatchFlash = eggHatchScreenGui:FindFirstChild("Flash")
	
	SetupUIButtons()
end

function EggController:KnitStart()
	EggService = Knit.GetService("EggService")
	DataService = Knit.GetService("DataService")
	NotificationController = Knit.GetController("NotificationController")

	CurrentWorldName = GetCurrentWorld()
	UpdateBillboardAdornees(CurrentWorldName)

	DataService.DataReady:Connect(function(_newData)
		self:UpdateEggUI()
	end)

	-- Refresh egg percentages when gamepass ownership changes (e.g., Luck/SuperLuck purchased)
	MonetizationController.GamePassChanged:Connect(function(_gamePassName, _owned)
		self:UpdateEggUI()
	end)

	Player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		local newWorld = Player:GetAttribute("CurrentWorld")
		if newWorld and newWorld ~= CurrentWorldName then
			self:OnWorldChanged(newWorld)
		end
	end)

	EggService.PetObtained:Connect(function(petInfo)
		if NotificationController and petInfo then
			NotificationController:ShowNotification(
				string.format("🥚 Hatched: %s!", petInfo.Name or "Unknown Pet"),
				NotificationController.Category.Success,
				3
			)
		end
	end)
	
	-- Listen for hatch animation requests from server (for shop purchases)
	EggService.PlayHatchAnimation:Connect(function(eggName: string, petInfo: any)
		-- Queue the animation
		QueueHatchAnimation(eggName, petInfo)
	end)
	
	-- Listen for bonus updates to refresh egg UI (e.g., LuckParty changes probabilities)
	local ServerBonusService = Knit.GetService("ServerBonusService")
	ServerBonusService.BonusUpdated:Connect(function(_BonusName: string, _value: boolean)
		self:UpdateEggUI()
	end)
end

return EggController
