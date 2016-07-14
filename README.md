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
### http server config (see in lua-resty-test/test/conf/nginx.conf)
```
    server {
        listen 100;
        location / { 
            content_by_lua '
                local t = {a3=99, b4=22, f="20", b0="bb"}
                local cjson = require("cjson")
                ngx.say(cjson.encode(t));
            ';  
        }   
        location = /test {
            content_by_lua '
                ngx.say([[hello world\n\nhello lxj]])
            ';  
        }   
        location = /post {
            content_by_lua '
                ngx.req.read_body()
                local body = ngx.req.get_body_data()
                ngx.say(ngx.md5(body))
            ';  
        }   
    }   
```

### Http Test(see in lua-testy-test/lib/simple_test.lua)
```
local cjson = require("cjson")
local ht = require "resty.http_test"
local tb    = require "resty.iresty_test"

local blocks = [[
=== Test Get 
--- request
GET /get_json
--- more_headers
Host: test.com
--- error_code
200
--- response_body json_fmt
{"a3":99, 
"b4":22, 
"f":"20", 
"b0": "bb"}
--- response_body_filter
json_fmt


=== Test Hello
--- request
GET /test
--- more_headers
Host: test.com
--- error_code
200
--- response_body
hello world

hello lxj

=== Test Post&eval
--- request eval
local req_line = "POST /post"
local datas = {}
for i =1, 10 do 
	table.insert(datas, "line:" .. i)
end
return req_line .. "\n" .. table.concat(datas, "\n")
--- more_headers
Host: test.com
--- error_code eval
return 2000/10
--- response_body eval ngx.md5
local datas = {}
for i =1, 10 do 
	table.insert(datas, "line:" .. i)
end
return table.concat(datas, "\n")
--- response_body_filter
trim
]]

function json_fmt(s)
	local jso = cjson.decode(s)
	if jso then 
		local keys = {}
		for k, _ in pairs(jso) do 
			table.insert(keys, k)
		end
		local lines = {}
		for _, k in ipairs(keys) do 
			table.insert(lines, k .. ":" .. jso[k])
		end
		return table.concat(lines, '\n')
	else
		return s 
	end
end

-- units test
local test = ht.new({unit_name="test-base", blocks = blocks, server="http://127.0.0.1:100"})
test:run()
```

### The output (Run: path/to/resty -I /path/to/lua-resty-test/lib simple_test.lua)
```
0.000  [test-base] unit test start 
0.045    |--[Test Get] PASS 
0.045    |--[Test Hello] PASS 
0.045    |--[Test Post&eval] PASS 
0.045  [test-base] unit test complete 
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
