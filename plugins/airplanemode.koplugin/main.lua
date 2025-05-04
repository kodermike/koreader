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
local lfs = require("libs/libkoreader-lfs")
local airplanemode = false

-- establish the main settings file
local DataStorage = require("datastorage")

local AirPlaneMode = WidgetContainer:extend{
    name = "airplanemode",
    is_doc_only = false,
}
-- also verify if the airplanemode flag is set. we will use this to decide if something is funky
local airplanemode_active = G_reader_settings:isTrue("airplanemode")
logger.dbg("AirPlane Mode - we checked for an active setting",airplanemode_active)

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


     ----------
    -- if G_reader_settings == nil then
    --    G_reader_settings = require("luasettings"):open(self.settings_file)
    -- end

    logger.dbg("AirPlane Mode - Registering menu...")
    self.ui.menu:registerToMainMenu(self)
   -- logger.dbg("Switch time")
   -- self:onSwitchAirPlane()
end


function AirPlaneMode:onSwitchAirPlane()
    self.settings_file = DataStorage:getDataDir().."/settings.reader.lua"
    self.settings_bk = DataStorage:getDataDir().."/settings.reader.lua.airplane"

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
    ---------
    if self.settings_bk_exists == true and airplanemode_active == true then
        airplanemode = true
        AirPlaneMode:turnoff(self.settings_file, self.settings_bk)
    elseif self.settings_bk_exists == false and airplanemode_active == false then
        airplanemode = false
        logger.dbg("AirPlane Mode - we're sending the settings file ",self.settings_file)
        logger.dbg("AirPlane Mode - we're sending the backup file ",self.settings_bk)
        AirPlaneMode:turnon(self.settings_file, self.settings_bk)
    else
        logger.dbg("AirPlane Mode - Failed to determine if bk exists or mode is active")
    end
end

function AirPlaneMode:backup(settings_file,backup_file)
    -- settings_file = settings_file or self.settings_file
    logger.dbg("AirPlane Mode - we have a settings file, ",settings_file)
    if isFile(settings_file) then

        -- lifted straight from reader.lua, including explanation. thank you lua gods
        -- As an additional safety measure (to the ffiutil.fsync* calls used in util.writeToFile),
        -- we only backup the settings_file to .old when it has not been modified in the last 60 seconds.
        -- This should ensure in the case the fsync calls are not supported
        -- that the OS may have itself sync'ed that settings_file content in the meantime.
        -- local mtime = lfs.attributes(settings_file, "modification")
        -- if mtime < os.time() - 60 then
            ffiutil.copyFile(settings_file,backup_file )
            -- MPC if this works remove below block
        --    local orig = settings_file
        --    local dest = backup_file
        --    --open and read content file
        --    local saved_settings = io.open(orig,"r")
        --    local content = saved_settings:read("*a")
        --    saved_settings:close()
        --    --copy the content
        --    local bk_file=io.open(dest,"w")
        --    bk_file:write(content)
        --    bk_file:close()
            return isFile(backup_file) and true or false

        -- end
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
    logger.dbg("AirPlane Mode - executing:turning off")
    if isFile(backup_file) then
        logger.dbg("AirPlane Mode - restoring our backup")
        ffiutil.copyFile(backup_file,settings_file)
        -- remove backup file
        local ok, err = os.remove(backup_file)
        if ok then
            logger.dbg("AirPlane Mode - removed backup file")
        else
            logger.err("AirPlane Mode - file not removed!", err)
        end
        G_reader_settings:saveSetting("airplanemode",false)
        -- restart koreader with refreshed settings

        logger.dbg("AirPlane Mode - restarting koreader with original settings")
        if Device:canRestart() then
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("KOReader needs to be restarted to finish disabling AirPlane Mode."),
                ok_text = _("Restart"),
                ok_callback = function()
                        UIManager:restartKOReader()
                end,
            })
        else
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("You will need to restart KOReader to finish disabling AirPlane Mode."),
                ok_text = _("OK"),
                ok_callback = function()
                    UIManager:quit()
                end,
            })
        end
    else
        logger.err("AirPlane Mode [ERROR] - unable to find backup config!", backup_file)
    end
end


function AirPlaneMode:addToMainMenu(menu_items)
    menu_items.airplanemode = {
        text = _("AirPlane Mode"),
        sorting_hint = "more_tools",
        callback = function()
            AirPlaneMode:onSwitchAirPlane()
            -- if not airplanemode == true then
            --    AirPlaneMode:turnon()
            -- else
            --    AirPlaneMode:turnoff()
            -- end
        end,
    }
end

return AirPlaneMode
