require 'chef/resource'
require 'chef/resource/service'

class Chef
  class Resource
    class DockerDeployImage < Chef::Resource

      attr_accessor :exists

      def initialize(name, run_context=nil)
        super

        @resource_name = :docker_deploy_image
        @provider = Chef::Provider::DockerDeployImage
        @action = :pull_if_missing
        @allowed_actions = [:pull_if_missing, :pull, :build_if_missing, :build, :push, :remove_if_unused, :nothing]
        
        @name = name
      end

      def name(arg = nil)
        set_or_return(
          :name,
          arg,
          :kind_of => [String],
        )
      end

      def tag(arg = nil)
        set_or_return(
          :tag,
          arg,
          :kind_of => [String],
          :default => 'latest'  
        )
      end

      def base_image(arg = nil)
        set_or_return(
          :base_image,
          arg,
          :kind_of => [String],
        )
      end

      def base_image_tag(arg = nil)
        set_or_return(
          :base_image_tag,
          arg,
          :kind_of => [String],
        )
      end

      def dockerbuild_options(arg = nil)
        set_or_return(
          :dockerbuild_options,
          arg,
          :kind_of => [Array],
          :default => ['--force-rm=true']
        )
      end

      ##
      ## enable to run container in local mode (chef solo)
      ##

      def enable_local_mode(arg = nil)
        set_or_return(
          :enable_local_mode,
          arg,
          :kind_of => [TrueClass, FalseClass],
          :default => false
        )
      end

      ##
      ## environment for container
      ##

      def chef_environment(arg = nil)
        set_or_return(
          :chef_environment,
          arg,
          :kind_of => [String],
          :default => node.chef_environment
        )
      end

      ##
      ## encrupted_data_bag_secret
      ##

      def encrypted_data_bag_secret(arg = nil)
        set_or_return(
          :encrypted_data_bag_secret,
          arg,
          :kind_of => [String],
        )
      end

      ##
      ## Dockerfile
      ##

      def dockerfile_template(arg = nil)
        set_or_return(
          :dockerfile_template,
          arg,
          :kind_of => [String],
          :default => enable_local_mode ? 'local/Dockerfile.erb' : 'Dockerfile.erb'
        )
      end

      def dockerfile_template_cookbook(arg = nil)
        set_or_return(
          :dockerfile_template_cookbook,
          arg,
          :kind_of => [String],
          :default => 'docker_deploy'
        )
      end

      def dockerfile_commands(arg = nil)
        set_or_return(
          :dockerfile_commands,
          arg,
          :kind_of => [Array],
          :default => []
        )
      end

      ##
      ## first-boot.json as in http://docs.getchef.com/containers.html#container-services
      ##

      def first_boot(arg = nil)
        set_or_return(
          :first_boot,
          arg,
          :kind_of => [Hash],
          :default => {}
        )
      end

      ##
      ## preload data bags needed for chef run. encrypted data bags are left encrypted.
      ## {'bag_name' => ['bag_item1', 'bag_item2']}
      ##

      def data_bags(arg = nil)
        set_or_return(
          :local_data_bags,
          arg,
          :kind_of => [Hash],
          :default => {}
        )
      end

      ##
      ## zero.rb
      ##

      def local_template(arg = nil)
        set_or_return(
          :local_template,
          arg,
          :kind_of => [String],
          :default => 'local/zero.rb.erb'
        )
      end

      def local_template_cookbook(arg = nil)
        set_or_return(
          :local_template_cookbook,
          arg,
          :kind_of => [String],
          :default => 'docker_deploy'
        )
      end

      def local_template_variables(arg = nil)
        set_or_return(
          :local_template_variables,
          arg,
          :kind_of => [Hash],
          :default => {
            :chef_environment => chef_environment,
          }
        )
      end

      ##
      ## use with chef server
      ##

      def chef_server_url(arg = nil)
        set_or_return(
          :chef_server_url,
          arg,
          :kind_of => [String],
          :default => Chef::Config[:chef_server_url]
        )
      end

      def validation_client_name(arg = nil)
        set_or_return(
          :validation_client_name,
          arg,
          :kind_of => [String],
          :default => Chef::Config[:validation_client_name]
        )
      end

      ##
      ## client.rb
      ##

      def config_template(arg = nil)
        set_or_return(
          :config_template,
          arg,
          :kind_of => [String],
          :default => 'client.rb.erb'
        )
      end

      def config_template_cookbook(arg = nil)
        set_or_return(
          :config_template_cookbook,
          arg,
          :kind_of => [String],
          :default => 'docker_deploy'
        )
      end

      def config_template_variables(arg = nil)
        set_or_return(
          :config_template_variables,
          arg,
          :kind_of => [Hash],
          :default => {
            :chef_server_url => chef_server_url,
            :validation_client_name => validation_client_name,
            :chef_environment => chef_environment,
          }
        )
      end
    end
  end
end
