require 'chef/provider'
require 'chef/provider/directory'
require 'chef/resource/directory'
require 'chef/provider/template'
require 'chef/resource/template'
require 'chef/provider/file'
require 'chef/resource/file'

class Chef
  class Provider
    class DockerDeployImage < Chef::Provider

      include DockerHelpers
      include DockerWrapper

      def initialize(*args)
        super
        
        @rest = ChefRestHelper.new(new_resource.chef_server_url, new_resource.chef_admin_user, new_resource.chef_admin_key)

        @build_node_name = new_resource.build_node_name || generate_unique_container_name('build')
        @image_name_full = "#{new_resource.name}:#{new_resource.tag}"
        @build_resources = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
        @current_resource.exists = get_exists?(@image_name_full)
        @current_resource
      end

      def populate_build_dir(build_dir)
        return unless @build_resources.nil?

        @build_resources = Chef::Resource::Directory.new(::File.join(build_dir), run_context)
        @build_resources.recursive(true)
        @build_resources.run_action(:create)

        ## sub direcotries
        r = Chef::Resource::Directory.new(::File.join(build_dir, 'chef', 'secure'), run_context)
        r.recursive(true)
        r.run_action(:create)

        ## client.rb
        r = Chef::Resource::Template.new(::File.join(build_dir, 'chef', 'client.rb'), run_context)
        r.source(new_resource.client_template)
        r.variables({
          :chef_environment => new_resource.chef_environment,
          :validation_client_name => new_resource.validation_client_name,
          :chef_server_url => new_resource.chef_server_url
        })
        r.cookbook(new_resource.client_template_cookbook)
        r.run_action(:create)

        ## first-boot.json
        r = Chef::Resource::File.new(::File.join(build_dir, 'chef', 'first-boot.json'), run_context)
        r.content(::JSON.pretty_generate(new_resource.first_boot))
        r.run_action(:create)

        ## validation.pem
        r = Chef::Resource::File.new(::File.join(build_dir, 'chef', 'secure', 'validation.pem'), run_context)
        r.sensitive(true)
        r.content(new_resource.validation_key)
        r.run_action(:create)

        ## encrypted_data_bag_secret
        r = Chef::Resource::File.new(::File.join(build_dir, 'chef', 'secure', 'encrypted_data_bag_secret'), run_context)
        r.sensitive(true)
        r.content(new_resource.encrypted_data_bag_secret)
        r.run_action(:create)

        ## dockerfile
        r = Chef::Resource::Template.new(::File.join(build_dir, 'Dockerfile'), run_context)
        r.source(new_resource.dockerfile_template)
        r.variables({
          :base_image_name => new_resource.base_image,
          :base_image_tag => new_resource.base_image_tag,
          :build_node_name => @build_node_name,
          :docker_build_commands => new_resource.docker_build_commands,
        })
        r.cookbook(new_resource.dockerfile_template_cookbook)
        r.run_action(:create)
      end

      def delete_build_dir
        @build_resources.run_action(:delete) unless @build_resources.nil?
      end

      def build_image
        build_dir = new_resource.build_dir || ::Dir.mktmpdir

        populate_build_dir(build_dir)
        docker_build("#{new_resource.build_options.join(' ')} -t #{new_resource.name}:#{new_resource.tag}", build_dir)
      ensure
        delete_build_dir
        @rest.remove_from_chef(@build_node_name)
      end

      ## actions

      def action_pull_if_missing
        unless (@current_resource.exists)
          converge_by("Pulled new image #{@image_name_full}") do
            docker_pull(@image_name_full)
            new_resource.updated_by_last_action(true)
          end
        end
      end

      def action_pull
        if (@current_resource.exists)
          updated = false
          image_id = get_id(@image_name_full)

          begin
            new_image_id = docker_pull(@image_name_full)
            updated = (image_id == new_image_id)

          rescue => e
            Chef::Log.warn(e.message)
          end

          if (updated)
            converge_by("Updated image #{@image_name_full}") do
              docker_rm(image_id)
              new_resource.updated_by_last_action(true)
            end
          end
        else
          action_pull_if_missing
        end
      end

      def action_build
        converge_by("Built image #{@image_name_full}") do
          build_image
          new_resource.updated_by_last_action(true)
        end
      end

      def action_build_if_missing
        action_build unless (@current_resource.exists)
      end

      def action_push
        converge_by("Pushed image #{@image_name_full}") do
          docker_push(@image_name_full)
        end
      end

      def action_try_pull_if_missing
        action_pull_if_missing
      rescue DockerPull => e
        Chef::Log.warn(e.message)
      end

      def action_try_pull
        action_pull
      rescue DockerPull => e
        Chef::Log.warn(e.message)
      end

      def action_remove
        if (@current_resource.exists)
          converge_by("Removed image #{@image_name_full}") do
            docker_rmi(@image_name_full)
            new_resource.updated_by_last_action(true)
          end
        end
      end
    end
  end
end
