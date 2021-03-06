local event = require 'ev'

local function mpq_path()
    local mt = {}
    local archive = nil
    local lang = nil
    function mt:lang(lng)
        lang = lng
    end
    function mt:open(path)
        archive = path
    end
    function mt:close(path)
        if archive == path then
            archive = nil
        end
    end
    function mt:each_path(callback)
        if lang then
            if archive then
                local buf = callback(lang .. '\\' .. archive)
                if buf then
                    return buf
                end
            end
            local buf = callback(lang)
            if buf then
                return buf
            end
        end
        if archive then
            local buf = callback(archive)
            if buf then
                return buf
            end
        end
        local buf = callback('')
        if buf then
            return buf
        end
    end
    function mt:first_path()
        if lang then
            if archive then
                return lang .. '\\' .. archive
            end
            return lang
        end
        if archive then
            return archive
        end
        return ''
    end
    return mt
end

local mt = {}

function mt:path()
    if self.mpq_path then
        return self.mpq_path
    end
    local lang = (require "i18n").get_language()
    self.mpq_path = mpq_path()
    self.mpq_path:lang(lang)
    event.on('virtual_mpq: open path', function(name)
        log.info('OpenPathAsArchive', name)
        self.mpq_path:open(name)
    end)
    event.on('virtual_mpq: close path', function(name)
        log.info('ClosePathAsArchive', name)
        self.mpq_path:close(name)
    end)
    return self.mpq_path
end

function mt:load(dir, filename)
    return self:path():each_path(function(path)
		return io.load(dir / path / filename)
	end)
end

function mt:save(dir, filename, buf)
    local path = dir / self:path():first_path() / filename
    fs.create_directories(path:parent_path())
    io.save(path, buf)
end

function mt:create_directories(dir)
    fs.create_directories(dir / self:path():first_path())
end

return mt
