-- Main configuration of Knot Resolver.
-- Refer to manual: https://knot-resolver.readthedocs.io/en/latest/daemon.html#configuration

local lfs = require('lfs')

function find_files(dir, pattern)
    local files = {}
    if lfs.attributes(dir) ~= nil then
        for entry in lfs.dir(dir) do
            if entry:match(pattern) ~= nil then
                table.insert(files, dir .. '/' .. entry)
            end
        end
        table.sort(files)
    end
    return files
end

-- load configuration from /etc/kres.d/*.conf
local files = find_files(env.KRESD_CONF_DIR .. '/kresd.conf.d', '.conf$')
for i = 1, #files do
    local file_path = files[i]
    log('Loading configuration from %s\n', file_path)
    dofile(file_path)
end

modules.load('hints')
hints.add_hosts('/etc/hosts')