function explain_bool(var)
	if var then
		io.stdout:write("Variable is TRUE\n");
	else
		io.stdout:write("Variable is FALSE\n");
	end
end


local doc = xmlwrap.new_xml_doc("root", "http://nic.cz/notreg/router");
local root = doc:root();
local node = root:add_child("elem");
node:register_ns("http://nic.cz/router", "router");

node = node:add_child("attribute");
node:set_text("Lorem ipsum dolor sit amet.");
node:set_attribute("pokus", "tak jak?", "http://nic.cz/router");

io.stdout:write("Modified XML (1): " .. doc:strdump() .. "\n");

local res = node:rm_attribute("pokus");
explain_bool(res);
local res = node:rm_attribute("pokus", "http://nic.cz/router");
explain_bool(res);

io.stdout:write("Modified XML (2): " .. doc:strdump() .. "\n");
