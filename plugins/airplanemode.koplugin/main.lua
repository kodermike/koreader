local Dispatcher = require("dispatcher")
local Device = require("device")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local airplanemode = false

-- establish the main settings file
local DataStorage = require("datastorage")

local AirPlaneMode = WidgetContainer:extend{
    name = "airplanemode",
    is_doc_only = false,
}

logger.dbg("we got past setting the widgetcontainer")

function AirPlaneMode:onDispatcherRegisterActions()
    Dispatcher:registerAction("airplanemode_action", { category="none", event="SwitchAirPlane", title=_("AirPlane Mode"), general=true,})
end

function AirPlaneMode:init()
    logger.dbg("Registering dispatch...")
    self:onDispatcherRegisterActions()
    logger.dbg("Registering menu...")
    self.ui.menu:registerToMainMenu(self)
   -- logger.dbg("Switch time")
   -- self:onSwitchAirPlane()
end

function AirPlaneMode:onSwitchAirPlane()
    ----------
    if G_reader_settings == nil then
        G_reader_settings = require("luasettings"):open(settings_file)
    end

    self.settings_file = DataStorage:getDataDir().."/settings.reader.lua"
    self.settings_bk = DataStorage:getDataDir().."/settings.reader.lua.current"

    -- test we can see the real settings file.
    if os.rename(self.settings_file,self.settings_file) then
        logger.dbg("Settings file confirmed to exist")
    else
        logger.err("Settings file not found! Abort!")
    end

    -- check if we currently have a backup of our settings running
    logger.dbg("Checking if we already have a backup config", self.settings_bk)
    self.settings_bk_exists = false
    if os.rename(self.settings_bk,self.settings_bk) then
        self.settings_bk_exists = true
    end

    -- also verify if the airplanemode flag is set. we will use this to decide if something is funky
    local airplanemode_active = false
    if G_reader_settings:isTrue("airplanemode") then airplanemode_active = true end

    logger.dbg("we checked for an active setting",airplanemode_active)

    ---------
    if settings_bk_exists == true and airplanemode_active == true then
        airplanemode = true
        AirPlaneMode:turnoff()
    elseif settings_bk_exists == false and airplanemode_active == false then
        airplanemode = false
        AirPlaneMode:turnon()
    else
        logger.dbg("Failed to determine if bk exists or mode is active")
    end
end

function AirPlaneMode:backup(cur_file,bak_file)
    -- settings_file = settings_file or self.settings_file
    logger.dbg("we have a settings file, "cur_file)
    if os.rename(cur_file,cur_file) then
        if lfs.attributes(cur_file, "mode") == "cur_file" then
            -- lifted straight from reader.lua, including explanation. thank you lua gods
            -- As an additional safety measure (to the ffiutil.fsync* calls used in util.writeToFile),
            -- we only backup the settings_file to .old when it has not been modified in the last 60 seconds.
            -- This should ensure in the case the fsync calls are not supported
            -- that the OS may have itself sync'ed that settings_file content in the meantime.
            local mtime = lfs.attributes(cur_file, "modification")
            if mtime < os.time() - 60 then
                -- os.rename(settings_file, settings_file .. ".current")
                local orig = cur_file
                local dest = bak_file
                --open and read content file
                local saved_settings = io.open(orig,"r")
                local content = saved_settings:read("*a")
                saved_settings:close()
                --copy the content
                local bk_file=io.open(dest,"w")
                bk_file:write(content)
                bk_file:close()
                return os.rename(bak_file,bak_file) and true or false
            end
        end
    else
        logger.err("Failed to find settings file at: ",cur_file)
        return false
    end
end

function AirPlaneMode:turnon()
    logger.dbg("AirPlane Mode - executing:turning on")
    local current_config = self:backup(self.settings_file, self.settings_bk)
    if current_config then
        -- mark airplane as active
        G_reader_settings:saveSetting("airplanemode",true)
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
        })
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
    logger.dbg("AirPlane Mode - executing:turning off")
    if os.rename(self.settings_bk,self.settings_bk) then
        os.rename(self.settings_bk,self.settings_file)
        -- restart koreader with refreshed settings
        UIManager:broadcastEvent(Event:new("Restart"))
    end
end


function AirPlaneMode:addToMainMenu(menu_items)
    menu_items.airplanemode = {
        text = _("AirPlane Mode"),
        sorting_hint = "more_tools",
        callback = function()
            if not airplanemode == true then
                AirPlaneMode:turnon()
            else
                AirPlaneMode:turnoff()
            end
        end,
    }
end

return AirPlaneMode
