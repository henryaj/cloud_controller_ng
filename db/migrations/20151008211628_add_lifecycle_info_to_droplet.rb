Sequel.migration do
  up do
    add_column :v3_droplets, :stack_name, String, text: true, null: true
    add_column :v3_droplets, :lifecycle, String, text: true, null: true
    rename_column :v3_droplets, :procfile, :process_types, type: :text
    add_column :v3_droplets, :execution_metadata, String, text: true, null: true
    add_column :v3_droplets, :memory_limit, Integer, null: true
    add_column :v3_droplets, :disk_limit, Integer, null: true
  end

  down do
    alter_table(:v3_droplets) do
      rename_column :process_types, :procfile, type: :text
      drop_column :execution_metadata
      drop_column :stack_name
      drop_column :lifecycle
      drop_column :memory_limit
      drop_column :disk_limit
    end
  end
end
