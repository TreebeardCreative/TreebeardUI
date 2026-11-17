-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

TBU.SettingsLayout = TBU.SettingsLayout or {}
local L = TBU.SettingsLayout

local DEFAULT_GAP = TBU.Constants.Layout.SETTINGS_GAP
local DEFAULT_PADDING = TBU.Constants.Layout.SETTINGS_PADDING

-- One shared geometry grid per layout pass. All descendants of a frame use
-- the same physical-pixel size, rather than rounding each border independently.
-- The right/bottom gutter absorbs any remainder of the available dimensions.
local function LayoutPixel(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    if type(GetPhysicalScreenSize) == "function" and UIParent and UIParent.GetHeight then
        local ok, _, physicalHeight = pcall(GetPhysicalScreenSize)
        local uiHeight = UIParent:GetHeight()
        local uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if ok and physicalHeight and physicalHeight > 0 and uiHeight and uiHeight > 0
            and uiScale and uiScale > 0 then
            return (uiHeight * uiScale / physicalHeight) / scale
        end
    end
    return 1 / scale
end

local function FloorGrid(value, pixel)
    return math.floor(math.max(0, value) / pixel + 0.000001) * pixel
end

local function CeilGrid(value, pixel)
    return math.ceil(math.max(0, value) / pixel - 0.000001) * pixel
end

local function SetAnchorsIfChanged(frame, anchors)
    local saved = frame._tbuLayoutAnchorSpec
    local same = saved and #saved == #anchors
    if same then
        for i, anchor in ipairs(anchors) do
            local old = saved[i]
            if old[1] ~= anchor[1] or old[2] ~= anchor[2] or old[3] ~= anchor[3]
                or math.abs(old[4] - anchor[4]) > 0.0001
                or math.abs(old[5] - anchor[5]) > 0.0001 then
                same = false
                break
            end
        end
    end
    if same then return false end
    frame:ClearAllPoints()
    local copy = {}
    for i, anchor in ipairs(anchors) do
        copy[i] = {anchor[1], anchor[2], anchor[3], anchor[4], anchor[5]}
        frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    end
    frame._tbuLayoutAnchorSpec = copy
    return true
end

local function SetWidthIfChanged(frame, width)
    if frame and math.abs((frame:GetWidth() or 0) - width) > 0.0001 then frame:SetWidth(width) end
end

local function SetHeightIfChanged(frame, height)
    if frame and math.abs((frame:GetHeight() or 0) - height) > 0.0001 then frame:SetHeight(height) end
end


-- Shared Settings geometry. Ordinary Settings UI must consume these values
-- instead of inventing section-local padding, gaps, or header spacing.
L.Metrics = {
    SECTION_PADDING = 5,
    SECTION_GAP = 2,
    PAGE_SECTION_GAP = 6,
    CONTENT_GAP = 2,
    SECTION_BODY_GAP = 14,
    SECTION_BOTTOM_PADDING = 14,
    ROW_GAP = 2,
    COLUMN_GAP = 4,
    -- Rows grow from their measured content. This is the symmetric default
    -- vertical inset on each Row; layout applies it above and below children.
    ROW_MIN_HEIGHT = 1,
    ROW_VERTICAL_PADDING = 1,
    -- Host-region inset is separate from the internal Row breathing room.
    ROW_REGION_INSET_Y = 2,
    SECTION_HEADER_HEIGHT = 30,
    DESCRIPTION_GAP = 2,
    CONTENT_HEADER_HEIGHT = 20,
    CONTENT_BOTTOM_PADDING = 10,
    -- Shared native-slider geometry; label region matches dropdown Content.
    SLIDER_CONTROL_HEIGHT = 26,
    SLIDER_HIT_HEIGHT = 18,
    SLIDER_TRACK_HEIGHT = 5,
    SLIDER_THUMB_SIZE = 13,
    SLIDER_ENDPOINT_GAP = 9,
    COLOR_CONTROL_GAP = 3,
    COLOR_EDIT_HEIGHT = 24,
    SELECTION_CONTENT_BOTTOM_PADDING = 3,
}

-- Shared vertical-flow primitives. A Section is the page-level vertical
-- container; Rows/Columns can use the same registration contract as the
-- architecture is migrated away from section-local coordinates.
-- Every layout container owns one child registry. Flow is a property of a child,
-- not a second child list. This keeps Section/Box/Row/Column on one contract.
local function RegisterChild(parent, child, opts)
    if not parent or not child then return child end
    opts = opts or {}
    parent.layoutChildren = parent.layoutChildren or {}
    child.layoutParent = parent
    child.layoutRole = opts.role or child.layoutRole or "content"
    child.layoutGapBefore = opts.gapBefore
    -- Registered children flow in creation order by default. Callers can
    -- reserve a child outside the flow with flow=false.
    child.layoutParticipatesInFlow = opts.flow ~= false
    table.insert(parent.layoutChildren, child)
    if child.layoutParticipatesInFlow and type(parent._tbuRequestLayout) == "function" then
        parent:_tbuRequestLayout()
    end
    return child
end

function L:RegisterChild(parent, child, opts)
    return RegisterChild(parent, child, opts)
end

function L:RegisterFlowChild(parent, child, role, gapBefore)
    return RegisterChild(parent, child, { role = role, gapBefore = gapBefore, flow = true })
end

-- Promote an already-registered child into the shared flow without inserting it
-- a second time. This is useful while legacy Settings content is migrated a
-- few structural groups at a time.
function L:SetFlowChild(parent, child, role, gapBefore)
    if not parent or not child then return child end
    parent.layoutChildren = parent.layoutChildren or {}
    local found = false
    for _, existing in ipairs(parent.layoutChildren) do
        if existing == child then found = true break end
    end
    if not found then
        table.insert(parent.layoutChildren, child)
    end
    child.layoutParent = parent
    child.layoutRole = role or child.layoutRole or "content"
    child.layoutGapBefore = gapBefore
    child.layoutParticipatesInFlow = true
    if type(parent._tbuRequestLayout) == "function" then
        parent:_tbuRequestLayout()
    end
    return child
end

-- One-pixel inner edges anchored directly to their owner's final geometry.
-- Unlike 1px SetBackdrop edge rendering, these do not rely on the backdrop
-- border's pixel-snapping/rebuild path after a Section is measured or resized.
-- Edges deliberately stay INSIDE the frame, avoiding scroll-parent clipping.
function L:CreateInnerBorder(frame)
    if frame._tbuInnerBorder then return frame._tbuInnerBorder end
    local parts = {}
    -- One physical pixel at the frame's effective scale; fractional WoW UI
    -- coordinates otherwise round differently during scroll and resize.
    local effectiveScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local pixel = (effectiveScale and effectiveScale > 0) and (uiScale / effectiveScale) or 1
    if type(GetPhysicalScreenSize) == "function" and UIParent and UIParent.GetHeight then
        local ok, _, screenHeight = pcall(GetPhysicalScreenSize)
        local uiHeight = UIParent:GetHeight()
        if ok and screenHeight and screenHeight > 0 and uiHeight and uiHeight > 0 then
            pixel = pixel * uiHeight / screenHeight
        end
    end
    if pixel <= 0 then pixel = 1 end
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        local borderColor = TBU.WindowStyles and TBU.WindowStyles:GetBorderColor(frame)
        if borderColor then edge:SetVertexColor(unpack(borderColor)) end
        if TBU.WindowStyles and TBU.WindowStyles.RegisterVisual then
            TBU.WindowStyles:RegisterVisual(edge, function(target)
                target:SetVertexColor(unpack(TBU.WindowStyles:GetBorderColor(target)))
            end)
        end
        -- This edge already has a physical-pixel width. Leave texture sampling
        -- unsnapped so the client does not independently sharpen each edge as
        -- a content viewport changes size.
        if type(edge.SetSnapToPixelGrid) == "function" then
            edge:SetSnapToPixelGrid(false)
        end
        if type(edge.SetTexelSnappingBias) == "function" then
            edge:SetTexelSnappingBias(0)
        end
        if side == "top" then
            edge:SetHeight(pixel)
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", pixel, -pixel)
            edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pixel, -pixel)
        elseif side == "bottom" then
            edge:SetHeight(pixel)
            edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pixel, pixel)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pixel, pixel)
        elseif side == "left" then
            edge:SetWidth(pixel)
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", pixel, -pixel)
            edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pixel, pixel)
        else
            edge:SetWidth(pixel)
            edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pixel, -pixel)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pixel, pixel)
        end
        parts[#parts+1] = edge
    end
    frame._tbuInnerBorder = parts
    return parts
end

function L:SetInnerBorderColor(frame, color)
    local parts = self:CreateInnerBorder(frame)
    local borderColor = TBU.WindowStyles and TBU.WindowStyles.GetBorderColor
        and TBU.WindowStyles:GetBorderColor(frame) or color
    if type(borderColor) ~= "table" then return end
    for _, edge in ipairs(parts) do edge:SetVertexColor(unpack(borderColor)) end
end

-- Disable the client's texture-edge sharpening under a framework-owned page.
-- This pass also catches backdrop/template textures the library did not create
-- directly. Run it after layout and again when a viewport changes, since a
-- later texture/style update can restore its default sampling flags.
local SHARPENED_REGION_TYPES = {Texture=true, MaskTexture=true, Line=true}
function L:DisableTextureSnapping(root)
    if not root or type(root.GetRegions) ~= "function" then return 0 end
    local pending, visited = {root}, {}
    local changed = 0
    while #pending > 0 do
        local frame = table.remove(pending)
        if not visited[frame] then
            visited[frame] = true
            if type(frame.GetRegions) == "function" then
                for _, region in ipairs({frame:GetRegions()}) do
                    local kind = type(region.GetObjectType) == "function" and region:GetObjectType()
                    if SHARPENED_REGION_TYPES[kind] then
                        local didChange = false
                        if type(region.SetSnapToPixelGrid) == "function" then
                            local snapping = type(region.IsSnappingToPixelGrid) == "function"
                                and region:IsSnappingToPixelGrid()
                            if snapping ~= false then
                                region:SetSnapToPixelGrid(false)
                                didChange = true
                            end
                        end
                        if type(region.SetTexelSnappingBias) == "function" then
                            local bias = type(region.GetTexelSnappingBias) == "function"
                                and region:GetTexelSnappingBias()
                            if bias ~= 0 then
                                region:SetTexelSnappingBias(0)
                                didChange = true
                            end
                        end
                        if didChange then changed = changed + 1 end
                    end
                end
            end
            if type(frame.GetChildren) == "function" then
                for _, child in ipairs({frame:GetChildren()}) do pending[#pending + 1] = child end
            end
        end
    end
    return changed
end

local function NormalizeBorderInsets(value, fallback)
    if type(value) == "number" then
        local amount = math.max(0, value)
        return {left=amount, right=amount, top=amount, bottom=amount}
    end
    value = type(value) == "table" and value or {}
    local horizontal = math.max(0, tonumber(value.horizontal or value.x) or fallback)
    local vertical = math.max(0, tonumber(value.vertical or value.y) or fallback)
    return {
        left=math.max(0, tonumber(value.left) or horizontal),
        right=math.max(0, tonumber(value.right) or horizontal),
        top=math.max(0, tonumber(value.top) or vertical),
        bottom=math.max(0, tonumber(value.bottom) or vertical),
    }
end

function L:Section(parent, id, opts)
    opts = opts or {}
    local section = TBU:CreateBackdropFrame("Frame", parent)
    section.layoutKind = "section"
    section.layoutId = id
    section.layoutChildren = {}
    section.layoutPadding = opts.padding
    if section.layoutPadding == nil then section.layoutPadding = L.Metrics.SECTION_PADDING end
    section.layoutGap = opts.gap
    if section.layoutGap == nil then section.layoutGap = L.Metrics.SECTION_GAP end

    -- Optional per-section border geometry. Legacy sections keep their current
    -- spacing; a selected border can declare its own edge width and safe inset.
    local borderGeometry = type(opts.borderGeometry) == "table" and opts.borderGeometry or nil
    if borderGeometry then
        local edgeSize = math.max(0, tonumber(borderGeometry.edgeSize) or 1)
        local contentInsets = NormalizeBorderInsets(borderGeometry.contentInsets, edgeSize)
        section.layoutBorderInsets = contentInsets
        section.layoutBorderGeometry = { edgeSize=edgeSize, contentInsets=contentInsets }
    end

    -- Section is structural. Border/background are presentation choices only.
    if opts.border ~= false then
        -- Native WHITE8X8 backdrop border. Section content/layout are unchanged.
        section:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = section.layoutBorderGeometry and section.layoutBorderGeometry.edgeSize or 1,
        })
        local borderStyle = TBU.WindowStyles and TBU.WindowStyles:GetForFrame(section)
        local sectionBorder = TBU.WindowStyles:GetSectionBorderColor(borderStyle)
        local sectionFill = TBU.WindowStyles:GetSectionSurfaceColor(borderStyle)
        if opts.backgroundAlpha ~= nil then
            sectionFill = {sectionFill[1], sectionFill[2], sectionFill[3], opts.backgroundAlpha}
        end
        section:SetBackdropColor(unpack(sectionFill))
        section:SetBackdropBorderColor(unpack(sectionBorder))
        if TBU.WindowStyles and TBU.WindowStyles.RegisterVisual then
            TBU.WindowStyles:RegisterVisual(section, function(target)
                local style = TBU.WindowStyles:GetForFrame(target)
                local fill = TBU.WindowStyles:GetSectionSurfaceColor(style)
                if opts.backgroundAlpha ~= nil then
                    fill = {fill[1], fill[2], fill[3], opts.backgroundAlpha}
                end
                target:SetBackdropColor(unpack(fill))
                target:SetBackdropBorderColor(unpack(TBU.WindowStyles:GetSectionBorderColor(style)))
            end)
        end
    end

    self:PrepareOrdinarySection(section)
    if parent and (parent.layoutKind or type(parent._tbuPageSectionCreated) ~= "function") then
        RegisterChild(parent, section, { role = "section", flow = opts.flow ~= false, gapBefore = opts.gapBefore })
    end
    -- A Section created directly under an embedded page's content frame is a
    -- top-level page Section. The page host owns its ordered reflow list; a
    -- nested Section has a different parent and stays in its parent's flow.
    if parent and type(parent._tbuPageSectionCreated) == "function" then
        parent:_tbuPageSectionCreated(section)
    end
    return section
end

-- Create a normal layout Section with a TreebeardUI BorderStyles treatment.
-- Section spacing remains governed by shared metrics. A small border-safe
-- inset keeps content clear of decorative corners, matching the rounded
-- samples in TreebeardSandbox without the old edge-size-sized spacing.
function L:BorderedSection(parent, id, opts)
    opts = opts or {}
    local treatment = opts.treatment or "square"
    local edgeSize = tonumber(opts.edgeSize)
    if edgeSize == nil then
        edgeSize = treatment == "rounded" and 16
            or treatment == "toast" and 12
            or treatment == "nineSlice" and 16 or 1
    end
    edgeSize = math.max(1, edgeSize)
    local contentInsets = opts.contentInsets
    if contentInsets == nil then
        contentInsets = {left=5, right=5, top=5, bottom=10}
    end

    local section = self:Section(parent, id, {
        border = false,
        padding = opts.padding,
        gap = opts.gap,
        borderGeometry = {
            edgeSize = edgeSize,
            contentInsets = contentInsets,
        },
    })
    local border = TBU.BorderStyles:Create(section, {
        treatment = treatment,
        edgeSize = edgeSize,
        borderColor = opts.borderColor,
        opacity = opts.borderOpacity,
        contentInsets = contentInsets,
        canvasColor = opts.canvasColor,
        canvasOpacity = opts.canvasOpacity,
    })
    -- BorderStyles returns an independently sized surface. A section-level
    -- treatment follows the Section bounds while content continues through
    -- the ordinary SettingsLayout flow.
    border:SetAllPoints(section)
    section.customBorder = border
    return section, border
end

function L:MainHeader(section, text, opts)
    opts = opts or {}
    local header = TBU:CreateBackdropFrame("Frame", section)
    local minHeight = tonumber(opts.height) or L.Metrics.SECTION_HEADER_HEIGHT
    local paddingX = math.max(0, tonumber(opts.paddingX) or 8)
    local paddingY = math.max(0, tonumber(opts.paddingY) or 4)
    header:SetHeight(minHeight)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    -- Source the neutral section-title fill from the SAME palette as window
    -- borders. Without an explicit color, WoW draws this as solid white.
    local style = TBU.WindowStyles and TBU.WindowStyles:GetForFrame(header)
    local border = style.allEverythingTestVariable
    header:SetBackdropColor(unpack(style.allEverythingTestVariable))
    if TBU.WindowStyles and TBU.WindowStyles.RegisterVisual then
        TBU.WindowStyles:RegisterVisual(header, function(target)
            local style = TBU.WindowStyles:GetForFrame(target)
            target:SetBackdropColor(unpack(style.allEverythingTestVariable))
            if target.label then
                target.label:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("primary", target.label)))
            end
        end)
    end

    local label = header:CreateFontString(nil, "ARTWORK", opts.fontObject or "GameFontNormal")
    label:SetPoint("TOPLEFT", header, "TOPLEFT", paddingX, -paddingY)
    label:SetPoint("TOPRIGHT", header, "TOPRIGHT", -paddingX, -paddingY)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("TOP")
    label:SetWordWrap(opts.wrap ~= false)
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(opts.wrap ~= false) end
    label:SetText(text or "")
    label:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("header", label)))
    TBU.WindowStyles:RegisterVisual(label, function(target)
        target:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("header", target)))
    end)
    header.label = label

    local function FitHeader()
        local width = tonumber(header:GetWidth()) or 0
        if width <= paddingX * 2 then return end
        SetWidthIfChanged(label, width - (paddingX * 2))
        local textHeight = math.ceil(label:GetStringHeight() or 0)
        local targetHeight = math.max(minHeight, textHeight + (paddingY * 2))
        if math.abs((header:GetHeight() or 0) - targetHeight) > 0.5 then
            header:SetHeight(targetHeight)
        end
    end
    header:HookScript("OnSizeChanged", FitHeader)
    FitHeader()

    RegisterChild(section, header, { role = "main-header", gapBefore = 0, flow = true })
    return header, label
end

local function CreateLayoutText(section, text, opts, textRole, defaultFont, layoutRole)
    opts = opts or {}
    local textString = section:CreateFontString(nil, "ARTWORK", opts.fontObject or defaultFont)
    -- Text added to a layout parent fills its layout width and wraps by
    -- default. Consumers can pass wrap=false for fixed-width text.
    textString.layoutWrap = opts.wrap ~= false
    textString:SetJustifyH(opts.justifyH or "CENTER")
    textString:SetJustifyV("TOP")
    textString:SetWordWrap(opts.wrap ~= false)
    if textString.SetNonSpaceWrap then textString:SetNonSpaceWrap(opts.wrap ~= false) end
    textString:SetText(text or "")
    if TBU.WindowStyles then
        local function repaintText(target)
            target:SetTextColor(unpack(TBU.WindowStyles:GetTextColor(textRole, target)))
        end
        TBU.WindowStyles:RegisterVisual(textString, repaintText)
        repaintText(textString)
    end
    local gapBefore = opts.gapBefore
    if gapBefore == nil then gapBefore = L.Metrics.CONTENT_GAP end
    RegisterChild(section, textString, { role = layoutRole, gapBefore = gapBefore, flow = true })
    return textString
end

-- A lightweight section/area label with a text-width underline. The text and
-- line remain independent style choices; consumers can supply a role and a
-- style-aware color getter without creating another canvas or border layer.
function L:TextHeader(section, text, opts)
    opts = opts or {}
    local styles = TBU.WindowStyles
    local justifyH = opts.justifyH or "LEFT"
    local underlineGap = math.max(0, tonumber(opts.underlineGap) or 2)
    local underlineHeight = math.max(1, tonumber(opts.underlineHeight) or 2)
    local textString = CreateLayoutText(section, text, {
        justifyH = justifyH,
        wrap = opts.wrap,
        gapBefore = opts.gapBefore,
        fontObject = opts.fontObject,
    }, opts.textRole or "header", opts.fontObject or "GameFontHighlightSmall",
        opts.role or "text-header")
    textString.layoutBottomPadding = underlineGap + underlineHeight

    local underline = styles and styles:CreateFlatTexture(section, "BORDER",
        (type(opts.underlineColor) == "function" and opts.underlineColor(textString))
            or styles:GetSeparatorColor(textString))
    if underline then
        underline:SetHeight(underlineHeight)
        local function PositionUnderline()
            local availableWidth = math.max(1, textString:GetWidth() or 1)
            local measuredWidth = tonumber(textString:GetStringWidth()) or availableWidth
            local width = math.max(1, math.min(availableWidth, measuredWidth))
            local xOffset = 0
            if justifyH == "CENTER" then
                xOffset = (availableWidth - width) / 2
            elseif justifyH == "RIGHT" then
                xOffset = availableWidth - width
            end
            underline:ClearAllPoints()
            underline:SetPoint("TOPLEFT", textString, "BOTTOMLEFT", xOffset, -underlineGap)
            underline:SetWidth(width)
        end
        PositionUnderline()
        if section.HookScript then section:HookScript("OnSizeChanged", PositionUnderline) end
        if styles.RegisterVisual then
            styles:RegisterVisual(underline, function(target)
                local color = type(opts.underlineColor) == "function"
                    and opts.underlineColor(textString) or styles:GetSeparatorColor(textString)
                target:SetVertexColor(unpack(color))
            end)
        end
    end
    return textString, underline
end

-- Area headers separate related content with a little more breathing room than
-- ordinary text headers. Keep both extra spacings overridable for consumers.
function L:AreaHeader(section, text, opts)
    opts = opts or {}
    local headerOpts = {}
    for key, value in pairs(opts) do headerOpts[key] = value end

    local extraTop = math.max(0, tonumber(opts.extraTopSpacing) or 4)
    local extraBottom = math.max(0, tonumber(opts.extraBottomSpacing) or 4)
    local gapBefore = tonumber(opts.gapBefore)
    if gapBefore == nil then gapBefore = self.Metrics.CONTENT_GAP end
    headerOpts.gapBefore = math.max(0, gapBefore)
    headerOpts.extraTopSpacing = nil
    headerOpts.extraBottomSpacing = nil
    headerOpts.textRole = opts.textRole or "textInteractionAccentColor"
    headerOpts.underlineColor = opts.underlineColor or function(frame)
        return TBU.WindowStyles:GetTextColor("textNeutralAccentColor", frame)
    end

    local textString, underline = self:TextHeader(section, text, headerOpts)
    if textString then
        textString.layoutTopPadding = (textString.layoutTopPadding or 0) + extraTop
        textString.layoutBottomPadding = (textString.layoutBottomPadding or 0) + extraBottom
    end
    return textString, underline
end

function L:Note(section, text, opts)
    return CreateLayoutText(section, text, opts, "notes", "GameFontDisableSmall", "note")
end

-- Ordinary paragraph/text content. Note and Text are distinct helper names,
-- but their current style color resolves to the shared allEverythingTestVariable field.
function L:Text(section, text, opts)
    return CreateLayoutText(section, text, opts, "primary", "GameFontHighlightSmall", "content")
end

function L:ReflowSection(section)
    if not section or not section.layoutChildren then return 1 end
    local pad = section.layoutPadding or L.Metrics.SECTION_PADDING
    local sectionGap = section.layoutGap or L.Metrics.SECTION_GAP
    local borderInsets = section.layoutBorderInsets or {left=0, right=0, top=0, bottom=0}
    local contentLeft = pad + borderInsets.left
    local contentRight = pad + borderInsets.right
    local contentTop = pad + borderInsets.top
    local contentBottom = pad + borderInsets.bottom
    local headerInsets = section.layoutBorderGeometry and borderInsets
        or {left=1, right=1, top=1, bottom=1}
    local previous
    local firstFlowChild
    for _, child in ipairs(section.layoutChildren) do
        if child.layoutParticipatesInFlow and child:IsShown() then
            firstFlowChild = child
            break
        end
    end
    -- Main headers are anchored to the Section's top edge. Do not count the
    -- Section's top inset as blank space before that header; place that inset
    -- after the header, before the first body item, and retain one bottom inset.
    local total
    if firstFlowChild and firstFlowChild.layoutRole == "main-header" then
        total = section.layoutBorderGeometry and headerInsets.top or 0
    else
        total = contentTop
    end

    for _, child in ipairs(section.layoutChildren) do
        if child.layoutParticipatesInFlow and child:IsShown() then
            if child.layoutKind == "section" then
                SetWidthIfChanged(child, math.max(1, section:GetWidth() - contentLeft - contentRight))
                self:ReflowSection(child)
            elseif child.layoutKind == "row" then
                self:LayoutRow(child, math.max(1, section:GetWidth() - contentLeft - contentRight))
            elseif child.layoutKind == "container" or child.layoutKind == "column" then
                self:ReflowFrame(child, {
                    width=math.max(1, section:GetWidth() - contentLeft - contentRight),
                    autoSize=true,
                })
            end
            local topPadding = math.max(0, tonumber(child.layoutTopPadding) or 0)
            local gap = previous and (child.layoutGapBefore or sectionGap) or 0
            if previous and previous.layoutRole == "main-header" then
                gap = math.max(gap, pad)
            end
            local anchors
            if previous then
                gap = gap + topPadding
                -- Bottom padding is measured as part of the preceding child's
                -- flow height. Include it in the next child's anchor offset as
                -- well, so helpers such as AreaHeader create visible spacing,
                -- not only extra section height.
                local anchorGap = gap + math.max(0,
                    tonumber(previous.layoutBottomPadding) or 0)
                local xInset = (previous.layoutRole == "main-header")
                    and (contentLeft - headerInsets.left) or 0
                anchors = {
                    {"TOPLEFT", previous, "BOTTOMLEFT", xInset, -anchorGap},
                    {"RIGHT", section, "RIGHT", -contentRight, 0},
                }
                total = total + gap
            else
                -- Main headers span the section border; ordinary flow content
                -- uses the shared section inset.
                if child.layoutRole == "main-header" then
                    anchors = {
                        {"TOPLEFT", section, "TOPLEFT", headerInsets.left, -headerInsets.top},
                        {"RIGHT", section, "RIGHT", -headerInsets.right, 0},
                    }
                else
                    anchors = {
                        {"TOPLEFT", section, "TOPLEFT", contentLeft, -(contentTop + topPadding)},
                        {"RIGHT", section, "RIGHT", -contentRight, 0},
                    }
                end
                total = total + topPadding
            end

            SetAnchorsIfChanged(child, anchors)

            local h = (child.GetHeight and child:GetHeight()) or 0
            if child.GetObjectType and child:GetObjectType() == "FontString" then
                h = math.max(h or 0, child:GetStringHeight() or 0)
            end
            h = math.max(1, h or 0) + math.max(0, tonumber(child.layoutBottomPadding) or 0)
            total = total + h
            previous = child
        end
    end

    -- Round the measured outer rectangle upward on the physical-pixel grid.
    -- Each child height and gap above uses that same grid, so dynamic growth
    -- cannot leave the section's bottom edge between screen pixels.
    SetHeightIfChanged(section, math.max(1, total + contentBottom))
    return section:GetHeight()
end

function L:PrepareOrdinarySection(section)
    -- Section frames deliberately start geometry-free. StackSections owns width
    -- and placement; the section's content flow must eventually own height.
    section:ClearAllPoints()
    section:SetHeight(1)
    section._tbuOrdinarySection = true
end

local function Node(parent, kind, id, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f.layoutKind = kind
    f.layoutId = id
    f.layoutGap = opts.gap or DEFAULT_GAP
    f.layoutPadding = opts.padding
    if f.layoutPadding == nil then f.layoutPadding = (kind == "box") and DEFAULT_PADDING or 0 end
    f.layoutChildren = {}
    if parent then
        RegisterChild(parent, f, { role = kind, flow = opts.flow ~= false, gapBefore = opts.gapBefore })
    end
    return f
end

function L:Box(parent, id, opts)
    opts = opts or {}
    local box = Node(parent, "box", id, opts)
    box.layoutBorder = opts.border == true
    return box
end

local function NormalizeHorizontalAlign(value)
    value = type(value) == "string" and string.upper(value) or "LEFT"
    if value ~= "LEFT" and value ~= "CENTER" and value ~= "RIGHT" then
        return "LEFT"
    end
    return value
end

local function NormalizeVerticalAlign(value)
    value = type(value) == "string" and string.upper(value) or "TOP"
    if value ~= "TOP" and value ~= "CENTER" and value ~= "BOTTOM" then
        return "TOP"
    end
    return value
end

local function NormalizeLayoutPadding(value, default)
    value = value == nil and default or value
    if type(value) == "number" then
        local amount = math.max(0, value)
        return { left=amount, right=amount, top=amount, bottom=amount }
    end
    value = type(value) == "table" and value or {}
    local horizontal = math.max(0, tonumber(value.horizontal or value.x) or 0)
    local vertical = math.max(0, tonumber(value.vertical or value.y) or 0)
    return {
        left=math.max(0, tonumber(value.left) or horizontal),
        right=math.max(0, tonumber(value.right) or horizontal),
        top=math.max(0, tonumber(value.top) or vertical),
        bottom=math.max(0, tonumber(value.bottom) or vertical),
    }
end

function L:Row(parent, id, opts)
    opts = opts or {}
    local rowOptions = {}
    for key, value in pairs(opts) do rowOptions[key] = value end
    if rowOptions.gap == nil then rowOptions.gap = L.Metrics.ROW_GAP end
    local row = Node(parent, "row", id, rowOptions)
    row.layoutPadding = NormalizeLayoutPadding(opts.padding,
        { horizontal=0, vertical=L.Metrics.ROW_VERTICAL_PADDING })
    -- Rows fill their parent Column. Children default to top-left inside the
    -- Row's padded content area; alignment does not move the padding itself.
    row.layoutVerticalAlign = NormalizeVerticalAlign(opts.verticalAlign or opts.align)
    row.layoutAlign = row.layoutVerticalAlign -- legacy consumer-facing field
    row.layoutHorizontalAlign = NormalizeHorizontalAlign(opts.horizontalAlign)
    -- Control rows keep the established shared height unless a consumer opts
    -- into a smaller slot for text-only or button-only content.
    local minHeight = tonumber(opts.minHeight)
    if minHeight then
        row.layoutMinHeight = math.max(1, minHeight)
    end
    return row
end

function L:Columns(row, count, ids, opts)
    opts = opts or {}
    count = math.max(1, tonumber(count) or 1)
    -- `gap` remains a compatibility shorthand for callers that historically
    -- used one value for both directions. New callers can tune the horizontal
    -- column gap and vertical content gap independently.
    local legacyGap = opts.gap
    local contentGap = opts.contentGap
    if contentGap == nil then contentGap = legacyGap end
    if contentGap == nil then contentGap = L.Metrics.CONTENT_GAP end
    local columnGap = opts.columnGap
    if columnGap == nil then columnGap = legacyGap end
    if columnGap == nil then columnGap = row.layoutColumnGap end
    if columnGap == nil then columnGap = L.Metrics.COLUMN_GAP end
    local cols = {}
    for i=1,count do
        local id = ids and ids[i] or ("column"..i)
        local columnHorizontalAlign = opts.horizontalAlign or opts.align
        if type(opts.horizontalAlignments) == "table" and opts.horizontalAlignments[i] then
            columnHorizontalAlign = opts.horizontalAlignments[i]
        elseif type(opts.alignments) == "table" and opts.alignments[i] then
            columnHorizontalAlign = opts.alignments[i]
        end
        cols[i] = Node(row, "column", id, { gap=contentGap, padding=0, flow=false })
        local columnPadding = opts.padding
        if type(opts.paddings) == "table" and opts.paddings[i] ~= nil then
            columnPadding = opts.paddings[i]
        end
        -- Numeric padding is applied equally on all four sides. A table may
        -- use x/y or explicit left/right/top/bottom values.
        cols[i].layoutPadding = NormalizeLayoutPadding(columnPadding, 0)
        cols[i].layoutHorizontalAlign = NormalizeHorizontalAlign(columnHorizontalAlign)
        cols[i].layoutAlign = cols[i].layoutHorizontalAlign -- legacy consumer-facing field
        local columnVerticalAlign = opts.verticalAlign
        if type(opts.verticalAlignments) == "table" and opts.verticalAlignments[i] then
            columnVerticalAlign = opts.verticalAlignments[i]
        end
        cols[i].layoutVerticalAlign = NormalizeVerticalAlign(columnVerticalAlign)
        local minHeight = type(opts.minHeights) == "table" and tonumber(opts.minHeights[i]) or nil
        cols[i].layoutMinHeight = minHeight and math.max(1, minHeight) or nil
        local fixedWidth = type(opts.widths) == "table" and tonumber(opts.widths[i]) or nil
        cols[i].layoutFixedWidth = fixedWidth and fixedWidth > 0 and fixedWidth or nil
    end
    row.layoutColumns = cols
    row.layoutColumnCount = count
    row.layoutColumnGap = columnGap

    -- Optional per-row column weights. Equal flexible columns remain the
    -- default. A positive `widths[i]` fixes that Column's width; all other
    -- Columns divide the remaining width by weight.
    local weights = {}
    for i = 1, count do
        local weight = type(opts.weights) == "table" and tonumber(opts.weights[i]) or 1
        if not weight or weight <= 0 then weight = 1 end
        weights[i] = weight
    end
    row.layoutColumnWeights = weights

    function row:LayoutColumns(width)
        width = tonumber(width) or self:GetWidth() or 1
        local pixel = LayoutPixel(self)
        local snappedGap = CeilGrid(columnGap, pixel)
        local rowPadding = NormalizeLayoutPadding(self.layoutPadding, 0)
        local innerWidth = math.max(pixel, width - rowPadding.left - rowPadding.right)
        local usable = FloorGrid(math.max(pixel, innerWidth - snappedGap * (count - 1)), pixel)
        local fixedTotal, flexibleWeight = 0, 0
        for i, col in ipairs(cols) do
            if col.layoutFixedWidth then
                fixedTotal = fixedTotal + FloorGrid(col.layoutFixedWidth, pixel)
            else
                flexibleWeight = flexibleWeight + weights[i]
            end
        end
        local flexUsable = math.max(0, usable - fixedTotal)
        local allocated, flexUsed = {}, 0
        for i, col in ipairs(cols) do
            if col.layoutFixedWidth then
                allocated[i] = math.max(pixel, FloorGrid(col.layoutFixedWidth, pixel))
            else
                local nextUsed = flexUsed + weights[i]
                allocated[i] = flexibleWeight > 0
                    and math.max(pixel, FloorGrid(flexUsable * nextUsed / flexibleWeight, pixel)
                        - FloorGrid(flexUsable * flexUsed / flexibleWeight, pixel))
                    or pixel
                flexUsed = nextUsed
            end
        end
        local totalWidth = snappedGap * (count - 1)
        for i = 1, count do totalWidth = totalWidth + allocated[i] end
        local remaining = math.max(0, innerWidth - totalWidth)
        local rowAlign = NormalizeHorizontalAlign(self.layoutHorizontalAlign)
        local x = rowPadding.left + (rowAlign == "RIGHT" and remaining
            or (rowAlign == "CENTER" and remaining / 2 or 0))
        for i, col in ipairs(cols) do
            local columnWidth = allocated[i]
            SetWidthIfChanged(col, columnWidth)
            SetHeightIfChanged(col, math.max(1, col:GetHeight() or 1))
            SetAnchorsIfChanged(col, {{"TOPLEFT", self, "TOPLEFT", x, -rowPadding.top}})
            x = x + columnWidth + snappedGap
        end
    end

    function row:GetColumnWidth(index)
        local pixel = LayoutPixel(self)
        local width = self:GetWidth() or 1
        index = math.max(1, math.min(count, tonumber(index) or 1))
        if (cols[index]:GetWidth() or 0) > 0 then return cols[index]:GetWidth() end
        if cols[index].layoutFixedWidth then
            return math.max(pixel, FloorGrid(cols[index].layoutFixedWidth, pixel))
        end
        local rowPadding = NormalizeLayoutPadding(self.layoutPadding, 0)
        local usable = FloorGrid(math.max(pixel, width - rowPadding.left - rowPadding.right
            - CeilGrid(columnGap, pixel) * (count - 1)), pixel)
        local before = 0
        local fixed, flexibleWeight = 0, 0
        for i = 1, count do
            if cols[i].layoutFixedWidth then
                fixed = fixed + cols[i].layoutFixedWidth
            else
                flexibleWeight = flexibleWeight + weights[i]
                if i < index then before = before + weights[i] end
            end
        end
        local flexUsable = math.max(0, usable - fixed)
        return math.max(pixel, FloorGrid(flexUsable * (before + weights[index]) / math.max(1, flexibleWeight), pixel)
            - FloorGrid(flexUsable * before / math.max(1, flexibleWeight), pixel))
    end
    return cols
end


-- Reusable two-column Section structure. The same Row / Column / Section
-- reflow handles every host; no independent pixel anchoring or frame copies.
-- Sections are borderless presentation by default, but remain fully measured.
function L:SectionPair(parent, id, leftId, rightId, opts)
    opts = opts or {}
    local columnGap = opts.columnGap
    if columnGap == nil then columnGap = L.Metrics.COLUMN_GAP end
    local contentGap = opts.contentGap
    if contentGap == nil then contentGap = opts.columnGap or L.Metrics.CONTENT_GAP end
    local rowGap = opts.rowGap
    if rowGap == nil then rowGap = opts.columnGap or L.Metrics.ROW_GAP end
    local row = self:Row(parent, id, { flow=true, gap=rowGap })
    self:SetFlowChild(parent, row, "row")
    local columns = self:Columns(row, 2, {leftId .. "-host", rightId .. "-host"},
        { columnGap=columnGap, contentGap=contentGap })
    local sectionOpts = {
        flow=true, border=opts.border == true,
        padding=opts.padding == nil and L.Metrics.SECTION_PADDING or opts.padding,
        gap=opts.gap == nil and L.Metrics.SECTION_GAP or opts.gap,
    }
    local left = self:Section(columns[1], leftId, sectionOpts)
    local right = self:Section(columns[2], rightId, sectionOpts)
    left._tbuContentAlign = opts.align
    right._tbuContentAlign = opts.align
    return left, right
end

function L:GetRowVerticalAnchor(row)
    local align = NormalizeVerticalAlign(row and row.layoutVerticalAlign)
    if align == "TOP" then return "TOP" end
    if align == "BOTTOM" then return "BOTTOM" end
    return "CENTER"
end

function L:GetColumnHorizontalAnchor(column)
    local align = NormalizeHorizontalAlign(column and column.layoutHorizontalAlign)
    if align == "LEFT" then return "LEFT" end
    if align == "RIGHT" then return "RIGHT" end
    return "CENTER"
end

function L:AdoptContent(parent, content, opts)
    if not parent or not content then return content end
    opts = opts or {}
    content.layoutKind = content.layoutKind or "content"
    content.layoutFillWidth = opts.fillWidth == true
    content.layoutMaxWidth = tonumber(opts.maxWidth) or nil
    content.layoutWrap = opts.wrap == true
    content.layoutMeasureHeight = opts.measureHeight or content.layoutMeasureHeight
    return self:SetFlowChild(parent, content, opts.role or content.layoutRole or "content", opts.gapBefore)
end

-- Generic spelling for content adopted by a Row, Column, layout Container,
-- or a consumer-owned Frame. AdoptContent remains as a compatibility alias.
function L:AddContent(parent, content, opts)
    return self:AdoptContent(parent, content, opts)
end

function L:MeasureContent(content)
    if not content then return 1 end
    local measured
    if content.layoutMeasureHeight then
        measured = math.max(1, tonumber(content.layoutMeasureHeight(content)) or 1)
    elseif content.GetObjectType and content:GetObjectType() == "FontString" then
        measured = math.max(1, content:GetStringHeight() or content:GetHeight() or 1)
    else
        measured = math.max(1, (content.GetHeight and content:GetHeight()) or 1)
    end
    return measured + (content.layoutBottomPadding or 0)
end

function L:LayoutRow(row, width)
    if not row then return end
    if not row.layoutColumns or not row.LayoutColumns then
        -- A Row may contain content directly. When no Columns are declared,
        -- place its flow children left-to-right in creation order and measure
        -- the tallest child. Columns remain optional for simple one-line rows.
        width = math.max(1, tonumber(width) or row:GetWidth() or 1)
        local pixel = LayoutPixel(row)
        width = math.max(pixel, FloorGrid(width, pixel))
        SetWidthIfChanged(row, width)
        local padding = NormalizeLayoutPadding(row.layoutPadding, 0)
        local children, fixedWidth, fillCount, totalGap = {}, 0, 0, 0
        for _, child in ipairs(row.layoutChildren or {}) do
            if child:IsShown() and child.layoutParticipatesInFlow then
                children[#children + 1] = child
                if child.layoutFillWidth then
                    fillCount = fillCount + 1
                else
                    local childWidth = tonumber(child.layoutPreferredWidth)
                        or (child.GetWidth and tonumber(child:GetWidth())) or 1
                    if child.GetObjectType and child:GetObjectType() == "FontString"
                        and child.GetStringWidth then
                        childWidth = math.max(childWidth, tonumber(child:GetStringWidth()) or 1)
                    end
                    fixedWidth = fixedWidth + math.max(pixel, childWidth)
                end
                if #children > 1 then
                    totalGap = totalGap + math.max(0, tonumber(child.layoutGapBefore)
                        or row.layoutGap or L.Metrics.ROW_GAP)
                end
            end
        end

        if #children == 0 then
            row.layoutDirectContentHeight = 0
            return self:MeasureRow(row)
        end

        local innerWidth = math.max(pixel, width - padding.left - padding.right)
        local fillWidth = fillCount > 0 and math.max(pixel,
            (innerWidth - fixedWidth - totalGap) / fillCount) or nil
        local remaining = math.max(0, innerWidth - fixedWidth - totalGap - (fillWidth or 0) * fillCount)
        local horizontal = NormalizeHorizontalAlign(row.layoutHorizontalAlign)
        local x = padding.left + (horizontal == "RIGHT" and remaining
            or (horizontal == "CENTER" and remaining / 2 or 0))
        local placements, tallest = {}, 0
        for index, child in ipairs(children) do
            if index > 1 then
                x = x + math.max(0, tonumber(child.layoutGapBefore)
                    or row.layoutGap or L.Metrics.ROW_GAP)
            end
            local childWidth
            if child.layoutFillWidth then
                childWidth = fillWidth
            else
                childWidth = tonumber(child.layoutPreferredWidth)
                    or (child.GetWidth and tonumber(child:GetWidth())) or 1
                if child.GetObjectType and child:GetObjectType() == "FontString"
                    and child.GetStringWidth then
                    childWidth = math.max(childWidth, tonumber(child:GetStringWidth()) or 1)
                    if child.layoutWrap then
                        childWidth = math.min(childWidth, math.max(pixel, innerWidth - totalGap))
                    end
                end
            end
            childWidth = math.max(pixel, FloorGrid(childWidth, pixel))
            if child.layoutMaxWidth then childWidth = math.min(childWidth, child.layoutMaxWidth) end
            if child.SetWidth then SetWidthIfChanged(child, childWidth) end
            if child.UpdateLabelGeometry then child:UpdateLabelGeometry() end
            if child.layoutKind == "row" then
                self:LayoutRow(child, childWidth)
            elseif child.layoutKind == "section" then
                SetWidthIfChanged(child, childWidth)
                self:ReflowSection(child)
            elseif child.layoutKind == "container" or child.layoutKind == "column" then
                self:ReflowFrame(child, {width=childWidth, autoSize=true})
            end
            local childHeight = self:MeasureContent(child)
            tallest = math.max(tallest, childHeight)
            placements[#placements + 1] = {child=child, x=x, height=childHeight}
            x = x + childWidth
        end

        local naturalHeight = tallest + padding.top + padding.bottom
        local rowHeight = math.max(row.layoutMinHeight or L.Metrics.ROW_MIN_HEIGHT, naturalHeight)
        SetHeightIfChanged(row, rowHeight)
        local freeHeight = math.max(0, rowHeight - naturalHeight)
        local vertical = self:GetRowVerticalAnchor(row)
        local yOffset = vertical == "BOTTOM" and freeHeight
            or (vertical == "CENTER" and freeHeight / 2 or 0)
        for _, placement in ipairs(placements) do
            SetAnchorsIfChanged(placement.child, {{"TOPLEFT", row, "TOPLEFT",
                placement.x, -(padding.top + yOffset)}})
        end
        row.layoutDirectContentHeight = naturalHeight
        return rowHeight
    end

    width = math.max(1, tonumber(width) or row:GetWidth() or 1)
    local pixel = LayoutPixel(row)
    width = math.max(pixel, FloorGrid(width, pixel))
    SetWidthIfChanged(row, width)
    local rowPadding = NormalizeLayoutPadding(row.layoutPadding, 0)
    row:LayoutColumns(width)

    -- Recursive layout contract:
    -- Section -> Row -> Column -> Content OR Section.
    -- A nested Section receives the width of its Column, reflows its own Rows,
    -- and returns its measured height to that Column. The Row then measures the
    -- tallest Column. No presentation concept (box/header/subsection) participates
    -- in this geometry contract.
    for _, col in ipairs(row.layoutColumns) do
        local outerColumnWidth = math.max(1, col:GetWidth() or 1)
        local columnPadding = NormalizeLayoutPadding(col.layoutPadding, 0)
        local columnWidth = math.max(1, outerColumnWidth - columnPadding.left - columnPadding.right)
        local previous
        local totalHeight = 0
        local placements = {}

        for _, child in ipairs(col.layoutChildren or {}) do
            if child:IsShown() and (child.layoutParticipatesInFlow or child.layoutKind == "section" or child.layoutKind == "row") then
                -- Measure the gap BEFORE placement. Applying it later would
                -- replace CENTER/RIGHT anchors with TOPLEFT for the second
                -- Content in a Column and silently break standard alignment.
                local gap = previous and (child.layoutGapBefore or col.layoutGap or L.Metrics.ROW_GAP) or 0
                totalHeight = totalHeight + math.max(0, gap)
                local anchors
                local childTop = columnPadding.top + totalHeight
                if child.layoutKind == "section" then
                    SetWidthIfChanged(child, columnWidth)
                    anchors = {
                        {"TOPLEFT", col, "TOPLEFT", columnPadding.left, -childTop},
                        {"TOPRIGHT", col, "TOPRIGHT", -columnPadding.right, -childTop},
                    }
                    SetAnchorsIfChanged(child, anchors)
                    placements[#placements + 1] = { child=child, anchors=anchors }
                    self:ReflowSection(child)
                elseif child.layoutKind == "row" then
                    SetWidthIfChanged(child, columnWidth)
                    anchors = {{"TOPLEFT", col, "TOPLEFT", columnPadding.left, -childTop}}
                    SetAnchorsIfChanged(child, anchors)
                    placements[#placements + 1] = { child=child, anchors=anchors }
                    self:LayoutRow(child, columnWidth)
                else
                    if child.layoutWrap and child.GetObjectType and child:GetObjectType() == "FontString" then
                        SetWidthIfChanged(child, columnWidth)
                        child:SetWordWrap(true)
                        child:SetNonSpaceWrap(true)
                    elseif child.layoutFillWidth then
                        local fillWidth = math.min(columnWidth, child.layoutMaxWidth or columnWidth)
                        SetWidthIfChanged(child, fillWidth)
                    elseif child.SetWidth and child.GetWidth then
                        SetWidthIfChanged(child, child:GetWidth() or columnWidth)
                    end
                    local anchor = self:GetColumnHorizontalAnchor(col)
                    if child.layoutFillWidth or anchor == "LEFT" then
                        anchors = {{"TOPLEFT", col, "TOPLEFT", columnPadding.left, -childTop}}
                    elseif anchor == "RIGHT" then
                        anchors = {{"TOPRIGHT", col, "TOPRIGHT", -columnPadding.right, -childTop}}
                    else
                        anchors = {{"TOP", col, "TOP", (columnPadding.left - columnPadding.right) / 2, -childTop}}
                    end
                    SetAnchorsIfChanged(child, anchors)
                    placements[#placements + 1] = { child=child, anchors=anchors }
                end

                local childHeight = self:MeasureContent(child)
                totalHeight = totalHeight + childHeight
                previous = child
            end
        end

        -- Every layout pass owns the current measurement, including an empty
        -- Column. Never retain a previous Content height after its children stop
        -- participating in flow; the structural Column remains, but measures empty.
        col.layoutContentHeight = math.max(1,
            columnPadding.top + totalHeight + columnPadding.bottom)
        col.layoutAllocatedHeight = math.max(col.layoutContentHeight, col.layoutMinHeight or 0)
        SetHeightIfChanged(col, col.layoutAllocatedHeight)
        local freeHeight = math.max(0, col.layoutAllocatedHeight - col.layoutContentHeight)
        local vertical = NormalizeVerticalAlign(col.layoutVerticalAlign)
        local contentOffset = vertical == "BOTTOM" and freeHeight
            or (vertical == "CENTER" and freeHeight / 2 or 0)
        if contentOffset > 0 then
            for _, placement in ipairs(placements) do
                local shifted = {}
                for i, anchorSpec in ipairs(placement.anchors) do
                    shifted[i] = {anchorSpec[1], anchorSpec[2], anchorSpec[3], anchorSpec[4], anchorSpec[5] - contentOffset}
                end
                SetAnchorsIfChanged(placement.child, shifted)
            end
        end
    end

    self:MeasureRow(row)
    -- Rows keep their own order and use their selected vertical alignment only
    -- to place shorter Columns within the measured Row height.
    local anchor = self:GetRowVerticalAnchor(row)
    local rowHeight = row:GetHeight()
    local innerHeight = math.max(0, rowHeight - rowPadding.top - rowPadding.bottom)
    for _, col in ipairs(row.layoutColumns) do
        local contentHeight = col.layoutAllocatedHeight or col.layoutContentHeight or 0
        local remaining = math.max(0, innerHeight - contentHeight)
        local offsetY = anchor == "BOTTOM" and remaining or (anchor == "CENTER" and remaining / 2 or 0)
        local columnX = col._tbuLayoutAnchorSpec and col._tbuLayoutAnchorSpec[1][4] or 0
        SetAnchorsIfChanged(col, {{"TOPLEFT", row, "TOPLEFT", columnX, -(rowPadding.top + offsetY)}})
    end
    return rowHeight
end


-- Arrange complete page Sections into responsive rows. Sections are never
-- split or internally resized beyond their normal reflow; the page chooses how
-- many full Section columns can fit at the preferred width and wraps to a new
-- row when necessary. This keeps Section -> Row -> Column -> Content intact
-- while removing the previous hard two-column ceiling.
function L:FlowContainerSections(container, sections, opts)
    opts = opts or {}
    local width = math.max(1, tonumber(opts.width) or container:GetWidth() or 1)
    -- Optional content-width packing. Each Section still reflows through the
    -- standard Section -> Row -> Column -> Content measurement contract; the
    -- container only positions complete, measured Sections in available rows.
    -- Content-width packing remains a separate opt-in arrangement.
    if opts.fitContentWidths then
        local left = math.max(0, tonumber(opts.left) or 0)
        local right = math.max(0, tonumber(opts.right) or 0)
        local top = math.max(0, tonumber(opts.top) or 0)
        local columnGap = math.max(0, tonumber(opts.columnGap) or L.Metrics.PAGE_SECTION_GAP)
        local rowGap = math.max(0, tonumber(opts.rowGap) or L.Metrics.PAGE_SECTION_GAP)
        local available = math.max(1, width - left - right)
        local x, y, rowHeight = 0, top, 0
        for _, section in ipairs(sections or {}) do
            if section:IsShown() then
                local naturalWidth = math.max(1, tonumber(section.layoutPreferredWidth) or available)
                local sectionWidth = math.min(naturalWidth, available)
                SetWidthIfChanged(section, sectionWidth)
                self:ReflowSection(section)
                local sectionHeight = math.max(1, section:GetHeight() or 1)
                if x > 0 and x + sectionWidth > available then
                    x, y, rowHeight = 0, y + rowHeight + rowGap, 0
                end
                SetAnchorsIfChanged(section, {{"TOPLEFT", container, "TOPLEFT", left + x, -y}})
                x = x + sectionWidth + columnGap
                rowHeight = math.max(rowHeight, sectionHeight)
            else
                if section:GetNumPoints() > 0 then section:ClearAllPoints() end
                section._tbuLayoutAnchorSpec = nil
            end
        end
        local totalHeight = y + rowHeight
        SetHeightIfChanged(container, math.max(1, totalHeight))
        return totalHeight
    end
    local pixel = LayoutPixel(container)
    local preferred = math.max(pixel, FloorGrid(math.max(100, tonumber(opts.sectionWidth) or 590), pixel))
    local columnGap = CeilGrid(math.max(0, tonumber(opts.columnGap) or L.Metrics.PAGE_SECTION_GAP), pixel)
    local rowGap = CeilGrid(math.max(0, tonumber(opts.rowGap) or L.Metrics.PAGE_SECTION_GAP), pixel)
    local left = CeilGrid(math.max(0, tonumber(opts.left) or 0), pixel)
    local right = CeilGrid(math.max(0, tonumber(opts.right) or 0), pixel)
    local top = CeilGrid(math.max(0, tonumber(opts.top) or 0), pixel)
    local available = math.max(pixel, FloorGrid(width - left - right, pixel))
    local maxColumns = tonumber(opts.maxColumns)
    if maxColumns and maxColumns > 0 then
        maxColumns = math.max(1, math.floor(maxColumns))
    else
        maxColumns = nil
    end

    local columnsPerRow = math.max(1, math.floor((available + columnGap) / (preferred + columnGap)))
    if maxColumns then columnsPerRow = math.min(columnsPerRow, maxColumns) end
    local sectionWidth = FloorGrid(math.min(preferred, available), pixel)

    -- Ordered, height-aware bands. The first Section determines the initial
    -- band height. Subsequent Sections stack downward, then move to the next
    -- column if they would exceed the current band boundary. A taller Section
    -- placed at the top of an available column may extend that band height.
    -- Once all columns are used, the following Section starts a new band.
    local bandTop = top
    local bandHeight = 0
    local column = 1
    local columnUsed = 0
    local hasBand = false

    local function NextBand()
        bandTop = bandTop + bandHeight + rowGap
        bandHeight, column, columnUsed = 0, 1, 0
    end

    for _, section in ipairs(sections or {}) do
        if section:IsShown() then
            SetWidthIfChanged(section, sectionWidth)
            self:ReflowSection(section)
            local height = math.max(pixel, CeilGrid(tonumber(section:GetHeight()) or 1, pixel))
            SetHeightIfChanged(section, height)
            if not hasBand then
                hasBand = true
                bandHeight = height
            elseif columnUsed > 0 and columnUsed + rowGap + height > bandHeight then
                if column < columnsPerRow then
                    column = column + 1
                    columnUsed = 0
                else
                    NextBand()
                    bandHeight = height
                end
            end
            if columnUsed == 0 then
                bandHeight = math.max(bandHeight, height)
            end
            local x = left + (column - 1) * (sectionWidth + columnGap)
            local y = bandTop + (columnUsed > 0 and columnUsed + rowGap or 0)
            SetAnchorsIfChanged(section, {{"TOPLEFT", container, "TOPLEFT", x, -y}})
            columnUsed = (columnUsed > 0 and columnUsed + rowGap or 0) + height
        else
            if section:GetNumPoints() > 0 then section:ClearAllPoints() end
            section._tbuLayoutAnchorSpec = nil
        end
    end

    local contentHeight = hasBand and (bandTop + bandHeight) or top
    SetHeightIfChanged(container, math.max(1, contentHeight))
    return contentHeight
end

-- A layout container can live in a frame, pane, or switchable container. Page
-- selection belongs to the host; this node only measures and flows content.
function L:Container(parent, id, opts)
    local container = Node(parent, "container", id, opts or {})
    container.layoutPadding = (opts and opts.padding) or 0
    return container
end

function L:AdoptChild(parent, child, opts)
    if not parent or not child then return child end
    opts = opts or {}
    if child.layoutParent and child.layoutParent.layoutChildren then
        for i = #child.layoutParent.layoutChildren, 1, -1 do
            if child.layoutParent.layoutChildren[i] == child then
                table.remove(child.layoutParent.layoutChildren, i)
                break
            end
        end
    end
    return RegisterChild(parent, child, {
        role = opts.role or child.layoutRole or child.layoutKind or "content",
        gapBefore = opts.gapBefore,
        flow = opts.flow ~= false,
    })
end

function L:PageSectionRow(page, id, section)
    local row = self:Row(page, id, { gap = 0, padding = 0 })
    local columns = self:Columns(row, 1, { id .. "-column" }, { gap = 0, padding = 0 })
    local column = columns[1]
    self:AdoptChild(column, section, { role = "section" })
    row.layoutSection = section
    row.layoutSectionColumn = column
    return row
end

-- Reflow directly registered content in any Frame. A Row and Column are useful
-- structure, but neither is required for a simple creation-order content stack.
function L:ReflowFrame(frame, opts)
    if not frame then return 0 end
    opts = opts or {}
    local width = tonumber(opts.width) or (frame.GetWidth and frame:GetWidth())
    if not width or width <= 1 then return 0 end
    width = math.max(1, width)
    SetWidthIfChanged(frame, width)
    local padding = NormalizeLayoutPadding(opts.padding ~= nil and opts.padding
        or frame.layoutPadding or 0, 0)
    local gap = math.max(0, tonumber(opts.gap) or frame.layoutGap or L.Metrics.ROW_GAP)
    local innerWidth = math.max(1, width - padding.left - padding.right)
    local children = opts.children or frame.layoutChildren or {}
    local previous
    local totalHeight = padding.top

    for _, child in ipairs(children) do
        if child and child:IsShown() and (child.layoutParticipatesInFlow
            or child.layoutKind == "row" or child.layoutKind == "column"
            or child.layoutKind == "container" or child.layoutKind == "section") then
            local childGap = previous and math.max(0, tonumber(child.layoutGapBefore) or gap) or 0
            totalHeight = totalHeight + childGap
            local childWidth = innerWidth
            if child.layoutFillWidth == false and child.layoutKind ~= "row"
                and child.layoutKind ~= "section" and child.layoutKind ~= "column"
                and child.layoutKind ~= "container" then
                childWidth = tonumber(child.layoutPreferredWidth)
                    or (child.GetWidth and tonumber(child:GetWidth())) or innerWidth
                if child.GetObjectType and child:GetObjectType() == "FontString"
                    and child.layoutWrap then childWidth = innerWidth end
                childWidth = math.max(1, math.min(innerWidth, childWidth))
            end
            if child.SetWidth then SetWidthIfChanged(child, childWidth) end
            if child.layoutKind == "row" then
                self:LayoutRow(child, childWidth)
            elseif child.layoutKind == "section" then
                self:ReflowSection(child)
            elseif child.layoutKind == "column" or child.layoutKind == "container" then
                self:ReflowFrame(child, {width=childWidth, autoSize=true})
            elseif child.layoutWrap and child.GetObjectType
                and child:GetObjectType() == "FontString" then
                child:SetWordWrap(true)
                if child.SetNonSpaceWrap then child:SetNonSpaceWrap(true) end
            end

            local anchor = self:GetColumnHorizontalAnchor(frame)
            local x = padding.left
            if anchor == "RIGHT" then x = width - padding.right - childWidth
            elseif anchor == "CENTER" then x = padding.left + (innerWidth - childWidth) / 2 end
            SetAnchorsIfChanged(child, {{"TOPLEFT", frame, "TOPLEFT", x, -totalHeight}})
            totalHeight = totalHeight + math.max(1, self:MeasureContent(child))
            previous = child
        end
    end

    totalHeight = totalHeight + padding.bottom
    if opts.autoSize == true or (opts.autoSize == nil and frame.layoutKind == "container") then
        SetHeightIfChanged(frame, math.max(1, totalHeight))
    end
    return totalHeight
end

-- Opt an existing WoW Frame into direct creation-order layout. Content can be
-- adopted straight into this frame; additions and frame resizes schedule a
-- coalesced reflow after the current geometry pass. Consumers can call
-- frame:RequestContentLayout() after changing content that affects its measured size.
function L:EnableFrameLayout(frame, opts)
    if not frame then return nil end
    opts = opts or {}
    frame.layoutKind = frame.layoutKind or "frame"
    frame.layoutChildren = frame.layoutChildren or {}
    if opts.padding ~= nil then frame.layoutPadding = opts.padding end
    if opts.gap ~= nil then frame.layoutGap = opts.gap end
    if opts.horizontalAlign ~= nil then frame.layoutHorizontalAlign = opts.horizontalAlign end
    frame._tbuFrameLayoutOptions = opts

    if not frame._tbuLayoutUpdate then
        local update = CreateFrame("Frame", nil, frame)
        update:Hide()
        update:SetScript("OnUpdate", function(self)
            self:Hide()
            L:ReflowFrame(frame, frame._tbuFrameLayoutOptions)
        end)
        frame._tbuLayoutUpdate = update
        frame._tbuRequestLayout = function()
            if frame._tbuLayoutUpdate and not frame._tbuLayoutUpdate:IsShown() then
                frame._tbuLayoutUpdate:Show()
            end
        end
        frame:HookScript("OnSizeChanged", frame._tbuRequestLayout)
        frame.RequestContentLayout = function(self)
            if self._tbuRequestLayout then self:_tbuRequestLayout() end
        end
    end

    frame:_tbuRequestLayout()
    return frame
end

function L:ReflowColumn(column, opts)
    opts = opts or {}
    opts.autoSize = opts.autoSize ~= false
    return self:ReflowFrame(column, opts)
end

function L:ReflowContainer(container, rows, opts)
    opts = opts or {}
    if rows == nil then
        opts.autoSize = opts.autoSize ~= false
        return self:ReflowFrame(container, opts)
    end
    local width = math.max(1, tonumber(opts.width) or container:GetWidth() or 1)
    SetWidthIfChanged(container, width)

    for _, row in ipairs(rows or {}) do
        SetWidthIfChanged(row, width)
        row:LayoutColumns(width)
        local section = row.layoutSection
        local column = row.layoutSectionColumn
        -- Conditional container Sections control their wrapper Row visibility.
        -- This keeps hidden Sections out of stacking and scroll measurements.
        if section then row:SetShown(section:IsShown()) end
        if section and column and row:IsShown() then
            SetWidthIfChanged(column, width)
            local sectionAnchors = {
                {"TOPLEFT", column, "TOPLEFT", 0, 0},
                {"RIGHT", column, "RIGHT", 0, 0},
            }
            SetAnchorsIfChanged(section, sectionAnchors)
            self:ReflowSection(section)
            local height = math.max(1, section:GetHeight() or 1)
            SetHeightIfChanged(column, height)
            SetHeightIfChanged(row, height)
        end
    end

    return self:StackRows(container, rows, {
        padding = opts.padding or 0,
        gap = opts.gap or L.Metrics.SECTION_GAP,
    })
end

function L:SetContentHeight(node, height)
    node.layoutContentHeight = math.max(0, tonumber(height) or 0)
    SetHeightIfChanged(node, math.max(1, node.layoutContentHeight))
end

function L:MeasureRow(row, bottomPadding)
    local tallest = 0
    for _,col in ipairs(row.layoutColumns or {}) do
        if col:IsShown() then
            tallest = math.max(tallest, col.layoutAllocatedHeight or col.layoutContentHeight or col:GetHeight() or 0)
        end
    end
    -- Symmetric Row padding is included in its measured outer height. Rows
    -- otherwise grow from measured content instead of reserving a tall slot.
    local rowPadding = NormalizeLayoutPadding(row.layoutPadding, 0)
    local natural = tallest + rowPadding.top + rowPadding.bottom + (bottomPadding or 0)
    SetHeightIfChanged(row, math.max(row.layoutMinHeight or L.Metrics.ROW_MIN_HEIGHT, natural))
    return row:GetHeight()
end

-- Reusable placement for persistent footer/other host regions. The region
-- sizes to its measured Row and the Row stays positioned by structural layout,
-- without any control-specific geometry. Host styles may still define a minimum.
function L:LayoutRowInRegion(row, region, opts)
    if not row or not region then return end
    opts = opts or {}
    local insetX = math.max(0, tonumber(opts.insetX) or 0)
    local insetY = opts.insetY
    if insetY == nil then insetY = L.Metrics.ROW_REGION_INSET_Y end
    insetY = math.max(0, tonumber(insetY) or 0)
    local width = math.max(1, region:GetWidth() - (2 * insetX))
    self:LayoutRow(row, width)
    local height = math.max(tonumber(opts.minHeight) or 1, row:GetHeight() + (2 * insetY))
    -- OnSizeChanged may trigger the sizing pass again. Only write changed height.
    SetHeightIfChanged(region, height)
    SetAnchorsIfChanged(row, {{"TOPLEFT", region, "TOPLEFT", insetX, -insetY}})
    return height
end

function L:StackRows(box, rows, opts)
    opts = opts or {}
    local gap = opts.gap or box.layoutGap or DEFAULT_GAP
    local pad = opts.padding
    if pad == nil then pad = box.layoutPadding or 0 end
    local previous
    local total = pad
    for _,row in ipairs(rows) do
      if row:IsShown() then
        if previous then
            SetAnchorsIfChanged(row, {
                {"TOPLEFT", previous, "BOTTOMLEFT", 0, -gap},
                {"RIGHT", box, "RIGHT", -pad, 0},
            })
            total = total + gap
        else
            SetAnchorsIfChanged(row, {
                {"TOPLEFT", box, "TOPLEFT", pad, -pad},
                {"RIGHT", box, "RIGHT", -pad, 0},
            })
        end
        total = total + (row:GetHeight() or 0)
        previous = row
      end
    end
    SetHeightIfChanged(box, math.max(1, total + pad))
    return box:GetHeight()
end


-- Development normalization pass: ordinary sections surrender their direct-child
-- placement to one shared flow. This intentionally exposes legacy nested layout
-- assumptions so they can be replaced by named shared element primitives.
function L:NormalizeOrdinarySection(section)
    -- During the architecture rebuild, normalization now means one thing:
    -- reflow the children explicitly registered with the shared Section.
    -- Unregistered legacy controls are intentionally NOT guessed from frame
    -- enumeration; they remain visibly broken until assigned a Row/Column role.
    return self:ReflowSection(section)
end

function L:Describe(node)
    if not node then return nil end
    return { kind=node.layoutKind, id=node.layoutId, columns=node.layoutColumnCount }
end


-- Stack a major settings section after another section. The child section only
-- needs to know its immediate predecessor, not the page's absolute Y position.
function L:PlaceSectionAfter(section, previous, gap, leftOffset)
    gap = gap or DEFAULT_GAP
    leftOffset = leftOffset or 0
    SetAnchorsIfChanged(section, {{"TOPLEFT", previous, "BOTTOMLEFT", leftOffset, -gap}})
end

-- A named structure can be inspected/addressed without relying on coordinates.
function L:FindChild(parent, id)
    for _, child in ipairs((parent and parent.layoutChildren) or {}) do
        if child.layoutId == id then return child end
    end
    return nil
end


function L:StackSections(parent, sections, opts)
    opts = opts or {}
    local left, right = opts.left or 8, opts.right or 8
    local top, gap = opts.top or 8, opts.gap or L.Metrics.SECTION_GAP
    local bottom = opts.bottom or 0
    local previous
    local total = top
    local count = 0
    for _, section in ipairs(sections or {}) do
        local anchors = {
            {"LEFT", parent, "LEFT", left, 0},
            {"RIGHT", parent, "RIGHT", -right, 0},
        }
        if previous then
            anchors[#anchors + 1] = {"TOP", previous, "BOTTOM", 0, -gap}
            total = total + gap
        else
            anchors[#anchors + 1] = {"TOP", parent, "TOP", 0, -top}
        end
        SetAnchorsIfChanged(section, anchors)
        total = total + (section:GetHeight() or 0)
        count = count + 1
        previous = section
    end
    return math.max(1, total + bottom)
end

function L:PlaceInColumn(frame, column, x, y)
    SetAnchorsIfChanged(frame, {{"TOPLEFT", column, "TOPLEFT", x or 0, -(y or 0)}})
end
