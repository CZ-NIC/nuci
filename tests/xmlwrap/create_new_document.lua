-- Example and basic test case for part of API that is providing manipulation with new document

-- Create new document
local doc = xmlwrap.new_xml_doc();
-- Create new node
local root_node = xmlwrap.new_node("employees");
-- Set root_node node as root node of this document
doc:set_root_node(root_node);

-- Prepare variables
local person = nil;
local node = nil;

-- Add some data
person = xmlwrap.new_node("person"); -- Create new node
root_node:add_child(person); -- And add it to root

node = xmlwrap.new_node("name");
	node:add_child(xmlwrap.new_text("Marry"));
	person:add_child(node);

node = xmlwrap.new_node("phone_number");
	node:add_child(xmlwrap.new_text("123456789"));
	person:add_child(node);

node = xmlwrap.new_node("post");
	node:add_child(xmlwrap.new_text("accountant"));
	person:add_child(node);


-- Add more data
person = xmlwrap.new_node("person");
root_node:add_child(person);

node = xmlwrap.new_node("name");
	node:add_child(xmlwrap.new_text("Joe"));
	person:add_child(node);

node = xmlwrap.new_node("phone_number");
	node:add_child(xmlwrap.new_text("987654321"));
	person:add_child(node);

node = xmlwrap.new_node("post");
	node:add_child(xmlwrap.new_text("CEO"));
	person:add_child(node);


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
