# docker_deploy-cookbook

This recipe provides some build and versioning automation for services deployed as Docker containers. Some effort has been put into also keeping the environment clutter free.

* Build container contents with Chef (based on method used by knife-container).
* Removes most of the clutter from failed builds.
* Treat revision containers of the same service as a group.
 * Automatically stop container of a previous revision and replace with new.
 * Detect changes in container configuration and only replace as needed.
 * Keep old revisions available for quick rollback.
 * Rotate out old containers after N releases. Rotation priority is by earliest "finished at" time which is recorded when a running container is stopped.
 * Clean out local images associated with old containers if no longer used.
 * A Chef server node per service per Docker node.
 * Clean up for stale container Chef nodes (if credentials are provided).

## Requirements

* Docker (tested on 1.3.3 and 1.4.1)
* Docker base image with chef-init for build. Chef provides various Docker images with chef-init including:
 * chef/ubuntu-12.04
 * chef/ubuntu-14.04
* Recipe can also be used to just run prebuilt images as containers.

## Create image example

```ruby
docker_deploy_image "image_name" do
  tag "tag"

  base_image "chef/ubuntu-14.04"
  base_image_tag "latest"

  ## Environment for container node
  chef_environment "_default"

  ## Commands to pass into Dockerfile
  dockerfile_commands ([
    'RUN apt-get update && apt-get -y upgrade'
  ])

  ## Properties to for Chef run in the container
  first_boot ({
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
    "run_list" => [
      'recipe[<run>]'
    ]
  })

  ## Allow build node to access the Chef server if building off of a server
  encrypted_data_bag_secret data_bag['encrypted_data_bag_secret']
  validation_key data_bag['validation_key']

  ## Credentials to delete Chef build node if building off of a server
  chef_admin_user "admin"
  chef_admin_key data_bag['private_key']

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
    <td><tt>build_options</tt></td>
    <td>Array</td>
    <td>Options to pass into docker build command.</td>
    <td>build, build_if_missing</td>
    <td><tt>['--force-rm=true']</tt></td>
  </tr>
  <tr>
    <td><tt>dockerfile_commands</tt></td>
    <td>Array</td>
    <td>Commands to append into Dockerfile template.</td>
    <td>build, build_if_missing</td>
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
    <td><tt>chef_server_url</tt></td>
    <td>String</td>
    <td>Chef server URL</td>
    <td>build, build_if_missing</td>
    <td><tt>Chef::Config[:chef_server_url]</tt></td>
  </tr>
  <tr>
    <td><tt>chef_environment</tt></td>
    <td>String</td>
    <td>Chef environment for container node. Written to node client.rb.</td>
    <td>build, build_if_missing</td>
    <td><tt>node.chef_environment</tt></td>
  </tr>
  <tr>
    <td><tt>validation_client_name</tt></td>
    <td>String</td>
    <td>Validation client to use for registering container node. Written to node client.rb.</td>
    <td>build, build_if_missing</td>
    <td><tt>Chef::Config[:validation_client_name]</tt></td>
  </tr>
  <tr>
    <td><tt>validation_key</tt></td>
    <td>String</td>
    <td>Validation key for registering container node during build. Removed after build.</td>
    <td>build, build_if_missing</td>
  </tr>
  <tr>
    <td><tt>encrypted_data_bag_secret</tt></td>
    <td>String</td>
    <td>Optional encrypted_data_bag_secret for use by container node during build. Removed after build.</td>
    <td>build, build_if_missing</td>
  </tr>
  <tr>
    <td><tt>client_template</tt></td>
    <td>String</td>
    <td>Template for client.rb for container node.</td>
    <td>build, build_if_missing</td>
    <td><tt>'client.rb.erb'</tt></td>
  </tr>
  <tr>
    <td><tt>client_template_cookbook</tt></td>
    <td>String</td>
    <td>Cookbook for client.rb template</td>
    <td>build, build_if_missing</td>
    <td><tt>'docker_deploy'</tt></td>
  </tr>
  <tr>
    <td><tt>dockerfile_template</tt></td>
    <td>String</td>
    <td>Template for Dockerfile for container node.</td>
    <td>build, build_if_missing</td>
    <td><tt>'Dockerfile.erb'</tt></td>
  </tr>
  <tr>
    <td><tt>dockerfile_template_cookbook</tt></td>
    <td>String</td>
    <td>Cookbook for Dockerfile template.</td>
    <td>build, build_if_missing</td>
    <td><tt>'docker_deploy'</tt></td>
  </tr>
  <tr>
    <td><tt>first_boot</tt></td>
    <td>Hash</td>
    <td>Chef node attributes to pass in for contianer build. See http://docs.getchef.com/containers.html#container-services</td>
    <td>build, build_if_missing</td>
    <td><tt>{}</tt></td>
  </tr>
  <tr>
    <td><tt>chef_admin_user</tt></td>
    <td>String</td>
    <td>Optional chef admin credentials for cleaning up temp contianer build node/client.</td>
    <td>build, build_if_missing</td>
  </tr>
  <tr>
    <td><tt>chef_admin_key</tt></td>
    <td>String</td>
    <td>Optional chef admin credentials for cleaning up temp contianer build node/client.</td>
    <td>build, build_if_missing</td>
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
    <td>Name used to identify the service that a container belongs to. Used for chef node name (if any) and container hostname.</td>
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
    <td><tt>chef_server_url</tt></td>
    <td>String</td>
    <td>Chef server URL</td>
    <td>create</td>
    <td><tt>Chef::Config[:chef_server_url]</tt></td>
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
    <td>Chef validation key for registering container node.</td>
    <td>create</td>
  </tr>
  <tr>
    <td><tt>keep_releases</tt></td>
    <td>Integer</td>
    <td>Number of past container revisions to keep available for rollback.</td>
    <td>create</td>
    <td><tt>3</tt></td>
  </tr>
  <tr>
    <td><tt>chef_admin_user</tt></td>
    <td>String</td>
    <td>Chef admin credentials for removing container node/client when using the remove action.</td>
    <td>remove</td>
  </tr>
  <tr>
    <td><tt>chef_admin_key</tt></td>
    <td>String</td>
    <td>Chef admin credentials for removing container node/client when using the remove action.</td>
    <td>remove</td>
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

Also a file containing the active container ID is written to chef_cache_path/service_name/cidfile by default.
