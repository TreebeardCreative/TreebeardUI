-- Width and height come from the packaged PNGs. Preview sizes are curated so
-- the Texture Library shows useful sizes down to 16px; smaller sizes are conceptual.
local _, private = ...
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private
TBU.TextureManifest = {
    {name='addon_icon', width=256, height=256, sizes={256,128,64,32,16}},
    {name='checkbox_checked', width=64, height=64, sizes={64,32,16}},
    {name='checkbox_outline', width=64, height=64, sizes={64,32,16}},
    {name='draggable_list_grip', width=64, height=64, sizes={64,32,16}},
    {name='exit_icon', width=64, height=64, sizes={64,32,16}},
    {name='input_mask', width=32, height=32, sizes={32,16}},
    {name='lock', width=256, height=256, sizes={256,128,64,32,16}},
    {name='minimize_icon', width=64, height=64, sizes={64,32,16}},
    {name='radio_checked', width=64, height=64, sizes={64,32,16}},
    {name='radio_outline', width=64, height=64, sizes={64,32,16}},
    {name='resize_handle', width=256, height=256, sizes={256,128,64,32,16}},
    {name='rounded_input', width=48, height=32, sizes={48,24}},
    {name='scroll_arrow', width=256, height=256, sizes={256,128,64,32,16}},
    {name='scroll_thumb', width=64, height=64, sizes={64,32,16}},
    {name='settings', width=256, height=256, sizes={256,128,64,32,16}},
    {name='text_input_icon', width=64, height=64, sizes={64,32,16}},
    {name='unlock', width=256, height=256, sizes={256,128,64,32,16}},
}
