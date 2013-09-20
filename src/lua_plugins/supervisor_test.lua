--[[
FIXME:

This file should not be part of official distribution. Delete in #2706 (together with the .yin).
]]
require("views_supervisor");

register_datastore_provider(supervisor:generate_datasource_provider('supervisor_test.yin'))
