-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Host-neutral layout refresh lifecycle. This does not own a Blizzard category,
-- page, scroll frame, Section, or setting. It only schedules bounded remeasure
-- passes when a page's viewport/content geometry has changed.
local Scheduler = {}
TBU.SettingsPageMeasure = Scheduler

function Scheduler:Create(owner, updateMeasure, opts)
    opts = opts or {}
    local autoRefresh = opts.autoRefresh ~= false
    local passes = tonumber(opts.passes) or 4
    local defer = opts.defer == true

    if not autoRefresh then
        return function() updateMeasure() end
    end

    local measureFrame = CreateFrame("Frame", nil, owner)
    measureFrame:Hide()
    local remaining = 0
    measureFrame:SetScript("OnUpdate", function(self)
        updateMeasure()
        remaining = remaining - 1
        if remaining <= 0 then self:Hide() end
    end)

    return function()
        -- Deferred requests coalesce geometry changes made within a frame.
        -- The ordinary (non-deferred) path retains its immediate refresh.
        remaining = passes
        if not defer then updateMeasure() end
        measureFrame:Show()
    end
end
