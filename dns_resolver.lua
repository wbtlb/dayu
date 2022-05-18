local resolver = require "resty.dns.resolver"

local _M = {}

_M.__index = _M

local RFC_TYPE = {
    [1] = "A",
    [2] = "NS",
    [3] = "MD",
    [4] = "MF",
    [5] = "CNAME",
    [6] = "SOA",
    [7] = "MB",
    [8] = "MG",
    [9] = "MR",
    [15] = "MX",
    [16] = "TXT"
}

local RFC_CLASS = {
    [1] = "IN",
    [2] = "CS",
    [3] = "CH",
    [4] = "HS"
}

function _M:new(resolver_params)
    local self = {}
    setmetatable(self, _M)
    local resolver_client, err = resolver:new {
        nameservers = resolver_params.nameservers,
        retrans     = resolver_params.retrans,
        timeout     = resolver_paramstimeout
    }
    if not resolver_client then
        ngx.log(ngx.ERR, "failed to instantiate then resolver: ", err)
        return nil
    end
    self.resolver_client = resolver_client
    return self
end

function _M:query(domain)
    local answers, err, tries = self.resolver_client:query(domain, nil, {})
    if not answers then
        ngx.log(ngx.ERR, "failed to query then DNS server: ", err)
        ngx.log(ngx.ERR, "retry historie: ", table.concat(tries, "\n "))
        return
    end

    if answers.errcode then
        ngx.log(ngx.ERR, "server returned err code: ", answers.errcode, ": ", answers.errstr)
        return
    end
    
    local result = {}
    for i, ans in ipairs(answers) do
        result = {
            name = ans.name,
            value = ans.address or ans.cname,
            type = RFC_TYPE[ans.type] or "NULL",
            class = RFC_CLASS[ans.class],
            ttl = ans.ttl
        }
        --ngx.log(ngx.ERR, " ############# ", ans.name, " ", ans.address or ans.cname, " type:", ans.type, " class:", ans.class, " ttl:", ans.ttl)
    end
    return result
end

return _M
