local messager = require 'share.messager'
local core = require 'backend.sandbox_core'
local builder = require 'map-builder'
local plugin = require 'share.plugin'
local lang = require 'share.lang'
local get_report = require 'share.report'
local check_lni_mark = require 'share.check_lni_mark'
local unpack_setting = require 'backend.unpack_setting'
local w2l = core()
local root = fs.current_path()
local setting
local input_ar
local output_ar

local report = {}
local messager_report = messager.report
function messager.report(type, level, content, tip)
    messager_report(type, level, content, tip)
    local name = level .. type
    if not report[name] then
        report[name] = {}
    end
    table.insert(report[name], {content, tip})
end

local function default_output(input)
    if w2l.setting.target_storage == 'dir' then
        if fs.is_directory(input) then
            return input:parent_path() / (input:filename():string() .. '_' .. w2l.setting.mode)
        else
            return input:parent_path() / input:stem():string()
        end
    elseif w2l.setting.target_storage == 'mpq' then
        if fs.is_directory(input) then
            return input:parent_path() / (input:filename():string() .. '.w3x')
        else
            return input:parent_path() / (input:stem():string() .. '_' .. w2l.setting.mode .. '.w3x')
        end
    end
end

local function exit(report)
    local err = 0
    local warn = 0
    for k, t in pairs(report) do
        if k:sub(1, 1) == '1' then
            err = #t
        elseif k:sub(1, 1) == '2' then
            warn = #t
        end
    end
    if err > 0 then
        messager.exit('error', lang.script.ERROR_COUNT:format(err, warn))
    elseif warn > 0 then
        messager.exit('warning', lang.script.ERROR_COUNT:format(err, warn))
    else
        messager.exit('success', lang.script.ERROR_COUNT:format(err, warn))
    end
    return err, warn
end

local function get_io_time(map, file_count)
    local io_speed = map:get_type() == 'mpq' and 30000 or 10000
    local io_rate = math.min(0.3, file_count / io_speed)
    return io_rate
end

return function (mode)
    w2l:set_messager(messager)
    w2l.messager.text(lang.script.INIT)
    w2l.messager.progress(0)

    fs.remove(root:parent_path() / 'log' / 'report.log')

    setting = unpack_setting(w2l, mode)

    if setting.mode == 'slk' then
        messager.title 'Slk'
    elseif setting.mode == 'obj' then
        messager.title 'Obj'
    elseif setting.mode == 'lni' then
        messager.title 'Lni'
    end

    messager.text(lang.script.OPEN_MAP)
    local err
    input_ar, err = builder.load(setting.input)
    if not input_ar then
        w2l:failed(err)
    end
    if input_ar:get_type() == 'mpq' and not input_ar:get '(listfile)' then
        w2l:failed(lang.script.UNSUPPORTED_MAP)
    end

    if input_ar:get '.w3x' then
        if check_lni_mark(input_ar:get '.w3x') then
            w2l.input_mode = 'lni'
        else
            w2l:failed(lang.script.UNSUPPORTED_LNI_MARK)
        end
    end
    
    w2l:set_setting(setting)
    
    w2l.input_ar = input_ar
    output = setting.output or default_output(setting.input)
    setting.output = output
    if w2l.setting.target_storage == 'dir' then
        if not fs.exists(output) then
            fs.create_directories(output)
        end
    end
    output_ar, err = builder.load(output, 'w')
    if not output_ar then
        w2l:failed(err)
    end
    w2l.output_ar = output_ar

    local slk = {}
    local file_count = input_ar:number_of_files()
    local input_rate = get_io_time(input_ar, file_count)
    local output_rate = get_io_time(output_ar, file_count)
    local frontend_rate = (1 - input_rate - output_rate) * 0.4
    local backend_rate = (1 - input_rate - output_rate) * 0.6

    messager.text(lang.script.CHECK_PLUGIN)
    plugin(w2l, function(source, plugin)
        w2l:add_plugin(source, plugin)
    end)
    
    messager.text(lang.script.LOAD_FILE)
    w2l.progress:start(input_rate)
    input_ar:search_files(w2l.progress)
    w2l.progress:finish()
    
    messager.text(lang.script.LOAD_OBJECT)
    w2l.progress:start(input_rate + frontend_rate)
    w2l:frontend(slk)
    w2l.progress:finish()
    
    messager.text(lang.script.DO_CONVERT)
    w2l.progress:start(input_rate + frontend_rate + backend_rate)
    w2l:backend(slk)
    w2l.progress:finish()
    
    messager.text(lang.script.SAVE_FILE)
    w2l.progress:start(1)
    builder.save(w2l, slk.w3i, input_ar, output_ar, w2l.input_proxy, w2l.output_proxy)
    w2l.progress:finish()
    
    fs.create_directories(root:parent_path() / 'log')
    local clock = os.clock()
    messager.text(lang.script.FINISH:format(clock))
    local err, warn = exit(report)
    io.save(root:parent_path() / 'log' / 'report.log', get_report(w2l, report, setting, clock, err, warn))
end
