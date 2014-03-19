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
	return '<ok/>';
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'message' then
		local data, err = extract_multi_texts(root, {'subject', 'severity', 'body'});
		if err then
			return nil, err;
		end
		return send_message(data[1], data[2], data[3]);
	elseif rpc == 'test' then
		nlog(NLOG_INFO, "Sending test message");
		return send_message('Test', 'test', ':-)');
	elseif rpc == 'display' then
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
