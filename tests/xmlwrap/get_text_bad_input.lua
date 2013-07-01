-- Example and basic test case

function createMultipleTextXML()
	return "<root><elem>text <!-- comment --> some text before CDATA <![CDATA[ I'm Pretty cool example of CDATA ]]> and some more text</elem></root>";
end

doc = xmlwrap.read_memory(createMultipleTextXML());

io.stdout:write("Original XML: " .. doc:strdump() .. "\n");

local node = doc:root();

local str = node:text();
if (str == nil) then
	io.stdout:write("Obtained text: is nil value\n");
else
	io.stdout:write("Obtained text: " .. node:text() .. "\n");
end


