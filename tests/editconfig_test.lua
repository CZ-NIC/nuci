#!bin/test_runner

--[[
Unit tests the editconfig library.

Generally, it works by running the editconfig function on bunch of
inputs and checking the outputs. We don't really care much how it
gets to the desired output.
]]
package.path = 'src/lua_lib/?.lua;' .. package.path;
require("editconfig");

local small_model = [[
<module name='test' xmlns='urn:ietf:params:xml:ns:yang:yin:1'>
  <yang-version value='1'/>
  <namespace uri='http://example.org/'/>
  <prefix value='prefix'/>
  <container name='data'>
    <leaf name='value'>
      <type name='int32'/>
    </leaf>
  </container>
</module>
]];

local tests = {
	["Empty command"]={
		--[[
		The command XML is effectively empty, while the config contains something.
		It should result in empty list of operations.

		It partly serves for checking the test suite itself is sane.
		]]
		command=[[<edit/>]],
		config=[[<config><data xmlns='http://example.org'><value>13</value></data></config>]],
		model=small_model,
		ns='http://example.org',
		expected_ops={}
	}
};

local function perform_test(name, test)
	io.write('Running test "', name, '"\t');
	local command_xml = lxml2.read_memory(test.command);
	local config_xml = lxml2.read_memory(test.config);
	local model_xml = lxml2.read_memory(test.model);
	io.write('XML\t');
	local ops, err = editconfig(config_xml, command_xml, model_xml, test.ns, test.defop or 'merge', nil);
	io.write('Run\t');
	-- TODO: Check the error properly
	if err then
		error(err.msg);
	end
	if #ops ~= #test.expected_ops then
		error("Wrong ops count: " .. #ops .. ", expected: " .. #test.expected_ops);
	end
	-- TODO: Check the operations
	io.write("OK\n");
end

for name, test in pairs(tests) do
	perform_test(name, test);
end
