#!bin/test_runner

package.path = 'src/lua_lib/?.lua;' .. package.path;
require("xmltree");

--[[
Unit test for the xmltree converter.

Each test is just the input value and expected XML output.
]]

local cases = {
	toptext = {
		input = { name = 'doc', namespace = 'http://example.org/namespace', text = 'nothing' },
		output = [[<doc xmlns="http://example.org/namespace">nothing</doc>]]
	},
	nocontent = {
		input = { name = 'doc', namespace = 'http://example.org/namespace' },
		output = [[<doc xmlns="http://example.org/namespace"/>]]
	},
	child = {
		input = { name = 'doc', namespace = 'http://example.org/namespace', children = { { name = 'child' } } },
		output = [[<doc xmlns="http://example.org/namespace"><child/></doc>]]
	},
	foreignchild = {
		input = { name = 'doc', namespace = 'http://example.org/namespace', children = { { name = 'child', namespace = 'http://example.org/another' } } },
		output = [[<doc xmlns="http://example.org/namespace"><child xmlns="http://example.org/another"/></doc>]]
	},
	order = {
		input = { name = 'doc', namespace = 'http://example.org/namespace', children = { { name = 'first' }, { name = 'second' }, { name = 'third' } } },
		output = [[<doc xmlns="http://example.org/namespace"><first/><second/><third/></doc>]]
	},
	twins = {
		input = { name = 'doc', namespace = 'http://example.org/namespace', children = { { name = 'child' }, { name = 'child' } } },
		output = [[<doc xmlns="http://example.org/namespace"><child/><child/></doc>]]
	}
}

for name, test in pairs(cases) do
	local output = xmltree_dump(test.input):strdump();
	local expected = '<?xml version="1.0"?>\n' .. test.output .. "\n";
	if output ~= expected then
		error("The output of test " .. name .. " differs:\n" .. output .. " vs. \n" .. expected);
	end
end
