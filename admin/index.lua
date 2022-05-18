local ngx_re = require "ngx.re"
local cjson = require "cjson"
local plugins = require "plugins.init"
local radix = require("resty.radixtree")
local uri = ngx.var.request_uri
local service_type = ngx_re.split(uri, "/")


local rx =  radix.new({
    {
        paths = "/admin/plugin/list",
        handler = function(ctx)
            local ps = plugins.get_loaded_plugins()
            ngx.say("already loaded plugins list: "..cjson.encode(ps))
        end,
    },
    {
        paths = "/admin/plugin/load/all",
        handler = function(ctx)
            plugins.load_plugins()
            ngx.say("load finished!")
        end,
    },
    {
        paths = "/admin/plugin/unload/:name",
        metadata = "metadata /name",
    },
    {
        paths = "/admin/upstreams/list",
        handler = function(ctx)
            local tkeys = ngx.shared.ngx_ups_list:get_keys()
            for k, v in pairs(tkeys) do
                local config = ngx.shared.ngx_ups_list:get(v)
                ngx.say(config)
            end
        end
    },
    --{
    --    --paths = "/admin/plugin/load/:name",
    --    paths = "/admin/plugin/load/:name",
    --    metadata = "metadata /name",
    --}
})

--local opts = {matched = {}}
----local meta = rx:match("/name/json/id/1", opts)
--local meta = rx:match(uri, opts)
----ngx.say("match meta:", meta)
--ngx.say("matched: ", cjson.encode(opts.matched))
--local load_plugin = oopts.matched
--if load_plugin ~= nil then
--    
--end
--opts.matched = {}
----meta = rx:match("/name/json/id/", opts)
--meta = rx:match(uri, opts)
--ngx.say("match meta: ", meta)
--ngx.say("matched: ", cjson.encode(opts.matched))
local opts = {matched = {}}
local meta = rx:match(uri, opts)
local upname = opts.matched["name"]
plugins.unload_plugin(upname)
ngx.say(cjson.encode(opts.matched))


rx:dispatch(uri)
