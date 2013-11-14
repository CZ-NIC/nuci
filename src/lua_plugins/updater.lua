require("datastore");

local datastore = datastore("updater.yin");

local state_dir = '/tmp/update-state';

local tags = {
	I = 'install',
	R = 'remove'
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

	local last_file = io.open(state_dir .. '/log');
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
