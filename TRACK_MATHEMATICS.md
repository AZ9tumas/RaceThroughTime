# Track Movement Mathematics

This document explains the mathematical formulas and physics behind the circular track movement system in Race Through Time.

## Overview

The track system moves players in a circular path around a central point (SpawnLocation). Movement is calculated using polar coordinates and converted to Cartesian coordinates for positioning in the 3D world.

## Coordinate Systems

### Polar Coordinates (θ, r)
- **θ (theta)**: Angular position in radians, measured from positive X-axis
- **r (radius)**: Distance from the center (constant per world)

### Cartesian Coordinates (x, y, z)
- **x, z**: Horizontal plane position
- **y**: Vertical position (determined by raycast to track surface)

## Core Formulas

### 1. Speed Calculation from Fuel

The base speed is calculated using fuel and world efficiency:

```
V_base = BaseSpeed + (Fuel^0.7 × E_world) × Multipliers
```

**Code (`Stats.luau`):**
```lua
function Stats.CalculateSpeedFromFuel(fuel: number, worldName: string?): number
    local baseSpeed = Stats.BaseSpeed
    local worldEfficiency = Stats.WorldEfficiency[worldName or "Main"] or 1
    local multipliers = Stats.CalculateMultipliers()
    
    local fuelComponent = math.pow(fuel, 0.7) * worldEfficiency
    local totalSpeed = (baseSpeed + fuelComponent) * multipliers
    
    return totalSpeed
end
```

### 2. Track Parameters with 30-Second Limit

Track runs are capped at 30 seconds maximum. If the fuel-based time exceeds this, acceleration is adjusted to cover the required distance in the limited time.

**Time Calculation:**
```
T_base = Fuel / FuelConsumptionRate
T_actual = min(T_base, 30)
```

**Distance Calculation:**
```
D = V_base × T_base
```

**Acceleration Adjustment (when time is limited):**

Using kinematics equation: `d = v₀t + ½at²`

Solving for acceleration:
```
a = 2(D - v₀t) / t²
```

**Code (`Stats.luau`):**
```lua
function Stats.CalculateTrackParameters(fuel: number, worldName: string?)
    local actualTime = math.min(baseTime, Stats.MaxTrackTime)
    
    if actualTime < baseTime then
        -- Time is capped, adjust acceleration
        local avgSpeedNeeded = baseDistance / actualTime
        initialSpeed = avgSpeedNeeded * 0.3
        acceleration = 2 * (baseDistance - initialSpeed * actualTime) / (actualTime * actualTime)
        maxSpeed = initialSpeed + acceleration * actualTime
    end
    
    return {
        initialSpeed = initialSpeed,
        acceleration = acceleration,
        maxSpeed = maxSpeed,
        totalTime = actualTime,
        totalDistance = baseDistance,
    }
end
```

### 3. Current Speed with Acceleration

Speed increases linearly with time until reaching max speed:

```
V(t) = min(V₀ + a×t, V_max)
```

Where:
- `V₀` = Initial speed
- `a` = Acceleration (studs/sec²)
- `t` = Elapsed time
- `V_max` = Maximum speed cap

**Code (`Stats.luau`):**
```lua
function Stats.CalculateCurrentSpeed(initialSpeed, acceleration, maxSpeed, elapsedTime)
    local speed = initialSpeed + acceleration * elapsedTime
    return math.min(speed, maxSpeed)
end
```

### 4. Linear Speed to Angular Velocity

Converting linear speed to angular velocity for circular motion:

```
ω = V / r
```

Where:
- `ω` = Angular velocity (radians/second)
- `V` = Linear speed (studs/second)
- `r` = Track radius (studs)

**Code (`Stats.luau`):**
```lua
function Stats.LinearSpeedToAngularVelocity(linearSpeed, radius)
    if radius <= 0 then return 0 end
    return linearSpeed / radius
end
```

### 5. Angular Position Update

The angle is updated each frame based on angular velocity:

```
θ(t+dt) = θ(t) + ω × dt
```

**Code (`TrackService.luau`):**
```lua
trackData.currentAngle = trackData.currentAngle + (angularVelocity * dt)
```

### 6. Polar to Cartesian Conversion

Converting polar coordinates to world position:

```
x = center_x + r × cos(θ)
z = center_z + r × sin(θ)
```

**Code (`Stats.luau`):**
```lua
function Stats.PolarToCartesian(centerX, centerZ, radius, angle)
    local x = centerX + radius * math.cos(angle)
    local z = centerZ + radius * math.sin(angle)
    return x, z
end
```

### 7. Player Orientation (Tangential Direction)

The player faces tangent to the circle (in the direction of motion):

```
lookAt_x = x - sin(θ)
lookAt_z = z + cos(θ)
```

This works because the tangent vector to a circle at angle θ is:
```
T = (-sin(θ), cos(θ))
```

**Code (`TrackService.luau`):**
```lua
local lookAtPos = targetPosition + Vector3.new(
    -math.sin(angle), -- Derivative of cos
    0,
    math.cos(angle)   -- Derivative of sin
)
local finalCFrame = CFrame.lookAt(targetPosition, lookAtPos)
```

## Distance Tracking

### Linear Distance Traveled

Distance is accumulated each frame based on current speed:

```
D_traveled += V_current × dt
```

This represents the arc length traveled along the circular path.

### Lap Detection

A lap is completed when the angle has increased by 2π from the starting angle:

```
Lap completed when: θ_current ≥ θ_start + 2π × (lapCount + 1)
```

## Body Mover Physics

### Dynamic Responsiveness

At higher speeds, the AlignPosition body mover needs higher responsiveness to prevent the player from "cutting corners" and drifting toward the center.

```
Responsiveness = Base + (V_current / 10) × 10
MaxVelocity = max(500, V_current × 2)
```

Where Base = 50 and the speed factor is clamped to prevent extreme values.

**Code (`TrackService.luau`):**
```lua
local baseResponsiveness = 50
local speedFactor = math.clamp(currentSpeed / 10, 1, 20)
local dynamicResponsiveness = baseResponsiveness + (speedFactor * 10)
local dynamicMaxVelocity = math.max(500, currentSpeed * 2)

alignPosition.Responsiveness = dynamicResponsiveness
alignPosition.MaxVelocity = dynamicMaxVelocity
```

## Ground Detection

### Raycasting to Track Surface

The Y position is determined by raycasting down to the Visual_Track:

```
Ray origin: (x, fallback_y + 50, z)
Ray direction: (0, -100, 0)
Ground Y: raycastResult.Position.Y (or fallback if miss)
```

## World-Specific Parameters

| World | Radius | Efficiency | Fuel Rate | Cash Rate |
|-------|--------|------------|-----------|-----------|
| Main | 205 | 1.0 | 25/sec | 150/1000 |
| StoneAge | 205 | 1.2 | 28/sec | 180/1000 |

## Physical Speed Limit

### Dual Speed System

To prevent physics issues at high calculated speeds while still tracking accurate stats, the system uses two speed values:

1. **Calculated Speed** (`calculatedSpeed`): The full speed based on fuel and acceleration, used for distance tracking and stats
2. **Physical Speed** (`physicalSpeed`): Capped at `MaxPhysicalSpeed` (150 studs/sec), used for body movers and lap detection

```
physicalSpeed = min(calculatedSpeed, MaxPhysicalSpeed)
```

This means:
- **Stats/Distance**: Uses `calculatedSpeed` - players earn full distance rewards
- **Lap Detection**: Uses `physicalSpeed` - laps are counted based on actual circular motion
- **Body Movers**: Uses `physicalSpeed` - prevents physics glitches at extreme speeds

**Code (`TrackService.luau`):**
```lua
-- Calculate current speed using acceleration (for stats)
local calculatedSpeed = Stats.CalculateCurrentSpeed(
    trackData.initialSpeed,
    trackData.acceleration,
    trackData.maxSpeed,
    trackData.elapsedTime
)

-- Physical speed is capped for body movers and lap detection
local physicalSpeed = math.min(calculatedSpeed, Stats.MaxPhysicalSpeed)

-- Angular velocity uses physical speed
local angularVelocity = Stats.LinearSpeedToAngularVelocity(physicalSpeed, radius)

-- Distance uses calculated speed for full tracking
local distanceThisFrame = calculatedSpeed * dt
trackData.distanceTraveled = trackData.distanceTraveled + distanceThisFrame
```

## Summary of Motion

1. **Calculate speed** from fuel using power law: `V = Base + Fuel^0.7 × Efficiency`
2. **Calculate track parameters** with 30s time limit, adjusting acceleration if needed
3. **Each frame:**
   - Update elapsed time
   - Calculate current speed with acceleration: `V = V₀ + a×t`
   - Apply physical speed limit: `V_physical = min(V, MaxPhysicalSpeed)`
   - Convert to angular velocity: `ω = V_physical / r`
   - Update angle: `θ += ω × dt`
   - Convert to Cartesian: `(x, z) = (center + r×cos(θ), center + r×sin(θ))`
   - Raycast to get ground Y
   - Update body mover target with dynamic responsiveness (based on physical speed)
   - Track distance: `D += V × dt` (using full calculated speed)
