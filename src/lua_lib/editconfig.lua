--[[
Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)

This file is part of NUCI configuration server.

NUCI is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

NUCI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
]]

require("nutils");

local netconf_ns = 'urn:ietf:params:xml:ns:netconf:base:1.0'
local yang_ns = 'urn:ietf:params:xml:ns:yang:yin:1'

-- Compare names and namespaces of two nodes
local function cmp_elemname(command_node, config_node)
	local name1, ns1 = command_node:name();
	local name2, ns2 = config_node:name();
	ns1 = ns1 or ns; -- The namespace may be missing from the command XML, as it is only snippet
	return name1 == name2 and ns1 == ns2;
end
-- Compare names, namespaces and their text
local function cmp_name_content(command_node, config_node)
	return cmp_elemname(command_node, config_node, ns, model) and command_node:text() == config_node:text();
end

-- Find a leaf of the given name and extract its content.
-- Convert to the canonical notation according to its type (described in model).
-- Both the node and the model are for the supernode of what we want.
local function extract_leaf_subvalue(node, model, name)
	local _, ns = node:name();
	local subnode = find_node_name_ns(node, name, ns);
	if subnode then
		-- TODO: Do the canonization (#2708)
		return subnode:text();
	end
end

-- Names of valid node names in model, with empty data for future extentions
local model_names = {
	leaf={
		cmp=cmp_elemname
	},
	['leaf-list']={
		cmp=cmp_name_content
	},
	container={
		cmp=cmp_elemname,
		children=true
	},
	list={
		cmp=function(command_node, config_node, ns, model)
			-- First, it must be the same kind of thing (name and ns)
			if not cmp_elemname(command_node, config_node, ns, model) then
				return false;
			end
			local keys = list_keys(model);
			for key_name in keys do
				nlog(NLOG_TRACE, (command_key or "[nil value]"));
				local command_key = extract_leaf_subvalue(command_node, model, key_name);
				nlog(NLOG_TRACE, (command_key or "[nil value]"));
				if not command_key then
					return nil, {
						msg="Missing key in configuration: " .. key_name,
						tag="data-missing",
						info_badelem=model,
						info_badns=ns
					};
				end
				local config_key = extract_leaf_subvalue(config_node, model, key_name);
				if not config_key or config_key ~= command_key then
					return false;
				end
			end
			return true; -- No key differs
		end,
		children=true
	}
	-- TODO: AnyXML. What to do with that? (#2709)
}

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
			for model_name, model_opts in pairs(model_names) do
				-- Found allowed name, all done
				if name == model_name then
					return model, model_opts;
				end
			end
			-- Not a valid name. Try next node.
		end
	end
end

-- Look through the config and try to find a node corresponding to the command_node one. Consider the model.
local function config_identify(model_node, model_opts, command_node, config, ns)
	local cmp_func = model_opts.cmp;
	-- It is OK not to find, returning nothing then.
	return find_node(config, function(node)
		return cmp_func(command_node, node, ns, model_node);
	end);
end

-- Perform operation on all the children here.
local function children_perform(config, command, model, ns, defop, errop, ops)
	for command_node in command:iterate() do
		local command_name, command_ns = command_node:name();
		if command_ns == ns then
			local model_node, model_opts = model_identify(model, command_name);
			if not model_node then
				-- TODO What about errop = continue?
				return {
					msg="Unknown element",
					tag="unknown-element",
					info_badelem=command_name
				};
			end
			nlog(NLOG_TRACE, "Found model node ", model_node:name(), " for ", command_name);
			local config_node, err = config_identify(model_node, model_opts, command_node, config, ns);
			if err then
				return err;
			end

			-- Is there an override for the operation here?
			local operation = command_node:attribute('operation', netconf_ns) or defop;
			-- What we are asked to do (may be different from what we actually do)
			local asked_operation = operation;
			if operation == 'merge' and not model_opts.children then
				-- Merge on leaf(like) element just replaces it.
				operation = 'replace'
			end
			if config_node then
				nlog(NLOG_TRACE, "Found config node ", config_node:name(), " for ", command_name);
				-- The value exists
				if operation == 'create' then
					return {
						msg="Can't create an element, such element already exists: " .. command_name,
						tag="data-exists",
						info_badelem=command_name,
						info_badns=command_ns
					};
				end
				if operation == 'delete' then
					-- Normalize
					operation = 'remove';
				end
				if operation == 'merge' then
					-- We are in containerish node, that has no value, so just recurse
					operation = 'none';
				end
			else
				nlog(NLOG_TRACE, "Not found corresponding node");
				-- The value does not exist in config now
				if operation == 'none' or operation == 'delete' then
					return {
						msg="Missing element in configuration: " .. command_name,
						tag="data-missing",
						info_badelem=command_name,
						info_badns=command_ns
					};
				end
				if operation == 'replace' or operation == 'merge' then
					-- Normalize to something common
					operation = 'create';
				end
			end
			if operation == 'replace' and not model_opts.children and config_node:text() == command_node:text() then
				-- We should replace a node without any children with the same one.
				-- Skip it.
				operation = 'none';
			end
			--[[
			Now, after normalization, we have just 5 possible operations:
			* none (recurse)
			* replace (translated to remove and create)
			* create
			* remove
			]]
			nlog(NLOG_TRACE, "Performing operation ", operation);
			local function add_op(name, note)
				nlog(NLOG_TRACE, "Adding operation ", name, '(', (note or ''), ')', ' on ', command_node:name());
				table.insert(ops, {
					op=name,
					command_node=command_node,
					model_node=model_node,
					config_node=config_node,
					note=note
				});
			end
			local replace_note;
			if operation == 'replace' then
				replace_note = 'replace';
			end
			if (operation == 'remove' or operation == 'replace') and config_node then
				add_op('remove-tree', replace_note);
			end
			if operation == 'create' or operation == 'replace' then
				local create_scan;
				create_scan = function(command_node)
					for node in command_node:iterate() do
						local op = node:attribute('operation', netconf_ns);
						if op == 'remove' then -- It doesn't exist, but don't add it.
							node:delete();
							-- Restart the scan of this node because the deletion probably invalidated the iterator
							return create_scan(command_node);
						elseif op == 'delete' then
							local name, ns = node:name();
							return {
								msg="Missing element in configuration: " .. name,
								tag="data-missing",
								info_badelem=name,
								info_badns=ns
							};
						else
							local err = create_scan(node);
							if err then
								return err;
							end
						end
					end
					return nil;
				end
				local err = create_scan(command_node);
				if err then
					return err;
				end
				add_op('add-tree', replace_note);
			end
			if operation == 'none' then
				-- We recurse to the rest
				add_op('enter');
				local op_last = #ops;
				local err = children_perform(config_node, command_node, model_node, ns, asked_operation, errop, ops);
				if err then
					return err;
				end
				if #ops == op_last then
					nlog(NLOG_TRACE, "Dropping the last enter, as the command is empty");
					ops[op_last] = nil;
				else
					add_op('leave');
				end
			end
		elseif command_ns then
			-- Skip empty namespaced stuff, that's just the whitespace between the nodes
			return {
				msg="Element in foreing namespace found",
				tag="unknown-namespace",
				info_badns=command_ns
			};
		end
	end
end
--[[
Turn the <edit-config /> method into a list of trivial changes to the given
current config. The current_config, command and model are xmlwrap objects. The
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
	local ops = {};
	if defop == 'notset' then
		defop = 'merge'; -- Compat mode, we didn't have notset before, collapse it.
	end
	err = children_perform(config_node, command_node, model_node, ns, defop, errop, ops);
	return ops, err;
end

--[[
Go through the list of operations and apply them using definitions from the passed description.

TODO: Describe the description.
]]
function applyops(ops, description)
	local desc_stack = {}
	local current_desc = description;
	nlog(NLOG_DEBUG, "Opcount: ", #ops);
	for i, op in ipairs(ops) do
		nlog(NLOG_TRACE, "Operation ", op.op);
		local result;
		local recursing = 0;
		-- Stack manipulation function
		local function pop()
			if recursing > 0 then return end; -- Recursion manages the stack itself
			-- Pop the stack
			if current_desc.leave then
				current_desc.leave(op);
			end
			current_desc = table.remove(desc_stack);
			if not current_desc then
				error('More leaves then enters!');
			end
		end
		local function push()
			if recursing > 0 then return end; -- Recursion manages the stack itself
			-- Store the current one in the stack
			local name, ns = op.command_node:name();
			table.insert(desc_stack, current_desc);
			-- Go one level deeper.
			current_desc = (current_desc.children or {})[name];
			if ns ~= description.namespace or not current_desc then
				-- This should not get here, it is checked by editconfig above
				error('Entering invalid node ' .. name .. '@' .. ns);
			end
			if current_desc.enter then
				current_desc.enter(op)
			end
		end
		local apply;
		-- Recurse through children and apply the operation on them.
		local function recurse(name, node, operation)
			nlog(NLOG_TRACE, "Recurse ", name);
			-- Prepare list of skipped children
			local skip = list2map(current_desc[name .. '_recurse_skip'] or {});
			-- Have a list of mandatory sub nodes (and remove them if we see them)
			local mandatory = list2map(current_desc[name .. '_recurse_mandatory'] or {});
			-- Go through children and apply their operations on them.
			for child in node:iterate() do
				local nname, nns = child:name();
				nlog(NLOG_TRACE, "Child ", nname, "@", (nns or ""));
				if nns == description.namespace then -- Namespace is ours
					mandatory[nname] = nil; -- Seen this, mandatory satisfied
					if not skip[nname] then
						nlog(NLOG_TRACE, "Recursing ", nname);
						table.insert(desc_stack, current_desc);
						current_desc = (current_desc.children or {})[nname];
						if not current_desc then
							result = {
								msg="Unknown element " .. nname,
								tag="unknown-element",
								info_badelem=nname,
								info_badns=nns
							}
							return;
						end
						if current_desc.enter then
							current_desc.enter({command_node=child, config_node=child})
						end
						apply(name, child, child, child, op);
						if not result and current_desc.leave then
							current_desc.leave({command_node=child, config_node=child});
						end
						current_desc = table.remove(desc_stack);
						if result then
							return;
						end
					else
						nlog(NLOG_TRACE, "Skipping ", nname);
					end;
				elseif nns then -- Some foreign stuff
					result = {
						msg="Foreign namespace " .. nns .. " with element " .. nname,
						tag="unknown-namespace",
						info_badelem=nname,
						info_badns=nns
					}
					return;
				end -- Else: empty, some text node or so.
			end
			local missing = next(mandatory);
			if missing then
				result = {
					msg="Missing mandatory element <" .. missing .. "/>",
					tag="data-missing",
					info_badelem=missing,
					info_badns=description.namespace
				}
				return;
			end
		end
		-- Apply a function or other behaviour to the operation.
		apply = function(name, node, node_before, node_after, operation, older_operation)
			nlog(NLOG_TRACE, "Apply ", name, " to ", node:name());
			push();
			if current_desc[name .. '_recurse_before'] then
				recursing = recursing + 1;
				recurse(current_desc[name .. '_recurse_before'], node_before, operation);
				recursing = recursing - 1;
			end
			if not result then
				nlog(NLOG_TRACE, "Tag: ", (current_desc.dbg or '<none>'));
				local what = current_desc[name];
				if not what then
					local nname, nns = node:name();
					result = {
						msg="Can not " .. name .. " " .. nname .. '@' .. nns,
						tag="operation-not-supported",
						info_badelem=name,
						info_badns=nns
					};
				elseif type(what) == 'table' or type(what) == 'string' then
					result = what;
				else
					nlog(NLOG_TRACE, "Func");
					result = current_desc[name](node, operation, older_operation)
				end
			end
			if not result and current_desc[name .. '_recurse_after'] then
				recursing = recursing + 1;
				recurse(current_desc[name .. '_recurse_after'], node_after, operation);
				recursing = recursing - 1;
			end
			pop();
		end
		-- What operation is it?
		if op.op == 'leave' then
			pop();
		elseif op.op == 'enter' then
			push();
		elseif op.op == 'add-tree' then
			local name = op.command_node:name();
			if ((current_desc.children or {})[name] or {}).replace and op.note == 'replace' then
				apply('replace', op.command_node, op.config_node, op.command_node, op, ops[i - 1]);
			else
				apply('create', op.command_node, op.command_node, op.command_node, op);
			end
		elseif op.op == 'remove-tree' then
			local name = op.config_node:name();
			if not (((current_desc.children or {})[name] or {}).replace and op.note == 'replace') then
				apply('remove', op.config_node, op.config_node, op.config_node, op);
			end
		else
			error("Unknown operation " .. op.op);
		end
		if result then -- An error happened
			return result;
		end
	end
end
