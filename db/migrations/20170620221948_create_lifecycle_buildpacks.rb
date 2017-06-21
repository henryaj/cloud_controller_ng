Sequel.migration do
  change do
    create_table :lifecycle_buildpacks do
      VCAP::Migration.common(self)

      Integer :position, null: false
      String  :admin_buildpack_name
      String  :buildpack_lifecycle_data_guid, null: false
      foreign_key [:buildpack_lifecycle_data_guid], :buildpack_lifecycle_data, key: :guid, name: :fk_buildpack_lifecycle_data_guid

    end
  end
end
