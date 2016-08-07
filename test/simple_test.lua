local cjson = require("cjson")
local ht = require "resty.http_test"
local tb    = require "resty.iresty_test"

_G.test_tel = "10022224444"
function username()
	return "jie123108"
end
local function get_save_data_as_json(name)
	local save_data = get_save_data(name)
	return cjson.decode(save_data or '{}')
end
function get_sms_code()
	local jso = get_save_data_as_json("Test SMS Send")
	return tostring(jso.data.code)
end

function get_token()
	local jso = get_save_data_as_json("Test Reg OK")
	return tostring(jso.data.token)
end

function get_user_id()
	local jso = get_save_data_as_json("Test Reg OK")
	return tostring(jso.data.user_id)
end

local blocks = [[
=== Test SMS Send
--- request
POST /account/sms/send
{"tel": "`test_tel`"}
--- more_headers
Host: test.com
--- error_code
200
--- response_body json_fmt
{"data":{"code":"###"}, "ok": true}
--- response_body_filter
json_fmt
--- response_body_save

=== Test Reg Code Invalid
--- request
POST /account/reg
{"code": "0000", "tel": "`test_tel`","username": "`username()`"}
--- error_code
200
--- response_body json_fmt
{"reason": "ERR_CODE_INVALID", "ok": false}
--- response_body_filter
json_fmt

=== Test Reg OK
--- request
POST /account/reg
{"code": "`get_sms_code()`", "tel": "`test_tel`","username": "`username()`"}
--- error_code
200
--- response_body json_fmt
{"data": {"token": "###", "user_id": "###"}, "ok": true}
--- response_body_filter
json_fmt
--- response_body_save

=== Test Userinfo Get Token Invalid
--- request
GET /account/user_info/get
--- more_headers
X-Token: Invalid-Token
--- error_code
401
--- response_body json_fmt
{"reason": "ERR_TOKEN_INVALID", "ok": false}
--- response_body_filter
json_fmt

=== Test Userinfo Get OK
--- request
GET /account/user_info/get
--- more_headers
X-Token: `get_token()`
--- error_code
200
--- response_body json_fmt_not_replace
{"ok": true, "data": {"user_id": "`get_user_id()`", "username": "`username()`"}}
--- response_body_filter
json_fmt_not_replace


]]

local function table_format(jso, replace_fields)
	local keys = {}	
	for k, _ in pairs(jso) do 
		table.insert(keys, k)
	end
	table.sort(keys)
	local lines = {}
	for _, k in ipairs(keys) do 
		local value = jso[k]
		if type(value) == 'table' then 
			value = table_format(value, replace_fields)
		end
		if replace_fields and replace_fields[k] then
			value = '###'
		end
		table.insert(lines, k .. ":" .. tostring(value))
	end
	return table.concat(lines, '\n')
end

function json_fmt(s)
	if s == nil or s == '' then 
		return ''
	end
	local jso  = cjson.decode(s)
	local replace_fields = {code=true, token=true, user_id=true}
	if jso then 
		return table_format(jso, replace_fields)
	else
		return s 
	end
end

function json_fmt_not_replace(s)
	if s == nil or s == '' then 
		return ''
	end
	local jso  = cjson.decode(s)
	if jso then 
		return table_format(jso)
	else
		return s 
	end
end
-- units test
local test = ht.new({unit_name="test-base", blocks = blocks, server="http://127.0.0.1:100"})
test:run()