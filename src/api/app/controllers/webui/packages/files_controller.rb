module Webui
  module Packages
    class FilesController < Packages::MainController
      include Webui::PackageHelper

      before_action :set_project
      before_action :set_package
      before_action :set_filename, only: %i[show update destroy]
      before_action :ensure_existence, only: :show
      before_action :ensure_viewable, only: :show
      before_action :set_file, only: :show

      after_action :verify_authorized, except: :show

      def show
        @rev = params[:rev]
        @expand = params[:expand]
        @addeditlink = false

        if User.possibly_nobody.can_modify?(@package) && @rev.blank? && @package.scmsync.blank?
          files = @package.dir_hash({ rev: @rev, expand: @expand }.compact).elements('entry')
          if (file = files.find { |f| f['name'] == @filename }.presence)
            @addeditlink = editable_file?(@filename, file['size'].to_i)
          end
        end

        render(template: 'webui/packages/files/simple_show') && return if @spider_bot
      end

      def new
        authorize @package, :update?
      end

      def create
        authorize @package, :update?

        files = params[:files] || []
        filename = params[:filename]
        files << ActionDispatch::Http::UploadedFile.new(tempfile: Tempfile.new(''), filename: filename) if filename.present?
        file_url = params[:file_url]

        errors = []

        if file_url.present?
          # we have a remote file URI, so we have to download and save it
          services = @package.services

          # detects automatically git://, src.rpm formats
          services.add_download_url(file_url, filename)
          added_files = filename || '_service'

          errors << "Failed to add file from URL '#{file_url}'" unless services.save
        elsif files.present?
          # we get files to upload to the backend
          upload_service = FileService::Uploader.new(@package, files, params[:comment])
          upload_service.call
          errors << upload_service.errors
          added_files = upload_service.added_files
        else
          errors << 'No file or URI given'
        end

        if errors.compact_blank.empty?
          redirect_to(package_show_path(project: @project, package: @package),
                      success: "#{added_files} have been successfully saved.")
        else
          redirect_back(fallback_location: root_path,
                        error: "Error while creating #{added_files} files: #{errors.compact_blank.join("\n")}.")
        end
      end

      def update
        return unless request.xhr?

        authorize @package, :update?

        errors = []

        begin
          @package.save_file(file: params[:file], filename: @filename,
                             comment: params[:comment])
        rescue APIError, StandardError => e
          errors << e.message
        rescue Backend::Error => e
          errors << Xmlhash::XMLHash.new(error: e.summary)[:error]
        end

        if errors.blank?
          flash.now[:success] = "'#{@filename}' has been successfully saved."
        else
          flash.now[:error] = "Error while adding '#{@filename}': #{errors.compact.join("\n")}."
          status = 400
        end

        status ||= 200
        render layout: false, status: status, partial: 'layouts/webui/flash', object: flash
      end

      def destroy
        authorize @package, :update?

        begin
          @package.delete_file(@filename)
          flash[:success] = "File '#{@filename}' removed successfully"
        rescue Backend::NotFoundError
          flash[:error] = "Failed to remove file '#{@filename}'"
        end

        redirect_to package_show_path(project: @project, package: @package)
      end

      private

      def set_filename
        @filename = params[:filename]
      end

      def ensure_existence
        return if @package.file_exists?(@filename, params.slice(:rev, :expand).permit!.to_h)

        flash[:error] = "File not found: #{@filename}"
        redirect_to package_show_path(project: @project, package: @package)
      end

      def ensure_viewable
        return unless binary_file?(@filename) # We don't want to display binary files

        flash[:error] = "Unable to display binary file #{@filename}"
        redirect_back(fallback_location: package_show_path(project: @project, package: @package))
      end

      def set_file
        @file = @package.source_file(@filename, params.slice(:rev, :expand).permit!.to_h)
      rescue Backend::Error => e
        flash[:error] = "Error: #{e}"
        redirect_back(fallback_location: package_show_path(project: @project, package: @package))
      end
    end
  end
end
