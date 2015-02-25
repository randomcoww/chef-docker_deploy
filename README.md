# docker_deploy-cookbook

This recipe provides some versioning automation for services deployed as Docker containers:

* Treat a revision containers of the same service as a group.
 * Automatically stop container of a previous revision and replace with new.
 * Keep old revisions available for quick rollback.
 * Rotate out old containers after N releases.
 * Detect changes in container configuration and only replace as needed.
 * Clean out local images associated with old containers if no longer used.

Some image build options:

* Build container contents using chef (based on method used by knife-container)

## Requirements

* Docker 1.3.3-1.4.1
* Docker base image with chef-init

Chef provides various Docker images with chef-init including:
* chef/ubuntu-12.04
* chef/ubuntu-14.04

## Create image example

```ruby
docker_deploy_image "image_name" do
  tag "tag"

  base_image "chef/ubuntu-14.04"
  base_image_tag "latest"

  ## Environment for container node
  chef_environment "_default"

  ## Commands to pass into Dockerfile
  docker_build_commands ([
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

* Push image. Push to local registry only so far.

:remove_if_unused

* Remove image if not referenced by any containers or another image.

## Create container example

```ruby
docker_deploy_container "service_name" do

  ## Base image to run
  base_image "image_name"
  base_image_tag "latest"

  ## Chef node name if connecting to a server and also the hostname of the container
  node_name "sample_service"

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

#### Actions

:create

* Create and replace current running container of the same service name if configs differ. Old container is stopped and kept available for rollback. Containers are removed after Keep_releases rotations.

:stop

* Stop all containers of service_name.

:remove

* Stop and remove all container of service_name. Associated images are also removed if not used for anything else.
