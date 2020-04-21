module Repositories
  class StatePresenter < SimpleDelegator
    attr_reader :published_repository_exist, :download_area_url

    def initialize(project, repository, configuration)
      download_url = configuration['download_url']
      @published_repository_exist = Backend::Api::Published.published_repository_exist?(project.to_s, repository.to_s)
      @download_area_url = "#{download_url}/#{project.to_s.gsub(/:/, ':/')}/#{repository}"
    end
  end
end
