local lru_middware = require "middware"
local lplugin = lru_middware.plugins

local plugins = {
    ["geoip"] = true,
}

local _M = {}

function _M.load_plugins()
    for plugin_name, if_load in pairs(plugins) do
        if if_load then
            ngx.ctx[plugin_name] = require("plugins."..plugin_name)
            lplugin:set(plugin_name, ngx.ctx[plugin_name])
        end
    end
end

function _M.unload_plugin(plugin_name)
    if plugin_name ~= nil then
        ngx.ctx[plugin_name] = nil
        lp = lplugin:get(plugin_name)
        package.loaded[plugin_name] = nil
        if lp ~= nil then
           lplugin:delete(plugin_name) 
        end
    end
end

function _M.get_loaded_plugins()
    local p = {}
    for plugin_name, if_load in pairs(plugins) do
        if if_load then
            table.insert(p, plugin_name)
        end
    end
    return p
end

return _M
