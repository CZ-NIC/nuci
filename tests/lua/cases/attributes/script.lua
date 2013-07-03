--prepare variables
local doc = nil;
local root = nil;
local node = nil;

-- create document
doc = xmlwrap.new_xml_doc("employees");
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

node = doc:root():first_child():next();

node:set_attribute("salary", "raise");
node:set_attribute("eye_color", "blue");
io.stdout:write("O2: " .. node:attribute("salary") .. "\n");
io.stdout:write("O3: " .. doc:strdump() .. "\n");


node:set_attribute("salary", "not raise");
io.stdout:write("O4: " .. node:attribute("salary") .. "\n");
io.stdout:write("O5: " .. doc:strdump() .. "\n");

node:rm_attribute("eye_color");
io.stdout:write("O6: " .. node:attribute("salary") .. "\n");
io.stdout:write("O7: " .. doc:strdump() .. "\n");

node:set_attribute("salary", "");
io.stdout:write("O8: " .. node:attribute("salary") .. "\n");
io.stdout:write("O9: " .. doc:strdump() .. "\n");
