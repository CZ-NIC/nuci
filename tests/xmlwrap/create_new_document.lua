-- Example and basic test case for part of API that is providing manipulation with new document

-- Create new document
local doc = xmlwrap.new_xml_doc("employees");
-- Get root element
local root_node = doc:root();

-- Prepare variables
local person = nil;
local node = nil;

-- Add some data
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


-- Get my XML
io.stdout:write(doc:strdump() .. "\n");

--[[ This script generates:
<?xml version="1.0"?>
<employees>
	<person>
		<name>Marry</name>
		<phone_number>123456789</phone_number>
		<post>accountant</post>
	</person>
	<person>
		<name>Joe</name>
		<phone_number>987654321</phone_number>
		<post>CEO</post>
	</person>
</employees>
]]

