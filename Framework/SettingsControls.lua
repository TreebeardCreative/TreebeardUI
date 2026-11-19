-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

TBU.SettingsControls = TBU.SettingsControls or {}
local SC = TBU.SettingsControls

-- Reusable Settings Content/control implementation.
-- Settings.lua owns semantic settings definitions and callbacks; this file owns
-- generic control construction, interaction, intrinsic metrics, and internal flow.
--
-- CONTROL LIFECYCLE CONTRACT (required for every NEW stateful control):
--  1. Accept consumer-owned getter/setter; never store consumer settings here.
--  2. Register a visual refresh via RegisterStatefulControl below.
--  3. Read the getter during refresh; update visuals without calling setter.
--  4. After a user-initiated setter, call TBU:RefreshAll() to synchronize peers.
--  5. Guard programmatic refresh against recursive OnValueChanged callbacks.
--  6. Keep SPECIAL behavior (e.g., commitOnRelease) in that control's own code.
--  7. For future disposable controls, add an explicit unregister lifecycle;
--     today's Settings controls are persistent for their window lifetime.
-- Action-only buttons have no value to refresh unless their visuals depend on
-- consumer state. Do not implement sandbox-specific peer synchronization here.
--
-- CHECKLIST FOR A NEW CONTROL: getter, setter, refresh registration,
-- user-change broadcast, recursion guard, and any special interaction policy.

-- The shared registration point is intentionally obvious to future authors.
-- It delegates coordination to the library's single refresh manager.
local function RegisterStatefulControl(control, refreshFromGetter)
    assert(type(refreshFromGetter) == "function", "stateful control must provide refresh-from-getter")
    TBU:RegisterRefreshControl(control, refreshFromGetter)
end

local ApplyRecessedInput

-- Release text focus when a mouse press begins outside the edit field.
-- WoW clients expose different mouse-focus APIs; geometry is a fallback when
-- the focus API reports a covering parent frame instead of the input itself.
local inputFocusWatch = CreateFrame("Frame")
inputFocusWatch:Hide()
local watchedInput, mousePreviouslyDown = nil, false
local function IsWithinInput(region, edit)
    local current = region
    while current do
        if current == edit then return true end
        if not current.GetParent then break end
        current = current:GetParent()
    end
    return false
end
local function CursorInside(edit)
    if not edit or not edit.GetRect or not GetCursorPosition then return false end
    local left, bottom, width, height = edit:GetRect()
    if not left or not bottom or not width or not height then return false end
    local x, y = GetCursorPosition()
    local scale = edit:GetEffectiveScale()
    if not scale or scale <= 0 then return false end
    x, y = x / scale, y / scale
    return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end
local function FocusedRegionIsInput(edit)
    if CursorInside(edit) then return true end
    if GetMouseFoci then
        local regions = GetMouseFoci()
        if type(regions) == "table" then
            for _, region in ipairs(regions) do
                if IsWithinInput(region, edit) then return true end
            end
        end
    end
    return GetMouseFocus and IsWithinInput(GetMouseFocus(), edit) or false
end
local function WatchInputFocus(edit)
    watchedInput = edit
    mousePreviouslyDown = (IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))) or false
    inputFocusWatch:Show()
end
local function StopWatchingInput(edit)
    if watchedInput ~= edit then return end
    watchedInput = nil
    inputFocusWatch:Hide()
end
-- Share one authoritative focus state across every visual attached to an
-- EditBox. Widget focus events update it immediately; Refresh also reconciles
-- against HasFocus so a missed/replaced callback cannot leave stale styling.
local InputFocus = TBU.InputFocus or {}
TBU.InputFocus = InputFocus
local function SetInputFocused(edit, focused)
    local state = edit and edit._tbuInputFocusState
    if not state then return end
    focused = focused == true
    if state.focused == focused then return end
    state.focused = focused
    for _, listener in ipairs(state.listeners) do
        listener(focused, edit)
    end
end
function InputFocus:Attach(edit, onChanged)
    if not edit or not edit.HookScript or not edit.HasFocus then return nil end
    local state = edit._tbuInputFocusState
    if not state then
        state = { focused = edit:HasFocus() and true or false, listeners = {} }
        edit._tbuInputFocusState = state
        edit:HookScript("OnEditFocusGained", function()
            SetInputFocused(edit, true)
            WatchInputFocus(edit)
        end)
        edit:HookScript("OnEditFocusLost", function()
            SetInputFocused(edit, false)
            -- The focus-lost event is authoritative here. Do not poll this
            -- EditBox again: a stale HasFocus result could re-enable its
            -- interaction visuals after the blur event.
            StopWatchingInput(edit)
        end)
    end
    if type(onChanged) == "function" then
        state.listeners[#state.listeners + 1] = onChanged
        onChanged(state.focused, edit)
    end
    if state.focused then WatchInputFocus(edit) end
    return state
end
function InputFocus:IsFocused(edit)
    local state = edit and edit._tbuInputFocusState
    if state then return state.focused end
    return edit and edit.HasFocus and edit:HasFocus() or false
end
function InputFocus:Refresh(edit)
    if not edit or not edit.HasFocus then return false end
    local focused = edit.IsShown and edit:IsShown() and edit:HasFocus() or false
    SetInputFocused(edit, focused)
    if focused then WatchInputFocus(edit) else StopWatchingInput(edit) end
    return focused
end
inputFocusWatch:SetScript("OnUpdate", function()
    local edit = watchedInput
    if not edit then
        watchedInput = nil
        inputFocusWatch:Hide()
        return
    end
    if not InputFocus:Refresh(edit) then return end
    local down = (IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))) or false
    if down and not mousePreviouslyDown and not FocusedRegionIsInput(edit) then
        edit:ClearFocus()
        InputFocus:Refresh(edit)
    end
    mousePreviouslyDown = down
end)

-- Framework-owned image asset. The consumer can hide it per ordinary input;
-- color inputs use the swatch in the same position instead.
local function AddTextInputGlyph(edit)
    local icon = edit:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(TBU:GetAssetPath("text_input_icon.png"))
    icon:SetSize(16, 16)
    icon:SetPoint("RIGHT", edit, "RIGHT", -6, 0)
    local function repaint()
        local styles = TBU.WindowStyles
        local color = TBU.InputFocus:IsFocused(edit)
            and styles:GetWindowInteractionColor(edit)
            or styles:GetControlBorderColor(edit)
        icon:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
    TBU.WindowStyles:RegisterVisual(icon, repaint)
    TBU.InputFocus:Attach(edit, repaint)
    return icon
end

local ControlMetrics = {
    DROPDOWN_OPTION_INDICATOR_SIZE = 18,
    STANDALONE_OPTION_INDICATOR_SIZE = 18,
    RADIO_OPTION_MIN_HEIGHT = 24,
    RADIO_OPTION_GAP = 0,
    RADIO_INDICATOR_LEFT_INSET = 0,
    RADIO_TEXT_GAP = 4,
    RADIO_TEXT_RIGHT_INSET = 0,
    RADIO_TEXT_VERTICAL_PADDING = 4,
    RADIO_LABEL_TO_OPTIONS_GAP = 2,
    RADIO_HIGHLIGHT_EXTRA_WIDTH_RATIO = 0.20,
}

local DropdownMetrics = {
    LABEL_HEIGHT = 14,
    LABEL_TO_CONTROL_GAP = 2,
    DISPLAY_LEFT_INSET = 13,
    DISPLAY_RIGHT_INSET = 32,
    MENU_OFFSET_Y = -1,
    MENU_BORDER_SIZE = 1,
    MENU_BACKGROUND = {0.055, 0.055, 0.065, 0.95},
    MENU_BORDER = {0.76, 0.56, 0.20, 1},
    MENU_HORIZONTAL_INSET = 2,
    MENU_TOP_PADDING = 4,
    MENU_BOTTOM_PADDING = 4,
    OPTION_GAP = 0,
    OPTION_MIN_HEIGHT = 24,
    OPTION_INDICATOR_LEFT_INSET = 6,
    OPTION_TEXT_GAP = 4,
    OPTION_TEXT_RIGHT_INSET = 6,
    OPTION_TEXT_VERTICAL_PADDING = 4,
    HEADER_HORIZONTAL_INSET = 6,
    HEADER_TOP_PADDING = 6,
    HEADER_TEXT_TO_DIVIDER_GAP = 3,
    HEADER_BOTTOM_PADDING = 3,
    MAX_VISIBLE_OPTIONS = 5,
    SCROLLBAR_WIDTH = 16,
    SCROLL_ARROW_HEIGHT = 17,
    SCROLL_THUMB_MIN_HEIGHT = 12,
    SCROLL_THUMB_MAX_HEIGHT = 32,
    SCROLL_THUMB_WIDTH = 9,
    SCROLL_THUMB_SCALE = 0.65,
    SLIM_SCROLLBAR_WIDTH = 12,
    SLIM_SCROLLBAR_GUTTER_WIDTH = 12,
    SLIM_SCROLLBAR_GAP = 2,
    SLIM_SCROLLBAR_TOP_INSET = 3,
    SLIM_SCROLLBAR_BOTTOM_INSET = 12,
    SLIM_SCROLLBAR_WHEEL_TOP_INSET = 2,
    SLIM_SCROLLBAR_WHEEL_BOTTOM_INSET = 15,
    SLIM_SCROLLBAR_TRACK_WIDTH = 1,
    SLIM_SCROLLBAR_THUMB_WIDTH = 17,
    SLIM_SCROLLBAR_THUMB_HEIGHT = 30,
}

local function SetDropdownDisplayText(fontString, fullText, availableWidth)
    if not fontString then return end
    fullText = tostring(fullText or "")
    availableWidth = math.max(1, tonumber(availableWidth) or 1)
    fontString:SetWordWrap(false)
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(false) end
    if fontString.SetMaxLines then fontString:SetMaxLines(1) end
    fontString:SetWidth(availableWidth)
    fontString:SetText(fullText)
    if (fontString:GetStringWidth() or 0) <= availableWidth then return end

    local suffix = "..."
    local lo, hi, best = 0, #fullText, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local candidate = fullText:sub(1, mid):gsub("%s+$", "") .. suffix
        fontString:SetText(candidate)
        if (fontString:GetStringWidth() or 0) <= availableWidth then
            best = candidate
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    fontString:SetText(best ~= "" and best or suffix)
end

local CONTENT_TEXT_FONT_SIZE = 12

local function ApplyContentText(fontString)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    fontString._tbuSettingsLevel = "CONTENT_TEXT"
    local path, _, flags = fontString:GetFont()
    if path then fontString:SetFont(path, CONTENT_TEXT_FONT_SIZE, flags or "") end
    if TBU.WindowStyles then
        local function repaint(target)
            target:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("primary", target)))
        end
        TBU.WindowStyles:RegisterVisual(fontString, repaint)
        repaint(fontString)
    end
end

-- The role argument is retained for existing call sites, but all text uses
-- currently resolve to the shared allTextTestVariable style field.
local function ApplyRoleColor(target, role, focusAware, hoverFrame)
    if not target or not TBU.WindowStyles then return end
    local function repaint(obj)
        local focused = focusAware and TBU.InputFocus:IsFocused(obj)
        local hovered = hoverFrame and hoverFrame.IsMouseOver and hoverFrame:IsMouseOver()
        local resolved = focused and "primary" or (hovered and "primary" or role)
        obj:SetTextColor(unpack(TBU.WindowStyles:GetTextColor(resolved, obj)))
    end
    TBU.WindowStyles:RegisterVisual(target, repaint)
    if focusAware then TBU.InputFocus:Attach(target, function() repaint(target) end) end
    if hoverFrame and hoverFrame.HookScript then
        local repaintTarget = function() repaint(target) end
        hoverFrame:HookScript("OnEnter", repaintTarget)
        hoverFrame:HookScript("OnLeave", repaintTarget)
    end
    repaint(target)
    return repaint
end

local function ApplyButtonContentText(button)
    if not button or not button.GetFontString then return end
    ApplyContentText(button:GetFontString())
end

local function GetDropdownOptionHighlightWidth(row, fontString, indicator)
    local leftInset = DropdownMetrics.OPTION_INDICATOR_LEFT_INSET
    if indicator then
        leftInset = leftInset + ControlMetrics.DROPDOWN_OPTION_INDICATOR_SIZE + DropdownMetrics.OPTION_TEXT_GAP
    end
    local labelWidth = math.ceil(fontString and fontString.GetStringWidth and fontString:GetStringWidth() or 0)
    local availableWidth = math.max(1, math.ceil(row:GetWidth() or 1))
    return math.min(availableWidth, leftInset + labelWidth + DropdownMetrics.OPTION_TEXT_RIGHT_INSET)
end

local function AddDropdownOptionHighlight(row, onEnter, widthProvider, widthScale, horizontalOffset)
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetTexture(TBU:GetAssetPath("text_highlight_full.png"))
    widthScale = tonumber(widthScale) or 1
    horizontalOffset = tonumber(horizontalOffset) or 0

    local function RefreshHighlightWidth()
        -- Preserve the established bounds: top-left anchored, full row height,
        -- and sized from the same optional content-width provider.
        highlight:ClearAllPoints()
        highlight:SetPoint("TOPLEFT", row, "TOPLEFT", horizontalOffset, 0)
        if widthProvider then
            local width = math.max(1, math.ceil(tonumber(widthProvider()) or 1))
            width = math.min(math.max(1, math.ceil(row:GetWidth() or 1)), math.ceil(width * widthScale))
            highlight:SetWidth(width)
            highlight:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", horizontalOffset, 0)
        else
            highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        end

        local color = TBU.WindowStyles:GetControlOptionHighlightColor(row)
        highlight:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    highlight.RefreshWidth = RefreshHighlightWidth
    TBU.WindowStyles:RegisterVisual(row, function() RefreshHighlightWidth() end)
    RefreshHighlightWidth()
    highlight:Hide()
    row:HookScript("OnEnter", function()
        RefreshHighlightWidth()
        highlight:Show()
        if onEnter then onEnter() end
    end)
    row:HookScript("OnLeave", function() highlight:Hide() end)
    return highlight
end

-- Choice indicators have a container (the square/circle image) and a separate
-- selected-state mark (the check/dot). The container follows the ordinary
-- black control color; it is not part of the all-borders test category.
local function CreateChoiceIndicator(parent, radio, size)
    local control = CreateFrame("CheckButton", nil, parent)
    control:SetSize(size, size)
    local containerTexture = control:CreateTexture(nil, "ARTWORK")
    containerTexture:SetAllPoints(control)
    containerTexture:SetTexture(TBU:GetAssetPath(radio and "radio_outline.png" or "checkbox_outline.png"))
    local selected = control:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints(control)
    selected:SetTexture(TBU:GetAssetPath(radio and "radio_checked.png" or "checkbox_checked.png"))
    control:SetCheckedTexture(selected)
    control:SetNormalTexture(containerTexture)
    local function repaint()
        containerTexture:SetVertexColor(unpack(TBU.WindowStyles:GetControlContainerColor(control)))
        selected:SetVertexColor(unpack(TBU.WindowStyles:GetControlIndicatorColor(control)))
    end
    TBU.WindowStyles:RegisterVisual(control, repaint)
    repaint()
    return control
end
local function CreateLargeCheckbox(parent)
    return CreateChoiceIndicator(parent, false, ControlMetrics.STANDALONE_OPTION_INDICATOR_SIZE)
end
local function CreateSmallCheckbox(parent)
    return CreateChoiceIndicator(parent, false, ControlMetrics.DROPDOWN_OPTION_INDICATOR_SIZE)
end
local function CreateSingleSelectIndicator(parent)
    return CreateChoiceIndicator(parent, true, ControlMetrics.DROPDOWN_OPTION_INDICATOR_SIZE)
end

local dropdownMenuTicker = CreateFrame("Frame")
dropdownMenuTicker:Hide() -- No per-frame work unless a menu is awaiting delayed closure.

local DropdownMenuManager = {
    activeButton = nil,
    pendingCloseButton = nil,
    pendingCloseAt = nil,
    delay = TBU.Constants.Layout.DROPDOWN_CLOSE_DELAY,
}

local function UpdateDropdownMenuManager()
    local manager = DropdownMenuManager
    if manager.pendingCloseButton and manager.pendingCloseAt and GetTime() >= manager.pendingCloseAt then
        local closingButton = manager.pendingCloseButton
        manager.pendingCloseButton = nil
        manager.pendingCloseAt = nil
        local overTrigger = closingButton.IsMouseOver and closingButton:IsMouseOver()
        local menu = closingButton.TBUPopupMenu
        local overMenu = menu and menu:IsShown() and menu:IsMouseOver()
        if not overTrigger and not overMenu and closingButton == manager.activeButton
            and closingButton.CloseMenu then
            closingButton:CloseMenu()
        end
        if not manager.pendingCloseButton then dropdownMenuTicker:Hide() end
    end
end

-- This driver is shown only while a delayed close is pending.
dropdownMenuTicker:SetScript("OnUpdate", function()
    if DropdownMenuManager.pendingCloseButton then
        UpdateDropdownMenuManager()
    end
end)

local function RegisterDropdownOpened(button)
    local manager = DropdownMenuManager
    local previous = manager.activeButton
    if previous and previous ~= button and previous.CloseMenu then
        previous:CloseMenu()
    end
    if manager.pendingCloseButton and manager.pendingCloseButton ~= button
        and manager.pendingCloseButton ~= previous
        and manager.pendingCloseButton.CloseMenu then
        manager.pendingCloseButton:CloseMenu()
    end
    manager.pendingCloseButton = nil
    manager.pendingCloseAt = nil
    dropdownMenuTicker:Hide()

    -- Single and multi dropdowns share one popup, so no stacking is needed.
    local menu = button.TBUPopupMenu
    if menu then
        menu:SetFrameLevel(button:GetFrameLevel() + 20)
    end
    manager.activeButton = button
end

local function RegisterDropdownClosed(button)
    -- Reset popup priority once closed, avoiding ever-increasing frame levels
    -- across repeated menu interactions.
    if button.TBUPopupMenu then
        button.TBUPopupMenu:SetFrameLevel(button:GetFrameLevel() + 20)
    end
    local manager = DropdownMenuManager
    if manager.activeButton == button then
        manager.activeButton = nil
    end
    if manager.pendingCloseButton == button then
        manager.pendingCloseButton = nil
        manager.pendingCloseAt = nil
        dropdownMenuTicker:Hide()
    end
end

local function ExtendDropdownLifetime(button)
    local manager = DropdownMenuManager
    if manager.pendingCloseButton == button then
        manager.pendingCloseButton = nil
        manager.pendingCloseAt = nil
        dropdownMenuTicker:Hide()
    end
end

local function ScheduleDropdownClose(button)
    local manager = DropdownMenuManager
    if manager.activeButton ~= button then return end
    manager.pendingCloseButton = button
    manager.pendingCloseAt = GetTime() + manager.delay
    dropdownMenuTicker:Show()
end

local function AttachDropdownCloseOnLeave(button, menu)
    button:HookScript("OnEnter", function() ExtendDropdownLifetime(button) end)
    button:HookScript("OnLeave", function() ScheduleDropdownClose(button) end)
    menu:HookScript("OnEnter", function() ExtendDropdownLifetime(button) end)
    menu:HookScript("OnLeave", function() ScheduleDropdownClose(button) end)
end

-- Called by page/group navigation when existing content remains shown but
-- represents a different selection. Do not rely on a parent OnHide event:
-- dropdown popup frames may stay visible while a page refreshes in place.
function SC:DismissOpenMenus()
    local manager = DropdownMenuManager
    local pending, active = manager.pendingCloseButton, manager.activeButton
    if pending and pending.CloseMenu then pending:CloseMenu() end
    if active and active ~= pending and active.CloseMenu then active:CloseMenu() end
    manager.pendingCloseButton = nil
    manager.activeButton = nil
    manager.pendingCloseAt = nil
    dropdownMenuTicker:Hide()
end

-- Experimental v1.0: skin the closed dropdown ourselves. Native Button
-- interaction and existing option-menu logic stay intact; no Blizzard
-- WowStyle1DropdownTemplate visual dependency remains.
local function CreateDropdownButton(parent)
    local button = TBU:CreateBackdropFrame("Button", parent)
    button:SetSize(206, 26)
    -- The closed dropdown trigger and expanded option pane both use the
    -- shared control-border color, while keeping their own separate canvases.
    button:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        edgeSize=1,
        insets={left=0,right=0,top=0,bottom=0},
    })
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(14, 14)
    arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    arrow:SetTexture(TBU:GetAssetPath("scroll_arrow.png"))
    button.Arrow = arrow -- required by shared popup-scrollbar alignment
    button.RepaintDropdown = nil
    local hovering = false
    local function Paint()
        local style = TBU.WindowStyles:GetForFrame(button)
        button:SetBackdropColor(unpack(TBU.WindowStyles:GetControlInputCanvasColor(style)))
        button:SetBackdropBorderColor(unpack(TBU.WindowStyles:GetControlBorderColor(style)))
        arrow:SetVertexColor(unpack(TBU.WindowStyles:GetControlIndicatorColor(button)))
    end
    button.RepaintDropdown = Paint
    TBU.WindowStyles:RegisterVisual(button, Paint)
    button:HookScript("OnEnter", function() hovering=true; Paint() end)
    button:HookScript("OnLeave", function() hovering=false; Paint() end)
    Paint()
    return button
end

local function PrepareDropdownOptionText(fontString, row, indicator, text)
    if not fontString or not row then return DropdownMetrics.OPTION_MIN_HEIGHT end
    fontString:ClearAllPoints()

    -- Center the measured label vertically within the option row, matching the
    -- centered selection indicator. Wrapped text still determines row height.
    local leftInset = DropdownMetrics.OPTION_INDICATOR_LEFT_INSET
    if indicator then
        leftInset = leftInset + ControlMetrics.DROPDOWN_OPTION_INDICATOR_SIZE + DropdownMetrics.OPTION_TEXT_GAP
    end
    fontString:SetPoint("LEFT", row, "LEFT", leftInset, 0)

    -- Give the FontString an explicit derived width before asking WoW to measure
    -- its wrapped height. Anchoring only its right edge can leave wrapping
    -- unresolved until a later layout pass, which lets the following option
    -- overlap it. The width is still entirely derived from the option row and
    -- shared control metrics; no per-option geometry is introduced here.
    local rowWidth = row:GetWidth() or 0
    local textWidth = math.max(1, rowWidth - leftInset - DropdownMetrics.OPTION_TEXT_RIGHT_INSET)
    fontString:SetWidth(textWidth)
    fontString:SetJustifyH("LEFT")
    fontString:SetJustifyV("MIDDLE")
    fontString:SetWordWrap(true)
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(false) end
    if fontString.SetMaxLines then fontString:SetMaxLines(0) end
    fontString:SetText(text or "")

    local textHeight = math.ceil(fontString:GetStringHeight() or 0)
    return math.max(
        DropdownMetrics.OPTION_MIN_HEIGHT,
        textHeight + (DropdownMetrics.OPTION_TEXT_VERTICAL_PADDING * 2)
    )
end

-- Determine a closed single-select menu's eventual visible height without
-- opening it or building option buttons. This uses the same shared width,
-- wrapping/font and five-visible-option rules as the popup renderer.
-- Cache by menu width and displayed options to keep resize reflow lightweight.
local function CreateSinglePopupHeightGetter(parent, optionProvider, widthProvider)
    local probeRow = CreateFrame("Frame", nil, parent)
    probeRow:SetSize(1, 1)
    probeRow:Hide() -- Measurement only: these are never visible option rows.
    local probeOption = probeRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ApplyContentText(probeOption)
    local probeHeader = probeRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ApplyContentText(probeHeader)
    local cachedWidth, cachedOptions, cachedHeight

    return function()
        local options = optionProvider() or {}
        local width = math.max(1, tonumber(widthProvider()) or 1)
        local visibleCount = math.min(#options, DropdownMetrics.MAX_VISIBLE_OPTIONS)
        local parts = {tostring(#options)}
        for i = 1, visibleCount do
            local option = options[i]
            parts[#parts + 1] = option.header and ("H" .. tostring(option.header))
                or ("O" .. tostring(option.name))
        end
        local signature = table.concat(parts, "\001")
        if cachedWidth == width and cachedOptions == signature then
            return cachedHeight
        end

        local useScroll = #options > DropdownMetrics.MAX_VISIBLE_OPTIONS
        local contentWidth = math.max(1, width - (useScroll and DropdownMetrics.SCROLLBAR_WIDTH or 0))
        probeRow:SetWidth(math.max(1, contentWidth - DropdownMetrics.MENU_HORIZONTAL_INSET * 2))
        local height = DropdownMetrics.MENU_TOP_PADDING + DropdownMetrics.MENU_BOTTOM_PADDING
        for i = 1, visibleCount do
            local option = options[i]
            if option.header then
                probeHeader:SetWidth(math.max(1, probeRow:GetWidth() - DropdownMetrics.HEADER_HORIZONTAL_INSET * 2))
                probeHeader:SetWordWrap(true)
                probeHeader:SetJustifyH("LEFT")
                probeHeader:SetJustifyV("TOP")
                probeHeader:SetText(option.header)
                local textHeight = math.max(1, math.ceil(probeHeader:GetStringHeight() or 1))
                height = height + DropdownMetrics.HEADER_TOP_PADDING + textHeight
                    + DropdownMetrics.HEADER_TEXT_TO_DIVIDER_GAP + 1
                    + DropdownMetrics.HEADER_BOTTOM_PADDING
            else
                height = height + PrepareDropdownOptionText(probeOption, probeRow, true, option.name)
            end
        end
        cachedWidth, cachedOptions, cachedHeight = width, signature, height
        return height
    end
end

-- Small internal-flow helper for controls that own a variable number of
-- vertically stacked children. This deliberately mirrors the Settings layout
-- contract (child measures itself; parent places the next child after it)
-- without turning popup/control internals into structural Settings Sections.
local function CreateVerticalControlFlow(container, metrics)
    metrics = metrics or {}
    local flow = {
        container = container,
        leftInset = metrics.leftInset or 0,
        rightInset = metrics.rightInset or 0,
        topPadding = metrics.topPadding or 0,
        gap = metrics.gap or 0,
        bottomPadding = metrics.bottomPadding or 0,
        cursor = metrics.topPadding or 0,
        count = 0,
    }

    function flow:Add(child, measuredHeight)
        if not child then return end
        local height = math.max(1, math.ceil(measuredHeight or child:GetHeight() or 1))
        if self.count > 0 then self.cursor = self.cursor + self.gap end
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", self.container, "TOPLEFT", self.leftInset, -self.cursor)
        child:SetPoint("RIGHT", self.container, "RIGHT", -self.rightInset, 0)
        child:SetHeight(height)
        self.cursor = self.cursor + height
        self.count = self.count + 1
    end

    function flow:GetHeight()
        return self.cursor + self.bottomPadding
    end

    return flow
end

local function CreateDropdownOptionFlow(menu)
    return CreateVerticalControlFlow(menu, {
        leftInset = DropdownMetrics.MENU_HORIZONTAL_INSET,
        rightInset = DropdownMetrics.MENU_HORIZONTAL_INSET,
        topPadding = DropdownMetrics.MENU_TOP_PADDING,
        gap = DropdownMetrics.OPTION_GAP,
        bottomPadding = DropdownMetrics.MENU_BOTTOM_PADDING,
    })
end

-- Align popup scrollbars to the native dropdown arrow, rather than assuming
-- every Blizzard dropdown skin and width has identical right-edge insets.
-- Geometry is measured when the popup is visible and positions are resolved.
local function AlignDropdownScrollbar(menu, button, scrollbar)
    local arrow = button and button.Arrow
    if not arrow or not arrow.GetCenter then return end
    local arrowX = arrow:GetCenter()
    local menuRight = menu:GetRight()
    if not arrowX or not menuRight then return end
    local offset = arrowX - menuRight + scrollbar:GetWidth() / 2
    scrollbar:ClearAllPoints()
    scrollbar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", offset, -2)
    scrollbar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", offset, 2)
end

local CreateSettingsScrollbar -- shared by SingleDropdown and MultiDropdown

local function AddMultiDropdown(parent, label, x, y, options, width, emptyText)
    local controlWidth = width

    local hasLabel = label and label ~= ""
    -- Labels and controls are siblings owned by the Settings layout. The label
    -- gets its own fixed region; the dropdown never becomes part of the label's
    -- anchor chain. This prevents circular dependencies when label alignment is
    -- changed and makes column alignment a layout concern rather than a control concern.
    local labelRegion
    local labelText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    if hasLabel then
        labelRegion = CreateFrame("Frame", nil, parent)
        labelRegion:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        -- Width may be supplied later by the owning Column. Use the button's
        -- intrinsic width until structural layout provides the final width.
        labelRegion:SetSize(controlWidth or 1, DropdownMetrics.LABEL_HEIGHT)
        labelText:SetPoint("LEFT", labelRegion, "LEFT", 0, 0)
        labelText:SetPoint("RIGHT", labelRegion, "RIGHT", 0, 0)
        labelText:SetJustifyH("LEFT")
    else
        labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    labelText:SetText(label or "")
    labelText:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("primary", labelText)))
    TBU.WindowStyles:RegisterVisual(labelText, function(text)
        text:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("primary", text)))
    end)
    -- Blizzard skin only. hudcraft owns all text/state/menu behavior.
    local button = CreateDropdownButton(parent)
    if hasLabel then
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - DropdownMetrics.LABEL_HEIGHT - DropdownMetrics.LABEL_TO_CONTROL_GAP)
    else
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if controlWidth then button:SetWidth(controlWidth) end
    controlWidth = math.max(1, math.ceil(button:GetWidth() or 1))

    local displayText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    displayText:SetPoint("LEFT", button, "LEFT", DropdownMetrics.DISPLAY_LEFT_INSET, 0)
    displayText:SetPoint("RIGHT", button, "RIGHT", -DropdownMetrics.DISPLAY_RIGHT_INSET, 0)
    displayText:SetJustifyH("LEFT")
    displayText:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("value", displayText)))
    ApplyContentText(displayText)
    TBU.WindowStyles:RegisterVisual(displayText, function(text)
        text:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("value", text)))
    end)

    local function refreshDisplay()
        local selected = {}
        for _, opt in ipairs(options) do
            if opt.getter() then
                selected[#selected + 1] = opt.shortLabel or opt.name
            end
        end
        SetDropdownDisplayText(displayText, #selected > 0 and table.concat(selected, " + ") or (emptyText or "None"), controlWidth - DropdownMetrics.DISPLAY_LEFT_INSET - DropdownMetrics.DISPLAY_RIGHT_INSET)
    end

    -- Popup belongs to this control. Match the visible dropdown field width exactly.
    local menu = TBU:CreateBackdropFrame("Frame", parent)
    menu:SetFrameLevel(button:GetFrameLevel() + 20)
    menu:SetWidth(controlWidth)
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, DropdownMetrics.MENU_OFFSET_Y)
    -- Test the same native one-pixel border as the stable Section border.
    -- Field and popup now share the same renderer, avoiding mixed-edge offsets.
    menu:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        edgeSize=1,
        insets={left=0,right=0,top=0,bottom=0},
    })
    local function RepaintPopup(target)
        local color = TBU.WindowStyles:GetForFrame(target)
        target:SetBackdropColor(unpack(TBU.WindowStyles:GetControlInputCanvasColor(color)))
        target:SetBackdropBorderColor(unpack(TBU.WindowStyles:GetControlBorderColor(color)))
    end
    TBU.WindowStyles:RegisterVisual(menu, RepaintPopup)
    RepaintPopup(menu)
    menu:Hide()
    button.TBUPopupMenu = menu
    AttachDropdownCloseOnLeave(button, menu)
    menu:HookScript("OnShow", function() if button.RepaintDropdown then button.RepaintDropdown() end end)
    menu:HookScript("OnHide", function() if button.RepaintDropdown then button.RepaintDropdown() end end)

    -- MultiDropdown uses the exact same native scroll viewport and shared
    -- custom scrollbar as SingleDropdown; short lists remain unscrollable.
    local viewport = CreateFrame("ScrollFrame", nil, menu)
    viewport:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
    viewport:EnableMouseWheel(true)
    local scrollContent = CreateFrame("Frame", nil, viewport)
    scrollContent:SetSize(1, 1)
    viewport:SetScrollChild(scrollContent)
    local scrollbar = CreateSettingsScrollbar(menu, viewport, button, "gold")
    scrollbar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -2)
    scrollbar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -4, 2)
    menu:HookScript("OnShow", function()
        AlignDropdownScrollbar(menu, button, scrollbar)
    end)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        scrollbar:ScrollBy(-delta * DropdownMetrics.OPTION_MIN_HEIGHT)
    end)

    local optionEntries = {}
    local function LayoutOptions()
        local useScroll = #optionEntries > DropdownMetrics.MAX_VISIBLE_OPTIONS
        local availableWidth = math.max(1, controlWidth - (useScroll and DropdownMetrics.SCROLLBAR_WIDTH or 0))
        scrollContent:SetWidth(availableWidth)
        local optionFlow = CreateDropdownOptionFlow(scrollContent)
        for _, entry in ipairs(optionEntries) do
            local row = entry.row
            row:SetWidth(math.max(1, availableWidth - (DropdownMetrics.MENU_HORIZONTAL_INSET * 2)))
            local rowHeight = PrepareDropdownOptionText(entry.text, row, entry.indicator, entry.name)
            if row.highlight then row.highlight:RefreshWidth() end
            optionFlow:Add(row, rowHeight)
        end
        local fullHeight = optionFlow:GetHeight()
        local visibleHeight = fullHeight
        if useScroll then
            local height = DropdownMetrics.MENU_TOP_PADDING + DropdownMetrics.MENU_BOTTOM_PADDING
            for i = 1, math.min(#optionEntries, DropdownMetrics.MAX_VISIBLE_OPTIONS) do
                height = height + optionEntries[i].row:GetHeight()
            end
            visibleHeight = math.min(fullHeight, height)
        end
        scrollContent:SetHeight(math.max(1, fullHeight))
        menu:SetHeight(visibleHeight)
        viewport:SetSize(availableWidth, visibleHeight)
        viewport:SetVerticalScroll(0)
        if fullHeight > visibleHeight then
            scrollbar:Show()
            scrollbar:Update()
        else
            scrollbar:Hide()
        end
    end

    for _, opt in ipairs(options) do
        local row = CreateFrame("Frame", nil, scrollContent)
        row:SetWidth(math.max(1, controlWidth - (#options > DropdownMetrics.MAX_VISIBLE_OPTIONS and DropdownMetrics.SCROLLBAR_WIDTH or 0) - DropdownMetrics.MENU_HORIZONTAL_INSET * 2)) -- establish available wrapping width
        row:EnableMouse(true)

        local cb = CreateSmallCheckbox(row)
        cb:SetPoint("LEFT", row, "LEFT", DropdownMetrics.OPTION_INDICATOR_LEFT_INSET, 0)

        local optionText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        optionText:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("value", optionText)))
        ApplyContentText(optionText)
        ApplyRoleColor(optionText, "value", false, row)
        row.highlight = AddDropdownOptionHighlight(row, function() ExtendDropdownLifetime(button) end, function()
            return GetDropdownOptionHighlightWidth(row, optionText, cb)
        end, 2)
        row.highlight:RefreshWidth()
        optionEntries[#optionEntries + 1] = { row=row, indicator=cb, text=optionText, name=opt.name, getter=opt.getter }

        local function toggleOption(explicitValue)
            local newValue = explicitValue
            if newValue == nil then newValue = not opt.getter() end
            opt.setter(newValue and true or false)
            cb:SetChecked(newValue and true or false)
            refreshDisplay()
            TBU:RefreshAll()
        end
        cb:SetScript("OnShow", function(self) self:SetChecked(opt.getter()) end)
        cb:SetScript("OnClick", function(self) toggleOption(self:GetChecked()) end)
        row:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "LeftButton" then toggleOption() end
        end)
    end
    LayoutOptions()

    local function closeMenu()
        menu:Hide()
        RegisterDropdownClosed(button)
    end
    button:SetScript("OnClick", function()
        if menu:IsShown() then
            closeMenu()
        else
            refreshDisplay()
            for _, entry in ipairs(optionEntries) do
                entry.indicator:SetChecked(entry.getter() == true)
            end
            LayoutOptions() -- recalculate widths, content wrapping, and overflow on open
            RegisterDropdownOpened(button)
            menu:Show()
        end
    end)
    button:SetScript("OnHide", closeMenu)
    parent:HookScript("OnHide", closeMenu)

    button.SetControlWidth = function(_, newWidth)
        newWidth = math.max(1, math.floor((tonumber(newWidth) or controlWidth) + 0.5))
        if newWidth == controlWidth then return end
        controlWidth = newWidth
        button:SetWidth(controlWidth)
        if labelRegion then labelRegion:SetWidth(controlWidth) end
        menu:SetWidth(controlWidth)
        LayoutOptions()
        refreshDisplay()
    end
    button.RefreshDisplay = refreshDisplay
    RegisterStatefulControl(button, function() refreshDisplay() end)
    button.DisplayText = displayText
    button.CloseMenu = closeMenu
    button.OptionMenu = menu
    button.GetPopupDownwardOffset = function() return -DropdownMetrics.MENU_OFFSET_Y end
    button.OptionLabel = labelText
    button.OptionLabelRegion = labelRegion
    button.GetExpandedMenuHeight = function() return menu:GetHeight() or 0 end
    refreshDisplay()
    return button
end

-- Reusable scrollbar: native ScrollFrame mechanics, framework-owned visuals.
-- themeMode is a developer-facing choice: "gold" for Settings, "inherit"
-- for future HUD surfaces that should follow the secondary theme color.
CreateSettingsScrollbar = function(parent, scrollFrame, button, themeMode, variant)
    local isSlim = variant == "slim"
    local barWidth = isSlim and DropdownMetrics.SLIM_SCROLLBAR_WIDTH or DropdownMetrics.SCROLLBAR_WIDTH
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(barWidth)
    -- Scroll children contain Sections, Rows, controls and text at nested frame
    -- levels. A +3 offset can leave the scrollbar UNDER the section backdrop.
    -- Keep the scrollbar in the same window strata, above ordinary content.
    bar:SetFrameLevel(scrollFrame:GetFrameLevel() + 12)
    local up = CreateFrame("Button", nil, bar)
    local down = CreateFrame("Button", nil, bar)
    up:SetPoint("TOP", bar, "TOP", 0, 0)
    down:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    up:SetSize(16, DropdownMetrics.SCROLL_ARROW_HEIGHT)
    down:SetSize(16, DropdownMetrics.SCROLL_ARROW_HEIGHT)

    -- Texture-backed chevrons render consistently at small UI scales.
    -- White source artwork permits runtime tinting by the shared theme mode.
    local upTexture = up:CreateTexture(nil, "ARTWORK")
    upTexture:SetPoint("CENTER")
    upTexture:SetSize(16, 16)
    upTexture:SetTexture(TBU:GetAssetPath("scroll_arrow.png"))
    upTexture:SetRotation(math.pi)
    local downTexture = down:CreateTexture(nil, "ARTWORK")
    downTexture:SetPoint("CENTER")
    downTexture:SetSize(16, 16)
    downTexture:SetTexture(TBU:GetAssetPath("scroll_arrow.png"))
    downTexture:SetRotation(0)
    local track = CreateFrame("Button", nil, bar)
    track:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 0, -1)
    track:SetPoint("BOTTOMRIGHT", down, "TOPRIGHT", 0, 1)
    if isSlim then
        up:Hide()
        down:Hide()
        track:ClearAllPoints()
        track:SetPoint("TOPLEFT", bar, "TOPLEFT")
        track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    end
    local trackTexture = track:CreateTexture(nil, "BACKGROUND")
    trackTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    local function repaintTrack(target)
        target:SetVertexColor(unpack(TBU.WindowStyles:GetScrollbarTrackColor(target)))
    end
    TBU.WindowStyles:RegisterVisual(trackTexture, repaintTrack)
    repaintTrack(trackTexture)
    trackTexture:SetPoint("CENTER")
    trackTexture:SetWidth(isSlim and DropdownMetrics.SLIM_SCROLLBAR_TRACK_WIDTH or 3)
    trackTexture:SetPoint("TOP", 0, -9)
    trackTexture:SetPoint("BOTTOM", 0, 9)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(isSlim and DropdownMetrics.SLIM_SCROLLBAR_THUMB_WIDTH or DropdownMetrics.SCROLL_THUMB_WIDTH)
    thumb:SetHeight(isSlim and DropdownMetrics.SLIM_SCROLLBAR_THUMB_HEIGHT or DropdownMetrics.SCROLL_THUMB_MIN_HEIGHT)
    -- Extend the interactive target by 2 UI units on every side.
    thumb:SetHitRectInsets(-2, -2, -2, -2)
    -- Slim uses the library's rounded-rectangle thumb artwork at half the
    -- standard scrollbar lane/minimum thumb dimensions. The regular scrollbar
    -- keeps its existing three-slice rendering. Hit expansion is independent
    -- of the visible thumb dimensions.
    local thumbParts = {}
    local thumbTop, thumbMiddle, thumbBottom
    if isSlim then
        local thumbImage = thumb:CreateTexture(nil, "ARTWORK")
        thumbImage:SetTexture(TBU:GetAssetPath("scroll_thumb.png"))
        thumbImage:SetAllPoints(thumb)
        thumbParts[1] = thumbImage
    else
        local function makeRoundCap(parent, topCap)
            local cap = parent:CreateTexture(nil, "ARTWORK")
            cap:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            cap:SetTexCoord(0, 1, topCap and 0 or 0.5, topCap and 0.5 or 1)
            return cap
        end
        thumbTop = makeRoundCap(thumb, true)
        thumbMiddle = thumb:CreateTexture(nil, "ARTWORK")
        thumbMiddle:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumbBottom = makeRoundCap(thumb, false)
        thumbParts = {thumbTop, thumbMiddle, thumbBottom}
    end
    local function positionThumbParts()
        if isSlim then return end
        local width = math.max(1, thumb:GetWidth())
        local capHeight = math.min(width / 2, thumb:GetHeight() / 2)
        thumbTop:ClearAllPoints()
        thumbTop:SetPoint("TOPLEFT", thumb, "TOPLEFT")
        thumbTop:SetPoint("TOPRIGHT", thumb, "TOPRIGHT")
        thumbTop:SetHeight(capHeight)
        thumbBottom:ClearAllPoints()
        thumbBottom:SetPoint("BOTTOMLEFT", thumb, "BOTTOMLEFT")
        thumbBottom:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT")
        thumbBottom:SetHeight(capHeight)
        thumbMiddle:ClearAllPoints()
        thumbMiddle:SetPoint("TOPLEFT", thumbTop, "BOTTOMLEFT")
        thumbMiddle:SetPoint("BOTTOMRIGHT", thumbBottom, "TOPRIGHT")
    end

    local function indicatorColor()
        return TBU.WindowStyles:GetControlIndicatorColor(bar)
    end
    local trackHovered, thumbHovered, thumbDragging = false, false, false
    local function thumbColor()
        local styles = TBU.WindowStyles
        if thumbDragging then
            return styles:GetMainNavigationButtonSelectedBorderColor(thumb)
        elseif trackHovered or thumbHovered then
            return styles:GetControlIndicatorColor(thumb)
        end
        return styles:GetScrollbarThumbIdleColor(thumb)
    end
    local function maxScroll()
        if scrollFrame.GetVerticalScrollRange then
            return math.max(0, scrollFrame:GetVerticalScrollRange() or 0)
        end
        return math.max(0, (scrollFrame:GetScrollChild() and scrollFrame:GetScrollChild():GetHeight() or 0) - scrollFrame:GetHeight())
    end
    local function update()
        local indicator = indicatorColor()
        local r, g, b = indicator[1] or 1, indicator[2] or 1, indicator[3] or 1
        local alpha = indicator[4] or 1
        local thumbR, thumbG, thumbB, thumbA = unpack(thumbColor())
        for _, part in ipairs(thumbParts) do part:SetVertexColor(thumbR, thumbG, thumbB, thumbA or 1) end
        local maximum = maxScroll()
        local value = math.max(0, math.min(maximum, scrollFrame:GetVerticalScroll() or 0))
        local trackHeight = math.max(1, track:GetHeight())
        -- Fixed rendered pill width, independent of source-image whitespace.
        -- Stay inside narrow scrollbars while remaining wider than the track.
        if isSlim then
            thumb:SetWidth(DropdownMetrics.SLIM_SCROLLBAR_THUMB_WIDTH)
        else
            thumb:SetWidth(math.max(5, math.min(DropdownMetrics.SCROLL_THUMB_WIDTH,
                (bar:GetWidth() or DropdownMetrics.SCROLLBAR_WIDTH) - 2)))
        end
        local visible = math.max(1, scrollFrame:GetHeight())
        -- Each scrollbar scales to its own viewport, with a compact thumb
        -- rather than filling most of short dropdown tracks.
        local thumbHeight = isSlim and DropdownMetrics.SLIM_SCROLLBAR_THUMB_HEIGHT
            or math.max(DropdownMetrics.SCROLL_THUMB_MIN_HEIGHT,
                math.min(DropdownMetrics.SCROLL_THUMB_MAX_HEIGHT,
                    math.floor(trackHeight * visible / (visible + maximum) * DropdownMetrics.SCROLL_THUMB_SCALE + 0.5)))
        thumbHeight = math.min(trackHeight, thumbHeight)
        thumb:SetHeight(thumbHeight)
        positionThumbParts()
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0,
            -((maximum > 0) and (value / maximum * (trackHeight - thumbHeight)) or 0))
        -- Fractional frame scaling can leave the last pixel short of the
        -- nominal scroll range; disabled states use a 1px tolerance.
        upTexture:SetVertexColor(r, g, b, alpha * (value <= 1 and 0.35 or 1))
        downTexture:SetVertexColor(r, g, b, alpha * (value >= maximum - 1 and 0.35 or 1))
    end
    local function scrollBy(delta)
        delta = tonumber(delta) or 0
        scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll(), (scrollFrame:GetVerticalScroll() or 0) + delta)))
        update()
        ExtendDropdownLifetime(button)
    end
    up:SetScript("OnClick", function() scrollBy(-DropdownMetrics.OPTION_MIN_HEIGHT) end)
    down:SetScript("OnClick", function() scrollBy(DropdownMetrics.OPTION_MIN_HEIGHT) end)
    -- Treat the entire scrollbar gutter as part of its associated scrollable
    -- region. Forward to the viewport's own wheel handler, which preserves
    -- page versus dropdown wheel speed and any future consumer behavior.
    -- Wheel handling remains local to this scrollbar even at scroll limits.
    local function wheelOverScrollbar(_, delta)
        local handler = scrollFrame:GetScript("OnMouseWheel")
        if handler then
            handler(scrollFrame, delta)
            update()
            ExtendDropdownLifetime(button)
        else
            scrollBy(-delta * DropdownMetrics.OPTION_MIN_HEIGHT)
        end
    end
    for _, region in ipairs({bar, up, down, track, thumb}) do
        region:EnableMouseWheel(true)
        region:SetScript("OnMouseWheel", wheelOverScrollbar)
    end

    local function moveThumb()
        local _, cursorY = GetCursorPosition()
        local scale = track:GetEffectiveScale()
        local top = track:GetTop()
        if not top or not scale or scale == 0 then return end
        local span = math.max(1, track:GetHeight() - thumb:GetHeight())
        local offset = math.max(0, math.min(span, top - cursorY / scale - thumb:GetHeight() / 2))
        scrollFrame:SetVerticalScroll(maxScroll() * offset / span)
        update()
        ExtendDropdownLifetime(button)
    end
    local function endThumbDrag(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        thumbDragging = false
        thumbHovered = self:IsMouseOver() and true or false
        update()
    end
    thumb:SetScript("OnEnter", function() thumbHovered = true; update() end)
    thumb:SetScript("OnLeave", function() thumbHovered = false; update() end)
    -- Match the horizontal slider's hover target: the whole usable track lane
    -- highlights the thumb, not only the small thumb hit rectangle.
    track:SetScript("OnEnter", function() trackHovered = true; update() end)
    track:SetScript("OnLeave", function() trackHovered = false; update() end)
    track:SetScript("OnHide", function() trackHovered = false; update() end)
    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        thumbDragging = true
        thumbHovered = true
        update()
        -- Only run this update while being dragged; a released mouse outside
        -- the thumb must not leave the thumb gold or running OnUpdate forever.
        self:SetScript("OnUpdate", function(active)
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                endThumbDrag(active)
                return
            end
            moveThumb()
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then endThumbDrag(self) end
    end)
    thumb:SetScript("OnHide", function(self)
        thumbDragging = false
        self:SetScript("OnUpdate", nil)
        thumbHovered = false
        update()
    end)
    track:SetScript("OnMouseDown", moveThumb)
    scrollFrame:HookScript("OnVerticalScroll", update)
    -- WindowFrame dynamically reorders entire windows. On the active window,
    -- rebase the scrollbar above its own scroll content each time. Preserve
    -- arrow/track/thumb ordering regardless of the underlying host order.
    function bar:RefreshLayer()
        local level = scrollFrame:GetFrameLevel() + 12
        self:SetFrameLevel(level)
        up:SetFrameLevel(level + 1)
        down:SetFrameLevel(level + 1)
        track:SetFrameLevel(level + 1)
        thumb:SetFrameLevel(level + 2)
    end
    bar:RefreshLayer()
    bar.Update = update
    TBU.WindowStyles:RegisterVisual(bar, update)
    bar.ScrollBy = function(_, delta) scrollBy(delta) end
    bar:Hide()
    return bar
end

-- Scrollbars occupy a right-side layout lane. Keep a small content gap before
-- the bar and a separate inset between its track and the pane's outer edge.
SC.ScrollbarRightInset = 4
SC.ScrollbarContentGap = 6
SC.ScrollbarGutterWidth = SC.ScrollbarRightInset
    + DropdownMetrics.SCROLLBAR_WIDTH + SC.ScrollbarContentGap
SC.SlimScrollbarGutterWidth = DropdownMetrics.SLIM_SCROLLBAR_GUTTER_WIDTH

function SC:GetScrollbarGutterWidth(options)
    local variant = type(options) == "table" and options.variant or options
    if variant == "slim" then return DropdownMetrics.SLIM_SCROLLBAR_GUTTER_WIDTH end
    return SC.ScrollbarGutterWidth
end

-- Public shared scrollbar wrapper for Settings pages and future scrollable content.
-- Scrolling is native; only the arrows/track/thumb belong to framework.
function SC:AttachScrollbar(parent, scrollFrame, themeMode, options)
    options = type(options) == "table" and options or {}
    local variant = options.variant == "slim" and "slim" or "standard"
    local bar = CreateSettingsScrollbar(parent, scrollFrame, nil, themeMode or "gold", variant)
    -- The scroll viewport reserves a right-side lane. Place the bar in that
    -- lane, separated from the viewport by ScrollbarContentGap.
    local gutterWidth = SC:GetScrollbarGutterWidth(variant)
    local barOffset = variant == "slim"
        and DropdownMetrics.SLIM_SCROLLBAR_GAP or SC.ScrollbarContentGap
    local topInset = math.max(0, tonumber(options.topInset)
        or (variant == "slim" and DropdownMetrics.SLIM_SCROLLBAR_TOP_INSET or 0))
    local bottomInset = math.max(0, tonumber(options.bottomInset)
        or (variant == "slim" and DropdownMetrics.SLIM_SCROLLBAR_BOTTOM_INSET or 0))
    local wheelTopInset = math.max(0, tonumber(options.wheelTopInset)
        or (variant == "slim" and DropdownMetrics.SLIM_SCROLLBAR_WHEEL_TOP_INSET or 0))
    local wheelBottomInset = math.max(0, tonumber(options.wheelBottomInset)
        or (variant == "slim" and DropdownMetrics.SLIM_SCROLLBAR_WHEEL_BOTTOM_INSET or 0))
    bar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", barOffset, -topInset)
    bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", barOffset,
        bottomInset)
    local wheelGutter = CreateFrame("Frame", nil, parent)
    wheelGutter:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, -wheelTopInset)
    wheelGutter:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", gutterWidth,
        wheelBottomInset)
    wheelGutter:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    wheelGutter:EnableMouse(true)
    wheelGutter:EnableMouseWheel(true)
    wheelGutter:SetScript("OnMouseWheel", function(_, delta)
        local handler = scrollFrame:GetScript("OnMouseWheel")
        if handler then
            handler(scrollFrame, delta)
        else
            local current = scrollFrame:GetVerticalScroll() or 0
            local range = scrollFrame:GetVerticalScrollRange() or 0
            scrollFrame:SetVerticalScroll(math.max(0, math.min(range, current - delta * 35)))
        end
        if bar:IsShown() then bar:Update() end
    end)
    bar.wheelGutter = wheelGutter
    bar.variant = variant
    bar.gutterWidth = gutterWidth
    local function refreshNow()
        bar:RefreshLayer()
        local scrollable = scrollFrame:GetVerticalScrollRange() or 0
        if scrollable > 1 then
            if not bar:IsShown() then bar:Show() end
            bar:Update()
        else
            if bar:IsShown() then bar:Hide() end
        end
    end

    -- Scroll range can be transient while the root window, viewport, and
    -- scroll child are resolving a resize. Coalesce visibility checks until
    -- the next frame so one intermediate range cannot flash the bar on/off.
    local visibilityUpdate = CreateFrame("Frame", nil, parent)
    visibilityUpdate:Hide()
    local candidateVisibility, stableMeasurements = nil, 0
    visibilityUpdate:SetScript("OnUpdate", function(self)
        self:Hide()
        bar:RefreshLayer()
        local scrollable = (scrollFrame:GetVerticalScrollRange() or 0) > 1
        if scrollable == candidateVisibility then
            stableMeasurements = stableMeasurements + 1
        else
            candidateVisibility = scrollable
            stableMeasurements = 1
        end
        -- Keep the current state through a one-frame intermediate range.
        -- Require two settled measurements before changing visibility.
        if stableMeasurements < 2 then
            if bar:IsShown() then bar:Update() end
            self:Show()
            return
        end
        refreshNow()
    end)
    local function scheduleRefresh()
        if not visibilityUpdate:IsShown() then visibilityUpdate:Show() end
    end
    scrollFrame:HookScript("OnSizeChanged", scheduleRefresh)
    scrollFrame:HookScript("OnShow", scheduleRefresh)
    bar.RefreshVisibility = scheduleRefresh
    scheduleRefresh()
    return bar
end

-- Custom-rendered multiline editor. The EditBox remains responsible for input
-- and selection geometry; TreebeardUI draws the visible text and blinking caret.
function SC:CreateCustomMultilineTextInput(parent, options)
    assert(parent and parent.CreateFontString, "custom multiline editor parent required")
    options = type(options) == "table" and options or {}

    local insets = type(options.insets) == "table" and options.insets or {}
    local leftInset = math.max(0, tonumber(insets.left) or 0)
    local topInset = math.max(0, tonumber(insets.top) or 0)
    local rightInset = math.max(0, tonumber(insets.right) or 0)
    local bottomInset = math.max(0, tonumber(insets.bottom) or 0)
    local textInsets = type(options.textInsets) == "table" and options.textInsets or {}
    local textLeft = math.max(0, tonumber(textInsets.left) or 8)
    local textRight = math.max(0, tonumber(textInsets.right) or 8)
    local textTop = math.max(0, tonumber(textInsets.top) or 8)
    local textBottom = math.max(0, tonumber(textInsets.bottom) or 8)
    local scrollbarOptions = type(options.scrollbar) == "table" and options.scrollbar or nil
    local gutter = scrollbarOptions and self:GetScrollbarGutterWidth(scrollbarOptions) or 0
    local scrollbarGap = scrollbarOptions and math.max(0, tonumber(options.scrollbarGap) or 2) or 0
    local fontObject = options.fontObject or "GameFontHighlight"

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", leftInset, -topInset)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",
        -(rightInset + gutter + scrollbarGap), bottomInset)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local edit = CreateFrame("EditBox", nil, content)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:EnableMouse(true)
    edit:EnableMouseWheel(true)
    edit:EnableKeyboard(true)
    edit:SetFontObject(fontObject)
    edit:SetMaxLetters(tonumber(options.maxLetters) or 20000)
    edit:SetTextInsets(textLeft, textRight, textTop, textBottom)
    edit:SetJustifyH(options.justifyH or "LEFT")
    edit:SetJustifyV(options.justifyV or "TOP")
    edit:SetIndentedWordWrap(false)
    edit:SetText(tostring(options.text or ""))
    edit:SetTextColor(1, 1, 1, 0)

    local visibleText = edit:CreateFontString(nil, "ARTWORK", fontObject)
    visibleText:SetJustifyH(options.justifyH or "LEFT")
    visibleText:SetJustifyV(options.justifyV or "TOP")
    visibleText:SetWordWrap(true)
    if visibleText.SetNonSpaceWrap then visibleText:SetNonSpaceWrap(true) end
    if visibleText.SetMaxLines then visibleText:SetMaxLines(0) end

    local measure = parent:CreateFontString(nil, "ARTWORK", fontObject)
    measure:SetAlpha(0)
    measure:SetJustifyH("LEFT")
    measure:SetJustifyV("TOP")
    measure:SetWordWrap(true)
    if measure.SetNonSpaceWrap then measure:SetNonSpaceWrap(true) end
    if measure.SetMaxLines then measure:SetMaxLines(0) end

    local surface = {
        scrollFrame = scroll,
        editBox = edit,
        visibleText = visibleText,
        measureText = measure,
        content = content,
    }
    local caret = edit:CreateTexture(nil, "OVERLAY")
    local caretWidth = math.max(1, tonumber(options.caretWidth) or 1)
    local caretBlinkRate = math.max(0.1, tonumber(options.caretBlinkRate) or 0.5)
    caret:SetSize(caretWidth, 16)
    caret:Hide()
    surface.caret = caret

    local caretElapsed, caretVisible = 0, false
    local function RepaintInteractionColor()
        if not TBU.WindowStyles then return end
        local color = TBU.WindowStyles:GetWindowInteractionColor(edit)
        if not color then return end
        caret:SetColorTexture(color[1] or 1, color[2] or 0.5,
            color[3] or 0, color[4] or 1)
        edit:SetHighlightColor(color[1] or 1, color[2] or 0.5,
            color[3] or 0, tonumber(options.selectionOpacity) or 0.35)
    end
    if TBU.WindowStyles then
        TBU.WindowStyles:RegisterVisual(caret, RepaintInteractionColor)
    end
    RepaintInteractionColor()

    local function EscapeMarkup(value)
        return (tostring(value or ""):gsub("|", "||"))
    end
    local function RenderText()
        visibleText:SetText(EscapeMarkup(edit:GetText() or ""))
    end
    local function SetCaretVisible(visible)
        caretVisible = visible == true
        if caretVisible and edit:HasFocus() then caret:Show() else caret:Hide() end
    end
    local function UpdateCaret(_, x, y, _cursorWidth, height)
        height = tonumber(height) or 16
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", edit, "TOPLEFT",
            (tonumber(x) or 0) + textLeft,
            (tonumber(y) or 0) - textTop)
        caret:SetSize(caretWidth, math.max(1, height))
        if edit:HasFocus() then SetCaretVisible(true) end
    end

    local function RefreshGeometry()
        local width = math.max(1, scroll:GetWidth() or 1)
        local text = edit:GetText() or ""
        local explicitLines = select(2, text:gsub("\n", "")) + 1
        local _, fontSize = edit:GetFont()
        measure:SetWidth(math.max(1, width - textLeft - textRight))
        measure:SetText(text)
        visibleText:SetWidth(math.max(1, width - textLeft - textRight))
        visibleText:SetText(EscapeMarkup(text))
        local measuredHeight = type(measure.GetStringHeight) == "function"
            and (tonumber(measure:GetStringHeight()) or 0) or 0
        local viewportHeight = math.max(1, scroll:GetHeight() or 1)
        local contentHeight = math.max(viewportHeight,
            measuredHeight + textTop + textBottom,
            explicitLines * (tonumber(fontSize) or 12) + textTop + textBottom)
        content:SetSize(width, contentHeight)

        -- Keep short notes filling the viewport so mouse selection still works;
        -- overflow notes grow the ScrollFrame child from measured wrapped text.
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", content, "TOPLEFT")
        edit:SetWidth(width)
        edit:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
        visibleText:ClearAllPoints()
        visibleText:SetPoint("TOPLEFT", edit, "TOPLEFT", textLeft, -textTop)
        visibleText:SetPoint("RIGHT", edit, "RIGHT", -textRight, 0)
        visibleText:SetHeight(math.max(1, contentHeight - textTop - textBottom))

        scroll:UpdateScrollChildRect()
        local range = math.max(0, scroll:GetVerticalScrollRange() or 0)
        scroll:SetVerticalScroll(math.max(0, math.min(range,
            scroll:GetVerticalScroll() or 0)))
        if surface.scrollbar and surface.scrollbar.RefreshVisibility then
            surface.scrollbar:RefreshVisibility()
        end
    end
    local geometryUpdate = CreateFrame("Frame", nil, parent)
    geometryUpdate:Hide()
    geometryUpdate:SetScript("OnUpdate", function(target)
        target:Hide()
        RefreshGeometry()
    end)
    surface.RefreshGeometry = RefreshGeometry
    surface.QueueGeometry = function()
        if not geometryUpdate:IsShown() then geometryUpdate:Show() end
    end
    surface.GetText = function() return edit:GetText() or "" end
    surface.SetText = function(_, text)
        edit:SetText(tostring(text or ""))
        surface:QueueGeometry()
    end
    surface.SetInputEnabled = function(_, enabled)
        enabled = enabled == true
        if not enabled then edit:ClearFocus() end
        edit:EnableMouse(enabled)
        edit:EnableKeyboard(enabled)
    end

    local function ScrollBy(delta)
        local range = math.max(0, scroll:GetVerticalScrollRange() or 0)
        local current = scroll:GetVerticalScroll() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(range,
            current - delta * (tonumber(options.wheelStep) or 35))))
        if surface.scrollbar and surface.scrollbar:IsShown() then
            surface.scrollbar:Update()
        end
    end
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
    edit:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
    edit:HookScript("OnMouseDown", function(target, button)
        if button == "LeftButton" then target:SetFocus() end
    end)
    edit:HookScript("OnCursorChanged", UpdateCaret)
    edit:HookScript("OnTextChanged", function(target, userInput)
        RenderText()
        surface:QueueGeometry()
        if options.onTextChanged then options.onTextChanged(target, userInput) end
    end)
    edit:HookScript("OnEditFocusGained", function()
        caretElapsed = 0
        SetCaretVisible(true)
    end)
    edit:HookScript("OnEditFocusLost", function()
        SetCaretVisible(false)
    end)
    local caretClock = CreateFrame("Frame", nil, parent)
    caretClock:SetScript("OnUpdate", function(_, elapsed)
        if not edit:HasFocus() then return end
        caretElapsed = caretElapsed + elapsed
        if caretElapsed >= caretBlinkRate then
            caretElapsed = caretElapsed - caretBlinkRate
            SetCaretVisible(not caretVisible)
        end
    end)

    if options.textColorRole ~= false then
        ApplyRoleColor(visibleText, options.textColorRole or "primary", false)
    end
    if options.onEditBoxCreated then options.onEditBoxCreated(edit, surface) end
    if options.onVisibleTextCreated then options.onVisibleTextCreated(visibleText, surface) end
    if scrollbarOptions then
        surface.scrollbar = self:AttachScrollbar(parent, scroll,
            options.themeMode, scrollbarOptions)
    end
    parent:HookScript("OnShow", surface.QueueGeometry)
    surface:QueueGeometry()
    return surface
end

local function AddSingleDropdown(parent, label, x, y, options, getter, setter, width)
    local controlWidth = width
    local hasLabel = label and label ~= ""

    local labelRegion
    local labelText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    if hasLabel then
        labelRegion = CreateFrame("Frame", nil, parent)
        labelRegion:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        -- The structural Column may not have assigned width yet.
        -- Resolve the true width from the created dropdown button below.
        labelRegion:SetSize(controlWidth or 1, DropdownMetrics.LABEL_HEIGHT)
        labelText:SetPoint("LEFT", labelRegion, "LEFT", 0, 0)
        labelText:SetPoint("RIGHT", labelRegion, "RIGHT", 0, 0)
        labelText:SetJustifyH("LEFT")
    else
        labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    labelText:SetText(label or "")
    labelText:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("primary", labelText)))
    TBU.WindowStyles:RegisterVisual(labelText, function(text)
        text:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("primary", text)))
    end)
    local button = CreateDropdownButton(parent)
    button.labelText = labelText
    if hasLabel then
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - DropdownMetrics.LABEL_HEIGHT - DropdownMetrics.LABEL_TO_CONTROL_GAP)
    else
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if controlWidth then button:SetWidth(controlWidth) end
    controlWidth = math.max(1, math.ceil(button:GetWidth() or 1))
    if labelRegion then labelRegion:SetWidth(controlWidth) end

    local displayText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    displayText:SetPoint("LEFT", button, "LEFT", DropdownMetrics.DISPLAY_LEFT_INSET, 0)
    displayText:SetPoint("RIGHT", button, "RIGHT", -DropdownMetrics.DISPLAY_RIGHT_INSET, 0)
    displayText:SetJustifyH("LEFT")
    displayText:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("value", displayText)))
    ApplyContentText(displayText)
    TBU.WindowStyles:RegisterVisual(displayText, function(text)
        text:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("value", text)))
    end)

    local function resolvedOptions()
        return type(options) == "function" and options() or options
    end

    local function optionDisplay(value)
        for _, opt in ipairs(resolvedOptions()) do
            if not opt.header and opt.value == value then
                return opt.name or tostring(opt.value)
            end
        end
        return tostring(value or "None")
    end

    local function refreshDisplay()
        SetDropdownDisplayText(displayText, optionDisplay(getter()), controlWidth - DropdownMetrics.DISPLAY_LEFT_INSET - DropdownMetrics.DISPLAY_RIGHT_INSET)
    end

    local menu = TBU:CreateBackdropFrame("Frame", parent)
    menu:SetFrameLevel(button:GetFrameLevel() + 20)
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, DropdownMetrics.MENU_OFFSET_Y)
    -- Test the same native one-pixel border as the stable Section border.
    -- Field and popup now share the same renderer, avoiding mixed-edge offsets.
    menu:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",
        edgeSize=1,
        insets={left=0,right=0,top=0,bottom=0},
    })
    local function RepaintPopup(target)
        local color = TBU.WindowStyles:GetForFrame(target)
        target:SetBackdropColor(unpack(TBU.WindowStyles:GetControlInputCanvasColor(color)))
        target:SetBackdropBorderColor(unpack(TBU.WindowStyles:GetControlBorderColor(color)))
    end
    TBU.WindowStyles:RegisterVisual(menu, RepaintPopup)
    RepaintPopup(menu)
    menu:Hide()
    button.TBUPopupMenu = menu
    AttachDropdownCloseOnLeave(button, menu)
    menu:HookScript("OnShow", function() if button.RepaintDropdown then button.RepaintDropdown() end end)
    menu:HookScript("OnHide", function() if button.RepaintDropdown then button.RepaintDropdown() end end)
    menu.dynamicChildren = {}

    local viewport = CreateFrame("ScrollFrame", nil, menu)
    viewport:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
    viewport:EnableMouseWheel(true)
    local scrollContent = CreateFrame("Frame", nil, viewport)
    scrollContent:SetSize(1, 1)
    viewport:SetScrollChild(scrollContent)
    local scrollbar = CreateSettingsScrollbar(menu, viewport, button, "gold")
    scrollbar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -2)
    scrollbar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -4, 2)
    menu:HookScript("OnShow", function()
        AlignDropdownScrollbar(menu, button, scrollbar)
    end)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        scrollbar:ScrollBy(-delta * DropdownMetrics.OPTION_MIN_HEIGHT)
    end)

    local function clearMenuChildren()
        for _, child in ipairs(menu.dynamicChildren) do child:Hide() end
        menu.dynamicChildren = {}
    end

    local function rebuildMenu()
        clearMenuChildren()
        local currentOptions = resolvedOptions()
        menu:SetWidth(controlWidth)
        local useScroll = #currentOptions > DropdownMetrics.MAX_VISIBLE_OPTIONS
        local menuContentWidth = math.max(1, controlWidth - (useScroll and DropdownMetrics.SCROLLBAR_WIDTH or 0))
        scrollContent:SetWidth(menuContentWidth)
        local optionFlow = CreateDropdownOptionFlow(scrollContent)
        scrollContent.layoutMenuRows = {}
        for _, opt in ipairs(currentOptions) do
            if opt.header then
                -- A category header is an optional, nonselectable dropdown row.
                -- Its text and separator are measured independently of normal
                -- option rows, so text can wrap without hitting the divider.
                local headerRow = CreateFrame("Frame", nil, scrollContent)
                headerRow:SetWidth(math.max(1, menuContentWidth - DropdownMetrics.MENU_HORIZONTAL_INSET * 2))
                menu.dynamicChildren[#menu.dynamicChildren + 1] = headerRow

                local header = headerRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                header:SetPoint("TOPLEFT", headerRow, "TOPLEFT",
                    DropdownMetrics.HEADER_HORIZONTAL_INSET, -DropdownMetrics.HEADER_TOP_PADDING)
                header:SetWidth(math.max(1, headerRow:GetWidth() - DropdownMetrics.HEADER_HORIZONTAL_INSET * 2))
                header:SetJustifyH("LEFT")
                header:SetJustifyV("TOP")
                header:SetWordWrap(true)
                header:SetText(opt.header)
                ApplyContentText(header)

                local textHeight = math.max(1, math.ceil(header:GetStringHeight() or 1))
                local headerHeight = DropdownMetrics.HEADER_TOP_PADDING + textHeight
                    + DropdownMetrics.HEADER_TEXT_TO_DIVIDER_GAP + 1
                    + DropdownMetrics.HEADER_BOTTOM_PADDING
                optionFlow:Add(headerRow, headerHeight)
                scrollContent.layoutMenuRows[#scrollContent.layoutMenuRows + 1] = headerRow

                local underline = headerRow:CreateTexture(nil, "ARTWORK")
                underline:SetTexture("Interface\\Buttons\\WHITE8X8")
                underline:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0,
                    -DropdownMetrics.HEADER_TEXT_TO_DIVIDER_GAP)
                underline:SetPoint("RIGHT", headerRow, "RIGHT",
                    -DropdownMetrics.HEADER_HORIZONTAL_INSET, 0)
                underline:SetHeight(1)
                local function repaintDivider(target)
                    target:SetVertexColor(unpack(TBU.WindowStyles:GetSeparatorColor(target)))
                end
                TBU.WindowStyles:RegisterVisual(underline, repaintDivider)
                repaintDivider(underline)
            else
                local row = CreateFrame("Button", nil, scrollContent)
                row:SetWidth(math.max(1, menuContentWidth - DropdownMetrics.MENU_HORIZONTAL_INSET * 2)) -- measured within the scrolling viewport, not beneath the scrollbar
                menu.dynamicChildren[#menu.dynamicChildren + 1] = row

                local radio = CreateSingleSelectIndicator(row)
                radio:SetPoint("LEFT", row, "LEFT", DropdownMetrics.OPTION_INDICATOR_LEFT_INSET, 0)
                radio:SetChecked(getter() == opt.value)

                local optionText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                optionText:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("value", optionText)))
                ApplyContentText(optionText)
                ApplyRoleColor(optionText, "value", false, row)
                local rowHeight = PrepareDropdownOptionText(optionText, row, radio, opt.name)
                row.highlight = AddDropdownOptionHighlight(row, function() ExtendDropdownLifetime(button) end, function()
                    return GetDropdownOptionHighlightWidth(row, optionText, radio)
                end, 2)
                row.highlight:RefreshWidth()
                optionFlow:Add(row, rowHeight)
                scrollContent.layoutMenuRows[#scrollContent.layoutMenuRows + 1] = row

                local optionValue = opt.value
                local function chooseOption()
                    setter(optionValue)
                    refreshDisplay()
                    menu:Hide()
                    RegisterDropdownClosed(button)
                    TBU:RefreshAll()
                end
                radio:SetScript("OnClick", chooseOption)
                row:SetScript("OnClick", chooseOption)
            end
        end
        local fullHeight = optionFlow:GetHeight()
        local visibleHeight = fullHeight
        if useScroll then
            local maxHeight = DropdownMetrics.MENU_TOP_PADDING + DropdownMetrics.MENU_BOTTOM_PADDING
            local count = 0
            for _, child in ipairs(scrollContent.layoutMenuRows or {}) do
                count = count + 1
                if count > DropdownMetrics.MAX_VISIBLE_OPTIONS then break end
                maxHeight = maxHeight + child:GetHeight()
            end
            visibleHeight = math.min(fullHeight, maxHeight)
        end
        scrollContent:SetHeight(math.max(1, fullHeight))
        menu:SetSize(controlWidth, visibleHeight)
        viewport:SetSize(menuContentWidth, visibleHeight)
        viewport:SetVerticalScroll(0)
        if fullHeight > visibleHeight then
            scrollbar:Show()
            scrollbar:Update()
        else
            scrollbar:Hide()
        end
    end

    local function closeMenu()
        menu:Hide()
        RegisterDropdownClosed(button)
    end
    button:SetScript("OnClick", function()
        if menu:IsShown() then
            closeMenu()
        else
            rebuildMenu()
            RegisterDropdownOpened(button)
            menu:Show()
        end
    end)
    button:SetScript("OnHide", closeMenu)
    parent:HookScript("OnHide", closeMenu)

    button.SetControlWidth = function(_, newWidth)
        newWidth = math.max(1, math.floor((tonumber(newWidth) or controlWidth) + 0.5))
        if newWidth == controlWidth then return end
        controlWidth = newWidth
        button:SetWidth(controlWidth)
        if labelRegion then labelRegion:SetWidth(controlWidth) end
        menu:SetWidth(controlWidth)
        refreshDisplay()
        if menu:IsShown() then rebuildMenu() end
    end
    button.RefreshDisplay = refreshDisplay
    RegisterStatefulControl(button, function()
        refreshDisplay()
        if menu:IsShown() then rebuildMenu() end
    end)
    button.RebuildMenu = rebuildMenu
    button.DisplayText = displayText
    button.CloseMenu = closeMenu
    button.OptionMenu = menu
    button.GetPopupDownwardOffset = function() return -DropdownMetrics.MENU_OFFSET_Y end
    button.OptionLabel = labelText
    button.OptionLabelRegion = labelRegion
    button.GetExpandedMenuHeight = CreateSinglePopupHeightGetter(scrollContent, resolvedOptions,
        function() return controlWidth end)
    refreshDisplay()
    return button
end

-- Shared native-slider presentation. Values, labels, and behavior are supplied by
-- the consumer; input handling stays on WoW's native Slider frame. Unlike the
-- former OptionsSliderTemplate wrapper, every visible region is TreebeardUI-owned.
local function AddSteppedSlider(parent, label, values, x, y, getter, setter, formatter, behavior)
    local metrics = TBU.SettingsLayout.Metrics
    local labelHeight = DropdownMetrics.LABEL_HEIGHT
    local labelGap = DropdownMetrics.LABEL_TO_CONTROL_GAP
    local controlHeight = metrics.SLIDER_CONTROL_HEIGHT

    local content = CreateFrame("Frame", nil, parent)
    content.layoutKind = "content"
    content.layoutRole = "slider"
    content:SetSize(206, labelHeight + labelGap + controlHeight)

    -- Same font object, label region and anchor contract as dropdown Content.
    local labelRegion = CreateFrame("Frame", nil, content)
    labelRegion:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    labelRegion:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    labelRegion:SetHeight(labelHeight)
    local labelText = labelRegion:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    labelText:SetPoint("LEFT", labelRegion, "LEFT", 0, 0)
    labelText:SetPoint("RIGHT", labelRegion, "RIGHT", 0, 0)
    labelText:SetJustifyH("LEFT")
    ApplyRoleColor(labelText, "primary")

    local controlRegion = CreateFrame("Frame", nil, content)
    controlRegion:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(labelHeight + labelGap))
    controlRegion:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(labelHeight + labelGap))
    controlRegion:SetHeight(controlHeight)

    -- Endpoints occupy the SAME horizontal line as the track, not a second
    -- line underneath it. Each text field supplies its own natural width.
    local low = controlRegion:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    local high = controlRegion:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ApplyContentText(low)
    ApplyContentText(high)
    ApplyRoleColor(low, "value")
    ApplyRoleColor(high, "value")
    low:SetText(formatter(values[1]))
    high:SetText(formatter(values[#values]))
    low:SetPoint("LEFT", controlRegion, "LEFT", 0, 0)
    high:SetPoint("RIGHT", controlRegion, "RIGHT", 0, 0)
    low:SetJustifyH("LEFT")
    high:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, controlRegion)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("LEFT", low, "RIGHT", metrics.SLIDER_ENDPOINT_GAP, 0)
    slider:SetPoint("RIGHT", high, "LEFT", -metrics.SLIDER_ENDPOINT_GAP, 0)
    slider:SetHeight(metrics.SLIDER_HIT_HEIGHT)
    slider:SetMinMaxValues(1, #values)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    -- The subdued scrollbar track rotated horizontally, drawn as a thin
    -- full-width line behind a small round scrollbar-colored thumb.
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    local function repaintTrack(target)
        target:SetVertexColor(unpack(TBU.WindowStyles:GetWindowBorderColor(target)))
    end
    TBU.WindowStyles:RegisterVisual(track, repaintTrack)
    repaintTrack(track)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(metrics.SLIDER_TRACK_HEIGHT)
    -- Use WoW-supplied circular artwork directly. Both thumbs are independent
    -- of bundled PNG files; theme tints remain controlled by TreebeardUI.
    slider:SetThumbTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    local thumb = slider:GetThumbTexture()
    slider:SetHitRectInsets(-2, -2, -2, -2)
    if thumb then
        thumb:SetSize(metrics.SLIDER_THUMB_SIZE, metrics.SLIDER_THUMB_SIZE)
        -- Match the shared control presentation: action-button canvas at rest,
        -- dropdown-indicator color on hover, selected navigation border while
        -- dragging. Never change the consumer's slider value.
        local hovering = false
        local dragging = false
        local function refreshThumbAccent()
            local styles = TBU.WindowStyles
            local color
            if hovering or dragging then
                color = dragging
                    and styles:GetMainNavigationButtonSelectedBorderColor(thumb)
                    or styles:GetControlIndicatorColor(thumb)
            else
                color = styles:GetControlThumbIdleColor(thumb)
            end
            thumb:SetVertexColor(unpack(color))
        end
        TBU.WindowStyles:RegisterVisual(slider, refreshThumbAccent)
        slider:HookScript("OnEnter", function()
            hovering = true
            refreshThumbAccent()
        end)
        slider:HookScript("OnLeave", function()
            hovering = false
            refreshThumbAccent()
        end)
        slider:HookScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                dragging = true
                refreshThumbAccent()
            end
        end)
        slider:HookScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                dragging = false
                refreshThumbAccent()
            end
        end)
        slider:HookScript("OnHide", function()
            dragging = false
            hovering = false
            refreshThumbAccent()
        end)
        refreshThumbAccent()
    end

    local function nearestIndex(value)
        local best, dist = 1, math.huge
        for i, v in ipairs(values) do
            local d = math.abs(v - value)
            if d < dist then best, dist = i, d end
        end
        return best
    end

    behavior = behavior or {}
    -- SLIDER VALUE CONTRACT (all options optional; consumer owns policy):
    -- formatValue(value) -> text shown in the value label; defaults to the
    -- existing formatter. Changes in display precision NEVER change the value.
    -- validateInput(value) -> bool; defaults to finite, in-range numbers.
    -- normalizeInput(value) -> number; defaults to identity (no rounding).
    -- Normalization and validation apply to typed input only. Drag snapping,
    -- actual stored values and automatic intervals remain separate concerns.
    local formatValue = type(behavior.formatValue) == "function" and behavior.formatValue or formatter
    local validateInput = type(behavior.validateInput) == "function" and behavior.validateInput or function(v)
        return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
            and v >= values[1] and v <= values[#values]
    end
    local normalizeInput = type(behavior.normalizeInput) == "function" and behavior.normalizeInput or function(v)
        return v
    end
    local function displayValue(v)
        local ok, formatted = pcall(formatValue, v)
        return ok and formatted ~= nil and tostring(formatted) or tostring(v)
    end
    -- Optional width-calibrated drag stops. Measure the real usable track,
    -- not the Section or outer Content. Manual value stepping is unchanged
    -- unless the consumer explicitly enables this mode.
    local autoIntervals = behavior.autoDragIntervals == true
    local unitsPerStop = math.max(1, tonumber(behavior.unitsPerDragStop) or 12)
    local dragIntervals = math.max(1, #values - 1)
    local reconfiguring = false
    local minValue, maxValue = values[1], values[#values]
    local function valueForPosition(position)
        if not autoIntervals then return values[math.max(1, math.min(#values, math.floor(position + 0.5)))] end
        local fraction = math.max(0, math.min(1, (position - 1) / dragIntervals))
        local raw = minValue + fraction * (maxValue - minValue)
        -- Floating-point noise should not enter SavedVariables.
        return math.floor(raw * 10000 + 0.5) / 10000
    end
    local function positionForValue(value)
        if not autoIntervals or maxValue == minValue then return nearestIndex(value) end
        return 1 + math.floor((math.max(minValue, math.min(maxValue, value)) - minValue)
            / (maxValue - minValue) * dragIntervals + 0.5)
    end
    local function applyTrackIntervals()
        if not autoIntervals then return end
        local width = slider:GetWidth()
        if not width or width <= 0 then return end
        local count = math.max(1, math.floor(width / unitsPerStop + 0.5))
        if count == dragIntervals then return end
        dragIntervals = count
        local committed = getter()
        reconfiguring = true
        slider:SetMinMaxValues(1, count + 1)
        slider:SetValue(positionForValue(committed))
        reconfiguring = false
    end
    local editableValue = behavior.editableValue == true
    -- Editable values use a separate focusable input; the label itself remains
    -- framework-owned and uses the same font and alignment as a dropdown.
    local valueButton, valueText, valueEdit
    if editableValue then
        labelText:ClearAllPoints()
        labelText:SetPoint("LEFT", labelRegion, "LEFT", 0, 0)
        labelText:SetText(label .. ":")
        labelText:SetWidth(math.max(1, labelText:GetStringWidth() + 2))
        valueButton = CreateFrame("Button", nil, labelRegion)
        valueButton:SetHeight(labelHeight)
        valueButton:SetWidth(100)
        valueButton:SetPoint("LEFT", labelText, "RIGHT", 5, 0)
        valueText = valueButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        valueText:SetAllPoints()
        valueText:SetJustifyH("LEFT")
        ApplyRoleColor(valueText, "value")
        valueEdit = CreateFrame("EditBox", nil, labelRegion)
        valueEdit:SetSize(94, labelHeight + 5)
        valueEdit:SetPoint("LEFT", valueButton, "LEFT", -4, 0)
        valueEdit:SetAutoFocus(false)
        valueEdit:SetMaxLetters(18)
        valueEdit:SetFontObject("GameFontHighlightSmall")
        valueEdit:SetJustifyH("LEFT")
        ApplyRecessedInput(valueEdit, 25)
        ApplyRoleColor(valueEdit, "value", true)
        valueEdit.inputIcon = AddTextInputGlyph(valueEdit)
        valueEdit:Hide()
    end

    local function updateLabel(index, providedValue)
        -- Values entered directly can sit between automatic drag positions.
        -- Preserve that committed value in the display; the thumb still snaps
        -- to the nearest physical drag stop without committing a replacement.
        local value = providedValue
        if value == nil then value = valueForPosition(index) end
        if editableValue then
            if not valueEdit:HasFocus() then valueText:SetText(displayValue(value) .. "  [edit]") end
        else
            labelText:SetText(label .. ": " .. displayValue(value))
        end
    end

    -- Existing consumer interaction contract is unchanged. In particular,
    -- commitOnRelease prevents window-scale feedback while actively dragging.
    behavior = behavior or {}
    local commitOnRelease = behavior.commitOnRelease == true
    local syncing = false
    local pendingValue = nil
    local lastCommittedValue = getter()

    local function commit(value)
        if value == nil then return end
        pendingValue = nil
        if value == lastCommittedValue then return end
        lastCommittedValue = value
        setter(value)
        TBU:RefreshAll()
    end

    if editableValue then
        local function cancelEdit()
            valueEdit:Hide()
            valueEdit:ClearFocus()
            TBU.InputFocus:Refresh(valueEdit)
            valueButton:Show()
            updateLabel(positionForValue(getter()), getter())
        end
        local function acceptEdit()
            local n = tonumber(valueEdit:GetText())
            if not n or n ~= n or n == math.huge or n == -math.huge then cancelEdit(); return end
            -- Preserve historical default clamping. Custom validators can
            -- reject instead of clamping; normalization never changes a
            -- committed value until Enter is pressed.
            if type(behavior.validateInput) ~= "function" then
                n = math.max(values[1], math.min(values[#values], n))
            end
            local okNormalized, normalized = pcall(normalizeInput, n)
            if not okNormalized or type(normalized) ~= "number" or normalized ~= normalized
                or normalized == math.huge or normalized == -math.huge then
                cancelEdit(); return
            end
            n = normalized
            local okValid, valid = pcall(validateInput, n)
            if not okValid or not valid or n < values[1] or n > values[#values] then
                cancelEdit(); return
            end
            local index = positionForValue(n)
            valueEdit:Hide()
            valueEdit:ClearFocus()
            TBU.InputFocus:Refresh(valueEdit)
            valueButton:Show()
            syncing = true
            slider:SetValue(index)
            syncing = false
            updateLabel(index, n)
            commit(n)
        end
        valueButton:SetScript("OnClick", function()
            valueButton:Hide()
            valueEdit:SetText(tostring(getter()))
            valueEdit:Show()
            valueEdit:SetFocus()
            valueEdit:HighlightText()
        end)
        valueEdit:SetScript("OnEnterPressed", acceptEdit)
        valueEdit:SetScript("OnEscapePressed", cancelEdit)
        valueEdit:SetScript("OnEditFocusLost", function()
            if valueEdit:IsShown() then cancelEdit() end
        end)
        content.valueEditBox = valueEdit
    end

    local initial = positionForValue(lastCommittedValue)
    slider:SetValue(initial)
    updateLabel(initial, lastCommittedValue)
    slider:SetScript("OnValueChanged", function(_, index)
        if syncing or reconfiguring then return end
        index = math.max(1, math.min(autoIntervals and (dragIntervals + 1) or #values, math.floor(index + 0.5)))
        local value = valueForPosition(index)
        if value == nil then return end
        updateLabel(index)
        if commitOnRelease and IsMouseButtonDown("LeftButton") then
            pendingValue = value
        else
            commit(value)
        end
    end)

    if commitOnRelease then
        local function releasePending()
            if pendingValue ~= nil then commit(pendingValue) end
        end
        slider:HookScript("OnMouseUp", releasePending)
        slider:HookScript("OnUpdate", function()
            if pendingValue ~= nil and not IsMouseButtonDown("LeftButton") then
                releasePending()
            end
        end)
    end

    content.RefreshValue = function()
        local actual = getter()
        lastCommittedValue = actual
        local index = positionForValue(actual)
        syncing = true
        slider:SetValue(index)
        syncing = false
        updateLabel(index, actual)
    end
    RegisterStatefulControl(content, content.RefreshValue)
    if autoIntervals then
        slider:HookScript("OnSizeChanged", function()
            applyTrackIntervals()
        end)
        -- Initial width becomes nonzero after the consumer's Row/Column
        -- geometry is measured. This does not commit a value when resizing.
        applyTrackIntervals()
    end
    content.GetDragIntervalCount = function() return dragIntervals end
    content.slider = slider
    content.OptionLabel = labelText
    content.OptionLabelRegion = labelRegion
    content.Low = low
    content.High = high
    return content
end

local function AddDropdownContent(parent, label, options, getter, setter, width, contentOptions)
    local controlWidth = width
    contentOptions = contentOptions or {}

    -- Every dropdown is created with a label. Presentation decides whether that
    -- owned label is shown; hidden labels do not consume logical content height.
    local showLabel = contentOptions.showLabel
    if showLabel == nil then showLabel = true end
    local labelAlign = contentOptions.labelAlign or "LEFT"
    local labelHeight = showLabel and DropdownMetrics.LABEL_HEIGHT or 0
    local labelGap = showLabel and DropdownMetrics.LABEL_TO_CONTROL_GAP or 0

    local content = CreateFrame("Frame", nil, parent)
    content.layoutKind = "content"
    content.layoutRole = "dropdown"

    local button = AddSingleDropdown(content, label or "", 0, 0, options, getter, setter, controlWidth)
    controlWidth = math.max(1, math.ceil(button:GetWidth() or 1))
    -- The Blizzard dropdown skin owns the closed bar's intrinsic height. Content
    -- measures that live value instead of duplicating it as a Settings magic number.
    local controlHeight = math.max(1, math.ceil(button:GetHeight() or 1))
    content:SetSize(controlWidth, labelHeight + labelGap + controlHeight)

    if button.OptionLabelRegion then
        button.OptionLabelRegion:ClearAllPoints()
        button.OptionLabelRegion:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        button.OptionLabelRegion:SetSize(controlWidth, labelHeight)
        button.OptionLabelRegion:SetShown(showLabel)
    end
    if button.OptionLabel then
        button.OptionLabel:SetJustifyH(labelAlign)
        button.OptionLabel:SetShown(showLabel)
    end

    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(labelHeight + labelGap))

    content.Control = button
    content.OptionLabel = button.OptionLabel
    content.OptionLabelRegion = button.OptionLabelRegion
    content.ShowLabel = showLabel
    content.LabelAlign = labelAlign
    content.RefreshDisplay = function(self)
        if self.Control and self.Control.RefreshDisplay then
            self.Control:RefreshDisplay()
        end
    end
    content:SetScript("OnSizeChanged", function(self, newWidth)
        if self.layoutFillWidth and self.Control and self.Control.SetControlWidth and newWidth and newWidth > 1 then
            self.Control:SetControlWidth(newWidth)
        end
    end)
    return content
end

-- Diagnostic Content helper kept outside InitializeSettings so repetitive test
-- controls do not consume that function's limited local-variable budget.
-- Real hudcraft settings remain explicit; loops here are for test data only.
local function AddMultiDropdownContent(parent, label, options, width, contentOptions)
    local controlWidth = width
    contentOptions = contentOptions or {}
    local showLabel = contentOptions.showLabel
    if showLabel == nil then showLabel = true end
    local labelAlign = contentOptions.labelAlign or "LEFT"
    local labelHeight = showLabel and DropdownMetrics.LABEL_HEIGHT or 0
    local labelGap = showLabel and DropdownMetrics.LABEL_TO_CONTROL_GAP or 0

    local content = CreateFrame("Frame", nil, parent)
    content.layoutKind = "content"
    content.layoutRole = "dropdown"

    local button = AddMultiDropdown(content, label or "", 0, 0, options, controlWidth, contentOptions.emptyText)
    controlWidth = math.max(1, math.ceil(button:GetWidth() or 1))
    -- Match Single Dropdown: the closed bar reports its own intrinsic height.
    local controlHeight = math.max(1, math.ceil(button:GetHeight() or 1))
    content:SetSize(controlWidth, labelHeight + labelGap + controlHeight)

    if button.OptionLabelRegion then
        button.OptionLabelRegion:ClearAllPoints()
        button.OptionLabelRegion:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        button.OptionLabelRegion:SetSize(controlWidth, labelHeight)
        button.OptionLabelRegion:SetShown(showLabel)
    end
    if button.OptionLabel then
        button.OptionLabel:SetJustifyH(labelAlign)
        button.OptionLabel:SetShown(showLabel)
    end

    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(labelHeight + labelGap))

    content.Control = button
    content.OptionLabel = button.OptionLabel
    content.OptionLabelRegion = button.OptionLabelRegion
    content.ShowLabel = showLabel
    content.LabelAlign = labelAlign
    content.RefreshDisplay = function(self)
        if self.Control and self.Control.RefreshDisplay then
            self.Control:RefreshDisplay()
        end
    end
    content:SetScript("OnSizeChanged", function(self, newWidth)
        if self.layoutFillWidth and self.Control and self.Control.SetControlWidth and newWidth and newWidth > 1 then
            self.Control:SetControlWidth(newWidth)
        end
    end)
    return content
end

local function AddDropdown(parent, label, x, y, options, getter, setter, width)
    -- All framework settings single-select controls use the same custom menu.
    return AddSingleDropdown(parent, label, x, y, options, getter, setter, width)
end

-- Diagnostic helper: lets us compare inherited dropdown-label placement with
-- explicit left/center alignment without changing the dropdown implementation.
local function SetDropdownLabelAlignment(dropdown, mode)
    local label = dropdown and dropdown.OptionLabel
    local region = dropdown and dropdown.OptionLabelRegion
    if not label or not region then return end

    -- Alignment changes only how text is justified inside the layout-owned
    -- label region. It never re-anchors the label to the dropdown control.
    if mode == "LEFT" then
        label:SetJustifyH("LEFT")
    elseif mode == "CENTER" then
        label:SetJustifyH("CENTER")
    elseif mode == "RIGHT" then
        label:SetJustifyH("RIGHT")
    end
end


local function AddModuleSelectionDropdown(parent, label, x, y, options, selectedGetter, toggleSetter, width)
    local mapped = {}
    for _, option in ipairs(options) do
        mapped[#mapped + 1] = {
            name = option.name,
            shortLabel = option.shortLabel,
            getter = function()
                local selected = selectedGetter() or {}
                return selected[option.value] == true
            end,
            setter = function(enabled)
                toggleSetter(option.value, enabled)
            end,
        }
    end
    local dd = AddMultiDropdown(parent, label, x, y, mapped, width or 220)
    -- Module Selection is an action/menu control; keep its closed label stable.
    dd.RefreshDisplay = function()
        if dd.DisplayText then dd.DisplayText:SetText("Module Selection") end
    end
    if dd.DisplayText then dd.DisplayText:SetText("Module Selection") end
    return dd
end

local function AddActionButton(parent, label, x, y, width, callback, labelOptions)
    -- Reuse the same preset-aware buttons as navigation, output and chrome.
    -- Unlike UIPanelButtonTemplate this has no Blizzard border or text theme.
    local button = TBU.WindowStyles:CreateButton(parent, label, width or 170,
        callback or function() end, nil, labelOptions)
    button:SetPoint("TOPLEFT", x, y)
    if button.labelOptions and button.labelOptions.autoHeight then
        button.labelOptions.minHeight = math.max(1, tonumber(button.labelOptions.minHeight) or 24)
        button:UpdateLabelGeometry()
    else
        button:SetHeight(24)
    end
    return button
end

local function AddActionButtonContent(parent, label, callback, options)
    options = options or {}
    local mode = options.widthMode or "fill" -- Preserve existing content-button default.
    if mode ~= "auto" and mode ~= "fill" and mode ~= "fixed" then mode = "fill" end
    local content = CreateFrame("Frame", nil, parent)
    content.layoutKind = "content"
    content:SetHeight(24)

    local labelOptions = {}
    for key, value in pairs(options) do labelOptions[key] = value end
    labelOptions.horizontalPadding = math.max(0,
        tonumber(options.horizontalPadding) or 12)
    local button = AddActionButton(content, label, 0, 0, 1,
        callback or function() end, labelOptions)
    button:ClearAllPoints()
    button:SetAllPoints(content)
    if button.labelOptions and button.labelOptions.autoHeight then
        button:HookScript("OnSizeChanged", function(target)
            local height = target:GetHeight() or 24
            if math.abs((content:GetHeight() or 0) - height) > 0.0001 then
                content:SetHeight(height)
            end
        end)
        button:UpdateLabelGeometry()
    end
    local pad = labelOptions.horizontalPadding
    local natural = math.ceil((button.label and button.label:GetStringWidth() or 0) + pad * 2)
    content:SetWidth(mode == "fixed" and math.max(1, tonumber(options.width) or natural) or math.max(1, natural))
    content.layoutButtonWidthMode = mode
    content.Button = button
    return content
end

-- Shared commit path for standalone choice controls. A selection
-- change is local UI state and should be applied to the HUD immediately, just
-- like Dropdown and MultiDropdown changes.  Keep this behavior here so every
-- choice instance inherits it instead of patching individual settings.
local function CommitChoiceSelection(setter, value)
    if setter then setter(value) end
    TBU:RefreshAll()
end

-- Standalone checkbox content for consumer-owned boolean values. The full row
-- is clickable, while the checkbox remains the visible state indicator. The
-- row participates in column flow and grows to fit a wrapped label.
local function AddCheckbox(parentColumn, label, getter, setter)
    local content = CreateFrame("Button", nil, parentColumn)
    content.layoutKind = "content"
    content.layoutRole = "selection"

    local compactHighlightWidth = 1
    local highlight = AddDropdownOptionHighlight(content, nil, function() return compactHighlightWidth end, 1, -20)

    local check = CreateLargeCheckbox(content)
    check:SetPoint("LEFT", content, "LEFT", ControlMetrics.RADIO_INDICATOR_LEFT_INSET, 0)
    check:SetScript("OnClick", function() content:Click() end)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(true)
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
    if text.SetMaxLines then text:SetMaxLines(0) end
    ApplyContentText(text)
    ApplyRoleColor(text, "value")
    text:SetText(label or "")

    local function Refresh()
        check:SetChecked(getter and getter() and true or false)

        local width = math.max(1, math.ceil(content:GetWidth() or parentColumn:GetWidth() or 1))
        local leftInset = ControlMetrics.RADIO_INDICATOR_LEFT_INSET
            + ControlMetrics.STANDALONE_OPTION_INDICATOR_SIZE
            + ControlMetrics.RADIO_TEXT_GAP
        text:ClearAllPoints()
        text:SetPoint("LEFT", content, "LEFT", leftInset, 0)
        text:SetWidth(math.max(1, width - leftInset - ControlMetrics.RADIO_TEXT_RIGHT_INSET))

        local textHeight = math.ceil(text:GetStringHeight() or 0)
        local textVisualWidth = math.ceil(text:GetStringWidth() or 0)
        compactHighlightWidth = math.min(width, leftInset + textVisualWidth + ControlMetrics.RADIO_TEXT_RIGHT_INSET + (width * ControlMetrics.RADIO_HIGHLIGHT_EXTRA_WIDTH_RATIO))
        highlight:RefreshWidth()
        local height = math.max(ControlMetrics.RADIO_OPTION_MIN_HEIGHT,
            textHeight + (ControlMetrics.RADIO_TEXT_VERTICAL_PADDING * 2))
        content:SetHeight(height)
    end

    content:SetScript("OnClick", function()
        CommitChoiceSelection(setter, not (getter and getter() and true or false))
        Refresh()
    end)
    content:SetScript("OnSizeChanged", function(_, width)
        if width and width > 1 then Refresh() end
    end)

    content.Refresh = Refresh
    RegisterStatefulControl(content, Refresh)
    content.Check = check
    content.Text = text
    Refresh()
    return content
end


-- Reusable single-selection radio Content built directly in SettingsControls.
-- It follows the same width-down / measured-height-up contract as dropdown
-- option flow: each choice measures its wrapping label, then the next choice
-- flows after the resulting row height.
local function AddRadioSelectorContent(parent, label, options, getter, setter)
    local content = CreateFrame("Frame", nil, parent)
    content.layoutKind = "content"
    content.layoutRole = "radio-selector"
    content.rows = {}

    local title
    local topOffset = 0
    if label and label ~= "" then
        title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        title:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        title:SetJustifyH("LEFT")
        title:SetText(label)
        ApplyContentText(title)
        topOffset = math.ceil(title:GetStringHeight() or 1) + ControlMetrics.RADIO_LABEL_TO_OPTIONS_GAP
    end

    local choices = CreateFrame("Frame", nil, content)
    choices:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -topOffset)
    choices:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -topOffset)

    local function Refresh()
        local width = math.max(1, math.ceil(content:GetWidth() or parent:GetWidth() or 1))
        choices:SetWidth(width)
        local flow = CreateVerticalControlFlow(choices, { gap=ControlMetrics.RADIO_OPTION_GAP })
        local current = nil
        if getter then current = getter() end -- Preserve false-valued radio choices.

        for index, option in ipairs(options or {}) do
            local row = content.rows[index]
            if not row then
                row = CreateFrame("Button", nil, choices)
                -- Standalone selectors advertise only their actual visual/clickable
                -- footprint. Long/wrapped labels can still grow to the available width.
                row.compactHighlightWidth = 1
                row.highlight = AddDropdownOptionHighlight(row, nil, function() return row.compactHighlightWidth end, 1, -20)
                local indicator = CreateChoiceIndicator(row, true, ControlMetrics.STANDALONE_OPTION_INDICATOR_SIZE)
                indicator:SetPoint("LEFT", row, "LEFT", ControlMetrics.RADIO_INDICATOR_LEFT_INSET, 0)
                indicator:SetScript("OnClick", function() row:Click() end)
                row.indicator = indicator

                local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetJustifyH("LEFT")
                text:SetJustifyV("MIDDLE")
                text:SetWordWrap(true)
                if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
                if text.SetMaxLines then text:SetMaxLines(0) end
                ApplyContentText(text)
                ApplyRoleColor(text, "value", false, row)
                row.text = text

                row:SetScript("OnClick", function(self)
                    if self.value ~= nil then CommitChoiceSelection(setter, self.value) end
                    Refresh()
                end)
                content.rows[index] = row
            end

            row.value = option.value
            row.text:ClearAllPoints()
            local leftInset = ControlMetrics.RADIO_INDICATOR_LEFT_INSET + ControlMetrics.STANDALONE_OPTION_INDICATOR_SIZE + ControlMetrics.RADIO_TEXT_GAP
            row.text:SetPoint("LEFT", row, "LEFT", leftInset, 0)
            local textWidth = math.max(1, width - leftInset - ControlMetrics.RADIO_TEXT_RIGHT_INSET)
            row.text:SetWidth(textWidth)
            row.text:SetText(option.name or tostring(option.value or ""))
            local textHeight = math.ceil(row.text:GetStringHeight() or 0)
            local textVisualWidth = math.ceil(row.text:GetStringWidth() or 0)
            row.compactHighlightWidth = math.min(width, leftInset + textVisualWidth + ControlMetrics.RADIO_TEXT_RIGHT_INSET + (width * ControlMetrics.RADIO_HIGHLIGHT_EXTRA_WIDTH_RATIO))
            row.highlight:RefreshWidth()
            local rowHeight = math.max(ControlMetrics.RADIO_OPTION_MIN_HEIGHT, textHeight + (ControlMetrics.RADIO_TEXT_VERTICAL_PADDING * 2))
            row.indicator:SetChecked(current == option.value)
            row:Show()
            flow:Add(row, rowHeight)
        end

        for index = #(options or {}) + 1, #content.rows do content.rows[index]:Hide() end
        local choicesHeight = flow:GetHeight()
        choices:SetHeight(math.max(1, choicesHeight))
        content:SetHeight(math.max(1, topOffset + choicesHeight))
    end

    content.Refresh = Refresh
    RegisterStatefulControl(content, Refresh)
    content:SetScript("OnSizeChanged", function(_, width)
        if width and width > 1 then Refresh() end
    end)
    Refresh()
    return content
end

-- Library-owned recessed input chrome. Three horizontal texture slices keep the
-- rounded corners consistent without stretching them as the control widens.
-- The native EditBox still owns selection, caret, focus, and keyboard handling.
ApplyRecessedInput = function(edit, rightInset)
    local texturePath = TBU:GetAssetPath("input_mask.png")
    local layers = {}
    local function addLayer(inset, xShift, yShift, depth)
        local slices = {}
        for i = 1, 3 do
            local tex = edit:CreateTexture(nil, "BACKGROUND", nil, depth)
            tex:SetTexture(texturePath)
            if i == 1 then
                tex:SetTexCoord(0, 0.25, 0, 1)
                tex:SetPoint("TOPLEFT", edit, "TOPLEFT", inset + xShift, -inset + yShift)
                tex:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", inset + xShift, inset + yShift)
                tex:SetWidth(8)
            elseif i == 2 then
                tex:SetTexCoord(0.25, 0.75, 0, 1)
                tex:SetPoint("TOPLEFT", slices[1], "TOPRIGHT")
                tex:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -(inset + 8) + xShift, inset + yShift)
            else
                tex:SetTexCoord(0.75, 1, 0, 1)
                tex:SetPoint("TOPRIGHT", edit, "TOPRIGHT", -inset + xShift, -inset + yShift)
                tex:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -inset + xShift, inset + yShift)
                tex:SetWidth(8)
            end
            slices[i] = tex
        end
        layers[#layers + 1] = slices
    end
    addLayer(0, 1, -1, -8) -- slight drop shadow
    addLayer(0, 0, 0, -7) -- theme border
    addLayer(1, 0, 0, -6) -- inset dark fill
    edit:SetTextInsets(6, rightInset or 7, 0, 0)
    local function paintShadow()
        local style = TBU.WindowStyles:GetForFrame(edit)
        local shadow = TBU.WindowStyles:GetRecessedInputShadowColor(style)
        for _, texture in ipairs(layers[1]) do
            texture:SetVertexColor(unpack(shadow))
        end
    end
    local function paintBorder()
        local style = TBU.WindowStyles:GetForFrame(edit)
        local border = TBU.InputFocus:IsFocused(edit)
            and TBU.WindowStyles:GetTextInputFocusBorderColor(style)
            or TBU.WindowStyles:GetControlBorderColor(style)
        for _, texture in ipairs(layers[2]) do
            texture:SetVertexColor(border[1], border[2], border[3], 1)
        end
    end
    local function paintFill()
        local style = TBU.WindowStyles:GetForFrame(edit)
        local fill = TBU.WindowStyles:GetControlInputCanvasColor(style)
        for _, texture in ipairs(layers[3]) do
            texture:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
        end
    end
    -- Register each visual region separately. The EditBox itself is also
    -- registered by ApplyRoleColor, and RegisterVisual intentionally keeps
    -- one callback per frame; storing chrome repaint on the EditBox would be
    -- replaced by the text-color callback.
    for _, texture in ipairs(layers[1]) do
        TBU.WindowStyles:RegisterVisual(texture, paintShadow)
    end
    for _, texture in ipairs(layers[2]) do
        TBU.WindowStyles:RegisterVisual(texture, paintBorder)
    end
    for _, texture in ipairs(layers[3]) do
        TBU.WindowStyles:RegisterVisual(texture, paintFill)
    end
    local function repaint()
        paintShadow()
        paintBorder()
        paintFill()
    end
    edit.RepaintInputChrome = repaint
    TBU.InputFocus:Attach(edit, function() repaint() end)
    repaint()
end

-- Generic, consumer-owned text input. The EditBox owns only a temporary draft;
-- validation, persistence, and application-specific log messages belong to the caller.
local function AddTextInputContent(parent, label, getter, setter, behavior)
    behavior = behavior or {}
    local content = CreateFrame("Frame", nil, parent)
    content.layoutKind = "content"
    content.layoutRole = "text-input"
    local metrics = TBU.SettingsLayout.Metrics
    local caption = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    caption:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    caption:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    caption:SetJustifyH(parent.layoutAlign == "LEFT" and "LEFT" or "CENTER")
    caption:SetText(label or "")
    ApplyContentText(caption)
    local captionHeight = math.max(1, caption:GetStringHeight() or 1)
    local edit = CreateFrame("EditBox", nil, content)
    edit:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -metrics.COLOR_CONTROL_GAP)
    edit:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    edit:SetHeight(metrics.COLOR_EDIT_HEIGHT)
    edit:SetAutoFocus(false)
    edit:EnableMouse(true)
    edit:EnableKeyboard(true)
    edit:HookScript("OnMouseDown", function(target, button)
        if button == "LeftButton" then target:SetFocus() end
    end)
    edit:SetFontObject("GameFontHighlight")
    edit:SetMaxLetters(behavior.maxLetters or 128)
    edit:SetJustifyH("LEFT")
    ApplyContentText(edit)
    local showIcon = behavior.showInputIcon ~= false and behavior.isColorInput ~= true
    ApplyRecessedInput(edit, behavior.rightInset or (showIcon and 25 or 7))
    -- Editable values use the primary text role even before focus. The value
    -- role remains useful for the other, read-only settings controls.
    local repaintValueText = ApplyRoleColor(edit, "primary", true)
    edit:HookScript("OnTextChanged", function(target)
        repaintValueText(target)
    end)
    if showIcon then content.inputIcon = AddTextInputGlyph(edit) end
    content:SetHeight(captionHeight + metrics.COLOR_CONTROL_GAP + metrics.COLOR_EDIT_HEIGHT)
    local function refresh(force)
        force = force == true
        if not force and edit:HasFocus() then return end
        local value = tostring(getter() or "")
        edit:SetText(value)
        -- SetText leaves the insertion point at the end, which can horizontally
        -- scroll an unfocused EditBox past short values. Start idle views at the
        -- beginning; never disturb the caret or scroll position during editing.
        if not edit:HasFocus() then edit:SetCursorPosition(0) end
        repaintValueText(edit)
        if behavior.onRefresh then behavior.onRefresh(content, value) end
    end
    content.Refresh = refresh
    -- RegisterRefreshControl invokes callbacks with the control as an argument;
    -- keep that object from being mistaken for the optional force flag.
    RegisterStatefulControl(content, function() refresh() end)
    -- Settings pages are often constructed while hidden. Re-read consumer data
    -- when this input becomes visible so its initial displayed value is current.
    content:HookScript("OnShow", function() refresh() end)
    local finishing = false
    local function finish(commit)
        if finishing then return end
        finishing = true
        -- Even rejected edits are discarded; the consumer decides how to log.
        if commit then setter(edit:GetText()) end
        edit:ClearFocus()
        TBU.InputFocus:Refresh(edit)
        if edit.RepaintInputChrome then edit:RepaintInputChrome() end
        finishing = false
        refresh()
        if commit then TBU:RefreshAll() end
    end
    edit:SetScript("OnEnterPressed", function() finish(true) end)
    edit:SetScript("OnEscapePressed", function() finish(false) end)
    edit:SetScript("OnEditFocusLost", function() if not finishing then finish(behavior.commitOnFocusLost == true) end end)
    content.editBox = edit
    content.label = caption
    -- Always populate at creation. Focus guards are only for later refreshes,
    -- when preserving a user's in-progress draft matters.
    refresh(true)
    return content
end

-- Color input composes generic text editing with a visual swatch. Hex policy
-- and defaults remain the consumer's responsibility; no theme colors change.
local function AddHexColorContent(parent, label, getter, setter, onChanged)
    local content = AddTextInputContent(parent, label,
        function() return getter() end,
        function(value)
            local accepted = setter(value)
            if accepted and onChanged then onChanged(content) end
            return accepted
        end,
        {maxLetters=32, rightInset=28, isColorInput=true})
    content.layoutRole = "color"
    local swatch = TBU:CreateBackdropFrame("Frame", content.editBox)
    swatch:SetSize(12, 12)
    swatch:SetPoint("RIGHT", content.editBox, "RIGHT", -5, 0)
    swatch:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    local preview = swatch:CreateTexture(nil, "ARTWORK")
    preview:SetTexture("Interface\\Buttons\\WHITE8X8")
    preview:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
    preview:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    swatch.preview = preview
    local function repaintSwatch()
        local style = TBU.WindowStyles:GetForFrame(content.editBox)
        local border = TBU.WindowStyles:GetControlBorderColor(style)
        swatch:SetBackdropColor(unpack(TBU.WindowStyles:GetControlInputCanvasColor(style)))
        swatch:SetBackdropBorderColor(border[1], border[2], border[3], 0.95)
    end
    TBU.WindowStyles:RegisterVisual(swatch, repaintSwatch)
    repaintSwatch()
    swatch:EnableMouse(false)
    local baseRefresh = content.Refresh
    local function refreshSwatch(value)
        local hex = tostring(value or ""):gsub("^#", "")
        if #hex == 6 and hex:match("^%x+$") then
            local r = tonumber(hex:sub(1, 2), 16) / 255
            local g = tonumber(hex:sub(3, 4), 16) / 255
            local b = tonumber(hex:sub(5, 6), 16) / 255
            preview:SetVertexColor(r, g, b, 1)
        else
            preview:SetVertexColor(1, 1, 1, 1)
        end
    end
    -- The saved color is committed only on Enter, but its preview tracks the
    -- live draft so the visible hex and swatch stay in step while typing.
    content.editBox:HookScript("OnTextChanged", function(edit)
        refreshSwatch(edit:GetText())
    end)
    -- Register another shared refresh callback under the same key by replacing
    -- the initial one. The swatch derives its fill from the authoritative hex
    -- value, so consumers do not need to return a second RGB representation.
    local function refresh()
        baseRefresh()
        refreshSwatch(content.editBox:GetText())
        repaintSwatch()
    end
    content.Refresh = refresh
    content.RefreshColor = refresh
    RegisterStatefulControl(content, refresh)
    content.colorSwatch = swatch
    refresh()
    return content
end

local function AddDraggableOrderedListContent(parent, labelText, initialValues, displayName, onReorder)
    local control = CreateFrame("Frame", nil, parent)
    control.rows = {}
    control.values = {}
    for i, value in ipairs(initialValues or {}) do control.values[i] = value end

    local title = control:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", control, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", control, "TOPRIGHT", 0, 0)
    title:SetJustifyH("LEFT")
    title:SetText(labelText or "")
    ApplyContentText(title)

    local list = CreateFrame("Frame", nil, control)
    list:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    list:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -5)
    list.rows = control.rows
    control.list = list

    local ROW_HEIGHT, ROW_GAP = 24, 3
    local function CopyValues(values)
        local copy = {}
        for i, value in ipairs(values or {}) do copy[i] = value end
        return copy
    end

    local Refresh
    local lastListWidth
    local function CreateRow()
        local row = TBU:CreateBackdropFrame("Button", list)
        row:SetHeight(ROW_HEIGHT)
        row:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Buttons\\WHITE8X8",
            edgeSize=1,
        })
        -- Keep the row's existing canvas and border visible during hover/drag.
        -- State styling can recolor these same surfaces without adding layers.
        local hovering, dragging = false, false
        local function repaintRow(target)
            local style = TBU.WindowStyles:GetForFrame(target)
            -- GetMainCanvasColor returns one RGBA array, not four values.
            -- BackdropTemplateMixin:SetBackdropColor expects numeric channels.
            local canvas = TBU.WindowStyles:GetControlInputCanvasColor(style)
            local alpha = (hovering or dragging) and 1 or (canvas[4] or 1)
            target:SetBackdropColor(canvas[1], canvas[2], canvas[3], alpha)
            target:SetBackdropBorderColor(unpack(TBU.WindowStyles:GetControlBorderColor(style)))
        end
        TBU.WindowStyles:RegisterVisual(row, repaintRow)
        repaintRow(row)
        row:SetMovable(true)
        row:SetClampedToScreen(true)
        row:RegisterForDrag("LeftButton")
        local restingFrameLevel

        local grip = row:CreateTexture(nil, "ARTWORK")
        grip:SetSize(16, 16)
        grip:SetPoint("LEFT", row, "LEFT", 7, 0)
        grip:SetTexture(TBU:GetAssetPath("draggable_list_grip.png"))
        row.grip = grip
        local function RepaintGrip()
            local styles = TBU.WindowStyles
            local tint = dragging and styles:GetWindowInteractionColor(row)
                or hovering and styles:GetWindowHighlightColor(row)
                or styles:GetControlBorderColor(row)
            grip:SetVertexColor(unpack(tint))
        end
        TBU.WindowStyles:RegisterVisual(grip, RepaintGrip)
        RepaintGrip()

        row:HookScript("OnEnter", function()
            hovering = true
            repaintRow(row)
            RepaintGrip()
        end)
        row:HookScript("OnLeave", function()
            hovering = false
            repaintRow(row)
            RepaintGrip()
        end)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", grip, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        row.label = label
        ApplyRoleColor(label, "value")

        row:SetScript("OnDragStart", function(self)
            list.dragged = self
            dragging = true
            repaintRow(self)
            RepaintGrip()
            restingFrameLevel = self:GetFrameLevel()
            local raisedFrameLevel = restingFrameLevel
            for _, sibling in ipairs(list.rows) do
                if sibling ~= self and sibling:IsShown() then
                    raisedFrameLevel = math.max(raisedFrameLevel, sibling:GetFrameLevel())
                end
            end
            self:SetFrameLevel(raisedFrameLevel + 1)
            self:StartMoving()
        end)

        row:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetFrameStrata(list:GetFrameStrata())
            if restingFrameLevel then
                self:SetFrameLevel(restingFrameLevel)
                restingFrameLevel = nil
            end

            local values = control.values
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / UIParent:GetEffectiveScale()

            -- Default to the insertion slot *after* the final item.
            -- The old Module Order-derived logic defaulted to #values, which
            -- made the last visible row the lowest possible target and meant
            -- a dragged item could never be inserted beneath it.
            local target = #values + 1
            for j, other in ipairs(list.rows) do
                if other:IsShown() and other ~= self then
                    local _, centerY = other:GetCenter()
                    if centerY and cursorY > centerY then
                        target = j
                        break
                    end
                end
            end

            local from = self.index
            if from and values[from] then
                local moved = table.remove(values, from)
                if target > from then target = target - 1 end
                target = math.max(1, math.min(#values + 1, target))
                table.insert(values, target, moved)
            end

            list.dragged = nil
            dragging = false
            repaintRow(self)
            RepaintGrip()
            Refresh()
            if onReorder then onReorder(CopyValues(values), control) end
        end)

        return row
    end

    Refresh = function()
        local values = control.values
        -- The list can be measured before its anchored width has resolved on
        -- first opening a Settings page. Never size drag rows to that 1px
        -- placeholder: it clips both labels and grip artwork until a reload.
        local listWidth = list:GetWidth() or 0
        local controlWidth = control:GetWidth() or 0
        local width = math.max(1, listWidth > 1 and listWidth or controlWidth)
        for i, value in ipairs(values) do
            local row = list.rows[i]
            if not row then
                row = CreateRow()
                list.rows[i] = row
            end
            row:StopMovingOrSizing()
            row:ClearAllPoints()
            row:SetParent(list)
            row:SetFrameStrata(list:GetFrameStrata())
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))
            row:SetWidth(width)
            row.index = i
            row.value = value
            row.label:SetText(displayName and displayName(value) or tostring(value))
            row:Show()
        end
        for i = #values + 1, #list.rows do
            local row = list.rows[i]
            row:StopMovingOrSizing()
            row:ClearAllPoints()
            row:Hide()
            row.index = nil
            row.value = nil
        end

        local listHeight = math.max(ROW_HEIGHT, (#values * (ROW_HEIGHT + ROW_GAP)) - ROW_GAP)
        list:SetHeight(listHeight)
        local titleHeight = math.max(1, title:GetStringHeight() or 1)
        control:SetHeight(titleHeight + 5 + listHeight)
    end

    control.Refresh = Refresh
    control.GetValues = function() return CopyValues(control.values) end
    control.SetValues = function(_, values)
        control.values = CopyValues(values)
        Refresh()
    end
    control:SetScript("OnSizeChanged", function(self, width)
        if width and width > 1 then Refresh() end
    end)
    -- Anchors may resolve the inner list *after* the parent content is sized.
    -- A width-only listener ensures all ordered-list instances repaint once
    -- their real space becomes available; height changes do not recurse.
    list:SetScript("OnSizeChanged", function(_, width)
        if width and width > 1 and (not lastListWidth or math.abs(width - lastListWidth) > 0.5) then
            lastListWidth = width
            Refresh()
        end
    end)
    Refresh()
    return control
end

-- Public reusable control surface. Internal helpers/metrics remain private here.
SC.SetDropdownDisplayText = SetDropdownDisplayText
SC.AddMultiDropdown = AddMultiDropdown
SC.AddSingleDropdown = AddSingleDropdown
SC.AddCheckbox = AddCheckbox
SC.AddSteppedSlider = AddSteppedSlider
SC.AddDropdownContent = AddDropdownContent
SC.AddMultiDropdownContent = AddMultiDropdownContent
SC.AddDropdown = AddDropdown
SC.SetDropdownLabelAlignment = SetDropdownLabelAlignment
SC.AddModuleSelectionDropdown = AddModuleSelectionDropdown
SC.AddActionButton = AddActionButton
SC.AddActionButtonContent = AddActionButtonContent
SC.AddRadioSelectorContent = AddRadioSelectorContent
SC.AddTextInputContent = AddTextInputContent
SC.AddHexColorContent = AddHexColorContent
SC.AddDraggableOrderedListContent = AddDraggableOrderedListContent
