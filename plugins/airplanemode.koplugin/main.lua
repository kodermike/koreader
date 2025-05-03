local Device = require("device")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local airplanemode = false

-- establish the main settings file
local DataStorage = require("datastorage")
if G_reader_settings is nil then
    G_reader_settings = require("luasettings"):open(settings_file)
end

local settings_file = DataStorage:getDataDir().."/settings.reader.lua"
local settings_bk = DataStorage:getDataDir().."/settings.reader.lua.current"

-- test we can see the real settings file.
if os.rename(settings_file,settings_file) then
    logger.dbg("Settings file confirmed to exist")
else
    logger.err("Settings file not found! Abort!")
end

-- check if we currently have a backup of our settings running
local settings_bk_exists = false
if os.rename(settings_bk,settings_bk) then
    settings_bk_exists = true
end

-- also verify if the airplanemode flag is set. we will use this to decide if something is funky
local airplanemode_active = false
if G_reader_settings:isTrue("airplanemode") then airplanemode_active = true end

-- start / end - need to detect status

-- start
-- copy backup
-- unset all wireless values

-- end
-- mv backup to current
-- reload settings

local autostart_done

local AirPlaneMode = WidgetContainer:extend{
    name = "airplanemode",
    prefix = "airplanemode_exec_",
    airplanemode_file = DataStorage:getSettingsDir() .. "/airplanemode.lua",
    data = nil,
    updated = false,
}

function AirPlaneMode:init()
    Dispatcher:init()
    self.ui.menu:registerToMainMenu(self)
    self:onStart()
end

function AirPlaneMode:onStart() -- local event
    if not autostart_done then
        self:executeAutoExecEvent("Start")
        autostart_done = true
    end
end

function AirPlaneMode:onOutOfScreenSaver() -- global
    self:executeAutoExecEvent("OutOfScreenSaver")
end

function AirPlaneMode:executeAutoExecEvent(event)
    if self.autoexec[event] == nil then return end
    if settings_bk_exists == true and airplanemode_active == true then
        airplanemode = true
    elseif settings_bk_exists = false and airplanemode_active = false then
        airplanemode = false
    AirPlaneModef:turnon(airplanemode, event)
end

function AirPlaneMode:backup(settings_file)
    settings_file = settings_file or self.settings_file
    if os.rename(settings_file,settings_file) then
        if lfs.attributes(settings_file, "mode") == "settings_file" then
            -- lifted straight from reader.lua, including explanation. thank you lua gods
            -- As an additional safety measure (to the ffiutil.fsync* calls used in util.writeToFile),
            -- we only backup the settings_file to .old when it has not been modified in the last 60 seconds.
            -- This should ensure in the case the fsync calls are not supported
            -- that the OS may have itself sync'ed that settings_file content in the meantime.
            local mtime = lfs.attributes(settings_file, "modification")
            if mtime < os.time() - 60 then
                -- os.rename(settings_file, settings_file .. ".current")
                local orig = settings_file
                local dest = settings_bk
                --open and read content file
                local saved_settings = io.open(orig,"r")
                local content = saved_settings:read("*a")
                saved_settings:close()
                --copy the content
                local bk_file=io.open(dest,"w")
                bk_file:write(content)
                bk_file:close()
                return os.rename(settings_bk,settings_bk) and true or false
            end
        end
    else
        logger.err("Failed to find settings file at: ",settings_file)
        return false
    end
end

function AirplaneMode:turnon(airplanemode, event)
    if airplanemode == nil then return end
    logger.dbg("AirPlane Mode - executing:turning on")
    local current_config = self:backup()
    if current_config then
        -- disable plugins, wireless, all of it
        G_reader_settings:saveSetting("auto_restore_wifi",false)
        G_reader_settings:saveSetting("auto_disable_wifi",true)
        G_reader_settings:saveSetting("http_proxy_enabled",false)
        G_reader_settings:saveSetting("kosync",{autosync = false})
        G_reader_settings:saveSetting("plugins_disabled", {
            goodreads = true,
            newsdownloader = true,
            wallabag = true,
            calibre = true,
            kosync = true,
            opds = true,
            SSH = true,
            timesync = true,
        }
        G_reader_settings:saveSetting("wifi_enable_action","ignore")
        G_reader_settings:saveSetting("wifi_disable_action","turn_off")
        if Device:hasWifiManager() then
            NetworkMgr:disableWifi()
        end
        return
    else
        logger.err("Failed to create backup file and execute")
    end
end

function AirPlaneMode:turnoff()
    if airplanemode == nil then return end
    logger.dbg("AirPlane Mode - executing:turning on")
    local prev_config = if os.rename(settings_bk,settings_bk) then true else false
    if prev_config == true then
        os.rename(settings_bk,settings_file)
        -- restart koreader with refreshed settings
        UIManager:broadcastEvent(Event:new("Restart"))
    end
end


function AirPlaneMode:addToMainMenu(menu_items)
    menu_items.airplanemode = {
        text = _("AirPlane Mode"),
        sub_item_table = {
            {
                text_func = function()
                    if airplanemode = true then
                        return _("Turn off")
                    else
                        return _("Turn on")
                    end
                end,
                separator = true,
                callback = function()
                    if not airplanemode == true then
                        AirPlaneMode:turnon()
                    else
                        AirPlaneMode:turnoff()
                    end
                end,
            },
        }
    }
end




function AirPlaneMode:purge()
    if self.settings_bk then
        os.remove(self.settings_bk)
    end
    return self
end
