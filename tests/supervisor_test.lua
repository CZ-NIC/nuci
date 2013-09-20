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
	return provider;
end

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

local tests = {
	{
		--[[
		Simply a test that does nothing. It checks the supervisor can be created
		(implicit) and the cache invalidated (run by the test).

		It also checks the test harness is sane little bit.
		]]
		name = 'startup',
		body = function() end
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
