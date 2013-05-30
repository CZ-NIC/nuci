--[[
Turn the <edit-config /> method into a list of trivial changes to the given
current config. The current_config, command and model are lxml2 objects. The
defop and errop are strings, specifying the default operation/error operation
on the document.

Returns either the table of modifications to perform on the config, or nil,
error. The error can be directly passed as result of the operation.
]]
function editconfig(current_config, command, module, defop, errop)
	print(current_config, command, module, defop, errop);
end
