require("editconfig")
--[[
Crete skeleton of the abstraction plugin
]]
function abstraction_plugin(plugin_name)
	local result = {
		id = plugin_name;
	};

	function result:get(value)
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
