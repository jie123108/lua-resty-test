# Name
lua-resty-test is Ngx_lua test frame based on Openresty


#Description
This Lua library is a test frame for test your ngx_lua source or other server(tcp or udp):

http://wiki.nginx.org/HttpLuaModule

Note that at least ngx_lua 0.5.14 or ngx_openresty 1.2.1.14 is required.

#Synopsis


```
 # you do not need the following line if you are using
    # the ngx_openresty bundle:
    lua_package_path "/path/to/lua-resty-test/lib/?.lua;;";

    # A lua_shared_dict named cache_ngx is required by test:bench_run
    lua_shared_dict cache_ngx 100k;

    server {

        listen 8080;

        server_name 127.0.0.1;

        error_log /path/to/error.log;

        location /test {
            content_by_lua '
                	local tb    = require "resty.iresty_test"
					local test = tb.new({unit_name="bench_example"})

					function tb:init(  )
					    self:log("init complete")
					end

					function tb:test_00001(  )
					    error("invalid input")
					end

					function tb:atest_00002()
					    self:log("never be called")
					end

					function tb:test_00003(  )
					   self:log("ok")
					end

					-- units test
					test:run()
					
					-- bench units test
					test:bench_run()
            ';
        }
    }
```

Run test case:

```
curl "http://127.0.0.1:8080/test"
```

The output result:

```
0.000  [bench_example] unit test start
0.000  [bench_example] init complete
0.000    \_[test_00001] fail ...de/nginx/main_server/test_case_lua/unit/test_example.lua:9: invalid input
0.000    \_[test_00003] ↓ ok
0.000    \_[test_00003] PASS
0.000  [bench_example] unit test complete
0.000  [bench_example] !!!BENCH TEST START!!
0.484  [bench_example] succ count:	 100001	QPS:	 206613.65
0.484  [bench_example] fail count:	 100001 	QPS:	 206613.65
0.484  [bench_example] loop count:	 100000 	QPS:	 206611.58
0.484  [bench_example] !!!BENCH TEST ALL DONE!!!
```

#Synopsis-Http
### http server config for test (see in lua-resty-test/test/conf/nginx.conf)
```nginx
    init_worker_by_lua '
        cjson = require("cjson")
        -- 临时存储注册用户信息，登录信息等。(只有在worker_processes配置为1时，才能保证运行正常)
        cache = {}
    ';
    
    server {
        listen 100;
        server_name test.com;
        location = /account/sms/send { 
            # request body: {tel: "电话号码"}
            content_by_lua '
                ngx.req.read_body()
                local body = ngx.req.get_body_data() 
                local jso = cjson.decode(body)
                -- TODO: 发送短信
                local code = "1984"
                cache["cd:" .. tostring(code)] = jso.tel
                -- 返回Code，用于单元测试。
                local t = {ok=true, data={code=code}}
                ngx.say(cjson.encode(t));
            ';  
        }

        location = /account/reg {
            # request body: {code: "验证吗", tel: "电话号码"，username: "用户名"}
            content_by_lua '
                -- 注册帐号
                ngx.req.read_body()
                local body = ngx.req.get_body_data() 
                local jso = cjson.decode(body)
                local key = "cd:" .. tostring(jso.code)
                local tel = cache[key]
                if tel == nil or tel ~= jso.tel then 
                    ngx.say(cjson.encode({ok=false, reason="ERR_CODE_INVALID"}))
                    ngx.exit(0)
                end
                local user_id=100
                local token="Tk-for-Login"
                local key = "tk:" .. token
                cache[key] = cjson.encode({user_id=user_id, username=jso.username})
                ngx.say(cjson.encode({ok=true, data={token=token, user_id=user_id}}))                
            ';  
        }   
        location = /account/user_info/get {
            # token需要通过请求头(X-Token)传递。
            content_by_lua '
                local headers = ngx.req.get_headers()
                local token = headers["X-Token"]
                if token == nil or cache["tk:" .. token] == nil then 
                    ngx.status = 401
                    ngx.say(cjson.encode({ok=false, reason="ERR_TOKEN_INVALID"}))
                    ngx.exit(0)
                end
                local key = "tk:" .. token
                local user_info = cjson.decode(cache[key])

                ngx.say(cjson.encode({ok=true, data=user_info}))
            ';  
        }   
    }   
```

### Http Test(see in lua-testy-test/test/simple_test.lua)
```lua
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
```

### The output (Run As: /path/to/resty -I /path/to/lua-resty-test/lib /path/to/lua-resty-test/test/simple_test.lua)
```
0.000  [test-base] unit test start 
0.132    |--[Test SMS Send] PASS 
0.132    |--[Test Reg Code Invalid] PASS 
0.132    |--[Test Reg OK] PASS 
0.132    |--[Test Userinfo Get Token Invalid] PASS 
0.132    |--[Test Userinfo Get OK] PASS 
0.132  [test-base] unit test complete 
```

#Author
Yuansheng Wang "membphis" (王院生) membphis@gmail.com, 360 Inc.

#Copyright and License
This module is licensed under the BSD license.

Copyright (C) 2012, by Zhang "agentzh" Yichun (章亦春) agentzh@gmail.com.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#See Also
* the ngx_lua module: http://wiki.nginx.org/HttpLuaModule
