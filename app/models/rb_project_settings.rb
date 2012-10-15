require 'rb_scope'

class RbProjectSettings < ActiveRecord::Base
  include RbScope
  unloadable
  serialize :ignored_versions
  serialize :backlog_versions
  belongs_to :project

  validate :versions_valid?

  # returns settings corresponding to the given projects where the project
  # settings are configured with versions to ignore from sprints and backlog
  rb_scope :with_ignored_versions, lambda {|projects|
    if projects.respond_to?(:scoped)
      # given a scope of projects, add and select the project settings columns
      table = RbProjectSettings.table_name
      scope_options = {
          :select => "#{RbProjectSettings.column_names.collect{|column| "#{table}.#{column}" }.join(",")}",
          :joins => :rb_project_settings,
          :conditions => ["#{table}.ignored_versions IS NOT NULL AND #{table}.ignored_versions != ?", [].to_yaml]
      }
      if Rails::VERSION::MAJOR < 3
        projects.scoped(scope_options).scope(:find)
      else
        projects.merge(RbProjectSettings.scoped(scope_options))
      end
    else
      # given a single project, array of projects, project id, or array of project ids
      projects = Array(projects).collect{|project| project.is_a?(Integer) ? project : project.id }
      { :conditions => ["project_id IN (?) AND ignored_versions IS NOT NULL AND ignored_versions != ?", projects, [].to_yaml] }
    end
  }

  # returns settings corresponding to the given projects where the project
  # settings are configured with specific version(s) as the backlog
  rb_scope :with_backlog_versions, lambda {|projects|
    if projects.respond_to?(:scoped)
      # given a scope of projects, add and select the project settings columns
      table = RbProjectSettings.table_name
      scope_options = {
          :select => "#{RbProjectSettings.column_names.collect{|column| "#{table}.#{column}" }.join(",")}",
          :joins => :rb_project_settings,
          :conditions => ["#{table}.backlog_versions IS NOT NULL AND #{table}.backlog_versions != ? AND #{table}.backlog_versions != ?", [].to_yaml, [0].to_yaml]
          }
      if Rails::VERSION::MAJOR < 3
        projects.scoped(scope_options).scope(:find)
      else
        projects.merge(RbProjectSettings.scoped(scope_options))
      end
    else
      # given a single project, array of projects, project id, or array of project ids
      projects = Array(projects).collect{|project| project.is_a?(Integer) ? project : project.id }
      { :conditions => ["project_id IN (?) AND backlog_versions IS NOT NULL AND backlog_versions != ? AND backlog_versions != ?", projects, [].to_yaml, [0].to_yaml] }
    end
  }

  def ignored_versions
    read_attribute(:ignored_versions) || []
  end

  def backlog_versions
    read_attribute(:backlog_versions) || [0]
  end

  # returns versions for the project that can be selected for include and exclude
  # include "(No Version)" with +options+ :include_nil
  def self.filterable_versions_for_project(project, options = {})
    v = Version.open.all(:conditions => {:project_id => project.id})
    v.unshift(nil_version) if options[:include_nil]
    v
  end

  private

  # returns a struct that acts like a version for the purposes of
  # including and excluding versions from the backlog
  def self.nil_version
    Struct.new("NilVersion", :id, :name) unless defined?(Struct::NilVersion)
    Struct::NilVersion.new(0, '(No Version)')
  end

  protected

  def versions_valid?
    unless ignored_versions.nil? || (ignored_versions.is_a?(Array) && ignored_versions.all?{|v|v.is_a?(Integer)})
      errors.add(:ignored_versions, "Must be a list of version ids")
    end
    unless backlog_versions.nil? || (backlog_versions.is_a?(Array) && backlog_versions.all?{|v|v.is_a?(Integer)})
      errors.add(:backlog_versions, "Must be a list of version ids")
    end
    !errors.empty?
  end

end

