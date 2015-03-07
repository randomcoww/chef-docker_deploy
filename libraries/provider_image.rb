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
        
        @image_name_full = "#{new_resource.name}:#{new_resource.tag}"
        @build_path = nil
        @build_node_name = nil
        @build_resources = nil
        @chef_secure_path = '/etc/chef/secure'
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
        @current_resource.exists = DockerWrapper::Image.exists?(@image_name_full)
        @current_resource
      end

      ## create temp dir for docker build ##
      
      def build_path
        return @build_resources unless @build_resources.nil?

        @build_path = ::Dir.mktmpdir

        @build_resources = Chef::Resource::Directory.new(@build_path, run_context)
        @build_resources.recursive(true)

        return @build_resources
      end

      ## create docker build tmp path ##
      
      def populate_build_path
        build_path.run_action(:create)
        chef_path = ::File.join(@build_path, 'chef')
        @build_node_name = DockerWrapper::Container.unique_name('buildtmp')
        #@build_node_name = new_resource.build_node_name

        ## sub direcotries
        r = Chef::Resource::Directory.new(::File.join(chef_path, 'secure'), run_context)
        r.recursive(true)
        r.run_action(:create)

        ## encrypted_data_bag_secret
        r = Chef::Resource::File.new(::File.join(chef_path, 'secure', 'encrypted_data_bag_secret'), run_context)
        r.sensitive(true)
        r.content(new_resource.encrypted_data_bag_secret)
        r.run_action(:create)

        ## first-boot.json
        r = Chef::Resource::File.new(::File.join(chef_path, 'first-boot.json'), run_context)
        r.content(::JSON.pretty_generate(new_resource.first_boot))
        r.run_action(:create)

        ## dockerfile
        r = Chef::Resource::Template.new(::File.join(@build_path, 'Dockerfile'), run_context)
        r.source(new_resource.dockerfile_template)
        r.variables({
          :base_image_name => new_resource.base_image,
          :base_image_tag => new_resource.base_image_tag,
          :build_node_name => @build_node_name,
          :dockerfile_commands => new_resource.dockerfile_commands,
        })
        r.cookbook(new_resource.dockerfile_template_cookbook)
        r.run_action(:create)

        if (new_resource.enable_local_mode)
          ## zero.rb
          r = Chef::Resource::Template.new(::File.join(chef_path, 'zero.rb'), run_context)
          r.source(new_resource.config_template)
          r.variables({
            :chef_environment => new_resource.chef_environment,
          })
          r.cookbook(new_resource.config_template_cookbook)
          r.run_action(:create)

          ['environments', 'data_bags', 'cookbooks', 'roles'].each do |p|
            r = Chef::Resource::Directory.new(::File.join(chef_path, p), run_context)
            r.recursive(true)
            r.run_action(:create)
          end

          ## packaged cookbooks (berks package)
          new_resource.berks_package_files.each do |src_cookbook, pkgs|
            ## copy to build dir
            pkgs.each do |pkg|
              r = Chef::Resource::CookbookFile.new(::File.join(chef_path, pkg), run_context)
              r.source(pkg)
              r.cookbook(src_ookbook)
              r.run_action(:create)

              ## untar
              unpack_cookbook(::File.join(chef_path, pkg), chef_path)
            end
          end

          ## write data bags to build
          new_resource.local_data_bags.each_pair do |bag, items|
            r = Chef::Resource::Directory.new(::File.join(chef_path, 'data_bags', bag), run_context)
            r.recursive(true)
            r.run_action(:create)

            items.each do |item|
              r = Chef::Resource::File.new(::File.join(chef_path, 'data_bags', bag, "#{item}.json"), run_context)
              r.content(Chef::DataBagItem.load(bag, item).to_json)
              r.run_action(:create)
            end
          end

          ## write environments to build
          new_resource.local_environments.each do |env|
            r = Chef::Resource::File.new(::File.join(chef_path, 'environments', "#{env}.json"), run_context)
            r.content(Chef::Environment.load(env).to_json)
            r.run_action(:create)
          end

          ## write roles to build
          new_resource.local_roles.each do |role|
            r = Chef::Resource::File.new(::File.join(chef_path, 'roles', "#{role}.json"), run_context)
            r.content(Chef::Environment.load(role).to_json)
            r.run_action(:create)
          end

        else
          ## client.rb
          r = Chef::Resource::Template.new(::File.join(chef_path, 'client.rb'), run_context)
          r.source(new_resource.config_template)
          r.variables({
            :chef_environment => new_resource.chef_environment,
            :validation_client_name => new_resource.validation_client_name,
            :chef_server_url => new_resource.chef_server_url,
            :chef_secure_path => @chef_secure_path,
          })
          r.cookbook(new_resource.config_template_cookbook)
          r.run_action(:create)

          ## validation.pem
          r = Chef::Resource::File.new(::File.join(chef_path, 'secure', 'validation.pem'), run_context)
          r.sensitive(true)
          r.content(new_resource.validation_key)
          r.run_action(:create)
        end
      end
      
      ## remove docker build tmp path ##
      def remove_build_path
        build_path.run_action(:delete)
      end

      ## try to read keyfile from image and remove associated chef node ##
      
      def remove_build_node(image)
        begin
          key = image.read_file(::File.join(@chef_secure_path, 'client_key.pem'))
          write_tmp_key(key) do |keyfile|
            remove_from_chef(new_resource.chef_server_url, @build_node_name, keyfile)
          end if key
        rescue
          Chef::Log.warn("Could not remove Chef build node #{@build_node_name}")
        end unless new_resource.enable_local_mode
      end

      ## generate docker build environment and build image ##

      def build_image
        populate_build_path
        image = DockerWrapper::Image.build("#{new_resource.name}:#{new_resource.tag}", new_resource.dockerbuild_options.join(' '), @build_path)
        return image

      ensure
        remove_build_path
        remove_build_node(image)

        DockerWrapper::Image.all('-a -f dangling=true').map{ |i|
          begin
            i.rmi
          rescue
            Chef::Log.warn("Not removing image in use #{i.id}")
          end
        }
      end

      ## remove image and warn if in use ##

      def remove_unused_image(image)
        image.rmi
      rescue
        Chef::Log.warn("Not removing image in use #{image.id}")
      end

      ## actions ##

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
