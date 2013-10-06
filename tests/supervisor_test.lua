#!bin/test_runner

--[[
Tests for the views supervisor.

We have several auxiliary help functions here. Each test is a function, registered
in a table. Then, the main routine runs each in turn and checks if they terminate
correctly. Then it invalidates the cache and resets in the supervisor after each test.
]]

package.path = 'src/lua_lib/?.lua;' .. package.path;
require("views_supervisor");
require("dumper");

--[[
Generate a provider plugin, based on bunch of value definitions. Nothing too fancy.
]]
local function test_provider(value_definitions)
	local provider = {};
	-- Extract the paths, to know where to register.
	function provider:positions()
		local result = {};
		for _, value in ipairs(value_definitions) do
			table.insert(result, value.path);
		end
		return result;
	end
	function provider:get()
		return value_definitions;
	end
	function provider:collision_handlers()
		return {};
	end
	return provider;
end

local generate_simple_values = {
	{
		path = {'a', 'b'},
		multival = {'something', 'nothing'}
	},
	{
		path = {'b', 'c', 'value'},
		keys = {{}, {key = 'hello'}},
		val = 42
	},
	{
		path = {'b', 'c', 'value'},
		keys = {{}, {key = 'greetings'}},
		val = 24
	}
};

local generate_duplicate = {
	{
		path = {'a'},
		val = 42
	},
	{
		path = {'b'},
		multival = {'something', 'nothing'}
	},
	{
		path = {'c', 'value'},
		keys = { {key = 'key'} },
		val = 'value'
	}
};

--[[
Check the value1 and value2 are the same. Recurses through table structures,
to check them for deep equality.
]]
local function deep_equal(value1, value2)
	local type1, type2 = type(value1), type(value2);
	if type1 ~= type2 then
		return false;
	end
	if type1 == 'table' then
		-- Shortcut, if they are the same address
		if value1 == value2 then return true; end
		local function check(t1, t2)
			for key, value in pairs(t1) do
				if not deep_equal(value, t2[key]) then
					return false;
				end
			end
			return true;
		end
		return check(value1, value2) and check(value2, value1);
	else
		return value1 == value2;
	end
end

local function test_equal(expected, real, message)
	message = message or 'Values differ';
	if not deep_equal(expected, real) then
		error(message .. ': ' .. DataDumper({
			expected = expected,
			real = real
		}));
	end
end

--[[
Common part of the generate single tests. This checks the
tree inside the supervisor looks correct.
]]
local function test_tree_simple(namespace)
	-- Check it is cached and the values are proper
	test_equal(true, supervisor.cached, 'Cached');
	--[[
	TODO: This order is internal-data-representation dependant :-(.
	See #2702.
	]]
	local tree = {
		children = {
			{
				name = 'a',
				children = {
					{ name = 'b', text = 'something' },
					{ name = 'b', text = 'nothing' }
				}
			},
			{
				name = 'b',
				namespace = namespace,
				children = {
					{
						name = 'c',
						children = {
							{ key = true, name = 'key', text = 'hello' },
							{ name = 'value', text = 42 }
						}
					},
					{
						name = 'c',
						children = {
							{ key = true, name = 'key', text = 'greetings' },
							{ name = 'value', text = 24 }
						}
					}
				}
			}
		}
	};
	test_equal(tree, supervisor.data, 'Data tree differs');
	test_equal({
		a = tree.children[1],
		b = tree.children[2]
	}, supervisor.index, 'Data index differs');
end

local tests = {
	{
		--[[
		Simply a test that does nothing. It checks the supervisor can be created
		(implicit) and the cache invalidated (run by the test).

		It also checks the test harness is sane little bit.
		]]
		name = 'startup',
		body = function() end
	},
	{
		--[[
		Test we can register to some places in the supervisor. Check the registration
		results in correct data structures in the supervisor.
		]]
		name = 'register values',
		provider_plugins = {
			test_provider({
				-- The following path is there twice. Check it is only once in the result.
				{ path = {'x', 'y', 'z'} },
				{ path = {'x', 'y', 'z'} },
				-- A wildcard
				{ path = {'x', 'y', '*'} },
				-- Another path
				{ path = {'a', 'b', 'c'} }
			}),
			test_provider({
				{ path = {'a', 'b', 'c' } },
				{ path = {'a', 'b', 'd' } },
				{ path = { 'x', '*' } }
			})
		},
		body = function(test)
			-- Check the things are registered properly, by examining the data structures
			test_equal(test.provider_plugins, supervisor.plugins, 'Plugins are wrong');
			test_equal({
				plugins = {},
				subnodes = {
					a = {
						plugins = {},
						subnodes = {
							b = {
								plugins = {},
								subnodes = {
									c = {
										plugins = test.provider_plugins,
										subnodes = {}
									},
									d = {
										plugins = {test.provider_plugins[2]},
										subnodes = {}
									}
								}
							}
						}
					},
					x = {
						plugins = {},
						subnodes = {
							y = {
								plugins = {},
								subnodes = {
									z = {
										plugins = {test.provider_plugins[1]},
										subnodes = {}
									},
									['*'] = {
										plugins = {test.provider_plugins[1]},
										subnodes = {}
									}
								}
							},
							['*'] = {
								plugins = {test.provider_plugins[2]},
								subnodes = {}
							}
						}
					}
				}
			}, supervisor.tree, 'Registration trees are different');
			-- Test by calling the finding method
			test_equal({test.provider_plugins[2], test.provider_plugins[1]}, supervisor:get_plugins({'x', 'y', 'z'}), 'Get plugins 1');
			test_equal({test.provider_plugins[2]}, supervisor:get_plugins({'a', 'b', 'd'}), 'Get plugins 2');
			test_equal({}, supervisor:get_plugins({'c'}), 'Get plugins 3');
			test_equal({}, supervisor:get_plugins({}), 'Get plugins 4');
			test_equal(test.provider_plugins, supervisor:get_plugins(), 'Get plugins noparam');
		end
	},
	{
		--[[
		Let the supervisor generate some data and examine the tree directly.
		]]
		name = 'generate single (tree)',
		provider_plugins = { test_provider(generate_simple_values) },
		body = function()
			-- Build the tree
			supervisor:check_tree_built();
			test_tree_simple();
		end
	},
	{
		--[[
		Let the supervisor generate some data and the returned XML.

		Also check the tree inside is generated when we call get.
		]]
		name = 'generate single (XML)',
		provider_plugins = { test_provider(generate_simple_values) },
		body = function()
			local xml = supervisor:get('b', 'http://example.org/b');
			-- The tree is built by that
			test_tree_simple('http://example.org/b');
			-- The XML looks sane
			test_equal([[<?xml version="1.0"?>
<b xmlns="http://example.org/b"><c><key>hello</key><value>42</value></c><c><key>greetings</key><value>24</value></c></b>
]], xml:strdump());
			-- Get the other part too
			test_equal([[<?xml version="1.0"?>
<a xmlns="http://example.org/a"><b>something</b><b>nothing</b></a>
]], supervisor:get('a', 'http://example.org/a'):strdump());
			-- The namespace in the 'b' is preserved ‒ it did not get regenerated
			test_equal(supervisor.index.b.namespace, 'http://example.org/b');
		end
	},
	{
		--[[
		Check the implicit nodes are created and are created exactly once.
		]]
		name = 'generate implicit',
		provider_plugins = { test_provider({
			{ path = {'a', 'b'}, val = 42 },
			{ path = {'a', 'c'}, val = 24 }
		}) };
		body = function()
			supervisor:check_tree_built();
			test_equal({
				children = {
					{
						name = 'a',
						children = {
							--[[
							TODO (#2702):
							The order depends on internal order in tables indexed
							by names. This is unreliable and will likely break :-(.

							Either detect the order or make sure the supervisor preserves
							it.
							]]
							{ name = 'c', text = 24 },
							{ name = 'b', text = 42 }
						}
					}
				}
			}, supervisor.data, 'Data');
		end
	},
	{
		--[[
		Check that if we specify the same node from two different
		plugins (without collision), only one instance created.
		]]
		name = 'generate dupliccate (no collision)',
		provider_plugins = {
			test_provider(generate_duplicate),
			test_provider(generate_duplicate)
		},
		body = function(test)
			-- Check that both plugins are preserved in there
			test_equal(test.provider_plugins, supervisor:get_plugins(), 'Global plugins')
			test_equal(test.provider_plugins, supervisor:get_plugins({'a'}), 'Local plugins');
			-- Build the tree
			supervisor:check_tree_built();
			-- Check each of the desired nodes is generated exactly once
			--[[
			TODO: The order of data is internal-data-representation dependant.
			See #2702.
			]]
			test_equal({
				children = {
					{ name = 'a', text = 42 },
					{
						name = 'c',
						children = {
							{ key = true, name = 'key', text = 'key' },
							{ name = 'value', text = 'value' }
						}
					},
					{ name = 'b', text = 'something' },
					{ name = 'b', text = 'nothing' }
				}
			}, supervisor.data, 'Data');
		end
	}
}

local function run_test(test)
	io.write('Running test "', test.name, "\"\t");
	-- The provider plugins
	for _, plugin in ipairs(test.provider_plugins or {}) do
		supervisor:register_plugin(plugin);
	end
	io.write("Setup\t");
	test.body(test);
	io.write("Body\t");
	-- Reset the cache
	supervisor:invalidate_cache();
	supervisor.plugins = {};
	supervisor.tree = { subnodes = {}, plugins = {} }
	io.write("OK\n");
end

for i, test in ipairs(tests) do
	run_test(test);
end
