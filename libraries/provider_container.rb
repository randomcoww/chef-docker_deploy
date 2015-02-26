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
        
        @rest = ChefRestHelper.new(new_resource.chef_server_url, new_resource.chef_admin_user, new_resource.chef_admin_key)
        @container_create_options = []
        @cache_resources = nil
        @secure_resources = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployContainer.new(new_resource.service_name)
        @current_resource
      end

      def create_unique_container
        @container_create_options << %Q{--hostname="#{new_resource.service_name}"}
        @container_create_options << %Q{--env="CHEF_NODE_NAME=#{new_resource.service_name}"}
        @container_create_options << %Q{--volume="#{new_resource.chef_secure_path}:/etc/chef/secure"}
        @container_create_options << %Q{--name="#{DockerWrapper::Container.unique_name(new_resource.container_base_name)}"}

        return DockerWrapper::Container.create((@container_create_options + new_resource.container_create_options).join(' '), "#{new_resource.base_image}:#{new_resource.base_image_tag}")
      end

      def start_container(container)
        populate_chef_secure_path unless @rest.exists?(new_resource.service_name)
        container.start
      end

      def stop_container(container)
        container.stop
        container.kill if container.running?
        raise StopContainer, "Unable to stop container #{container.name}" if container.running?
      end

      def remove_container(container)
        image = DockerWrapper::Image.new(container.parent_id)
        stop_container(container)

        container.rm
        begin
          image.rmi
        rescue
          Chef::Log.info("Not removing image in use #{image.id}")
        end
      end

      def cache_path
        return @cache_resources unless @cache_resources.nil?

        @cache_resources = Chef::Resource::Directory.new(::File.join(new_resource.cache_path), run_context)
        @cache_resources.recursive(true)

        return @cache_resources
      end

      def chef_secure_path
        return @secure_resources unless @secure_resources.nil?

        @secure_resources = Chef::Resource::Directory.new(::File.join(new_resource.chef_secure_path), run_context)
        @secure_resources.recursive(true)

        return @secure_resources
      end

      def populate_cache_path(container)
        cache_path.run_action(:create)

        r = Chef::Resource::File.new(::File.join(new_resource.cache_path, 'cid'), run_context)
        r.content(container.id)
        r.run_action(:create)
      end

      def populate_chef_secure_path
        chef_secure_path.run_action(:create)

        unless new_resource.encrypted_data_bag_secret.nil?
          r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_path, 'encrypted_data_bag_secret'), run_context)
          r.content(new_resource.encrypted_data_bag_secret)
          r.sensitive(true)
          r.run_action(:create)
        end

        r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_path, 'client.pem'), run_context)
        r.sensitive(true)
        r.run_action(:delete)

        r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_path, 'validation.pem'), run_context)
        r.content(new_resource.validation_key)
        r.sensitive(true)
        r.run_action(:create)
      end

      def remove_cache_path
        cache_path.run_action(:delete)
      end

      def remove_chef_secure_path
        chef_secure_path.run_action(:delete)
      end

      def set_service_mapping(container)
        node.default['docker_deploy']['service_mapping'][new_resource.service_name]['id'] = container.id
        node.default['docker_deploy']['service_mapping'][new_resource.service_name]['name'] = container.name
      end

      def rotate_node_containers(container)
        containers_rotate = {}

        DockerWrapper::Container.all('-a').each do |c|
          
          ## look for matching hostname
          next unless new_resource.service_name == c.hostname
          ## skip self
          next if c == container

          stop_container(c)
          containers_rotate[c.finished_at] = c
        end

        keys = containers_rotate.keys.sort
        while (keys.size >= new_resource.keep_releases)
          remove_container(containers_rotate[keys.shift])
        end
      end
  
      ## actions

      def action_create
        ## create the new container
        container = create_unique_container
        config = container.config
        hostconfig = container.hostconfig

        ## look for similar containers
        DockerWrapper::Container.all('-a').each do |c|
          ## found self
          next if (c == container)

          if (compare_config(c.config, config) and
            compare_config(c.hostconfig, hostconfig))
            ## similar container already exists. remove the new one
            remove_container(container)
            container = c
            break
          end
        end

        rotate_node_containers(container)
        set_service_mapping(container)
        populate_cache_path(container)

        converge_by("Started container #{new_resource.service_name}") do
          start_container(container)
          new_resource.updated_by_last_action(true)
        end unless container.running?
      end

      def action_stop
        converge_by("Stopped container for #{new_resource.service_name}") do
          DockerWrapper::Container.all.each do |c|
            ## look for matching hostname
            next unless new_resource.service_name == c.hostname
            c.stop
            new_resource.updated_by_last_action(true)
          end
        end
      end

      def action_remove
        converge_by("Removed containers for #{new_resource.service_name}") do
          DockerWrapper::Container.all('-a').each do |c|
            ## look for matching hostname
            next unless new_resource.service_name == c.hostname

            remove_container(c)
            new_resource.updated_by_last_action(true)
          end

          remove_cache_path
          remove_chef_secure_path

          @rest.remove_from_chef(new_resource.service_name)
        end
      end

      def action_nothing
      end
    end
  end
end
