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

local dir = '/tmp/user_notify'
local test_dir = '/tmp/user_notify_test'

function send_message(severity, text)
	local wdir = dir;
	if severity == 'test' then
		wdir = test_dir;
		severity = 'error';
	end;
	-- -t = trigger sending right now and wait for it to finish (and fail if it does so)
	local ecode, stdout, stderr = run_command(nil, 'create_notification', '-t', '-d', wdir, '-s', severity, text);
	if ecode ~= 0 then
		return "Failed to send: " .. stderr;
	end
	return '<ok/>';
end

local severities = { restart = true, error = true, update = true, news = true };

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'message' then
		local data, err = extract_multi_texts(root, {'severity', 'body'}, self.model_ns);
		if err then
			return nil, err;
		end
		if not severities[data[1]] then
			return {
				msg = 'Unknown message severity: ' .. data[1],
				app_tag = 'invalid-value',
				info_badelem = 'severity',
				info_badns = self.model_ns
			};
		end
		nlog(NLOG_INFO, "Sending message " .. data[1]);
		return send_message(data[1], data[2]);
	elseif rpc == 'test' then
		nlog(NLOG_INFO, "Sending test message");
		local result = send_message('test', 'Test test test! :-)');
		run_command(nil, 'sh', '-c', 'rm -rf ' .. test_dir);
		return result;
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

function datastore:message(dir, root)
	function getcontent(name)
		local file, err = io.open(dir .. '/' .. name);
		if not file then return
			nil, err;
		end
		local result = file:read("*a");
		file:close();
		return trimr(result);
	end
	function exists(name)
		-- This is not really check for existence of file, but it is OK for our use ‒ the file should be readable if it exists
		local file, err = io.open(dir .. '/' .. name);
		if file then
			file:close();
			return true;
		else
			return false;
		end
	end
	local severity, seerr = getcontent('severity');
	local body, berr = getcontent('message');
	local err = serr or berr;
	if err then
		return err;
	end
	local sent = exists('sent_by_email');
	local displayed = exists('displayed');
	local id = dir:match('[^/]+$');
	local mnode = root:add_child('message');
	mnode:add_child('id'):set_text(id);
	mnode:add_child('body'):set_text(body);
	mnode:add_child('severity'):set_text(severity);
	if sent then
		mnode:add_child('sent');
	end
	if displayed then
		mnode:add_child('displayed');
	end
end

function datastore:get()
	local ecode = run_command(nil, 'sh', '-c', 'mkdir -p ' .. dir .. ' ; while ! mkdir ' .. dir .. '/.locked ; do sleep 1 ; done');
	if ecode ~= 0 then
		return nil, "Couldn't lock message storage";
	end
	local ok, result = pcall(function()
		local ok, dirs = pcall(function() return dir_content(dir) end);
		if not ok then
			nlog(NLOG_WARN, "The directory " .. dir .. " can't be scanned ‒ it probably doesn't exist: " .. dirs);
			return '';
		end
		local result = '';
		local xml = xmlwrap.new_xml_doc('messages', self.model_ns);
		local root = xml:root();
		for _, dir in ipairs(dirs) do
			if dir.filename:match('/[%d%-]+/?$') and dir.type == 'd' then -- Check it is message, not lockdir.
				local err = self:message(dir.filename, root);
				if err then
					nlog(NLOG_ERROR, "Message in " .. dir .. " is broken: " .. err);
				end
			end
		end
		return xml:strdump();
	end);
	run_command(nil, 'sh', '-c', 'rm -rf ' .. dir .. '/.locked');
	if ok then
		return result;
	else
		return nil, result;
	end
end

register_datastore_provider(datastore);
