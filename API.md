# Pathfind API Reference

> Complete API documentation for the **Pathfind** library — a lightweight, modular, production-ready pathfinding library for Roblox Luau.

---

## Table of Contents

- [Installation](#installation)
- [Type Definitions](#type-definitions)
- [Constructor](#constructor)
- [Navigation Methods](#navigation-methods)
- [Control Methods](#control-methods)
- [Query Methods](#query-methods)
- [Configuration Methods](#configuration-methods)
- [Events](#events)
- [Configuration Reference](#configuration-reference)
- [Error Handling](#error-handling)
- [Performance Guide](#performance-guide)
- [Examples](#examples)

---

## Installation

### Rojo

```json
{
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "Pathfind": { "$path": "src" }
    }
  }
}
```

### Wally

```toml
[dependencies]
Pathfind = "your-username/pathfind@1.0.0"
```

### Manual

Copy the `src/` folder into your project and require it via a ModuleScript.

---

## Type Definitions

### `PathfindConfig`

All fields are optional. Unset fields use sensible defaults.

```lua
export type PathfindConfig = {
    -- Agent Parameters (passed to PathfindingService)
    agentRadius: number?,           -- Agent collision radius
    agentHeight: number?,           -- Agent clearance height
    agentCanJump: boolean?,         -- Allow jumping (default: true)
    agentCanClimb: boolean?,        -- Allow climbing ladders (default: false)
    agentCanSlide: boolean?,        -- Allow sliding (default: false)

    -- Movement
    moveSpeed: number?,             -- Override WalkSpeed (nil = keep current)
    turnSpeed: number?,             -- Rotation speed in radians/sec (default: 12)
    reachDistance: number?,         -- Studs to consider a waypoint "reached" (default: 2)
    jumpPower: number?,             -- Override JumpPower (nil = keep current)

    -- Path Management
    repathInterval: number?,        -- Seconds between repath checks (default: 0.5)
    repathThreshold: number?,       -- Studs target must move to trigger repath (default: 4)
    maxPathAttempts: number?,       -- Max failed path computations (default: 3)
    timeout: number?,               -- Max seconds for entire path (nil = none)
    waypointTimeout: number?,       -- Max seconds per waypoint (default: 4)

    -- Anti-Stuck
    antiStuckEnabled: boolean?,     -- Enable anti-stuck system (default: true)
    stuckThreshold: number?,        -- Seconds before considered stuck (default: 2)
    stuckRecoveryAttempts: number?, -- Max recovery attempts (default: 3)
    stuckMoveDelta: number?,        -- Min studs to reset stuck timer (default: 0.5)

    -- Line-of-Sight
    losCheckEnabled: boolean?,      -- Enable LOS waypoint skipping (default: true)
    losRaycastParams: RaycastParams?, -- Custom raycast params for LOS checks

    -- Debug
    debug: boolean?,                -- Enable debug visualization (default: false)
    debugColor: Color3?,            -- Waypoint color (default: Cyan)
    debugBlockedColor: Color3?,     -- Blocked marker color (default: Red)
    debugLineColor: Color3?,        -- Path line color (default: Yellow)
}
```

### `WaypointData`

```lua
export type WaypointData = {
    position: Vector3,
    action: Enum.PathWaypointAction,  -- Walk or Jump
    index: number,
}
```

### `PathStatus`

```lua
export type PathStatus =
    "idle"       -- No path is active
    | "computing" -- Path is being computed
    | "moving"    -- Character is following waypoints
    | "paused"    -- Movement is paused
    | "blocked"   -- Path is blocked
    | "completed" -- Path finished successfully
    | "failed"    -- Path failed
```

### `PathInfo`

Returned by `:GetPathInfo()`.

```lua
export type PathInfo = {
    status: PathStatus,
    target: Vector3?,
    progress: number,               -- 0 to 1
    currentWaypoint: number,
    totalWaypoints: number,
    distanceToTarget: number?,      -- Studs to final target
    pathAttempts: number,
    isPaused: boolean,
}
```

### `PathfindEvents`

All events follow the `RBXScriptSignal` pattern with `:Connect()`, `:Once()`, and `:Wait()`.

```lua
export type PathfindEvents = {
    Completed: (success: boolean, reason: string?) -> (),
    Blocked:   (waypointIndex: number) -> (),
    Repath:    (pathIndex: number) -> (),
    Stuck:     (recoveryAttempt: number) -> (),
    Failed:    (reason: string) -> (),
    Paused:    () -> (),
    Resumed:   () -> (),
    Started:   (target: Vector3 | Instance) -> (),
    Waypoint:  (index: number, waypoint: WaypointData) -> (),
}
```

---

## Constructor

### `Pathfind.new(character, config?)`

Creates a new Pathfind instance and begins tracking a character.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `character` | `Model?` | Yes | The character model to pathfind with. Pass `nil` to set later via `:SetCharacter()`. |
| `config` | `PathfindConfig?` | No | Configuration overrides. Unset fields use defaults. |

**Returns:** `Pathfind`

**Example:**

```lua
local Pathfind = require(path.to.Pathfind)

-- With character
local path = Pathfind.new(workspace.MyNPC, {
    debug = true,
    agentCanJump = true,
})

-- Without character (set later)
local path = Pathfind.new(nil)
path:SetCharacter(workspace.MyNPC)
```

---

## Navigation Methods

### `:GoTo(target, timeout?)`

Computes a path and navigates the character to the target.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `target` | `Vector3 \| BasePart \| Model \| Attachment` | Yes | The destination. Accepts a position, Part, Model (uses PrimaryPart), or Attachment. |
| `timeout` | `number?` | No | Max seconds for this path. Overrides the config `timeout`. |

**Returns:** `Pathfind` (for method chaining)

**Behavior:**
- Cancels any active path before starting
- Automatically retries on computation failure (up to `maxPathAttempts`)
- Fires `Started` immediately, then `Completed` or `Failed` when done
- If target is an Instance, automatically repaths when the target moves beyond `repathThreshold`

**Example:**

```lua
path:GoTo(workspace.Part.Position)

-- With timeout
path:GoTo(workspace.FarAway, 10)

-- With Instance (auto-follows movement)
path:GoTo(workspace.MovingPart)

-- Method chaining
path:GoTo(workspace.A):Completed:Wait()
path:GoTo(workspace.B)
```

---

### `:Follow(target, repathInterval?)`

Continuously follows a moving target by recomputing paths periodically.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `target` | `Instance` | Yes | The instance to follow (must have a BasePart). |
| `repathInterval` | `number?` | No | Seconds between repath checks. Overrides config `repathInterval`. |

**Returns:** `Pathfind` (for method chaining)

**Behavior:**
- Runs an async follow loop until the target is destroyed, `:Stop()` is called, or the path fails
- Recomputes path when target moves beyond `repathThreshold`
- Fires `Repath` each time the path is recalculated
- Fires `Completed(false, "Follow loop ended")` when the loop exits

**Example:**

```lua
path:Follow(game.Players.LocalPlayer.Character, 0.3)

-- Follow with completion handler
path.Follow(game.Workspace.Enemy, 0.5)
    .Completed:Connect(function(success)
        print("Stopped following:", success)
    end)
```

---

### `:PreviewPath(target)`

Computes a path without starting movement. Useful for showing the path to the player before they commit.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `target` | `Vector3 \| Instance` | Yes | The destination to preview. |

**Returns:** `{ waypoints: { WaypointData }, distance: number, success: boolean }?`

**Example:**

```lua
local preview = path:PreviewPath(workspace.Destination)
if preview and preview.success then
    print("Path found! Distance:", math.floor(preview.distance), "studs")
    -- Draw preview in debug mode...
else
    print("No path available")
end
```

---

## Control Methods

### `:Stop()`

Immediately stops all movement and clears the current path.

**Behavior:**
- Disconnects the movement loop
- Clears the path cache and anti-stuck state
- Cancels all active threads (timeout, repath)
- Clears debug visualization
- Resets status to `"idle"`

**Example:**

```lua
path:Stop()
print(path:GetStatus()) --> "idle"
```

---

### `:Pause()`

Pauses movement. The character stops but the path is preserved.

**Behavior:**
- Sets `isPaused` flag on the movement engine
- Character stops moving but path state is maintained
- Fires `Paused` event

**Example:**

```lua
path:GoTo(workspace.Far)
task.wait(2)
path:Pause()
print("Paused!")
task.wait(1)
path:Resume()
```

---

### `:Resume()`

Resumes a paused path.

**Behavior:**
- Clears the `isPaused` flag
- The movement loop continues from the current waypoint
- Fires `Resumed` event

---

### `:CancelGoTo()`

Cancels the current `GoTo` path but does not destroy the instance. The instance can be reused for new paths.

**Example:**

```lua
path:GoTo(workspace.Far)
task.wait(1)
path:CancelGoTo()
path:GoTo(workspace.Close) -- Start a new path immediately
```

---

## Query Methods

### `:IsMoving(): boolean`

Returns `true` if the character is actively following waypoints and not paused.

**Returns:** `boolean`

**Example:**

```lua
if not path:IsMoving() then
    path:GoTo(workspace.Destination)
end
```

---

### `:GetStatus(): PathStatus`

Returns the current status string.

**Returns:** `PathStatus`

**Example:**

```lua
print(path:GetStatus()) --> "idle" | "computing" | "moving" | "paused" | ...

-- Use in conditionals
if path:GetStatus() == "idle" then
    path:GoTo(workspace.Target)
end
```

---

### `:GetProgress(): number`

Returns movement progress as a fraction from 0 to 1.

**Returns:** `number` — 0 = just started, 1 = reached destination

**Example:**

```lua
while path:IsMoving() do
    print(string.format("Progress: %.0f%%", path:GetProgress() * 100))
    task.wait(0.5)
end
```

---

### `:GetPathInfo(): PathInfo`

Returns comprehensive information about the current path state.

**Returns:** `PathInfo`

**Example:**

```lua
local info = path:GetPathInfo()
print("Status:", info.status)
print("Progress:", info.progress)
print("Waypoints:", info.currentWaypoint .. "/" .. info.totalWaypoints)
print("Distance:", info.distanceToTarget)
print("Attempts:", info.pathAttempts)
```

---

### `:GetWaypoints(): { WaypointData }?`

Returns the current set of waypoints, or `nil` if no path is active.

**Returns:** `{ WaypointData }?`

**Example:**

```lua
local waypoints = path:GetWaypoints()
if waypoints then
    print("Path has", #waypoints, "waypoints")
    for i, wp in waypoints do
        print(i, wp.position, wp.action.Name)
    end
end
```

---

### `:GetTarget(): Vector3?`

Returns the current target position, or `nil` if no path is active.

**Returns:** `Vector3?`

**Example:**

```lua
path:GoTo(workspace.Enemy.Position)
task.wait(1)
local target = path:GetTarget()
if target then
    print("Heading to:", target)
end
```

---

### `:GetCharacter(): Model?`

Returns the character model this pathfinder is tracking.

**Returns:** `Model?`

---

### `:IsPaused(): boolean`

Returns whether the path is currently paused.

**Returns:** `boolean`

---

### `:IsAlive(): boolean`

Returns whether the instance is still valid (not destroyed).

**Returns:** `boolean`

---

## Configuration Methods

### `:SetConfig(key, value)`

Updates a configuration value at runtime.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `key` | `string` | The config key to update (see [Configuration Reference](#configuration-reference)). |
| `value` | `any` | The new value. |

**Behavior:**
- Automatically propagates changes to subsystems (e.g., changing `debug` toggles debug mode)
- Changes take effect immediately for subsequent paths

**Example:**

```lua
path:SetConfig("debug", true)
path:SetConfig("turnSpeed", 20)
path:SetConfig("stuckThreshold", 3)
```

---

### `:GetConfig(key): any`

Returns the current value of a configuration key.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `key` | `string` | The config key to read. |

**Returns:** `any`

**Example:**

```lua
print(path:GetConfig("turnSpeed")) --> 12
print(path:GetConfig("debug")) --> false
```

---

### `:EnableDebug(enabled: boolean)`

Shorthand to toggle debug visualization.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `enabled` | `boolean` | `true` to enable, `false` to disable. |

**Example:**

```lua
path:EnableDebug(true)  -- Show waypoints and lines
path:EnableDebug(false) -- Hide everything
```

---

### `:SetCharacter(character)`

Changes the character model this pathfinder tracks. Useful for handling respawns.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `character` | `Model?` | The new character model. Pass `nil` to clear. |

**Behavior:**
- Stops any active path
- Sets up character destruction watch for auto-cleanup

**Example:**

```lua
-- Handle respawn
player.CharacterAdded:Connect(function(char)
    path:SetCharacter(char)
end)
```

---

### `:Destroy()`

Cleans up all connections, events, threads, and debug visualization. The instance cannot be reused after this.

**Example:**

```lua
path:Destroy()
path = nil -- Prevent accidental reuse
```

---

## Events

All events use the standard Roblox signal pattern:

```lua
local connection = path.EventName:Connect(function(...) end)
connection:Disconnect()

path.EventName:Once(function(...) end) -- Auto-disconnects after first fire

local args = { path.EventName:Wait() } -- Yields until fired
```

### Event Reference

| Event | Signature | Description |
|-------|-----------|-------------|
| **Completed** | `(success: boolean, reason: string?)` | Fired when a path finishes. `success = true` means the destination was reached. `reason` is provided on failure (e.g., `"Timeout"`, `"Follow loop ended"`). |
| **Blocked** | `(waypointIndex: number)` | Fired when PathfindingService reports the path is blocked at the given waypoint index. |
| **Repath** | `(pathIndex: number)` | Fired when the path is being recalculated (target moved, anti-stuck, etc.). |
| **Stuck** | `(recoveryAttempt: number)` | Fired when the anti-stuck system detects the character hasn't moved. `recoveryAttempt` is 1-based (1 = first attempt). |
| **Failed** | `(reason: string)` | Fired when the path fails permanently. Reason examples: `"Invalid target"`, `"No path found after 3 attempts"`, `"Timeout"`, `"Character is invalid"`. |
| **Paused** | `()` | Fired when `:Pause()` is called. |
| **Resumed** | `()` | Fired when `:Resume()` is called. |
| **Started** | `(target: Vector3 \| Instance)` | Fired immediately when a new path begins. |
| **Waypoint** | `(index: number, waypoint: WaypointData)` | Fired each time a waypoint is reached during movement. |

### Event Examples

```lua
-- Completion handling
path.Completed:Connect(function(success, reason)
    if success then
        print("Arrived!")
    else
        warn("Failed:", reason)
    end
end)

-- Block detection with auto-repath
path.Blocked:Connect(function(waypointIndex)
    print("Blocked at waypoint", waypointIndex, "- repathing...")
end)

-- Stuck recovery
path.Stuck:Connect(function(attempt)
    print("Stuck! Recovery attempt:", attempt)
end)

-- Failure with cleanup
path.Failed:Once(function(reason)
    warn("Path failed:", reason)
    path:Destroy()
end)

-- Waypoint tracking
path.Waypoint:Connect(function(index, waypoint)
    print("Reached waypoint", index, "at", waypoint.position)
end)

-- Block → Repath → Continue pattern
path.Blocked:Connect(function(idx)
    print("Blocked at", idx, "- will auto-repath")
end)

-- Wait for completion
task.spawn(function()
    path:GoTo(workspace.Target)
    local success = path.Completed:Wait()
    print("Done:", success)
end)
```

---

## Configuration Reference

### Default Values

```lua
{
    -- Agent Parameters
    agentRadius         = nil,          -- PathfindingService default
    agentHeight         = nil,          -- PathfindingService default
    agentCanJump        = true,
    agentCanClimb       = false,
    agentCanSlide       = false,

    -- Movement
    moveSpeed           = nil,          -- Keep current WalkSpeed
    turnSpeed           = 12,           -- radians/sec
    reachDistance        = 2,           -- studs
    jumpPower           = nil,          -- Keep current JumpPower

    -- Path Management
    repathInterval      = 0.5,          -- seconds
    repathThreshold     = 4,            -- studs
    maxPathAttempts     = 3,
    timeout             = nil,          -- no timeout
    waypointTimeout     = 4,            -- seconds

    -- Anti-Stuck
    antiStuckEnabled    = true,
    stuckThreshold      = 2,            -- seconds
    stuckRecoveryAttempts = 3,
    stuckMoveDelta      = 0.5,          -- studs

    -- Line-of-Sight
    losCheckEnabled     = true,
    losRaycastParams    = nil,          -- default RaycastParams

    -- Debug
    debug               = false,
    debugColor          = Color3.new(0, 1, 1),   -- Cyan
    debugBlockedColor   = Color3.new(1, 0, 0),   -- Red
    debugLineColor      = Color3.new(1, 1, 0),   -- Yellow
}
```

### Configuration Descriptions

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `agentRadius` | `number?` | `nil` | Collision radius passed to `PathfindingService:CreatePath()`. |
| `agentHeight` | `number?` | `nil` | Clearance height passed to `PathfindingService:CreatePath()`. |
| `agentCanJump` | `boolean` | `true` | Whether the agent can jump over obstacles. |
| `agentCanClimb` | `boolean` | `false` | Whether the agent can climb ladders/rope. |
| `agentCanSlide` | `boolean` | `false` | Whether the agent can slide on slopes. |
| `moveSpeed` | `number?` | `nil` | If set, overrides the character's `WalkSpeed`. |
| `turnSpeed` | `number` | `12` | How fast the character rotates toward waypoints (radians/sec). |
| `reachDistance` | `number` | `2` | How close (in studs) the character must be to a waypoint to count as "reached". |
| `jumpPower` | `number?` | `nil` | If set, overrides the character's `JumpPower`. |
| `repathInterval` | `number` | `0.5` | How often (in seconds) to check if the path should be recalculated. |
| `repathThreshold` | `number` | `4` | How far (in studs) the target must move to trigger a repath. |
| `maxPathAttempts` | `number` | `3` | Maximum number of failed path computations before giving up. |
| `timeout` | `number?` | `nil` | Maximum seconds for the entire path. `nil` = no timeout. |
| `waypointTimeout` | `number` | `4` | Maximum seconds to spend on a single waypoint before moving on. |
| `antiStuckEnabled` | `boolean` | `true` | Enable the anti-stuck detection system. |
| `stuckThreshold` | `number` | `2` | Seconds without movement before considered "stuck". |
| `stuckRecoveryAttempts` | `number` | `3` | Maximum recovery attempts before firing `Failed`. |
| `stuckMoveDelta` | `number` | `0.5` | Minimum studs moved to reset the stuck timer. |
| `losCheckEnabled` | `boolean` | `true` | Enable line-of-sight raycast checks to skip waypoints. |
| `losRaycastParams` | `RaycastParams?` | `nil` | Custom raycast parameters for LOS checks. |
| `debug` | `boolean` | `false` | Enable debug visualization (waypoints, lines, labels). |
| `debugColor` | `Color3` | Cyan | Color for normal waypoints. |
| `debugBlockedColor` | `Color3` | Red | Color for blocked markers. |
| `debugLineColor` | `Color3` | Yellow | Color for path lines. |

---

## Error Handling

Pathfind is designed to **never throw errors** in normal usage. All edge cases are handled gracefully:

| Scenario | Behavior |
|----------|----------|
| Invalid target | Fires `Failed("Invalid target")` |
| Character destroyed | Stops path, fires `Completed(false)` |
| Character has no HumanoidRootPart | Fires `Failed("Character is invalid")` |
| No path exists | Retries up to `maxPathAttempts`, then fires `Failed("No path found...")` |
| Path is blocked | Fires `Blocked`, auto-repaths if target moved |
| Target destroyed during GoTo | Fires `Failed("Invalid target")` |
| Target destroyed during Follow | Fires `Completed(false, "Follow loop ended")` |
| Timeout reached | Fires `Failed("Timeout")` |
| Anti-stuck recovery exhausted | Fires `Failed("Anti-stuck recovery failed...")` |
| `Destroy()` called | Cleans up everything, no further events fire |

### Safe Usage Pattern

```lua
local path = Pathfind.new(character)

-- Always handle both success and failure
path.Completed:Connect(function(success, reason)
    if success then
        print("Reached destination!")
    else
        warn("Path failed:", reason)
    end
end)

-- Or use pcall for maximum safety
path:GoTo(workspace.Target)
```

---

## Performance Guide

### Best Practices

1. **Reuse Pathfind instances** — Creating new instances is cheap, but reusing one for the same character avoids event leaks.

2. **Don't call GoTo every frame** — The library handles repathing automatically. Only call `GoTo()` when you actually need a new destination.

3. **Use Follow() for moving targets** — It handles repathing internally and is more efficient than manual GoTo loops.

4. **Enable LOS optimization** — `losCheckEnabled = true` (default) skips waypoints via raycasts, reducing unnecessary movement checks.

5. **Set reasonable repathInterval** — `0.5s` is good for most cases. Lower values (0.1-0.2) are better for fast-moving targets but use more CPU.

6. **Use timeout for long paths** — Prevents the character from pathing forever if the target is unreachable.

7. **Disable debug in production** — Debug mode creates Parts in workspace which impacts performance.

### CPU Usage

- **Idle**: ~0 CPU (no connections active)
- **Moving**: ~1 Heartbeat connection + optional repath thread
- **Following**: ~1 Heartbeat + 1 periodic repath check
- **Debug mode**: Additional Part creation in workspace

### Memory

- Each Pathfind instance: ~2KB + 1 BindableEvent per event (8 events = 8 BindableEvents)
- Debug visualization: Parts are cleaned up on `:Stop()` and `:Destroy()`

---

## Examples

### Basic Navigation

```lua
local Pathfind = require(path.to.Pathfind)

local path = Pathfind.new(workspace.MyNPC)

path.Completed:Connect(function(success)
    print("Navigation", success and "succeeded" or "failed")
end)

path:GoTo(workspace.Destination.Position)
```

### Follow Player with Custom Config

```lua
local path = Pathfind.new(workspace.EnemyNPC, {
    agentCanJump = true,
    moveSpeed = 20,
    turnSpeed = 15,
    repathInterval = 0.3,
    stuckThreshold = 1.5,
})

path:Follow(player.Character, 0.3)

path.Completed:Connect(function(success, reason)
    if not success then
        print("Lost target:", reason)
    end
end)
```

### Sequential Paths

```lua
task.spawn(function()
    path:GoTo(workspace.CheckpointA)
    path.Completed:Wait()

    path:GoTo(workspace.CheckpointB)
    path.Completed:Wait()

    path:GoTo(workspace.CheckpointC)
    path.Completed:Wait()

    print("All checkpoints reached!")
end)
```

### Preview and Confirm

```lua
local preview = path:PreviewPath(workspace.Enemy)
if preview and preview.success then
    print("Path found:", #preview.waypoints, "waypoints")
    -- Show preview to player...

    -- Player confirms
    path:GoTo(workspace.Enemy)
end
```

### Runtime Config Changes

```lua
-- Enable debug during development
path:SetConfig("debug", true)

-- Slow down for a stealth section
path:SetConfig("moveSpeed", 8)

-- Speed up later
path:SetConfig("moveSpeed", 24)

-- Disable anti-stuck for scripted sequences
path:SetConfig("antiStuckEnabled", false)
```

### Handle Respawn

```lua
local path = Pathfind.new(player.Character)

player.CharacterAdded:Connect(function(newCharacter)
    path:SetCharacter(newCharacter)
    path:GoTo(workspace.SpawnPoint)
end)
```

### Waypoint Callback

```lua
path.Waypoint:Connect(function(index, waypoint)
    print("Waypoint", index, "reached!")

    -- Trigger animations, sounds, etc.
    if waypoint.action == Enum.PathWaypointAction.Jump then
        print("Jumping!")
    end
end)
```

### Full Event Monitoring

```lua
path.Started:Connect(function(target)
    print("[STARTED] Navigating to", target)
end)

path.Completed:Connect(function(success, reason)
    print("[COMPLETED]", success, reason)
end)

path.Blocked:Connect(function(idx)
    print("[BLOCKED] at waypoint", idx)
end)

path.Repath:Connect(function(attempt)
    print("[REPATH] attempt", attempt)
end)

path.Stuck:Connect(function(attempt)
    print("[STUCK] recovery", attempt)
end)

path.Failed:Connect(function(reason)
    print("[FAILED]", reason)
end)

path.Paused:Connect(function()
    print("[PAUSED]")
end)

path.Resumed:Connect(function()
    print("[RESUMED]")
end)

path.Waypoint:Connect(function(index, wp)
    print("[WAYPOINT]", index, wp.position)
end)
```

---

## Architecture

```
Pathfind (orchestrator)
├── PathManager      → PathfindingService wrapper, path computation, repathing
├── MovementEngine   → Waypoint following, LOS optimization, smooth turning
├── AntiStuck        → Stuck detection, recovery strategies
├── Events           → Custom event bus (BindableEvent wrappers)
└── Debug            → Waypoint markers, path lines, debug logging
```

### How Path Computation Works

1. `Pathfind:GoTo()` resolves the target to a `Vector3`
2. `PathManager:ComputePath()` creates a `PathfindingService` path and computes waypoints
3. Waypoints are extracted and passed to `MovementEngine:StartMoving()`
4. MovementEngine runs a Heartbeat loop that:
   - Checks distance to current waypoint
   - Calls `Humanoid:MoveTo()` once per waypoint (no jitter)
   - Smoothly rotates the character via CFrame interpolation
   - Handles jump waypoints
   - Skips waypoints via LOS raycasts
5. When all waypoints are reached, `Completed` fires

### Anti-Stuck Recovery Flow

```
Stuck detected
  ├── Attempt 1: Jump
  ├── Attempt 2: Recalculate path
  └── Attempt 3+: Random movement adjustment
       └── If all fail: Failed event
```

### Repathing Triggers

- Target moved beyond `repathThreshold` studs
- `repathInterval` seconds elapsed (for Following)
- `Path.Blocked` event from PathfindingService
- Anti-stuck recovery requesting repath

---

## License

MIT License — see [LICENSE](LICENSE).
