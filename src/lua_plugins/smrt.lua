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

local datastore = datastore("smrt.yin");

local state_dir = '/tmp/smrtd';

function datastore:get()
	local xml = '<' .. self.model_name .. ' xmlns="' .. self.model_ns .. '">';
	local ok, dirs = pcall(function() return dir_content(state_dir) end);
	if not ok then
		nlog(NLOG_WARN, "The directory " .. state_dir .. " can't be scanned ‒ it probably doesn't exist: " .. dirs);
		return '';
	end
	for _, dir in ipairs(dirs) do
		local name = dir.filename:match('([^/]*)$')
		xml = xml .. '<interface><name>' .. name .. '</name>';
		local file, errstr = io.open(dir.filename);
		if file then
			for line in file:lines() do
				xml = xml .. line;
			end
			file:close();
		else
			nlog(NLOG_ERROR, "Can't read " .. dir.filename .. ": " .. errstr);
			return '';
		end
		xml = xml .. '</interface>';
	end
	xml = xml .. '</' .. self.model_name .. '>';
	return xml;
end

register_datastore_provider(datastore)
