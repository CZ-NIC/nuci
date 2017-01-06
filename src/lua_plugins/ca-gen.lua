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
require("cert");

local datastore = datastore("ca-gen.yin");
local ca_dir = '/etc/ssl/ca'
local script_dir = '/usr/share/nuci/ca/';
local script = script_dir .. 'gen';

local states = {
	V = 'active',
	E = 'expired',
	R = 'revoked'
};

local function get_ca(dir, cas)
	-- Try to read the CA data from files.
	local path = dir .. '/';
	local name = dir:match('[^/]+$');
	local gen, gen_err = file_content(path .. 'generating');
	local index, index_err = file_content(path .. 'index.txt');
	local notes, notes_err = file_content(path .. 'notes.txt');
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

local function notes_parse(path, name)
	local content, err = file_content(path);
	if err then return nil, err end
	local result = {
		['--'] = {
			kind = 'root',
			name = name,
			fname = 'ca'
		}
	};
	for line in lines(content) do
		local serial, kind, name = line:match('^([^%s]+)%s+([^%s]+)%s+(.*)');
		if serial then
			local fname = kind .. '-' .. name
			result[serial] = {
				kind = kind,
				name = name,
				fname = fname
			};
		else
			return nil, "Broken notes line in " .. name .. ": " .. line;
		end
	end
	return result;
end

function datastore:download_cert(ca_path, notes, output, cert)
	local serial = find_node_name_ns(cert, 'serial', self.model_ns);
	if not serial then
		return {
			msg = "Missing <serial>",
			app_tag = 'data-missing',
			info_badelem = 'serial',
			info_badns = self.model_ns
		};
	end
	serial = serial:text();
	if not notes[serial] then
		return {
			msg = "Missing certificate " .. serial,
			app_tag = 'invalid-value',
			info_badelem = 'serial',
			info_badns = self.model_ns
		};
	end
	local o = output:add_child('cert');
	o:add_child('serial'):set_text(serial);
	local basename = ca_path .. '/' .. notes[serial].fname;
	o:add_child('cert'):set_text(file_content(basename .. '.crt'));
	if find_node_name_ns(cert, 'key', self.model_ns) then
		o:add_child('key'):set_text(file_content(basename .. '.key'));
	end
end

function datastore:name_get(from)
	local name = find_node_name_ns(from, 'name', self.model_ns)
	if not name then
		return nil, {
			msg = "Missing <name>",
			app_tag = 'data-missing',
			info_badelem = 'name',
			info_badns = self.model_ns
		};
	end
	name = name:text();
	if not verify_cert_name(name) then
		return nil, {
			msg = "Invalid CA name: " .. name,
			app_tag = 'invalid-value',
			info_badelem = 'name',
			info_badns = self.model_ns
		}
	end
	return name
end

function datastore:download_ca(ca)
	local output = xmlwrap.new_xml_doc('ca', self.model_ns)
	local root = output:root();
	local name, err = self:name_get(ca);
	if not name then
		return nil, err;
	end
	local path = ca_dir .. '/' .. name;
	root:add_child('name'):set_text(name);
	local parsed, err = notes_parse(path .. '/notes.txt', name);
	if err then return nil, err end
	for cert in ca:iterate() do
		local cname, cns = cert:name();
		if cns == self.model_ns and cname == 'cert' then
			local err = self:download_cert(path, parsed, root, cert);
		end
	end
	local crlfile = path .. '/ca.crl';
	if find_node_name_ns(ca, 'crl', self.model_ns) and file_exists(crlfile) then
		root:add_child('crl'):set_text(file_content(crlfile));
	end
	local dhfile = path .. '/dhparam.pem';
	if find_node_name_ns(ca, 'dhparams', self.model_ns) and file_exists(dhfile) then
		root:add_child('dhparams'):set_text(file_content(dhfile));
	end
	return output;
end

local function append(into, what)
	for _, v in ipairs(what) do
		table.insert(into, v)
	end
end

function datastore:ca_gen_params(ca)
	local params = {}
	local name, err = self:name_get(ca);
	if not name then
		return nil, err;
	end
	if find_node_name_ns(ca, 'new', self.model_ns) then
		append(params, {'new_ca', name, 'gen_ca', name});
	else
		append(params, {'switch', name});
	end
	if find_node_name_ns(ca, 'dhparams', self.model_ns) then
		table.insert(params, 'gen_dh');
	end
	for cert in ca:iterate() do
		local cname, cns = cert:name();
		if cns == self.model_ns and cname == 'cert' then
			local name, err = self:name_get(cert);
			if not name then
				return nil, err;
			end
			local kind = find_node_name_ns(cert, 'type', self.model_ns);
			if not kind then
				return nil, {
					msg = "Missing <type>",
					app_tag = 'data-missing',
					info_badelem = 'type',
					info_badns = self.model_ns
				};
			end
			kind = kind:text();
			if kind ~= 'server' and kind ~= 'client' then
				return nil, {
					msg = 'Invalid cert type: ' .. kind,
					app_tag = 'invalid-value',
					info_badelem = 'type',
					info_badns = self.model_ns
				};
			end
			append(params, {'gen_' .. kind, name});
		end
	end
	return params;
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();
	if rpc == 'download' then
		-- Unfortunately, we return part of XML and this one wouldn't have single root, so we build each one separately and concatenate as strings. We are supposted to return string anyway.
		local output = ''
		for ca_child in root:iterate() do
			local name, ns = ca_child:name();
			if ns == self.model_ns and name == 'ca' then
				local out, err = self:download_ca(ca_child);
				if err then
					return err;
				end
				output = output .. strip_xml_def(out:strdump());
			end
		end
		return output
	elseif rpc == 'generate' then
		local params = {}
		-- Do we want to run in the background?
		if find_node_name_ns(root, 'background', self.model_ns) then
			table.insert(params, 'background')
		end
		-- Go through all the CAs and their internal requests
		for ca_child in root:iterate() do
			local name, ns = ca_child:name();
			if ns == self.model_ns and name == 'ca' then
				local ca_params, err = self:ca_gen_params(ca_child);
				if err then
					return nil, err;
				end
				append(params, ca_params);
			end
		end
		local ecode, stdout, stderr = run_command(nil, script, unpack(params));
		if ecode == 0 then
			return '<ok/>';
		else
			return nil, stderr;
		end
	elseif rpc == 'delete-ca' then
		local params = {}
		for ca_child in root:iterate() do
			local name, ns = ca_child:name();
			if ns == self.model_ns and name == 'ca' then
				local ca_name = ca_child:text();
				if not verify_cert_name(ca_name) then
					return nil, {
						msg = "Invalid CA name: " .. ca_name,
						app_tag = 'invalid-value',
						info_badelem = 'ca',
						info_badns = self.model_ns
					};
				end
				append(params, {'drop_ca', ca_name});
			end
		end
		local ecode, stdout, stderr = run_command(nil, script, unpack(params));
		if ecode == 0 then
			return '<ok/>';
		else
			return nil, stderr;
		end
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
