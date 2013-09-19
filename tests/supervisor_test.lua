#!bin/test_runner

--[[
Tests for the views supervisor.

We have several auxiliary help functions here. Each test is a function, registered
in a table. Then, the main routine runs each in turn and checks if they terminate
correctly. Then it invalidates the cache in the supervisor after each test.
]]

package.path = 'src/lua_lib/?.lua;' .. package.path;
require("views_supervisor");

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
	-- TODO: Setup
	io.write("Setup\t");
	test.body();
	io.write("Body\t");
	supervisor:invalidate_cache();
	io.write("OK\n");
end

for i, test in ipairs(tests) do
	run_test(test);
end
