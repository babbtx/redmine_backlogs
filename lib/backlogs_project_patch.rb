require_dependency 'project'

module Backlogs
  class Statistics
    def initialize(project)
      @project = project
      @statistics = {:succeeded => [], :failed => [], :values => {}}

      @active_sprint = RbSprint.find(:first, :conditions => ["project_id = ? and status = 'open' and not (sprint_start_date is null or effective_date is null) and ? between sprint_start_date and effective_date", @project.id, Date.today])
      @past_sprints = RbSprint.find(:all,
        :conditions => ["project_id = ? and not(effective_date is null or sprint_start_date is null) and effective_date < ?", @project.id, Date.today],
        :order => "effective_date desc",
        :limit => 5).select(&:has_burndown?)
      @all_sprints = (@past_sprints + [@active_sprint]).compact

      @all_sprints.each{|sprint| sprint.burndown.direction = :up }
      days = @past_sprints.collect{|s| s.days.size}.sum
      if days != 0
        @points_per_day = @past_sprints.collect{|s| s.burndown.data[:points_committed][0]}.compact.sum / days
      end

      if @all_sprints.size != 0
        @velocity = @past_sprints.collect{|sprint| sprint.burndown.data[:points_accepted][-1].to_f}
        @velocity_stddev = stddev(@velocity)
      end

      @product_backlog = RbStory.product_backlog(@project, 10)

      hours_per_point = []
      @all_sprints.each {|sprint|
        hours = sprint.burndown.data[:hours_remaining][0].to_f
        next if hours == 0.0
        hours_per_point << sprint.burndown.data[:points_committed][0].to_f / hours
      }
      @hours_per_point_stddev = stddev(hours_per_point)
      @hours_per_point = hours_per_point.sum.to_f / hours_per_point.size unless hours_per_point.size == 0

      Statistics.active_tests.sort.each{|m|
        r = send(m.intern)
        next if r.nil? # this test deems itself irrelevant
        @statistics[r ? :succeeded : :failed] <<
          (m.to_s.gsub(/^test_/, '') + (r ? '' : '_failed'))
      }
      Statistics.stats.sort.each{|m|
        v = send(m.intern)
        @statistics[:values][m.to_s.gsub(/^stat_/, '')] = v unless v.nil? || (v.respond_to?(:"nan?") && v.nan?) || (v.respond_to?(:"infinite?") && v.infinite?)
      }

      if @statistics[:succeeded].size == 0 && @statistics[:failed].size == 0
        @score = 100 # ?
      else
        @score = (@statistics[:succeeded].size * 100) / (@statistics[:succeeded].size + @statistics[:failed].size)
      end
    end

    attr_reader :statistics, :score
    attr_reader :active_sprint, :past_sprints
    attr_reader :hours_per_point

    def stddev(values)
      median = values.sum / values.size.to_f
      variance = 1.0 / (values.size * values.inject(0){|acc, v| acc + (v-median)**2})
      return Math.sqrt(variance)
    end

    def self.available
      return Statistics.instance_methods.select{|m| m =~ /^test_/}.collect{|m| m.split('_', 2).collect{|s| s.intern}}
    end

    def self.active_tests
      # test this!
      return Statistics.instance_methods.select{|m| m =~ /^test_/}.reject{|m| Backlogs.setting["disable_stats_#{m}".intern] }
    end

    def self.active
      return Statistics.active_tests.collect{|m| m.split('_', 2).collect{|s| s.intern}}
    end

    def self.stats
      return Statistics.instance_methods.select{|m| m =~ /^stat_/}
    end

    def info_no_active_sprint
      return !@active_sprint
    end

    def test_product_backlog_filled
      return (@project.status != Project::STATUS_ACTIVE || @product_backlog.length != 0)
    end

    def test_product_backlog_sized
      return !@product_backlog.detect{|s| s.story_points.blank? }
    end

    def test_sprints_sized
      return !Issue.exists?(["story_points is null and fixed_version_id in (?) and tracker_id in (?)", @all_sprints.collect{|s| s.id}, RbStory.trackers])
    end

    def test_sprints_estimated
      return !Issue.exists?(["estimated_hours is null and fixed_version_id in (?) and tracker_id = ?", @all_sprints.collect{|s| s.id}, RbTask.tracker])
    end

    def test_sprint_notes_available
      return !@past_sprints.detect{|s| !s.has_wiki_page}
    end

    def test_active
      return (@project.status != Project::STATUS_ACTIVE || (@active_sprint && @active_sprint.activity))
    end

    def test_yield
      accepted = []
      @past_sprints.each {|sprint|
        bd = sprint.burndown
        bd.direction = :up
        c = bd.data[:points_committed][-1]
        a = bd.data[:points_accepted][-1]
        next unless c && a && c != 0

        accepted << [(a * 100.0) / c, 100.0].min
      }
      return false if accepted == []
      return (stddev(accepted) < 10) # magic number
    end

    def test_committed_velocity_stable
      return (@velocity_stddev && @velocity_stddev < 4) # magic number!
    end

    def test_sizing_consistent
      return (@hours_per_point_stddev < 4) # magic number
    end

    def stat_sprints
      return @past_sprints.size
    end

    def stat_velocity
      return nil unless @velocity && @velocity.size > 0
      return @velocity.sum / @velocity.size
    end

    def stat_velocity_stddev
      return @velocity_stddev
    end

    def stat_sizing_stddev
      return @hours_per_point_stddev
    end

    def stat_hours_per_point
      return @hours_per_point
    end
  end

  module ProjectPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.class_eval do
        has_one :rb_project_settings, :dependent => :destroy
        include Backlogs::ActiveRecord::Attributes
      end
    end

    module ClassMethods
    end

    module InstanceMethods

      def scrum_statistics
        ## pretty expensive to compute, so if we're calling this multiple times, return the cached results
        @scrum_statistics ||= Backlogs::Statistics.new(self)
      end

      def rb_project_settings
        project_settings = RbProjectSettings.first(:conditions => ["project_id = ?", self.id])
        unless project_settings
          project_settings = RbProjectSettings.new( :project_id => self.id)
          project_settings.save
        end
        project_settings
      end

      def projects_in_shared_product_backlog
        #sharing off: only the product itself is in the product backlog
        #sharing on: subtree is included in the product backlog
        if Backlogs.setting[:sharing_enabled] and self.rb_project_settings.show_stories_from_subprojects
          self.self_and_descendants.active
        else
          [self]
        end
        #TODO have an explicit association map which project shares its issues into other product backlogs
      end

      #return sprints which are 
      # 1. open in project,
      # 2. share to project, 
      # 3. share to project but are scoped to project and subprojects
      #depending on sharing mode
      def open_shared_sprints
        if Backlogs.setting[:sharing_enabled]
          # ignore the ignored versions plus the backlog
          ignored = RbProjectSettings.with_ignored_versions(self.self_and_descendants).collect(&:ignored_versions)
          ignored += RbProjectSettings.with_backlog_versions(self.self_and_descendants).collect(&:backlog_versions)
          ignored.flatten!
          shared_versions.
              scoped(RbSprint.find_options(:ignored => ignored, :status => ['open', 'locked'])).
              collect{|v| v.becomes(RbSprint) }
        else #no backlog sharing
          RbSprint.open_sprints(self)
        end 
      end

      #depending on sharing mode
      def closed_shared_sprints
        if Backlogs.setting[:disable_closed_sprints_to_master_backlogs]
          return []
        else
          if Backlogs.setting[:sharing_enabled]
            # ignore the ignored versions plus the backlog
            ignored = RbProjectSettings.with_ignored_versions(self.self_and_descendants).collect(&:ignored_versions)
            ignored += RbProjectSettings.with_backlog_versions(self.self_and_descendants).collect(&:backlog_versions)
            ignored.flatten!
            shared_versions.
                scoped(RbSprint.find_options(:ignored => ignored, :status => 'closed')).
                collect{|v| v.becomes(RbSprint) }
          else #no backlog sharing
            RbSprint.closed_sprints(self)
          end
        end #disable_closed
      end

    end
  end
end

Project.send(:include, Backlogs::ProjectPatch) unless Project.included_modules.include? Backlogs::ProjectPatch
