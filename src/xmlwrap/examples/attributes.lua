-- Example and basic test case

local function createSomeXML()
	local doc = xmlwrap.new_xml_doc("employees");
	local root_node = doc:root();
	local person = nil;
	local node = nil;

	person = root_node:add_child("person");
		node = person:add_child("name");
		node:set_text("Marry");

		node = person:add_child("phone_number");
		node:set_text("123456789");

		node = person:add_child("post");
		node:set_text("accountant");

	person = root_node:add_child("person");
		node = person:add_child("name");
		node:set_text("Joe");

		node = person:add_child("phone_number");
		node:set_text("987654321");

		node = person:add_child("post");
		node:set_text("CEO");

	return doc:strdump()
end

local doc = xmlwrap.read_memory(createSomeXML());

io.stdout:write("Original XML: " .. doc:strdump() .. "\n");

local node = doc:root():first_child();

node:set_attribute("salary", "raise");
node:set_attribute("eye_color", "blue");

io.stdout:write("Modified XML (1): " .. doc:strdump() .. "\n");

node:set_attribute("salary", "not raise");

io.stdout:write("Obtained text: " .. node:attribute("salary") .. "\n");

io.stdout:write("Modified XML (2): " .. doc:strdump() .. "\n");

node:rm_attribute("eye_color");

io.stdout:write("Modified XML (3): " .. doc:strdump() .. "\n");
