-- Names of valid node names in model, with empty data for future extentions
local model_names = {
	leaf={},
	['leaf-list']={},
	container={},
	list={}
}
local netconf_ns = 'urn:ietf:params:netconf:base:1.0'
local yang_ns = 'urn:ietf:params:xml:ns:yang:yin:1'

-- Find a model node corresponding to the node_name here.
-- TODO: Preprocess the model, so we can do just table lookup instead?
local function model_identify(model_dir, node_name)
	--[[
	Find a node in the current model one that is in the netconf namespace
	and it is either container, leaf, list or leaf-list that has the name
	attribute equal to node_name.
	]]
	for model in model_dir:iterate() do
		local name, ns = model:name();
		-- The corrent namespace and attribute
		if ns == yang_ns and model:attribute('name') == node_name then
			for model_name in pairs(model_names) do
				-- Found allowed name, all done
				if name == model_name then
					return model;
				end
			end
			-- Not a valid name. Try next node.
		end
	end
end

-- Perform operation on all the children here.
local function children_perform(config, command, model, ns, defop, errop, ops)
	for command_node in command:iterate() do
		local command_name, command_ns = command_node:name();
		if command_ns == ns then
			model_node = model_identify(model, command_name);
			if not model_node then
				-- TODO What about errop = continue?
				return {
					msg="Unknown element",
					tag="unknown element",
					info_badelem=command_name
				};
			end
			print("Found model node " .. model_node:name() .. " for " .. command_name);
		end
	end
end
--[[
Turn the <edit-config /> method into a list of trivial changes to the given
current config. The current_config, command and model are lxml2 objects. The
defop and errop are strings, specifying the default operation/error operation
on the document.

Returns either the table of modifications to perform on the config, or nil,
error. The error can be directly passed as result of the operation.

The config and command XML is supposed to be wrapped in something (since
by default there may be more elements, which wouldn't be valid XML). The
top-level element of them is ignored.
]]
function editconfig(config, command, model, ns, defop, errop)
	local config_node = config:root();
	local command_node = command:root();
	local model_node = model:root();
	local ops = {}
	err = children_perform(config_node, command_node, model_node, ns, defop, errop, ops)
	return ops, err
end
