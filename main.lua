local init = require("init")

local main = {}

function main.start(options)
    local manager = init.create(options)
    manager:open("LoginPanel", options.params)
    return manager
end

return main
