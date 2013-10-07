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

register_datastore_provider(datastore);
