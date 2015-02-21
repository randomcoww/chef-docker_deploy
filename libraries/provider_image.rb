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
        @image_name_full = "#{new_resource.name}:#{new_resource.tag}"
        @build_resources = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
        @current_resource.exists = get_exists?(@image_name_full)
        @current_resource
      end

      def populate_build_dir(build_dir, node_name)
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
          :build_node_name => node_name,
          :docker_build_commands => new_resource.docker_build_commands,
        })
        r.cookbook(new_resource.dockerfile_template_cookbook)
        r.run_action(:create)
      end

      def build_image
        tmp_build_dir = ::Dir.mktmpdir
        tmp_node_name = generate_unique_container_name("build")

        populate_build_dir(tmp_build_dir, tmp_node_name)
        docker_build("#{new_resource.build_options.join(' ')} -t #{new_resource.name}:#{new_resource.tag}", tmp_build_dir)
      ensure
        @build_resources.run_action(:delete) unless @build_resources.nil?
        @rest.remove_from_chef(tmp_node_name)

        list_dangling_images.map { |i_id|
          docker_rmi(i_id)
        }
      end

      def remove_unused_image(name)
        docker_rmi(name)
      rescue
        Chef::Log.warn("Not removing image in use #{name}")
      end

      ## actions

      def action_pull_if_missing
        converge_by("Pulled new image #{@image_name_full}") do
          docker_pull(@image_name_full)
          new_resource.updated_by_last_action(true)
        end unless @current_resource.exists
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

          converge_by("Updated image #{@image_name_full}") do
            new_resource.updated_by_last_action(true)
            remove_unused_image(image_id)
          end if updated
        else
          action_pull_if_missing
        end
      end

      def action_build
        if (@current_resource.exists)
          image_id = get_id(@image_name_full)

          converge_by("Built image #{@image_name_full}") do
            build_image
            new_resource.updated_by_last_action(true)
            remove_unused_image(image_id)
          end
        else
          action_build_if_missing
        end
      end

      def action_build_if_missing
        converge_by("Built image #{@image_name_full}") do
          build_image
          new_resource.updated_by_last_action(true)
        end unless @current_resource.exists
      end

      def action_push
        converge_by("Pushed image #{@image_name_full}") do
          docker_push(@image_name_full)
        end
      end

      def action_remove_if_unused
        converge_by("Removed image #{@image_name_full}") do
          remove_unused_image(@image_name_full)
        end
      end

      def action_nothing
      end
    end
  end
end
