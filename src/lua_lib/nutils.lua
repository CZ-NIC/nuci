--[[
Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)

This file is part of NUCI configuration server.

NUCI is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

NUCI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
]]

require("uci");

local yang_ns = 'urn:ietf:params:xml:ns:yang:yin:1'

-- Enable StackTracePlus instead of standard Lua version
debug.traceback = require("stacktraceplus").stacktrace;
-- And now just call: print(debug.traceback());

-- Find the first child node matching a predicate, or nil.
function find_node(node, predicate)
	for child in node:iterate() do
		local result, err = predicate(child)
		if err then
			return nil, err;
		end

		if result then
			return child;
		end
	end
end

-- Find a subnode with given name and ns
function find_node_name_ns(node, name, ns)
	return find_node(node, function(node)
		local nname, nns = node:name();
		return ns == nns and name == nname;
	end);
end

function extract_multi_texts(root, names, ns)
	result = {}
	for i, name in pairs(names) do
		local node = find_node_name_ns(root, name, ns)
		if not node then
			return nil, {
				msg = "Missing <" .. name .. ">",
				app_tag = 'data-missing',
				info_badelem = name,
				info_badns = ns
			};
		end
		result[i] = node:text();
	end
	return result;
end

-- split the string into words
function split(str)
	return str:gmatch('%S+');
end

-- Split string into lines (return iterator)
function lines(str)
	local position = 1;
	return function ()
		local s, e = str:find('\n', position, true);
		if not s then
			return nil;
		end
		local result = str:sub(position, s - 1);
		position = e + 1;
		return result;
	end;
end

--[[
Extract the list of expected keys in the model node.
The model node should yang description of a list (specially, it should contain
the key element).
]]
function list_keys(model_node)
	return split(find_node_name_ns(model_node, 'key', yang_ns):attribute('value'));
end

-- Dump the table, for debug purposes.
function dump_table(tab)
	for k, v in pairs(tab) do
		nlog(NLOG_TRACE, k, ":", tostring(v));
	end
end

local uci_cursor;

function get_uci_cursor()
	if not uci_cursor then
		uci_cursor = uci.cursor(os.getenv("NUCI_TEST_CONFIG_DIR"));
	end
	return uci_cursor;
end

function reset_uci_cursor()
	uci_cursor = nil;
end

-- For debug
function var_test(varname, var)
	local str;
	if var == nil then str = ""; else str = "not "; end
	nlog(NLOG_TRACE, varname, " is ", str, "nil ");
end

function var_len(varname, var)
	if var then
		nlog(NLOG_TRACE, varname, " has length ", #var);
	end
end

function list2map(list)
	local result = {};
	for _, value in pairs(list) do
		result[value] = true;
	end
	return result;
end

function iter2list(iter)
	local result = {};
	for i in iter do
		table.insert(result, i);
	end
	return result;
end

-- Like split, but returns the values as multiple results instead of iterator
function words(str)
	return unpack(iter2list(split(str)))
end

--[[
Drop the <?xml …?> at the beginning of string.
]]
function strip_xml_def(xml_string)
	local l, r = xml_string:find('<%?xml .-%?>');
	io.stderr:write(xml_string .. ":" .. (l or "<nil>") .. "-" .. (r or "<nil>") .. "\n");
	if l == 1 then
		return xml_string:sub(r + 1);
	else
		return xml_string;
	end
end

-- trim whitespace from right end of string
function trimr(s)
	return s:find'^%s*$' and '' or s:match'^(.*%S)'
end

--[[
Check if two key sets are the same (effectively checks two tables for equality by
performing the comparison on each item. No recursion is done.
]]
function match_keysets(keys1, keys2)
	if not keys1 and not keys2 then return true end;
	if not keys1 or not keys2 then return false end;
	local function check(k1, k2)
		for k, v in pairs(k1) do
			if k2[k] ~= v then
				return false;
			end
		end
		return true;
	end
	--[[
	Check if everything in keys1 is in keys2 and vice versa.

	We could check the size first, but there's no function to check size of
	table in lua ‒ using # doesn't work, it works only on „ordered“ tables,
	not on string-key based one.
	]]
	return check(keys1, keys2) and check(keys2, keys1);
end

-- check whether the file on a given path exists
function file_exists(path)
	local file = io.open(path, "r");
	if file then
		file:close();
		return true;
	end
	return nil;
end
