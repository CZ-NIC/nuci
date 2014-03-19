--[[
Copyright 2014, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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
require("nutils");

local datastore = datastore("user-notify.yin");

local dir = '/tmp/user-notify'
local test_dir = '/tmp/user-notify-test'

function send_message(subject, severity, text)
	local wdir = dir;
	if severity == 'test' then
		wdir = test_dir
	end;
	-- -t = trigger sending right now and wait for it to finish (and fail if it does so)
	local ecode, stdout, stderr = run_command(text, 'user-notify-send', '-s', severity, '-S', subject, '-d', wdir, '-t');
	if ecode ~= 0 then
		return "Failed to send: " .. stderr;
	end
	-- TODO: Delete the message if it's test, or leave it up for that thing?
	return '<ok/>';
end

local severities = { reboot = true, error = true, update = true };

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'message' then
		local data, err = extract_multi_texts(root, {'subject', 'severity', 'body'});
		if err then
			return nil, err;
		end
		if not severities[data[2]] then
			return {
				msg = 'Unknown message severity: ' .. data[2],
				app_tag = 'invalid-value',
				info_badelem = 'severity',
				info_badns = self.model_ns
			};
		end
		nlog(NLOG_INFO, "Sending message " .. data[1]);
		return send_message(data[1], data[2], data[3]);
	elseif rpc == 'test' then
		nlog(NLOG_INFO, "Sending test message");
		return send_message('Test', 'test', ':-)');
	elseif rpc == 'display' then
		local ids = {};
		for mid in root:iterate() do
			local name, ns = mid:name();
			if name == 'message-id' and ns == self.model_ns then
				local id = mid:text();
				table.insert(ids, id);
			end
		end
		local ecode, stdout, stderr = run_command(nil, 'user-notify-display', unpack(ids));
		if ecode ~= 0 then
			return nil, "Error marking messages as displayed: " .. stderr;
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

function datastore:get()
	return '';
end

register_datastore_provider(datastore);
