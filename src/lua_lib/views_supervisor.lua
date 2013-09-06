-- Global state varables
supervisor = {
	plugins = {},
	tree = {}
};

supervisor.tree["a"] = {["c"] = {}, ["d"] = {}};
supervisor.tree["b"] = {["e"] = {}, ["f"] = {}};

function supervisor:add_to_tree(node, level, plugin, path)
	if level >= (#path) then
		--tady to je
		return;
	end

	for key, node in pairs(node) do
		if key == path[level] then
			supervisor:add_to_tree(node, level+1, plugin, path);
		end
	end
	node[path[level]] = plugin;
end

function supervisor:register_ap(plugin, name)
	supervisor.plugins[name] = plugin;
end

function supervisor:register_value(plugin, path)
	supervisor:add_to_tree(tree, 1, plugin, path);
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
	for key, node in pairs(root) do
		debug_tree(root[key], xmlnode:add_child(key));
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
