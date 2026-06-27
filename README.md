# Pathfind

A lightweight, modular, production-ready pathfinding library for Roblox that wraps `PathfindingService` with a clean, modern API.

## Features

- 🚶 **Smooth Waypoint Following** — Natural character movement without jitter
- 🦘 **Automatic Jump Handling** — Handles jump waypoints seamlessly
- 👁️ **Line-of-Sight Optimization** — Skips waypoints when the path is clear
- 🔄 **Smart Repathing** — Recalculates when targets move or paths become blocked
- 🛡️ **Anti-Stuck System** — Detects and recovers from stuck states
- 👻 **Respawn Handling** — Automatically handles character respawns
- 🎨 **Debug Visualization** — Draw waypoints, lines, and debug info
- ⚡ **Performance Optimized** — Throttled computations, low CPU usage
- 📝 **Well Documented** — Clean Luau types and inline docs
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

### `Pathfind.new(character, config?)`

Creates a new Pathfind instance.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `character` | `Model?` | The character model to pathfind with |
| `config` | `PathfindConfig?` | Optional configuration table |

**Returns:** `Pathfind` instance

---

### `:GoTo(target, timeout?)`

Pathfind to a target position or instance.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `target` | `Vector3 \| Instance` | Destination position or instance |
| `timeout` | `number?` | Optional timeout in seconds |

**Returns:** `Pathfind` (for chaining)

---

### `:Follow(target, repathInterval?)`

Follow a moving target continuously.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `target` | `Instance` | Instance to follow |
| `repathInterval` | `number?` | Seconds between repaths (default: 0.5) |

**Returns:** `Pathfind` (for chaining)

---

### `:Stop()`

Stops all current movement and clears the path.

---

### `:Pause()`

Pauses movement. Call `:Resume()` to continue.

---

### `:Resume()`

Resumes paused movement.

---

### `:IsMoving(): boolean`

Returns whether the character is currently moving along a path.

---

### `:GetStatus(): string`

Returns the current status: `"idle"`, `"computing"`, `"moving"`, `"paused"`, `"blocked"`, `"completed"`, or `"failed"`.

---

### `:GetProgress(): number`

Returns movement progress from 0 to 1.

---

### `:SetConfig(key, value)`

Updates a configuration value at runtime.

---

### `:GetConfig(key): any`

Gets the current value of a configuration key.

---

### `:EnableDebug(enabled: boolean)`

Toggles debug visualization on or off.

---

### `:SetCharacter(character)`

Changes the character model (useful for respawning).

---

### `:Destroy()`

Cleans up all connections and destroys the instance.

---

## Events

| Event | Parameters | Description |
|-------|-----------|-------------|
| `Completed` | `(success: boolean)` | Fired when path finishes |
| `Blocked` | `(waypointIndex: number)` | Fired when path is blocked |
| `Repath` | `(pathIndex: number)` | Fired when path is recalculated |
| `Stuck` | `(recoveryAttempt: number)` | Fired when stuck is detected |
| `Failed` | `(reason: string)` | Fired when path fails |
| `Paused` | — | Fired when movement is paused |
| `Resumed` | — | Fired when movement is resumed |
| `Started` | `(target)` | Fired when a new path starts |

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
