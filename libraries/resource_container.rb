require 'chef/resource'
require 'chef/resource/service'

class Chef
  class Resource
    class DockerDeployContainer < Chef::Resource

      attr_accessor :exists

      def initialize(name, run_context=nil)
        super

        @resource_name = :docker_deploy_container
        @provider = Chef::Provider::DockerDeployContainer
        @action = :create
        @allowed_actions = [:create, :stop, :remove, :nothing]
        
        @name = service_name
      end

      # chef node name of container. also used for the hostname of the container
      # node not set if chef credentials are not provided
      def service_name(arg = nil)
        set_or_return(
          :service_name,
          arg,
          :kind_of => [String],
          :regex => [/[a-zA-Z0-9_-]+/]
        )
      end

      def container_base_name(arg = nil)
        set_or_return(
          :container_base_name,
          arg,
          :kind_of => [String],
          :default => service_name,
          :regex => [/[a-zA-Z0-9_-]+/]
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

      def container_create_options(arg = nil)
        set_or_return(
          :container_create_options,
          arg,
          :kind_of => [Array],
          :default => []
        )
      end

      def cache_path(arg = nil)
        set_or_return(
          :cache_path,
          arg,
          :kind_of => [String],
          :default => ::File.join(Chef::Config[:cache_path], 'docker_deploy', service_name)
        )
      end

      def chef_secure_path(arg = nil)
        set_or_return(
          :chef_secure_path,
          arg,
          :kind_of => [String],
          :default => ::File.join(cache_path, 'chef')
        )
      end

      # use with chef init
      def enable_local_mode(arg = nil)
        set_or_return(
          :enable_local_mode,
          arg,
          :kind_of => [TrueClass, FalseClass],
          :default => false
        )
      end

      def chef_server_url(arg = nil)
        set_or_return(
          :chef_server_url,
          arg,
          :kind_of => [String],
          :default => Chef::Config[:chef_server_url]
        )
      end

      def encrypted_data_bag_secret(arg = nil)
        set_or_return(
          :encrypted_data_bag_secret,
          arg,
          :kind_of => [String],
        )
      end

      def validation_key(arg = nil)
        set_or_return(
          :validation_key,
          arg,
          :kind_of => [String],
        )
      end

      # use with rotating container
      # keep this many containers with a common node_name. remove extra
      def keep_releases(arg = nil)
        set_or_return(
          :keep_releases,
          arg,
          :kind_of => [Integer],
          :default => 3,
          :callbacks => {
          "should be greater than 0" => lambda {
            |p| p > 0
            }
          }
        )
      end
    end
  end
end
