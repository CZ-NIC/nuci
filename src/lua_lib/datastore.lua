require("editconfig")
--[[
Create a skeleton data store.
]]
function datastore(model_file)
	local result = {
		scheduled_commits = {}
	};
	-- Store the file
	result.model_file = model_file;
	-- Default implementations of methods.
	function result:get_config()
		return ""; -- No config, empty store by default.
	end
	function result:set_config(config, defop, deferr)
		-- It is empty, so setting it always works
	end
	function result:get()
		--[[
		Return empty set of statistics by default.

		This differs from the libnetconf behaviour a little bit. But it looks
		more sane, as config should not be returned as part of normal get.
		]]
		return "";
	end
	--[[
	Error reporting from user_rpcs:
	OK, no error, some data: return data, nil;
	FAILED with "error message" error: return nil, "error message";
	]]
	function result:user_rpc(rpc)
		return nil, "Custom RPCs are not implemented yet";
	end
	--[[
	Helper function. Wrapper around the global editconfig, to get the
	corresponding operations on the config.
	]]
	function result:edit_config_ops(config, defop, deferr)
		local current = xmlwrap.read_memory('<config>' .. strip_xml_def(self:get_config()) .. '</config>');
		local operation = xmlwrap.read_memory('<edit>' .. strip_xml_def(config) .. '</edit>');
		return editconfig(current, operation, self.model, self.model_ns, defop, deferr);
	end
	--[[
	A commit function. It is called after all the data stores
	successfuly handled set_config method. This is where the
	changes should be actually put to effect. It should be exception free.

	You don't need to override this method, usually you want to
	use self:schedule_commit(function ()). All such functions will be
	called from here.
	]]
	function result:commit()
		-- Call each function.
		for _, func in ipairs(self.scheduled_commits) do
			func();
		end
		self.scheduled_commits = {};
	end
	--[[
	Called when no commit will happen. This is to drop the changes
	that were created by set_config method, because some (possibly
	other) data store failed to apply.

	Note that it can be called even if set_config was not called on
	this data store.
	]]
	function result:rollback()
		-- Just remove all the scheduled functions.
		self.scheduled_commits = {};
	end
	--[[
	Schedule a commit function to be called from within commit().
	Note that if you override commit() method, this might not get
	called.
	]]
	function result:schedule_commit(commit_func)
		table.insert(self.scheduled_commits, commit_func);
	end
	--[[
	Upon the registration, the core sets these:
	- model_path -- full path to the model file.
	- model -- parsed xmlwrap object of the model.
	- model_ns -- namespace of the model.
	]]
	return result;
end
