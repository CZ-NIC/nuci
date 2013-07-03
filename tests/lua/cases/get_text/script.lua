
local doc = xmlwrap.read_memory("<elem>text <!-- comment --> some text before CDATA <![CDATA[ I'm Pretty cool example of CDATA ]]> and some more text</elem>");

io.stdout:write("Original XML (1): " .. doc:strdump() .. "\n");

local node = doc:root();

local str = node:text();
if (str == nil) then
	io.stdout:write("Obtained text (1): is nil value\n");
else
	io.stdout:write("Obtained text (1): " .. node:text() .. "\n");
end


doc = xmlwrap.read_memory("<root> BEFORE ELEM <elem>text <!-- comment --> some text before CDATA <![CDATA[ I'm Pretty cool example of CDATA ]]> and some more text</elem> AFTER ELEM </root>");

io.stdout:write("Original XML (2): " .. doc:strdump() .. "\n");

node = doc:root();

str = node:text();
if (str == nil) then
	io.stdout:write("Obtained text (2): is nil value\n");
else
	io.stdout:write("Obtained text (2): " .. node:text() .. "\n");
end
