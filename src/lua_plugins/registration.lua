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
require("nutils");

local datastore = datastore('registration.yin');

-- Where we get the challenge
local challenge_url = 'https://api.turris.cz/challenge.cgi';

-- Where registration lookup url
local lookup_url = 'https://www.turris.cz/api/registration-lookup.txt';

local connection_timeout = 10

function simple_escape(str)
	return str:gsub("[ :/?#%[%]@!$&'()*+,;=]", function (char)
	    return string.format('%%%02X', string.byte(char))
	end)
end

function get_registration_code()
	--[[
	Download the challenge and generate a response to it.

	Notice that the challenge doesn't check certificate here. It is simply not needed.
	If someone is able to MITM the communication, they'd be able to only prevent
	generation of the correct response, but that would be possible with the
	cert checking too.
	]]
	local ecode, stdout, stderr = run_command(nil, 'sh', '-c', 'curl -k -m ' .. connection_timeout .. ' ' .. challenge_url .. ' | atsha204cmd challenge-response');
	if ecode ~= 0 then
		return nil, "Can't generate challenge: " .. stderr;
	end
	return trimr(stdout:sub(1, 16))
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'get' then
		local registration_code, err_msg = get_registration_code()
		if not registration_code then
			return nil, err_msg
		end
		return "<reg-num xmlns='" .. self.model_ns .. "'>" .. registration_code .. "</reg-num>";

	elseif rpc == 'serial' then
		local ecode, stdout, stderr = run_command(nil, 'atsha204cmd', 'serial-number');
		if ecode ~= 0 then
			return nil, "Can't get serial number: " .. stderr;
		end
		return "<serial xmlns='" .. self.model_ns .. "'>" .. trimr(stdout) .. "</serial>";

	elseif rpc == 'get-status' then
		local email_node = find_node_name_ns(root, 'email', self.model_ns);
		if not email_node then
			return nil, {
				msg = "Missing the <email> parameter, can't query the server without an email",
				app_tag = 'data-missing',
				info_badelem = 'email',
				info_badns = self.model_ns
			}
		end
		local language_node = find_node_name_ns(root, 'lang', self.model_ns);
		local language = 'en';
		if code_node and language_node:text():len() == 2 then  -- expect 2 letter for country code
			language = language_node:text();
		end
		local registration_code, err_msg = get_registration_code();
		if not registration_code then
			return nil, err_msg;
		end

		-- update crl
		run_command(nil, 'get-api-crl');

		-- query the server
		local ecode, stdout, stderr = run_command(
			nil, 'curl', '-s', '-S', '-L', '-H', '"Accept-Language: ' .. language .. '"',
			'-H', '"Accept: plain/text"', '--cacert', '/etc/ssl/www_turris_cz_ca.pem', '--cert-status',
			'-m', tostring(connection_timeout), '-w', "\ncode: %{http_code}",
			lookup_url .. "?registration_code=" .. registration_code .. "&email=" .. simple_escape(email_node:text())
		);
		if ecode ~= 0 then
			return nil, "The communication with the registration web failed: " .. stderr;
		end

		-- test for errors
		local err = stdout:match("^error:%s*([^\n]+)")
		if err then
			return nil, {
				msg = "Error occured: " .. err .. ' (registration_code=' .. registration_code .. ', email=' .. email_node:text() .. ')',
				app_tag = 'operation-failed',
			}
		end

		-- read the http code - the last occurence of `code:`
		-- (it should be appended by curl)
		local http_code = stdout:match(".*code:%s*(%d+)")
		if http_code ~= "200" then
			return nil, {
				msg = "Unexpected http status occured: " .. http_code .. ' (registration_code=' .. registration_code .. ', email=' .. email_node:text() .. ')',
				app_tag = 'operation-failed',
			}
		end

		-- parse the answer
		local status = stdout:match("status:%s*([^\n]+)")

		if not status then
			return nil, "Mandatory status missing in the server response: " .. stdout;
		end
		if not(status == "free" or status == "owned" or status == "foreign") then
			return nil, "Incorrect status obtained for the server: " .. status;
		end
		url = stdout:match("url:%s*([^\n]+)")
		if not url and (status == "free" or status == "foreign") then
			return nil, "Missing url in the server response: " .. stdout;
		end

		-- build xml response
		local xml_response = xmlwrap.new_xml_doc("get-status", self.model_ns);
		local node = xml_response:root();
		node:add_child('status'):set_text(status);
		if url then
			node:add_child('url'):set_text(url);
		end
		node:add_child('reg-num'):set_text(registration_code);

		return xml_response:strdump();

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
