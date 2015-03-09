require 'chef/provider'
require 'chef/provider/directory'
require 'chef/resource/directory'
require 'chef/provider/template'
require 'chef/resource/template'
require 'chef/provider/file'
require 'chef/resource/file'
require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

class Chef
  class Provider
    class DockerDeployImage < Chef::Provider

      include DockerHelper

      def initialize(*args)
        super
        
        @image_name_full = "#{new_resource.name}:#{new_resource.tag}"
      end

      def load_current_resource
        @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
        @current_resource.exists = DockerWrapper::Image.exists?(@image_name_full)
        @current_resource
      end

     


      ##
      ## build the image
      ##

      def build_image
        image = docker_build_in_path do |build_path|

          chef_path = ::File.join(build_path, 'chef')

          r = Chef::Resource::Directory.new(chef_path, run_context)
          r.recursive(true)
          r.run_action(:create)

          secure_path = ::File.join(chef_path, 'secure')

          r = Chef::Resource::Directory.new(secure_path, run_context)
          r.recursive(true)
          r.run_action(:create)

          write_first_boot(chef_path)
          write_encrypted_data_bag_secret(secure_path)
          write_server_conf(chef_path) unless new_resource.enable_local_mode

          create_zero_build_resources(chef_path)
        end
      end

      ##
      ## create and clean up build path for docker build
      ##

      def docker_build_in_path
        build_path = ::Dir.mktmpdir
        write_dockerfile(build_path)

        yield build_path

        begin
          image = DockerWrapper::Image.build("#{new_resource.name}:#{new_resource.tag}", new_resource.dockerbuild_options.join(' '), build_path)
        ensure
          cleanup_dangling_images
        end

        return image

      ensure
        r = Chef::Resource::Directory.new(build_path, run_context)
        r.recursive(true)
        r.run_action(:delete)
      end

      ##
      ## try to remove image and warn if in use
      ##

      def remove_unused_image(image)
        image.rmi
      rescue
        Chef::Log.warn("Not removing image in use #{image.id}")
      end

      ##
      ## create chef zero build resources
      ##

      def create_zero_build_resources(build_path)
        write_zero_conf(build_path)

        ['environments', 'data_bags', 'cookbooks', 'roles'].each do |p|
          r = Chef::Resource::Directory.new(::File.join(build_path, p), run_context)
          r.recursive(true)
          r.run_action(:create)
        end

        write_build_data_bags(::File.join(build_path, 'data_bags'))
        write_build_environments(::File.join(build_path, 'environments'))
        write_build_cookbooks(::File.join(build_path, 'cookbooks'))
        write_build_roles(::File.join(build_path, 'roles'))
      end

      ##
      ## encrypted_data_bag_secret
      ##

      def write_encrypted_data_bag_secret(path)
        r = Chef::Resource::File.new(::File.join(path, 'encrypted_data_bag_secret'), run_context)
        r.sensitive(true)
        r.content(new_resource.encrypted_data_bag_secret)
        r.run_action(:create)
      end

      ##
      ## first-boot.json
      ##

      def write_first_boot(path)
        r = Chef::Resource::File.new(::File.join(path, 'first-boot.json'), run_context)
        r.content(::JSON.pretty_generate(new_resource.first_boot))
        r.run_action(:create)
      end

      ##
      ## dockerfile
      ##

      def write_dockerfile(path)
        r = Chef::Resource::Template.new(::File.join(path, 'Dockerfile'), run_context)
        r.source(new_resource.dockerfile_template)
        r.variables({
          :base_image_name => new_resource.base_image,
          :base_image_tag => new_resource.base_image_tag,
          :dockerfile_commands => new_resource.dockerfile_commands,
        })
        r.cookbook(new_resource.dockerfile_template_cookbook)
        r.run_action(:create)
      end

      ##
      ## write chef config.rb
      ##

      def write_server_conf(path)
        r = Chef::Resource::Template.new(::File.join(path, 'client.rb'), run_context)
        r.source(new_resource.config_template)
        r.variables(new_resource.config_template_variables) 
        r.cookbook(new_resource.config_template_cookbook)
        r.run_action(:create)
      end

      ##
      ## write chef solo config
      ##

      def write_zero_conf(path)
        r = Chef::Resource::Template.new(::File.join(path, 'zero.rb'), run_context)
        r.source(new_resource.local_template)
        r.variables(new_resource.local_template_variables)
        r.cookbook(new_resource.local_template_cookbook)
        r.run_action(:create)
      end

      ##
      ## write data bag json to path (does not unencrypt)
      ##

      def write_build_data_bags(path)
        ## write data bags to build (must be fed as arg)
        new_resource.data_bags.each_pair do |bag, items|
          r = Chef::Resource::Directory.new(::File.join(path, bag), run_context)
          r.recursive(true)
          r.run_action(:create)

          items.each do |item|
            r = Chef::Resource::File.new(::File.join(path, bag, "#{item}.json"), run_context)
            r.sensitive(true)
            r.content(Chef::DataBagItem.load(bag, item).to_json)
            r.run_action(:create)
          end
        end
      end

      ## 
      ## write environment json to path
      ##

      def write_build_environments(path)
        r = Chef::Resource::File.new(::File.join(path, "#{new_resource.chef_environment}.json"), run_context)
        r.content(Chef::Environment.load(new_resource.chef_environment).to_json)
        r.run_action(:create)
      end

      ##
      ## download cookbooks and dependencies to path
      ##

      def write_build_cookbooks(path)
        download_cookbooks(cookbook_hash, path)
      end

      ##
      ## write role json to build path
      ##

      def write_build_roles(path)
         expanded_run_list_roles.each do |role|
          r = Chef::Resource::File.new(::File.join(path, "#{role}.json"), run_context)
          r.content(Chef::Role.load(role).to_json)
          r.run_action(:create)
        end
      end

      ##
      ## get base run_list fed in as argument
      ##

      def container_run_list
        return @container_run_list unless @container_run_list.nil?
        @container_run_list = new_resource.first_boot['run_list'] || []
        return @container_run_list
      end

      ##
      ## get expanded run_list
      ##

      def expanded_run_list
        return @expanded_run_list unless @expanded_run_list.nil?

        r = Chef::RunList.new()
        container_run_list.each do |i|
          r << i
        end
        re = r.expand(new_resource.chef_environment)
        re.expand
        @expanded_run_list = re

        return @expanded_run_list
      end

      ##
      ## get expanded list of roles
      ##

     def expanded_run_list_roles
        return @expanded_run_list_roles unless @expanded_run_list_roles.nil?
        @expanded_run_list_roles = expanded_run_list.roles
        return @expanded_run_list_roles
      end

      ##
      ## get expanded list of recipes
      ##

      def expanded_run_list_recipes
        return @expanded_run_list_recipes unless @expanded_run_list_recipes.nil?
        @expanded_run_list_recipes = expanded_run_list.recipes.with_version_constraints_strings
        return @expanded_run_list_recipes
      end

      ##
      ## create simple {cookbook => version} hash of cookbooks needed by run_list
      ##

      def cookbook_hash
        return @cookbook_hash unless @cookbook_hash.nil?

        @cookbook_hash = {}
        rest = Chef::REST.new(chef_server_url, node.name, ::Chef::Config[:client_key])
        cookbook_hash = rest.post("environments/#{new_resource.chef_environment}/cookbook_versions", {:run_list => expanded_run_list_recipes})
        @cookbook_hash = Chef::CookbookCollection.new(cookbook_hash)

        return @cookbook_hash
      end

      ##
      ## download cookbooks using knife
      ##

      def download_cookbooks(cookbook_hash, path)
        synchronizer = Chef::CookbookSynchronizer.new(cookbook_hash, nil)
        synchronizer.download_container_cookbooks(path)

#        Chef::Log.info("Downloading cookbook #{cookbook} #{version}")
#        shell_out!("knife cookbook download #{cookbook} #{version} -s #{new_resource.chef_server_url} -u #{node.name} -k #{::Chef::Config[:client_key]} -f -d #{path}")
#
#        ## knife generates directories <cookbook>-<version>. rename these to <cookbook>
#        ::File.rename(::File.join(path, "#{cookbook}-#{version}"), ::File.join(path, cookbook))

      end

      ##
      ## clean up dangling images
      ##

      def cleanup_dangling_images
        DockerWrapper::Image.all('-a -f dangling=true').map{ |i|
          begin
            i.rmi
          rescue
            Chef::Log.warn("Not removing image in use #{i.id}")
          end
        }
      end





      ##
      ## actions
      ##

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
