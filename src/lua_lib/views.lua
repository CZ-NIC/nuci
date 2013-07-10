require("datastore");

local hooks_set = {};
local hooks_get = {};
local hooks_differ = {};

function register_view(model, top_name, id)
	local result = datascore(model);

	register_datastore_provider(result);
	return result;
end

local function register(where, id, path, callback)
	local node = where[id] or { callbacks = {}, subnodes = {} };
	where[id] = node;
	for _, level in ipairs(path) do
		local sub = node.subnodes[level] or { callbacks = {}, subnodes = {} };
		node.subnodes[level] = sub;
		node = sub;
	end
	table.insert(node.callbacks, callback);
end

function hook_set(id, path, callback)
	register(hooks_set, id, path, callback);
end

function hook_get(id, path, callback)
	register(hooks_get, id, path, callback);
end

function hook_differ(id, path, callback)
	register(hooks_get, id, path, callback);
end
