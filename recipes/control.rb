include_recipe 'docker_deploy::save_build_node_key' unless ENV['CONTAINER_RUN'].to_i > 0
