-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Common movable window host. Content and diagnostic logging live elsewhere.
-- Shared border/title interaction deliberately resembles movable group drag handles,
-- but uses muted grayscale feedback and is never controlled by Group lock state.
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

local function SnapWindowRectangle(frame, preserveLogicalSize)
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    local parentLeft, parentBottom = UIParent:GetLeft(), UIParent:GetBottom()
    if not (left and right and bottom and top and parentLeft and parentBottom) then return false end

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
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
        leftPixel / parentScale, bottomPixel / parentScale)
    frame:SetSize(widthPixels / frameScale, heightPixels / frameScale)
    if not preserveLogicalSize then
        if frame.expandedWidth ~= nil then frame.expandedWidth = frame:GetWidth() end
        if frame.expandedHeight ~= nil and not frame.collapsed then frame.expandedHeight = frame:GetHeight() end
    end
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
        if frame.windowHeader then frame.windowHeader:SetFrameLevel(base + 1) end
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
    state.windowTitlePositions = state.windowTitlePositions or {}
    state.windowSizes = state.windowSizes or {}
    return state
end

-- Title chrome is an optional component of the window assembly. Keeping its
-- construction separate lets a consumer request a bare frame without
-- creating title controls or a title label.
local function CreateTitleBar(parent, title, style, outline)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(style.titleHeight)
    header:EnableMouse(true)
    header.bg = Styles:CreateFlatTexture(header, "BACKGROUND", style.title)
    header.bg:SetAllPoints(header)

    local heading = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("LEFT", header, "LEFT", 13, 0)
    heading:SetText(title or "")
    heading:SetTextColor(unpack(style.text))
    heading:SetJustifyH("LEFT")
    heading:SetJustifyV("MIDDLE")
    heading:SetWordWrap(true)
    if heading.SetNonSpaceWrap then heading:SetNonSpaceWrap(true) end
    header.label = heading
    if outline then
        local edgeSize = style.edgeSize or 1
        local edges = {}
        local function AddEdge(point1, relativePoint1, point2, relativePoint2, width, height)
            local edge = Styles:CreateFlatTexture(header, "OVERLAY", style.border)
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
        header.borderEdges = edges
    end
    return header, heading
end

function Host:Create(key, title, width, height, defaultX, defaultY, minWidth, minHeight, owner, options)
    options = options or {}
    -- Keep the established title-bar behavior unless a consumer selects a
    -- different composition. The frame remains usable without title chrome.
    local titleBarMode = options.titleBar
    if titleBarMode == nil then titleBarMode = "always" end
    if titleBarMode ~= "always" and titleBarMode ~= "hover" and titleBarMode ~= "never" then
        titleBarMode = "always"
    end
    local titleBarWidthOption = options.titleBarWidth
    local titleBarWidthMode = titleBarWidthOption == "content" and "content" or "percent"
    local titleBarWidthPercent = tonumber(titleBarWidthOption) or 100
    if titleBarWidthPercent <= 0 then titleBarWidthPercent = 100 end
    local titleBarAnchor = options.titleBarAnchor
    if titleBarAnchor ~= "center" and titleBarAnchor ~= "right" then
        titleBarAnchor = "left"
    end
    local preset = nil -- use live per-owner preset for window chrome
    local style = Styles:Get(Styles:GetConsumerPreset(owner))
    local root = TBU.Compatibility:CreateBackdropFrame("Frame", UIParent)
    root.windowKey = key
    root.storageOwner = owner
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
        self:SetClampedToScreen(true)
        SnapWindowRectangle(self, true)
    end
    local configuredMinWidth = tonumber(options.minWidth)
    local configuredMinHeight = tonumber(options.minHeight)
    root.minimumWidth = configuredMinWidth and math.max(1, configuredMinWidth)
        or math.max(320, tonumber(minWidth) or 320)
    root.minimumHeight = configuredMinHeight and math.max(1, configuredMinHeight)
        or math.max(120, tonumber(minHeight) or 120)
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
    end
    root:SetFrameStrata("DIALOG")
    root.movementEnabled = options.movable ~= false
    root:SetMovable(root.movementEnabled)
    root:EnableMouse(true)
    root:SetClampedToScreen(true)
    root:Hide()

    local state = CharacterWindowState(owner)
    local saved = state and state.windowPositions[key]
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
        and type(saved.point) == "string" and type(saved.relativePoint) == "string" then
        root:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        root:SetPoint("CENTER", UIParent, "CENTER", defaultX or 0, defaultY or 0)
    end
    SnapWindowRectangle(root)

    local header, heading
    if titleBarMode ~= "never" then
        header, heading = CreateTitleBar(root, title, style, true)
        root.windowHeader = header
        root.titleBar = header
    end

    local content = CreateFrame("Frame", nil, root)
    root.content = content

    -- With an always-visible title bar, keep the root's bare-frame outline
    -- around the body only. The title bar supplies its own three outer sides;
    -- the body's top edge meets the open bottom of that title outline.
    local bodyBorder
    if titleBarMode == "always" and header then
        bodyBorder = CreateFrame("Frame", nil, root)
        bodyBorder:EnableMouse(false)
        bodyBorder:SetFrameLevel(root:GetFrameLevel() + 8)
        root.windowBodyBorder = bodyBorder
        root._tbuSplitTitleAndBodyBorder = true
        local edges = {}
        local edgeSize = style.edgeSize or 1
        local function AddEdge(point1, relativePoint1, point2, relativePoint2, width, height)
            local edge = Styles:CreateFlatTexture(bodyBorder, "OVERLAY", style.border)
            edge:SetPoint(point1, bodyBorder, relativePoint1, 0, 0)
            edge:SetPoint(point2, bodyBorder, relativePoint2, 0, 0)
            if width then edge:SetWidth(width) end
            if height then edge:SetHeight(height) end
            edges[#edges + 1] = edge
        end
        AddEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, edgeSize)
        AddEdge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", edgeSize, nil)
        AddEdge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", edgeSize, nil)
        AddEdge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, edgeSize)
        bodyBorder.borderEdges = edges
    end

    local function SetContentTitleSpacing(reserveTitleBar)
        content:ClearAllPoints()
        local titleHeight = reserveTitleBar and header and (header:GetHeight() or 0) or 0
        if root.titlePosition == "bottom" then
            content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
            content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, titleHeight + 2)
        else
            content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -titleHeight - 1)
            content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
        end
    end

    local function SetTitleBarBackgroundBounds()
        if not (header and header.bg) then return end
        header.bg:ClearAllPoints()
        local borderInset = style.edgeSize or 1
        if titleBarMode == "always" and root.titlePosition == "bottom" then
            -- Keep the outer bottom border visible while filling the gap on
            -- the content-facing side of a bottom title bar.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", borderInset, borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -borderInset, borderInset)
        elseif titleBarMode == "always" then
            -- Keep the main frame's top and side outline visible, and extend
            -- only toward the pane to cover the one-unit content seam.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", borderInset, -borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -borderInset, -borderInset)
        else
            -- Hover chrome is outside the main frame, so keep its fill under
            -- its own outline and off the main frame's shared border.
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", borderInset, -borderInset)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -borderInset, borderInset)
        end
    end

    local function TitleBarContentWidth()
        local textWidth = math.max(0, (heading and heading:GetStringWidth()) or 0)
        local closeWidth = root.closeButton and (root.closeButton:GetWidth() or 25) or 0
        local collapseWidth = root.collapseButton and (root.collapseButton:GetWidth() or 25) or 0
        local controlsWidth = closeWidth + collapseWidth
        local controlsGap = closeWidth > 0 and collapseWidth > 0 and 5 or 0
        local labelGap = controlsWidth > 0 and 8 or 0
        return math.ceil(13 + textWidth + labelGap + controlsWidth + controlsGap + 8)
    end

    local function SetTitleBarHorizontalAnchors()
        if not header then return end
        header:ClearAllPoints()
        if root.titlePosition == "bottom" then
            if titleBarMode == "hover" then
                header:SetPoint("TOP", root, "BOTTOM", 0, 0)
            else
                header:SetPoint("BOTTOM", root, "BOTTOM", 0, 1)
            end
        else
            if titleBarMode == "hover" then
                header:SetPoint("BOTTOM", root, "TOP", 0, 0)
            else
                header:SetPoint("TOP", root, "TOP", 0, 0)
            end
        end
        if titleBarWidthMode == "percent" and math.abs(titleBarWidthPercent - 100) < 0.001 then
            header:SetPoint("LEFT", root, "LEFT", 0, 0)
            header:SetPoint("RIGHT", root, "RIGHT", 0, 0)
            return
        end
        local width
        if titleBarWidthMode == "content" then
            width = TitleBarContentWidth()
        else
            width = (tonumber(root:GetWidth()) or 1) * titleBarWidthPercent / 100
        end
        local screenWidth = tonumber(UIParent:GetWidth()) or width
        header:SetWidth(math.max(1, math.min(width, math.max(1, screenWidth - 20))))
        if titleBarAnchor == "center" then
            local leftOffset = ((tonumber(root:GetWidth()) or width) - header:GetWidth()) / 2
            header:SetPoint("LEFT", root, "LEFT", leftOffset, 0)
        elseif titleBarAnchor == "right" then
            header:SetPoint("RIGHT", root, "RIGHT", 0, 0)
        else
            header:SetPoint("LEFT", root, "LEFT", 0, 0)
        end
    end

    local function SetBodyBorderBounds()
        if not bodyBorder or not header then return end
        bodyBorder:ClearAllPoints()
        if root.titlePosition == "bottom" then
            bodyBorder:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
            bodyBorder:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", 0, 0)
        else
            bodyBorder:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            bodyBorder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- One reversible anchor policy for every shared window instance. Both
    -- title label and action buttons are header children and move together.
    function root:SetTitlePosition(position)
        if not header then return false end
        position = position == "bottom" and "bottom" or "top"
        self.titlePosition = position
        SetTitleBarHorizontalAnchors()
        SetTitleBarBackgroundBounds()
        SetBodyBorderBounds()
        -- Hover chrome grows outside the basic frame; it never reserves space
        -- by moving or resizing the content area.
        SetContentTitleSpacing(titleBarMode ~= "hover")
        local charState = CharacterWindowState(owner)
        if charState then charState.windowTitlePositions[key] = position end
        if self.PlaceResizeGrip then self:PlaceResizeGrip() end
    end
    if header then
        root:SetTitlePosition(options.titleBarPosition or (state and state.windowTitlePositions[key]) or "top")
    else
        root.titlePosition = options.titleBarPosition == "bottom" and "bottom" or "top"
        content:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
        content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
    end
    function root:RefreshTitleBarVisibility()
        if not header then return end
        local visible = titleBarMode == "always"
            or (titleBarMode == "hover" and (hovering or dragging or resizing or self.collapsed))
        header:SetShown(visible)
    end
    root:RefreshTitleBarVisibility()
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
        local pane = TBU.Compatibility:CreateBackdropFrame("Frame", parent)
        Styles:ApplyPanel(pane) -- resolve the pane owner on every repaint
        local paneStyle = Styles:Get(Styles:GetConsumerPreset(owner))
        local headerHeight = hasHeader and (options.headerHeight or paneStyle.paneHeaderHeight) or 0
        local footerHeight = options.footer and (options.footerHeight or paneStyle.paneFooterHeight) or 0
        local headerRegion, footerRegion
        if headerHeight > 0 then
            headerRegion = CreateFrame("Frame", nil, pane)
            headerRegion:SetPoint("TOPLEFT", pane, "TOPLEFT", 1, -1)
            headerRegion:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -1, -1)
            headerRegion:SetHeight(headerHeight)
            local headerFill = sectionHeader and paneStyle.sectionHeaderFill or paneStyle.panel
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
                local color = sectionHeader and currentStyle.sectionHeaderFill or currentStyle.panel
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
        pane.footerRegion = footerRegion
        pane.isNavigationPane = isNavigationPane
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
            local headerLabel, headerNote
            local autoSizeHeader = options.headerAutoSize ~= false or isNavigationPane
            local paddingX = tonumber(options.headerPaddingX) or paneStyle.paneHeaderPaddingX or 12
            local paddingY = tonumber(options.headerPaddingY) or paneStyle.paneHeaderPaddingY or 10
            local textGap = tonumber(options.headerTextGap) or paneStyle.paneHeaderTextGap or 4
            local function FitHeader()
                if not headerLabel then return end
                local width = math.max(1, headerRegion:GetWidth() - paddingX * 2)
                headerLabel:SetWidth(width)
                if headerNote then headerNote:SetWidth(width) end
                headerLabel:ClearAllPoints()
                headerLabel:SetPoint("TOPLEFT", headerRegion, "TOPLEFT", paddingX, -paddingY)
                if headerNote then
                    headerNote:ClearAllPoints()
                    headerNote:SetPoint("TOPLEFT", headerLabel, "BOTTOMLEFT", 0, -textGap)
                end
                local titleHeight = math.max(1, headerLabel:GetStringHeight() or headerLabel:GetHeight() or 1)
                local noteHeight = headerNote and headerNote:IsShown()
                    and math.max(1, headerNote:GetStringHeight() or headerNote:GetHeight() or 1) or 0
                if autoSizeHeader then
                    local measuredHeight = paddingY + titleHeight + (noteHeight > 0 and textGap + noteHeight or 0) + paddingY
                    if math.abs(headerRegion:GetHeight() - measuredHeight) > 0.5 then
                        headerRegion:SetHeight(measuredHeight)
                    end
                elseif noteHeight <= 0 then
                    headerLabel:ClearAllPoints()
                    headerLabel:SetPoint("LEFT", headerRegion, "LEFT", paddingX, 0)
                end
            end
            function pane:SetHeaderText(titleText, noteText)
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
    local activeResizeGrip
    local highlight = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = Styles:CreateFlatTexture(root, "OVERLAY", Styles:GetForFrame(root).resizeHighlight)
        Styles:RegisterVisual(tex, function(target)
            target:SetVertexColor(unpack(Styles:GetForFrame(target).resizeHighlight))
        end)
        if side == "TOP" then
            tex:SetPoint("BOTTOMLEFT", root, "TOPLEFT", -1, 0)
            tex:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 1, 0)
            tex:SetHeight(1)
        elseif side == "BOTTOM" then
            tex:SetPoint("TOPLEFT", root, "BOTTOMLEFT", -1, 0)
            tex:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 1, 0)
            tex:SetHeight(1)
        elseif side == "LEFT" then
            tex:SetPoint("TOPRIGHT", root, "TOPLEFT", 0, 1)
            tex:SetPoint("BOTTOMRIGHT", root, "BOTTOMLEFT", 0, -1)
            tex:SetWidth(1)
        else
            tex:SetPoint("TOPLEFT", root, "TOPRIGHT", 0, 1)
            tex:SetPoint("BOTTOMLEFT", root, "BOTTOMRIGHT", 0, -1)
            tex:SetWidth(1)
        end
        tex:Hide()
        highlight[#highlight + 1] = tex
    end

    local function Repaint()
        style = Styles:Get(Styles:GetConsumerPreset(owner))
        local current = (dragging or resizing) and "drag" or hovering and "hover" or "normal"
        Styles:ApplyWindow(root, current, Styles:GetConsumerPreset(owner))
        for _, tex in ipairs(highlight) do
            if current == "normal" then tex:Hide() else
                tex:SetAlpha((dragging or resizing) and 0.42 or 0.19)
                tex:Show()
            end
        end
        if root.RefreshTitleBarVisibility then root:RefreshTitleBarVisibility() end
    end
    root.RefreshWindowStyle = Repaint
    Styles:RegisterVisual(root, function(window)
        if window.RefreshWindowStyle then window:RefreshWindowStyle() end
        if window.RefreshResizeGrip then window:RefreshResizeGrip() end
    end)

    local function SavePosition()
        local charState = CharacterWindowState(owner)
        if not charState then return end
        local point, _, relativePoint, x, y = root:GetPoint(1)
        if point and relativePoint and type(x) == "number" and type(y) == "number" then
            charState.windowPositions[key] = {
                point = point, relativePoint = relativePoint, x = x, y = y,
            }
        end
    end

    local function RefreshGrip()
        for _, grip in ipairs(resizeGrips) do
            if root.collapsed then
                grip:Hide()
            else
                -- Keep each hit target active while its small glyph stays hidden
                -- until the window or that specific grip is hovered.
                grip:Show()
                if grip.icon then
                    local active = resizing and activeResizeGrip == grip
                    local gold = grip:IsMouseOver() or active
                    grip.icon:SetVertexColor(unpack(gold and style.interactionGold or style.resizeGripIdle))
                    grip.icon:SetShown(hovering or dragging or active or gold)
                end
            end
        end
    end
    root.RefreshResizeGrip = RefreshGrip
    root:HookScript("OnEnter", function()
        hovering = true
        root:RefreshTitleBarVisibility()
        Repaint()
        RefreshGrip()
    end)
    root:HookScript("OnLeave", function()
        -- Hover title bars sit outside the basic frame bounds. Keep the
        -- revealed state active while the pointer moves from the frame onto
        -- its external title-bar surface.
        hovering = (root.IsMouseOver and root:IsMouseOver())
            or (header and header.IsMouseOver and header:IsMouseOver())
            or false
        root:RefreshTitleBarVisibility()
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
        SavePosition()
        Repaint()
        RefreshGrip()
    end

    local function EndDrag()
        if dragging then
            root:StopMovingOrSizing()
            SnapWindowRectangle(root)
            dragging = false
            SavePosition()
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
        elseif titleBarMode == "hover" then
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
        header:SetScript("OnMouseUp", function(handle, button)
            if button == "RightButton" then
                EndDrag()
                root:SetTitlePosition(root.titlePosition == "top" and "bottom" or "top")
                TBU:Log(owner, "Window title: " .. root.titlePosition .. " (" .. key .. ")")
            else
                ReleaseDrag(handle, button)
            end
        end)
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

    -- Root/content mouse events activate the window but do not initiate dragging.
    root.windowEdges = {top, bottom, left, right}

    -- Corner and one-axis grips share the window's existing pixel-snapped
    -- sizing, constraints, persistence, and hover feedback.
    local function PlaceGrip(grip)
        grip:ClearAllPoints()
        grip.icon:ClearAllPoints()
        local mode = grip.resizeMode
        if mode == "corner" then
            if root.titlePosition == "bottom" then
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
            local fromTopLeft = root.titlePosition == "bottom"
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
            local fromTopLeft = root.titlePosition == "bottom"
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
    local resizeEnabled = options.resizeHandles ~= false
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
    RefreshGrip()
    -- External page controls may use this shared method after changing their
    -- interaction surface; no per-window resize code is needed.
    function root:CancelResize() EndResize() end

    -- Collapse pins the title-side right corner (TOPRIGHT or BOTTOMRIGHT).
    -- Resizing pins the opposite edge or corner of its active grip.
    local function PinTitleCorner()
        local right = root:GetRight()
        local parentRight = UIParent:GetRight()
        if not right or not parentRight then return false end
        if root.titlePosition == "bottom" then
            local bottom, parentBottom = root:GetBottom(), UIParent:GetBottom()
            if not bottom or not parentBottom then return false end
            root:ClearAllPoints()
            root:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", right - parentRight, bottom - parentBottom)
        else
            local top, parentTop = root:GetTop(), UIParent:GetTop()
            if not top or not parentTop then return false end
            root:ClearAllPoints()
            root:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", right - parentRight, top - parentTop)
        end
        return true
    end


    -- Window action glyphs are framework-owned assets. The surrounding button
    -- supplies hover, pressed and disabled states; glyph tint follows the same
    -- active style as the window controls without a separate palette.
    local function SetWindowButtonGlyph(button, assetName)
        button.label:SetText("")
        local glyph = button:CreateTexture(nil, "OVERLAY")
        glyph:SetTexture(TBU:GetAssetPath(assetName .. ".png"))
        glyph:SetSize(16, 16)
        glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
        local function RepaintGlyph(target)
            local current = Styles:GetForFrame(target)
            glyph:SetVertexColor(unpack((target.tbuPressed or target:IsMouseOver())
                and (current.interactionGold or current.borderHover) or current.text))
        end
        Styles:RegisterVisual(glyph, function() RepaintGlyph(button) end)
        button:HookScript("OnEnter", RepaintGlyph)
        button:HookScript("OnLeave", RepaintGlyph)
        button:HookScript("OnMouseDown", RepaintGlyph)
        button:HookScript("OnMouseUp", RepaintGlyph)
        RepaintGlyph(button)
        return glyph
    end

    function root:SetCollapsed(collapsed)
        -- A bare frame has no title-bar surface to collapse into.
        if not header or options.collapseButton == false then return false end
        collapsed = collapsed and true or false
        if self.collapsed ~= collapsed then
            if PinTitleCorner() then SavePosition() end
        end
        self.collapsed = collapsed
        if self.collapsed then
            content:Hide()
            self:SetHeight(header:GetHeight() + 2)
        else
            self:SetHeight(self.expandedHeight)
            content:Show()
        end
        local charState = CharacterWindowState(owner)
        if charState then charState.windowCollapsed[key] = self.collapsed end
        if self.collapseButton then
            self.collapseButton.label:SetText("")
        end
        if self.RefreshTitleBarVisibility then self:RefreshTitleBarVisibility() end
        if self.RefreshResizeGrip then self:RefreshResizeGrip() end
        return true
    end

    local close, collapse
    if header and options.closeButton ~= false then
        close = Styles:CreateButton(header, "X", 25, function() root:Hide() end, preset)
        close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
        close:SetFrameLevel(root:GetFrameLevel() + 22)
        close:SetHeight(24)
        SetWindowButtonGlyph(close, "exit_icon")
        root.closeButton = close
    end
    if header and options.collapseButton ~= false then
        collapse = Styles:CreateButton(header, "—", 25, function()
            root:SetCollapsed(not root.collapsed)
        end, preset)
        collapse:SetPoint("RIGHT", close or header, close and "LEFT" or "RIGHT", close and -5 or -8, 0)
        collapse:SetFrameLevel(root:GetFrameLevel() + 22)
        collapse:SetHeight(24)
        SetWindowButtonGlyph(collapse, "minimize_icon")
        root.collapseButton = collapse
    end

    if heading then
        local anchor = collapse or close or header
        local anchorPoint = (close or collapse) and "LEFT" or "RIGHT"
        heading:SetPoint("RIGHT", anchor, anchorPoint, -8, 0)
    end
    local function FitWindowTitle()
        if not heading or not header then return end
        if (tonumber(heading:GetWidth()) or 0) <= 1 then return end
        local titleHeight = math.max(1, math.ceil(heading:GetStringHeight() or 1))
        local targetHeight = math.max(style.titleHeight, titleHeight + 4)
        if math.abs((header:GetHeight() or 0) - targetHeight) > 0.5 then
            header:SetHeight(targetHeight)
            SetContentTitleSpacing(titleBarMode ~= "hover")
            if root.collapsed then root:SetHeight(targetHeight + 2) end
        end
    end
    if header then
        SetTitleBarHorizontalAnchors()
        if titleBarWidthMode ~= "percent" or math.abs(titleBarWidthPercent - 100) >= 0.001 then
            root:HookScript("OnSizeChanged", SetTitleBarHorizontalAnchors)
        end
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
        Host:BringToFront(self)
    end)
    root:SetCollapsed(false)
    RefreshGrip()
    Repaint()
    return root
end
