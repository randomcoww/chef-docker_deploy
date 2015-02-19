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
        @action = :create_and_rotate
        @allowed_actions = [:create_if_missing, :create, :create_and_rotate, :stop, :remove]
        
        @name = name
      end

      def name(arg = nil)
        set_or_return(
          :name,
          arg,
          :kind_of => [String],
        )
      end

      # chef node name of container. also used for the hostname of the container
      # node not set if chef credentials are not provided
      def node_name(arg = nil)
        set_or_return(
          :node_name,
          arg,
          :kind_of => [String],
          :default => name
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

      # try to stop running containers that would conflict with the new container
      def stop_conflicting(arg = nil)
        set_or_return(
          :stop_conflicting,
          arg,
          :kind_of => [TrueClass, FalseClass],
          :default => true
        )
      end

      # wrapper scipt in /etc/init.d
      def script_template(arg = nil)
        set_or_return(
          :script_template,
          arg,
          :kind_of => [String],
          :default => 'wrapper_script.erb'
        )
      end

      def script_cookbook(arg = nil)
        set_or_return(
          :script_cookbook,
          arg,
          :kind_of => [String],
          :default => 'docker_deploy'
        )
      end

      def script_path(arg = nil)
        set_or_return(
          :script_path,
          arg,
          :kind_of => [String],
          :default => '/etc/init.d'
        )
      end

      # use with chef init
      def chef_secure_dir(arg = nil)
        set_or_return(
          :chef_secure_dir,
          arg,
          :kind_of => [String],
          :default => ::File.join(Chef::Config[:cache_path], name)
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
        )
      end

      # used for removing chef node and client of container
      def chef_admin_user(arg = nil)
        set_or_return(
        :chef_admin_user,
        arg,
        :kind_of => [String, NilClass],
        :default => nil
      )
      end

      def chef_admin_key(arg = nil)
        set_or_return(
        :chef_admin_key,
        arg,
        :kind_of => [String, NilClass],
        :default => nil
      )
      end
    end
  end
end
