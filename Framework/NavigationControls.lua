-- Shared navigation controls. Consumers own page selection, ordering, and layout.
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
        if not button._tbuIndicatorSelectedOnly or button._tbuNavigationSelected == true then
            button._tbuNavigationLine:Show()
        else
            button._tbuNavigationLine:Hide()
        end
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
    button:SetSize(math.max(1, tonumber(options.width) or 1),
        math.max(1, tonumber(options.height) or Styles.GeometryDefaults.navigationItemHeight))

    if kind == "main" then
        AddMainButtonBorder(button)
    elseif options.showIndicator ~= false then
        button._tbuNavigationLine = MakeSlice(button, "OVERLAY", 0)
        button._tbuIndicatorSelectedOnly = options.indicatorSelectedOnly == true
        button._tbuNavigationLine:SetHeight(math.max(1,
            tonumber(options.indicatorHeight) or Styles.GeometryDefaults.subpageIndicatorHeight or 2))
        button._tbuNavigationLine:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 1)
        button._tbuNavigationLine:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 1)
    end

    local labelText = button:CreateFontString(nil, "OVERLAY", options.fontObject or "GameFontHighlightSmall")
    labelText:SetJustifyH("LEFT")
    labelText:SetJustifyV("MIDDLE")
    labelText:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -2)
    labelText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 2)
    labelText:SetWordWrap(true)
    labelText:SetText(tostring(label or ""))
    button.label = labelText

    function button:SetSelected(selected)
        self._tbuNavigationSelected = selected == true
        RefreshNavigationButton(self)
    end
    function button:SetLabel(value)
        self.label:SetText(tostring(value or ""))
        RefreshNavigationButton(self)
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
function NavigationControls:AddSubpageNavigationButton(parent, label, options)
    return CreateNavigationButton(parent, label, options, "subpage")
end
