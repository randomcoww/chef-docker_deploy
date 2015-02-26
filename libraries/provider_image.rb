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

      include DockerHelper

      def initialize(*args)
        super
        
        @rest = ChefRestHelper.new(new_resource.chef_server_url, new_resource.chef_admin_user, new_resource.chef_admin_key)
        @image_name_full = "#{new_resource.name}:#{new_resource.tag}"
        @build_path = nil
        @build_node_name = nil
        @build_resources = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
        @current_resource.exists = DockerWrapper::Image.exists?(@image_name_full)
        @current_resource
      end

      def build_path
        return @build_resources unless @build_resources.nil?

        @build_path = ::Dir.mktmpdir

        @build_resources = Chef::Resource::Directory.new(@build_path, run_context)
        @build_resources.recursive(true)

        return @build_resources
      end

      def populate_build_path
        build_path.run_action(:create)
        @build_node_name = DockerWrapper::Container.unique_name("buildtmp")

        ## sub direcotries
        r = Chef::Resource::Directory.new(::File.join(@build_path, 'chef', 'secure'), run_context)
        r.recursive(true)
        r.run_action(:create)

        ## client.rb
        r = Chef::Resource::Template.new(::File.join(@build_path, 'chef', 'client.rb'), run_context)
        r.source(new_resource.client_template)
        r.variables({
          :chef_environment => new_resource.chef_environment,
          :validation_client_name => new_resource.validation_client_name,
          :chef_server_url => new_resource.chef_server_url
        })
        r.cookbook(new_resource.client_template_cookbook)
        r.run_action(:create)

        ## first-boot.json
        r = Chef::Resource::File.new(::File.join(@build_path, 'chef', 'first-boot.json'), run_context)
        r.content(::JSON.pretty_generate(new_resource.first_boot))
        r.run_action(:create)

        ## validation.pem
        r = Chef::Resource::File.new(::File.join(@build_path, 'chef', 'secure', 'validation.pem'), run_context)
        r.sensitive(true)
        r.content(new_resource.validation_key)
        r.run_action(:create)

        ## encrypted_data_bag_secret
        r = Chef::Resource::File.new(::File.join(@build_path, 'chef', 'secure', 'encrypted_data_bag_secret'), run_context)
        r.sensitive(true)
        r.content(new_resource.encrypted_data_bag_secret)
        r.run_action(:create)

        ## dockerfile
        r = Chef::Resource::Template.new(::File.join(@build_path, 'Dockerfile'), run_context)
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

      def remove_build_path
        build_path.run_action(:delete)
      end

      def build_image
        populate_build_path
        return DockerWrapper::Image.build("#{new_resource.name}:#{new_resource.tag}", new_resource.build_options.join(' '), @build_path)
      ensure
        remove_build_path
        @rest.remove_from_chef(@build_node_name)
        DockerWrapper::Image.all('-a -f dangling=true').map{ |i|
          begin
            i.rmi
          rescue
            Chef::Log.warn("Not removing image in use #{i.id}")
          end
        }
      end

      def remove_unused_image(image)
        image.rmi
      rescue
        Chef::Log.warn("Not removing image in use #{image.id}")
      end

      ## actions

      def action_pull_if_missing
        converge_by("Pulled new image #{@image_name_full}") do
          DockerWrapper::Image.pull(@image_name_full)
          new_resource.updated_by_last_action(true)
        end unless @current_resource.exists
      end

      def action_pull
        if (@current_resource.exists)
          updated = false
          image = DockerWrapper::Image.get(@image_name_full)

          begin
            new_image = DockerWrapper::Image.pull(@image_name_full)
            updated = (image == new_image)

          rescue => e
            Chef::Log.warn(e.message)
          end

          converge_by("Updated image #{@image_name_full}") do
            new_resource.updated_by_last_action(true)
            remove_unused_image(image)
          end if updated
        else
          action_pull_if_missing
        end
      end

      def action_build
        if (@current_resource.exists)
          image = DockerWrapper::Image.get(@image_name_full)

          converge_by("Built image #{@image_name_full}") do
            build_image
            new_resource.updated_by_last_action(true)
            remove_unused_image(image)
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
          image = DockerWrapper::Image.get(@image_name_full)
          image.push
        end if @current_resource.exists
      end

      def action_remove_if_unused
        converge_by("Removed image #{@image_name_full}") do
          image = DockerWrapper::Image.get(@image_name_full)
          remove_unused_image(image)
        end if @current_resource.exists
      end

      def action_nothing
      end
    end
  end
end
