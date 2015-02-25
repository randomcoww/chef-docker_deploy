# docker_deploy-cookbook

This recipe provides some version control automation for service deploymenhts as Docker containers.


Recipe for facilitating Docker deployments.



* Some automation for handling deployment of container revisions
 * 


* Treat revisions of same service image/containers as a group.
 * Detect container config changes.
 * Automatically stop and replace containers of old revisions with new.
 * Keep old revisions and remove after N rotations.
 * Cleanup associated images.

* Some automation involving image builds including cleaning bad builds

## Requirements

* Docker
* Docker image with chef-init

Chef provides various Docker base images with chef-init including:
* chef/ubuntu-12.04
* chef/ubuntu-14.04

## Supported Platforms

* Docker 1.3.3-1.4.1

## Create image example

```ruby
docker_deploy_image "image_name" do
  tag "tag"

  ## Base image should run chef-init
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

* Remove image in not referenced by any containers or another image.

## Create container example

```ruby
docker_deploy_container "service_name" do

  ## Base image to run
  base_image "image_name"
  base_image_tag "latest"
  node_name "sample_service"
  container_create_options ([
    "--volume=<vol>",
    "--memory=1073741824",
    "--cpu-shares=256",
    "--publish=0.0.0.0:#{service_port}:#{service_port}",
    "--volume=/m/apps/#{svc}:/m/apps/#{svc}",
    "--env=ENV=1",
  ])
  encrypted_data_bag_secret encrypted_data_bag_secret
  validation_key validation_key
  keep_releases 2
  action :create
end
```

#### Actions

:create

* Rotate containers by common node_name.
 * Create new container with unique name of format base_name-random_string to avoid name conflict.
 * Stop but keep N containers with the same node_name.
 * Older containers with the same node_name are deleted in order of earliest time stopped.
 * Images of deleted containers are also removed if not used by any other container.

:stop

* 

:remove
:nothing
