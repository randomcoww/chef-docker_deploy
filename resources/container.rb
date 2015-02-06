actions :create_if_missing, :create, :create_and_rotate
default_action :create_if_missing
attr_accessor :exists

attribute :name, :kind_of => [String], :name_attribute => true
# chef node name of container. also used for the hostname of the container
attribute :node_name, :kind_of => [String]
attribute :base_image, :kind_of => [String]
attribute :base_image_tag, :kind_of => [String], :default => 'latest'
# format as in ["Config"]["Env"]. can also be set in :container_create_options
attribute :env, :kind_of => [Array], :default => []
# format as in ["HostConfig"]["PortBindings"]. can also be set in :container_start_options
attribute :port_bindings, :kind_of => [Hash], :default => {}
# format as in ["HostConfig"]["Binds"]. can also be set in :container_start_options
attribute :binds, :kind_of => [Array], :default => []
# config of ["Config"] as in https://docs.docker.com/reference/api/docker_remote_api_v1.15/#create-a-container
attribute :container_create_options, :kind_of => [Hash], :default => {}
# config of ["HostConfig"] as in https://docs.docker.com/reference/api/docker_remote_api_v1.15/#start-a-container
attribute :container_start_options, :kind_of => [Hash], :default => {}
# try to stop running containers that would conflict with the new container
attribute :stop_conflicting, :kind_of => [TrueClass, FalseClass], :default => false
# wrapper scipt
attribute :init_template, :kind_of => [String], :default => 'init.erb'
attribute :init_cookbook, :kind_of => [String], :default => 'docker_deploy'

## use with chef init
attribute :chef_secure_dir, :kind_of => [String]
attribute :chef_server_url, :kind_of => [String], :default => Chef::Config[:chef_server_url]
attribute :encrypted_data_bag_secret, :kind_of => [String]
attribute :validation_key, :kind_of => [String]

## use with rotating container
# keep this many containers with a common node_name. remove extra
attribute :keep_releases, :kind_of => [Integer], :default => 3
