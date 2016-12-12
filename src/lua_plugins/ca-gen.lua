--[[
Copyright 2016, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

local datastore = datastore("ca-gen.yin");
local ca_dir = '/etc/ssl/ca'

local states = {
	V = 'active',
	E = 'expired',
	R = 'revoked'
};

local function get_ca(dir, cas)
	-- Try to read the CA data from files.
	local path = dir .. '/';
	local name = dir:match('[^/]+$');
	local gen, gen_err = slurp(path .. 'generating');
	local index, index_err = slurp(path .. 'index.txt');
	local notes, notes_err = slurp(path .. 'notes.txt');
	local ca_done = file_exists(path .. 'ca.crt');
	local dh_done = file_exists(path .. 'dhparam.pem');
	local crl_done = file_exists(path .. 'ca.crl');
	local fatal = index_err or notes_err;
	if fatal then return fatal ; end
	-- Post-process the files
	gen = trimr(gen or '');
	-- We don't have the root CA in the metadata, so add it here to easy up the rest of code
	local notes_parsed = {};
	if ca_done or gen:match('^-- root ') then
		notes_parsed['--'] = {
			kind = 'root',
			name = name,
			fname = 'ca';
		}
	end
	local files = {
		ca = '--'
	}
	local indexes = {};
	if not gen:match('^-- root ') then
		indexes['--'] = 'active'; -- TODO: Do we want to actually parse the CA cert to decide if it expired?
	end
	-- Parse the CA metadata
	for line in lines(notes) do
		local serial, kind, name = line:match('^([^%s]+)%s+([^%s]+)%s+(.*)');
		if serial then
			local fname = kind .. '-' .. name
			notes_parsed[serial] = {
				kind = kind,
				name = name,
				fname = fname
			};
			files[fname] = serial;
		else
			return nil, "Broken notes line in " .. name .. ": " .. line;
		end
	end
	local now = os.date("%y%m%d%H%M%S"); -- It is so ordered that we can compare just as a number. We don't care about the time zone, the error would be small enough to not matter.
	for line in lines(index) do
		local status, date, serial = line:match('([VER])%s+(%d+)Z%s+(%d+)');
		if status then
			if now > date then
				-- Handle the case when the expiration passed, but the index haven't been updated yet
				status = 'E';
			end
			indexes[serial] = states[status]
		else
			return nil, "Broken index line in " .. name .. ": " .. line;
		end
	end
	-- Once we have read it, add the CA into the XML
	local ca = cas:add_child('ca')
	ca:add_child('name'):set_text(name)
	-- Add a certificate into the output
	local function add_cert(idx)
		local gen_exp;
		local note = notes_parsed[idx];
		if not note then
			return "Missing info about certificate " .. idx;
		end
		local kind = note.kind;
		local name = note.name;
		local status = indexes[idx] or 'generating'; -- If it is not in index, it might still be generated
		if status == 'generating' then
			local gen_exp = idx .. ' ' .. kind .. ' ' .. name;
			if gen ~= gen_exp then
				-- Ignore this cert, it is not there (leftover from crashed generation?)
				nlog(NLOG_WARN, "Generation not running, but " .. idx .. " not present");
				return
			end;
		end
		if status == 'active' and files[note.fname] ~= idx then
			-- Overwritten by something else
			status = 'lost';
		end
		local cert = ca:add_child('cert');
		cert:add_child('serial'):set_text(idx);
		cert:add_child('name'):set_text(name);
		cert:add_child('type'):set_text(kind);
		cert:add_child('status'):set_text(status);
		if status == 'active' then
			local cfile = path .. note.fname;
			cert:add_child('cert'):set_text(cfile .. '.crt');
			cert:add_child('key'):set_text(cfile .. '.key');
		end
	end
	local idx_sorted = iter2list(pairs(notes_parsed));
	table.sort(idx_sorted);
	for _, idx in ipairs(idx_sorted) do -- Notes are updated first, so they contain even the unfinished ones
		add_cert(idx);
	end
	if dh_done or gen == 'dhparams' then
		local dh = ca:add_child('dhparams');
		dh:add_child('file'):set_text(path .. "dhparam.pem");
		if gen == 'dhparams' then
			dh:add_child('generating');
		end
	end
	if crl_done then
		ca:add_child('crl'):set_text(path .. 'ca.crl');
	end
end

function datastore:get()
	local xml = xmlwrap.new_xml_doc('cas', self.model_ns);
	local cas = xml:root();

	local ok, dirs = pcall(function() return dir_content(ca_dir) end);

	if not ok then
		nlog(NLOG_WARN, "The CA dir not found");
	else
		for _, ca in ipairs(dirs) do
			if ca.type == 'd' then
				local ca_result = get_ca(ca.filename, cas);
				if ca_result then
					return nil, 'ca ' .. ca .. ': ' .. ca_result;
				end
			end
		end
	end

	return xml:strdump();
end

register_datastore_provider(datastore)
