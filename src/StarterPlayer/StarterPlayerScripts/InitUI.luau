
local handler = {
    _connections = {},
    data = {
        Currencies = {
            Cash = 0,
            Gems = 0,
        },
        Stats = {
            TotalDistance = 0,
            Points = 0,
            Rebirths = 0,
            Fuel = 100, -- Starting fuel for players
        },
        Progression = {
            CurrentWorld = "Main",
            UnlockedWorlds = { "Main" },
        },
        Inventory = {
            -- PetInventory stores full pet data:
            -- { Name: string, PetType: string, Multiplier: number, FuelBonus: number, 
            --   PickupRangeBonus: number, World: string, Level: number, Rarity: string }
            PetInventory = {},
            EquippedPets = {}, -- Indices of equipped pets (max 3)
            Potions = {},
        },
        Meta = {
            DailyStreak = 0,
            LastClaim = 0,
            CollectedRewards = {}, -- Tracks which daily reward IDs have been collected
            UpdateVersion = 0,
            Settings = {
                Music = true,
                SFX = true,
            },
        },
    }
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Knit for service communication
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local EggService = Knit.GetService("EggService")
local DailyRewardService = Knit.GetService("DailyRewardService")
local DataService = Knit.GetService("DataService")
local PetService = Knit.GetService("PetService")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))
local rebirthStatsM = require(modules:WaitForChild("RebirthStats"))

-- Debounce state for track requests
local isRequestingTrack = false

-- Gate settings from Stats
local GATE_PROXIMITY_DISTANCE = statsM.GateProximityDistance
local MAX_GATE_INDEX = statsM.MaxGateIndex

-- ui
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local uiShop: ScreenGui = PlayerGui:WaitForChild("UI_Shop")
local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
local cashDisplay: TextLabel = leftPanel:WaitForChild("CashDisplay")
local GemsDisplay: TextLabel = leftPanel:WaitForChild("GemsDisplay")
local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
local runButton: TextButton = centerHUD:WaitForChild("RunButton")
local fuelBar = centerHUD:WaitForChild("FuelBar")
local multiplierLabel: TextLabel = fuelBar:WaitForChild("SpeedStat")
local fuelText: TextLabel = fuelBar:WaitForChild("FuelText")
local otherFrames: Frame = mainUi:WaitForChild("OtherFrames")
local worldlabel: TextLabel = mainUi:WaitForChild("TopInfo"):WaitForChild("WorldName")

-- sub frames
local dailyButton: TextButton = leftPanel:WaitForChild("DailyButton")
local dailyFrame: Frame = otherFrames:WaitForChild("DailyFrame")
local shopButton: TextButton = leftPanel:WaitForChild("ShopButton")

-- Shop Internal UI
local shopMain = uiShop:WaitForChild("MainFrame")
local shopTop = shopMain:WaitForChild("Top")
local shopCashCount = shopTop:WaitForChild("Cash"):WaitForChild("Count")
local shopGemsCount = shopTop:WaitForChild("Gems"):WaitForChild("Count")

local shopEggsContainer = shopMain:WaitForChild("ScrollingFrame"):WaitForChild("Eggs"):WaitForChild("MainFrame")
local standardEggBuy = shopEggsContainer:WaitForChild("StandardEgg"):WaitForChild("Buy")

-- pets and inv
local petsButton: TextButton = leftPanel:WaitForChild("PetsButton")
local uiInventory: ScreenGui = PlayerGui:WaitForChild("UI_Inventory")
local inventoryMainFrame: Frame = uiInventory:WaitForChild("MainFrame")
local inventoryPetCount: TextLabel = inventoryMainFrame:WaitForChild("PetCount")
local inventoryScrollingFrame: ScrollingFrame = inventoryMainFrame:WaitForChild("ScrollingFrame")
local inventoryPetTemplate: Frame = inventoryScrollingFrame:WaitForChild("UIGridLayout"):WaitForChild("Template")
local inventoryCloseButton: TextButton = inventoryMainFrame:WaitForChild("CloseButton")

-- Pet modal UI (for equipping/unequipping pets)
local uiPetModal: ScreenGui = PlayerGui:WaitForChild("UI_PetModal")
local petModalDarkOverlay: Frame = uiPetModal:WaitForChild("DarkOverlay")
local petModalMainFrame: Frame = petModalDarkOverlay:WaitForChild("MainFrame")
local petModalCloseButton: TextButton = petModalMainFrame:WaitForChild("CloseButton")
local petModalEquipButton: TextButton = petModalMainFrame:WaitForChild("EquipButton")
local petModalEquipEmoji: TextLabel = petModalEquipButton:WaitForChild("Emoji")
local petModalEquipLabel: TextLabel = petModalEquipButton:WaitForChild("TextLabel")
local petModalMergeButton: TextButton = petModalMainFrame:WaitForChild("MergeButton")
local petModalMultiplier: TextLabel = petModalMainFrame:WaitForChild("Multiplier")

-- rebirth ui
local rebirthStatsM = require(ReplicatedStorage.Modules.RebirthStats)
local rebirthModalButton: TextButton = leftPanel:WaitForChild("RebirthButton")
local buttonPressed: boolean = false
local rebirthMenu: Frame = PlayerGui:WaitForChild("SimulatorPopups"):WaitForChild("RebirthMenu")
local rebirthCloseButton: TextLabel = rebirthMenu:WaitForChild("Close")
local progressBar: Frame = rebirthMenu:WaitForChild("Progress"):WaitForChild("Fill")
local progressText: TextLabel = rebirthMenu:WaitForChild("Progress"):WaitForChild("TextLabel")
local rebirthButton: TextButton = rebirthMenu:WaitForChild("Rebirth")
local rebirthMainLabel: TextLabel = rebirthMenu:WaitForChild("TextLabel")

-- world service ui
local worldMenu: Frame = PlayerGui:WaitForChild("SimulatorPopups"):WaitForChild("WorldMenu")
local worldClose: TextButton = worldMenu:WaitForChild("Close")
local worldScrollFrame: ScrollingFrame = worldMenu:WaitForChild("ScrollingFrame")
local worldButtonTemplate: TextButton = worldScrollFrame:WaitForChild("UIListLayout"):WaitForChild("Template")

-- Currently selected pet data for the modal
local selectedPetData = nil

-- vals
local leaderstats = player:WaitForChild("leaderstats")
local gemsVal = leaderstats:WaitForChild("Gems")
local cashVal = leaderstats:WaitForChild("Cash")
local statsfolder = player:WaitForChild("Stats")
local fuelVal = statsfolder:WaitForChild("Fuel")

local dailyFrameMain = dailyFrame:WaitForChild("Main")
local dailyFrameCloseButton = dailyFrame:WaitForChild("Close")
local cardHolderFrame = dailyFrameMain:WaitForChild("CardHolder")
local cardHolders = {
    DayOne = {
        Day = 1,
        Frame = cardHolderFrame:WaitForChild("1"),
        RedeemButton = cardHolderFrame:WaitForChild("1"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("1"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("1"):WaitForChild("Amount"),
    },
    DayTwo = {
        Day = 2,
        Frame = cardHolderFrame:WaitForChild("2"),
        RedeemButton = cardHolderFrame:WaitForChild("2"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("2"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("2"):WaitForChild("Amount"),
    },
    DayThree = {
        Day = 3,
        Frame = cardHolderFrame:WaitForChild("3"),
        RedeemButton = cardHolderFrame:WaitForChild("3"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("3"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("3"):WaitForChild("Amount"),
    },
    DayFour = {
        Day = 4,
        Frame = cardHolderFrame:WaitForChild("4"),
        RedeemButton = cardHolderFrame:WaitForChild("4"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("4"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("4"):WaitForChild("Amount"),
    },
    DayFive = {
        Day = 5,
        Frame = cardHolderFrame:WaitForChild("5"),
        RedeemButton = cardHolderFrame:WaitForChild("5"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("5"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("5"):WaitForChild("Amount"),
    },
}

-- Get TrackGates for the player's current world
local function GetTrackGatesForCurrentWorld(): Folder?
    local currentWorld = handler.data.Progression.CurrentWorld
    local worldFolder = Workspace:FindFirstChild(currentWorld)
    if worldFolder then
        local trackSystem = worldFolder:FindFirstChild("Track_System")
        if trackSystem then
            return trackSystem:FindFirstChild("Track_Gates")
        end
    end
    
    -- Fallback to Main world
    local mainWorld = Workspace:FindFirstChild("Main")
    if mainWorld then
        local trackSystem = mainWorld:FindFirstChild("Track_System")
        if trackSystem then
            return trackSystem:FindFirstChild("Track_Gates")
        end
    end
    
    return nil
end

-- Helper function to close all frames (shop, daily rewards, inventory, pet modal)
-- Used to avoid cluttering of frames when opening a new one
local function CloseAllFrames(exceptFrame: Frame?)
    local old = exceptFrame and exceptFrame.Visible
    dailyFrame.Visible = false
    shopMain.Visible = false
    inventoryMainFrame.Visible = false
    petModalDarkOverlay.Visible = false
    rebirthMenu.Visible = false

    if exceptFrame then exceptFrame.Visible = old end
end

-- Helper function to truncate large numbers
local function truncateNumber(n: number)
    -- add support till trillion
    if n >= 1e12 then
        return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then
        return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.2fK", n / 1e3)
    end

    return tostring(n)
end

-- Check if player is near any gate
local function IsPlayerNearGate(): boolean
    local character = player.Character
    if not character then return false end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end
    
    local playerPosition = rootPart.Position
    
    -- Get track gates for current world
    local trackGates = GetTrackGatesForCurrentWorld()
    if not trackGates then return false end
    
    -- Check distance to each gate
    for i = 0, MAX_GATE_INDEX do
        local gateName = "Gate_" .. i
        local gate = trackGates:FindFirstChild(gateName)
        if gate then
            local gatePosition: Vector3
            if gate:IsA("BasePart") then
                gatePosition = gate.Position
            elseif gate:IsA("Model") then
                local primaryPart = gate.PrimaryPart or gate:FindFirstChildWhichIsA("BasePart")
                if primaryPart then
                    gatePosition = primaryPart.Position
                end
            end
            
            if gatePosition then
                local distance = (playerPosition - gatePosition).Magnitude
                if distance <= GATE_PROXIMITY_DISTANCE then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Check if player is near WorldSelectPad
local function IsPlayerNearWorldPad(): boolean
    local character = player.Character
    if not character then return false end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end
    
    local playerPosition = rootPart.Position
    
    -- Get current world folder
    local currentWorld = player:GetAttribute("CurrentWorld")
    local worldFolder = Workspace:FindFirstChild(currentWorld)

    if not worldFolder then return warn(currentWorld .. " world folder not found"), false end
    local pad = worldFolder:FindFirstChild("WorldSelectPad")
    
    if pad and pad:IsA("BasePart") then
        local distance = (playerPosition - pad.Position).Magnitude
        if distance <= GATE_PROXIMITY_DISTANCE then
            return true
        end
    end
    
    return false
end

local function isPlayerNearRebirthArea(): boolean
    local character = player.Character
    if not character then return false end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end
    
    local playerPosition = rootPart.Position
    
    -- Get current world folder
    local currentWorld = player:GetAttribute("CurrentWorld")
    local worldFolder = Workspace:FindFirstChild(currentWorld)

    if not worldFolder then return warn(currentWorld .. " world folder not found"), false end
    local pad = worldFolder:FindFirstChild("Rebirth_Altar")

    if pad and pad:IsA("BasePart") then
        local distance = (playerPosition - pad.Position).Magnitude
        if distance <= GATE_PROXIMITY_DISTANCE then
            return true
        end
    end
    
    return false
end

-- Update the pet modal equip button appearance based on equipped state
local function UpdatePetModalEquipButton(isEquipped: boolean)
    if isEquipped then
        petModalEquipEmoji.Text = "❌"
        petModalEquipLabel.Text = "Unequip"
        petModalEquipButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80) -- Red color for unequip
    else
        petModalEquipEmoji.Text = "✅"
        petModalEquipLabel.Text = "Equip"
        petModalEquipButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80) -- Green color for equip
    end
end

-- Open the pet modal with the selected pet data
local function OpenPetModal(petData)
    selectedPetData = petData
    
    -- Update modal content
    petModalMultiplier.Text = string.format("x%.1f Multiplier", petData.Multiplier or 1.0)
    
    -- Update equip button state
    UpdatePetModalEquipButton(petData.Equipped or false)

    -- Show the modal
    petModalDarkOverlay.Visible = true
end

local function clearWorlds()
    for _, v in pairs(worldScrollFrame:GetChildren()) do
        if v:IsA("TextButton") then
            v:Destroy()
        end
    end
end

function handler.UpdateWorlds()
    local worlds = handler.data.Progression.UnlockedWorlds
    local currworld = handler.data.Progression.CurrentWorld
    clearWorlds()

    for _, world in pairs(worlds) do
        print(world)
        local temp = worldButtonTemplate:Clone()
        temp.Parent = worldScrollFrame
        temp.Name = world
        temp.TextLabel.Text = world
        temp.Visible = true
        temp.UIStroke.Enabled = world == currworld

        temp.MouseButton1Click:Connect(function()
            print("Teleporting to world: " .. world)
            local worldService = Knit.GetService("WorldService")

            worldService:RequestTeleportToWorld(world):andThen(function(success, errorMsg, updatedData)
                if success then
                    print("Teleported to world: " .. world)
                    handler.UpdateDataOnClient(updatedData)

                    local notificationController = Knit.GetController("NotificationController")
                    notificationController:ShowNotification(
                        errorMsg,
                        notificationController.Category.Success,
                        5
                    )
                else
                    print("Failed to teleport to world: " .. (errorMsg or "Unknown error"))
                end
            end)
        end)
    end
end

function handler.UpdatePetsInventory()
    -- Clear existing pet frames (except the template)
    for _, child in ipairs(inventoryScrollingFrame:GetChildren()) do
        if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and (child:IsA("Frame") or child:IsA("TextButton")) then
            child:Destroy()
        end
    end
    
    -- Get the pet inventory from handler data
    local petInventory = handler.data.Inventory.PetInventory
    local equippedPets = handler.data.Inventory.EquippedPets
    
    -- Create a set of equipped pet indices for quick lookup
    local equippedSet = {}
    for _, petIndex in ipairs(equippedPets) do
        equippedSet[petIndex] = true
    end
    
    -- Update pet count display
    inventoryPetCount.Count.Text = #petInventory .. "/3"
    
    -- Create a frame for each pet
    for index, petData in ipairs(petInventory) do
        local petFrame = inventoryPetTemplate:Clone()
        petFrame.Name = "Pet_" .. index
        petFrame.Visible = true
        
        local nameLabel = petFrame:FindFirstChild("PetName")
        if nameLabel then
            nameLabel.Text = petData.Name or "Unknown Pet"
        end
        
        -- Set the multiplier text (TextLabel under Multiplier frame)
        local multiplierFrame = petFrame:FindFirstChild("Multiplier")
        if multiplierFrame then
            local multiplierLabel = multiplierFrame:FindFirstChild("TextLabel")
            if multiplierLabel then
                multiplierLabel.Text = string.format("x%.1f", petData.Multiplier or 1.0)
            end
        end

        print(petData)
        
        -- Store pet data and index for later use
        local isEquipped = equippedSet[index] == true

        if isEquipped then
            petFrame.UIStroke.Color = Color3.fromRGB(85, 255, 0)
        else
            petFrame.UIStroke.Color = Color3.fromRGB(49, 49, 49)
        end

        local fullPetData = {
            ID = petData.ID,
            Name = petData.Name,
            Multiplier = petData.Multiplier,
            FuelBonus = petData.FuelBonus,
            PickupRangeBonus = petData.PickupRangeBonus,
            RoamRange = petData.RoamRange,
            StarCollectionRadius = petData.StarCollectionRadius,
            Velocity = petData.Velocity,
            World = petData.World,
            Level = petData.Level,
            TierLevel = petData.TierLevel,
            TierName = petData.TierName,
            Rarity = petData.Rarity,
            Equipped = isEquipped,
            Index = index,
        }
        
        -- Connect click event to open pet modal (template should be a TextButton)
        if petFrame:IsA("TextButton") then
            petFrame.MouseButton1Click:Connect(function()
                CloseAllFrames()
                print("Full pet data: ", fullPetData)
                OpenPetModal(fullPetData)
            end)
        end
        
        petFrame.Parent = inventoryScrollingFrame
    end
end

function handler.UpdateFuelUI(amount: number)
    -- Update fuel text
    fuelText.Text = "⭐ FUEL: " .. math.floor(amount)
end

function handler.UpdateCashUI(amount: number)
    cashDisplay.Text = "💵 " .. truncateNumber(amount)
    shopCashCount.Text = truncateNumber(amount)
end

function handler.UpdateGemsUI(amount: number)
    GemsDisplay.Text = "💎 " .. truncateNumber(amount)
    shopGemsCount.Text = truncateNumber(amount)
end

function handler.UpdateShopUI()
    -- Shop UI updates can be extended here for other items
    -- Eggs are no longer tracked as they immediately hatch to pets
end


-- Function to update UI with loaded data from server
-- Called after data has been loaded on the server
function handler.UpdateDataOnClient(newData)
    -- Update handler.Data with new data
    if newData then
        handler.data = newData
    end

    -- Initial UI updates from leaderstats (already replicated)
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    handler.UpdateRewardsStatus()
    handler.UpdateShopUI()
    handler.UpdateWorlds()

    print("UPDATED DATA ON CLIENT:", handler.data)
end

function handler.UpdateRewardsStatus()
    -- Get DailyRewardService to check collected rewards
    local collectedRewards = handler.data.Meta.CollectedRewards or {}
    local DailyRewardsConfig = require(modules:WaitForChild("DailyRewards"))
    
    -- Update each card's status based on collected rewards
    for _, cardData in pairs(cardHolders) do
        local rewardID = DailyRewardsConfig.GetRewardIDForDay(cardData.Day)
        if rewardID and collectedRewards[rewardID] then
            cardData.RedeemButton.Parent.PriceLabel.Text = "REDEEMED"
        end
    end
end

-- Function to reset debounce when track ends (called externally)
function handler.ResetTrackDebounce()
    isRequestingTrack = false
end

-- Update run button visibility based on gate proximity
local function UpdateRunButtonVisibility()
    -- Don't show if player is on track or requesting track
    local TrackController = Knit.GetController("TrackController")
    if TrackController and TrackController:IsOnTrack() then
        runButton.Visible = false
        return
    end
    
    if isRequestingTrack then
        runButton.Visible = false
        return
    end
    
    -- Show only if near a gate
    runButton.Visible = IsPlayerNearGate()
end

-- Update world menu visibility based on world pad proximity
local function UpdateWorldMenuVisibility()
    worldMenu.Visible = IsPlayerNearWorldPad()
end

local function UpdateRebirthMenuVisibility()
    rebirthMenu.Visible = buttonPressed or isPlayerNearRebirthArea()
end

-- daily frame
handler._connections["DailyButton"] = dailyButton.MouseButton1Click:Connect(function()
    CloseAllFrames(dailyFrame)
    dailyFrame.Visible = not dailyFrame.Visible
end)

for _, cardData in pairs(cardHolders) do
    handler._connections["Day" .. cardData.Frame.Name] = cardData.RedeemButton.MouseButton1Click:Connect(function()
        -- Send claim request to server with the specific day number
        local success, _ = DailyRewardService:RequestCollectReward(cardData.Day)
        
        handler.UpdateRewardsStatus()
        
        -- Close the daily frame after clicking
        dailyFrame.Visible = false
    end)
end

-- ui init
handler._connections["RunButton"] = runButton.MouseButton1Click:Connect(function()
    -- Debounce: prevent spam requests while one is already in progress
    if isRequestingTrack then
        return
    end
    
    -- Check if player is already on track (via TrackController)
    local TrackController = Knit.GetController("TrackController")
    if TrackController and TrackController:IsOnTrack() then
        return
    end
    
    -- Set debounce flag
    isRequestingTrack = true
    
    -- Get the TrackService and send request to start running on track
    local TrackService = Knit.GetService("TrackService")
    
    -- Fade in the loading screen before making the request
    local LoadingScreenController = Knit.GetController("LoadingScreenController")
    if LoadingScreenController then
        LoadingScreenController:ShowLoadingScreen()
    end

    local NotificationController = Knit.GetController("NotificationController")

    
    TrackService:RequestTrackStart():andThen(function(success: boolean, gateName: string?)
        if success then
            runButton.Visible = false
        else
            print(string.format("[InitUI]: Track start failed - %s", gateName or "Unknown error"))

            NotificationController:ShowNotification(
                "Failed to start track: " .. (gateName or "Unknown error"),
                NotificationController.Category.Error,
                5
            )
            
            -- Fade out loading screen on failure
            if LoadingScreenController then
                LoadingScreenController:HideLoadingScreen()
            end
            -- Reset debounce on failure so player can try again
            isRequestingTrack = false
        end
    end)
end)

handler._connections["DailyFrameClose"] = dailyFrameCloseButton.MouseButton1Click:Connect(function()
    dailyFrame.Visible = false
end)

handler._connections["ShopButton"] = shopButton.MouseButton1Click:Connect(function()
    local wasVisible = shopMain.Visible
    CloseAllFrames()
    shopMain.Visible = not wasVisible
end)

handler._connections["StandardEggBuy"] = standardEggBuy.MouseButton1Click:Connect(function()
    -- Purchase egg and immediately receive pet
    EggService:RequestPurchaseEgg("StandardEgg"):andThen(function(success, errorMsg, petInfo)
        if success and petInfo then
            print("Obtained pet from StandardEgg:", petInfo.Name, "ID:", petInfo.ID)
            
            -- Update local pet inventory
            if not handler.data.Inventory.PetInventory then
                handler.data.Inventory.PetInventory = {}
            end
            
            table.insert(handler.data.Inventory.PetInventory, {
                ID = petInfo.ID,
                Name = petInfo.Name,
                Multiplier = petInfo.Multiplier,
            })
            
            -- Update the pets inventory UI if it's visible
            handler.UpdatePetsInventory()
        else
            print("Failed to purchase StandardEgg:", errorMsg or "Unknown error")
        end
    end)
end)

handler._connections["ShopClose"] = shopMain:WaitForChild("Close").MouseButton1Click:Connect(function()
    shopMain.Visible = false
end)

-- Pets inventory UI
handler._connections["PetsButton"] = petsButton.MouseButton1Click:Connect(function()
    CloseAllFrames(inventoryMainFrame)
    inventoryMainFrame.Visible = not inventoryMainFrame.Visible

    if inventoryMainFrame.Visible then
        handler.UpdatePetsInventory()
    end
end)

handler._connections["InventoryClose"] = inventoryCloseButton.MouseButton1Click:Connect(function()
    inventoryMainFrame.Visible = false
end)

-- Pet Modal UI handlers
handler._connections["PetModalClose"] = petModalCloseButton.MouseButton1Click:Connect(function()
    petModalDarkOverlay.Visible = false
    selectedPetData = nil
    inventoryMainFrame.Visible = true
end)

handler._connections["PetModalEquip"] = petModalEquipButton.MouseButton1Click:Connect(function()
    if not selectedPetData then
        return
    end
    
    local NotificationController = Knit.GetController("NotificationController")
    print(selectedPetData)
    
    if selectedPetData.Equipped then
        -- Unequip the pet
        PetService:RequestUnequipPet(selectedPetData.ID):andThen(function(success, errorMsg)
            if success then
                selectedPetData.Equipped = false
                UpdatePetModalEquipButton(false)
                
                -- Update local data
                local equippedPets = handler.data.Inventory.EquippedPets or {}
                for i, petIndex in ipairs(equippedPets) do
                    if petIndex == selectedPetData.Index then
                        table.remove(handler.data.Inventory.EquippedPets, i)
                        break
                    end
                end
                
                -- Refresh pet inventory
                handler.UpdatePetsInventory()
            else
                NotificationController:ShowNotification(
                    "Failed to unequip pet: " .. (errorMsg or "Unknown error"),
                    NotificationController.Category.Error,
                    3
                )
            end
        end)
    else
        -- Equip the pet
        PetService:RequestEquipPet(selectedPetData.ID):andThen(function(success, errorMsg)
            if success then
                selectedPetData.Equipped = true
                UpdatePetModalEquipButton(true)
                
                -- Update local data
                if not handler.data.Inventory.EquippedPets then
                    handler.data.Inventory.EquippedPets = {}
                end
                table.insert(handler.data.Inventory.EquippedPets, selectedPetData.Index)
                
                -- Refresh pet inventory
                handler.UpdatePetsInventory()
            else
                NotificationController:ShowNotification(
                    "Failed to equip pet: " .. (errorMsg or "Unknown error"),
                    NotificationController.Category.Error,
                    3
                )
            end
        end)
    end
end)

-- rebirth events
local function handleRebirthFrame()
    local cash = truncateNumber(cashVal.Value)

    local currentRebirthLevel = handler.data.Stats.Rebirths
    local nextLevel: rebirthStatsM.RebirthLevel = rebirthStatsM.GetNextRebirth(currentRebirthLevel)

    local frames : {string: Frame} = {
        access = rebirthMenu.Frame.Access,
        bonus = rebirthMenu.Frame.Bonus,
        multiplier = rebirthMenu.Frame.Multiplier,
        status = rebirthMenu.Frame.Status,
    }

    local vals = {
        access = nextLevel.Bonus.WorldAccess or " --- ",
        bonus = "+" .. nextLevel.Bonus.Gems .. " Gems",
        multiplier = "+" .. (nextLevel.CashMultiplierBonus * 100) .. "% Cash",
        status = nextLevel.KeepPets and "Keep Pets" or "Lose Pets",
    }

    if nextLevel then
        local progress, remainingCash = rebirthStatsM.GetRebirthProgress(currentRebirthLevel, cashVal.Value)
        progressBar.Size = UDim2.new(progress, 0, 1, 0)
        progressText.Text = cash .. "/" .. truncateNumber(nextLevel.CashRequired) .. " Cash"
        rebirthMainLabel.Text = "Rebirth to Level " .. tostring(nextLevel.Level)

        for key, v in pairs(frames) do
            v.Label.Text = vals[key]
        end
    else
        progressBar.Size = UDim2.new(1, 0, 1, 0)
        progressText.Text = "MAX LEVEL REACHED"
        rebirthMainLabel.Text = "MAX LEVEL REACHED"

        for _, v in pairs(frames) do
            v.Label.Text = " --- "
        end
    end
end

handler._connections["RebirthButton"] = rebirthButton.MouseButton1Click:Connect(function()
    -- Request rebirth from server
    rebirthMenu.Visible = false

    local RebirthService = Knit.GetService("RebirthService")
    RebirthService:RequestRebirth():andThen(function(success, errorMsg, resultData)
        --[=[
            resultData = {
                NewRebirthLevel = newLevel,
                CashMultiplier = newCashMultiplier,
                SpeedMultiplier = newSpeedMultiplier,
                CashMultiplierBonus = nextRebirth.CashMultiplierBonus,
                SpeedBoostBonus = nextRebirth.SpeedBoostMultiplier,
                PetReward = petInfo,
                FuelReset = true,
            }
        ]=]

        if success then
            print("Rebirth successful!")
        else
            print("Rebirth failed:", errorMsg or "Unknown error")
        end
    end)
end)

handler._connections["RebirthModalButton"] = rebirthModalButton.MouseButton1Click:Connect(function()
    CloseAllFrames(rebirthMenu)
    buttonPressed = not buttonPressed
    rebirthMenu.Visible = buttonPressed

    if rebirthMenu.Visible then
        handleRebirthFrame()
    end
end)

handler._connections["RebirthClose"] = rebirthCloseButton.MouseButton1Click:Connect(function()
    rebirthMenu.Visible = false
end)

-- worlds
handler._connections["WorldClose"] = worldClose.MouseButton1Click:Connect(function()
    worldMenu.Visible = false
end)

-- Listen for DataReady signal from server to update UI
handler._connections["DataReady"] = DataService.DataReady:Connect(function(data)
    -- Call UpdateDataOnClient when data is ready
    handler.UpdateDataOnClient(data)
end)

handler._connections["RenderStepped"] = RunService.RenderStepped:Connect(function()
    worldlabel.Text = "🌍 " .. (handler.data.Progression.CurrentWorld)
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    
    -- Calculate Rebirth Multiplier
    local currentRebirthLevel = handler.data.Stats.Rebirths or 0
    local rebirthMultiplier = rebirthStatsM.CalculateTotalCashMultiplier(currentRebirthLevel)
    
    -- Calculate Pet Multiplier
    local equippedPetsList = {}
    if handler.data.Inventory and handler.data.Inventory.EquippedPets and handler.data.Inventory.PetInventory then
        for _, petIndex in ipairs(handler.data.Inventory.EquippedPets) do
            local pet = handler.data.Inventory.PetInventory[petIndex]
            if pet then
                table.insert(equippedPetsList, pet)
            end
        end
    end
    
    local petMultiplier = statsM.CalculateFuelMultiplier(equippedPetsList)
    
    -- VIP and Dev Products (Placeholders - assume 1.0 if not implemented yet)
    local vipMultiplier = 1.0 
    local devProductMultiplier = 1.0
    local totalMultiplier = rebirthMultiplier * petMultiplier * vipMultiplier * devProductMultiplier
    
    local formattedMultiplier = string.format("%.1f", totalMultiplier)
    if formattedMultiplier:sub(-2) == ".0" then
        formattedMultiplier = formattedMultiplier:sub(1, -3)
    end
    
    multiplierLabel.Text = "⚡ x" .. formattedMultiplier

    UpdateRebirthMenuVisibility()
    UpdateWorldMenuVisibility()
    UpdateRunButtonVisibility()
end)

return handler