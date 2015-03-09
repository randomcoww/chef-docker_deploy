module DockerHelper
  class DockerRunList

    def initialize(run_list, chef_environment)
      @run_list = run_list
      @chef_environment = chef_environment

      @chef_server_url = Chef::Config[:chef_server_url]
      @client_key = Chef::Config[:client_key]
      @node_name = node.name
    end

    ##
    ## get expanded run_list
    ##

    def expanded_run_list
      return @expanded_run_list unless @expanded_run_list.nil?

      r = Chef::RunList.new()
      @run_list.each do |i|
        r << i
      end
      re = r.expand(chef_environment)
      re.expand

      re = @expanded_run_list

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

      cookbook_hash = {}
      rest = Chef::REST.new(@chef_server_url, @node_name, @client_key)
      cookbook_hash = rest.post("environments/#{@chef_environment}/cookbook_versions", {:run_list => expanded_run_list_recipes})
      @cookbook_hash = Chef::CookbookCollection.new(cookbook_hash)

      return @cookbook_hash

    rescue => e
      Chef::Log.error("Failed to get cookbook revisions with #{e.message}")
    end

    ##
    ## download cookbooks using hacked syncronizer: path/<cookbook_name>/<recipe, etc>
    ##

    def download_dependency_cookbooks(path)
      synchronizer = Chef::CookbookSynchronizer.new(cookbook_hash, nil)
      synchronizer.download_container_cookbooks(path)

    rescue => e
      Chef::Log.error("Failed to sync cookbooks with #{e.message}")
    end
  end
end
