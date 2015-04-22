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

      ##
      ## chef node name of container. also used for the hostname of the container
      ## node not set if chef credentials are not provided
      ##

      def service_name(arg = nil)
        set_or_return(
          :service_name,
          arg,
          :kind_of => [String],
          :regex => [/[a-zA-Z0-9_-]+/]
        )
      end

      ##
      ## generate container name like <base_name>-<random_hash>
      ##

      def container_base_name(arg = nil)
        set_or_return(
          :container_base_name,
          arg,
          :kind_of => [String],
          :default => service_name,
          :regex => [/[a-zA-Z0-9_-]+/]
        )
      end

      ##
      ## base image for this container
      ##

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

      ##
      ## command to run in container
      ##

      def command(arg = nil)
        set_or_return(
          :command,
          arg,
          :kind_of => [Array],
          :default => []
        )
      end

      ##
      ## main container config. array of options to pass into docker create
      ##

      def container_create_options(arg = nil)
        set_or_return(
          :container_create_options,
          arg,
          :kind_of => [Array],
          :default => []
        )
      end

      ##
      ## path for cid file and possibly other things in future
      ##

      def cache_path(arg = nil)
        set_or_return(
          :cache_path,
          arg,
          :kind_of => [String],
          :default => ::File.join(Chef::Config[:cache_path], 'docker_deploy', service_name)
        )
      end


      ##
      ## path exposed to container containing validation.pem and encrypted_data_bag_secret
      ##

      def chef_secure_path(arg = nil)
        set_or_return(
          :chef_secure_path,
          arg,
          :kind_of => [String, NilClass],
          :default => ::File.join(cache_path, 'chef')
        )
      end

      ##
      ## encrypted_data_bag_secret
      ##

      def encrypted_data_bag_secret(arg = nil)
        set_or_return(
          :encrypted_data_bag_secret,
          arg,
          :kind_of => [String, NilClass],
        )
      end

      ##
      ## pass in data bags to be read during container run
      ## {'bag_name' => ['bag_item1', 'bag_item2']}
      ##

      def data_bags(arg = nil)
        set_or_return(
          :data_bags,
          arg,
          :kind_of => [Hash],
          :default => {}
        )
      end

      ##
      ## validation.pem - don't set this if local mode
      ##

      def validation_key(arg = nil)
        set_or_return(
          :validation_key,
          arg,
          :kind_of => [String, NilClass],
        )
      end

      ##
      ## keep this many containers with a common node_name. remove extra
      ##

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

      ##
      ## use this hash key to store service name in labels
      ##

      def service_label_key(arg = nil)
        set_or_return(
          :service_label_key,
          arg,
          :kind_of => [String],
          :default => 'docker_deploy_service'
        )
      end
    end
  end
end
