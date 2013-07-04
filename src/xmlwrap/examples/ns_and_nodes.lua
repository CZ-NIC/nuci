
local doc = xmlwrap.new_xml_doc("employees", "http://nic.cz/router/test");
local root_node = doc:root();
local person = nil;
local node = nil;

person = root_node:add_child("person", "http://nic.cz/router/person");
	node = person:add_child("name", "foo");
	node:set_text("Marry");

	node = person:add_child("phone_number");
	node:set_text("123456789");

	node = person:add_child("post");
	node:set_text("accountant");

person = root_node:add_child("person");
	node = person:add_child("name");
	node:set_text("Anne");

	node = person:add_child("phone_number");
	node:set_text("123456799");

	node = person:add_child("post");
	node:set_text("secretary");

person = root_node:add_child("person");
	node = person:add_child("name");
	node:set_text("Joe");

	node = person:add_child("phone_number");
	node:set_text("987654321");

	node = person:add_child("post");
	node:set_text("CEO");

io.stdout:write("Original XML: " .. doc:strdump() .. "\n");
