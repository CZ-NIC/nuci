require("tableutils");
require("nutils");
require("datastore");
require("xmltree");
require("commits");

-- Global state varables
supervisor = {
	plugins = {},
	tree = { subnodes = {}, plugins = {} },
};

-- Add a plugin to given path in the tree
local function register_to_tree(tree, path, plugin)
	local node = tree;
	for _, level in ipairs(path) do
		local sub = node.subnodes[level] or { plugins = {}, subnodes = {} };
		node.subnodes[level] = sub;
		node = sub;
	end
	table.insert(node.plugins, plugin);
	node.plugins = table.uniq(node.plugins);
end

--[[
Find the list of plugins at given path in the tree.
If not found, returns empty set.

Takes the '*' terminal label into account.

Frow every plugin, only its first instance in the list is preserved
(so a plugin will never be present twice).
]]
local function callbacks_find(tree, path)
	local pre_result = {};
	local node = tree;
	for _, level in ipairs(path) do
		-- If there's a .* here, add it to the result
		table.insert(pre_result, (node.subnodes["*"] or {}).plugins or {});
		node = node.subnodes[level] or { subnodes = {} };
	end
	-- Add the final node's plugins
	table.insert(pre_result, node.plugins or {});
	local result = {};
	-- Flatten the result to a single list
	for _, partial in ipairs(pre_result) do
		table.extend(result, partial);
	end
	return table.uniq(result);
end

--[[
Register a plugin. It'll be inserted into the tree for callbacks.
]]
function supervisor:register_plugin(plugin)
	table.insert(self.plugins, plugin);
	for _, path in pairs(plugin:positions()) do
		register_to_tree(self.tree, path, plugin);
	end
end

--[[
Get list of plugins that are valid for given path.
]]
function supervisor:get_plugins(path)
	if not path then
		return self.plugins
	else
		return callbacks_find(self.tree, path);
	end
end

-- Can't use the local function syntax, due to mutual dependency with merge_data
local build_children;

--[[
Take the values and convert them to a tree (eg. compact the common beginnings
of paths), creating a table-built tree. The tree is compatible with the
xmltree library.
]]
local function merge_data(values, level)
	local level = level or 1; -- If not provided, we start from the front

	--[[
	We first divide the values by their name in path on the current level.
	We have some names for the children and we set the ones wich end here
	]]
	local children_defs = {};
	local local_defs = {};
	for _, value in ipairs(values) do
		local name = value.path[level];
		if name then
			-- Get the data gathered for the child or a new list
			local def = children_defs[name] or {};
			children_defs[name] = def;
			table.insert(def, value);
		else
			table.insert(local_defs, value);
		end
	end
	--[[
	Now we have definitions for all the children, so we handle them
	(indirectly) recursively and concatenate the results together.
	Beware that there may be multiple results from one name of child.
	]]
	local children = {};
	local child_error;
	for name, values in pairs(children_defs) do
		local children_local, err = build_children(name, values, level);
		table.extend(children, children_local);
		if err then
			child_error = true;
		end;
	end
	-- Extract the local information to something more digestible
	local seen_multival;
	local multivals = {};
	local seen_val;
	local vals = {};
	local err_val;
	for _, value in ipairs(local_defs) do
		if value.multival then
			seen_multival = true;
			table.insert(multivals, value.multival);
		else
			seen_val = true;
			if next(vals) and not value.val then
				err_val = true;
			end
			table.insert(vals, value.val);
		end
	end
	-- Check for error conditions
	if seen_val and seen_multival then -- Both single and multi value?
		err_val = true;
	end
	if seen_val then
		local prev; -- All shall be the same
		for _, val in ipairs(vals) do
			if prev and prev ~= val then
				err_val = true;
			end
			prev = val;
		end
	end
	if seen_multival then
		local prev; -- All shall be the same, but we don't care about the order
		for _, mval in ipairs(multivals) do
			if prev then
				-- Little bit of abuse, but it works.
				if not match_keysets(list2map(prev), list2map(mval)) then
					err_val = true;
				end
			end
			prev = mval;
		end
	end
	-- Build the nodes
	local function build_result(value)
		local result = { children = children, text = value };
		local errors = {};
		if child_error then
			table.insert(errors, 'children');
		end
		if err_val then
			table.insert(errors, 'value');
		end
		if next(errors) then
			result.errors = errors;
			result.source = values;
		end
		return result;
	end
	local result = {};
	if seen_multival then
		for _, val in ipairs(multivals[1]) do
			table.insert(result, build_result(val));
		end
	else
		table.insert(result, build_result(vals[1]));
	end
	return result;
end

build_children = function(name, values, level)
	local result = {};
	while next(values) do -- Pick a keyset, filter it out and process
		local keyset = (values[1].keys or { [level] = {} })[level];
		local picked, rest = {}, {};
		local key_list = {};
		-- FIXME: Check the key sets are for the same indexes (#2697)
		-- FIXME: Choose order of the keys (#2696)
		for name, value in pairs(keyset) do
			table.insert(key_list, { name = name, text = value });
		end
		for _, value in ipairs(values) do
			if match_keysets(keyset, (value.keys or { [level] = {} })[level]) then
				table.insert(picked, value);
			else
				table.insert(rest, value);
			end
		end
		values = rest;
		local generated = merge_data(picked, level + 1);
		for _, child in pairs(generated) do
			local children = {};
			-- The keys must go first
			table.extend(children, key_list);
			table.extend(children, child.children or {});
			child.children = children;
		end
		table.extend(result, generated);
	end
	for _, child in pairs(result) do
		child.name = name;
	end
	return result;
end

--[[
Check that the tree with data from the plugins is built. If not, build it.
]]
function supervisor:check_tree_built()
	if not self.cached then
		-- Nothing ready yet. Build the complete tree and store it.

		--[[
		Make sure the data is wiped out after the current operation.
		Both after success and failure.

		Let it happen after we (possibly) push changes to the UCI system,
		but before we commit UCI.
		]]
		commit_hook_success(function() self:invalidate_cache() end, 0);
		commit_hook_failure(function() self:invalidate_cache() end, 0);
		-- First, let each plugin dump everything and store it for now.
		local values = {};
		for _, plugin in ipairs(self:get_plugins) do
			local pvalues, errors = plugin:get();
			if errors then
				return nil, errors;
			end
			-- We call the get() without path and keys, to get everything
			for _, value in pairs(pvalues) do
				value.from = plugin; -- Remember who provided this ‒ for debugging and tracking of differences in future
			end
			table.extend(values, pvalues);
		end
		-- Go through the values and merge them together, in preorder DFS
		self.data = merge_data(values)[1]; -- There must be exactly 1 result at the top level
		-- Index the direct sub-children, for easier lookup.
		-- We assume there's just single one of each name.
		self.index = {}
		for _, subtree in pairs(self.data.children or {}) do
			self.index[subtree.name] = subtree;
		end
		--[[
		TODO: Collision and error checking ‒ walk the tree and call relevant plugins
		on the places where something happens. (#2680)
		]]
		self.cached = true;
	end
end

function supervisor:get(name, ns)
	self:check_tree_built();
	--[[
	Extract the appropriate part of tree and convert to XML.

	First, take the part of the tree by the name, set up the namespace and
	run it through the xmltree module.
	]]
	local subtree = self.index[name] or { name = name };
	subtree.namespace = ns;
	return xmltree_dump(subtree);
end

--[[
Invalidate cache, most useful after a complete get or editconfig request.
]]
function supervisor:invalidate_cache()
	self.cached = nil;
	self.data = nil;
	self.index = nil;
end

--[[
Generate a usual datasource provider based on the supervisor and views.
Pass the yin file, the rest is extracted from it.
]]
function supervisor:generate_datasource_provider(yin_name)
	local datastore = datastore(yin_name);
	local supervisor = self;

	function datastore:get()
		local doc, err = supervisor:get(self.model_name, self.model_ns);

		if doc then
			return doc:strdump();
		else
			return nil, err;
		end
	end

	return datastore;
end
