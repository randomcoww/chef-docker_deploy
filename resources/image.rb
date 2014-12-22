actions :pull_if_missing, :try_pull_if_missing, :pull, :try_pull, :build_if_missing, :build, :push
default_action :pull_if_missing
attr_accessor :exists

attribute :name, :kind_of => [String], :name_attribute => true
attribute :tag, :kind_of => [String], :default => 'latest'

## use for build
attribute :build_dir, :kind_of => [String]
attribute :build_options, :kind_of => [Hash], :default => { 'forcerm' => true }
attribute :docker_build_commands, :kind_of => [Array], :default => []
# delete the build dir after build
attribute :remove_build_dir, :kind_of => [TrueClass, FalseClass], :default => true

## use for chef runlist build
attribute :base_image, :kind_of => [String]
attribute :base_image_tag, :kind_of => [String]
# client params
attribute :chef_server_url, :kind_of => [String], :default => Chef::Config[:chef_server_url]
attribute :chef_environment, :kind_of => [String], :default => node.chef_environment
attribute :validation_client_name, :kind_of => [String], :default => Chef::Config[:validation_client_name]
attribute :validation_key, :kind_of => [String]
attribute :encrypted_data_bag_secret, :kind_of => [String]
attribute :client_template, :kind_of => [String], :default => 'client.rb.erb'
attribute :client_template_cookbook, :kind_of => [String], :default => 'docker_deploy'
attribute :dockerfile_template, :kind_of => [String], :default => 'Dockerfile.erb'
attribute :dockerfile_template_cookbook, :kind_of => [String], :default => 'docker_deploy'
# content of first-boot.json as in http://docs.getchef.com/containers.html#container-services
attribute :first_boot, :kind_of => [Hash], :default => {}
attribute :build_node_name, :kind_of => [String]
# this is used to delete the temporary build node from the chef server
attribute :chef_admin_user, :kind_of => [String]
attribute :chef_admin_key, :kind_of => [String]

## authentication if needed
attribute :docker_user, :kind_of => [String]
attribute :docker_password, :kind_of => [String]
attribute :docker_email, :kind_of => [String]
