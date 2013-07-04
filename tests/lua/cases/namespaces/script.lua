--prepare variables
local doc = nil;
local root = nil;
local node = nil;

-- create document
doc = xmlwrap.new_xml_doc("employees", "http://nic.cz/router/document");
root = doc:root();
person = nil;

person = root:add_child("person");
	node = person:add_child("name");
	node:set_text("Marry");

	node = person:add_child("phone_number");
	node:set_text("123456789");

	node = person:add_child("post");
	node:set_text("accountant");

person = root:add_child("person");
	node = person:add_child("name");
	node:set_text("Anne");

	node = person:add_child("phone_number");
	node:set_text("123456799");

	node = person:add_child("post");
	node:set_text("secretary");

person = root:add_child("person");
	node = person:add_child("name");
	node:set_text("Joe");

	node = person:add_child("phone_number");
	node:set_text("987654321");

	node = person:add_child("post");
	node:set_text("CEO");

io.stdout:write("O1: " .. doc:strdump() .. "\n");

root:register_ns("http://nic.cz/router/employee", "empl");
io.stdout:write("O2: " .. doc:strdump() .. "\n");

node = root:first_child();
node:set_attribute("key", "value", "http://nic.cz/router/employee");
io.stdout:write("O3: " .. doc:strdump() .. "\n");

node:rm_attribute("key");
io.stdout:write("O4: " .. doc:strdump() .. "\n");

node:rm_attribute("key", "http://nic.cz/router/employee");
io.stdout:write("O5: " .. doc:strdump() .. "\n");

node:register_ns("http://nic.cz/router/employee/marry", "marry");
io.stdout:write("O6: " .. doc:strdump() .. "\n");

node:register_ns("http://nic.cz/router/document", "routerdoc");
io.stdout:write("O7: " .. doc:strdump() .. "\n");

node = root:add_child("manager_person", "http://nic.cz/router/employee");
io.stdout:write("O8: " .. doc:strdump() .. "\n");

node = root:add_child("manager_person", "http://nic.cz/router/employee/marry");
io.stdout:write("O9: " .. doc:strdump() .. "\n");
