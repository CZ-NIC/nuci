#!bin/test_runner

--[[
This stress-tests the xmlwrap library. There was some kind of bug on garbage
collection, this therefore creates and manipulates with XML a lot and tries
to trigger it.
]]

local doc_str = [[
<?xml version='1.0' encoding='UTF-8'?>
<root xmlns:x='y' xmlns='x:y'>
  <node attribute='42'>Text</node>
  <node x:attribute='13' attribute='42'/>
  <x:wrapper>
    <content/>
  </x:wrapper>
</root>
]];

local function recurse(node, offset)
	local name, ns = node:name();
	if not ns then
		return
	end
	print(offset .. name .. '@' .. ns);
	if node:text() == 'Text' then
		node:set_text('Some other text');
		print(offset .. '#' .. node:text());
	end
	for child in node:iterate() do
		recurse(child, offset .. ' ');
	end
end

local function iteration()
	local doc = xmlwrap.read_memory(doc_str);
	local node = doc:root();
	recurse(node, ' ');
end

for i = 0, 1000 do
	iteration();
end
