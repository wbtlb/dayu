local lrucache = require "lrucache"
local tab_new = require "table.new"

local _M = {}

_M.c = lrucache.new(256)

_M.checker = lrucache.new(256)

_M.picker = lrucache.new(256)

_M.upstream_table = lrucache.new(256)

_M.ups_list = lrucache.new(1024)

_M.lbackup_list = lrucache.new(1024)

_M.plugins = lrucache.new(1024)

_M.ori_value = tab_new(0, 32)

_M.status = tab_new(0, 32)

return _M
