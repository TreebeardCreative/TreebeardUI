-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Common movable window host. Content and diagnostic logging live elsewhere.
-- Shared border/title interaction deliberately resembles movable group drag handles,
-- but uses the current allEverythingTestVariable style value and is never controlled by Group lock state.
TBU.WindowFrame = {}
local Host = TBU.WindowFrame
local Styles = TBU.WindowStyles

local function EffectiveScale(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    return type(scale) == "number" and scale > 0 and scale or 1
end

local function SnapToPixel(value, scale)
    scale = type(scale) == "number" and scale > 0 and scale or 1
    return math.floor((tonumber(value) or 0) * scale + 0.5) / scale
end

local POSITION_ANCHORS = {
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

local function SnapWindowRectangle(frame, preserveLogicalSize)
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    local parentLeft, parentRight = UIParent:GetLeft(), UIParent:GetRight()
    local parentBottom, parentTop = UIParent:GetBottom(), UIParent:GetTop()
    if not (left and right and bottom and top and parentLeft and parentRight
        and parentBottom and parentTop) then return false end

    -- Anchor offsets use the parent's scale; local frame dimensions use the
    -- frame's effective scale. Align all four visible edges, then derive the
    -- dimensions from those integer-pixel boundaries.
    local parentScale = EffectiveScale(UIParent)
    local frameScale = EffectiveScale(frame)
    local leftPixel = math.floor((left - parentLeft) * parentScale + 0.5)
    local rightPixel = math.floor((right - parentLeft) * parentScale + 0.5)
    local bottomPixel = math.floor((bottom - parentBottom) * parentScale + 0.5)
    local topPixel = math.floor((top - parentBottom) * parentScale + 0.5)
    local widthPixels = math.max(1, rightPixel - leftPixel)
    local heightPixels = math.max(1, topPixel - bottomPixel)

    frame:ClearAllPoints()
    -- Keep the snapped rectangle stable while using the consumer-selected
    -- growth anchor. Fixed windows retain the historical TOPRIGHT anchor.
    local anchor = frame.positionAnchorMode == "screenAdaptive"
        and POSITION_ANCHORS[frame.positionAnchorPoint] and frame.positionAnchorPoint or "TOPRIGHT"
    local x
    if anchor:find("LEFT", 1, true) then
        x = leftPixel / parentScale
    else
        x = rightPixel / parentScale - (parentRight - parentLeft)
    end
    local y
    if anchor:find("TOP", 1, true) then
        y = topPixel / parentScale - (parentTop - parentBottom)
    else
        y = bottomPixel / parentScale
    end
    frame:SetPoint(anchor, UIParent, anchor, x, y)
    frame:SetSize(widthPixels / frameScale, heightPixels / frameScale)
    if not preserveLogicalSize then
        if frame.expandedWidth ~= nil then frame.expandedWidth = frame:GetWidth() end
        if frame.expandedHeight ~= nil and not frame.collapsed then frame.expandedHeight = frame:GetHeight() end
    end
    return true
end

local function GetScreenAdaptiveAnchor(frame)
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    local screenLeft, screenRight = UIParent:GetLeft(), UIParent:GetRight()
    local screenBottom, screenTop = UIParent:GetBottom(), UIParent:GetTop()
    if not (left and right and bottom and top and screenLeft and screenRight
        and screenBottom and screenTop) then
        return frame.positionAnchorPoint or "TOPRIGHT"
    end

    local horizontal = (left + right) / 2 < (screenLeft + screenRight) / 2 and "LEFT" or "RIGHT"
    local vertical = (bottom + top) / 2 < (screenBottom + screenTop) / 2 and "BOTTOM" or "TOP"
    return vertical .. horizontal
end

local function ClampFrameBodyToScreen(frame)
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    local screenLeft, screenRight = UIParent:GetLeft(), UIParent:GetRight()
    local screenBottom, screenTop = UIParent:GetBottom(), UIParent:GetTop()
    if not (left and right and bottom and top and screenLeft and screenRight
        and screenBottom and screenTop) then
        return false
    end

    local offsetX, offsetY = 0, 0
    if right - left <= screenRight - screenLeft then
        if left < screenLeft then offsetX = screenLeft - left end
        if right + offsetX > screenRight then offsetX = screenRight - right end
    end
    if top - bottom <= screenTop - screenBottom then
        if bottom < screenBottom then offsetY = screenBottom - bottom end
        if top + offsetY > screenTop then offsetY = screenTop - top end
    end
    if math.abs(offsetX) <= 0.01 and math.abs(offsetY) <= 0.01 then return false end

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point or not relativeTo or not relativePoint
        or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x + offsetX, y + offsetY)
    return true
end

-- One ordered stack per addon, not a continuously incrementing frame-level
-- counter. Keeps windows at DIALOG while guaranteeing the selected window
-- draws above other addon windows, including border handles and buttons.
Host.windows = {}

function Host:BringToFront(window)
    if not window then return end
    for i = #self.windows, 1, -1 do
        if self.windows[i] == window then table.remove(self.windows, i) end
    end
    self.windows[#self.windows + 1] = window
    for i, frame in ipairs(self.windows) do
        local base = 35 + (i - 1) * 64
        frame:SetFrameLevel(base)
        if frame.frameHeader then frame.frameHeader:SetFrameLevel(base + 1) end
        if frame.content then frame.content:SetFrameLevel(base + 1) end
        if frame.windowBodyBorder then frame.windowBodyBorder:SetFrameLevel(base + 8) end
        if frame.windowEdges then
            for _, edge in ipairs(frame.windowEdges) do edge:SetFrameLevel(base + 8) end
        end
        if frame.closeButton then frame.closeButton:SetFrameLevel(base + 22) end
        if frame.collapseButton then frame.collapseButton:SetFrameLevel(base + 22) end
        if frame.resizeGrips then
            for _, grip in ipairs(frame.resizeGrips) do grip:SetFrameLevel(base + 18) end
        elseif frame.resizeGrip then
            frame.resizeGrip:SetFrameLevel(base + 18)
        end
        if frame.OnWindowLevelChanged then frame:OnWindowLevelChanged(base) end
    end
end

local function CharacterWindowState(owner)
    local state = TBU:GetWindowState(owner)
    if not state then return nil end
    state.windowPositions = state.windowPositions or {}
    state.windowCollapsed = state.windowCollapsed or {}
    -- Preserve positions saved by earlier development builds.
    state.frameHeaderPositions = state.frameHeaderPositions or state.windowTitlePositions or {}
    state.windowSizes = state.windowSizes or {}
    return state
end

local function ResolveFrameHeaderPadding(style, requested)
    local defaults = style.frameHeaderPadding or {}
    requested = type(requested) == "table" and requested or {}
    local horizontal = tonumber(requested.horizontal or requested.x)
    local vertical = tonumber(requested.vertical or requested.y)
    return {
        left = math.max(0, tonumber(requested.left) or horizontal
            or tonumber(defaults.left) or 13),
        right = math.max(0, tonumber(requested.right) or horizontal
            or tonumber(defaults.right) or 8),
        top = math.max(0, tonumber(requested.top) or vertical
            or tonumber(defaults.top) or 2),
        bottom = math.max(0, tonumber(requested.bottom) or vertical
            or tonumber(defaults.bottom) or 2),
    }
end

-- Title chrome is an optional component of the window assembly. Keeping its
-- construction separate lets a consumer request a bare frame without
-- creating title controls or a title label.
local function CreateFrameHeader(parent, title, style, outline, padding)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(style.titleHeight)
    header:EnableMouse(true)
    header.bg = Styles:CreateFlatTexture(header, "BACKGROUND", Styles:GetMainCanvasColor(style))
    header.bg:SetAllPoints(header)

    local heading = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("LEFT", header, "LEFT", padding.left, 0)
    heading:SetText(title or "")
    local function repaintHeading(target)
        target:SetTextColor(unpack(Styles:GetTextColor("header", target)))
    end
    Styles:RegisterVisual(heading, repaintHeading)
    repaintHeading(heading)
    heading:SetJustifyH("LEFT")
    heading:SetJustifyV("MIDDLE")
    heading:SetWordWrap(true)
    if heading.SetNonSpaceWrap then heading:SetNonSpaceWrap(true) end
    header.label = heading
    if outline then
        local edgeSize = style.edgeSize or 1
        local edges = {}
        local function AddEdge(point1, relativePoint1, point2, relativePoint2, width, height)
            local edge = Styles:CreateFlatTexture(header, "OVERLAY", Styles:GetWindowBorderColor(style))
            edge:SetPoint(point1, header, relativePoint1, 0, 0)
            edge:SetPoint(point2, header, relativePoint2, 0, 0)
            if width then edge:SetWidth(width) end
            if height then edge:SetHeight(height) end
            edges[#edges + 1] = edge
            return edge
        end
        AddEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, edgeSize)
        AddEdge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", edgeSize, nil)
        AddEdge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", edgeSize, nil)
        AddEdge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, edgeSize)
        header.borderEdges = edges
    end
    return header, heading
end

local DEFAULTS = {
    sizingMode = "user",
    minimumWidth = 15,
    minimumHeight = 15,
    movable = true,
    hover = true,
    dragRegion = "border",
    cornerResize = true,
    frameHeaderVisibility = "none",
    frameHeaderPosition = "top",
    frameHeaderWidthPercent = 100,
    frameHeaderControls = false,
}

local function NormalizeCreateConfig(config)
    config = type(config) == "table" and config or {}
    local sizing = type(config.sizing) == "table" and config.sizing or {}
    local initial = type(sizing.initial) == "table" and sizing.initial or {}
    local minimum = type(sizing.minimum) == "table" and sizing.minimum or {}
    local position = type(sizing.position) == "table" and sizing.position or {}
    local interaction = type(config.interaction) == "table" and config.interaction or {}
    local resize = interaction.resize
    local frameHeader = type(config.frameHeader) == "table" and config.frameHeader or nil
    local titleControls = frameHeader and type(frameHeader.controls) == "table" and frameHeader.controls or {}
    local surface = type(config.surface) == "table" and config.surface or {}
    local options = {
        frameHeader = frameHeader and (frameHeader.visibility or "always") or "never",
        -- Keep an omitted position unset here so consumer-saved position can
        -- take precedence; fall back to the framework default during create.
        frameHeaderPosition = frameHeader and frameHeader.position,
        frameHeaderAnchor = frameHeader and frameHeader.anchor,
        frameHeaderWidth = frameHeader and frameHeader.width and
            (frameHeader.width.mode == "content" and "content" or frameHeader.width.value),
        frameHeaderPadding = frameHeader and frameHeader.padding,
        frameHeaderControlGap = frameHeader and frameHeader.controlGap,
        closeButton = titleControls.close == true,
        collapseButton = titleControls.minimize == true,
        movementLockButton = titleControls.lock == true,
        movable = interaction.movable ~= false,
        onMovableChanged = type(interaction.onMovableChanged) == "function"
            and interaction.onMovableChanged or nil,
        hoverEnabled = interaction.hover ~= false,
        -- Border hover is independent: it must not disable title reveal,
        -- active header canvas, or resize-grip hover feedback.
        borderHoverEnabled = interaction.borderHover ~= false,
        dragRegion = interaction.dragRegion or DEFAULTS.dragRegion,
        minWidth = minimum.width,
        minHeight = minimum.height,
        frameBorder = surface.frameBorder,
        surface = surface,
        contentPadding = config.contentPadding,
        contentGap = config.contentGap,
    }
    if resize == false then
        options.resizeHandles = false
    elseif type(resize) == "table" then
        options.resizeHandles = {
            corner = resize.corner ~= false,
            horizontal = resize.horizontal,
            vertical = resize.vertical,
        }
    elseif sizing.mode == "consumer" then
        options.resizeHandles = false
    end

    local anchor = position.anchor
    if type(anchor) ~= "table" then anchor = {} end
    return {
        key = config.id,
        title = config.title,
        owner = config.owner,
        width = tonumber(initial.width) or DEFAULTS.minimumWidth,
        height = tonumber(initial.height) or DEFAULTS.minimumHeight,
        defaultX = tonumber(position.x) or 0,
        defaultY = tonumber(position.y) or 0,
        positionMode = position.mode == "screenAdaptive" and "screenAdaptive" or "fixed",
        minWidth = tonumber(minimum.width) or DEFAULTS.minimumWidth,
        minHeight = tonumber(minimum.height) or DEFAULTS.minimumHeight,
        minimumMode = minimum.mode == "content" and "content" or "fixed",
        sizingMode = sizing.mode or DEFAULTS.sizingMode,
        positionPoint = anchor.point or "CENTER",
        relativePoint = anchor.relativePoint or "CENTER",
        options = options,
    }
end

function Host:Create(config)
    local normalized = NormalizeCreateConfig(config)
    local key, title, width, height = normalized.key, normalized.title,
        normalized.width, normalized.height
    local defaultX, defaultY = normalized.defaultX, normalized.defaultY
    local minWidth, minHeight, owner = normalized.minWidth, normalized.minHeight, normalized.owner
    local options = normalized.options
    -- The basic frame has no title chrome. Consumers assemble title bars
    -- explicitly so its controls and occupied space are visible choices.
    local frameHeaderMode = options.frameHeader
    if frameHeaderMode == nil then frameHeaderMode = "never" end
    if frameHeaderMode ~= "always" and frameHeaderMode ~= "hover" and frameHeaderMode ~= "never" then
        frameHeaderMode = "never"
    end
    -- Hover treatment follows the draggable perimeter/title surfaces by
    -- default. Consumers can request the legacy whole-frame hover behavior.
    local boundaryHoverMode = options.hoverRegions ~= false
    local hoverEnabled = options.hoverEnabled ~= false
    local borderHoverEnabled = options.borderHoverEnabled ~= false
    local frameBorderMode = options.frameBorder
    if frameBorderMode ~= "body" and frameBorderMode ~= "none" then
        frameBorderMode = nil
    end
    local frameHeaderWidthOption = options.frameHeaderWidth
    local frameHeaderWidthMode = frameHeaderWidthOption == "content" and "content" or "percent"
    local frameHeaderWidthPercent = tonumber(frameHeaderWidthOption) or DEFAULTS.frameHeaderWidthPercent
    if frameHeaderWidthPercent <= 0 then frameHeaderWidthPercent = 100 end
    local frameHeaderAnchor = options.frameHeaderAnchor
    if frameHeaderAnchor ~= "left" and frameHeaderAnchor ~= "center" and frameHeaderAnchor ~= "right"
        and frameHeaderAnchor ~= "top" and frameHeaderAnchor ~= "bottom" then
        frameHeaderAnchor = "left"
    end
    local preset = nil -- use live per-owner preset for window chrome
    local style = Styles:Get(Styles:GetConsumerPreset(owner))
    local frameHeaderPadding = ResolveFrameHeaderPadding(style, options.frameHeaderPadding)
    local frameHeaderControlGap = math.max(0, tonumber(options.frameHeaderControlGap)
        or tonumber(style.frameHeaderControlGap) or 5)
    -- Keep the basic body and its optional title as sibling surfaces. The
    -- body can fade out while collapsed without also hiding its title chrome.
    local assembly = CreateFrame("Frame", nil, UIParent)
    assembly:SetSize(1, 1)
    assembly:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    assembly:SetFrameStrata("DIALOG")
    assembly:EnableMouse(false)
    assembly:SetClampedToScreen(false)
    assembly.storageOwner = owner
    local root = TBU:CreateBackdropFrame("Frame", assembly)
    root.frameAssembly = assembly
    root._tbuHideWindowBorder = frameBorderMode == "none"
    root._tbuSurfaceOptions = options.surface or {}
    root.windowKey = key
    root.storageOwner = owner
    root.positionAnchorMode = normalized.positionMode
    root.positionAnchorPoint = "TOPRIGHT"
    root.defaultWindowWidth = width
    root.defaultWindowHeight = height
    function root:BringToFront() Host:BringToFront(self) end
    local hovering, dragging, resizing = false, false, false
    -- Native UI scale is the default. The sandbox may explicitly apply an
    -- independent window scale through SetWindowUIScale without changing UIParent.
    function root:SetWindowUIScale(scale)
        scale = tonumber(scale) or 1
        scale = math.max(0.75, math.min(1.10, scale))
        self:SetScale(scale)
        if self.frameHeader then self.frameHeader:SetScale(scale) end
        self:SetClampedToScreen(true)
        SnapWindowRectangle(self, true)
        if self.frameHeader then self:SetFrameHeaderPosition(self.frameHeaderPosition, self.frameHeaderAnchor) end
    end
    local configuredMinWidth = tonumber(options.minWidth)
    local configuredMinHeight = tonumber(options.minHeight)
    root.minimumWidth = configuredMinWidth and math.max(1, configuredMinWidth)
        or math.max(15, tonumber(minWidth) or 15)
    root.minimumHeight = configuredMinHeight and math.max(1, configuredMinHeight)
        or math.max(15, tonumber(minHeight) or 15)
    root._minimumMode = normalized.minimumMode
    root._minimumContentContributions = {}
    root._minimumPaneContributions = {}
    local initialState = CharacterWindowState(owner)
    local storedSize = initialState and initialState.windowSizes[key]
    local initialWidth = storedSize and tonumber(storedSize.width) or width
    local initialHeight = storedSize and tonumber(storedSize.height) or height
    local screenWidth = UIParent:GetWidth() or width
    local screenHeight = UIParent:GetHeight() or height
    -- UI scale and screen size can change between characters/reloads. Keep
    -- stored dimensions recoverable even when their old bounds no longer fit.
    root.expandedWidth = math.max(1, math.min(math.max(root.minimumWidth, initialWidth), math.max(1, screenWidth - 20)))
    root.expandedHeight = math.max(1, math.min(math.max(root.minimumHeight, initialHeight), math.max(1, screenHeight - 20)))
    root:SetSize(root.expandedWidth, root.expandedHeight)
    function root:GetMinimumWindowSize()
        return self.minimumWidth, self.minimumHeight
    end
    local content
    local header
    local function AnchorInsets(frame, relativeTo)
        local insets = {left=0, right=0, top=0, bottom=0}
        if not (frame and frame.GetNumPoints and frame.GetPoint) then return insets end
        for index = 1, frame:GetNumPoints() do
            local point, relative, relativePoint, x, y = frame:GetPoint(index)
            if relative == relativeTo then
                point, relativePoint = tostring(point or ""), tostring(relativePoint or "")
                x, y = tonumber(x) or 0, tonumber(y) or 0
                if point:find("LEFT", 1, true) and relativePoint:find("LEFT", 1, true) then
                    insets.left = math.max(insets.left, x)
                elseif point:find("RIGHT", 1, true) and relativePoint:find("RIGHT", 1, true) then
                    insets.right = math.max(insets.right, -x)
                end
                if point:find("TOP", 1, true) and relativePoint:find("TOP", 1, true) then
                    insets.top = math.max(insets.top, -y)
                elseif point:find("BOTTOM", 1, true) and relativePoint:find("BOTTOM", 1, true) then
                    insets.bottom = math.max(insets.bottom, y)
                end
            end
        end
        return insets
    end
    local function HorizontalAnchor(frame, wantedSide)
        if not (frame and frame.GetNumPoints and frame.GetPoint) then return nil end
        for index = 1, frame:GetNumPoints() do
            local point, relative, relativePoint, x = frame:GetPoint(index)
            point, relativePoint = tostring(point or ""), tostring(relativePoint or "")
            local side = point:find("LEFT", 1, true) and "left"
                or (point:find("RIGHT", 1, true) and "right" or "center")
            if side == wantedSide then
                local targetSide = relativePoint:find("LEFT", 1, true) and "left"
                    or (relativePoint:find("RIGHT", 1, true) and "right" or "center")
                return {relative=relative, side=targetSide, offset=tonumber(x) or 0}
            end
        end
        return nil
    end
    local function AddExpression(left, right)
        return {a=(left and left.a or 0) + (right and right.a or 0),
            b=(left and left.b or 0) + (right and right.b or 0)}
    end
    local function SubtractExpression(left, right)
        return {a=(left and left.a or 0) - (right and right.a or 0),
            b=(left and left.b or 0) - (right and right.b or 0)}
    end
    local function ScaleExpression(value, scale)
        return {a=(value and value.a or 0) * scale, b=(value and value.b or 0) * scale}
    end
    local FrameHorizontalEdge
    FrameHorizontalEdge = function(frame, side, visiting)
        if frame == content or frame == root then
            if side == "left" then return {a=0, b=0} end
            if side == "right" then return {a=1, b=0} end
            return {a=0.5, b=0}
        end
        visiting = visiting or {}
        visiting[frame] = visiting[frame] or {}
        if visiting[frame][side] then return nil end
        visiting[frame][side] = true
        local anchor = HorizontalAnchor(frame, side)
        if not anchor and side ~= "center" then
            anchor = HorizontalAnchor(frame, "center")
            if anchor then
                local center = FrameHorizontalEdge(anchor.relative, anchor.side, visiting)
                if center then
                    center = AddExpression(center, {a=0, b=anchor.offset})
                    local halfWidth = ScaleExpression({a=0, b=tonumber(frame:GetWidth()) or 0}, 0.5)
                    visiting[frame][side] = nil
                    return side == "left" and SubtractExpression(center, halfWidth)
                        or AddExpression(center, halfWidth)
                end
            end
        end
        if anchor then
            local target = FrameHorizontalEdge(anchor.relative, anchor.side, visiting)
            if target then
                local result = AddExpression(target, {a=0, b=anchor.offset})
                visiting[frame][side] = nil
                return result
            end
        end
        if side ~= "center" then
            local oppositeSide = side == "left" and "right" or "left"
            if HorizontalAnchor(frame, oppositeSide) then
                local opposite = FrameHorizontalEdge(frame, oppositeSide, visiting)
                if opposite then
                    local size = {a=0, b=tonumber(frame:GetWidth()) or 0}
                    visiting[frame][side] = nil
                    return side == "left" and SubtractExpression(opposite, size)
                        or AddExpression(opposite, size)
                end
            end
        end
        visiting[frame][side] = nil
        return nil
    end
    local function PaneContentMinimumWidth(pane, minimumWidth)
        local leftAnchor = HorizontalAnchor(pane, "left")
        local rightAnchor = HorizontalAnchor(pane, "right")
        local centerAnchor = HorizontalAnchor(pane, "center")
        if not (leftAnchor and rightAnchor) then
            -- A one-sided anchor leaves the pane at its assigned width. Include
            -- that width so following panes retain their own minimum space.
            minimumWidth = math.max(minimumWidth, tonumber(pane:GetWidth()) or 0)
        end
        local left = FrameHorizontalEdge(pane, "left")
        local right = FrameHorizontalEdge(pane, "right")
        if left and right then
            local span = SubtractExpression(right, left)
            if span.a > 0.0001 then
                return math.max(0, (minimumWidth - span.b) / span.a)
            end
        elseif left then
            local remaining = 1 - left.a
            if remaining > 0.0001 then
                return math.max(0, (minimumWidth + left.b) / remaining)
            end
        elseif right and right.a > 0.0001 then
            return math.max(0, (minimumWidth - right.b) / right.a)
        end
        if centerAnchor and centerAnchor.relative == content
            and centerAnchor.side == "center" then
            return minimumWidth + (2 * math.abs(centerAnchor.offset))
        end
        -- Free positioning retains the previous direct-inset calculation.
        local paneInsets = AnchorInsets(pane, content)
        return minimumWidth + paneInsets.left + paneInsets.right
    end
    local function RefreshContentMinimum()
        if root._minimumMode ~= "content" or not content then return end
        -- Panes contribute their structural requirements. Scroll children do
        -- not contribute their full content height; they contribute only the
        -- visible viewport size their consumer requested.
        local width, height = DEFAULTS.minimumWidth, DEFAULTS.minimumHeight
        for _, contribution in pairs(root._minimumContentContributions) do
            width = math.max(width, contribution.width or 0)
            height = math.max(height, contribution.height or 0)
        end
        -- Anchored pane requirements compose through their actual relationships:
        -- a right-attached sibling inherits the preceding pane's width and gap,
        -- while independent or vertically stacked panes remain separate limits.
        for _, contribution in pairs(root._minimumPaneContributions) do
            local paneInsets = AnchorInsets(contribution.frame, content)
            width = math.max(width,
                PaneContentMinimumWidth(contribution.frame, contribution.width))
            height = math.max(height, contribution.height + paneInsets.top + paneInsets.bottom)
        end
        local contentInsets = AnchorInsets(content, root)
        root.minimumWidth = math.max(root._configuredMinimumWidth or DEFAULTS.minimumWidth,
            width + contentInsets.left + contentInsets.right)
        root.minimumHeight = math.max(root._configuredMinimumHeight or DEFAULTS.minimumHeight,
            height + contentInsets.top + contentInsets.bottom)
        if root.expandedWidth < root.minimumWidth or root.expandedHeight < root.minimumHeight then
            root:SetExpandedSize(root.expandedWidth, root.expandedHeight)
        end
    end
    root._configuredMinimumWidth = root.minimumWidth
    root._configuredMinimumHeight = root.minimumHeight
    function root:SetContentMinimumSize(key, width, height)
        if self._minimumMode ~= "content" or type(key) ~= "string" or key == "" then return end
        width, height = tonumber(width), tonumber(height)
        if not width or not height then return end
        self._minimumContentContributions[key] = {width=math.max(1, width), height=math.max(1, height)}
        RefreshContentMinimum()
    end
    function root:_SetPaneContentMinimumSize(key, pane, width, height)
        if type(key) ~= "string" or key == "" or not pane then return end
        width, height = tonumber(width), tonumber(height)
        if not width or not height then return end
        self._minimumPaneContributions[key] = {
            frame=pane, width=math.max(15, width), height=math.max(1, height),
        }
        RefreshContentMinimum()
    end
    function root:RemoveContentMinimumSize(key)
        self._minimumContentContributions[key] = nil
        self._minimumPaneContributions[key] = nil
        RefreshContentMinimum()
    end
    function root:SetExpandedSize(newWidth, newHeight)
        -- The same constraints apply to manual resizing and future presets.
        local availableWidth = math.max(1, (UIParent:GetWidth() or self.expandedWidth) - 20)
        local availableHeight = math.max(1, (UIParent:GetHeight() or self.expandedHeight) - 20)
        self.expandedWidth = math.min(math.max(self.minimumWidth, tonumber(newWidth) or self.expandedWidth), availableWidth)
        self.expandedHeight = math.min(math.max(self.minimumHeight, tonumber(newHeight) or self.expandedHeight), availableHeight)
        -- Commit both dimensions together. Separate SetWidth/SetHeight calls
        -- expose an intermediate viewport geometry to OnSizeChanged listeners
        -- during every active resize tick.
        if self.collapsed then
            if self:GetWidth() ~= self.expandedWidth then self:SetWidth(self.expandedWidth) end
        elseif self:GetWidth() ~= self.expandedWidth or self:GetHeight() ~= self.expandedHeight then
            self:SetSize(self.expandedWidth, self.expandedHeight)
        end
        if not resizing then SnapWindowRectangle(self) end
        self.expandedWidth = self:GetWidth()
        if not self.collapsed then self.expandedHeight = self:GetHeight() end
        if not resizing and self.RefreshPositionAnchor then self:RefreshPositionAnchor() end
    end
    root:SetFrameStrata("DIALOG")
    root.movementEnabled = options.movable ~= false
    root.dragRegion = options.dragRegion or DEFAULTS.dragRegion
    root:SetMovable(root.movementEnabled)
    root:EnableMouse(true)
    root:SetClampedToScreen(true)
    root:Hide()

    local state = CharacterWindowState(owner)
    local saved = state and state.windowPositions[key]
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
        and type(saved.point) == "string" and type(saved.relativePoint) == "string" then
        if root.positionAnchorMode == "screenAdaptive" and POSITION_ANCHORS[saved.point] then
            root.positionAnchorPoint = saved.point
        end
        root:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        root:SetPoint(normalized.positionPoint, UIParent, normalized.relativePoint, defaultX or 0, defaultY or 0)
    end
    SnapWindowRectangle(root)
    if root.positionAnchorMode == "screenAdaptive" then
        ClampFrameBodyToScreen(root)
        root.positionAnchorPoint = GetScreenAdaptiveAnchor(root)
        SnapWindowRectangle(root)
        local point, _, relativePoint, x, y = root:GetPoint(1)
        if state and point and relativePoint and type(x) == "number" and type(y) == "number" then
            state.windowPositions[key] = {
                point = point, relativePoint = relativePoint, x = x, y = y,
            }
        end
    end

    local heading
    if frameHeaderMode ~= "never" then
        header, heading = CreateFrameHeader(assembly, title, style, true, frameHeaderPadding)
        root.frameHeader = header
        header.storageOwner = owner
        header:Hide()
        if boundaryHoverMode and header.SetHitRectInsets then
            local hoverOutside = style.edgeOutside or 5
            header:SetHitRectInsets(-hoverOutside, -hoverOutside, -hoverOutside, -hoverOutside)
        end
    end

    content = CreateFrame("Frame", nil, root)
    root.content = content
    -- The window's body is a flow host by default. Consumers can register
    -- content directly here without adding a Row/Column wrapper; the frame
    -- reflows registered children after content is added or its size changes.
    if TBU.SettingsLayout and TBU.SettingsLayout.EnableFrameLayout then
        TBU.SettingsLayout:EnableFrameLayout(content, {
            padding = options.contentPadding or 0,
            gap = options.contentGap,
        })
    end

    -- The title bar keeps its three outer sides. The main-frame border is a
    -- higher-level sibling, so its shared edge stays visible over the title fill.
    local bodyBorder
    if header and (frameHeaderMode == "always" or frameHeaderMode == "hover") then
        bodyBorder = CreateFrame("Frame", nil, root)
        bodyBorder:EnableMouse(false)
        bodyBorder:SetFrameLevel(root:GetFrameLevel() + 8)
        root.windowBodyBorder = bodyBorder
        root._tbuSplitTitleAndBodyBorder = true
        local edges = {}
        local edgeSize = style.edgeSize or 1
        local function AddEdge(point1, relativePoint1, point2, relativePoint2, width, height)
            local edge = Styles:CreateFlatTexture(bodyBorder, "OVERLAY", Styles:GetWindowBorderColor(style))
            edge:SetPoint(point1, bodyBorder, relativePoint1, 0, 0)
            edge:SetPoint(point2, bodyBorder, relativePoint2, 0, 0)
            if width then edge:SetWidth(width) end
            if height then edge:SetHeight(height) end
            edges[#edges + 1] = edge
        end
        if frameBorderMode == "none" then
            -- Even without the rest of the body outline, retain its shared
            -- top/bottom seam edge beneath the open side of the title bar.
            AddEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, edgeSize)
        else
            AddEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, edgeSize)
            AddEdge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", edgeSize, nil)
            AddEdge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", edgeSize, nil)
            AddEdge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, edgeSize)
        end
        bodyBorder.borderEdges = edges
    end

    local function SetContentTitleSpacing(reserveFrameHeader)
        content:ClearAllPoints()
        local titleHeight = reserveFrameHeader and header and (header:GetHeight() or 0) or 0
        if root.frameHeaderPosition == "left" or root.frameHeaderPosition == "right" then
            content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
            content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
        elseif root.frameHeaderPosition == "bottom" then
            content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
            content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, reserveFrameHeader and (titleHeight + 2) or 1)
        else
            content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -titleHeight - 1)
            content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
        end
    end
    root:HookScript("OnSizeChanged", RefreshContentMinimum)

    local function SetFrameHeaderBackgroundBounds()
        if not (header and header.bg) then return end
        header.bg:ClearAllPoints()
        local borderInset = style.edgeSize or 1
        if root.frameHeaderPosition == "bottom" then
            -- Extend the fill under the main frame's shared top edge.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", borderInset, borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -borderInset, borderInset)
        elseif root.frameHeaderPosition == "left" then
            -- The tab projects left; fill under its attached right edge.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", borderInset, -borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", borderInset, borderInset)
        elseif root.frameHeaderPosition == "right" then
            -- The tab projects right; fill under its attached left edge.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", -borderInset, -borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -borderInset, borderInset)
        else
            -- This is the accepted default-chrome paint geometry for every
            -- top title bar, whether it is always visible or revealed on hover.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", borderInset, -borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -borderInset, -borderInset)
        end
    end

    local function FrameHeaderContentWidth()
        local textWidth = math.max(0, (heading and heading:GetStringWidth()) or 0)
        local closeWidth = root.closeButton and (root.closeButton:GetWidth() or 25) or 0
        local collapseWidth = root.collapseButton and (root.collapseButton:GetWidth() or 25) or 0
        local movementLockWidth = root.movementLockButton
            and (root.movementLockButton:GetWidth() or 25) or 0
        local controlsWidth = closeWidth + collapseWidth + movementLockWidth
        local controlCount = 0
        if closeWidth > 0 then controlCount = controlCount + 1 end
        if collapseWidth > 0 then controlCount = controlCount + 1 end
        if movementLockWidth > 0 then controlCount = controlCount + 1 end
        local controlsGap = math.max(0, controlCount - 1) * frameHeaderControlGap
        local labelGap = controlsWidth > 0 and 8 or 0
        return math.ceil(13 + textWidth + labelGap + controlsWidth + controlsGap + 8)
    end

    local function SetFrameHeaderAnchors()
        if not header then return end
        header:ClearAllPoints()
        local position = root.frameHeaderPosition
        local horizontalAnchor = frameHeaderAnchor
        local verticalAnchor = frameHeaderAnchor
        if horizontalAnchor ~= "left" and horizontalAnchor ~= "center" and horizontalAnchor ~= "right" then
            horizontalAnchor = "left"
        end
        if verticalAnchor ~= "top" and verticalAnchor ~= "center" and verticalAnchor ~= "bottom" then
            verticalAnchor = (position == "left" or position == "right") and "top" or "bottom"
        end

        if position == "top" then
            -- Always-visible and hover-revealed title bars use the same
            -- external geometry. Visibility is the only mode-specific behavior.
            if horizontalAnchor == "right" then header:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 0, 0)
            elseif horizontalAnchor == "center" then header:SetPoint("BOTTOM", root, "TOP", 0, 0)
            else header:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 0) end
        elseif position == "bottom" then
            if horizontalAnchor == "right" then header:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, 0)
            elseif horizontalAnchor == "center" then header:SetPoint("TOP", root, "BOTTOM", 0, 0)
            else header:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, 0) end
        elseif position == "left" then
            -- Side title bars remain horizontal tabs. Their right edge meets
            -- the frame's left edge; the vertical anchor chooses the tab's
            -- position along that edge.
            if verticalAnchor == "bottom" then header:SetPoint("BOTTOMRIGHT", root, "BOTTOMLEFT", 0, 0)
            elseif verticalAnchor == "center" then header:SetPoint("RIGHT", root, "LEFT", 0, 0)
            else header:SetPoint("TOPRIGHT", root, "TOPLEFT", 0, 0) end
        else -- right
            -- The left edge meets the frame's right edge. Default the tab to
            -- the top of the side unless the consumer chooses another anchor.
            if verticalAnchor == "top" then header:SetPoint("TOPLEFT", root, "TOPRIGHT", 0, 0)
            elseif verticalAnchor == "center" then header:SetPoint("LEFT", root, "RIGHT", 0, 0)
            else header:SetPoint("BOTTOMLEFT", root, "BOTTOMRIGHT", 0, 0) end
        end

        if frameHeaderWidthMode == "percent" and math.abs(frameHeaderWidthPercent - 100) < 0.001 then
            header:SetWidth(root:GetWidth() or 1)
            return
        end
        local width
        if frameHeaderWidthMode == "content" then
            width = FrameHeaderContentWidth()
        else
            width = (tonumber(root:GetWidth()) or 1) * frameHeaderWidthPercent / 100
        end
        local screenWidth = tonumber(UIParent:GetWidth()) or width
        header:SetWidth(math.max(1, math.min(width, math.max(1, screenWidth - 20))))
    end

    local function UpdateCollapsedClampInsets()
        if not header or not root.collapsed then
            root:SetClampRectInsets(0, 0, 0, 0)
            return
        end

        -- The header is an external sibling, so the body's normal screen
        -- clamp does not account for it. Expand the clamp rectangle to the
        -- union of body + header while collapsed, keeping the title visible
        -- when the user drags the collapsed window against a screen edge.
        local bodyLeft, bodyRight = root:GetLeft(), root:GetRight()
        local bodyBottom, bodyTop = root:GetBottom(), root:GetTop()
        local headerLeft, headerRight = header:GetLeft(), header:GetRight()
        local headerBottom, headerTop = header:GetBottom(), header:GetTop()
        if not (bodyLeft and bodyRight and bodyBottom and bodyTop
            and headerLeft and headerRight and headerBottom and headerTop) then
            return
        end

        root:SetClampRectInsets(
            math.min(0, headerLeft - bodyLeft),
            math.max(0, headerRight - bodyRight),
            math.max(0, headerTop - bodyTop),
            math.min(0, headerBottom - bodyBottom)
        )

        -- The clamp update can synchronously reposition the body. Re-read the
        -- composition bounds before calculating any corrective movement.
        bodyLeft, bodyRight = root:GetLeft(), root:GetRight()
        bodyBottom, bodyTop = root:GetBottom(), root:GetTop()
        headerLeft, headerRight = header:GetLeft(), header:GetRight()
        headerBottom, headerTop = header:GetBottom(), header:GetTop()
        if not (bodyLeft and bodyRight and bodyBottom and bodyTop
            and headerLeft and headerRight and headerBottom and headerTop) then
            return
        end

        -- Applying new clamp insets constrains the next drag, but the frame
        -- may already be beyond that new boundary. Bring the combined visible
        -- rectangle back onscreen now so a title that was clipped at collapse
        -- can be recovered without requiring an invisible drag handle.
        local screenLeft, screenRight = UIParent:GetLeft(), UIParent:GetRight()
        local screenBottom, screenTop = UIParent:GetBottom(), UIParent:GetTop()
        if not (screenLeft and screenRight and screenBottom and screenTop) then return end
        local left = math.min(bodyLeft, headerLeft)
        local right = math.max(bodyRight, headerRight)
        local bottom = math.min(bodyBottom, headerBottom)
        local top = math.max(bodyTop, headerTop)
        local offsetX, offsetY = 0, 0
        if left < screenLeft then offsetX = screenLeft - left end
        if right + offsetX > screenRight then offsetX = screenRight - right end
        if bottom < screenBottom then offsetY = screenBottom - bottom end
        if top + offsetY > screenTop then offsetY = screenTop - top end
        if math.abs(offsetX) > 0.01 or math.abs(offsetY) > 0.01 then
            local point, relativeTo, relativePoint, x, y = root:GetPoint(1)
            if point and relativeTo and relativePoint then
                root:ClearAllPoints()
                root:SetPoint(point, relativeTo, relativePoint,
                    (tonumber(x) or 0) + offsetX, (tonumber(y) or 0) + offsetY)
            end
        end
    end

    local function SetBodyBorderBounds()
        if not bodyBorder or not header then return end
        bodyBorder:ClearAllPoints()
        -- The basic frame always owns its full rectangle. Title chrome is
        -- attached outside it and draws only its exposed edges, independent
        -- of whether that title is always visible or revealed on hover.
        bodyBorder:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
        bodyBorder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
        if frameBorderMode == "none" then
            local edge = bodyBorder.borderEdges and bodyBorder.borderEdges[1]
            if edge then
                edge:ClearAllPoints()
                edge:SetSize(style.edgeSize or 1, style.edgeSize or 1)
                if root.frameHeaderPosition == "bottom" then
                    edge:SetPoint("BOTTOMLEFT", bodyBorder, "BOTTOMLEFT", 0, 0)
                    edge:SetPoint("BOTTOMRIGHT", bodyBorder, "BOTTOMRIGHT", 0, 0)
                    edge:SetHeight(style.edgeSize or 1)
                elseif root.frameHeaderPosition == "left" then
                    edge:SetPoint("TOPLEFT", bodyBorder, "TOPLEFT", 0, 0)
                    edge:SetPoint("BOTTOMLEFT", bodyBorder, "BOTTOMLEFT", 0, 0)
                    edge:SetWidth(style.edgeSize or 1)
                elseif root.frameHeaderPosition == "right" then
                    edge:SetPoint("TOPRIGHT", bodyBorder, "TOPRIGHT", 0, 0)
                    edge:SetPoint("BOTTOMRIGHT", bodyBorder, "BOTTOMRIGHT", 0, 0)
                    edge:SetWidth(style.edgeSize or 1)
                else
                    edge:SetPoint("TOPLEFT", bodyBorder, "TOPLEFT", 0, 0)
                    edge:SetPoint("TOPRIGHT", bodyBorder, "TOPRIGHT", 0, 0)
                    edge:SetHeight(style.edgeSize or 1)
                end
            end
        end
    end

    local function SetFrameHeaderBorderBounds()
        if not (header and header.borderEdges) then return end
        local extension = style.edgeSize or 1
        local topEdge, leftEdge, rightEdge, bottomEdge = unpack(header.borderEdges)
        if not (topEdge and leftEdge and rightEdge and bottomEdge) then return end
        local position = root.frameHeaderPosition
        local attachedEdge = {
            top = "bottom",
            right = "left",
            bottom = "top",
            left = "right",
        }
        local sharedEdge = attachedEdge[position]
        topEdge:ClearAllPoints()
        leftEdge:ClearAllPoints()
        rightEdge:ClearAllPoints()
        bottomEdge:ClearAllPoints()

        -- The body owns the edge where title and frame meet. The title draws
        -- the other three sides, with adjoining edges extended one pixel to
        -- overlap the shared border cleanly.
        topEdge:SetShown(sharedEdge ~= "top")
        leftEdge:SetShown(sharedEdge ~= "left")
        rightEdge:SetShown(sharedEdge ~= "right")
        bottomEdge:SetShown(sharedEdge ~= "bottom")

        if position == "bottom" then
            leftEdge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            leftEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            rightEdge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
            rightEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            bottomEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            bottomEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        elseif position == "top" then
            leftEdge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            leftEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            rightEdge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
            rightEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            topEdge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            topEdge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        elseif position == "left" then
            topEdge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            topEdge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
            bottomEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            bottomEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            leftEdge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            leftEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        else -- right
            topEdge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            topEdge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
            bottomEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            bottomEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            rightEdge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
            rightEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        end
    end

    local function SetCollapsedHeaderSeam(collapsed)
        if not (header and header.borderEdges) then return end
        local edgeIndex = ({top=4, left=3, bottom=1, right=2})[root.frameHeaderPosition or "top"]
        local edge = edgeIndex and header.borderEdges[edgeIndex]
        if not edge then return end
        edge:ClearAllPoints()
        if not collapsed then
            edge:Hide()
            return
        end
        local position = root.frameHeaderPosition or "top"
        if position == "top" then
            edge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            edge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        elseif position == "right" then
            edge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            edge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        elseif position == "bottom" then
            edge:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            edge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        else -- left
            edge:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
            edge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        end
        edge:Show()
    end

    -- One reversible anchor policy for every shared window instance. Both
    -- title label and action buttons are header children and move together.
    function root:SetFrameHeaderPosition(position, anchor)
        if not header then return false end
        if position ~= "top" and position ~= "bottom" and position ~= "left" and position ~= "right" then
            position = "top"
        end
        if anchor ~= nil then
            if anchor == "left" or anchor == "center" or anchor == "right"
                or anchor == "top" or anchor == "bottom" then
                frameHeaderAnchor = anchor
            end
        end
        self.frameHeaderPosition = position
        self.frameHeaderAnchor = frameHeaderAnchor
        SetFrameHeaderAnchors()
        UpdateCollapsedClampInsets()
        SetFrameHeaderBackgroundBounds()
        SetFrameHeaderBorderBounds()
        if root.collapsed then SetCollapsedHeaderSeam(true) end
        SetBodyBorderBounds()
        if self.UpdateBoundaryTitleSeam then self:UpdateBoundaryTitleSeam() end
        -- Title chrome is attached outside the basic frame in either mode;
        -- visibility must not change content or border geometry.
        SetContentTitleSpacing(false)
        local charState = CharacterWindowState(owner)
        if charState then charState.frameHeaderPositions[key] = position end
        if self.PlaceResizeGrip then self:PlaceResizeGrip() end
    end
    function root:SetFrameHeaderWidth(widthOption, anchor)
        if not header then return false end
        if type(widthOption) == "table" and widthOption.mode == "content" then
            frameHeaderWidthMode = "content"
        else
            frameHeaderWidthMode = "percent"
            local value = type(widthOption) == "table" and tonumber(widthOption.value) or tonumber(widthOption)
            frameHeaderWidthPercent = value and math.max(1, math.min(100, value)) or 100
        end
        if anchor then frameHeaderAnchor = anchor end
        self.frameHeaderAnchor = frameHeaderAnchor
        SetFrameHeaderAnchors()
        UpdateCollapsedClampInsets()
        if self.PlaceResizeGrip then self:PlaceResizeGrip() end
        return true
    end
    if header then
        root:SetFrameHeaderPosition(options.frameHeaderPosition or (state and state.frameHeaderPositions[key]) or "top", frameHeaderAnchor)
    else
        local noFrameHeaderPosition = options.frameHeaderPosition
        root.frameHeaderPosition = (noFrameHeaderPosition == "bottom" or noFrameHeaderPosition == "left" or noFrameHeaderPosition == "right")
            and noFrameHeaderPosition or "top"
        content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
        content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
    end
    function root:RefreshFrameHeaderVisibility()
        if not header then return end
        local visible = self:IsShown() and (frameHeaderMode == "always"
            or (frameHeaderMode == "hover" and (hovering or dragging or resizing or self.collapsed)))
        header:SetShown(visible)
    end
    function root:SetFrameHeaderVisibility(mode)
        if not header then return mode == "never" end
        if mode ~= "always" and mode ~= "hover" and mode ~= "never" then return false end
        frameHeaderMode = mode
        self:SetFrameHeaderPosition(self.frameHeaderPosition, self.frameHeaderAnchor)
        self:RefreshFrameHeaderVisibility()
        if self.RefreshWindowStyle then self:RefreshWindowStyle() end
        return true
    end
    root:RefreshFrameHeaderVisibility()
    -- Generic window pane chrome. All contents (settings/debug/future notepad)
    -- can request a compact header and footer from one shared layout host.
    -- Header/footer are structural slots, not page-specific content builders.
    function root:CreatePane(parent, options)
        options = options or {}
        -- Navigation is a reusable pane role, not a Settings-window special
        -- case. The consumer still supplies its own navigation items/actions.
        local isNavigationPane = options.navigation == true
        local hasHeader = options.header == true or isNavigationPane
        -- Pane headers (including navigation headers) use the page-header
        -- surface by default. Consumers can request a section header explicitly.
        local sectionHeader = options.headerStyle == "section"
        local pane = TBU:CreateBackdropFrame("Frame", parent)
        Styles:ApplyPanel(pane) -- resolve the pane owner on every repaint
        local paneStyle = Styles:Get(Styles:GetConsumerPreset(owner))
        local paneMinimumWidth = math.max(15, tonumber(options.minimumWidth)
            or paneStyle.paneMinimumWidth or 15)
        local autoSizeHeader = options.headerAutoSize ~= false or isNavigationPane
        local headerMinHeight = math.max(15, tonumber(options.headerMinHeight)
            or paneStyle.paneHeaderMinHeight or 15)
        local headerPaddingX = tonumber(options.headerPaddingX) or paneStyle.paneHeaderPaddingX or 12
        local headerPaddingY = tonumber(options.headerPaddingY) or paneStyle.paneHeaderPaddingY or 10
        local headerTextGap = tonumber(options.headerTextGap) or paneStyle.paneHeaderTextGap or 4
        local headerLabel, headerNote
        local headerHeight = hasHeader and (autoSizeHeader and headerMinHeight
            or options.headerHeight or paneStyle.paneHeaderHeight or headerMinHeight) or 0
        local footerHeight = options.footer and (options.footerHeight or paneStyle.paneFooterHeight) or 0
        local headerRegion, footerRegion
        if headerHeight > 0 then
            headerRegion = CreateFrame("Frame", nil, pane)
            headerRegion:SetPoint("TOPLEFT", pane, "TOPLEFT", 1, -1)
            headerRegion:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -1, -1)
            headerRegion:SetHeight(headerHeight)
            local headerFill = sectionHeader and paneStyle.sectionHeaderFill
                or Styles:GetMainCanvasColor(paneStyle)
            local fill = Styles:CreateFlatTexture(headerRegion, "BACKGROUND", headerFill)
            fill:SetAllPoints(headerRegion)
            Styles:RegisterVisual(fill, function(target)
                local currentOwner = target
                for _ = 1, 48 do
                    if not currentOwner then break end
                    if currentOwner.storageOwner then break end
                    currentOwner = currentOwner.GetParent and currentOwner:GetParent() or nil
                end
                local currentStyle = Styles:Get(currentOwner and Styles:GetConsumerPreset(currentOwner))
                local color = sectionHeader and currentStyle.sectionHeaderFill
                    or Styles:GetMainCanvasColor(currentStyle)
                target:SetVertexColor(unpack(color))
            end)
            Styles:CreateSeparator(headerRegion, "bottom", nil)
        end
        if footerHeight > 0 then
            footerRegion = CreateFrame("Frame", nil, pane)
            footerRegion:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 1, 1)
            footerRegion:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -1, 1)
            footerRegion:SetHeight(footerHeight)
            Styles:CreateSeparator(footerRegion, "top", nil)
        end
        local body = CreateFrame("Frame", nil, pane)
        local inset = options.inset or 0
        if headerRegion then
            body:SetPoint("TOPLEFT", headerRegion, "BOTTOMLEFT", inset, -inset)
            body:SetPoint("TOPRIGHT", headerRegion, "BOTTOMRIGHT", -inset, -inset)
        else
            body:SetPoint("TOPLEFT", pane, "TOPLEFT", 1 + inset, -1 - inset)
            body:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -1 - inset, -1 - inset)
        end
        if footerRegion then
            body:SetPoint("BOTTOMLEFT", footerRegion, "TOPLEFT", inset, inset)
            body:SetPoint("BOTTOMRIGHT", footerRegion, "TOPRIGHT", -inset, inset)
        else
            body:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 1 + inset, 1 + inset)
            body:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -1 - inset, 1 + inset)
        end
        pane.headerRegion = headerRegion
        pane.body = body
        -- A Pane body is also a direct-content flow host. Header/footer are
        -- separate slots; body content does not need a settings-specific Row.
        if TBU.SettingsLayout and TBU.SettingsLayout.EnableFrameLayout then
            TBU.SettingsLayout:EnableFrameLayout(body, {
                padding = options.contentPadding or 0,
                gap = options.contentGap,
            })
        end
        pane.footerRegion = footerRegion
        pane.isNavigationPane = isNavigationPane
        pane._tbuRoot = root
        pane.minimumWidth = paneMinimumWidth
        -- Even a pane with no requested body minimum contributes its small
        -- structural width floor to content-sized windows.
        pane._tbuMinimumBodySize = {width=1, height=1}
        root._minimumContentSequence = (root._minimumContentSequence or 0) + 1
        pane._tbuMinimumKey = "pane-" .. root._minimumContentSequence
        local function RefreshPaneMinimum()
            if not pane._tbuMinimumBodySize or root._minimumMode ~= "content" then return end
            local bodyMinimum = pane._tbuMinimumBodySize
            local paneWidth = math.max(pane.minimumWidth,
                bodyMinimum.width + (2 * (1 + inset)))
            local paneHeight = bodyMinimum.height + (2 * (1 + inset))
                + (headerRegion and (headerRegion:GetHeight() or 0) or 0)
                + (footerRegion and (footerRegion:GetHeight() or 0) or 0)
            root:_SetPaneContentMinimumSize(pane._tbuMinimumKey, pane, paneWidth, paneHeight)
        end
        function pane:SetMinimumBodySize(width, height)
            width, height = tonumber(width), tonumber(height)
            if not width or not height then return end
            self._tbuMinimumBodySize = {width=math.max(1, width), height=math.max(1, height)}
            RefreshPaneMinimum()
        end
        if headerRegion then headerRegion:HookScript("OnSizeChanged", RefreshPaneMinimum) end
        if footerRegion then footerRegion:HookScript("OnSizeChanged", RefreshPaneMinimum) end
        pane:HookScript("OnSizeChanged", RefreshPaneMinimum)
        RefreshPaneMinimum()
        if isNavigationPane then pane.navigationRegion = headerRegion end
        if footerRegion then
            local footerLayoutOptions
            local lastFooterWidth
            local function LayoutFooterRowAtCurrentWidth()
                if not pane._footerRow or not footerLayoutOptions then return end
                local width = footerRegion:GetWidth()
                if not width or width <= 1 then return end
                if width == lastFooterWidth then return end
                lastFooterWidth = width
                local layout = TBU.SettingsLayout
                if layout and layout.LayoutRowInRegion then
                    layout:LayoutRowInRegion(pane._footerRow, footerRegion, footerLayoutOptions)
                    RefreshPaneMinimum()
                end
            end
            local footerLayoutUpdate = CreateFrame("Frame", nil, pane)
            footerLayoutUpdate:Hide()
            footerLayoutUpdate:SetScript("OnUpdate", function(self)
                self:Hide()
                -- Coalesce footer reflow until the current resize/layout pass
                -- has finished resolving the pane and its anchored children.
                LayoutFooterRowAtCurrentWidth()
            end)
            local function FitFooterRow()
                if not pane._footerRow or not footerLayoutOptions then return end
                local width = footerRegion:GetWidth()
                if not width or width <= 1 then return end
                footerLayoutUpdate:Show()
            end
            function pane:LayoutFooterRow(row, rowOptions)
                if not row or not footerRegion then return end
                rowOptions = rowOptions or {}
                footerLayoutOptions = {
                    insetX = tonumber(rowOptions.insetX) or paneStyle.paneFooterPaddingX or 12,
                    insetY = rowOptions.insetY == nil
                        and (paneStyle.paneFooterPaddingY or 6) or rowOptions.insetY,
                    minHeight = rowOptions.minHeight == nil
                        and (paneStyle.paneFooterHeight or 0) or rowOptions.minHeight,
                }
                pane._footerRow = row
                lastFooterWidth = nil
                FitFooterRow()
                return footerRegion:GetHeight()
            end
            footerRegion:HookScript("OnSizeChanged", FitFooterRow)
        end
        if headerRegion then
            local headerLayoutOptions
            local lastHeaderWidth
            local function LayoutHeaderRowAtCurrentWidth()
                if not pane._headerRow or not headerLayoutOptions then return end
                local width = headerRegion:GetWidth()
                if not width or width <= 1 then return end
                if width == lastHeaderWidth then return end
                lastHeaderWidth = width
                local layout = TBU.SettingsLayout
                if layout and layout.LayoutRowInRegion then
                    if autoSizeHeader then
                        layout:LayoutRowInRegion(pane._headerRow, headerRegion, headerLayoutOptions)
                    elseif layout.LayoutRow then
                        layout:LayoutRow(pane._headerRow, math.max(1,
                            width - (2 * headerLayoutOptions.insetX)))
                        pane._headerRow:ClearAllPoints()
                        pane._headerRow:SetPoint("TOPLEFT", headerRegion, "TOPLEFT",
                            headerLayoutOptions.insetX, -headerLayoutOptions.insetY)
                    end
                    RefreshPaneMinimum()
                end
            end
            local headerLayoutUpdate = CreateFrame("Frame", nil, pane)
            headerLayoutUpdate:Hide()
            headerLayoutUpdate:SetScript("OnUpdate", function(self)
                self:Hide()
                -- Defer measurement until the pane has its final width, just
                -- like the footer row's resize-safe layout path.
                LayoutHeaderRowAtCurrentWidth()
            end)
            local function FitHeaderRow()
                if not pane._headerRow or not headerLayoutOptions then return end
                local width = headerRegion:GetWidth()
                if not width or width <= 1 then return end
                headerLayoutUpdate:Show()
            end
            function pane:LayoutHeaderRow(row, rowOptions)
                if not row or not headerRegion then return end
                rowOptions = rowOptions or {}
                local insetX = math.max(0, tonumber(rowOptions.insetX) or headerPaddingX)
                local insetY = math.max(0, tonumber(rowOptions.insetY) or headerPaddingY)
                headerLayoutOptions = {
                    insetX = insetX,
                    insetY = insetY,
                    minHeight = rowOptions.minHeight == nil
                        and math.max(1, headerMinHeight - (2 * insetY))
                        or math.max(1, tonumber(rowOptions.minHeight) or 1),
                }
                pane._headerRow = row
                -- This row owns the whole header content area. Consumers that
                -- need a title beside controls can put both in its columns.
                row:Show()
                if headerLabel then headerLabel:Hide() end
                if headerNote then headerNote:Hide() end
                lastHeaderWidth = nil
                FitHeaderRow()
                -- Reinvoke this method after changing header-row content at the
                -- same width so its new measured height is applied.
                return headerRegion:GetHeight()
            end
            headerRegion:HookScript("OnSizeChanged", FitHeaderRow)
        end
        if isNavigationPane then
            local navigationItems
            local lastNavigationWidth
            local function FitNavigationItems()
                if not body or type(navigationItems) ~= "table" then return end
                local width = body:GetWidth()
                if not width or width <= 1 or width == lastNavigationWidth then return end
                lastNavigationWidth = width
                local itemHeight = tonumber(options.navigationItemHeight)
                    or paneStyle.navigationItemHeight or 28
                local itemInset = tonumber(options.navigationItemInset)
                    or paneStyle.navigationItemInset or 8
                local itemWidth = math.max(1, width - (2 * itemInset))
                for _, item in ipairs(navigationItems) do
                    if item then
                        if item.labelOptions and item.labelOptions.autoHeight then
                            item:SetWidth(itemWidth)
                            item:UpdateLabelGeometry()
                        elseif item.SetSize then item:SetSize(itemWidth, itemHeight)
                        elseif item.SetHeight then item:SetHeight(itemHeight) end
                    end
                end
                local layout = TBU.SettingsLayout
                if layout and layout.StackRows then
                    layout:StackRows(body, navigationItems, {
                        padding=itemInset,
                        gap=tonumber(options.navigationItemGap)
                            or paneStyle.navigationItemGap or 6,
                    })
                end
            end
            function pane:LayoutNavigationItems(items)
                if type(items) ~= "table" then return end
                navigationItems = items
                lastNavigationWidth = nil
                FitNavigationItems()
            end
            body:HookScript("OnSizeChanged", FitNavigationItems)
        end
        if headerRegion then
            local function FitHeader()
                if pane._headerRow then return end
                if not headerLabel then return end
                local width = math.max(1, headerRegion:GetWidth() - headerPaddingX * 2)
                headerLabel:SetWidth(width)
                if headerNote then headerNote:SetWidth(width) end
                headerLabel:ClearAllPoints()
                headerLabel:SetPoint("TOPLEFT", headerRegion, "TOPLEFT", headerPaddingX, -headerPaddingY)
                if headerNote then
                    headerNote:ClearAllPoints()
                    headerNote:SetPoint("TOPLEFT", headerLabel, "BOTTOMLEFT", 0, -headerTextGap)
                end
                local titleHeight = math.max(1, headerLabel:GetStringHeight() or headerLabel:GetHeight() or 1)
                local noteHeight = headerNote and headerNote:IsShown()
                    and math.max(1, headerNote:GetStringHeight() or headerNote:GetHeight() or 1) or 0
                if autoSizeHeader then
                    local measuredHeight = math.max(headerMinHeight,
                        headerPaddingY + titleHeight + (noteHeight > 0 and headerTextGap + noteHeight or 0) + headerPaddingY)
                    if math.abs(headerRegion:GetHeight() - measuredHeight) > 0.5 then
                        headerRegion:SetHeight(measuredHeight)
                    end
                elseif noteHeight <= 0 then
                    headerLabel:ClearAllPoints()
                    headerLabel:SetPoint("LEFT", headerRegion, "LEFT", headerPaddingX, 0)
                end
            end
            function pane:SetHeaderText(titleText, noteText)
                if pane._headerRow then
                    pane._headerRow:Hide()
                    pane._headerRow = nil
                end
                if not headerLabel then
                    headerLabel = headerRegion:CreateFontString(nil, "ARTWORK", options.headerFont or "GameFontNormalLarge")
                    headerLabel:SetJustifyH("LEFT")
                    headerLabel:SetJustifyV("TOP")
                    headerLabel:SetWordWrap(options.headerWrap ~= false)
                    if headerLabel.SetNonSpaceWrap then
                        headerLabel:SetNonSpaceWrap(options.headerWrap ~= false)
                    end
                    Styles:RegisterVisual(headerLabel, function(target)
                        target:SetTextColor(unpack(Styles:GetTextColor("header", target)))
                    end)
                    if not autoSizeHeader then headerLabel:SetJustifyV("MIDDLE") end
                end
                headerLabel:SetText(titleText or "")
                headerLabel:Show()
                if noteText and noteText ~= "" then
                    if not headerNote then
                        headerNote = headerRegion:CreateFontString(nil, "ARTWORK", options.headerNoteFont or "GameFontHighlightSmall")
                        headerNote:SetJustifyH("LEFT")
                        headerNote:SetJustifyV("TOP")
                        headerNote:SetWordWrap(options.headerNoteWrap ~= false)
                        if headerNote.SetNonSpaceWrap then
                            headerNote:SetNonSpaceWrap(options.headerNoteWrap ~= false)
                        end
                        Styles:RegisterVisual(headerNote, function(target)
                            target:SetTextColor(unpack(Styles:GetTextColor("notes", target)))
                        end)
                    end
                    headerNote:SetText(noteText)
                    headerNote:Show()
                elseif headerNote then
                    headerNote:SetText("")
                    headerNote:Hide()
                end
                FitHeader()
            end
            headerRegion:HookScript("OnSizeChanged", FitHeader)
            if options.headerText or options.navigationTitle then
                pane:SetHeaderText(options.headerText or options.navigationTitle,
                    options.headerNote or options.navigationNote)
            end
        end
        pane:EnableMouse(true)
        pane:SetScript("OnMouseDown", function() Host:BringToFront(root) end)
        return pane
    end
    content:EnableMouse(true)
    content:SetScript("OnMouseDown", function() Host:BringToFront(root) end)
    root:HookScript("OnMouseDown", function() Host:BringToFront(root) end)

    local resizeGrip
    local resizeGrips = {}
    local resizeEnabled = options.resizeHandles ~= false
    local activeResizeGrip
    local function ApplyBorderColor(borderColor)
        -- State changes recolor the existing border surfaces. They never add
        -- another perimeter with separate anchors or thickness.
        if not root._tbuHideWindowBorder then
            root:SetBackdropBorderColor(unpack(borderColor))
        end
        for _, edge in ipairs((root.windowBodyBorder and root.windowBodyBorder.borderEdges) or {}) do
            edge:SetVertexColor(unpack(borderColor))
        end
        for _, edge in ipairs((header and header.borderEdges) or {}) do
            edge:SetVertexColor(unpack(borderColor))
        end
    end

    local function Repaint()
        style = Styles:Get(Styles:GetConsumerPreset(owner))
        local current = (dragging or resizing) and "drag"
            or (hoverEnabled and hovering and "hover") or "normal"
        Styles:ApplyWindow(root, current, Styles:GetConsumerPreset(owner))
        local function ReadSurfaceColor(role, fallback)
            local value = root._tbuSurfaceOptions and root._tbuSurfaceOptions[role]
            if type(value) ~= "table" then return fallback end
            local color = value.color
            local red, green, blue
            if type(color) == "string" then
                local hex = color:gsub("^#", "")
                if #hex == 6 and hex:match("^%x+$") then
                    red = tonumber(hex:sub(1, 2), 16) / 255
                    green = tonumber(hex:sub(3, 4), 16) / 255
                    blue = tonumber(hex:sub(5, 6), 16) / 255
                end
            elseif type(color) == "table" then
                red, green, blue = tonumber(color[1]), tonumber(color[2]), tonumber(color[3])
            end
            if not (red and green and blue) then return fallback end
            local opacity = tonumber(value.opacity)
            if opacity == nil then opacity = (fallback and fallback[4]) or 1 end
            opacity = math.max(0, math.min(100, opacity)) / 100
            return {red, green, blue, opacity}
        end
        local background = ReadSurfaceColor("background", Styles:GetMainCanvasColor(style))
        local normalBorder = ReadSurfaceColor("border", Styles:GetWindowBorderColor(style))
        local hoverBorder = ReadSurfaceColor("hoverBorder", Styles:GetWindowHighlightColor(style))
        local interactionBorder = ReadSurfaceColor("interactionBorder", Styles:GetWindowInteractionColor(style))
        local border = current == "drag" and interactionBorder
            or current == "hover" and borderHoverEnabled and hoverBorder or normalBorder
        root:SetBackdropColor(unpack(background))
        ApplyBorderColor(border)
        if root.RefreshFrameHeaderVisibility then root:RefreshFrameHeaderVisibility() end
    end
    root.RefreshWindowStyle = Repaint
    function root:SetSurfaceOptions(surfaceOptions)
        self._tbuSurfaceOptions = type(surfaceOptions) == "table" and surfaceOptions or {}
        Repaint()
    end
    function root:SetHoverEnabled(enabled)
        hoverEnabled = enabled ~= false
        if self.RefreshFrameHeaderVisibility then self:RefreshFrameHeaderVisibility() end
        Repaint()
        if self.RefreshResizeGrip then self:RefreshResizeGrip() end
    end
    function root:SetBorderHoverEnabled(enabled)
        borderHoverEnabled = enabled ~= false
        Repaint()
        return borderHoverEnabled
    end
    function root:GetBorderHoverEnabled()
        return borderHoverEnabled
    end
    Styles:RegisterVisual(root, function(window)
        if window.RefreshWindowStyle then window:RefreshWindowStyle() end
        if window.RefreshResizeGrip then window:RefreshResizeGrip() end
    end)

    local function CaptureCollapseGeometry(stage)
        if not root._captureCollapseGeometry then return end
        local point, relativeTo, relativePoint, x, y = root:GetPoint(1)
        local headerPoint, headerRelativeTo, headerRelativePoint, headerX, headerY
        if header then
            headerPoint, headerRelativeTo, headerRelativePoint, headerX, headerY = header:GetPoint(1)
        end
        root._lastCollapseGeometryTrace[#root._lastCollapseGeometryTrace + 1] = {
            stage = stage,
            collapsed = root.collapsed,
            rootPoint = point,
            rootRelativePoint = relativePoint,
            rootX = x,
            rootY = y,
            rootLeft = root:GetLeft(),
            rootRight = root:GetRight(),
            rootTop = root:GetTop(),
            rootBottom = root:GetBottom(),
            rootWidth = root:GetWidth(),
            rootHeight = root:GetHeight(),
            expandedHeight = root.expandedHeight,
            rootScale = EffectiveScale(root),
            uiScale = EffectiveScale(UIParent),
            headerPoint = headerPoint,
            headerRelativePoint = headerRelativePoint,
            headerX = headerX,
            headerY = headerY,
            headerLeft = header and header:GetLeft(),
            headerRight = header and header:GetRight(),
            headerTop = header and header:GetTop(),
            headerBottom = header and header:GetBottom(),
            savedY = root._lastSavedWindowPosition and root._lastSavedWindowPosition.y,
        }
    end

    local function SavePosition()
        local charState = CharacterWindowState(owner)
        if not charState then return end
        local point, _, relativePoint, x, y = root:GetPoint(1)
        if point and relativePoint and type(x) == "number" and type(y) == "number" then
            charState.windowPositions[key] = {
                point = point, relativePoint = relativePoint, x = x, y = y,
            }
            root._lastSavedWindowPosition = {
                point = point, relativePoint = relativePoint, x = x, y = y,
            }
        end
    end

    local function RefreshScreenAdaptiveAnchor()
        if root.positionAnchorMode ~= "screenAdaptive" then return end
        local nextAnchor = GetScreenAdaptiveAnchor(root)
        if nextAnchor ~= root.positionAnchorPoint then
            root.positionAnchorPoint = nextAnchor
            SnapWindowRectangle(root, true)
        end
        SavePosition()
    end
    function root:RefreshPositionAnchor()
        if resizing then return false end
        RefreshScreenAdaptiveAnchor()
        return true
    end

    local function RefreshGrip()
        for _, grip in ipairs(resizeGrips) do
            if root.collapsed or not resizeEnabled then
                grip:Hide()
            else
                -- Keep the resize affordance visible from initial creation so
                -- users can discover resizing without first finding a hover zone.
                grip:Show()
                if grip.icon then
                    local active = resizing and activeResizeGrip == grip
                    local gripHovered = hoverEnabled and grip:IsMouseOver()
                    local highlighted = hoverEnabled and (hovering or dragging or gripHovered)
                    local gripColor = active and Styles:GetWindowInteractionColor(style)
                        or highlighted and Styles:GetWindowHighlightColor(style)
                        or Styles:GetResizeGripIdleColor(style)
                    grip.icon:SetVertexColor(unpack(gripColor))
                    grip.icon:Show()
                end
            end
        end
    end
    root.RefreshResizeGrip = RefreshGrip
    local function IsBoundaryRegionHovered()
        local function hovered(frame)
            return frame and frame.IsShown and frame:IsShown()
                and frame.IsMouseOver and frame:IsMouseOver()
        end
        if hovered(header) or hovered(root.closeButton) or hovered(root.collapseButton) then return true end
        for _, edge in ipairs(root.windowEdges or {}) do
            if hovered(edge) then return true end
        end
        for _, grip in ipairs(resizeGrips or {}) do
            if hovered(grip) then return true end
        end
        return false
    end
    local hoverRefreshPending = false
    local function RefreshBoundaryHover()
        if not boundaryHoverMode then return end
        if dragging or resizing then
            hovering = true
        else
            hovering = IsBoundaryRegionHovered() and true or false
        end
        if root.RefreshFrameHeaderVisibility then root:RefreshFrameHeaderVisibility() end
        Repaint()
        RefreshGrip()
    end
    local function ScheduleBoundaryHoverRefresh()
        if not boundaryHoverMode or hoverRefreshPending then return end
        hoverRefreshPending = true
        local function refresh()
            hoverRefreshPending = false
            RefreshBoundaryHover()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, refresh) else refresh() end
    end
    root:HookScript("OnEnter", function()
        if boundaryHoverMode then return end
        hovering = true
        root:RefreshFrameHeaderVisibility()
        Repaint()
        RefreshGrip()
    end)
    root:HookScript("OnLeave", function()
        if boundaryHoverMode then
            ScheduleBoundaryHoverRefresh()
            return
        end
        -- Hover title bars sit outside the basic frame bounds. Keep the
        -- revealed state active while the pointer moves from the frame onto
        -- its external title-bar surface.
        hovering = (root.IsMouseOver and root:IsMouseOver())
            or (header and header.IsMouseOver and header:IsMouseOver())
            or false
        root:RefreshFrameHeaderVisibility()
        Repaint()
        RefreshGrip()
    end)

    local function SaveSize()
        local charState = CharacterWindowState(owner)
        if charState then
            charState.windowSizes[key] = {
                width = root.expandedWidth, height = root.expandedHeight,
            }
        end
    end

    local function EndResize()
        if not resizing then return end
        resizing = false
        activeResizeGrip = nil
        -- The cursor can leave the frame or the window can be hidden mid-drag.
        root:SetScript("OnUpdate", nil)
        SnapWindowRectangle(root)
        SaveSize()
        RefreshScreenAdaptiveAnchor()
        if root.positionAnchorMode ~= "screenAdaptive" then SavePosition() end
        Repaint()
        RefreshGrip()
    end

    local function EndDrag()
        if dragging then
            root:StopMovingOrSizing()
            SnapWindowRectangle(root)
            dragging = false
            RefreshScreenAdaptiveAnchor()
            if root.positionAnchorMode ~= "screenAdaptive" then SavePosition() end
        end
        Repaint()
        RefreshGrip()
    end
    root:SetScript("OnHide", function()
        EndResize()
        EndDrag()
        hovering = false
        Repaint()
    end)

    local function BeginDrag(_, button)
        if not root.movementEnabled or button ~= "LeftButton" or resizing then return end
        Host:BringToFront(root)
        SnapWindowRectangle(root)
        dragging = true
        root:StartMoving()
        Repaint()
        RefreshGrip()
    end
    local function ReleaseDrag(handle, button)
        if button ~= "LeftButton" then return end
        EndDrag()
        hovering = handle:IsMouseOver() and true or false
        Repaint()
        RefreshGrip()
    end
    local function UpdateHover(on)
        if on then
            hovering = true
            if root.RefreshFrameHeaderVisibility then root:RefreshFrameHeaderVisibility() end
        elseif boundaryHoverMode then
            ScheduleBoundaryHoverRefresh()
            return
        elseif frameHeaderMode == "hover" then
            hovering = root.IsMouseOver and root:IsMouseOver() or false
        else
            hovering = false
        end
        Repaint()
        RefreshGrip()
    end

    -- Drag from the title background (excluding action buttons).
    if header then
        header:SetScript("OnEnter", function() UpdateHover(true) end)
        header:SetScript("OnLeave", function() UpdateHover(false) end)
        header:SetScript("OnMouseDown", BeginDrag)
        header:SetScript("OnMouseUp", ReleaseDrag)
    end

    function root:SetDragRegion(region)
        if region ~= "window" and region ~= "border" then return false end
        self.dragRegion = region
        if region == "window" then
            -- Opt-in full-content dragging. Child controls retain their own
            -- mouse handling; otherwise the empty content surface can move it.
            content:EnableMouse(true)
            content:SetScript("OnEnter", function() UpdateHover(true) end)
            content:SetScript("OnLeave", function() UpdateHover(false) end)
            content:SetScript("OnMouseDown", BeginDrag)
            content:SetScript("OnMouseUp", ReleaseDrag)
        else
            content:EnableMouse(true)
            content:SetScript("OnEnter", nil)
            content:SetScript("OnLeave", nil)
            content:SetScript("OnMouseDown", function() Host:BringToFront(root) end)
            content:SetScript("OnMouseUp", nil)
        end
        return true
    end
    root:SetDragRegion(root.dragRegion)
    function root:SetMovableEnabled(enabled)
        local wasEnabled = self.movementEnabled == true
        self.movementEnabled = enabled == true
        self:SetMovable(self.movementEnabled)
        if not self.movementEnabled and dragging then EndDrag() end
        if self.RefreshMovementLockButton then self:RefreshMovementLockButton() end
        if wasEnabled ~= self.movementEnabled and type(options.onMovableChanged) == "function" then
            options.onMovableChanged(self.movementEnabled, self)
        end
        return true
    end
    function root:GetMovableEnabled()
        return self.movementEnabled == true
    end

    -- Four immediate perimeter drag handles, same principle as HUD Groups.
    -- Handles deliberately overlap the first few pixels inside the frame.
    local inside, outside = style.edgeInside, style.edgeOutside
    local function EdgeHandle()
        local edge = CreateFrame("Frame", nil, root)
        edge:SetFrameLevel(root:GetFrameLevel() + 8)
        edge:EnableMouse(true)
        edge:SetScript("OnEnter", function() UpdateHover(true) end)
        edge:SetScript("OnLeave", function() UpdateHover(false) end)
        edge:SetScript("OnMouseDown", BeginDrag)
        edge:SetScript("OnMouseUp", ReleaseDrag)
        return edge
    end
    local top = EdgeHandle()
    top:SetPoint("BOTTOMLEFT", root, "TOPLEFT", -outside, -inside)
    top:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", outside, -inside)
    top:SetHeight(inside + outside)
    local bottom = EdgeHandle()
    bottom:SetPoint("TOPLEFT", root, "BOTTOMLEFT", -outside, inside)
    bottom:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", outside, inside)
    bottom:SetHeight(inside + outside)
    local left = EdgeHandle()
    left:SetPoint("TOPRIGHT", root, "TOPLEFT", inside, outside)
    left:SetPoint("BOTTOMRIGHT", root, "BOTTOMLEFT", inside, -outside)
    left:SetWidth(inside + outside)
    local right = EdgeHandle()
    right:SetPoint("TOPLEFT", root, "TOPRIGHT", -inside, outside)
    right:SetPoint("BOTTOMLEFT", root, "BOTTOMRIGHT", -inside, -outside)
    right:SetWidth(inside + outside)

    -- In the always-visible title layout, the body's visual top edge sits at
    -- the title/body seam rather than at the outer root edge. Give that edge
    -- the same padded hit target so hover and drag survive crossing downward
    -- from the title bar. It follows the window's boundary-hover default.
    local titleSeam
    if boundaryHoverMode and header and bodyBorder and frameHeaderMode == "always" then
        titleSeam = EdgeHandle()
        titleSeam:SetHeight(inside + outside)
        root.UpdateBoundaryTitleSeam = function()
            titleSeam:ClearAllPoints()
            if root.frameHeaderPosition == "bottom" then
                titleSeam:SetPoint("TOPLEFT", bodyBorder, "BOTTOMLEFT", -outside, inside)
                titleSeam:SetPoint("TOPRIGHT", bodyBorder, "BOTTOMRIGHT", outside, inside)
                titleSeam:Show()
            elseif root.frameHeaderPosition == "top" then
                titleSeam:SetPoint("BOTTOMLEFT", bodyBorder, "TOPLEFT", -outside, -inside)
                titleSeam:SetPoint("BOTTOMRIGHT", bodyBorder, "TOPRIGHT", outside, -inside)
                titleSeam:Show()
            else
                -- Side title tabs leave the body's outer side edge in place;
                -- the normal perimeter handle already owns its hover gutter.
                titleSeam:Hide()
            end
        end
        root:UpdateBoundaryTitleSeam()
    end

    -- Root/content mouse events activate the window but do not initiate dragging.
    root.windowEdges = {top, bottom, left, right}
    if titleSeam then root.windowEdges[#root.windowEdges + 1] = titleSeam end

    -- Corner and one-axis grips share the window's existing pixel-snapped
    -- sizing, constraints, persistence, and hover feedback.
    local function PlaceGrip(grip)
        grip:ClearAllPoints()
        grip.icon:ClearAllPoints()
        local mode = grip.resizeMode
        if mode == "corner" then
            if root.frameHeaderPosition == "bottom" then
                grip:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
                grip.icon:SetPoint("TOPLEFT", grip, "TOPLEFT", 2, -2)
                grip.icon:SetTexCoord(1, 0, 1, 0)
            else
                grip:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
                grip.icon:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 2)
                grip.icon:SetTexCoord(0, 1, 0, 1)
            end
            grip.icon:SetRotation(0)
        elseif mode == "left" or mode == "right" then
            local horizontalEdge = mode == "left" and "LEFT" or "RIGHT"
            local insetX = mode == "left" and 7 or -7
            grip:SetPoint("CENTER", root, horizontalEdge, insetX, 0)
            grip.icon:SetPoint("CENTER", grip, "CENTER")
        else
            local verticalEdge = mode == "top" and "TOP" or "BOTTOM"
            local insetY = mode == "top" and -7 or 7
            grip:SetPoint("CENTER", root, verticalEdge, 0, insetY)
            grip.icon:SetPoint("CENTER", grip, "CENTER")
        end
    end

    local function BeginResize(grip, button)
        if button == "RightButton" and grip.resizeMode == "corner"
            and not root.collapsed and not dragging and not resizing then
            Host:BringToFront(root)
            root:SetExpandedSize(root.defaultWindowWidth, root.defaultWindowHeight)
            SaveSize()
            SavePosition()
            Repaint()
            RefreshGrip()
            return
        end
        if button ~= "LeftButton" or root.collapsed or dragging or resizing or not GetCursorPosition then return end
        local left, right, topPos, bottomPos = root:GetLeft(), root:GetRight(), root:GetTop(), root:GetBottom()
        local parentLeft, parentRight = UIParent:GetLeft(), UIParent:GetRight()
        local parentTop, parentBottom = UIParent:GetTop(), UIParent:GetBottom()
        if not (left and right and topPos and bottomPos and parentLeft and parentRight and parentTop and parentBottom) then return end
        local cursorX, cursorY = GetCursorPosition()
        if not (cursorX and cursorY) then return end
        Host:BringToFront(root)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(grip) then GameTooltip:Hide() end
        resizing = true
        activeResizeGrip = grip

        local mode = grip.resizeMode
        local fixedPoint
        if mode == "corner" then
            local fromTopLeft = root.frameHeaderPosition == "bottom"
            fixedPoint = fromTopLeft and "BOTTOMRIGHT" or "TOPLEFT"
        elseif mode == "right" then fixedPoint = "TOPLEFT"
        elseif mode == "left" then fixedPoint = "TOPRIGHT"
        elseif mode == "top" then fixedPoint = "BOTTOMLEFT"
        else fixedPoint = "TOPLEFT" end -- bottom edge
        root:ClearAllPoints()
        if fixedPoint == "TOPLEFT" then
            root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - parentLeft, topPos - parentTop)
        elseif fixedPoint == "TOPRIGHT" then
            root:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", right - parentRight, topPos - parentTop)
        elseif fixedPoint == "BOTTOMLEFT" then
            root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - parentLeft, bottomPos - parentBottom)
        else
            root:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", right - parentRight, bottomPos - parentBottom)
        end

        local startWidth, startHeight = root:GetWidth(), root:GetHeight()
        local startX, startY = cursorX, cursorY
        local scale = EffectiveScale(root)
        local widthSign, heightSign = 0, 0
        if mode == "corner" then
            local fromTopLeft = root.frameHeaderPosition == "bottom"
            widthSign, heightSign = fromTopLeft and -1 or 1, fromTopLeft and 1 or -1
        elseif mode == "right" then widthSign = 1
        elseif mode == "left" then widthSign = -1
        elseif mode == "top" then heightSign = 1
        else heightSign = -1 end

        local maxWidth = widthSign == 0 and startWidth
            or (widthSign > 0 and (parentRight - left - 10) or (right - parentLeft - 10))
        local maxHeight = heightSign == 0 and startHeight
            or (heightSign > 0 and (parentTop - bottomPos - 10) or (topPos - parentBottom - 10))
        root:SetScript("OnUpdate", function()
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then EndResize(); return end
            local x, y = GetCursorPosition()
            if not x or not y then return end
            local deltaWidth = SnapToPixel((x - startX) / scale, scale)
            local deltaHeight = SnapToPixel((y - startY) / scale, scale)
            local w = widthSign == 0 and startWidth or (startWidth + widthSign * deltaWidth)
            local h = heightSign == 0 and startHeight or (startHeight + heightSign * deltaHeight)
            w = math.max(math.min(root.minimumWidth, maxWidth), math.min(maxWidth, w))
            h = math.max(math.min(root.minimumHeight, maxHeight), math.min(maxHeight, h))
            root:SetExpandedSize(w, h)
        end)
        Repaint()
        RefreshGrip()
    end

    local function CreateResizeGrip(mode)
        local grip = CreateFrame("Frame", nil, root)
        grip.resizeMode = mode
        grip:SetFrameLevel(root:GetFrameLevel() + 18)
        grip:EnableMouse(true)
        -- One-axis grips fit the 12-unit pane gutter; their hit area matches
        -- the visible marker and is centered 7 units inward from the edge.
        local gripSize = mode == "corner" and 18 or 12
        grip:SetSize(gripSize, gripSize)
        local icon = grip:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(TBU:GetAssetPath(mode == "corner" and "resize_handle.png" or "radio_checked.png"))
        local iconSize = mode == "corner" and 14 or 12
        icon:SetSize(iconSize, iconSize)
        if mode ~= "corner" then
            -- radio_checked.png has transparent padding around a 17x17 mark.
            -- Crop to that mark so its visible diameter is the full 12 units.
            icon:SetTexCoord(24 / 64, 41 / 64, 24 / 64, 41 / 64)
        end
        grip.icon = icon
        PlaceGrip(grip)
        grip:SetScript("OnEnter", function()
            UpdateHover(true)
            RefreshGrip()
            if GameTooltip then
                GameTooltip:SetOwner(grip, "ANCHOR_RIGHT")
                GameTooltip:SetText("Resize Window")
                local hint = mode == "corner" and "Drag to resize"
                    or ((mode == "left" or mode == "right") and "Drag to change width" or "Drag to change height")
                GameTooltip:AddLine(hint, 0.85, 0.85, 0.87)
                if mode == "corner" then GameTooltip:AddLine("Right-click to restore default size", 0.66, 0.69, 0.72) end
                GameTooltip:Show()
            end
        end)
        grip:SetScript("OnLeave", function()
            RefreshGrip()
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(grip) then GameTooltip:Hide() end
            if not resizing then UpdateHover(false) end
        end)
        grip:SetScript("OnMouseDown", function(_, button) BeginResize(grip, button) end)
        grip:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then EndResize() end end)
        resizeGrips[#resizeGrips + 1] = grip
        return grip
    end

    local resizeConfig = type(options.resizeHandles) == "table" and options.resizeHandles or nil
    local horizontalEdge = resizeConfig and resizeConfig.horizontal
    local verticalEdge = resizeConfig and resizeConfig.vertical
    resizeEnabled = options.resizeHandles ~= false
    local cornerEnabled = resizeEnabled and (not resizeConfig or resizeConfig.corner ~= false)
    if cornerEnabled then resizeGrip = CreateResizeGrip("corner") end
    if resizeEnabled and (horizontalEdge == "left" or horizontalEdge == "right") then CreateResizeGrip(horizontalEdge) end
    if resizeEnabled and (verticalEdge == "top" or verticalEdge == "bottom") then CreateResizeGrip(verticalEdge) end
    root.resizeGrip = resizeGrip
    root.resizeGrips = resizeGrips
    root.PlaceResizeGrip = function()
        for _, grip in ipairs(resizeGrips) do PlaceGrip(grip) end
        RefreshGrip()
    end
    function root:SetResizeEnabled(enabled)
        resizeEnabled = enabled == true
        if not resizeEnabled and resizing then EndResize() end
        RefreshGrip()
        return true
    end
    RefreshGrip()
    -- External page controls may use this shared method after changing their
    -- interaction surface; no per-window resize code is needed.
    function root:CancelResize() EndResize() end

    function root:SetCollapsed(collapsed)
        -- A bare frame has no title-bar surface to collapse into.
        if not header or options.collapseButton == false then return false end
        collapsed = collapsed and true or false
        local wasCollapsed = self.collapsed
        local traceBottomTransition = self.frameHeaderPosition == "bottom" and wasCollapsed ~= collapsed
        if traceBottomTransition then
            self._lastCollapseGeometryTrace = {}
            self._captureCollapseGeometry = true
            CaptureCollapseGeometry("before-transition")
        end
        if not wasCollapsed and collapsed then
            self._expandedAlpha = self:GetAlpha()
        end
        self.collapsed = collapsed
        if self.collapsed then
            content:Hide()
            -- Keep the body rectangle at its expanded size while hidden. The
            -- sibling title bar can then change sides without using a
            -- title-height body rectangle as its anchor reference.
            self:EnableMouse(false)
            content:EnableMouse(false)
            for _, edge in ipairs({top, bottom, left, right}) do
                edge:EnableMouse(false)
            end
            self:SetAlpha(0)
            SetCollapsedHeaderSeam(true)
        else
            self:SetClampRectInsets(0, 0, 0, 0)
            self:EnableMouse(true)
            content:EnableMouse(true)
            for _, edge in ipairs({top, bottom, left, right}) do
                edge:EnableMouse(true)
            end
            content:Show()
            if wasCollapsed then
                self:SetAlpha(self._expandedAlpha or 1)
                SetCollapsedHeaderSeam(false)
            end
        end
        UpdateCollapsedClampInsets()
        CaptureCollapseGeometry("after-clamp-correction")
        local charState = CharacterWindowState(owner)
        if charState then charState.windowCollapsed[key] = self.collapsed end
        if self.collapseButton then
            self.collapseButton.label:SetText("")
        end
        if self.RefreshFrameHeaderVisibility then self:RefreshFrameHeaderVisibility() end
        if self.RefreshResizeGrip then self:RefreshResizeGrip() end
        SavePosition()
        CaptureCollapseGeometry("after-save-position")
        if traceBottomTransition then self._captureCollapseGeometry = false end
        return true
    end

    local close, collapse, movementLock
    if header and options.closeButton ~= false then
        close = Styles:CreateIconButton(header, "exit_icon", function() root:Hide() end, preset)
        close:SetPoint("RIGHT", header, "RIGHT", -frameHeaderPadding.right, 0)
        close:SetFrameLevel(root:GetFrameLevel() + 22)
        root.closeButton = close
    end
    if header and options.collapseButton ~= false then
        collapse = Styles:CreateIconButton(header, "minimize_icon", function()
            root:SetCollapsed(not root.collapsed)
        end, preset)
        collapse:SetPoint("RIGHT", close or header, close and "LEFT" or "RIGHT",
            close and -frameHeaderControlGap or -frameHeaderPadding.right, 0)
        collapse:SetFrameLevel(root:GetFrameLevel() + 22)
        root.collapseButton = collapse
    end
    if header and options.movementLockButton then
        local function GetMovementLockGlyphColor()
            local color = root.movementEnabled
                and Styles:GetWindowBorderColor(root)
                or Styles:GetWindowInteractionColor(root)
            -- The lock glyph follows the border's RGB tint, not its opacity.
            -- Border opacity applies to the frame edge and should never hide
            -- the control that changes movement state.
            return {color[1], color[2], color[3], 1}
        end
        movementLock = Styles:CreateIconButton(header,
            root.movementEnabled and "unlock_icon" or "lock_icon",
            function()
                root:SetMovableEnabled(not root.movementEnabled)
            end,
            preset,
            {
                getGlyphColor = GetMovementLockGlyphColor,
            })
        movementLock:SetPoint("RIGHT", collapse or close or header,
            (collapse or close) and "LEFT" or "RIGHT",
            (collapse or close) and -frameHeaderControlGap or -frameHeaderPadding.right, 0)
        movementLock:SetFrameLevel(root:GetFrameLevel() + 22)
        root.movementLockButton = movementLock
        function root:RefreshMovementLockButton()
            local button = self.movementLockButton
            if not button or not button.icon then return end
            button.icon:SetTexture(TBU:GetAssetPath(
                self.movementEnabled and "unlock_icon.png" or "lock_icon.png"))
            button.icon:SetVertexColor(unpack(GetMovementLockGlyphColor()))
        end
        root:RefreshMovementLockButton()
    end
    if boundaryHoverMode then
        -- Keep the reveal active while the pointer transfers from the title
        -- surface to its child controls; reconcile after WoW dispatches the
        -- matching leave/enter events for adjacent regions.
        for _, button in pairs({close, collapse, movementLock}) do
            if button then
                button:HookScript("OnEnter", function() UpdateHover(true) end)
                button:HookScript("OnLeave", function() ScheduleBoundaryHoverRefresh() end)
            end
        end
    end

    if heading then
        local anchor = movementLock or collapse or close or header
        local anchorPoint = (movementLock or close or collapse) and "LEFT" or "RIGHT"
        heading:SetPoint("RIGHT", anchor, anchorPoint, -frameHeaderPadding.right, 0)
    end
    local function FitWindowTitle()
        if not heading or not header then return end
        if (tonumber(heading:GetWidth()) or 0) <= 1 then return end
        local titleHeight = math.max(1, math.ceil(heading:GetStringHeight() or 1))
        local targetHeight = math.max(style.titleHeight,
            titleHeight + frameHeaderPadding.top + frameHeaderPadding.bottom)
        if math.abs((header:GetHeight() or 0) - targetHeight) > 0.5 then
            header:SetHeight(targetHeight)
            SetContentTitleSpacing(false)
            if root.collapsed then
                UpdateCollapsedClampInsets()
            end
        end
    end
    if header then
        SetFrameHeaderAnchors()
        root:HookScript("OnSizeChanged", SetFrameHeaderAnchors)
        header:HookScript("OnSizeChanged", FitWindowTitle)
        FitWindowTitle()
    end

    -- Defer loading collapsed state until first Show, when the expanded
    -- geometry is resolved and TOPRIGHT can be captured precisely.
    local initiallyCollapsed = header and options.collapseButton ~= false and state and state.windowCollapsed[key] == true
    root.collapsed = false
    root._initialCollapsePending = initiallyCollapsed
    root:SetScript("OnShow", function(self)
        -- Revalidate saved dimensions after a resolution or effective UI-scale
        -- change, including when this character last logged out collapsed.
        self:SetExpandedSize(self.expandedWidth, self.expandedHeight)
        if self._initialCollapsePending then
            self._initialCollapsePending = false
            self:SetCollapsed(true)
        end
        self:RefreshFrameHeaderVisibility()
        Host:BringToFront(self)
    end)
    root:HookScript("OnHide", function(self)
        if header then header:Hide() end
    end)
    root:SetCollapsed(false)
    RefreshGrip()
    Repaint()
    return root
end
