-- Shared color-family math for consumer-owned TreebeardUI presets.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

local Factory = {}
TBU.ColorFactory = Factory

-- These are fixed palette labels, not endpoints of a generated shade family.
Factory.white = "#FFFFFF"
Factory.black = "#000000"

local function ParseHex(value)
    if type(value) ~= "string" then return nil end
    local hex = value:match("^#?(%x%x%x%x%x%x)$")
    if not hex then return nil end
    local packed = tonumber(hex, 16)
    return math.floor(packed / 65536) / 255,
        math.floor(packed / 256) % 256 / 255,
        packed % 256 / 255
end

function Factory.ToRGBA(value, alpha)
    if type(value) == "table" then
        return value[1], value[2], value[3], value[4] or alpha or 1
    end
    local red, green, blue = ParseHex(value)
    if not red then return nil end
    return red, green, blue, alpha or 1
end

function Factory.ToHex(value)
    local red, green, blue = Factory.ToRGBA(value)
    if not red then return nil end
    return string.format("#%02X%02X%02X",
        math.floor(red * 255 + 0.5), math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5))
end

local function ToHSL(red, green, blue)
    local maximum, minimum = math.max(red, green, blue), math.min(red, green, blue)
    local delta = maximum - minimum
    local lightness = (maximum + minimum) / 2
    if delta == 0 then return 0, 0, lightness end
    local saturation = delta / (1 - math.abs(2 * lightness - 1))
    local hue
    if maximum == red then hue = ((green - blue) / delta) % 6
    elseif maximum == green then hue = (blue - red) / delta + 2
    else hue = (red - green) / delta + 4 end
    return hue / 6, saturation, lightness
end

local function FromHSL(hue, saturation, lightness)
    local chroma = (1 - math.abs(2 * lightness - 1)) * saturation
    local huePart = hue * 6
    local secondary = chroma * (1 - math.abs(huePart % 2 - 1))
    local red, green, blue
    if huePart < 1 then red, green, blue = chroma, secondary, 0
    elseif huePart < 2 then red, green, blue = secondary, chroma, 0
    elseif huePart < 3 then red, green, blue = 0, chroma, secondary
    elseif huePart < 4 then red, green, blue = 0, secondary, chroma
    elseif huePart < 5 then red, green, blue = secondary, 0, chroma
    else red, green, blue = chroma, 0, secondary end
    local match = lightness - chroma / 2
    return red + match, green + match, blue + match
end

function Factory.DeriveShades(base, step, count, direction)
    local red, green, blue, alpha = Factory.ToRGBA(base)
    if not red then return nil end
    local hue, saturation, lightness = ToHSL(red, green, blue)
    local shades = {{red, green, blue, alpha}}
    local sign = direction == "darker" and -1 or 1
    step, count = tonumber(step) or 0.08, math.max(0, math.floor(tonumber(count) or 3))
    for index = 1, count do
        local nextLightness = math.max(0, math.min(1, lightness + sign * step * index))
        local shadeRed, shadeGreen, shadeBlue = FromHSL(hue, saturation, nextLightness)
        shades[#shades + 1] = {shadeRed, shadeGreen, shadeBlue, alpha}
    end
    return shades
end

-- Five family levels start at the input base and increase in 5% HSL
-- lightness steps. These are offsets, not fixed absolute lightness values.
local LIGHTNESS_STEPS = {0, 0.05, 0.10, 0.15, 0.20}
Factory.LightnessSteps = LIGHTNESS_STEPS

-- Preserve the base hue and saturation, starting at its own lightness and
-- generating four successively brighter levels in 5% increments.
function Factory.DeriveFiveLevels(base)
    local red, green, blue, alpha = Factory.ToRGBA(base)
    if not red then return nil end

    local hue, saturation, baseLightness = ToHSL(red, green, blue)
    local levels = {}

    for index = 1, 5 do
        local lightness = math.min(1, baseLightness + LIGHTNESS_STEPS[index])
        local shadeRed, shadeGreen, shadeBlue = FromHSL(hue, saturation, lightness)
        levels[index] = {shadeRed, shadeGreen, shadeBlue, alpha}
    end

    return {
        [1] = levels[1], [2] = levels[2], [3] = levels[3],
        [4] = levels[4], [5] = levels[5],
    }
end

-- Build flat, directly addressable color-family tokens. Family names are
-- caller supplied palette labels, not semantic visual roles. Mapping a family
-- shade to a component remains an explicit style decision.
function Factory.BuildFamilies(bases)
    if type(bases) ~= "table" then return nil end
    local families, colors = {}, {black=Factory.black, white=Factory.white}
    for familyName, base in pairs(bases) do
        if type(familyName) ~= "string" or familyName == "" or familyName == "black" or familyName == "white" then
            return nil
        end
        local family = Factory.DeriveFiveLevels(base)
        if not family then return nil end
        families[familyName] = family
        colors[familyName .. "_base"] = Factory.ToHex(base)
        for index = 1, 5 do
            colors[familyName .. "_" .. index] = family[index]
        end
    end
    families.black, families.white = Factory.black, Factory.white
    return colors, families
end

function Factory.Mix(first, second, amount, alpha)
    local ar, ag, ab = Factory.ToRGBA(first)
    local br, bg, bb = Factory.ToRGBA(second)
    if not ar or not br then return nil end
    amount = math.max(0, math.min(1, tonumber(amount) or 0.5))
    return {
        ar + (br - ar) * amount,
        ag + (bg - ag) * amount,
        ab + (bb - ab) * amount,
        alpha or 1,
    }
end
