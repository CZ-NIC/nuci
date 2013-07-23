require("uci");
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

-- Dump the table, for debug purposes.
function dump_table(tab)
	for k, v in pairs(tab) do
		io.stderr:write(k .. ":" .. tostring(v) .. "\n");
	end
end

local uci_cursor;

function get_uci_cursor()
	if not uci_cursor then
		uci_cursor = uci.cursor(os.getenv("NUCI_TEST_CONFIG_DIR"));
	end
	return uci_cursor;
end

-- For debug
function var_test(varname, var)
	local str;
	if var == nil then str = ""; else str = "not "; end
	io.stderr:write(varname .. " is " .. str .. "nil " .. "\n");
end

function var_len(varname, var)
	if var then
		io.stderr:write(varname .. " has length " .. #var .. "\n");
	end
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
