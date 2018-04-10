class Intouch::TelegramBot < TelegramCommon::Bot
  def initialize(command)
    @logger = Logger.new(Rails.root.join('log/intouch', 'bot.log'))
    @command = command.is_a?(Telegram::Bot::Types::Message) ? command : Telegram::Bot::Types::Update.new(command).message
  end

  def call
    group_create_process if !private_command? && group_chat.new_record?
    super
  end

  def update
    private_command? ? private_update_process : group_update_process
  end

  def notify
    user = account.user

    (send_message(I18n.t('intouch.bot.subscription_failure')) && return) if user.blank?

    if command_arguments.blank?
      send_message(I18n.t('intouch.bot.subscription'), params: { reply_markup: subscriptions_keyboard(Project.where(Project.visible_condition(user)).pluck(:name)) })
      return
    end

    (clear_subscriptions && return) if command_arguments == 'clear'

    project = Project.find_by(name: command_arguments)

    (send_message(I18n.t('intouch.bot.subscription_failure')) && return) if project.blank?

    if IntouchSubscription.find_or_create_by(project_id: project.id, user_id: user.id)
      send_message(I18n.t('intouch.bot.subscription_success'))
    else
      send_message(I18n.t('intouch.bot.subscription_failure'))
    end
  end

  private

  def private_update_process
    update_account
    send_message(I18n.t('intouch.bot.private.update.message'))
  end

  def group_create_process
    group_chat.save
    send_message(I18n.t('intouch.bot.group.start.message'))
    logger.info "New group #{chat.title} added!"
  end

  def group_update_process
    group_chat.update title: chat.title
    send_message(I18n.t('intouch.bot.group.update.message'))
    logger.info "#{user.first_name} renamed group title #{chat.title}"
  end

  def group_chat
    @group_chat ||= fetch_group_chat
  end

  def fetch_group_chat
    TelegramGroupChat.where(tid: chat_id.abs).first_or_initialize(title: chat.title)
  end

  def clear_subscriptions
    IntouchSubscription.where(user_id: account.user.id).destroy_all
    send_message(I18n.t('intouch.bot.subscription_success'))
  end

  def subscriptions_keyboard(project_names)
    Telegram::Bot::Types::ReplyKeyboardMarkup.new(
      keyboard: [*project_names, 'clear'].map { |name| "/notify #{name}" }.each_slice(2).to_a,
      one_time_keyboard: true,
      resize_keyboard: true
    )
  end

  def chat
    command.chat
  end

  def private_commands
    %w[notify update help]
  end

  def group_commands
    %w[update help]
  end

  def private_help_message
    ['Redmine Intouch:', help_command_list(private_commands, namespace: 'intouch', type: 'private')].join("\n")
  end

  def group_help_message
    ['Redmine Intouch:', help_command_list(group_commands, namespace: 'intouch', type: 'group')].join("\n")
  end

  def command_arguments
    command.text.match(/^\/\w+ (.+)$/).try(:[], 1)
  end

  def bot_token
    Intouch.bot_token
  end

  def bot
    @bot ||= ::Telegram::Bot::Client.new(bot_token)
  end
end
