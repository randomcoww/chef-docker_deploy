module DockerDeployErrors

  class DockerDeployError < StandardError; end

  class PullImageError < DockerDeployError; end
  class GetImageError < DockerDeployError; end
  class BuildImageError < DockerDeployError; end
  class PushImageError < DockerDeployError; end

  class CreateContainerError < DockerDeployError; end
  class StartContainerError < DockerDeployError; end
  class StopContainerError < DockerDeployError; end
end
