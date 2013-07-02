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

	return doc:strdump();
end


local doc = xmlwrap.read_memory(createSomeXML());

io.stdout:write("Original XML: " .. doc:strdump() .. "\n");

local node = doc:root();
node = node:first_child();
node:delete();

io.stdout:write("Modified XML: " .. doc:strdump() .. "\n");
