-- Shared navigation controls. Consumers own page content and selection actions;
-- TreebeardUI supplies reusable navigation layout and visual defaults.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

local NavigationControls = {}
TBU.NavigationControls = NavigationControls

local WHITE = "Interface\\Buttons\\WHITE8X8"
local Styles = TBU.WindowStyles

local function SetColor(region, color)
    region:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function GetLabelWidth(button)
    local label = button and button.label
    if not label or not label.GetStringWidth then return 0 end
    return math.max(0, math.ceil(tonumber(label:GetStringWidth()) or 0))
end

local function SplitUTF8(text)
    local characters = {}
    local index = 1
    while index <= #text do
        local first = text:byte(index)
        local length = first and first >= 240 and 4 or first and first >= 224 and 3
            or first and first >= 192 and 2 or 1
        characters[#characters + 1] = text:sub(index, index + length - 1)
        index = index + length
    end
    return characters
end

local function RefreshSubpageIndicator(button)
    local line = button and button._tbuNavigationLine
    if not line or button._tbuIndicatorWidthMode ~= "content" then return end

    local width = math.min(GetLabelWidth(button), math.max(1, (button:GetWidth() or 1) - 6))
    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 3, 1)
    line:SetWidth(math.max(1, width))
end

local function MakeSlice(button, layer, subLevel)
    local texture = button:CreateTexture(nil, layer, nil, subLevel)
    texture:SetTexture(WHITE)
    return texture
end

local function AddMainButtonBorder(button)
    local fixed = {}
    local bottom = {}

    local topLeft = MakeSlice(button, "BORDER", 1)
    topLeft:SetSize(1, 1)
    topLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    fixed[#fixed + 1] = topLeft

    local top = MakeSlice(button, "BORDER", 1)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", button, "TOPLEFT", 1, 0)
    top:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, 0)
    fixed[#fixed + 1] = top

    local topRight = MakeSlice(button, "BORDER", 1)
    topRight:SetSize(1, 1)
    topRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    fixed[#fixed + 1] = topRight

    button._tbuMainLeftEdge = MakeSlice(button, "BORDER", 1)
    button._tbuMainLeftEdge:SetWidth(1)
    fixed[#fixed + 1] = button._tbuMainLeftEdge

    button._tbuMainFill = MakeSlice(button, "BACKGROUND", 0)

    button._tbuMainRightEdge = MakeSlice(button, "BORDER", 1)
    button._tbuMainRightEdge:SetWidth(1)
    fixed[#fixed + 1] = button._tbuMainRightEdge

    button._tbuMainBottomLeft = MakeSlice(button, "BORDER", 1)
    button._tbuMainBottomLeft:SetWidth(1)
    button._tbuMainBottomLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    bottom[#bottom + 1] = button._tbuMainBottomLeft

    button._tbuMainBottom = MakeSlice(button, "BORDER", 1)
    button._tbuMainBottom:SetHeight(3)
    button._tbuMainBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 0)
    button._tbuMainBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 0)
    bottom[#bottom + 1] = button._tbuMainBottom

    button._tbuMainBottomRight = MakeSlice(button, "BORDER", 1)
    button._tbuMainBottomRight:SetHeight(3)
    button._tbuMainBottomRight:SetWidth(1)
    button._tbuMainBottomRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    bottom[#bottom + 1] = button._tbuMainBottomRight

    button._tbuMainFixedSlices = fixed
    button._tbuMainBottomSlices = bottom
end

local function AddSubpageButtonBorder(button)
    local border = {}
    local top = MakeSlice(button, "BORDER", 1)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    border[#border + 1] = top

    local bottom = MakeSlice(button, "BORDER", 1)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    border[#border + 1] = bottom

    local left = MakeSlice(button, "BORDER", 1)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    border[#border + 1] = left

    local right = MakeSlice(button, "BORDER", 1)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    border[#border + 1] = right

    button._tbuSubpageBorder = border
end

local function PaintMainButton(button, style, borderColor, isHovered)
    local selected = button._tbuNavigationSelected == true
    local bottomHeight = selected
        and (tonumber(button._tbuSelectedBottomHeight) or 6)
        or (tonumber(button._tbuBottomHeight) or 3)

    for _, slice in ipairs(button._tbuMainFixedSlices) do SetColor(slice, borderColor) end
    for _, slice in ipairs(button._tbuMainBottomSlices) do SetColor(slice, borderColor) end

    button._tbuMainFill:ClearAllPoints()
    button._tbuMainFill:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button._tbuMainFill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, bottomHeight)
    local canvasColor
    if selected then
        canvasColor = Styles:GetMainNavigationButtonCanvasColor(button)
    elseif isHovered then
        canvasColor = Styles:GetMainNavigationButtonInactiveHoverCanvasColor(button)
    else
        canvasColor = Styles:GetMainNavigationButtonInactiveCanvasColor(button)
    end
    SetColor(button._tbuMainFill, canvasColor)

    button._tbuMainLeftEdge:ClearAllPoints()
    button._tbuMainLeftEdge:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -1)
    button._tbuMainLeftEdge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, bottomHeight)
    button._tbuMainRightEdge:ClearAllPoints()
    button._tbuMainRightEdge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, -1)
    button._tbuMainRightEdge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, bottomHeight)

    button._tbuMainBottomLeft:SetHeight(bottomHeight)
    button._tbuMainBottom:SetHeight(bottomHeight)
    button._tbuMainBottomRight:SetHeight(bottomHeight)
end

local function RefreshNavigationButton(button)
    if not button or not Styles then return end
    local style = Styles:GetForFrame(button)
    local isSubpage = button._tbuNavigationKind == "subpage"
    local isHovered = button:IsMouseOver()
    local borderColor
    if button._tbuNavigationKind == "main" then
        borderColor = button._tbuNavigationSelected
            and Styles:GetMainNavigationButtonSelectedBorderColor(button)
            or Styles:GetMainNavigationButtonBorderColor(button)
        PaintMainButton(button, style, borderColor, isHovered)
    elseif button._tbuNavigationLine then
        borderColor = Styles:GetSubpageUnderlineColor(button)
        -- Sub-page navigation remains transparent. The selected tab gets its
        -- own underline color; unselected tabs keep the shared neutral line.
        local underlineColor
        if isHovered then
            underlineColor = button._tbuNavigationSelected
                and Styles:GetTextColor("primary", button.label)
                or Styles:GetSubpageHoverTextColor(button)
        elseif button._tbuNavigationSelected then
            underlineColor = Styles:GetSubpageSelectedUnderlineColor(button)
        else
            underlineColor = borderColor
        end
        SetColor(button._tbuNavigationLine, underlineColor)
        RefreshSubpageIndicator(button)
        if not button._tbuIndicatorSelectedOnly or button._tbuNavigationSelected == true then
            button._tbuNavigationLine:Show()
        else
            button._tbuNavigationLine:Hide()
        end
    end
    if button._tbuSubpageBorder then
        local color = Styles:GetControlBorderColor(button)
        for _, edge in ipairs(button._tbuSubpageBorder) do SetColor(edge, color) end
    end
    if button.label then
        local textColor
        if isSubpage then
            if button._tbuNavigationSelected then
                textColor = Styles:GetTextColor("primary", button.label)
            elseif isHovered then
                textColor = Styles:GetSubpageHoverTextColor(button)
            else
                textColor = Styles:GetSubpageTextColor(button)
            end
        else
            textColor = Styles:GetTextColor("primary", button.label)
        end
        button.label:SetTextColor(unpack(textColor))
    end
end

local function CreateNavigationButton(parent, label, options, kind)
    assert(parent and parent.CreateTexture, "navigation button parent required")
    options = type(options) == "table" and options or {}

    local button = TBU:CreateBackdropFrame("Button", parent)
    button._tbuNavigationKind = kind
    button._tbuBottomHeight = math.max(1, tonumber(options.bottomBorderHeight)
        or Styles.GeometryDefaults.mainNavigationBottomBorderHeight or 3)
    button._tbuSelectedBottomHeight = math.max(1, tonumber(options.selectedBottomBorderHeight)
        or Styles.GeometryDefaults.mainNavigationSelectedBottomBorderHeight or 6)
    button._tbuIndicatorWidthMode = options.indicatorWidth
    button._tbuLabelHorizontalInset = 3
    button._tbuOnLabelChanged = options.onLabelChanged
    button:SetSize(math.max(1, tonumber(options.width) or 1),
        math.max(1, tonumber(options.height) or Styles.GeometryDefaults.navigationItemHeight))

    if kind == "main" then
        AddMainButtonBorder(button)
    else
        if options.showBorder == true then AddSubpageButtonBorder(button) end
        if options.showIndicator ~= false then
            button._tbuNavigationLine = MakeSlice(button, "OVERLAY", 0)
            button._tbuIndicatorSelectedOnly = options.indicatorSelectedOnly == true
            button._tbuNavigationLine:SetHeight(math.max(1,
                tonumber(options.indicatorHeight) or Styles.GeometryDefaults.subpageIndicatorHeight or 2))
            if button._tbuIndicatorWidthMode ~= "content" then
                button._tbuNavigationLine:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 1)
                button._tbuNavigationLine:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 1)
            end
        end
    end

    local labelText = button:CreateFontString(nil, "OVERLAY", options.fontObject or "GameFontHighlightSmall")
    labelText:SetJustifyH("LEFT")
    labelText:SetJustifyV("MIDDLE")
    labelText:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -2)
    labelText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 2)
    labelText:SetWordWrap(button._tbuIndicatorWidthMode ~= "content")
    labelText:SetText(tostring(label or ""))
    button.label = labelText

    function button:SetSelected(selected)
        self._tbuNavigationSelected = selected == true
        RefreshNavigationButton(self)
    end
    function button:SetLabel(value)
        self._tbuFullLabelText = tostring(value or "")
        self.label:SetText(self._tbuFullLabelText)
        RefreshNavigationButton(self)
        if type(self._tbuOnLabelChanged) == "function" then
            self._tbuOnLabelChanged(self)
        end
    end
    function button:GetLabelWidth()
        return GetLabelWidth(self)
    end
    function button:GetContentWidth()
        return GetLabelWidth(self) + (self._tbuLabelHorizontalInset or 0) * 2
    end
    function button:RefreshStyle()
        RefreshNavigationButton(self)
    end

    if type(options.onClick) == "function" then
        button:SetScript("OnClick", options.onClick)
    end
    button:HookScript("OnEnter", RefreshNavigationButton)
    button:HookScript("OnLeave", RefreshNavigationButton)
    button:SetScript("OnSizeChanged", RefreshNavigationButton)
    Styles:RegisterVisual(button, RefreshNavigationButton)
    button:SetSelected(options.selected == true)
    return button
end

-- Creates the outlined primary tab with a thicker selected lower edge.
-- Page selection and placement remain the consumer's responsibility.
function NavigationControls:AddMainNavigationButton(parent, label, options)
    return CreateNavigationButton(parent, label, options, "main")
end

-- Creates a canvas-free sub-page tab. Set showIndicator=false for navigation
-- that uses the same text states without an underline, such as a sidebar.
-- Set showBorder=true to outline the button without adding a canvas fill.
function NavigationControls:AddSubpageNavigationButton(parent, label, options)
    return CreateNavigationButton(parent, label, options, "subpage")
end

-- Lays out horizontal main or sub-page tabs using shared navigation spacing.
-- Main navigation gets a top inset by default; sub-page navigation uses only
-- the shared horizontal inset. Returns the height needed for the navigation row.
function NavigationControls:LayoutHorizontalButtons(parent, buttons, options)
    assert(parent and parent.GetWidth, "horizontal navigation parent required")
    buttons = type(buttons) == "table" and buttons or {}
    options = type(options) == "table" and options or {}
    if #buttons == 0 then return 0 end

    local geometry = Styles.GeometryDefaults or {}
    local edgeInset = math.max(0, tonumber(options.edgeInset)
        or tonumber(geometry.navigationEdgeInset) or 5)
    local gap = math.max(0, tonumber(options.gap)
        or tonumber(geometry.navigationGap) or 10)
    local height = math.max(1, tonumber(options.height)
        or tonumber(geometry.navigationItemHeight) or 28)
    local topInset = options.topInset
    if topInset == nil then
        topInset = options.kind == "main" and edgeInset or 0
    else
        topInset = math.max(0, tonumber(topInset) or 0)
    end
    local bottomInset = math.max(0, tonumber(options.bottomInset) or 0)
    local count = #buttons
    local availableWidth = math.max(count,
        (tonumber(parent:GetWidth()) or 0) - edgeInset * 2 - gap * (count - 1))
    local buttonWidth = availableWidth / count

    for index, button in ipairs(buttons) do
        button:SetSize(buttonWidth, height)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", parent, "TOPLEFT",
            edgeInset + (index - 1) * (buttonWidth + gap), -topInset)
    end

    return topInset + height + bottomInset
end

-- Creates a content-width vertical sub-page navigation rail. TreebeardUI owns
-- its button placement, spacing, padding, selected-only text underline, and
-- width measurement; consumers provide labels and page-selection behavior.
function NavigationControls:CreateVerticalSubpageNavigation(parent, items, options)
    assert(parent and parent.CreateTexture, "vertical sub-page navigation parent required")
    options = type(options) == "table" and options or {}
    items = type(items) == "table" and items or {}

    local layout = TBU.SettingsLayout
    local metrics = layout and layout.Metrics or {}
    local padding = math.max(0, tonumber(metrics.SECTION_PADDING) or 5)
    local gap = math.max(0, tonumber(metrics.CONTENT_GAP) or 2)
    local buttonHeight = math.max(1, tonumber(Styles.GeometryDefaults.navigationItemHeight) or 28)
    local minimumWidth = 15

    local navigation = CreateFrame("Frame", nil, parent)
    navigation.storageOwner = options.storageOwner or parent.storageOwner
    navigation.buttons = {}
    navigation.selectedIndex = nil
    navigation.maxWidth = tonumber(options.maxWidth)
    navigation:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    navigation:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    navigation:SetWidth(minimumWidth)

    local measureLabel = navigation:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measureLabel:SetAlpha(0)
    measureLabel:SetWordWrap(false)
    measureLabel:SetWidth(100000)
    navigation.measureLabel = measureLabel

    local function MeasureText(button, text)
        local fontObject = button.label:GetFontObject()
        if fontObject then measureLabel:SetFontObject(fontObject) end
        measureLabel:SetText(text or "")
        return math.max(0, tonumber(measureLabel:GetStringWidth()) or 0)
    end

    local function SetDisplayedLabel(button, fullText, maxTextWidth)
        if MeasureText(button, fullText) <= maxTextWidth then
            button.label:SetText(fullText)
            return
        end
        local characters = SplitUTF8(fullText)
        local low, high, best = 0, #characters, "…"
        while low <= high do
            local middle = math.floor((low + high) / 2)
            local candidate = table.concat(characters, "", 1, middle) .. "…"
            if MeasureText(button, candidate) <= maxTextWidth then
                best = candidate
                low = middle + 1
            else
                high = middle - 1
            end
        end
        button.label:SetText(best)
    end

    local separator = navigation:CreateTexture(nil, "BORDER")
    separator:SetTexture(WHITE)
    separator:SetWidth(1)
    separator:SetPoint("TOPRIGHT", navigation, "TOPRIGHT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", navigation, "BOTTOMRIGHT", 0, 0)
    separator.storageOwner = navigation.storageOwner
    local function RepaintSeparator(target)
        SetColor(target, Styles:GetSubpageUnderlineColor(target))
    end
    RepaintSeparator(separator)
    Styles:RegisterVisual(separator, RepaintSeparator)
    navigation.separator = separator

    local resizing = false
    local function RefreshWidth()
        if resizing then return end
        resizing = true
        local widestContent = 0
        for _, button in ipairs(navigation.buttons) do
            widestContent = math.max(widestContent, MeasureText(button, button._tbuFullLabelText or "")
                + (button._tbuLabelHorizontalInset or 0) * 2)
        end
        local width = math.max(minimumWidth, math.ceil(widestContent + padding * 2))
        if navigation.preferredWidth then
            width = math.max(width, navigation.preferredWidth)
        end
        if navigation.maxWidth then width = math.min(width, math.max(minimumWidth, navigation.maxWidth)) end
        if math.abs((navigation:GetWidth() or 0) - width) > 0.001 then
            navigation:SetWidth(width)
        end
        local availableTextWidth = math.max(1, width - padding * 2 - 6)
        for _, button in ipairs(navigation.buttons) do
            SetDisplayedLabel(button, button._tbuFullLabelText or "", availableTextWidth)
            RefreshNavigationButton(button)
        end
        resizing = false
    end

    function navigation:SetSelected(index)
        if index == nil then
            self.selectedIndex = nil
            for _, button in ipairs(self.buttons) do button:SetSelected(false) end
            return true
        end
        index = tonumber(index)
        if not index or not self.buttons[index] then return false end
        self.selectedIndex = index
        for buttonIndex, button in ipairs(self.buttons) do
            button:SetSelected(buttonIndex == index)
        end
        return true
    end

    function navigation:GetSelectedIndex()
        return self.selectedIndex
    end

    function navigation:GetButton(index)
        return self.buttons[index]
    end

    function navigation:SetLabel(index, label)
        local button = self.buttons[index]
        if not button then return false end
        button:SetLabel(label)
        return true
    end

    function navigation:SetMaxWidth(width)
        width = tonumber(width)
        self.maxWidth = width and math.max(minimumWidth, width) or nil
        RefreshWidth()
        return true
    end

    function navigation:SetDisplayWidth(width)
        width = tonumber(width)
        self.preferredWidth = width and math.max(minimumWidth, width) or nil
        RefreshWidth()
        return true
    end

    for index, item in ipairs(items) do
        local label = type(item) == "table" and item.label or item
        local selectedIndex = index
        local showBorder = options.showBorder == true
        if type(item) == "table" and item.showBorder ~= nil then
            showBorder = item.showBorder == true
        end
        local button = NavigationControls:AddSubpageNavigationButton(navigation, label, {
            width=minimumWidth,
            height=buttonHeight,
            indicatorWidth="content",
            indicatorSelectedOnly=true,
            showBorder=showBorder,
            selected=false,
            onLabelChanged=RefreshWidth,
            onClick=function()
                navigation:SetSelected(selectedIndex)
                if type(options.onSelect) == "function" then
                    options.onSelect(selectedIndex, item, navigation.buttons[selectedIndex])
                end
            end,
        })
        button.storageOwner = navigation.storageOwner
        button._tbuFullLabelText = tostring(label or "")
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", navigation, "TOPLEFT", padding,
            -padding - (index - 1) * (buttonHeight + gap))
        button:SetPoint("TOPRIGHT", navigation, "TOPRIGHT", -padding,
            -padding - (index - 1) * (buttonHeight + gap))
        navigation.buttons[index] = button
    end

    RefreshWidth()
    if #navigation.buttons > 0 then
        navigation:SetSelected(math.max(1, math.min(#navigation.buttons,
            math.floor(tonumber(options.selectedIndex) or 1))))
    end
    return navigation
end
