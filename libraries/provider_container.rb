require 'chef/provider'
require 'chef/provider/directory'
require 'chef/resource/directory'
require 'chef/provider/template'
require 'chef/resource/template'
require 'chef/provider/file'
require 'chef/resource/file'

class Chef
  class Provider
    class DockerDeployContainer < Chef::Provider

      include DockerHelper

      def initialize(*args)
        super
        
        @container_create_options = []
        @cache_resources = nil
        @secure_resources = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployContainer.new(new_resource.service_name)
        @current_resource
      end




      ##
      ## add extra build parameters and create new container
      ##

      def unique_container_name
        return DockerWrapper::Container.unique_name(new_resource.service_name)
      end

      def create_unique_container
        @container_create_options << %Q{--hostname="#{new_resource.service_name}"}
        @container_create_options << %Q{--env="CHEF_NODE_NAME=#{new_resource.service_name}"}
        @container_create_options << %Q{--volume="#{new_resource.chef_secure_path}:/etc/chef/secure"}
        @container_create_options << %Q{--name="#{unique_container_name}"}

        return DockerWrapper::Container.create((@container_create_options + new_resource.container_create_options).join(' '), "#{new_resource.base_image}:#{new_resource.base_image_tag}", new_resource.command.join(' '))
      end

      ##
      ## replace container name
      ##

      def replace_container_name(container)
        begin
          ## rename container that currently holds service name (if any)
          old_container = DockerWrapper::Container.get(new_resource.service_name)
          old_container.rename(unique_container_name) unless container == old_container
        rescue
        end

        container.rename(new_resource.service_name)
      end

      ##
      ## create chef credentials and start container
      ##

      def start_container(container)
        populate_chef_secure_path
        Chef::Log.info("Starting container #{container.id}...")
        container.start
      end

      ##
      ## path for writing CID and other files
      ##

      def cache_path
        return @cache_resources unless @cache_resources.nil?

        @cache_resources = Chef::Resource::Directory.new(::File.join(new_resource.cache_path), run_context)
        @cache_resources.recursive(true)

        return @cache_resources
      end

      ##
      ## path for chef keys. mounted to container
      ##

      def chef_secure_path
        return @secure_resources unless @secure_resources.nil?

        @secure_resources = Chef::Resource::Directory.new(::File.join(new_resource.chef_secure_path), run_context)
        @secure_resources.recursive(true)

        return @secure_resources
      end

      ##
      ## chef client key file
      ##

      def client_key_file
        return @client_key_file unless @client_key_file.nil?

        @client_key_file = ::File.join(new_resource.chef_secure_path, 'client.pem')
        return @client_key_file
      end

      ##
      ## write CID file to cache path
      ##

      def populate_cache_path(container)
        cache_path.run_action(:create)

        r = Chef::Resource::File.new(::File.join(new_resource.cache_path, 'cid'), run_context)
        r.content(container.id)
        r.run_action(:create)
      end

      ##
      ## write chef keys to secure path
      ##

      def populate_chef_secure_path
        chef_secure_path.run_action(:create)

        unless new_resource.encrypted_data_bag_secret.nil?
          r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_path, 'encrypted_data_bag_secret'), run_context)
          r.content(new_resource.encrypted_data_bag_secret)
          r.sensitive(true)
          r.run_action(:create)
        end

        unless chef_client_valid(chef_server_url, new_resource.service_name, client_key_file)
          r = Chef::Resource::File.new(client_key_file, run_context)
          r.sensitive(true)
          r.run_action(:delete)
        end

        unless ::File.exists?(client_key_file) or new_resource.validation_key.nil?
          r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_path, 'validation.pem'), run_context)
          r.content(new_resource.validation_key)
          r.sensitive(true)
          r.run_action(:create)
        end

        unless new_resource.data_bags.empty?
          write_data_bags(new_resource.data_bags(new_resource.chef_secure_path, 'data_bags'))
        end
      end

      ##
      ## remove chef node for this container
      ##

      def remove_chef_node
        remove_from_chef(chef_server_url, new_resource.service_name, client_key_file)
      end

      ##
      ## remove cache path and CID file
      ##

      def remove_cache_path
        cache_path.run_action(:delete)
      end

      ##
      ## remove chef keys and secure path
      ##

      def remove_chef_secure_path
        chef_secure_path.run_action(:delete)
      end

      ##
      ## write container name and ID mapping to service name
      ##

      def set_service_mapping(container)
        node.default['docker_deploy']['service_mapping'][new_resource.service_name]['id'] = container.id
        node.default['docker_deploy']['service_mapping'][new_resource.service_name]['name'] = container.name
      end

      ##
      ## remove container name from config so that they can be compared
      ##

      def clean_hostconfig(container)
        hostconfig = container.hostconfig
        return hostconfig if hostconfig.empty?

        return hostconfig['Links'].map { |k|
          j = k.split('/')
          if j[2] == container.name
            j[2] = new_resource.service_name
          end

          j.join('/')
        } unless hostconfig['Links'].nil?

        return hostconfig
      end

      ##
      ## wrapper for tweaking the config if needed
      ##

      def clean_config(container)
        return container.config 
      end



      ##
      ## actions
      ##

      def action_create
        ## create the new container
        container = create_unique_container
        config = clean_config(container)
        hostconfig = clean_hostconfig(container)

        containers_rotate = {}
        ## look for similar containers
        DockerWrapper::Container.all('-a').each do |c|
          ## skip if service name doesn't not match
          next unless new_resource.service_name == c.hostname
          ## found self
          next if c == container

          if (compare_config(clean_config(c), config) and
            compare_config(clean_hostconfig(c), hostconfig))
            ## similar container already exists. remove the new one
            remove_container(container)
            container = c
            #break
          else
            stop_container(c) if c.running?
            containers_rotate[c.finished_at] = c
          end
        end

        populate_cache_path(container)

        converge_by("Started container #{new_resource.service_name}") do
          start_container(container)
          new_resource.updated_by_last_action(true)
        end unless container.running?

        replace_container_name(container)
        set_service_mapping(container)

        ## rotate out older containers
        keys = containers_rotate.keys.sort
        while (keys.size > 0 and keys.size >= new_resource.keep_releases)
          remove_container(containers_rotate[keys.shift])
        end
      end

      def action_stop
        converge_by("Stopped container for #{new_resource.service_name}") do
          DockerWrapper::Container.all.each do |c|
            ## look for matching hostname
            next unless new_resource.service_name == c.hostname

            if c.running?
              stop_container(c) 
              new_resource.updated_by_last_action(true)
            end
          end
        end
      end

      def action_remove
        converge_by("Removed containers for #{new_resource.service_name}") do
          DockerWrapper::Container.all('-a').each do |c|
            ## look for matching service name
            next unless new_resource.service_name == c.hostname

            remove_container(c)
            new_resource.updated_by_last_action(true)
          end

          remove_chef_node
          remove_chef_secure_path
          remove_cache_path
        end
      end

      def action_nothing
      end
    end
  end
end
