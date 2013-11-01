require("datastore");

local datastore = datastore("password.yin");

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'set' then
		nlog(NLOG_DEBUG, "Setting password");
		local password_node = find_node_name_ns(root, 'password', self.model_ns);
		if not password_node then
			return nil, {
				msg = "Missing the <password> parameter, don't know what to use as password",
				app_tag = 'data-missing',
				info_badelem = 'password',
				info_badns = self.model_ns
			};
		end
		local user_node = find_node_name_ns(root, 'user', self.model_ns);
		if not user_node then
			return nil, {
				msg = "Missing the <user> parameter, don't whose password to set",
				app_tag = 'data-missing',
				info_badelem = 'user',
				info_badns = self.model_ns
			};
		end
		local input = password_node:text() .. "\n";
		input = input .. input;
		local ecode, stdout, stderr = run_command(input, 'passwd', user_node:text());
		if ecode ~= 0 then
			return nil, "Failed to set password: " .. stderr;
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

register_datastore_provider(datastore);
