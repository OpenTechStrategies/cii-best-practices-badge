class SessionsController < ApplicationController
  include SessionsHelper

  def new
  end

  def create
    if request.env['omniauth.auth'].present?
      omniauth_login
    elsif params[:session][:provider] == 'local'
      local_login
    else
      flash.now[:danger] = 'Incorrect login information'
      render 'new'
    end
  end

  def destroy
    log_out if logged_in?
    redirect_to root_url
    flash[:success] = 'Signed out!'
  end

  private

  # rubocop:disable Metrics/AbcSize
  def local_login
    user = User.find_by provider: 'local',
                        email: params[:session][:email].downcase
    if user && user.authenticate(params[:session][:password])
      login_procedure(user)
      params[:session][:remember_me] == '1' ? remember(user) : forget(user)
    else
      flash.now[:danger] = 'Invalid email/password combination'
      render 'new'
    end
  end
  # rubocop:enable Metrics/AbcSize

  def omniauth_login
    auth = request.env['omniauth.auth']
    user = User.find_by(provider: auth['provider'], uid: auth['uid']) ||
           User.create_with_omniauth(auth)
    session[:user_token] = auth['credentials']['token']
    login_procedure(user)
  end

  def login_procedure(user)
    log_in user
    redirect_back_or root_url
    flash[:success] = 'Signed in!'
  end
end
