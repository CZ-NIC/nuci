-- Datasource...

-- Create some debugging XML document (bassicali first version of create_new_document.lua example script
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

local function createMultipleTextXML()
	return "<elem>text <!-- comment --> some text before CDATA <![CDATA[ I'm Pretty cool example of CDATA ]]> and some more text</elem>";
end

io.stdout:write("Nothing to do.\n");
