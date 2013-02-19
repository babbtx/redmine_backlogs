include RbCommonHelper
include ProjectsHelper

class RbProjectSettingsController < RbApplicationController
  unloadable

  def project_settings
    head(:bad_request) unless request.post?

    settings = @project.rb_project_settings

    enabled = false
    enabled_scrum_stats = false
    if params[:settings]
      enabled = true if params[:settings]["show_stories_from_subprojects"]=="enabled"
      enabled_scrum_stats = true if params[:settings]["show_in_scrum_stats"]=="enabled"
    end
    settings.show_stories_from_subprojects = enabled
    settings.show_in_scrum_stats = enabled_scrum_stats

    if params[:settings][:ignored_versions].present?
      settings.ignored_versions = params[:settings][:ignored_versions].collect(&:to_i)
    end
    if params[:settings][:backlog_versions].present?
      settings.backlog_versions = params[:settings][:backlog_versions].collect(&:to_i)
    end

    if settings.save
      flash[:notice] = t(:rb_project_settings_updated)
    else
      flash[:error] = "While updating settings, #{settings.errors.full_messages.to_sentence}"
    end
    redirect_to :controller => 'projects', :action => 'settings', :id => @project,
                :tab => 'backlogs'
  end

end
