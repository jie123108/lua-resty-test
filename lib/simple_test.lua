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