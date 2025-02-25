# frozen_string_literal: true

require_relative '../test_helper'

class CommonViewsTest < Redmine::IntegrationTest
  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :trackers,
           :projects_trackers,
           :enabled_modules,
           :issue_statuses,
           :issues,
           :enumerations,
           :custom_fields,
           :custom_values,
           :custom_fields_trackers

  def setup
    RedmineMessenger::TestCase.prepare
  end

  test 'View user' do
    log_user 'admin', 'admin'
    get '/users/2'

    assert_response :success
  end

  test 'View issue' do
    log_user 'admin', 'admin'
    EnabledModule.create project_id: 1, name: 'issue_tracking'
    issue = Issue.where(id: 1).first
    issue.save
    get '/issues/1'

    assert_response :success
  end
end
