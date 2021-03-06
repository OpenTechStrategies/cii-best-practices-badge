require 'json'

# If it's a GitHub repo, grab easily-acquired data from GitHub API and
# use it to determine key values for project.

# WARNING: The JSON parser generates a 'normal' Ruby hash.
# Be sure to use strings, NOT symbols, as a key when accessing JSON-parsed
# results (because strings and symbols are distinct in basic Ruby).

# frozen_string_literal: true

class GithubBasicDetective < Detective
  # Individual detectives must identify their inputs, outputs
  INPUTS = [:repo_url].freeze
  OUTPUTS = [:name, :license].freeze

  # These are the 'correct' display case for SPDX for OSI-approved licenses.
  LICENSE_CORRECT_CASE = {
    'APACHE-2.0' => 'Apache-2.0',
    'ARTISTIC-2.0' => 'Artistic-2.0',
    'BSD-3-CLAUSE' => 'BSD-3-Clause',
    'BSD-2-CLAUSE' => 'BSD-2-Clause',
    'EUDATAGRID' => 'EUDatagrid',
    'ENTESSA' => 'Entessa',
    'FAIR' => 'Fair',
    'FRAMEWORX-1.0' => 'Frameworx-1.0',
    'MIROS' => 'MirOS',
    'MOTOSOTO' => 'Motosoto',
    'MULTICS' => 'Multics',
    'NAUMEN' => 'Naumen',
    'NOKIA' => 'Nokia',
    'POSTGRESQL' => 'PostgreSQL',
    'PYTHON-2.0' => 'Python-2.0',
    'CNRI-PYTHON' => 'CNRI-Python',
    'SIMPL-2.0' => 'SimPL-2.0',
    'SLEEPYCAT' => 'Sleepycat',
    'WATCOM-1.0' => 'Watcom-1.0',
    'WXWINDOWS' => 'WXwindows',
    'XNET' => 'Xnet',
    'ZLIB' => 'Zlib'
  }.freeze

  # Clean up name of license to be like the SPDX display.
  def cleanup_license(license)
    return nil if license.nil?
    license = license.upcase
    license = LICENSE_CORRECT_CASE[license] if LICENSE_CORRECT_CASE[license]
    license
  end

  # Individual detectives must implement "analyze"
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def analyze(evidence, current)
    repo_url = current[:repo_url]
    return {} if repo_url.nil?

    results = {}
    # Has form https://github.com/:user/:name?
    # e.g.: https://github.com/linuxfoundation/cii-best-practices-badge
    # Note: this limits what's accepted, otherwise we'd have to worry
    # about URL escaping.
    # Rubocop misinterprets and thinks we don't use the match.
    # rubocop:disable Performance/RedundantMatch
    repo_url.match(
      %r{\Ahttps://github.com/([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)/?\Z}) do |m|
      # We have a github repo.
      results[:repo_track_status] = {
        value: 'Met', confidence: 4,
        explanation: 'Repository on GitHub, which uses git. ' \
          'git can track the changes, ' \
          'who made them, and when they were made.' }
      results[:repo_distributed_status] = {
        value: 'Met', confidence: 4,
        explanation: 'Repository on GitHub, which uses git. ' \
          'git is distributed.' }
      results[:contribution_status] = {
        value: 'Met', confidence: 2,
        explanation: 'Projects on GitHub by default use issues and ' \
          'pull requests, as encouraged by documentation such as ' \
          '<https://guides.github.com/activities/contributing-to-open-source/>.'
      }

      # Get basic evidence using GET, e.g.:
      # https://api.github.com/repos/linuxfoundation/cii-best-practices-badge
      fullname = m[1] + '/' + m[2]
      basic_repo_data_raw = evidence.get(
        'https://api.github.com/repos/' + fullname)
      unless basic_repo_data_raw.blank?
        basic_repo_data = JSON.parse(basic_repo_data_raw)
        if basic_repo_data['description'] &&
           basic_repo_data['description'].to_s.length < 60
          # Short description, it's probably really the name.
          results[:name] = {
            value: basic_repo_data['description'],
            confidence: 3, explanation: 'GitHub name' }
        else
          if basic_repo_data['name']
            results[:name] = {
              value: basic_repo_data['name'],
              confidence: 3, explanation: 'GitHub name' }
          end
          if basic_repo_data['description']
            results[:description] = {
              value: basic_repo_data['description'],
              confidence: 3, explanation: 'GitHub description' }
          end
        end
      end

      # We'll ask GitHub what the license is.  This is a "preview"
      # API subject to change without notice, and doesn't do much analysis,
      # but it's a quick win to figure it out.
      license_data_raw = evidence.get(
        'https://api.github.com/repos/' + fullname + '/license')
      license_data = JSON.parse(license_data_raw) if license_data_raw
      if license_data_raw && license_data['license'].present? &&
         license_data['license']['key'].present?
        # TODO: GitHub doesn't reply with the expected upper/lower case
        # for SPDX; see:
        # https://github.com/benbalter/licensee/issues/72
        # For now, we'll upcase and then fix common cases.
        license = cleanup_license(license_data['license']['key'])
        results[:license] = {
          value: license,
          confidence: 3, explanation: 'GitHub API license analysis' }
      end
    end

    results
  end
end
