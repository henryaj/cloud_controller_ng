Sequel.migration do
  change do
    add_table
    VCAP::Migration.common(self, :buildpack_lifecycle_buildpacks)

    String :admin_buildpack_name

    String :buildpack_url

    Integer :buildpack_lifecycle_data_id, :,

    foreign_key [:buildpack_lifecycle_data_id], :buildpack_lifecycle_data, name: :fk_blbuildpack_bldata_id
    index [:buildpack_lifecycle_data_id], unique: false, name: :bl_buildpack_bldata_id_index

  end
end
