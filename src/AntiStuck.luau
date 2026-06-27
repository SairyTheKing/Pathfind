--[[
    Pathfind Library - Anti-Stuck System
    
    Detects when a character is stuck and attempts recovery.
    Recovery strategies: jump, recalculate path, small movement adjustments.
    
    @author Pathfind Contributors
    @version 1.2.0
    @license MIT
]]

local AntiStuck = {}
AntiStuck.__index = AntiStuck

export type AntiStuck = typeof(setmetatable({} :: {
    _enabled: boolean,
    _lastPosition: Vector3?,
    _lastMoveTime: number,
    _recoveryAttempts: number,
    _maxRecoveryAttempts: number,
    _stuckThreshold: number,
    _stuckMoveDelta: number,
    _onStuck: ((attempt: number) -> ())?,
    _onRecoveryFailed: ((reason: string) -> ())?,
    _active: boolean,
}, AntiStuck))

function AntiStuck.new(config: {
    enabled: boolean?,
    threshold: number?,
    moveDelta: number?,
    maxRecoveryAttempts: number?,
    onStuck: ((attempt: number) -> ())?,
    onRecoveryFailed: ((reason: string) -> ())?,
}?): AntiStuck
    local self = setmetatable({}, AntiStuck)
    
    config = config or {}
    self._enabled = config.enabled ~= false
    self._lastPosition = nil
    self._lastMoveTime = os.clock()
    self._recoveryAttempts = 0
    self._maxRecoveryAttempts = config.maxRecoveryAttempts or 3
    self._stuckThreshold = config.threshold or 2
    self._stuckMoveDelta = config.moveDelta or 0.5
    self._onStuck = config.onStuck
    self._onRecoveryFailed = config.onRecoveryFailed
    self._active = false
    
    return self
end

function AntiStuck:SetEnabled(enabled: boolean)
    self._enabled = enabled
    if not enabled then
        self:Reset()
    end
end

function AntiStuck:Start()
    self._active = true
    self._lastPosition = nil
    self._lastMoveTime = os.clock()
    self._recoveryAttempts = 0
end

function AntiStuck:Stop()
    self._active = false
    self:Reset()
end

function AntiStuck:Reset()
    self._lastPosition = nil
    self._lastMoveTime = os.clock()
    self._recoveryAttempts = 0
end

function AntiStuck:UpdatePosition(position: Vector3)
    if not self._active then return end
    
    local now = os.clock()
    
    if self._lastPosition then
        local delta = (position - self._lastPosition).Magnitude
        if delta >= self._stuckMoveDelta then
            -- Character moved enough, reset the timer
            self._lastMoveTime = now
            self._recoveryAttempts = 0
        end
    end
    
    self._lastPosition = position
end

function AntiStuck:IsStuck(): boolean
    if not self._enabled or not self._active then
        return false
    end
    
    local elapsed = os.clock() - self._lastMoveTime
    return elapsed >= self._stuckThreshold
end

function AntiStuck:GetRecoveryAttempt(): number
    return self._recoveryAttempts
end

function AntiStuck:AttemptRecovery(): string?
    if not self._active then return nil end
    
    self._recoveryAttempts += 1
    
    if self._recoveryAttempts > self._maxRecoveryAttempts then
        if self._onRecoveryFailed then
            self._onRecoveryFailed("Max recovery attempts exceeded")
        end
        return nil
    end
    
    -- Fire stuck event
    if self._onStuck then
        self._onStuck(self._recoveryAttempts)
    end
    
    -- Recovery strategy based on attempt number
    local strategy: string
    
    if self._recoveryAttempts == 1 then
        -- First attempt: try jumping
        strategy = "jump"
    elseif self._recoveryAttempts == 2 then
        -- Second attempt: request path recalculation
        strategy = "repath"
    else
        -- Third+ attempt: small random movement adjustment
        strategy = "adjust"
    end
    
    return strategy
end

function AntiStuck:GetAdjustmentDirection(): Vector3
    -- Return a small random horizontal adjustment
    local angle = math.random() * math.pi * 2
    return Vector3.new(math.cos(angle), 0, math.sin(angle)) * 2
end

return AntiStuck
