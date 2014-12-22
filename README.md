# docker_deploy-cookbook

Cookbook for simple project deployments using Docker. Includes container rotation and deletion after N deployments.
Wrapper for docker ruby API with knife-container like container deployment.

## Supported Platforms

TODO: List your supported platforms.

## Create image

```ruby
docker_deploy_image "image_name" do
  tag "latest"
  base_image "chef/ubuntu-14.04"
  base_image_tag "latest"
  chef_environment "_default"
  docker_build_commands ([
    'RUN apt-get update'
  ])
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
      'recipe[runit::default]'
    ],
    "container_service" => {
      "cron" => {
        "command" => "/usr/sbin/cron -f"
      }
    }
  })
  encrypted_data_bag_secret encrypted_data_bag_secret
  validation_key validation_key
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

:try_pull

* Same as pull but silently skip this step if the image cannot be pulled.

:try_pull_if_missing

* Same as pull_if_missing but silently skip this step if the image cannot be pulled.

:build

* Build image and replace existing image of the same name and tag.

:build_if_missing

* Build image if an image of the same name and tag does not already exist.

:push

* Push image. Push to local registry only so far.

## Create container

```ruby
docker_deploy_container "container_name" do
  base_image "image_name"
  base_image_tag "latest"
  node_name "sample_service"
  port_bindings ({
    "8081/tcp" => [
      {
        "HostIp" => "0.0.0.0",
        "HostPort" => "8081"
      }
    ],
    "8080/tcp" => [
      {
        "HostIp" => "0.0.0.0",
        "HostPort" => "8080"
      }
    ]
  })
  binds ([
    "/test:/test"
  ])
  env ([
    "TEST=env"
  ])
  container_create_options ({
    "ExposedPorts" => {
      "8081/tcp" => {},
      "8080/tcp" => {}
    }
  })
  container_start_options ({
    "Privileged" => true
  })
  chef_secure_dir "/var/chef/sample"
  encrypted_data_bag_secret encrypted_data_bag_secret
  validation_key validation_key
  keep_releases 2
  stop_conflicting true
  action :create_and_rotate
end
```

#### Actions

:create

* Create and replace existing container of the same name.
 * There are checks in place to attempt to detect identical container configurations and only create and replace an existing container as needed.

:create_if_missing

* Create only if a container of the same name does not already exist.

:create_and_rotate

* Rotate containers by common node_name.
 * Create new container with unique name of format base_name-random_string to avoid name conflict.
 * Stop but keep N containers with the same node_name.
 * Older containers with the same node_name are deleted in order of earliest time stopped.
 * Images of deleted containers are also removed if not used by any other container.
