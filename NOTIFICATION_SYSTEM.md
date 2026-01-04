# Notification System

A robust notification system for Race Through Time that allows displaying notifications to players from both server and client contexts.

## Architecture

The notification system consists of two main components:

1. **NotificationService** (Server) - Handles sending notifications from the server to clients
2. **NotificationController** (Client) - Handles displaying notifications on the client UI

## Features

- ✅ Send notifications from server to specific players
- ✅ Send notifications to all players
- ✅ Send notifications to multiple players
- ✅ Create client-side only notifications
- ✅ Multiple notification types (Info, Success, Warning, Error)
- ✅ Smooth animations (slide-in/slide-out)
- ✅ Automatic queuing when too many notifications are shown
- ✅ Color-coded by notification type
- ✅ Configurable duration per notification
- ✅ Convenience methods for common notification types

## Setup

### NotificationTemplate UI

The notification system requires a UI template located at:
```
ReplicatedStorage.Assets.NotificationTemplate
```

**⚠️ IMPORTANT: UI Template Setup Required**

The NotificationTemplate must exist in the game file at the location above. If it doesn't exist yet, you need to create it:

#### Creating the NotificationTemplate

1. In Roblox Studio, navigate to ReplicatedStorage
2. Create a folder named "Assets" if it doesn't exist
3. Inside Assets, create a Frame named "NotificationTemplate"
4. Add the following children to the NotificationTemplate Frame:

**Recommended structure:**
```
NotificationTemplate (Frame)
├── UICorner (optional, for rounded corners)
├── TypeIndicator (Frame) - Colored bar/indicator
│   └── UICorner (optional)
├── Title (TextLabel) - Displays notification title
│   ├── UITextSizeConstraint (optional)
│   └── UIPadding (optional)
└── Message (TextLabel) - Displays notification message
    ├── UITextSizeConstraint (optional)
    └── UIPadding (optional)
```

#### Example Template Properties

**NotificationTemplate (Frame):**
- Size: `UDim2.new(1, 0, 0, 80)` or `UDim2.new(0, 280, 0, 80)`
- BackgroundColor3: `Color3.fromRGB(40, 40, 40)` (dark gray)
- BorderSizePixel: 0

**TypeIndicator (Frame):**
- Size: `UDim2.new(0, 4, 1, 0)` (vertical bar on left side)
- Position: `UDim2.new(0, 0, 0, 0)`
- BackgroundColor3: Will be set automatically based on notification type

**Title (TextLabel):**
- Size: `UDim2.new(1, -15, 0, 25)`
- Position: `UDim2.new(0, 15, 0, 10)`
- TextSize: 18
- TextColor3: `Color3.fromRGB(255, 255, 255)`
- Font: Enum.Font.GothamBold
- TextXAlignment: Enum.TextXAlignment.Left
- TextYAlignment: Enum.TextYAlignment.Top

**Message (TextLabel):**
- Size: `UDim2.new(1, -15, 0, 35)`
- Position: `UDim2.new(0, 15, 0, 40)`
- TextSize: 14
- TextColor3: `Color3.fromRGB(200, 200, 200)`
- Font: Enum.Font.Gotham
- TextXAlignment: Enum.TextXAlignment.Left
- TextYAlignment: Enum.TextYAlignment.Top
- TextWrapped: true

The template should be designed but kept invisible (Visible = false), as the controller will clone and show it when needed.

## Usage Examples

### Server-Side (NotificationService)

#### Send notification to a single player

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local NotificationService = Knit.GetService("NotificationService")

-- Basic notification
NotificationService:Notify(player, "Welcome!", "Thanks for joining the game!")

-- With custom duration and type
NotificationService:Notify(
    player,
    "Achievement Unlocked!",
    "You've completed your first race!",
    5, -- Duration in seconds
    "Success" -- Type: "Info", "Success", "Warning", "Error"
)
```

#### Send notification to all players

```lua
local NotificationService = Knit.GetService("NotificationService")

NotificationService:NotifyAll(
    "Server Announcement",
    "Double XP event starting now!",
    10,
    "Info"
)
```

#### Send notification to multiple specific players

```lua
local NotificationService = Knit.GetService("NotificationService")

local topPlayers = {player1, player2, player3}
NotificationService:NotifyMultiple(
    topPlayers,
    "Top 3!",
    "You're in the top 3 players!",
    7,
    "Success"
)
```

#### Example: Reward notification when player collects fuel

```lua
-- In StarService or similar
local NotificationService = Knit.GetService("NotificationService")

function OnFuelCollected(player, fuelAmount)
    NotificationService:Notify(
        player,
        "Fuel Collected!",
        string.format("+%d Fuel", fuelAmount),
        2,
        "Success"
    )
end
```

### Client-Side (NotificationController)

#### Show a local notification (client-only)

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local NotificationController = Knit.GetController("NotificationController")

-- Basic notification
NotificationController:Show(
    "Setting Saved",
    "Your preferences have been updated",
    3,
    "Info"
)
```

#### Using convenience methods

```lua
local NotificationController = Knit.GetController("NotificationController")

-- Info notification (blue)
NotificationController:ShowInfo("Tip", "Press Space to jump!")

-- Success notification (green)
NotificationController:ShowSuccess("Level Up!", "You reached level 10!")

-- Warning notification (yellow)
NotificationController:ShowWarning("Low Fuel", "Your fuel is running low!")

-- Error notification (red)
NotificationController:ShowError("Connection Lost", "Failed to connect to server")
```

#### Example: Show notification on button click

```lua
local NotificationController = Knit.GetController("NotificationController")

local button = script.Parent.SettingsButton

button.MouseButton1Click:Connect(function()
    NotificationController:ShowInfo(
        "Settings",
        "Settings menu opened",
        2
    )
end)
```

#### Clear all notifications

```lua
local NotificationController = Knit.GetController("NotificationController")

-- Remove all active notifications immediately
NotificationController:ClearAll()
```

## Notification Types

The system supports four notification types, each with distinct colors:

| Type | Color | Use Case |
|------|-------|----------|
| **Info** | Blue | General information, tips, neutral messages |
| **Success** | Green | Achievements, rewards, successful actions |
| **Warning** | Yellow/Orange | Warnings, alerts, important notices |
| **Error** | Red | Errors, failures, critical issues |

## Configuration

The NotificationController has configurable settings:

```lua
-- In NotificationController.luau
local Config = {
    NotificationSpacing = 10,     -- Vertical spacing between notifications
    AnimationDuration = 0.3,      -- Duration of slide animations
    DefaultDuration = 3,          -- Default display time (seconds)
    TypeColors = {
        Info = Color3.fromRGB(52, 152, 219),
        Success = Color3.fromRGB(46, 204, 113),
        Warning = Color3.fromRGB(241, 196, 15),
        Error = Color3.fromRGB(231, 76, 60),
    },
}
```

Adjust these values to customize the appearance and behavior.

## Advanced Features

### Notification Queuing

The system automatically queues notifications when more than 3 are displayed simultaneously. Queued notifications appear as older ones fade out.

```lua
MaxVisibleNotifications = 3  -- Maximum shown at once
```

### Animations

All notifications feature smooth slide-in and slide-out animations using TweenService for a polished look.

## Migration from NotificationClient

The old `NotificationClient` script needs to be manually removed from the game file. It was a template/example script with incorrect implementation that referenced:
- Old "Sample" template name (now "NotificationTemplate")
- Wrong location (template is now in ReplicatedStorage.Assets)
- Event/remote-based system (now uses Knit signals)

### Removal Steps

**⚠️ IMPORTANT: Manual removal required**

The `NotificationClient` script exists in StarterPlayer.StarterPlayerScripts in the game file (.rbxl) but is NOT synced to source control. You must manually remove it:

1. Open the game file in Roblox Studio
2. Navigate to StarterPlayer → StarterPlayerScripts
3. Find and delete the "NotificationClient" script
4. Save the game file

The script is not in the src folder, so it won't be automatically removed when syncing from source. It must be manually deleted from the .rbxl file.

**What changed:**
- ❌ No RemoteEvents or RemoteFunctions
- ✅ Clean Knit service/controller architecture
- ✅ Proper template location (ReplicatedStorage.Assets.NotificationTemplate)
- ✅ More features (types, animations, queuing, convenience methods)
- ✅ Better API with clear server and client methods

## Best Practices

1. **Duration**: Keep notifications between 2-7 seconds for optimal readability
2. **Message Length**: Keep titles under 30 characters, messages under 100 characters
3. **Frequency**: Avoid spamming notifications; they queue automatically
4. **Types**: Use appropriate types to convey the right context
5. **Server vs Client**: 
   - Use server notifications for gameplay events (rewards, achievements)
   - Use client notifications for UI feedback (settings changes, local actions)

## Troubleshooting

**Notifications not showing?**
- Verify NotificationTemplate exists at `ReplicatedStorage.Assets.NotificationTemplate`
- Check that the template has Title and Message TextLabel children
- Ensure Knit is properly initialized on both server and client
- Check the console for warning messages

**Notifications appear off-screen?**
- The container is positioned in the top-right by default
- Adjust position in `GetNotificationContainer()` function if needed

## Examples in Practice

### Example 1: Player joins the game
```lua
-- Server script
Players.PlayerAdded:Connect(function(player)
    task.wait(1) -- Wait for client to load
    NotificationService:Notify(
        player,
        "Welcome to Race Through Time!",
        "Collect fuel and race through the ages!",
        6,
        "Info"
    )
end)
```

### Example 2: Achievement system
```lua
-- Server script
local function OnAchievementUnlocked(player, achievementName)
    NotificationService:Notify(
        player,
        "Achievement Unlocked!",
        achievementName,
        5,
        "Success"
    )
end
```

### Example 3: Low fuel warning
```lua
-- Client script checking fuel level
local function CheckFuelLevel(fuelAmount)
    if fuelAmount < 20 then
        NotificationController:ShowWarning(
            "Low Fuel!",
            "Collect stars to refuel",
            4
        )
    end
end
```

### Example 4: Server shutdown warning
```lua
-- Server script
local function WarnPlayersBeforeShutdown(minutesRemaining)
    NotificationService:NotifyAll(
        "Server Restart",
        string.format("Server restarting in %d minutes", minutesRemaining),
        10,
        "Warning"
    )
end
```
