--[[
Copyright 2015, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

local datastore = datastore("nuci-tls.yin");
local dir = '/usr/share/nuci/tls/ca/';
local index_file = dir .. 'index.txt';
local states = {
	V = 'active',
	E = 'expired',
	R = 'revoked'
};

function datastore:get()
	local xml = xmlwrap.new_xml_doc('ca', self.model_ns);
	local root = xml:root();
	local index, err = io.open(index_file);
	if not index then
		nlog(NLOG_ERROR, "The nuci TLS CA is not ready: " .. err);
		return '';
	end
	local first = true;
	local now = os.date("%y%m%d%H%M%S"); -- It is so ordered that we can compare just as a number. We don't care about the time zone, the error would be small enough to not matter.
	for line in index:lines() do
		if first then -- Skip over the first certificate, which is the server
			first = false;
		else
			local status, date, name = line:match('([VER])%s+(%d+)Z%s+%d+%s+%w+%s+/CN=(.*)');
			if status then
				if now > date then
					-- Handle the case when the expiration passed, but the index haven't been updated yet
					status = 'E';
				end
				local node = root:add_child('client');
				node:add_child('name'):set_text(name);
				node:add_child('status'):set_text(states[status]);
			else
				return nil, "Bad line in " .. index_file .. ": " .. line;
			end
		end
	end
	return xml:strdump();
end

register_datastore_provider(datastore);
