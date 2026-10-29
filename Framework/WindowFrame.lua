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
        if frame.windowEdges then
            for _, edge in ipairs(frame.windowEdges) do edge:SetFrameLevel(base + 8) end
        end
        if frame.closeButton then frame.closeButton:SetFrameLevel(base + 22) end
        if frame.collapseButton then frame.collapseButton:SetFrameLevel(base + 22) end
        if frame.resizeGrip then frame.resizeGrip:SetFrameLevel(base + 18) end
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

function Host:Create(key, title, width, height, defaultX, defaultY, minWidth, minHeight, owner)
    local preset = nil -- use live per-owner preset for window chrome
    local style = Styles:Get(Styles:GetConsumerPreset(owner))
    local root = TBU.Compatibility:CreateBackdropFrame("Frame", UIParent)
    root.windowKey = key
    root.storageOwner = owner
    root.defaultWindowWidth = width
    root.defaultWindowHeight = height
    function root:BringToFront() Host:BringToFront(self) end
    -- Native UI scale is the default. The sandbox may explicitly apply an
    -- independent window scale through SetWindowUIScale without changing UIParent.
    function root:SetWindowUIScale(scale)
        scale = tonumber(scale) or 1
        scale = math.max(0.75, math.min(1.10, scale))
        self:SetScale(scale)
        self:SetClampedToScreen(true)
    end
    root.minimumWidth = math.max(320, tonumber(minWidth) or 320)
    root.minimumHeight = math.max(120, tonumber(minHeight) or 120)
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
    end
    root:SetFrameStrata("DIALOG")
    root:SetMovable(true)
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

    local header = CreateFrame("Frame", nil, root)
    header:SetHeight(style.titleHeight)
    header:EnableMouse(true)
    header.bg = Styles:CreateFlatTexture(header, "BACKGROUND", style.title)
    header.bg:SetAllPoints(header)
    root.windowHeader = header

    local heading = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("LEFT", header, "LEFT", 13, 0)
    heading:SetText(title)
    heading:SetTextColor(unpack(style.text))
    heading:SetJustifyH("LEFT")
    header.label = heading

    local content = CreateFrame("Frame", nil, root)
    root.content = content

    -- One reversible anchor policy for every shared window instance. Both
    -- title label and action buttons are header children and move together.
    function root:SetTitlePosition(position)
        position = position == "bottom" and "bottom" or "top"
        self.titlePosition = position
        header:ClearAllPoints()
        content:ClearAllPoints()
        if position == "bottom" then
            header:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 1, 1)
            header:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
            content:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            content:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", 0, 1)
        else
            header:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            header:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -1)
            content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
            content:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
        end
        local charState = CharacterWindowState(owner)
        if charState then charState.windowTitlePositions[key] = position end
        if self.PlaceResizeGrip then self:PlaceResizeGrip() end
    end
    root:SetTitlePosition(state and state.windowTitlePositions[key] or "top")
    -- Generic window pane chrome. All contents (settings/debug/future notepad)
    -- can request a compact header and footer from one shared layout host.
    -- Header/footer are structural slots, not page-specific content builders.
    function root:CreatePane(parent, options)
        options = options or {}
        local pane = TBU.Compatibility:CreateBackdropFrame("Frame", parent)
        Styles:ApplyPanel(pane) -- resolve the pane owner on every repaint
        local paneStyle = Styles:Get(Styles:GetConsumerPreset(owner))
        local headerHeight = options.header and (options.headerHeight or paneStyle.paneHeaderHeight) or 0
        local footerHeight = options.footer and (options.footerHeight or paneStyle.paneFooterHeight) or 0
        local headerRegion, footerRegion
        if headerHeight > 0 then
            headerRegion = CreateFrame("Frame", nil, pane)
            headerRegion:SetPoint("TOPLEFT", pane, "TOPLEFT", 1, -1)
            headerRegion:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -1, -1)
            headerRegion:SetHeight(headerHeight)
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
        pane:EnableMouse(true)
        pane:SetScript("OnMouseDown", function() Host:BringToFront(root) end)
        return pane
    end
    content:EnableMouse(true)
    content:SetScript("OnMouseDown", function() Host:BringToFront(root) end)
    root:HookScript("OnMouseDown", function() Host:BringToFront(root) end)

    local hovering, dragging, resizing = false, false, false
    local resizeGrip
    local highlight = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = Styles:CreateFlatTexture(root, "OVERLAY", { 0.50, 0.51, 0.55, 0.20 })
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
        if not resizeGrip then return end
        if root.collapsed then
            resizeGrip:Hide()
            return
        end
        -- Keep the hit target active even when the glyph is visually hidden;
        -- otherwise a direct mouse entry into the corner cannot reveal it.
        resizeGrip:Show()
        if resizeGrip.icon then
            local gold = resizeGrip:IsMouseOver() or resizing
            resizeGrip.icon:SetVertexColor(unpack(gold and style.interactionGold or style.resizeGripIdle))
            resizeGrip.icon:SetShown(hovering or dragging or resizing or gold)
        end
    end
    root.RefreshResizeGrip = RefreshGrip
    root:HookScript("OnEnter", function() hovering = true; Repaint(); RefreshGrip() end)
    root:HookScript("OnLeave", function() hovering = false; Repaint(); RefreshGrip() end)

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
        -- The cursor can leave the frame or the window can be hidden mid-drag.
        root:SetScript("OnUpdate", nil)
        SaveSize()
        SavePosition()
        Repaint()
        RefreshGrip()
    end

    local function EndDrag()
        if dragging then
            root:StopMovingOrSizing()
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
        if button ~= "LeftButton" or resizing then return end
        Host:BringToFront(root)
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
        hovering = on and true or false
        Repaint()
        RefreshGrip()
    end

    -- Drag from the title background (excluding action buttons).
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

    -- One shared resize interaction for both title positions. The *visible*
    -- texture is small, but the hit box stays generous for precise mouse use.
    -- Artwork is monochrome and tintable; no per-window grip renderer.
    resizeGrip = CreateFrame("Frame", nil, root)
    resizeGrip:SetSize(18, 18)
    resizeGrip:SetFrameLevel(root:GetFrameLevel() + 18)
    resizeGrip:EnableMouse(true)
    local gripIcon = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripIcon:SetTexture(TBU:GetAssetPath("resize_handle.png"))
    gripIcon:SetSize(14, 14)
    resizeGrip.icon = gripIcon
    local gripHovered = false
    local function RepaintGrip()
        -- The grey grip becomes gold only when directly hovered or dragging.
        local color = (gripHovered or resizing) and style.interactionGold or style.resizeGripIdle
        gripIcon:SetVertexColor(unpack(color))
        gripIcon:SetShown(hovering or dragging or resizing or gripHovered)
    end
    local function PlaceGrip()
        resizeGrip:ClearAllPoints()
        gripIcon:ClearAllPoints()
        if root.titlePosition == "bottom" then
            resizeGrip:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
            gripIcon:SetPoint("TOPLEFT", resizeGrip, "TOPLEFT", 2, -2)
            -- Turn the lower-right motif toward the upper-left corner.
            gripIcon:SetTexCoord(1, 0, 1, 0)
        else
            resizeGrip:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
            gripIcon:SetPoint("BOTTOMRIGHT", resizeGrip, "BOTTOMRIGHT", -2, 2)
            gripIcon:SetTexCoord(0, 1, 0, 1)
        end
        RepaintGrip()
    end
    root.PlaceResizeGrip = PlaceGrip
    PlaceGrip()
    resizeGrip:Hide()
    resizeGrip:SetScript("OnEnter", function()
        gripHovered = true
        UpdateHover(true)
        RepaintGrip()
        if GameTooltip then
            GameTooltip:SetOwner(resizeGrip, "ANCHOR_RIGHT")
            GameTooltip:SetText("Resize Window")
            GameTooltip:AddLine("Drag to resize", 0.85, 0.85, 0.87)
            GameTooltip:AddLine("Right-click to restore default size", 0.66, 0.69, 0.72)
            GameTooltip:Show()
        end
    end)
    resizeGrip:SetScript("OnLeave", function()
        gripHovered = false
        RepaintGrip()
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(resizeGrip) then GameTooltip:Hide() end
        if not resizing then UpdateHover(false) end
    end)
    resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" and not root.collapsed and not dragging and not resizing then
            Host:BringToFront(root)
            root:SetExpandedSize(root.defaultWindowWidth, root.defaultWindowHeight)
            SaveSize()
            SavePosition()
            Repaint()
            RefreshGrip()
            return
        end
        if button ~= "LeftButton" or root.collapsed or dragging or resizing then return end
        if not GetCursorPosition then return end
        local left, right, topPos, bottomPos = root:GetLeft(), root:GetRight(), root:GetTop(), root:GetBottom()
        local parentLeft, parentRight = UIParent:GetLeft(), UIParent:GetRight()
        local parentTop, parentBottom = UIParent:GetTop(), UIParent:GetBottom()
        if not (left and right and topPos and bottomPos and parentLeft and parentRight and parentTop and parentBottom) then return end
        local cursorX, cursorY = GetCursorPosition()
        if not (cursorX and cursorY) then return end
        Host:BringToFront(root)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(resizeGrip) then GameTooltip:Hide() end
        resizing = true
        local fromTopLeft = root.titlePosition == "bottom"
        -- Pin the corner opposite the grip; SetWidth/SetHeight then change
        -- only the dragged sides. WoW cursor values are physical pixels.
        root:ClearAllPoints()
        if fromTopLeft then
            root:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", right - parentRight, bottomPos - parentBottom)
        else
            root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - parentLeft, topPos - parentTop)
        end
        local startWidth, startHeight = root:GetWidth(), root:GetHeight()
        local startX, startY = cursorX, cursorY
        local maxWidth = fromTopLeft and (right - parentLeft - 10) or (parentRight - left - 10)
        local maxHeight = fromTopLeft and (parentTop - bottomPos - 10) or (topPos - parentBottom - 10)
        local scale = root:GetEffectiveScale()
        if not scale or scale <= 0 then scale = 1 end
        root:SetScript("OnUpdate", function()
            -- MouseUp can land outside the grip. Never leave a permanent
            -- OnUpdate running after the user releases the drag.
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                EndResize()
                return
            end
            local x, y = GetCursorPosition()
            if not x or not y then return end
            local sign = fromTopLeft and -1 or 1
            local w = startWidth + sign * (x - startX) / scale
            local h = startHeight + (fromTopLeft and 1 or -1) * (y - startY) / scale
            w = math.max(math.min(root.minimumWidth, maxWidth), math.min(maxWidth, w))
            h = math.max(math.min(root.minimumHeight, maxHeight), math.min(maxHeight, h))
            root:SetExpandedSize(w, h)
        end)
        Repaint()
        RefreshGrip()
    end)
    resizeGrip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then EndResize() end
    end)
    root.resizeGrip = resizeGrip
    -- External page controls may use this shared method after changing their
    -- interaction surface; no per-window resize code is needed.
    function root:CancelResize() EndResize() end

    -- Collapse pins the title-side right corner (TOPRIGHT or BOTTOMRIGHT).
    -- Resizing instead pins the diagonal opposite corner of the grip.
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
        collapsed = collapsed and true or false
        if self.collapsed ~= collapsed then
            if PinTitleCorner() then SavePosition() end
        end
        self.collapsed = collapsed
        if self.collapsed then
            content:Hide()
            self:SetHeight(style.titleHeight + 2)
        else
            self:SetHeight(self.expandedHeight)
            content:Show()
        end
        local charState = CharacterWindowState(owner)
        if charState then charState.windowCollapsed[key] = self.collapsed end
        if self.collapseButton then
            self.collapseButton.label:SetText("")
        end
        if self.RefreshResizeGrip then self:RefreshResizeGrip() end
    end

    local close = Styles:CreateButton(header, "X", 25, function() root:Hide() end, preset)
    close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    close:SetFrameLevel(root:GetFrameLevel() + 22)
    close:SetHeight(24)
    SetWindowButtonGlyph(close, "exit_icon")
    root.closeButton = close
    local collapse = Styles:CreateButton(header, "—", 25, function()
        root:SetCollapsed(not root.collapsed)
    end, preset)
    collapse:SetPoint("RIGHT", close, "LEFT", -5, 0)
    collapse:SetFrameLevel(root:GetFrameLevel() + 22)
    collapse:SetHeight(24)
    SetWindowButtonGlyph(collapse, "minimize_icon")
    root.collapseButton = collapse

    -- Defer loading collapsed state until first Show, when the expanded
    -- geometry is resolved and TOPRIGHT can be captured precisely.
    local initiallyCollapsed = state and state.windowCollapsed[key] == true
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
