local Dispatcher = require("dispatcher")
local Device = require("device")
local LuaSettings = require("luasettings")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local ffiutil = require("ffi/util")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local airplanemode = false

-- establish the main settings file
local DataStorage = require("datastorage")

local AirPlaneMode = WidgetContainer:extend{
    name = "airplanemode",
    is_doc_only = false,
}

local function isFile(filename)
    if lfs.attributes(filename, "mode") == "file" then
        logger.dbg("AirPlane Mode - found a file ",filename)
        return true
    end
    logger.dbg("AirPlane Mode - did not find a file ",filename)
    return false
end

function AirPlaneMode:onDispatcherRegisterActions()
    Dispatcher:registerAction("airplanemode_action", { category="none", event="SwitchAirPlane", title=_("AirPlane Mode"), general=true,})
end

function AirPlaneMode:init()
    logger.dbg("AirPlane Mode - Registering dispatch...")
    self:onDispatcherRegisterActions()
    logger.dbg("AirPlane Mode - Registering menu...")
    self.ui.menu:registerToMainMenu(self)
end

function AirPlaneMode:backup(settings_file,backup_file)
    -- settings_file = settings_file or self.settings_file
    logger.dbg("AirPlane Mode - we have a settings file, ",settings_file)
    if isFile(settings_file) then
        if isFile(self.settings_bk) then
            os.remove(self.settings_bk)
        end
        ffiutil.copyFile(settings_file,backup_file )
        return isFile(backup_file) and true or false
    else
        logger.err("AirPlane Mode [ERROR] - Failed to find settings file at: ",settings_file)
        return false
    end
end

function AirPlaneMode:turnon(settings_file,backup_file)
    logger.dbg("AirPlane Mode - executing:turning on")
    logger.dbg("AirPlane Mode [turning on] settings: ", settings_file)
    logger.dbg("AirPlane Mode [turning on] backup: ", backup_file)
    local current_config = self:backup(settings_file,backup_file)
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
        logger.dbg("AirPlane Mode - restarting koreader with disabled settings")
        self.settings_bk_exists = true
        self.airplanemode_active = true
        if Device:canRestart() then
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("KOReader needs to be restarted to finish enabling AirPlane Mode."),
                ok_text = _("Restart"),
                ok_callback = function()
                        UIManager:restartKOReader()
                end,
            })
        else
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("You will need to restart KOReader to finish enabling AirPlane Mode."),
                ok_text = _("OK"),
                ok_callback = function()
                    UIManager:quit()
                end,
            })
        end
    else
        logger.err("AirPlane Mode [ERROR] - Failed to create backup file and execute")
    end
end

function AirPlaneMode:turnoff(settings_file,backup_file)
    logger.dbg("AirPlane Mode - executing:turning off and copying ",backup_file,settings_file)
    logger.dbg("AirPlane Mode - restoring our backup")

    local file_path = settings_file or DataStorage:getDataDir() .. "/settings.reader.lua"
    local new = AirPlaneMode:extend{
        file = file_path,
    }
    local ok, stored


    ok, stored = pcall(dofile, new.file..".airplane")
    if ok and stored then
        new.data = stored
        logger.dbg("AirPlane Mode - writing data to ", new.file)
        util.writeToFile(dump(new.data, nil, true), new.file, true, true, true)

        G_reader_settings:saveSetting("airplanemode",false)
        -- restart koreader with refreshed settings
        logger.dbg("AirPlane Mode - restarting koreader with original settings")
        self.airplanemode_active = false
        UIManager:show(ConfirmBox:new{
            dismissable = false,
                text = _("AirPlane Mode disabled."),
                ok_text = _("OK"),
                ok_callback = function()
                    UIManager:close(self)
                end,
        })
    else
        logger.err("AirPlane Mode [ERROR] - unable to find backup config!", backup_file)
    end
end

function AirPlaneMode:addToMainMenu(menu_items)
    local rootpath = lfs.currentdir()
    self.settings_file = rootpath.."/settings.reader.lua"
    self.settings_bk = rootpath.."/settings.reader.lua.airplane"
    menu_items.airplanemode = {
        text = _("AirPlane Mode Toggle"),
        sorting_hint = "more_tools",
        callback = function()
            -- test we can see the real settings file.
            logger.dbg("AirPlane Mode - checking if this is a file ", self.settings_file)
            if isFile(self.settings_file) then
                logger.dbg("AirPlane Mode - Settings file confirmed to exist", self.settings_file)
            else
                logger.err("AirPlane Mode [ERROR] - Settings file not found! Abort!", self.settings_file)
            end

            -- check if we currently have a backup of our settings running
            logger.dbg("AirPlane Mode - Checking if we already have a backup config", self.settings_bk)
            self.settings_bk_exists = false
            if isFile(self.settings_bk) then
                self.settings_bk_exists = true
            end

            -- also verify if the airplanemode flag is set. we will use this to decide if something is funky
            self.airplanemode_active = false
            if G_reader_settings:readSetting("airplanemode") then
                self.airplanemode_active = G_reader_settings:readSetting("airplanemode")
            end
            logger.dbg("AirPlane Mode - we checked for an active setting",self.airplanemode_active)

            ---------
            if self.settings_bk_exists == true and self.airplanemode_active == true then
                logger.dbg("AirPlane Mode - we're sending the settings file ",self.settings_file)
                logger.dbg("AirPlane Mode - we're sending the backup file ",self.settings_bk)
                --airplanemode = true
                self:turnoff(self.settings_file, self.settings_bk)
            elseif self.airplanemode_active == false then
                --airplanemode = false
                logger.dbg("AirPlane Mode - we're sending the settings file ",self.settings_file)
                logger.dbg("AirPlane Mode - we're sending the backup file ",self.settings_bk)
                self:turnon(self.settings_file, self.settings_bk)
            else
                -- chaos. missing backup file. tell the user and cry.
                UIManager:show(ConfirmBox:new{
                    dismissable = false,
                    text = _("Oh no! You have AirPlane Mode enabled, but your original configuration is missing. Please consider filing a bug report!"),
                    ok_text = _("OK"),
                    ok_callback = function()
                        UIManager:quit()
                    end,
                })
            end
        end,
    }
end

return AirPlaneMode
