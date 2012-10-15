class AddVersionFiltersToProjectSettings < ActiveRecord::Migration
  def self.up
    add_column :rb_project_settings, :ignored_versions, :text
    add_column :rb_project_settings, :backlog_versions, :text
  end
  def self.down
    remove_column :rb_project_settings, :ignored_versions
    remove_column :rb_project_settings, :backlog_versions
  end
end