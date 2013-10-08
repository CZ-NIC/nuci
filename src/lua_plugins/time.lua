require("datastore");
require("nutils");

local datastore = datastore("time.yin");

function datastore:get()
	local xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
	local root = xml:root();

	local timezone;
	get_uci_cursor():foreach("system", "system", function(s)
		timezone = s.timezone;
	end);

	local code, local_time, stderr = run_command(nil, 'date', '-Iseconds');
	if code ~= 0 then
		return nil, "Could not determine local time: " .. stderr;
	end
	local code, utc_time, stderr = run_command(nil, 'date', '-Iseconds', '-u');
	if code ~= 0 then
		return nil, "Could not determine UTC time: " .. stderr;
	end

	root:add_child('timezone'):set_text(timezone);
	root:add_child('local'):set_text(trimr(local_time));
	root:add_child('utc'):set_text(trimr(utc_time));

	return xml:strdump();
end

local function systohc()
	-- TODO: Check the RTC is really there on the final hardware (#2724)
	local code, stdout, stderr = run_command(nil, 'sh', '-c', 'if [ -e /dev/misc/rtc ] ; then hwclock -u -w ; fi');
	if code == 0 then
		return '<ok/>';
	else
		return nil, "Failed to store the time to hardware clock: " .. stderr;
	end
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'set' then
		local time_node = find_node_name_ns(root, 'time', self.model_ns);
		if not time_node then
			return nil, {
				msg = "Missing the <time> parameter, don't know what to set the time to",
				app_tag = 'data-missing',
				info_badelem = 'time',
				info_badns = self.model_ns
			};
		end
		local year, month, day, hour, minute, second = string.match(time_node:text(), '(....)-(..)-(..)T(..):(..):(..)');
		if not year then
			return nil, {
				msg = "Malformed <time> parameter (tip: it should look something like 1970-01-01T00:00:00+0100)",
				app_tag = 'invalid-value',
				info_badelem = 'time',
				info_badns = self.model_ns
			};
		end
		local utc = find_node_name_ns(root, 'utc', self.model_ns);
		local target_time = year .. '.' .. month .. '.' .. day .. '-' .. hour .. ':' .. minute .. ':' .. second;
		local code, stdout, stderr;
		if utc then
			code, stdout, stderr = run_command(nil, 'date', '-u', '-s', target_time);
		else
			code, stdout, stderr = run_command(nil, 'date', '-s', target_time);
		end
		if code ~= 0 then
			return nil, "Failed to set time: " .. stderr;
		end
		return systohc();
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
