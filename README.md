# Pathfind

A lightweight, modular, production-ready pathfinding library for Roblox that wraps `PathfindingService` with a clean, modern API.

> 📖 **[Full API Reference →](API.md)**

## Features

- 🚶 **Smooth Waypoint Following** — Natural character movement without jitter
- 🦘 **Automatic Jump Handling** — Handles jump waypoints seamlessly
- 👁️ **Line-of-Sight Optimization** — Skips waypoints when the path is clear
- 🔄 **Smart Repathing** — Recalculates when targets move or paths become blocked
- 🛡️ **Anti-Stuck System** — Detects and recovers from stuck states
- 👻 **Respawn Handling** — Automatically handles character respawns
- 👁️ **Path Preview** — Preview paths before committing to movement
- 🎯 **Waypoint Events** — Get notified at every waypoint reached
- 📊 **Path Info** — Query detailed path state and progress
- 🎨 **Debug Visualization** — Draw waypoints, lines, and debug info
- ⚡ **Performance Optimized** — Throttled computations, low CPU usage
- 📝 **Well Documented** — Clean Luau types, inline docs, and comprehensive API reference
- 🧩 **Fully Configurable** — Every aspect can be customized

## Installation

### Option 1: Rojo (Recommended)

1. Clone this repository or download the `src/` folder
2. Place it in your Rojo project under `ServerScriptService` or `ReplicatedStorage`
3. Reference it in your `default.project.json`:

```json
{
  "tree": {
    "$className": "DataModel",
    "ServerScriptService": {
      "Pathfind": {
        "$path": "src"
      }
    }
  }
}
```

### Option 2: Wally

Add to your `wally.toml`:

```toml
[dependencies]
Pathfind = "your-username/pathfind@1.0.0"
```

Then run:

```bash
wally install
```

## Quick Start

```lua
local Pathfind = require(path.to.Pathfind)

-- Create a pathfinder
local path = Pathfind.new(game.Players.LocalPlayer.Character, {
    debug = true, -- Enable debug visualization
})

-- Go to a target
path:GoTo(workspace.TargetPart)

-- Listen for completion
path.Completed:Connect(function(success)
    if success then
        print("Reached the target!")
    else
        print("Failed to reach target")
    end
end)
```

## API Reference

> 📖 **See [API.md](API.md) for the complete, detailed API reference.**

### `Pathfind.new(character, config?)`

Creates a new Pathfind instance.

```lua
local path = Pathfind.new(workspace.MyNPC, {
    debug = true,
    agentCanJump = true,
})
```

### `:GoTo(target, timeout?)` → `Pathfind`

Pathfind to a target position or instance.

```lua
path:GoTo(workspace.TargetPart)
path:GoTo(Vector3.new(10, 0, 5), 10) -- with timeout
path:GoTo(workspace.MovingPart) -- auto-repaths when target moves
```

### `:Follow(target, repathInterval?)` → `Pathfind`

Follow a moving target continuously.

```lua
path:Follow(player.Character, 0.3)
```

### `:PreviewPath(target)` → `PathPreview?`

Preview a path without starting movement.

```lua
local preview = path:PreviewPath(workspace.Enemy)
if preview and preview.success then
    print(#preview.waypoints, "waypoints,", preview.distance, "studs")
end
```

### `:Stop()` — Stop movement and clear path
### `:Pause()` — Pause movement
### `:Resume()` — Resume paused movement
### `:CancelGoTo()` — Cancel current path (reusable)

### Query Methods

```lua
path:IsMoving()          --> boolean
path:GetStatus()         --> PathStatus string
path:GetProgress()       --> number (0 to 1)
path:GetPathInfo()       --> PathInfo table
path:GetWaypoints()      --> { WaypointData }?
path:GetTarget()         --> Vector3?
path:GetCharacter()      --> Model?
path:IsPaused()          --> boolean
path:IsAlive()           --> boolean
```

### Configuration

```lua
path:SetConfig("debug", true)
path:GetConfig("turnSpeed") --> 12
path:EnableDebug(true)
path:SetCharacter(newCharacter)
```

### `:Destroy()` — Clean up everything

---

## Events

| Event | Parameters | Description |
|-------|-----------|-------------|
| `Completed` | `(success, reason?)` | Path finished |
| `Blocked` | `(waypointIndex)` | Path blocked |
| `Repath` | `(pathIndex)` | Path recalculated |
| `Stuck` | `(recoveryAttempt)` | Stuck detected |
| `Failed` | `(reason)` | Path failed |
| `Paused` | — | Movement paused |
| `Resumed` | — | Movement resumed |
| `Started` | `(target)` | New path started |
| `Waypoint` | `(index, waypoint)` | Waypoint reached |

## Configuration

```lua
local path = Pathfind.new(character, {
    -- Agent Parameters (for PathfindingService)
    agentRadius = nil,          -- Custom agent radius
    agentHeight = nil,          -- Custom agent height
    agentCanJump = true,        -- Allow jumping
    agentCanClimb = false,      -- Allow climbing
    agentCanSlide = false,      -- Allow sliding

    -- Movement
    moveSpeed = nil,            -- Override walk speed (nil = use current)
    turnSpeed = 12,             -- Rotation speed (radians/sec)
    reachDistance = 2,          -- Waypoint reach threshold
    jumpPower = nil,            -- Override jump power

    -- Path Management
    repathInterval = 0.5,       -- Seconds between repath checks
    repathThreshold = 4,        -- Studs target must move to repath
    maxPathAttempts = 3,        -- Max failed attempts
    timeout = nil,              -- Max path duration (nil = none)
    waypointTimeout = 4,        -- Max seconds per waypoint

    -- Anti-Stuck
    antiStuckEnabled = true,    -- Enable anti-stuck
    stuckThreshold = 2,         -- Seconds before "stuck"
    stuckRecoveryAttempts = 3,  -- Max recovery attempts
    stuckMoveDelta = 0.5,       -- Min movement to reset timer

    -- Line-of-Sight
    losCheckEnabled = true,     -- Enable LOS waypoint skipping
    losRaycastParams = nil,     -- Custom raycast params

    -- Debug
    debug = false,              -- Enable debug visualization
    debugColor = Color3.new(0, 1, 1),
    debugBlockedColor = Color3.new(1, 0, 0),
    debugLineColor = Color3.new(1, 1, 0),
})
```

## Examples

### Basic Navigation

```lua
local Pathfind = require(path.to.Pathfind)

local path = Pathfind.new(workspace.NPC)

path.Completed:Connect(function(success)
    print("Path completed:", success)
end)

path:GoTo(workspace.Destination.Position)
```

### Follow a Player

```lua
local path = Pathfind.new(workspace.NPC)

local player = game.Players.LocalPlayer
if player.Character then
    path:Follow(player.Character, 0.5) -- Repath every 0.5s
end
```

### Chained API

```lua
local path = Pathfind.new(character)

path:GoTo(workspace.PartA)
    .Completed:Wait()

path:GoTo(workspace.PartB)
    .Completed:Wait()

print("Finished both paths!")
```

### Pause and Resume

```lua
local path = Pathfind.new(character)
path:GoTo(workspace.FarTarget)

-- Pause when something happens
path.Paused:Connect(function()
    print("Path paused")
end)

task.wait(3)
path:Resume()
```

### Custom Agent Parameters

```lua
local path = Pathfind.new(character, {
    agentRadius = 2,      -- Wider character
    agentHeight = 5,      -- Taller character
    agentCanJump = true,  -- Allow jumping
    agentCanClimb = true, -- Allow climbing
})
```

### Debug Mode

```lua
local path = Pathfind.new(character, {
    debug = true,
    debugColor = Color3.new(0, 1, 1),        -- Cyan waypoints
    debugBlockedColor = Color3.new(1, 0, 0),  -- Red for blocked
    debugLineColor = Color3.new(1, 1, 0),     -- Yellow lines
})

-- Toggle at runtime
path:EnableDebug(false)
```

## How It Works

1. **Path Computation** — Uses `PathfindingService:CreatePath()` with configurable agent parameters
2. **Movement Engine** — Follows waypoints with smooth rotation and movement interpolation
3. **Line-of-Sight** — Checks if waypoints can be skipped using raycasts for faster navigation
4. **Anti-Stuck** — Monitors movement and attempts recovery (jump → repath → random adjustment)
5. **Smart Repathing** — Recalculates paths when targets move or time-based intervals elapse
6. **Debug Mode** — Visualizes waypoints, path lines, and current position in real-time

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
