require("datastore");
require("nutils");

local datastore = datastore('registration.yin');

-- Where we get the challenge
local challenge_url = 'https://test-dev.securt.cz/challenge.cgi';

function datastore:user_rpc(rpc)
	if rpc == 'get' then
		--[[
		Download the challenge and generate a response to it.

		Notice that the challenge doesn't check certificate here. It is simply not needed.
		If someone is able to MITM the communication, they'd be able to only prevent
		generation of the correct response, but that would be possible with the
		cert checking too.
		]]
		local ecode, stdout, stderr = run_command(nil, 'sh', '-c', 'curl -k ' .. challenge_url .. ' | atsha204cmd challenge-response');
		if ecode ~= 0 then
			return nil, "Can't generate challenge";
		end
		return "<reg-num xmlns='" .. self.model_ns .. "'>" .. trimr(stdout) .. "</reg-num>";
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
