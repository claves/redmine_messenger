# frozen_string_literal: true

module RedmineMessenger
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        include InstanceMethods

        after_create_commit :send_messenger_create
        after_update_commit :send_messenger_update
      end

      module InstanceMethods
        def send_messenger_create
          channels = Messenger.channels_for_project project
          url = Messenger.url_for_project project

          if Messenger.setting_for_project project, :messenger_direct_users_messages
            messenger_to_be_notified.each do |user|
              channels.append get_slack_mention_code(user) unless user == author
            end
          end

          return unless channels.present? && url
          return if is_private? && !Messenger.setting_for_project(project, :post_private_issues)

          initial_language = ::I18n.locale
          begin
            set_language_if_valid Setting.default_language

            attachment = {}
            if description.present? && Messenger.setting_for_project(project, :new_include_description)
              attachment[:text] = Messenger.markup_format description
            end
            attachment[:fields] = [{ title: I18n.t(:field_status),
                                     value: Messenger.markup_format(status.to_s),
                                     short: true },
                                   { title: I18n.t(:field_priority),
                                     value: Messenger.markup_format(priority.to_s),
                                     short: true }]
            if assigned_to.present?
              attachment[:fields] << { title: I18n.t(:field_assigned_to),
                                       value: Messenger.markup_format(assigned_to.to_s),
                                       short: true }
            end

            attachments.each do |att|
              attachment[:fields] << { title: I18n.t(:label_attachment),
                                       value: "<#{Messenger.object_url att}|#{ERB::Util.html_escape att.filename}>",
                                       short: true }
            end

            if RedmineMessenger.setting?(:display_watchers) && watcher_users.count.positive?
              attachment[:fields] << {
                title: I18n.t(:field_watcher),
                value: Messenger.markup_format(watcher_users.join(', ')),
                short: true
              }
            end

            Messenger.speak l(:label_messenger_issue_created,
                              project_url: Messenger.project_url_markdown(project),
                              url: send_messenger_mention_url(project, description),
                              user: author),
                            channels, url, attachment: attachment, project: project
          ensure
            ::I18n.locale = initial_language
          end
        end

        def send_messenger_update
          return if current_journal.nil?

          channels = Messenger.channels_for_project project
          url = Messenger.url_for_project project

          if Messenger.setting_for_project project, :messenger_direct_users_messages
            messenger_to_be_notified.each do |user|
              channels.append get_slack_mention_code(user) unless user == current_journal.user
            end
          end

          return unless channels.present? && url && Messenger.setting_for_project(project, :post_updates)
          return if is_private? && !Messenger.setting_for_project(project, :post_private_issues)
          return if current_journal.private_notes? && !Messenger.setting_for_project(project, :post_private_notes)

          initial_language = ::I18n.locale
          begin
            set_language_if_valid Setting.default_language

            attachment = {}
            if Messenger.setting_for_project project, :updated_include_description
              attachment_text = Messenger.attachment_text_from_journal current_journal
              attachment[:text] = attachment_text if attachment_text.present?
            end

            fields = current_journal.details.map { |d| Messenger.detail_to_field d, project }
            if current_journal.notes.present?
              fields << { title: I18n.t(:label_comment),
                          value: build_mentions(Messenger.markup_format(current_journal.notes)),
                          short: false }
            end
            fields << { title: I18n.t(:field_is_private), short: true } if current_journal.private_notes?
            fields.compact!
            attachment[:fields] = fields if fields.any?

            Messenger.speak l(:label_messenger_issue_updated,
                              project_url: Messenger.project_url_markdown(project),
                              url: send_messenger_mention_url(project, description),
                              user: current_journal.user),
                            channels, url, attachment: attachment, project: project
          ensure
            ::I18n.locale = initial_language
          end
        end

        private

        def messenger_to_be_notified
          to_be_notified = (notified_users + notified_watchers).compact
          to_be_notified.uniq
        end

        def send_messenger_mention_url(project, text)
          mention_to = ''
          if Messenger.setting_for_project(project, :auto_mentions) ||
             Messenger.textfield_for_project(project, :default_mentions).present?
            mention_to = Messenger.mentions project, text
          end
          if current_journal.nil?
            "<#{Messenger.object_url self}|#{Messenger.markup_format self}>#{mention_to}"
          else
            "<#{Messenger.object_url self}#change-#{current_journal.id}|#{Messenger.markup_format self}>#{mention_to}"
          end
        end

        def get_slack_mention_code(user)
          slack_mention_user_code = "@#{user.login}"

          ucf_slack_user_id = UserCustomField.find_by_name("Slack User ID")
          cfv_slack_user_id = user.custom_field_value(ucf_slack_user_id)
          slack_mention_user_code = "<@#{cfv_slack_user_id}>" unless cfv_slack_user_id.blank?

          return slack_mention_user_code
        end

        def build_mentions(text)
          # Retrieve the mentioned Redmine usernames from the given text
          mentioned_usernames = extract_usernames text

          # Slack usernames to be mentioned
          slack_user_mention_codes = to_slack_usernames(mentioned_usernames)
          text.gsub(Regexp.union(slack_user_mention_codes.keys), slack_user_mention_codes)
        end

        def extract_usernames text = ''
          # Extracts the @xxxxx from the given text and returns a list of usernames (only xxxxx parts)

          if text.nil?
            text = ''
          end

          # slack usernames may only contain lowercase letters, numbers,
          # dashes and underscores and must start with a letter or number.
          text.scan(/@[a-z0-9][a-z0-9_\-\.@.]*/).uniq.each do |username|
            # Remove the leading @
            username.slice!(0)
          end
        end

        def to_slack_usernames(usernames)
          return {} if usernames.empty?

          usernames.map { |username| ["@#{username}", find_slack_username(username)] }.to_h.compact
        end

        def find_slack_username(redmine_user)
          return nil if redmine_user.nil?

          if redmine_user.is_a? User
            user = redmine_user
          else
            user = User.find_by_login(redmine_user)
          end

          if user.present?
            return get_slack_mention_code(user)
          end
        end
      end
    end
  end
end
