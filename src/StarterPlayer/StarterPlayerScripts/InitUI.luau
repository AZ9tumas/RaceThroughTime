
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
            PetInventory = {},
            EquippedPets = {},
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

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

-- Debounce state for track requests
local isRequestingTrack = false

-- Arena state - tracks whether player is currently inside the arena
local isInArena = false
local lastArenaCheckTime = 0
local ARENA_CHECK_INTERVAL = 0.1 -- Check arena status every 0.1 seconds for performance

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
    local currentWorld = handler.data.Progression.CurrentWorld or "Main"
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

-- Get the Central Arena part for the current world
local function GetCentralArenaForCurrentWorld(): BasePart?
    local currentWorld = handler.data.Progression.CurrentWorld or "Main"
    local worldFolder = Workspace:FindFirstChild(currentWorld)
    if worldFolder then
        local centralArena = worldFolder:FindFirstChild("1_Central_Arena")
        if centralArena and centralArena:IsA("BasePart") then
            return centralArena
        end
    end
    
    -- Fallback to Main world
    local mainWorld = Workspace:FindFirstChild("Main")
    if mainWorld then
        local centralArena = mainWorld:FindFirstChild("1_Central_Arena")
        if centralArena and centralArena:IsA("BasePart") then
            return centralArena
        end
    end
    
    return nil
end

-- Check if player is inside the arena based on distance from center
-- Uses the arena radius from Stats for the current world
local function CheckPlayerInArena(): boolean
    local character = player.Character
    if not character then return false end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end
    
    local centralArena = GetCentralArenaForCurrentWorld()
    if not centralArena then return false end
    
    local currentWorld = handler.data.Progression.CurrentWorld or "Main"
    local arenaRadius = statsM.ArenaRadius[currentWorld] or statsM.ArenaRadius.Main or 200
    
    -- Calculate horizontal distance (ignoring Y axis) from arena center to player
    local arenaCenter = centralArena.Position
    local playerPos = rootPart.Position
    local horizontalDistance = math.sqrt(
        (playerPos.X - arenaCenter.X)^2 + 
        (playerPos.Z - arenaCenter.Z)^2
    )
    
    return horizontalDistance <= arenaRadius
end

-- Update arena status with throttling for performance
-- Only checks every ARENA_CHECK_INTERVAL seconds
local function UpdateArenaStatus(): boolean
    local currentTime = tick()
    if currentTime - lastArenaCheckTime < ARENA_CHECK_INTERVAL then
        return isInArena -- Return cached value if not enough time has passed
    end
    lastArenaCheckTime = currentTime
    
    local wasInArena = isInArena
    isInArena = CheckPlayerInArena()
    
    -- Log state change for debugging (can be removed later)
    if wasInArena ~= isInArena then
        if isInArena then
            print("[InitUI]: Player entered arena")
        else
            print("[InitUI]: Player left arena")
        end
    end
    
    return isInArena
end

-- Public function to check if player is in arena
function handler.IsPlayerInArena(): boolean
    return isInArena
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

function handler.UpdatePetsInventory()
    -- Clear existing pet frames (except the template)
    for _, child in ipairs(inventoryScrollingFrame:GetChildren()) do
        if child:IsA("Frame") and child.Name ~= "Template" then
            child:Destroy()
        end
    end
    
    -- Get the pet inventory from handler data
    local petInventory = handler.data.Inventory.PetInventory or {}
    
    -- Update pet count display
    inventoryPetCount.Count.Text = #petInventory .. "/3"
    
    -- Create a frame for each pet
    for index, petData in ipairs(petInventory) do
        local petFrame = inventoryPetTemplate:Clone()
        petFrame.Name = "Pet_" .. index
        petFrame.Visible = true
        
        local nameLabel = petFrame:FindFirstChild("PetName")
        nameLabel.Text = petData.Name or "Unknown Pet"
        
        -- Set the multiplier text (TextLabel under Multiplier frame)
        local multiplierFrame = petFrame:FindFirstChild("Multiplier")
        if multiplierFrame then
            local multiplierLabel = multiplierFrame:FindFirstChild("TextLabel")
            if multiplierLabel then
                multiplierLabel.Text = string.format("x%.1f", petData.Multiplier or 1.0)
            end
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

-- daily frame
handler._connections["DailyButton"] = dailyButton.MouseButton1Click:Connect(function()
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
        print(success, gateName)
    
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
    shopMain.Visible = not shopMain.Visible
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
    inventoryMainFrame.Visible = not inventoryMainFrame.Visible
    if inventoryMainFrame.Visible then
        handler.UpdatePetsInventory()
    end
end)

handler._connections["InventoryClose"] = inventoryCloseButton.MouseButton1Click:Connect(function()
    inventoryMainFrame.Visible = false
end)

-- Listen for DataReady signal from server to update UI
handler._connections["DataReady"] = DataService.DataReady:Connect(function(data)
    -- Call UpdateDataOnClient when data is ready
    handler.UpdateDataOnClient(data)
end)

handler._connections["RenderStepped"] = RunService.RenderStepped:Connect(function()
    worldlabel.Text = "🌍 " .. (handler.data.Progression.CurrentWorld or "Main")
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    UpdateRunButtonVisibility()
    UpdateArenaStatus()
end)

return handler