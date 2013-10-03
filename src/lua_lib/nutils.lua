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

-- split the string into words
function split(str)
	return str:gmatch('%S+');
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
