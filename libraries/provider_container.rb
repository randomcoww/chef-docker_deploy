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
        
        @base_image_name_full = "#{new_resource.base_image}:#{new_resource.base_image_tag}"
        @container_create_options = %Q{#{new_resource.container_create_options.join(' ')} --hostname="#{new_resource.node_name}" --env="CHEF_NODE_NAME=#{new_resource.node_name}" --volume="#{new_resource.chef_secure_dir}:/etc/chef/secure"}
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployContainer.new(new_resource.name)
        @current_resource.exists = get_exists?(new_resource.name)
        @current_resource
      end

      def create_container
        container_name = new_resource.name

        docker_create(%Q{#{@container_create_options} --name="#{container_name}"}, @base_image_name_full)
        return get_id(container_name)
      end

      def create_unique_container
        container_name = generate_unique_container_name(new_resource.name)

        docker_create(%Q{#{@container_create_options} --name="#{container_name}"}, @base_image_name_full)
        return get_id(container_name)
      end

      def start_container(name)
        stop_conflicting_containers(name) if new_resource.stop_conflicting
        populate_secure_dir unless @rest.exists?(new_resource.node_name)

        docker_start(name)
      end

      def stop_container(name)
        docker_stop(name) if get_container_running?(name)
        docker_kill(name) if get_container_running?(name)
        raise DockerWrapper::StopError, "Unable to stop container #{name}" if get_container_running?(name)
      end

      def remove_container(name)
        stop_container(name)
        docker_rm(name)
      end

      def compare_container_config(a, b)
        #puts JSON.pretty_generate(a)
        #puts JSON.pretty_generate(b)
        return a == b
      end

      def stop_conflicting_containers(name)
        container_id = get_id(name)
        host_port_bindings = parse_host_ports(get_container_port_bindings(container_id))

        list_running_containers.each do |c_id|
          # skip self
          next if container_id == c_id

          parse_host_ports(get_container_port_bindings(c_id)).each_key do |p|
            if (host_port_bindings.has_key?(p))
              stop_container(c_id)
            end
          end
        end
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

      def create_wrapper_scripts(name)
        container_id = get_id(name)

        r = Chef::Resource::Template.new(::File.join(new_resource.script_path, new_resource.name), run_context)
        r.source(new_resource.script_template)
        r.variables({
          :actions => {
            'start' => "docker start #{container_id}",
            'stop' => "docker stop #{container_id}",
            'attach' => "docker exec -it #{container_id} /bin/bash",
          }
        })
        r.cookbook(new_resource.script_cookbook)
        r.mode('0755')
        r.run_action(:create)
      end
      
      def rotate_node_containers(name)
        container_id = get_id(name)
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
          remove_image(image_id)
        end
      end
  
      ## actions

      def action_create_if_missing
        if (@current_resource.exists)
          container_id = get_id(new_resource.name)

          unless get_container_running?(container_id)
            converge_by("Starting container #{new_resource.name}") do
              start_container(container_id)
              new_resource.updated_by_last_action(true)
            end
          end
        else
          converge_by("Creating container #{new_resource.name}") do
            container_id = create_container
            start_container(container_id) unless get_container_running?(container_id)
            new_resource.updated_by_last_action(true)
          end
        end

        create_wrapper_scripts(new_resource.name)
      end

      def action_create
        if (@current_resource.exists)

          container_id = get_id(new_resource.name)
          config = get_container_config(container_id)

          dummy_container = create_unique_container
          dummy_config = get_container_config(dummy_container)

          if (compare_container_config(dummy_config, config))

            unless (container.running?)
              converge_by("Starting container #{new_resource.name}") do
                start_container(container)
                new_resource.updated_by_last_action(true)
              end
            end
          else

            stop_container(container_id)
            remove_container(container_id)
          end
        else

          converge_by("Creating container #{new_resource.name}") do 
            container_id = create_container
            start_container(container_id) unless get_container_running?(container_id)
            new_resource.updated_by_last_action(true)
          end
        end
        
        create_wrapper_scripts(container_id)
      end 

      def action_create_and_rotate
        ## create the new container
        container_id = create_unique_container
        config = get_container_config(container_id)

        ## look for similar containers
        list_all_containers.each do |c_id|
          ## found self
          next if (c_id == container_id)

          if (compare_container_config(get_container_config(c_id), config))
            ## similar container already exists. remove the new one
            remove_container(container_id)
            container_id = c_id
            break
          end
        end

        rotate_node_containers(container_id)
        create_wrapper_scripts(container_id)

        unless get_container_running?(container_id)
          converge_by("Starting container #{new_resource.name}") do
            start_container(container_id)
            new_resource.updated_by_last_action(true)
          end
        end
      end
    end
  end
end
