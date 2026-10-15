-- SPECTRA MM2 v2 + Extras Beta loader
-- Runs two readable files from this repository. Third-party executor compatibility not guaranteed.
local base = "https://raw.githubusercontent.com/xxsloppybaconxx-blip/MM2-Script-Hub/main/"
local function runFile(filename)
    local ok, source = pcall(function()
        return game:HttpGet(base .. filename)
    end)
    if not ok or type(source) ~= "string" then
        warn("SPECTRA: failed to fetch " .. filename)
        return
    end
    local chunk, err = loadstring(source)
    if not chunk then
        warn("SPECTRA: syntax error in " .. filename .. ": " .. tostring(err))
        return
    end
    local success, message = pcall(chunk)
    if not success then
        warn("SPECTRA: error running " .. filename .. ": " .. tostring(message))
    end
end
runFile("mm2_hub_v2.lua")
runFile("spectra_extras.lua")
