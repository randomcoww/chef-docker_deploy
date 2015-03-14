# docker_deploy-cookbook

This recipe provides some build and versioning automation for services deployed as Docker containers.

* Build container contents with Chef (based on methods used by knife-container).

* Handle revision deployment.
 * Automatically stop and replace older revision containers of common service name with new. Keep old containers available in stopped state for rollback.
 * Detect changes in container configuration and replace as needed. Rollback to older container by reverting configs to macth its settings.
 * Rotate out and remove old containers after N releases. Rotation priority is by earliest "FinishedAt" time which is recorded when a running container is stopped.
 * If running chef in containers, a node is shared by all containers of a service (of which one can be running at a time).

* Reduce clutter on the Docker host.
 * Service cleanup for containers, images, Chef nodes and cache paths by passing in the the :remove action.
 * Parent images are removed as containers are rotated out, if not used by any other.
 * Some cleanup of failed builds. Does not work so well if the chef run is killed during a build.

## Requirements

* Docker (tested on 1.3.3 and 1.4.1)
* Docker base image with chef-container for build. Chef provides various Docker images with chef-container including:
 * chef/ubuntu-12.04
 * chef/ubuntu-14.04
* Recipe can also be used to just run prebuilt images as containers.

## Build image example

Image build runs in Chef local mode (zero/solo) so no temporary clients or nodes are generated. Required Chef environment, cookbooks and roles are parsed from input and automatically downloaded to the build directory so no packaging or other preparation is needed. Any data bags required for build must be listed under data_bags (see example below for format) so that they can also be loaded to the build directory. Encrypted data bags should be listed as normal and will simply be copied as encrypted strings.


```ruby
docker_deploy_image "image_name" do
  
  tag "tag"

  base_image "chef/ubuntu-14.04"
  base_image_tag "latest"

  chef_environment "_default"

  ## Commands to pass into Dockerfile
  dockerfile_commands ([
    'RUN apt-get update && apt-get -y upgrade'
  ])

  ## Properties to for Chef run in the container
  first_boot ({

    ## attributs to add
    "runit" => {
      'sv_bin' => '/opt/chef/embedded/bin/sv',
      'chpst_bin' => '/opt/chef/embedded/bin/chpst',
      'service_dir' => '/opt/chef/service',
      'sv_dir' => '/opt/chef/sv'
    },
    'chef_client' => {
      'init_style' => 'runit'
    },
    "tags" => [
      "docker",
      "container"
    ],

    ## run list for container node
    "run_list" => [
      'recipe[item1]',
      'role[item2]'
    ]
  })

  enable_local_mode false
  validation_client_name 'chef-validatior'

  encrypted_data_bag_secret data_bag['encrypted_data_bag_secret']
  data_bags ({
    'bag_name1' => [
      'id1',
      'id2'
    ],
    'bag_name2' => [
      'id1'
    ]
  })

  action :build_if_missing
end
```

#### Options

<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Actions</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>name</tt></td>
    <td>String</td>
    <td>Image name</td>
    <td>all</td>
  </tr>
  <tr>
    <td><tt>tag</tt></td>
    <td>String</td>
    <td>Image tag</td>
    <td>all</td>
  </tr>
  <tr>
    <td><tt>base_image</tt></td>
    <td>String</td>
    <td>Base image for docker build.</td>
    <td>build, build_if_missing</td>
  </tr>
  <tr>
    <td><tt>base_image_tag</tt></td>
    <td>String</td>
    <td>Base image tag for docker build.</td>
    <td>build, build_if_missing</td>
  </tr>
  <tr>
    <td><tt>dockerbuild_options</tt></td>
    <td>Array</td>
    <td>Options to pass into docker build command. Cleanup of build containers enabled by default.</td>
    <td>build, build_if_missing</td>
    <td><tt>['--force-rm=true']</tt></td>
  </tr>
  <tr>
    <td><tt>enable_local_mode</tt></td>
    <td>Boolean</td>
    <td>Docker build runs in local mode, but the resulting image will, by default, be configured to run off of a Chef server when launched as a container. Enable to keep the image configured to run in local mode.</td>
    <td>build, build_if_missing</td>
    <td><tt>false</tt></td>
  </tr>

  <tr>
    <td><tt>chef_environment</tt></td>
    <td>String</td>
    <td>The Chef environment ro run the build as. This determines cookbooks and version copied to the build directory for local build execution. The environment cannot be changed after build if local mode is enabled. Environmetal variable CHEF_ENVIRONMENT can be set to control the environment of the container after build if local mode is disabled. Defaults to environment of Docker server. See container example below for passing in this variable.</td>
    <td>build, build_if_missing</td>
    <td><tt>node.chef_environment</tt></td>
  </tr>

  <tr>
    <td><tt>validation_client_name</tt></td>
    <td>String</td>
    <td>Validation client to use for registering container node. Written to node client.rb if local mode is disabled. Not used if local mode is enabled. This is the name of the client and not the key.</td>
    <td>build, build_if_missing</td>
    <td><tt>Chef::Config[:validation_client_name]</tt></td>
  </tr>
  <tr>
    <td><tt>encrypted_data_bag_secret</tt></td>
    <td>String</td>
    <td>Optional encrypted_data_bag_secret for use by container node during build. Removed after build.</td>
    <td>build, build_if_missing</td>
  </tr>

  <tr>
    <td><tt>dockerfile_template</tt></td>
    <td>String</td>
    <td>Template for Dockerfile for container node.</td>
    <td>build, build_if_missing</td>
    <td><tt>'local/Dockerfile.erb' if local mode. 'Dockerfile.erb' otherwise.</tt></td>
  </tr>
  <tr>
    <td><tt>dockerfile_template_cookbook</tt></td>
    <td>String</td>
    <td>Cookbook for Dockerfile template.</td>
    <td>build, build_if_missing</td>
    <td><tt>'docker_deploy'</tt></td>
  </tr>
  <tr>
    <td><tt>dockerfile_commands</tt></td>
    <td>Array</td>
    <td>Commands to append into Dockerfile. These will run before the chef-init call to allow for things like initial package updates and passing in environmental variables for use at build time.</td>
    <td>build, build_if_missing</td>
    <td><tt>[]</tt></td>
  </tr>

  <tr>
    <td><tt>first_boot</tt></td>
    <td>Hash</td>
    <td>Chef node attributes to pass in for contianer build. See http://docs.getchef.com/containers.html#container-services</td>
    <td>build, build_if_missing</td>
    <td><tt>{}</tt></td>
  </tr>
  <tr>
    <td><tt>data_bags</tt></td>
    <td>Hash</td>
    <td>Data bags needed during build must be listed here so that they can be copied to the build path for a local mode run. See image build example above for format.</td>
    <td>build, build_if_missing</td>
    <td><tt>{}</tt></td>
  </tr>

  <tr>
    <td><tt>local_template</tt></td>
    <td>String</td>
    <td>Template for zero.rb for container node. This configuration is used in local mode.</td>
    <td>build, build_if_missing</td>
    <td><tt>'local/zero.rb.erb'</tt></td>
  </tr>
  <tr>
    <td><tt>local_template_cookbook</tt></td>
    <td>String</td>
    <td>Cookbook for zero.rb template. This configuration is used in local mode.</td>
    <td>build, build_if_missing</td>
    <td><tt>'docker_deploy'</tt></td>
  </tr>
  <tr>
    <td><tt>local_template_variables</tt></td>
    <td>Hash</td>
    <td>Variables to pass into above template</td>
    <td>build, build_if_missing</td>
    <td><tt>{ :chef_environment => chef_environment }</tt></td>
  </tr>

  <tr>
    <td><tt>config_template</tt></td>
    <td>String</td>
    <td>Template for client.rb for container node. This configuration is used with a Chef server (not local mode).</td>
    <td>build, build_if_missing</td>
    <td><tt>'client.rb.erb'</tt></td>
  </tr>
  <tr>
    <td><tt>config_template_cookbook</tt></td>
    <td>String</td>
    <td>Cookbook for client.rb template. This configuration is used with a Chef server (not local mode).</td>
    <td>build, build_if_missing</td>
    <td><tt>'docker_deploy'</tt></td>
  </tr>
  <tr>
    <td><tt>config_template_variables</tt></td>
    <td>Hash</td>
    <td>Variables to pass into above template</td>
    <td>build, build_if_missing</td>
    <td><tt>{ :chef_server_url => Chef::Config[:chef_server_url], :validation_client_name => validation_client_name }</tt></td>
  </tr>

</table>

#### Actions

:pull

* Pull image by name and tag. Replace existing image if the source is updated.

:pull_if_missing

* Pull only if an image of the same name and tag does not already exist.

:build

* Build image and replace existing image of the same name and tag.

:build_if_missing

* Build image if an image of the same name and tag does not already exist.

:push

* Push image. Tested with local registry.

:remove_if_unused

* Remove image if not referenced by any containers or another image.

## Create container example

```ruby
docker_deploy_container "service_name" do

  ## Base image to run
  base_image "image_name"
  base_image_tag "latest"

  container_base_name "container_name"

  ## Options to pass into docker create
  container_create_options ([
    "--volume=#{vol}",
    "--memory=1073741824",
    "--cpu-shares=256",
    "--publish=0.0.0.0:#{service_port}:#{service_port}",
    "--volume=/#{svc}:/#{svc}",
    "--env=ENV=1",
    ## The Chef environment of the container can be set if not running in local mode
    "--env=CHEF_ENVIRONMENT=development"
  ])

  ## Container node credentials
  encrypted_data_bag_secret encrypted_data_bag_secret
  validation_key validation_key

  ## Number of old contiainers to keep stopped until removed.
  keep_releases 2
  action :create
end
```

#### Options

<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Actions</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>service_name</tt></td>
    <td>String</td>
    <td>Name used to identify the service that a container belongs to. Used for chef node name (if any) and container hostname. Having somethig that identifies both the service and the host node may be a good idea to keep container node names from colliding.</td>
    <td>all</td>
  </tr>
  <tr>
    <td><tt>container_base_name</tt></td>
    <td>String</td>
    <td>Generate unique container names based on this string.</td>
    <td>create</td>
    <td><tt>service_name</tt></td>
  </tr>
  <tr>
    <td><tt>base_image</tt></td>
    <td>String</td>
    <td>Base image for container.</td>
    <td>create</td>
  </tr>
  <tr>
    <td><tt>base_image_tag</tt></td>
    <td>String</td>
    <td>Base image tag for container.</td>
    <td>create</td>
  </tr>
  <tr>
    <td><tt>container_create_optoins</tt></td>
    <td>Array</td>
    <td>Options to pass into docker create command.</td>
    <td>create</td>
    <td><tt>[]</tt></td>
  </tr>
  <tr>
    <td><tt>cache_path</tt></td>
    <td>String</td>
    <td>Path to write some state files to.</td>
    <td>create</td>
    <td><tt>::File.join(Chef::Config[:cache_path], 'docker_deploy', service_name)</tt></td>
  </tr>
  <tr>
    <td><tt>chef_secure_path</tt></td>
    <td>String</td>
    <td>Path to write chef validation key, encrypted_data_bag_secret. This path is mounted to the container.</td>
    <td>create</td>
    <td><tt>::File.join(cache_path, 'chef')</tt></td>
  </tr>
  <tr>
    <td><tt>encrypted_data_bag_secret</tt></td>
    <td>String</td>
    <td>Optional encrypted_data_bag_secret for container node.</td>
    <td>create</td>
  </tr>
  <tr>
    <td><tt>validation_key</tt></td>
    <td>String</td>
    <td>Chef validation key for registering container node. Not needed if running in local mode.</td>
    <td>create</td>
  </tr>
  <tr>
    <td><tt>keep_releases</tt></td>
    <td>Integer</td>
    <td>Number of past container revisions to keep available for rollback.</td>
    <td>create</td>
    <td><tt>3</tt></td>
  </tr>
</table>

#### Actions

:create

* Create and replace current running container of the same service name if configs differ. Old container is stopped and kept available for rollback. Containers are removed after Keep_releases rotations.

:stop

* Stop all containers of service_name.

:remove

* Stop and remove all container of service_name. Associated images are also removed if not used for anything else. Container Chef node can be removed if credentails are provided.

## Sample definitions

docker_build

* Start with community image.
* Build a base image specific to a service.
* Build image specific to service and revision for running as a container.

docker_build_nobase

* Start with community image.
* Build image specific to service and revision for running as a container.

docker_run

* Run imag/tag as container.
* Create init script for starting container.

docker_push

* Push image if it exists

These defintions may be kept in runlist and disabled via the enable_service parameter to allow the recipe to run cleanup actions.

## Issues

* Docker authentication needed for some operations.

* Containers names cannot collide and existing containers cannot be renamed, so each revision of a service container needs a unique name. This makes linking difficult. The container create action some attributes of the active container which may help.

```json
{
  "docker_deploy": {
    "service_mapping": {
      "service_name": {
        "id": "container_id",
        "name": "container_name"
      }
    }
  }
}
```

Also a file containing the active container ID is written to chef_cache_path/service_name/cidfile by default.

* Config comparison between containers of different names generally works but fails with links where the container name gets referenced. There is currently a hack for this.
