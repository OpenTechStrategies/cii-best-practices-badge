# rubocop:disable Metrics/ClassLength
class ProjectsController < ApplicationController
  before_action :set_project, only: [:edit, :update, :destroy, :show]
  before_action :logged_in?, only: :create
  before_action :authorized, only: [:destroy, :edit, :update]

  helper_method :repo_data

  # GET /projects
  # GET /projects.json
  def index
    @projects = Project.all.paginate(page: params[:page]) # per_page: 5
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
  end

  def badge
    @project = Project.find(params[:id])
    respond_to do |format|
      status = Project.badge_achieved?(@project) ? 'passing' : 'failing'
      format.svg do
        send_file Rails.application.assets["badge-#{status}.svg"].pathname,
                  disposition: 'inline'
      end
    end
  end

  # GET /projects/new
  def new
    @project = Project.new
  end

  # GET /projects/:id/edit(.:format)
  def edit
  end

  # POST /projects
  # POST /projects.json
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def create
    @project = current_user.projects.build(project_params)

    # Error out if project_homepage_url and repo_url are both empty... don't
    # do a save yet.

    @project.project_homepage_url ||= set_homepage_url
    Chief.new(@project).autofill

    respond_to do |format|
      if @project.save
        flash[:success] = "Thanks for adding the Project!   Please fill out
                           the rest of the information to get the Badge."
        format.html { redirect_to edit_project_path(@project) }
        format.json { render :show, status: :created, location: @project }
      else
        format.html { render :new }
        format.json do
          render json: @project.errors, status: :unprocessable_entity
        end
      end
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # PATCH/PUT /projects/1
  # PATCH/PUT /projects/1.json
  # rubocop:disable Metrics/MethodLength
  def update
    old_badge_status = Project.badge_achieved_id?(params[:id])
    Chief.new(@project).autofill
    respond_to do |format|
      if @project.update(project_params)
        successful_update(format, old_badge_status)
      else
        format.html { render :edit }
        format.json do
          render json: @project.errors, status: :unprocessable_entity
        end
      end
    end
  end
  # rubocop:enable Metrics/MethodLength

  def successful_update(format, old_badge_status)
    format.html do
      redirect_to @project, success: 'Project was successfully updated.'
    end
    format.json { render :show, status: :ok, location: @project }
    new_badge_status = Project.badge_achieved?(@project)
    if new_badge_status != old_badge_status
      # TODO: Eventually deliver_later
      ReportMailer.project_status_change(
        @project, old_badge_status, new_badge_status).deliver_now
    end
  end

  # DELETE /projects/1
  # DELETE /projects/1.json
  def destroy
    @project.destroy
    respond_to do |format|
      @project.project_homepage_url ||= project_find_default_url
      format.html do
        redirect_to projects_url
        flash[:success] = 'Project was successfully deleted.'
      end
      format.json { head :no_content }
    end
  end

  def repo_data
    github = Github.new oauth_token: session[:user_token], auto_pagination: true
    github.repos.list.map do |repo|
      if repo.blank?
        nil
      else
        [repo.full_name, repo.fork, repo.homepage, repo.html_url]
      end
    end.compact
  end

  private

  PERMITTED_PARAMS = (Project::PROJECT_OTHER_FIELDS +
                     Project::ALL_CRITERIA_STATUS +
                     Project::ALL_CRITERIA_JUSTIFICATION).freeze

  def set_homepage_url
    # Assign to repo.homepage if it exists, and else repo_url
    repo = repo_data.find { |r| @project.repo_url == r[3] }
    return nil if repo.nil?
    repo[2].present? ? repo[2] : @project.repo_url
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_project
    @project = Project.find(params[:id])
  end

  # Never trust parameters from the scary internet,
  # only allow the white list through.
  def project_params
    params.require(:project).permit(PERMITTED_PARAMS)
  end

  def authorized
    if !current_user
      redirect_to root_url
    elsif current_user.admin?
      true
    else
      @project = current_user.projects.find_by(id: params[:id])
      redirect_to root_url if @project.nil?
    end
  end
end
