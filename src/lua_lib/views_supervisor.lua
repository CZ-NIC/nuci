-- Global state varables
supervisor = {
	plugins = {},
	tree = {};
};

-- Test if table is empty or not
local function is_empty(table)
	if next(table) == nil then
		return true;
	end

	return false;
end

local function tree_create_node()


end

local function tree_create_leaf()

end

local function tree_try_add_key(keys, keyset)
	if keyset ~= nil then
		for k, v in pairs(keyset) do
			keys[k] = v;
		end
	end
end

local function tree_rec_add(node, level, plugin, path, key)
	-- Test path variable
	if path[level] == nil then
		return nil, "Empty path";
	end

	-- Create if node is empty
	if is_empty(node) then
		node.name = path[level];
		node.keys = {};
		node.childs = {};
	end

	-- Add keys
	tree_try_add_key(node.keys, key[level]);

	if path[level+1] == nil then
		-- I'm leaf
		if node.plugins == nil then
			node.plugins = {};
		end

		table.insert(node.plugins, plugin);

	else
		if node.childs[path[level+1]] == nil then
			node.childs[path[level+1]] = {};
		end
		return tree_rec_add(node.childs[path[level+1]], level+1, path, key);
	end
end

function supervisor:register_ap(plugin, name)
	supervisor.plugins[name] = plugin;
end

function supervisor:register_value(plugin, path, key)
	supervisor:rec_add_to_tree(supervisor.tree, 1, plugin, path, key);
end

function supervisor:register_all_values()
	local ret, err;
	for _, plugin in pairs(supervisor.plugins) do
		supervisor.plugin:register_values();
		if not ret then
			return ret, err;
		end
	end

	return true;
end

local function debug_tree(root, xmlnode)
	if not root then
		return;
	end

	local n = xmlnode:add_child(root.name);
	for key, child in pairs(root.childs) do
		debug_tree(root[key], n);
	end
end

function supervisor:get()
	local ret, err;
	local doc = xmlwrap.new_xml_doc('root');
	-- First of all - register all values of tree
	ret, err = supervisor:register_all_values();
	if not ret then
		return ret, err;
	end
	debug_tree(supervisor.tree, doc:root());

	--return "Yes, I'm here!";
	return doc:strdump();
end
