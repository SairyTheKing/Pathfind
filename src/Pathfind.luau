--[[
    Pathfind Library - Core Module
    
    The main Pathfind class that orchestrates pathfinding, movement,
    anti-stuck recovery, and debug visualization.
    
    Usage:
        local Pathfind = require(path.to.Pathfind)
        local path = Pathfind.new(character, { debug = true })
        
        path:GoTo(workspace.TargetPart)
        path.Completed:Connect(function(success)
            print("Path completed:", success)
        end)
    
    @author Pathfind Contributors
    @version 1.0.0
    @license MIT
]]

local RunService = game:GetService("RunService")

-- Import sub-modules
local Types = require(script.Parent.Types)
local Event = require(script.Parent.Events)
local Debug = require(script.Parent.Debug)
local AntiStuck = require(script.Parent.AntiStuck)
local PathManager = require(script.Parent.PathManager)
local MovementEngine = require(script.Parent.MovementEngine)

local Pathfind = {}
Pathfind.__index = Pathfind

-- Default configuration
local DEFAULT_CONFIG: Types.PathfindConfig = {
    agentRadius = nil,
    agentHeight = nil,
    agentCanJump = true,
    agentCanClimb = false,
    agentCanSlide = false,
    
    moveSpeed = nil,
    turnSpeed = 12,
    reachDistance = 2,
    jumpPower = nil,
    
    repathInterval = 0.5,
    repathThreshold = 4,
    maxPathAttempts = 3,
    timeout = nil,
    waypointTimeout = 4,
    
    antiStuckEnabled = true,
    stuckThreshold = 2,
    stuckRecoveryAttempts = 3,
    stuckMoveDelta = 0.5,
    
    losCheckEnabled = true,
    losRaycastParams = nil,
    
    debug = false,
    debugColor = Color3.new(0, 1, 1),      -- Cyan
    debugBlockedColor = Color3.new(1, 0, 0), -- Red
    debugLineColor = Color3.new(1, 1, 0),    -- Yellow
}

export type Pathfind = typeof(setmetatable({} :: {
    _character: Model?,
    _config: Types.PathfindConfig,
    _pathManager: PathManager.PathManager,
    _movementEngine: MovementEngine.MovementEngine,
    _antiStuck: AntiStuck.AntiStuck,
    _debug: Debug.Debug,
    _status: Types.PathStatus,
    _isPaused: boolean,
    _timeoutThread: thread?,
    _repathThread: thread?,
    _alive: boolean,
    
    -- Events
    Completed: Event.Event,
    Blocked: Event.Event,
    Repath: Event.Event,
    Stuck: Event.Event,
    Failed: Event.Event,
    Paused: Event.Event,
    Resumed: Event.Event,
    Started: Event.Event,
}, Pathfind))

function Pathfind.new(character: Model?, config: Types.PathfindConfig?): Pathfind
    local self = setmetatable({}, Pathfind)
    
    -- Merge config with defaults
    self._config = {}
    for key, value in DEFAULT_CONFIG do
        (self._config :: any)[key] = (config :: any)?.[key] or value
    end
    
    self._character = character
    self._status = "idle"
    self._isPaused = false
    self._timeoutThread = nil
    self._repathThread = nil
    self._alive = true
    
    -- Initialize events
    self.Completed = Event.new()
    self.Blocked = Event.new()
    self.Repath = Event.new()
    self.Stuck = Event.new()
    self.Failed = Event.new()
    self.Paused = Event.new()
    self.Resumed = Event.new()
    self.Started = Event.new()
    
    -- Initialize subsystems
    self._debug = Debug.new()
    self._debug:SetEnabled(self._config.debug or false)
    
    self._pathManager = PathManager.new({
        agentRadius = self._config.agentRadius,
        agentHeight = self._config.agentHeight,
        agentCanJump = self._config.agentCanJump,
        agentCanClimb = self._config.agentCanClimb,
        agentCanSlide = self._config.agentCanSlide,
        repathInterval = self._config.repathInterval,
        repathThreshold = self._config.repathThreshold,
        maxPathAttempts = self._config.maxPathAttempts,
    })
    
    self._movementEngine = MovementEngine.new({
        turnSpeed = self._config.turnSpeed,
        reachDistance = self._config.reachDistance,
        moveSpeed = self._config.moveSpeed,
        jumpPower = self._config.jumpPower,
        losCheckEnabled = self._config.losCheckEnabled,
        losRaycastParams = self._config.losRaycastParams,
    })
    
    self._antiStuck = AntiStuck.new({
        enabled = self._config.antiStuckEnabled,
        threshold = self._config.stuckThreshold,
        moveDelta = self._config.stuckMoveDelta,
        maxRecoveryAttempts = self._config.stuckRecoveryAttempts,
        onStuck = function(attempt: number)
            self.Stuck:Fire(attempt)
            self._debug:Log("Stuck detected (attempt " .. attempt .. ")", "WARN")
        end,
        onRecoveryFailed = function(reason: string)
            self:_fail("Anti-stuck recovery failed: " .. reason)
        end,
    })
    
    -- Setup movement callbacks
    self._movementEngine:OnReachWaypoint(function(index: number, waypoint: any)
        self:_onWaypointReached(index, waypoint)
    end)
    
    self._movementEngine:OnPathCompleted(function(success: boolean)
        self:_onPathFinished(success)
    end)
    
    -- Setup blocked callback
    self._pathManager:SetBlockedCallback(function(waypointIndex: number)
        self._debug:Log("Path blocked at waypoint " .. waypointIndex, "WARN")
        self.Blocked:Fire(waypointIndex)
    end)
    
    -- Watch for character changes
    if character then
        self:_setupCharacterWatch()
    end
    
    self._debug:Log("Pathfind instance created")
    
    return self
end

function Pathfind:SetCharacter(character: Model?)
    self._character = character
    self._movementEngine:SetCharacter(character)
    if character then
        self:_setupCharacterWatch()
    end
end

function Pathfind:_setupCharacterWatch()
    if not self._character then return end
    
    -- Watch for character being removed (respawn handling)
    self._character.Destroying:Connect(function()
        if self._status == "moving" then
            self._debug:Log("Character destroyed, pausing path", "WARN")
            self:Stop()
        end
        self._movementEngine:SetCharacter(nil)
    end)
end

-- =========================================================================
-- Public API
-- =========================================================================

function Pathfind:GoTo(target: Vector3 | BasePart | Model, timeout: number?): Pathfind
    if not self._alive then return self end
    
    -- Stop any current movement
    if self._status == "moving" then
        self:Stop()
    end
    
    -- Resolve target position
    local targetPos = self:_resolveTargetPosition(target)
    if not targetPos then
        self:_fail("Invalid target")
        return self
    end
    
    -- Validate character
    if not self._movementEngine:_isCharacterValid() then
        self._debug:Log("Character is invalid, cannot start path", "WARN")
        self:_fail("Character is invalid")
        return self
    end
    
    self._debug:Log("GoTo: " .. tostring(targetPos))
    self.Started:Fire(target)
    
    -- Compute and start path
    self:_computeAndMove(targetPos, target, timeout or self._config.timeout)
    
    return self
end

function Pathfind:Follow(target: Instance, repathInterval: number?): Pathfind
    if not self._alive then return self end
    
    -- Stop any current movement
    if self._status == "moving" then
        self:Stop()
    end
    
    -- Validate target
    if not target or not target.Parent then
        self:_fail("Invalid follow target")
        return self
    end
    
    -- Validate character
    if not self._movementEngine:_isCharacterValid() then
        self:_fail("Character is invalid")
        return self
    end
    
    local interval = repathInterval or self._config.repathInterval or 0.5
    
    self._debug:Log("Following: " .. target:GetFullName())
    self.Started:Fire(target)
    
    -- Start follow loop
    task.spawn(function()
        while self._alive and target and target.Parent do
            if not self._alive then break end
            if self._isPaused then task.wait(0.1) continue end
            
            -- Get target position
            local targetPos = self:_resolveTargetPosition(target)
            if not targetPos then
                self:_fail("Follow target lost")
                break
            end
            
            -- Check if we should repath
            local currentPos = self._movementEngine:_getCharacterPosition()
            if currentPos then
                local shouldRepath = self._pathManager:ShouldRepathForMovingTarget(currentPos, targetPos)
                
                if shouldRepath then
                    self._debug:Log("Repathing for moving target")
                    self.Repath:Fire(self._pathManager._pathAttempts)
                    self:_computeAndMove(targetPos, target, nil)
                end
            end
            
            task.wait(interval)
        end
        
        -- Fire Completed when follow loop ends naturally
        if self._alive then
            self.Completed:Fire(false, "Follow loop ended")
            self._status = "idle"
        end
    end)
    
    return self
end

function Pathfind:Stop()
    if not self._alive then return end
    
    self._debug:Log("Stopping")
    self._status = "idle"
    self._isPaused = false
    self._movementEngine:Stop()
    self._pathManager:Clear()
    self._antiStuck:Stop()
    self:_cancelThreads()
    self._debug:Clear()
end

function Pathfind:Pause()
    if not self._alive or self._status ~= "moving" then return end
    
    self._debug:Log("Pausing")
    self._isPaused = true
    self._movementEngine:Pause()
    self.Paused:Fire()
end

function Pathfind:Resume()
    if not self._alive or not self._isPaused then return end
    
    self._debug:Log("Resuming")
    self._isPaused = false
    self._movementEngine:Resume()
    self.Resumed:Fire()
end

function Pathfind:IsMoving(): boolean
    return self._movementEngine:IsMoving()
end

function Pathfind:GetStatus(): Types.PathStatus
    return self._status
end

function Pathfind:GetProgress(): number
    return self._movementEngine:GetProgress()
end

-- =========================================================================
-- Configuration
-- =========================================================================

function Pathfind:SetConfig(key: string, value: any)
    (self._config :: any)[key] = value
    
    -- Propagate to subsystems
    if key == "debug" then
        self._debug:SetEnabled(value)
    elseif key == "antiStuckEnabled" then
        self._antiStuck:SetEnabled(value)
    end
end

function Pathfind:GetConfig(key: string): any
    return (self._config :: any)[key]
end

function Pathfind:EnableDebug(enabled: boolean)
    self._config.debug = enabled
    self._debug:SetEnabled(enabled)
end

-- =========================================================================
-- Internal - Path Computation
-- =========================================================================

function Pathfind:_computeAndMove(targetPos: Vector3, originalTarget: any, timeout: number?)
    if not self._alive then return end
    
    self._status = "computing"
    
    -- Get start position
    local startPos = self._movementEngine:_getCharacterPosition()
    if not startPos then
        self:_fail("Cannot get character position")
        return
    end
    
    -- Compute path
    local path = self._pathManager:ComputePath(startPos, targetPos)
    
    if not path or path.status ~= Enum.PathStatus.Success then
        self._pathManager:IncrementAttempts()
        
        if self._pathManager:HasExceededMaxAttempts() then
            self:_fail("No path found after " .. tostring(self._config.maxPathAttempts) .. " attempts")
            return
        end
        
        -- Retry
        self._debug:Log("Path computation failed, retrying...", "WARN")
        task.delay(0.3, function()
            if self._alive and self._status == "computing" then
                self:_computeAndMove(targetPos, originalTarget, timeout)
            end
        end)
        return
    end
    
    -- Validate we have waypoints
    if #path.waypoints < 2 then
        self:_fail("Path too short")
        return
    end
    
    -- Remove first waypoint (it's usually the start position)
    table.remove(path.waypoints, 1)
    
    -- Draw debug visualization
    if self._config.debug then
        self._debug:Clear()
        self._debug:DrawWaypoints(path.waypoints, self._config.debugColor, self._config.debugLineColor)
    end
    
    -- Start movement
    self._status = "moving"
    self._antiStuck:Start()
    self._movementEngine:StartMoving(path.waypoints, targetPos)
    
    -- Start timeout if configured
    if timeout and timeout > 0 then
        self:_startTimeout(timeout)
    end
    
    -- Start repath checker
    self:_startRepathChecker(originalTarget)
end

function Pathfind:_startTimeout(seconds: number)
    self:_cancelThread("timeout")
    self._timeoutThread = task.delay(seconds, function()
        if self._alive and self._status == "moving" then
            self._debug:Log("Path timed out after " .. seconds .. "s", "WARN")
            self:_fail("Timeout")
        end
    end)
end

function Pathfind:_startRepathChecker(originalTarget: any)
    self:_cancelThread("repath")
    self._repathThread = task.spawn(function()
        while self._alive and self._status == "moving" do
            task.wait(self._config.repathInterval or 0.5)
            
            if not self._alive or self._status ~= "moving" or self._isPaused then
                break
            end
            
            local currentPos = self._movementEngine:_getCharacterPosition()
            if not currentPos then continue end
            
            -- Check if we should repath for a moving target
            if originalTarget and typeof(originalTarget) == "Instance" then
                local targetPos = self:_resolveTargetPosition(originalTarget)
                if targetPos then
                    local shouldRepath = self._pathManager:ShouldRepathForMovingTarget(currentPos, targetPos)
                    if shouldRepath then
                        self._debug:Log("Repathing for moved target")
                        self.Repath:Fire(self._pathManager._pathAttempts)
                        self:_computeAndMove(targetPos, originalTarget, nil)
                        return
                    end
                end
            end
            
            -- Update anti-stuck
            self._antiStuck:UpdatePosition(currentPos)
            
            if self._antiStuck:IsStuck() then
                local strategy = self._antiStuck:AttemptRecovery()
                if strategy then
                    self._debug:Log("Anti-stuck recovery: " .. strategy, "WARN")
                    
                    if strategy == "jump" then
                        local humanoid = self._movementEngine:GetHumanoid()
                        if humanoid then
                            humanoid.Jump = true
                        end
                    elseif strategy == "repath" then
                        local goal = self._pathManager:GetCurrentGoal()
                        if goal then
                            self.Repath:Fire(self._pathManager._pathAttempts)
                            self:_computeAndMove(goal, originalTarget, nil)
                            return
                        end
                    elseif strategy == "adjust" then
                        local rootPart = self._movementEngine:GetRootPart()
                        if rootPart then
                            local adjustDir = self._antiStuck:GetAdjustmentDirection()
                            local humanoid = self._movementEngine:GetHumanoid()
                            if humanoid then
                                humanoid:MoveTo(rootPart.Position + adjustDir)
                            end
                        end
                    end
                end
            end
        end
    end)
end

function Pathfind:_cancelThreads(threadType: string?)
    if threadType == "timeout" or not threadType then
        if self._timeoutThread then
            task.cancel(self._timeoutThread)
            self._timeoutThread = nil
        end
    end
    
    if threadType == "repath" or not threadType then
        if self._repathThread then
            task.cancel(self._repathThread)
            self._repathThread = nil
        end
    end
end

-- =========================================================================
-- Internal - Movement Callbacks
-- =========================================================================

function Pathfind:_onWaypointReached(index: number, waypoint: any)
    self._debug:Log("Waypoint " .. index .. " reached")
    
    -- Update anti-stuck on waypoint reached
    self._antiStuck:Reset()
    
    -- Draw current waypoint marker in debug
    if self._config.debug then
        self._debug:DrawCurrentWaypoint(waypoint.position, self._config.debugColor)
    end
end

function Pathfind:_onPathFinished(success: boolean)
    self._antiStuck:Stop()
    self:_cancelThreads()
    
    if success then
        self._debug:Log("Path completed successfully!")
    else
        self._debug:Log("Path failed", "WARN")
    end
    
    self.Completed:Fire(success)
    self._status = "idle"
end

function Pathfind:_fail(reason: string)
    self._debug:Log("Failed: " .. reason, "ERROR")
    self._status = "failed"
    self._antiStuck:Stop()
    self:_cancelThreads()
    self._movementEngine:Stop()
    self._pathManager:Clear()
    self.Failed:Fire(reason)
    self._status = "idle"
end

-- =========================================================================
-- Internal - Utilities
-- =========================================================================

function Pathfind:_resolveTargetPosition(target: Vector3 | Instance): Vector3?
    if typeof(target) == "Vector3" then
        return target
    end
    
    if typeof(target) == "Instance" then
        if target:IsA("BasePart") then
            return target.Position
        elseif target:IsA("Model") then
            local primaryPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
            if primaryPart then
                return primaryPart.Position
            end
        elseif target:IsA("Attachment") then
            return target.WorldPosition
        end
        
        -- Try to find any part
        local part = target:FindFirstChildWhichIsA("BasePart")
        if part then
            return part.Position
        end
    end
    
    return nil
end

-- =========================================================================
-- Cleanup
-- =========================================================================

function Pathfind:Destroy()
    if not self._alive then return end
    
    self._alive = false
    self:Stop()
    
    self.Completed:Destroy()
    self.Blocked:Destroy()
    self.Repath:Destroy()
    self.Stuck:Destroy()
    self.Failed:Destroy()
    self.Paused:Destroy()
    self.Resumed:Destroy()
    self.Started:Destroy()
    
    self._debug:Log("Pathfind instance destroyed")
    
    self._debug:Destroy()
    self._movementEngine:Destroy()
    
    self._debug = nil :: any
    self._movementEngine = nil :: any
    self._pathManager = nil :: any
    self._antiStuck = nil :: any
    self._character = nil
end

return Pathfind
