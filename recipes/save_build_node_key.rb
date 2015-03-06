keyfile = Chef::Config[:client_key]
node.default['build_node_client_key'] = ::File.read(keyfile) if ::File.exists?(keyfile)
