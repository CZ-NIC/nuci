require("editconfig")
--[[
Create a skeleton data store.
]]
function datastore(model_file)
	local result = {};
	-- Store the file
	result.model_file = model_file;
	-- Default implementations of methods.
	function result:get_config()
		return ""; -- No config, empty store by default.
	end
	function result:set_cofig(config, defop, deferr)
		-- It is empty, so setting it always works
	end
	function result:get()
		-- By default return the set of configuration.
		return self:get_config();
	end
	function result:call(rpc)
		return "Custom RPCs are not implemented yet";
	end
	--[[
	Helper function. Wrapper around the global editconfig, to get the
	corresponding operations on the config.
	]]
	function result:edit_config_ops(config, defop, deferr)
		local current = lxml2.read_memory('<config>' .. self:get_config() .. '</config>');
		local operation = lxml2.read_memory('<edit>' .. config .. '</edit>');
		return editconfig(current, operation, self.model, self.model_ns, defop, deferr);
	end
	--[[
	Upon the registration, the core sets these:
	- model_path -- full path to the model file.
	- model -- parsed lxml2 object of the model.
	- model_ns -- namespace of the model.
	]]
	return result;
end
