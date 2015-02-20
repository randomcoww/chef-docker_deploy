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

      include DockerHelpers
      include DockerWrapper

      def initialize(*args)
        super
        
        @rest = ChefRestHelper.new(new_resource.chef_server_url, new_resource.chef_admin_user, new_resource.chef_admin_key)
        @secure_resources = nil
        @wrapper_script = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployContainer.new(new_resource.name)
        @current_resource
      end

      def create_unique_container
        container_name = generate_unique_container_name(new_resource.name)
        container_create_options = %W{--volume="#{new_resource.chef_secure_dir}:/etc/chef/secure" --hostname="#{new_resource.node_name}" --env="CHEF_NODE_NAME=#{new_resource.node_name}" --name="#{container_name}"} + new_resource.container_create_options

        return docker_create(container_create_options.join(' '), get_id("#{new_resource.base_image}:#{new_resource.base_image_tag}"))
      end

      def start_container(name)
        populate_secure_dir unless @rest.exists?(new_resource.node_name)
        docker_start(name)
      end

      def stop_container(name)
        docker_stop(name)
        docker_kill(name) if get_container_running?(name)
        raise StopContainer, "Unable to stop container #{name}" if get_container_running?(name)
      end

      def remove_container(name)
        stop_container(name)
        docker_rm(name)
      end

      def populate_secure_dir
        return unless @secure_resources.nil?

        @secure_resources = Chef::Resource::Directory.new(::File.join(new_resource.chef_secure_dir), run_context)
        @secure_resources.recursive(true)
        @secure_resources.run_action(:create)

        unless new_resource.encrypted_data_bag_secret.nil?
          r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_dir, 'encrypted_data_bag_secret'), run_context)
          r.content(new_resource.encrypted_data_bag_secret)
          r.sensitive(true)
          r.run_action(:create)
        end

        r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_dir, 'client.pem'), run_context)
        r.sensitive(true)
        r.run_action(:delete)

        r = Chef::Resource::File.new(::File.join(new_resource.chef_secure_dir, 'validation.pem'), run_context)
        r.content(new_resource.validation_key)
        r.sensitive(true)
        r.run_action(:create)
      end

      def remove_secure_dir
        return unless @secure_resources.nil?

        @secure_resources = Chef::Resource::Directory.new(::File.join(new_resource.chef_secure_dir), run_context)
        @secure_resources.recursive(true)
        @secure_resources.run_action(:delete)
      end

      def create_wrapper_scripts(name)
        return unless @wrapper_script.nil?

        container_id = get_id(name)

        @wrapper_script = Chef::Resource::Template.new(::File.join(new_resource.script_path, new_resource.name), run_context)
        @wrapper_script.source(new_resource.script_template)
        @wrapper_script.variables({
          :actions => {
            'start' => "docker start #{container_id}",
            'stop' => "docker stop #{container_id}",
            'attach' => "docker exec -it #{container_id} /bin/bash",
          }
        })
        @wrapper_script.cookbook(new_resource.script_cookbook)
        @wrapper_script.mode('0755')
        @wrapper_script.run_action(:create)
      end

      def remove_wrapper_scripts
        return unless @wrapper_script.nil?

        @wrapper_script = Chef::Resource::File.new(::File.join(new_resource.script_path, new_resource.name), run_context)
        @wrapper_script.run_action(:delete)
      end

      def rotate_node_containers(container_id)
        #container_id = get_id(name)
        containers_rotate = {}

        list_all_containers.each do |c_id|
          
          ## look for matching hostname
          next unless new_resource.node_name == get_container_hostname(c_id)
          ## skip self
          next if container_id == c_id

          stop_container(c_id)
          containers_rotate[get_container_finished_at(c_id)] = c_id
        end

        keys = containers_rotate.keys.sort
        while (keys.size >= new_resource.keep_releases)
          c_id = containers_rotate[keys.shift]
          image_id = get_container_image_id(c_id)

          remove_container(c_id)
          begin
            docker_rmi(image_id)
          rescue
            Chef::Log.info("Not removing image in use #{image_id}")
          end
        end
      end
  
      ## actions

      def action_create
        ## create the new container
        container_id = create_unique_container
        config = get_container_config(container_id)
        hostconfig = get_container_hostconfig(container_id)

        ## look for similar containers
        list_all_containers.each do |c_id|
          ## found self
          next if (c_id == container_id)

          if (compare_config(get_container_config(c_id), config) and
            compare_config(get_container_hostconfig(c_id), hostconfig))
            ## similar container already exists. remove the new one
            remove_container(container_id)
            container_id = c_id
            break
          end
        end

        rotate_node_containers(container_id)
        create_wrapper_scripts(container_id)

        converge_by("Started container #{new_resource.name}") do
          start_container(container_id)
          new_resource.updated_by_last_action(true)
        end unless get_container_running?(container_id)
      end

      def action_stop
        converge_by("Stopped container for #{new_resource.name}") do
          list_running_containers.each do |c_id|
            ## look for matching hostname
            next unless new_resource.node_name == get_container_hostname(c_id)
            stop_container(c_id)
            new_resource.updated_by_last_action(true)
          end
        end
      end

      def action_remove
        converge_by("Removed containers for #{new_resource.name}") do
          list_all_containers.each do |c_id|
            ## look for matching hostname
            next unless new_resource.node_name == get_container_hostname(c_id)

            stop_container(c_id) if get_container_running?(c_id)
            remove_container(c_id)
            new_resource.updated_by_last_action(true)
          end

          remove_wrapper_scripts
          remove_secure_dir

          @rest.remove_from_chef(new_resource.node_name)
        end
      end
    end
  end
end
