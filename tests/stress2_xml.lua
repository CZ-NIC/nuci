#!bin/test_runner

--[[
This stress-tests the xmlwrap library. There was some kind of bug on garbage
collection, this therefore creates and manipulates with XML a lot and tries
to trigger it.
]]

-- Basic rule for next code: Do crazy things and do it many times
function get_tree()
	local doc = xmlwrap.new_xml_doc("employees");
	local root = doc:root();
	local person, node = nil;

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

	return doc;
end

function get_mixed_doc()
	return xmlwrap.read_memory("<elem>text <!-- comment --> some text before CDATA <![CDATA[ I'm Pretty cool example of CDATA ]]> and some more text</elem>");
end

function del_from_leaves(node)
	local child = node:first_child();

	if child == nil then
		node:delete();
		return true;
	end

	function try_delete()
		for child in node:iterate() do
			if del_from_leaves(child) then
				-- Try again. We deleted a node, which invalidated the current iterator.
				return true;
			end
		end
	end

	while try_delete() do
		-- Retry as long as it deletes something
	end
end

function op1()
	local doc = get_tree();
	local root = doc:root();
	local node = nil;

	del_from_leaves(root);
end

function op2()
	local doc = get_tree();
	local root = doc:root();
	local node = nil;

	root:first_child():next():first_child():next():delete(); -- delete Anne's phone number
	root:first_child():next():next():first_child():delete(); -- delete Joe's name
	root:first_child():delete(); -- delete Marry
	root:first_child():delete(); -- ...
	root:first_child():delete(); -- ...
end

function op3()
	local doc = get_mixed_doc();
	local node = nil;
	doc:root():set_text("some info");
	doc:root():add_child("child"):set_text("lorem ipsum");
	doc:root():set_text("some new info");
	doc:root():add_child("child"):set_text("lorem ipsum");
	doc:root():set_text("some new info");
	doc:root():add_child("child"):set_text("lorem ipsum");
	doc:root():set_text("some new info");
	doc:root():set_text("some xyz");
	doc:root():set_text("some abc");
	doc:root():set_text("some def");
	doc:root():set_text("some ghi");
end

function op4() -- copy from namespace testcase
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

root:register_ns("http://nic.cz/router/employee", "empl");
node = root:first_child();
node:set_attribute("key", "value", "http://nic.cz/router/employee");
node:rm_attribute("key");
node:rm_attribute("key", "http://nic.cz/router/employee");
node:register_ns("http://nic.cz/router/employee/marry", "marry");
node:register_ns("http://nic.cz/router/document", "routerdoc");
node = root:add_child("manager_person", "http://nic.cz/router/employee");
node = root:add_child("manager_person", "http://nic.cz/router/employee/marry");
end

function op5()
	local doc = get_tree();
	local root = doc:root();

	root:first_child():register_ns("http://test1", "test1");
	root:first_child():next():register_ns("http://test2", "test2");
	root:first_child():next():next():register_ns("http://test3", "test3");

	--create and change values
	root:first_child():first_child():set_attribute("key", "value");
	root:first_child():first_child():set_attribute("key", "value", "http://test1");
	root:first_child():first_child():set_attribute("key", "value2");
	root:first_child():first_child():set_attribute("key", "value2", "http://test1");
	root:first_child():first_child():set_attribute("key2", "value");
	root:first_child():first_child():set_attribute("key2", "value", "http://test1");
	root:first_child():first_child():set_attribute("key2", "value2");
	root:first_child():first_child():set_attribute("key2", "value2", "http://test1");
	--delete values
	root:first_child():first_child():rm_attribute("key");
	root:first_child():first_child():rm_attribute("key", "http://test1");
	root:first_child():first_child():rm_attribute("key2");
	root:first_child():first_child():rm_attribute("key2", "http://test1");
	-- and do it again
	root:first_child():first_child():set_attribute("key", "value");
	root:first_child():first_child():set_attribute("key", "value", "http://test1");
	root:first_child():first_child():set_attribute("key", "value2");
	root:first_child():first_child():set_attribute("key", "value2", "http://test1");
	root:first_child():first_child():set_attribute("key2", "value");
	root:first_child():first_child():set_attribute("key2", "value", "http://test1");
	root:first_child():first_child():set_attribute("key2", "value2");
	root:first_child():first_child():set_attribute("key2", "value2", "http://test1");

	root:first_child():first_child():rm_attribute("key");
	root:first_child():first_child():rm_attribute("key", "http://test1");
	root:first_child():first_child():rm_attribute("key2");
	root:first_child():first_child():rm_attribute("key2", "http://test1");
end

function iteration()
	op1(); -- delete all from leaves
	op2(); -- delete nodes in random order
	op3(); -- set text
	op4(); -- namespaces
	op5(); -- attributes
end

for i = 1, 10 do
	iteration();
end
