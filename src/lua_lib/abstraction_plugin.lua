require("editconfig");
--[[
Crete skeleton of the abstraction plugin
]]
function abstraction_plugin(plugin_name)
	local result = {
		id = plugin_name;
	};

	--[[
		path - path of requested value
		level - number of valid items in path
		keyset - keyset of requested node

		returns value or nil (I nod't know about this value - does not necessarily mean an error)
	]]
	function result:get(path, level, keyset)
		return nil, "Not implemented";
	end;

	function result:set(vector)
		return nil, "Not implemented";
	end;

	function result:register_values()
		return nil, "Not implemented";
	end;

	function result:handle_conflicts(conflicts)
		return nil, "Not implemented";
	end;

	return result;
end
