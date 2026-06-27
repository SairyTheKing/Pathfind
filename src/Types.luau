--[[
    Pathfind Library - Type Definitions
    
    Contains all type definitions used throughout the Pathfind library.
    
    @author Pathfind Contributors
    @version 1.0.0
    @license MIT
    @date 2026
]]

export type PathfindConfig = {
    -- Agent parameters for PathfindingService
    agentRadius: number?,
    agentHeight: number?,
    agentCanJump: boolean?,
    agentCanClimb: boolean?,
    agentCanSlide: boolean?,
    
    -- Movement settings
    moveSpeed: number?,             -- Override humanoid walk speed (nil = use current)
    turnSpeed: number?,             -- How fast the character rotates (radians/sec, default = 12)
    reachDistance: number?,          -- Distance to consider a waypoint reached (default = 2)
    jumpPower: number?,             -- Override jump power (nil = use humanoid default)
    
    -- Path settings
    repathInterval: number?,        -- Seconds between path recalculations when following (default = 0.5)
    repathThreshold: number?,       -- Studs the target must move before repathing (default = 4)
    maxPathAttempts: number?,       -- Max failed path attempts before giving up (default = 3)
    timeout: number?,               -- Max seconds for entire path (nil = no timeout)
    waypointTimeout: number?,       -- Max seconds per waypoint (default = 4)
    
    -- Anti-stuck settings
    antiStuckEnabled: boolean?,     -- Enable anti-stuck detection (default = true)
    stuckThreshold: number?,        -- Seconds before considered stuck (default = 2)
    stuckRecoveryAttempts: number?, -- Max recovery attempts before Failed event (default = 3)
    stuckMoveDelta: number?,        -- Min studs moved to not be "stuck" (default = 0.5)
    
    -- Line-of-sight settings
    losCheckEnabled: boolean?,      -- Enable line-of-sight waypoint skipping (default = true)
    losRaycastParams: RaycastParams?, -- Custom raycast params for LOS checks
    
    -- Debug settings
    debug: boolean?,                -- Enable debug visualization (default = false)
    debugColor: Color3?,            -- Color for debug waypoints (default = Cyan)
    debugBlockedColor: Color3?,     -- Color for blocked/failed points (default = Red)
    debugLineColor: Color3?,        -- Color for debug lines (default = Yellow)
}

export type WaypointData = {
    position: Vector3,
    action: Enum.PathWaypointAction,
    index: number,
}

export type PathStatus = "idle" | "computing" | "moving" | "paused" | "blocked" | "completed" | "failed"

export type PathfindEvents = {
    Completed: RBXScriptSignal,     -- (success: boolean, reason: string?)
    Blocked: RBXScriptSignal,       -- (waypointIndex: number)
    Repath: RBXScriptSignal,        -- (pathIndex: number)
    Stuck: RBXScriptSignal,         -- (recoveryAttempt: number)
    Failed: RBXScriptSignal,        -- (reason: string)
    Paused: RBXScriptSignal,        -- ()
    Resumed: RBXScriptSignal,       -- ()
    Started: RBXScriptSignal,       -- (target: Vector3 | Instance)
}

return nil
