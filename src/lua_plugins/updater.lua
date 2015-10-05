--[[
Copyright 2013-2015, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

require("datastore");

local datastore = datastore("updater.yin");

local state_dir = '/tmp/update-state';

local tags = {
	I = 'install',
	R = 'remove',
	D = 'download'
};

local function load_user_list_definitions()
	local definitions_file_path = os.getenv("NUCI_UPDATER_DEFINITION_PATH") or '/usr/share/updater/definitions'
	--[[
	The file contains lua code, assigning the right table to lists variable.
	That's why it looks like lists is never assigned in this code.
	]]
	local lists_ok, lists_error = pcall(loadfile(definitions_file_path))
	if not lists_ok then
		nlog(NLOG_ERROR, "Failed to load user list definitions: " .. lists_error .. ". file possibly not downloaded yet");
		lists = {};
	end
end

local function get_active_lists(cursor, func)
	-- Load activated lists from uci
	local res;
	local uci_ok, uci_res = pcall(
		function() return cursor:get("updater", "pkglists", "lists") end
	)
	if uci_ok then
		if uci_res then
			for idx, user_list in pairs(uci_res) do
				func(user_list);
			end
		else
			-- this might happen quite often and should not be considered as an error
			nlog(NLOG_WARN, "Uci updater user lists might be empty!");
		end
		return true;
	else
		if uci_res then
			nlog(NLOG_ERROR, "Failed to load updater config: " .. uci_res);
		else
			nlog(NLOG_ERROR, "Failed to load updater config.");
		end
		return nil, {
			msg = "Failed to use uci!",
			tag = "operation-failed",
			type = "application",
			severity = "error",
		};
	end
end

function datastore:get()
	load_user_list_definitions();

	local xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
	local root = xml:root();

	-- First wipe out any outdated updater status.
	local code, stdout, stderr = run_command(nil, 'updater-wipe.sh');
	if code ~= 0 then
		return nil, "Failed to wipe updater: " .. stderr;
	end

	local failure_file = io.open(state_dir .. '/last_error');
	local failure;
	if failure_file then
		failure = trimr(failure_file:lines()());
		failure_file:close();
	end
	local state_file = io.open(state_dir .. '/state');
	local state;
	if state_file then
		state = trimr(state_file:lines()());
		state_file:close();
	end
	if state == 'done' or state == 'error' then
		state = nil;
	elseif state == 'lost' then
		state = nil;
		failure = 'Disappeared without a trace';
	end

	if state then
		root:add_child('running'):set_text(state);
	end

	if failure then
		root:add_child('failed'):set_text(failure);
	end

	local last_file = io.open(state_dir .. '/log2');
	if last_file then
		local last_act = root:add_child('last_activity');
		for line in last_file:lines() do
			local line = trimr(line);
			if #line then
				local op = string.match(line, '.');
				local package = string.match(line, '.%s+(.*)');
				local tag = tags[op];
				if not tag then
					return nil, 'Corrupt state file, found operation ' .. op;
				end
				last_act:add_child(tag):set_text(package);
			end
		end
		last_file:close();
	end

	local offline_file = io.open('/tmp/offline-update-ready');
	if offline_file then
		root:add_child('offline-pending');
		offline_file:close();
	end

	-- Load activated lists from uci
	local cursor = get_uci_cursor();
	local activated_set = {};
	local uci_res, uci_error = get_active_lists(cursor, function (list_name)
		activated_set[list_name] = true;
	end);
	reset_uci_cursor();
	if not uci_res then
		return uci_res, uci_error;
	end

	for name, list in pairs(lists) do
		local lnode = root:add_child('pkg-list');
		lnode:add_child('name'):set_text(name);
		if activated_set[name] then
			lnode:add_child('activated');
		end
		for name, value in pairs(list) do
			local tp, lang = name:match('(.*)_(.*)');
			local node = lnode:add_child(tp);
			node:set_text(value);
			node:set_attribute('xml:lang', lang);
		end
	end

	return xml:strdump();
end

function datastore:user_rpc(rpc)
	if rpc == 'check' then
		local code, stdout, stderr = run_command(nil, 'updater.sh', '-b', '-n');
		if code ~= 0 then
			return nil, "Failed to run the updater: " .. stderr;
		end
		return '<ok/>';
	else
		return nil, {
			msg = "Command '" .. rpc .. "' not known",
			app_tag = 'unknown-element',
			info_badelem = rpc,
			info_badns = self.model_ns
		};
	end
end

function datastore:get_config()
	local xml = xmlwrap.new_xml_doc('updater-config', self.model_ns);
	local root = xml:root();
	local lists_node = root:add_child('active-lists');

	-- Load activated lists from uci
	local cursor = get_uci_cursor();
	local uci_res, uci_error = get_active_lists(cursor, function (list_name)
		lists_node:add_child('user-list'):add_child('name'):set_text(list_name);
	end);
	reset_uci_cursor();
	if not uci_res then
		return uci_res, uci_error;
	end

	return strip_xml_def(xml:strdump());
end

function datastore:set_config(config, defop, deferr)
	local ops, err, current, operation = self:edit_config_ops(config, defop, deferr);
	if err then
		return err;
	end

	load_user_list_definitions();

	local remove_set, append_set = {}, {};

	name_descr = {
		replace = {
			msg="Can't replace name, replace the whole owner",
			tag="operation-not-supported",
			bad_elemname='name',
			bad_elemns=self.model_ns
		},
		remove = {
			msg="Can't delete mandatory node name",
			tag="data-missing",
			bad_elemname='name',
			bad_elemns=self.model_ns
		},
		create = {
			msg="Can't (directly) create node name",
			tag="data-exists",
			bad_elemname='name',
			bad_elemns=self.model_ns
		},
		dbg = 'name'
	}

	local user_list_descr = {
		create = function(node)
			local list_name, err = extract_multi_texts(node, {'name'}, self.model_ns);
			if not list_name then
				return err;
			end

			-- Is this a valid list name? var lists contains all valid lists
			if not lists[list_name[1]] then
				return {
					msg = "List '" .. list_name[1] .. "' in not a valid  user list.",
					tag = "invalid-value",
					info_badelem = 'user-list',
					info_badns=self.model_ns
				};
			end
			append_set[list_name[1]] = true;
		end,

		remove = function(node)
			local list_name, err = extract_multi_texts(node, {'name'}, self.model_ns);
			if not list_name then
				return err;
			end

			remove_set[list_name[1]] = true;
		end,

		children = {
			name = name_descr
		},

		dbg="user-list"
	}

	local active_lists_descr = {
		remove = function()
			return {
				msg = "Deleting active-lists not possible",
				tag = "operation-not-supported",
				info_badelem = 'active-lists',
				info_badns = self.model_ns
			};
		end,

		create = function()
			return {
				msg = "Creating active-lists not possible",
				tag = "operation-not-supported",
				info_badelem = 'active-lists',
				info_badns=self.model_ns
			};
		end,

		 -- We don't do anything when replacing the active-lists except recurse into user-lists
		replace = function(node)
		end,

		replace_recurse_before='remove',
		replace_recurse_after='create',

		-- When we enter a active-lists, we're going to change stuff inside, so schedule it for commit.
		enter = function(operation)
			commit_mark_dirty('updater');
		end,

		children = {
			['user-list'] = user_list_descr
		},
		dbg = "active-lists"
	};

	local updater_descr = {
		namespace = self.model_ns,
		children = {
			['updater-config'] = {
				children = {
					['active-lists'] = active_lists_descr
				}
			}
		},
		dbg = "updater-config"
	};

	local err = applyops(ops, updater_descr);
	if err then
		return err;
	end

	-- update uci
	local cursor = get_uci_cursor();
	local activated_set = {};
	local uci_res, uci_error = get_active_lists(cursor, function (list_name)
		activated_set[list_name] = true;
	end);
	if not uci_res then
		reset_uci_cursor();
		return uci_res, uci_error;
	end
	local final_list = {};

	for name, _ in pairs(lists) do
		-- keep existing (expect for the removed)
		if activated_set[name] and not remove_set[name] then
			table.insert(final_list, name);
		end
		-- add new
		if append_set[name] then
			table.insert(final_list, name);
		end
	end

	-- commit all into uci
	local final_res, final_err_msg;
	if #final_list == 0 then
		if #activated_set ~= 0 and not cursor:delete('updater', 'pkglists', 'lists') then
			final_res = false;
		else
			final_res = true;
		end
	else
		if not cursor:set('updater', 'pkglists', 'lists', final_list) then
			final_res = false;
		else
			final_res = true;
		end
	end
	commit_execute(final_res);
	reset_uci_cursor();

	if not final_res then
		nlog(NLOG_ERROR, "Failed to update updater user lists in uci!");
		return {
			msg = "Failed to write into uci!",
			tag = "operation-failed",
			type = "application",
			severity = "error",
		};
	end

end

register_datastore_provider(datastore)
