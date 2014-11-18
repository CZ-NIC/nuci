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

require("datastore");

local datastore = datastore("updater.yin");

local state_dir = '/tmp/update-state';

local tags = {
	I = 'install',
	R = 'remove',
	D = 'download'
};

-- TODO: Read this from some file that's periodically updated from the server
local lists = {
	['luci-controls'] = {
		title_cs = 'LuCI rozšíření',
		description_cs = 'Mnoho rozšiřujících záložek a ovládacích prvků do pokročilého rozhraní LuCI.',
		title_en = 'LuCI extensions',
		description_en = 'Several additional tabs and controls for the advanced LuCI interface.'
	},
	nas = {
		title_cs = 'NAS',
		title_en = 'NAS',
		description_cs = 'Služby umožňující připojit disk k routeru a používat jej jako síťové úložiště dat.',
		description_en = 'Services allowing to connect a disk to the router and use it as network data store.'
	},
	printserver = {
		title_cs = 'Tiskový server',
		title_en = 'Print server',
		description_cs = 'Služby umožňující připojit tiskárnu k routeru a používat ji pro tisk po síti.',
		description_en = 'Services allowing to connect a printer to the router and use it for remote printing.'
	},
	netutils = {
		title_cs = 'Rozšíření síťové podpory',
		title_en = 'Extensions of network protocols',
		description_cs = 'Podpora dalších protokolů a druhů připojení.',
		description_en = 'Support for additional protocols and connection types.'
	},
	['shell-utils'] = {
		title_cs = 'Pohodlnější příkazová řádka',
		title_en = 'More comfortable command line',
		description_cs = 'Programy usnadňující používání příkazové řádky (např. bash či vim).',
		description_en = 'Programs making life in command line slightly easier (like bash or vim).'
	},
	majordomo = {
		title_cs = 'Majordomo',
		title_en = 'Majordomo',
		description_cs = 'Software pro sledování spojení jednotlivých zařízení v síti.',
		description_en = 'Software for monitoring connections of devices in local network.'
	}
};

function datastore:get()
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

	for name, list in pairs(lists) do
		local lnode = root:add_child('pkg-list');
		lnode:add_child('name'):set_text(name);
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

register_datastore_provider(datastore)
