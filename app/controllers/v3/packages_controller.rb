require 'presenters/v3/package_presenter'
require 'presenters/v3/paginated_list_presenter'
require 'fetchers/package_list_fetcher'
require 'actions/package_delete'
require 'actions/package_upload'
require 'actions/package_create'
require 'actions/package_copy'
require 'messages/packages/package_create_message'
require 'messages/packages/package_upload_message'
require 'messages/packages/packages_list_message'
require 'controllers/v3/mixins/sub_resource'

class PackagesController < ApplicationController
  include SubResource

  before_action :check_read_permissions!, only: [:index, :show, :download]

  def index
    message = PackagesListMessage.from_params(subresource_query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    if app_nested?
      app, dataset = PackageListFetcher.new.fetch_for_app(message: message)
      app_not_found! unless app && can_read?(app.space.guid, app.organization.guid)
    else
      dataset = if can_read_globally?
                  PackageListFetcher.new.fetch_all(message: message)
                else
                  PackageListFetcher.new.fetch_for_spaces(message: message, space_guids: readable_space_guids)
                end
    end

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(dataset: dataset, path: base_url(resource: 'packages'), message: message)
  end

  def upload
    FeatureFlag.raise_unless_enabled!(:app_bits_upload)

    message = PackageUploadMessage.create_from_params(params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    package = PackageModel.where(guid: params[:guid]).eager(:space, space: :organization).all.first
    package_not_found! unless package && can_read?(package.space.guid, package.space.organization.guid)
    unauthorized! unless can_write?(package.space.guid)

    unprocessable!('Package type must be bits.') unless package.type == 'bits'
    bits_already_uploaded! if package.state != PackageModel::CREATED_STATE

    begin
      PackageUpload.new.upload_async(
        message:         message,
        package:         package,
        config:          configuration,
        user_audit_info: user_audit_info
      )
    rescue PackageUpload::InvalidPackage => e
      unprocessable!(e.message)
    end

    render status: :ok, json: Presenters::V3::PackagePresenter.new(package)
  end

  def download
    package = PackageModel.where(guid: params[:guid]).eager(:space, space: :organization).all.first
    package_not_found! unless package && can_read?(package.space.guid, package.space.organization.guid)
    unauthorized! unless can_see_secrets?(package.space)

    unprocessable!('Package type must be bits.') unless package.type == 'bits'
    unprocessable!('Package has no bits to download.') unless package.state == 'READY'

    VCAP::CloudController::Repositories::PackageEventRepository.record_app_package_download(
      package,
      user_audit_info
    )

    send_package_blob(package)
  end

  def show
    package = PackageModel.where(guid: params[:guid]).eager(:space, space: :organization).all.first
    package_not_found! unless package && can_read?(package.space.guid, package.space.organization.guid)

    render status: :ok, json: Presenters::V3::PackagePresenter.new(package)
  end

  def destroy
    package = PackageModel.where(guid: params[:guid]).eager(:space, space: :organization).all.first
    package_not_found! unless package && can_read?(package.space.guid, package.space.organization.guid)
    unauthorized! unless can_write?(package.space.guid)

    PackageDelete.new(user_audit_info).delete(package)

    head :no_content
  end

  def create
    if params[:source_guid]
      create_copy
    else
      create_fresh
    end
  end

  private

  def create_fresh
    message = PackageCreateMessage.create_from_http_request(params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    app = AppModel.where(guid: message.app_guid).eager(:space, :organization).all.first
    unprocessable_app! unless app && can_read?(app.space.guid, app.organization.guid)
    unauthorized! unless can_write?(app.space.guid)

    package = PackageCreate.create(message: message, user_audit_info: user_audit_info)

    render status: :created, json: Presenters::V3::PackagePresenter.new(package)
  rescue PackageCreate::InvalidPackage => e
    unprocessable!(e.message)
  end

  def create_copy
    app_guid = params[:body][:relationships][:app][:data][:guid]
    destination_app = AppModel.where(guid: app_guid).eager(:space, :organization).all.first
    app_not_found! unless destination_app && can_read?(destination_app.space.guid, destination_app.organization.guid)
    unauthorized! unless can_write?(destination_app.space.guid)

    source_package = PackageModel.where(guid: params[:source_guid]).eager(:app, :space, space: :organization).all.first
    package_not_found! unless source_package && can_read?(source_package.space.guid, source_package.space.organization.guid)
    unauthorized! unless can_write?(source_package.space.guid)

    package = PackageCopy.new.copy(
      destination_app_guid: app_guid,
      source_package:       source_package,
      user_audit_info:      user_audit_info
    )

    render status: :created, json: Presenters::V3::PackagePresenter.new(package)
  rescue PackageCopy::InvalidPackage => e
    unprocessable!(e.message)
  end

  def package_not_found!
    resource_not_found!(:package)
  end

  def bits_already_uploaded!
    raise CloudController::Errors::ApiError.new_from_details('PackageBitsAlreadyUploaded')
  end

  def send_package_blob(package)
    package_blobstore = CloudController::DependencyLocator.instance.package_blobstore
    BlobDispatcher.new(blobstore: package_blobstore, controller: self).send_or_redirect(guid: package.guid)
  end

  def unprocessable_app!
    unprocessable!('App is invalid. Ensure it exists and you have access to it.')
  end
end
