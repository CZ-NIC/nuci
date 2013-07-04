--prepare variables
local doc = nil;
local root = nil;
local node = nil;

--set text to empty node
doc = xmlwrap.new_xml_doc("root");
root = doc:root();
node = root:add_child("elem");

node:set_text("Lorem ipsum dolor sit amet");
io.stdout:write("O1: " .. doc:strdump() .. "\n");

node:set_text("Lorem ipsum...");
io.stdout:write("O2: " .. doc:strdump() .. "\n");

node:set_text("");
io.stdout:write("O3: " .. doc:strdump() .. "\n");

doc = xmlwrap.read_memory("<elem>text <!-- comment --> some text before CDATA <![CDATA[ I'm Pretty cool example of CDATA ]]> and some more text</elem>");
io.stdout:write("O4: " .. doc:strdump() .. "\n");

node = doc:root();
local str = node:set_text("Lorem ipsum");
io.stdout:write("O5: " .. doc:strdump() .. "\n");
