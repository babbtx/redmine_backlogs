require 'date'
require 'rb_scope'

class RbSprint < Version
  include RbScope
  unloadable

  validate :start_and_end_dates

  def start_and_end_dates
    errors.add(:base, "sprint_end_before_start") if self.effective_date && self.sprint_start_date && self.sprint_start_date >= self.effective_date
  end

  # +options+ can include:
  #
  #  :status      sprint status (String or Array) [open]
  #  :project_id  only versions associated with this project [no default]
  #  :ignored     version ids to be ignored [no default]
  #
  def self.find_options(options = {})
    status = options[:status] || 'open'
    status = Array(status)
    conditions = ['versions.status in (?)', status.collect(&:to_s)]

    if options.include?(:project_id)
      conditions.first << ' and versions.project_id = ?'
      conditions << options[:project_id]
    end

    if options.include?(:ignored)
      ignored = options[:ignored]
      unless ignored.empty?
        conditions.first << " and versions.id not in (?)"
        conditions << ignored
      end
    end

    { 
      :order => "CASE sprint_start_date WHEN NULL THEN 1 ELSE 0 END ASC,
                sprint_start_date ASC,
                CASE effective_date WHEN NULL THEN 1 ELSE 0 END ASC,
                effective_date ASC",
      :conditions => conditions
    }
  end

  rb_scope :open_sprints, lambda { |project|
    # ignore the ignored versions plus the backlog
    ignored = RbProjectSettings.with_ignored_versions(project).collect(&:ignored_versions)
    ignored += RbProjectSettings.with_backlog_versions(project).collect(&:backlog_versions)
    ignored.flatten!
    find_options(:project_id => project.id, :ignored => ignored, :status => 'open')  #FIXME locked, too?
  }

  #TIB ajout du scope :closed_sprints
  rb_scope :closed_sprints, lambda { |project|
    # ignore the ignored versions plus the backlog
    ignored = RbProjectSettings.with_ignored_versions(project).collect(&:ignored_versions)
    ignored += RbProjectSettings.with_backlog_versions(project).collect(&:backlog_versions)
    ignored.flatten!
    find_options(:project_id => project.id, :ignored => ignored, :status => 'closed')
  }

  #depending on sharing mode
  #return array of projects where this sprint is visible
  def shared_to_projects(scope_project)
    projects = []
    Project.visible.find(:all, :order => 'lft').each{|_project| #exhaustive search FIXME (pa sharing)
      projects << _project unless (_project.shared_versions.collect{|v| v.id} & [id]).empty?
    }
    projects
  end

  def stories
    return RbStory.sprint_backlog(self)
  end

  def points
    return stories.inject(0){|sum, story| sum + story.story_points.to_i}
  end

  def has_wiki_page
    return false if wiki_page_title.blank?

    page = project.wiki.find_page(self.wiki_page_title)
    return false if !page

    template = find_wiki_template
    return false if template && page.text == template.text

    return true
  end

  def find_wiki_template
    projects = [self.project] + self.project.ancestors

    template = Backlogs.setting[:wiki_template]
    if template =~ /:/
      p, template = *template.split(':', 2)
      projects << Project.find(p)
    end

    projects.compact!

    projects.each{|p|
      next unless p.wiki
      t = p.wiki.find_page(template)
      return t if t
    }
    return nil
  end

  def wiki_page
    if ! project.wiki
      return ''
    end

    self.update_attribute(:wiki_page_title, Wiki.titleize(self.name)) if wiki_page_title.blank?

    page = project.wiki.find_page(self.wiki_page_title)
    if !page
      template = find_wiki_template
      if template
      page = WikiPage.new(:wiki => project.wiki, :title => self.wiki_page_title)
      page.content = WikiContent.new
      page.content.text = "h1. #{self.name}\n\n#{template.text}"
      page.save!
      end
    end

    return wiki_page_title
  end

  def eta
    return nil if ! self.sprint_start_date

    dpp = self.project.scrum_statistics.info[:average_days_per_point]
    return nil if !dpp

    derived_days = if Backlogs.setting[:include_sat_and_sun]
                     Integer(self.points * dpp)
                   else
                     # 5 out of 7 are working days
                     Integer(self.points * dpp * 7.0/5)
                   end
    return self.sprint_start_date + derived_days
  end

  def activity
    bd = self.burndown

    # assume a sprint is active if it's only 2 days old
    return true if bd[:hours_remaining] && bd[:hours_remaining].compact.size <= 2

    return Issue.exists?(['fixed_version_id = ? and ((updated_on between ? and ?) or (created_on between ? and ?))', self.id, -2.days.from_now, Time.now, -2.days.from_now, Time.now])
  end

  def impediments
    @impediments ||= Issue.find(:all,
      :conditions => ["id in (
              select issue_from_id
              from issue_relations ir
              join issues blocked
                on blocked.id = ir.issue_to_id
                and blocked.tracker_id in (?)
                and blocked.fixed_version_id = (?)
              where ir.relation_type = 'blocks'
              )",
            RbStory.trackers + [RbTask.tracker],
            self.id]
      ) #.sort {|a,b| a.closed? == b.closed? ?  a.updated_on <=> b.updated_on : (a.closed? ? 1 : -1) }
  end
end
