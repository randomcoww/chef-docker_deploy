require 'chef/provider'
require 'chef/provider/directory'
require 'chef/resource/directory'
require 'chef/provider/template'
require 'chef/resource/template'
require 'chef/provider/file'
require 'chef/resource/file'
#require 'chef/resource/gemfile'
#require 'chef/provider/gemfile'

class Chef
  class Provider
    class DockerDeploy < Chef::Provider

      include DockerHelpers
      include DockerFunctions

      def initialize(*args)
        super
        
        #set_docker_api_timeout(new_resource.docker_timeout)
        #require_gem("docker", new_resource.docker_api_version, "docker-api")

        #r = Chef::Resource::ChefGem.new('docker-api')
        #r.version(new_resource.docker_api_version)
        #r.run_action(:install)

        extend DockerApiExtras

        @rest = ChefRestHelper.new(new_resource.chef_server_url, new_resource.chef_admin_user, new_resource.chef_admin_key)

        @build_dir = new_resource.build_dir || ::Dir.mktmpdir
        @build_node_name = new_resource.build_node_name || generate_unique_container_name('build')
        @image_name_full = "#{new_resource.name}:#{new_resource.tag}"
        @build_resources = nil
      end

      def load_current_resources
        @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
        #@current_resource.exists = Docker::Image.exist?(@image_name_full)
        @current_resource.exists = get_image_exists(@image_name_full)
        @current_resource
      end

      def populate_build_dir
        return unless @build_resources.nil?

        @build_resources = Chef::Resource::Directory.new(::File.join(@build_dir), run_context)
        @build_resources.recursive(true)
        @build_resources.run_action(:create)

        ## sub direcotries
        r = Chef::Resource::Directory.new(::File.join(@build_dir, 'chef', 'secure'), run_context)
        r.recursive(true)
        r.run_action(:create)

        ## client.rb
        r = Chef::Resource::Template.new(::File.join(@build_dir, 'chef', 'client.rb'), run_context)
        r.source(new_resource.client_template)
        r.variables({
          :chef_environment => new_resource.chef_environment,
          :validation_client_name => new_resource.validation_client_name,
          :chef_server_url => new_resource.chef_server_url
        })
        r.cookbook(new_resource.client_template_cookbook)
        r.run_action(:create)

        ## first-boot.json
        r = Chef::Resource::File.new(::File.join(@build_dir, 'chef', 'first-boot.json'), run_context)
        r.content(::JSON.pretty_generate(new_resource.first_boot))
        r.run_action:create)

        ## validation.pem
        r = Chef::Resource::File.new(::File.join(@build_dir, 'chef', 'secure', 'validation.pem'), run_context)
        r.sensitive(true)
        r.content(new_resource.validation_key)
        r.run_action(:create)

        ## encrypted_data_bag_secret
        r = Chef::Resource::File.new(::File.join(@build_dir, 'chef', 'secure', 'encrypted_data_bag_secret'), run_context)
        r.sensitive(true)
        r.content(new_resource.encrypted_data_bag_secret)
        r.run_action(:create)

        ## dockerfile
        r = Chef::Resource::Template.new(::File.join(@build_dir, 'Dockerfile'), run_context)
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
        set_build_resources
        populate_build_dir

        #return Docker::Image.build_and_tag(new_resource.name, new_resource.tag, @build_dir, new_resource.build_options)
        system(%Q{docker build #{new_resource.build_options.join(' ')} -t #{new_resource.name}:#{new_resource.tag}})
      ensure
        delete_build_dir
        @rest.remove_from_chef(@build_node_name)
      end

      ## actions

      def action_pull_if_missing
        unless (@current_resource.exists)
          converge_by("Pulled new image #{@image_name_full}") do
            #Docker::Image.pull('fromImage' => new_resource.name, 'tag' => new_resource.tag)
            docker_pull(@image_name_full)
            new_resource.updated_by_last_action(true)
          end
        end
      end

      def action_pull
        if (@current_resource.exists)
          updated = false
          #image = Docker::Image.get_local(@image_name_full)
          image_id = get_image_id(@image_name_full)

          begin
            #new_image = Docker::Image.pull('fromImage' => new_resource.name, 'tag' => new_resource.tag)
            docker_pull(@image_name_full)
            new_image_id = get_image_id(@image_name_full)

            updated = (image_id == new_image_id)

          rescue => e
            Chef::Log.warn(e.message)
          end

          if (updated)
            converge_by("Updated image #{@image_name_full}") do
              #image.remove_non_active
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
        #image = Docker::Image.get_local(@image_name_full)
        #image.tag('repo' => new_resource.name, 'tag' => new_resource.tag, 'force' => 1)

        converge_by("Pushed image #{@image_name_full}") do
          #image.push
          docker_push(@image_name_full)
        end
      end

      def action_try_pull_if_missing
        action_pull_if_missing
      rescue DockerDeploy::Errors::PullFail => e
        Chef::Log.warn(e.message)
      end

      def action_try_pull
        action_pull
      rescue DockerDeploy::Errors::PullFail => e
        Chef::Log.warn(e.message)
      end
    end
  end
end
