class RbQueriesController < RbApplicationController
  unloadable

  def show
    @query = Query.new(:name => "_")
    @query.project = @project
    add_version_column = false

    if params[:sprint_id]
      @query.add_filter("status_id", '*', ['']) # All statuses
      @query.add_filter("fixed_version_id", '=', [params[:sprint_id]])
      @query.add_filter("backlogs_issue_type", '=', ['any'])
    else
      @query.add_filter("status_id", 'o', ['']) # only open
      @query.add_filter("backlogs_issue_type", '=', ['story'])
      version_ids = @project.rb_project_settings.backlog_versions
      if version_ids == [0]
        @query.add_filter("fixed_version_id", '!*', ['']) # only unassigned
      elsif version_ids.include?(0)
        # unassigned plus specific versions
        # we have to do the inverse: not in the other versions
        # FIXME scope on version
        inverse_ids = Version.where(['project_id = ? and id not in (?)', @project.id, (version_ids - [0])]).collect(&:id)
        @query.add_filter("fixed_version_id", '!', inverse_ids.collect(&:to_s))
        add_version_column = true
      else
        @query.add_filter("fixed_version_id", '=', version_ids.collect(&:to_s))
        add_version_column = true
      end
    end

    column_names = @query.columns.collect{|col| col.name}
    column_names = column_names + ['position'] unless column_names.include?('position')
    column_names = column_names + ['fixed_version'] if add_version_column

    session[:query] = {:project_id => @query.project_id, :filters => @query.filters, :column_names => column_names}
    redirect_to :controller => 'issues', :action => 'index', :project_id => @project.id, :sort => 'position'
  end

  def impediments
    @query = Query.new(:name => "_")
    @query.project = @project
    @query.add_filter("status_id", 'o', ['']) # only open
    @query.add_filter("fixed_version_id", '=', [params[:sprint_id]])
    @query.add_filter("backlogs_issue_type", '=', ['impediment'])
    session[:query] = {:project_id => @query.project_id, :filters => @query.filters }
    redirect_to :controller => 'issues', :action => 'index', :project_id => @project.id
  end
end
