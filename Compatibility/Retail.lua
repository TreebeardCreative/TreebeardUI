-- Retail adapter. Loaded immediately after Bootstrap by the Retail TOC.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = assert((private.__TBUIRuntime or private.__TreebeardUIRuntime), "TreebeardUI bootstrap must load first")
TBU.Compatibility = { CLIENT = "Retail" }
function TBU.Compatibility:CreateBackdropFrame(kind, parent)
    return CreateFrame(kind, nil, parent, "BackdropTemplate")
end
