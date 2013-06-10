#!bin/test_runner

--[[
Unit tests the editconfig library.

Generally, it works by running the editconfig function on bunch of
inputs and checking the outputs. We don't really care much how it
gets to the desired output.
]]
package.path = 'src/lua_lib/?.lua;' .. package.path;
require("editconfig");

local yang_ns = 'urn:ietf:params:xml:ns:yang:yin:1';
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
		ns='http://example.org/',
		expected_ops={}
	},
	["Add command"]={
		--[[
		Add a node to the config by a command.
		]]
		command=[[<edit><data xmlns='http://example.org/'><value>42</value></data></edit>]],
		config=[[<config/>]],
		model=small_model,
		ns='http://example.org/',
		expected_ops={
			{
				name='add-tree',
				command_node_name='data',
				model_node_name='container'
			}
		}
	},
	["Replace leaf"]={
		--[[
		Replace the leaf with value.
		]]
		command=[[<edit><data xmlns='http://example.org/'><value>42</value></data></edit>]],
		config=[[<config><data xmlns='http://example.org/'><value>13</value></data></config>]],
		model=small_model,
		ns='http://example.org/',
		expected_ops={
			{
				name='enter',
				command_node_name='data',
				config_node_name='data',
				model_node_name='container'
			},
			{
				name='remove-tree',
				command_node_name='value',
				command_node_text='42',
				config_node_name='value',
				config_node_text='13',
				model_node_name='leaf',
				note='replace'
			},
			{
				name='add-tree',
				command_node_name='value',
				command_node_text='42',
				config_node_name='value',
				config_node_text='13',
				model_node_name='leaf',
				note='replace'
			},
			{
				name='leave',
				command_node_name='data',
				config_node_name='data',
				model_node_name='container'
			}
		}
	},
	["Delete leaf"]={
		command=[[<edit><data xmlns='http://example.org/' xmlns:xc='urn:ietf:params:xml:ns:netconf:base:1.0'><value xc:operation='delete'/></data></edit>]],
		config=[[<config><data xmlns='http://example.org/'><value>42</value></data></config>]],
		model=small_model,
		ns='http://example.org/',
		expected_ops={
			{
				name='enter',
				command_node_name='data',
				config_node_name='data',
				model_node_name='container'
			},
			{
				name='remove-tree',
				command_node_name='value',
				config_node_name='value',
				config_node_text='42',
				model_node_name='leaf'
			},
			{
				name='leave',
				command_node_name='data',
				config_node_name='data',
				model_node_name='container'
			}
		}
	},
	["Delete container"]={
		command=[[<edit><data xmlns='http://example.org/' xmlns:xc='urn:ietf:params:xml:ns:netconf:base:1.0' xc:operation='delete'><value>13</value></data></edit>]];
		config=[[<config><data xmlns='http://example.org/'><value>42</value></data></config>]],
		model=small_model,
		ns='http://example.org/',
		expected_ops={
			{
				name='remove-tree',
				command_node_name='data',
				config_node_name='data',
				model_node_name='container'
			}
		}
	}
};

local function op_matches(op, expected, ns)
	if op.op ~= expected.name then
		return nil, "Name differs: " .. (op.op or '(nil)') .. " vs. " .. (expected.name or '(nil)');
	end
	if op.note ~= expected.note then
		return nil, "Note differs: " .. (op.note or '(nil)') .. " vs. " .. (expected.note or '(nil)');
	end
	local reason;
	local function node_check(node_type, ns)
		local ex_name = expected[node_type .. '_node_name'];
		local ex_ns = expected[node_type .. '_node_ns'] or ns;
		local node = op[node_type .. '_node'];
		if node and not ex_name then
			reason = "Not expected node of type " .. node_type;
			return nil;
		end
		if not node and not ex_name then
			return true;
		end
		local node_name, node_ns = node:name();
		if node_name ~= ex_name then
			reason = "Name of " .. node_type .. " differs: " .. node_name .. " vs. " .. ex_name;
			return nil;
		end
		if node_ns ~= ex_ns then
			reason = "NS of " .. node_type .. " differs: " .. node_ns .. " vs. " .. ex_ns;
			return nil;
		end
		local ex_text = expected[node_type .. "_node_text"];
		local node_text = node:text();
		if node_text and not node_text:find('%S') then
			node_text = nil;
		end
		if node_text ~= ex_text then
			reason = "Text of " .. node_type .. " differs: " .. (node_text or '(nil)') .. " vs. " .. (ex_text or '(nil)');
			return nil;
		end
		return true;
	end
	if (not node_check('command', ns)) or (not node_check('config', ns)) or (not node_check('model', yang_ns)) then
		return nil, reason;
	end
	return true;
end

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
	-- There doesn't seem to be really elegant way to iterate over two lists in parallel
	local expected_index, expected_op = next(test.expected_ops)
	for index, op in ipairs(ops) do
		local result, reason = op_matches(op, expected_op, test.ns);
		if not result then
			error("Operation no. " .. index .. " differs (" .. (reason or "<unknown reason>") .. ")");
		end
		expected_index, expected_op = next(test.expected_ops, expected_index);
	end
	io.write("OK\n");
end

for name, test in pairs(tests) do
	perform_test(name, test);
end
