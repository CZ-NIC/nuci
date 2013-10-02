require("datastore");
require("nutils");

local datastore = datastore('registration.yin');

function datastore:user_rpc(rpc)
	if rpc == 'get' then
		local ecode, stdout, stderr = run_command(nil, 'sh', '-c', 'curl --cacert /etc/ssl/vorner.pem https://test-dev.securt.cz/challenge.cgi | atsha204cmd challenge-response');
		if ecode ~= 0 then
			return nil, "Can't generate challenge";
		end
		local ecode, serial = run_command(nil, 'atsha204cmd', 'serial-number');
		if ecode ~= 0 then
			return nil, "Can't get my own serial";
		end
		return "<reg-num xmlns='" .. self.model_ns .. "'>" .. trimr(serial) .. "-" .. trimr(stdout) .. "</reg-num>";
	else
		return nil, 'TODO:  Proper error message';
	end
end

register_datastore_provider(datastore)
