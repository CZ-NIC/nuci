require("datastore");
require("nutils");

local datastore = datastore('registration.yin');

function datastore:get()
	local ecode, serial_output, errs = run_command(nil, 'atsha204cmd', 'serial-number');

	if ecode ~= 0 then
		return nil, "Failed to acquire own serial number: " .. errs;
	end

	local ecode, challenge_output, errs = run_command('0000000000000000000000000000000000000000000000000000000000000000', 'atsha204cmd', 'challenge-response');

	if ecode ~= 0 then
		return nil, "Failed to compute the serial extention: " .. errs;
	end

	local serial = trimr(serial_output) .. "-" .. trimr(challenge_output);

	-- Encode it as XML
	local doc, root, node;
	doc = xmlwrap.new_xml_doc("registration", self.model_ns);
	root = doc:root();
	root:add_child("serial"):set_text(serial);
	return doc:strdump();
end

register_datastore_provider(datastore)
