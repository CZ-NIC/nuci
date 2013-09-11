require("tableutils");

-- Global state varables
supervisor = {
	plugins = {},
	tree = {},
	cached = false,
	doc= nil
};

dbg = "";
local function dbg_add(str)
	dbg = dbg .. str .. "\n";
end

local function tree_try_add_key(keys, keyset)
	local exists_keyset = function(keys, keyset)
		local candidate = false;
		for _, key in pairs(keys) do
			for k, v in pairs(key) do
				if keyset[k] == v then
					candidate = true;
				else
					candidate = false;
				end
			end
		end
		return candidate;
	end

	if keyset ~= nil then
		if not exists_keyset(keys, keyset) then
			table.insert(keys, keyset);
		end
	end
end

local function tree_rec_add(node, level, plugin, path, key)
	-- Test path variable
	if path[level] == nil then
		return nil, "Empty path";
	end

	-- Create if node is empty
	if table.is_empty(node) then
		node.name = path[level];
		node.keys = {};
		node.childs = {};
	end

	-- Add keys
	tree_try_add_key(node.keys, key[level]);

	-- Recurse or create node
	if path[level+1] == nil then
		-- I'm leaf
		if node.plugins == nil then
			node.plugins = {}; -- Table of plugin doesn't exists yet - create it
		end
		-- Leaf needs infromation about registered plugins
		table.insert(node.plugins, plugin);

	else
		-- I'm inner node
		if node.childs[path[level+1]] == nil then
			node.childs[path[level+1]] = {}; -- Table of child doesn't exists yet - create it
		end

		tree_rec_add(node.childs[path[level+1]], level+1, plugin, path, key);
	end
end

function supervisor:register_ap(plugin, name)
	supervisor.plugins[name] = plugin;
end

function supervisor:register_value(plugin, path, key)
	tree_rec_add(supervisor.tree, 1, plugin, path, key);
end

function supervisor:register_all_values()
	local ret, err;
	for _, plugin in pairs(supervisor.plugins) do
		ret, err = plugin:register_values();
		if not ret then
			return ret, err;
		end
	end

	return true;
end

function supervisor:init(init_doc)
	if supervisor.doc == nil then
		supervisor.doc = init_doc;
	end
end

function supervisor:invalidate_cache()
	supervisor.cached = false;
end

local function build_get_value(plugins, path, level, keyset)
	-- Return first valied answer is temporaly solution
	for _, plugin in pairs(plugins) do
		local res = plugin:get(path, level, keyset);
		if res ~= nil then
			return res;
		end
	end

	return "";
end

local function build_rec(node, onode, keyset, path, level)
	if node == nil then
		return
	end

	path[level] = node.name;

	local new_node;
	if table.is_empty(node.keys) then
		-- Create this node in XML
		new_node = onode:add_child(node.name);
		-- Generate leaf's value
		if table.is_empty(node.childs) then
			new_node:set_text(build_get_value(node.plugins, path, level, keyset));
		end
		-- Recurse to childs
		for _, child in pairs(node.childs) do
			build_rec(child, new_node, keyset, path, level+1);
		end
	else
		for _, key in pairs(node.keys) do
			-- Create copy of this node with this keyset in XML
			new_node = onode:add_child(node.name);
			-- Add keyset record into XML node
			for key_name, key_val in pairs(key) do
				new_node:add_child(key_name):set_text(key_val);
			end
			-- Recurse to childs of this copy
			for _, child in pairs(node.childs) do
				build_rec(child, new_node, key, path, level+1);
			end
		end
	end
end

function supervisor:build_tree(onode)
	build_rec(supervisor.tree, onode, nil, {}, 1);
end

function supervisor:get()
	-- Exists some data?
	if supervisor.cached == true then
		return supervisor.doc;
	end
	-- Data doesn't exists

	-- First of all - let plugins to register all values of tree
	ret, err = supervisor:register_all_values();
	if not ret then
		return ret, err;
	end

	-- Build new tree
	supervisor.cached = true;
	supervisor:build_tree(supervisor.doc:root());

	-- Development and debug
	--dbg_add(table.tostring(supervisor.tree)); -- This output is very long - uncomment it if you need it
	supervisor.doc:root():add_child("dbg"):set_text(dbg);


	return supervisor.doc;
end
