# A 'chief' instance analyzes project data.  It does this by calling
# 'Detectives' (analyzers) in the right order, each of which have
# access to the evidence accumulated so far.

# Only the 'chief' decides when to update the proposed changes.
# Currently it just runs sequentially, but the plan is for it to use
# the Detective INPUTS and OUTPUTS to determine what order to run, and
# run them in parallel in an appropriate order.

require 'set'

class Chief
  def initialize(project)
    @evidence = Evidence.new(project)
  end

  # TODO: Identify classes automatically and do topological sort.
  ALL_DETECTIVES =
    [GithubBasicDetective, HowAccessRepoFilesDetective, FileCheckDetective,
     OssLicenseDetective]

  # List fields allowed to be written into Project (an ActiveRecord).
  # TODO: Automatically determine allowed fields, or get from elsewhere.
  ALLOWED_FIELDS =
    [:name, :license,
     :oss_license_osi_status, :oss_license_osi_justification,
     :contribution_status, :contribution_justification,
     :oss_license_status, :oss_license_justification,
     :changelog_status, :changelog_justification].to_set

  # Given two changesets, produce merged "best" version
  # When confidence is the same, c1 wins.
  def merge_changeset(c1, c2)
    result = c1.dup
    c2.each do |field, data|
      if !result.key?(field) ||
         (field[:confidence] > result[field][:confidence])
        result[field] = data
      end
    end
    result
  end

  # Should we should update a project's value for 'key'?
  def update_value?(project, key, changeset_data)
    return false if changeset_data.blank?
    !project.attribute_present?(key) || project[key].blank? ||
      (project[key] == '?') || (changeset_data[:confidence] == 5)
  end

  # Return the best estimates for fields, given project & current proposal.
  def compute_current(fields, project, current_proposal)
    result = {}
    fields.each do |f|
      if update_value?(project, f, current_proposal)
        result[f] = current_proposal[f][:value]
      elsif project.attribute_present?(f)
        result[f] = project[f]
      end
    end
    result
  end

  # Analyze project and reply with a changeset in the form
  # { fieldname1: { value: value, confidence: 1..5, explanation: text}, ...}
  # Do this by determining the right order and way to invoke "detectives"
  # for this project, invoke them, and process their results.
  def propose_changes
    current_proposal = {} # Current best changeset.
    # TODO: Create topographical sort and Real loop over detectives.
    ALL_DETECTIVES.each do |d|
      current_data_for_d = compute_current(d::INPUTS, @evidence.project,
                                           current_proposal)
      result = d.new.analyze(@evidence, current_data_for_d)
      current_proposal = merge_changeset(current_proposal, result)
    end
    current_proposal
  end

  # Given project data, return it with the proposed changeset applied.
  # Note: This should probably be class-level
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/PerceivedComplexity
  def apply_changes(project, changes)
    changes.each do |key, data|
      next unless ALLOWED_FIELDS.include?(key)
      next unless update_value?(project, key, data)
      # Store change:
      project[key] = data[:value]
      # Now add the explanation, if we can.
      next unless key.to_s.end_with?('_status') && data.key?(:explanation)
      justification_key =
        (key.to_s.chomp('_status') + '_justification').to_sym
      if project.attribute_present?(justification_key)
        unless project[justification_key].end_with?(data[:explanation])
          project[justification_key] =
            project[justification_key] + ' ' + data[:explanation]
        end
      else
        project[justification_key] = data[:explanation]
      end
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # Given form data about a project, return an improved version.
  def autofill
    apply_changes(@evidence.project, propose_changes)
  end
end