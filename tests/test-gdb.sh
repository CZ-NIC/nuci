#!/bin/bash

export NUCI_TEST_CONFIG_DIR="./example-config"

(
read

cat <<ENDXML
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <capabilities>
    <capability>urn:ietf:params:netconf:base:1.0</capability>
  </capabilities>
</hello>
]]>]]><?xml version='1.0' encoding='UTF-8'?><rpc xmlns='urn:ietf:params:xml:ns:netconf:base:1.0' message-id='4'><edit-config>
    <target>
        <running/>
    </target>
    <config></config>
</edit-config>
</rpc>
]]>]]>
ENDXML

read
) | socat STDIO EXEC:'./bin/nuci -e trace -s disable',pty
