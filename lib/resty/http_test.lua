local tb    = require "resty.iresty_test"
local http = require("resty.http_simple")
local cjson = require("cjson")

tb.save_data = {}

function _G.trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function _G.eval(str)
	local code, err = loadstring(str)
	if code == nil then
		error(err)
	end
	return code()
end

function _G.get_save_data(section_name)
	return tb.save_data[section_name]
end

local function split_simple(s, delimiter)
    local result = {};
    for match in string.gmatch(s, "[^"..delimiter.."]+") do
        table.insert(result, match);
    end
    return result;
end

function _G.split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local function startswith(str,startstr)
   return startstr=='' or string.sub(str,1, string.len(startstr))==startstr
end

local methods = {GET=true, POST=true}

local function request_parse(raw_args, current_section)
	if current_section.funcs then 
		local request = table.concat(raw_args, '\n')
		if current_section.funcs and request then
			for i, func in ipairs(current_section.funcs) do  
				request = func(request)
			end
		end
		raw_args =split(request, '\n')
	end

	local req_line = raw_args[1]
	local arr = split(req_line, ' ')
	if #arr ~= 2 then 
		error("invalid request line: " .. req_line)
	end
	local method = arr[1]
	if methods[method] == nil then 
		error("unexpected http method: " .. method)
	end
	local args = {}
	args.method = method
	args.uri = trim(arr[2])
	if method == 'POST' then
		table.remove(raw_args, 1)		
		args.body = table.concat(raw_args, '\n')
	end

	return args
end

local function more_headers_parse(raw_args, current_section)
	local headers = {}
	for i, line in ipairs(raw_args) do 
		local arr = split(line, ':')
		if #arr ~= 2 then 
			assert("invalid header:" .. line)
		end
		headers[arr[1]]=trim(arr[2])
	end
	
	return headers
end

local function error_code_parse(raw_args, current_section)
	if current_section.funcs then 
		local error_code = table.concat(raw_args, '\n')
		if current_section.funcs and error_code then
			for i, func in ipairs(current_section.funcs) do  
				error_code = func(error_code)
			end
		end
		raw_args ={error_code}
	end

	assert(#raw_args ==1, "invalid error_code lines: " .. #raw_args)
	local error_code = tonumber(raw_args[1])
	if error_code == nil then
		assert("Invalid error_code:" .. raw_args[1])
	end
	return error_code	
end

local function response_body_parse(raw_args, current_section)
	local expected_body = table.concat(raw_args, '\n')
	if current_section.funcs and expected_body then
		for i, func in ipairs(current_section.funcs) do  
			expected_body = func(expected_body)
		end
	end
	return expected_body
end


local function response_body_filter_parse(raw_args, current_section)
	-- TODO: 验证函数合法性。
	local functions = {}
	for i, func in ipairs(raw_args) do 
		func = trim(func)
		if func ~= "" then 
			local f = _G[func]
			if f == nil then 
				error("global function [" .. func .. "] not found!")
			end
			table.insert(functions, f)
		end
	end
	return functions
end

local function response_body_save_parse(raw_args, current_section)
	return true
end

-- TODO: timeout指令支持。
local directives = {
	request = {parse=request_parse},
	more_headers = {parse=more_headers_parse},
	error_code = {parse=error_code_parse},
	response_body = {parse=response_body_parse},
	response_body_filter = {parse=response_body_filter_parse},
	response_body_save = {parse=response_body_save_parse},
}

local function args_proc(current_section)
	if current_section.raw_args then
		local secinfo = current_section.secinfo
		if secinfo.parse then 
			current_section.args = secinfo.parse(current_section.raw_args, current_section)
		else
			current_section.args = current_section.raw_args
		end
		current_section.raw_args = nil
	end
	current_section.secinfo = nil
end

local function get_func_by_name(arr)
	local funcs = {}
	for i, func in ipairs(arr) do 
		local obj_funcs = split_simple(func, '%.')
		local OBJ = _G
		local f = nil
		for i, name in ipairs(obj_funcs) do 
			if i == #obj_funcs then 
				f = OBJ[name]
			else 
				OBJ = OBJ[name]
			end
			if OBJ == nil then 
				break
			end
		end
		-- local f = _G[func]
		if f == nil then 
			error("global function [" .. func .. "] not found!")
		end
		table.insert(funcs, f)
	end
	return funcs
end

local function block_parse(block, block_pattern)
	local lines = nil
	if type(block) == 'table' then 
		lines = block
	else
		lines = split(block, "\n")
	end
	local sections = {}
	local current_section = nil
	for i, line in ipairs(lines) do 
		if startswith(line, block_pattern) then 
			local section = trim(string.sub(line, #block_pattern + 1))
			
			if current_section then
				--sections[current_section.section_name] = current_section.content
				table.insert(sections, current_section)
			end
			current_section = {section_name=section}
		else
			if current_section then 
				if current_section.content == nil then 
					current_section.content = {}
				end 
				table.insert(current_section.content, line)
			end
		end
		if i == #lines and current_section then 
			--sections[current_section.section_name] = current_section.content
			table.insert(sections, current_section)
		end
	end
	-- ngx.say(cjson.encode(sections))
	return sections
end

local function section_parse(block)
	local raw_sections =  block_parse(block, "--- ")
	local sections = {}
	for _, section_info in ipairs(raw_sections) do 
		local section = section_info.section_name
		local content = section_info.content
		local arr = split(section, ' ')
		local section_name = trim(arr[1])
		local secinfo = directives[section_name]
		if secinfo == nil then 
			error("unexpected section : " .. section_name)
		end
		local current_section = {section_name=section_name, secinfo=secinfo}
		if #arr > 1 then 
			table.remove(arr, 1)					
			current_section.funcs = get_func_by_name(arr)
		end
		current_section.raw_args = content
		args_proc(current_section)
		sections[current_section.section_name] = current_section
	end
	return sections
end

local function short_str(str, len)
	if str == nil then 
		return nil
	end 
	if #str <= len then 
		return str 
	else
		return string.sub(str, 1, len-3) .. "..."
	end
end

local function response_check(testname, req_params,  res)
	-- Check Http Code
	local expected_code = 200
	if req_params.error_code and req_params.error_code.args then 
		expected_code = req_params.error_code.args
	end
	if res.status ~= expected_code then 
		error("expected error_code [" .. expected_code .. "], but got [" .. res.status .. "]")
	end

	local expected_body = ''
	if req_params.response_body and req_params.response_body.args then 
		expected_body = req_params.response_body.args
	end
	local rsp_body = res.body

	if req_params.response_body_save and req_params.response_body_save.args then
		tb.save_data[testname] = rsp_body
	end
	if rsp_body and req_params.response_body_filter and req_params.response_body_filter.args then 
		for i, filter in ipairs(req_params.response_body_filter.args) do 
			if rsp_body then 
				rsp_body = filter(rsp_body)
			end
		end
	end
	if rsp_body ~= expected_body then 
		-- TODO: 更准确定位差异点。
		-- ngx.log(ngx.ERR, "expected response_body[[" .. expected_body .. "]]")
		-- ngx.log(ngx.ERR, "             but got  [[" .. rsp_body .. "]]")
		error("expected response_body [" .. short_str(expected_body,1024) 
				.. "], but got [" .. short_str(rsp_body, 1024) .. "]")
	end

	return true
end


-- TODO: check
local function section_check(section)
	-- request check, args, method, url
	if section.request == nil then 
		error("'--- request' missing!")
	end
	if section.error_code == nil and section.response_body == nil then 
		error("'--- error_code' or '--- response_body' missing!")
	end
	-- error_code check.
end


local function http_test(testname, block, server)
	local req_params = section_parse(block)
	section_check(req_params)

	local request = req_params.request
	local method = request.args.method
	local uri = nil
	if startswith(request.args.uri, "http://") then 
		uri = request.args.uri
	else
		uri = server .. request.args.uri
	end

	local more_headers = req_params.more_headers
	local myheaders = http.new_headers()
	-- local timeout = req_params.args or 1000*10
	if more_headers then 
		for key, value in pairs(more_headers.args) do 
			myheaders[key] = value
		end
	end

	local res, err, debug_sql
	if method == "GET" then 
		res, err, debug_sql = http.http_get(uri, myheaders, timeout)
	elseif method == "POST" then 
		res, err, debug_sql = http.http_post(uri, request.args.body, myheaders, timeout)
	else
		error("unexpected http method: " .. method)
	end
	if res == nil then 
		error("request to '" .. uri .. "' failed! err:" .. tostring(err))
	end

	return response_check(testname, req_params, res)
end

function tb:init()
	local testcases = block_parse(self.blocks, "=== ")
	local test_inits = {}

	for _, testcase in ipairs(testcases) do 
		local testname = testcase.section_name
		local httptest = testcase.content
		
		table.insert(test_inits, testname)
		self[testname] =  function()
			http_test(testname, httptest, self.server)
		end
	end
	self._test_inits = test_inits
end

return tb