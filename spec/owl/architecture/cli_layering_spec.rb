# frozen_string_literal: true

# Architecture guard for the §4 / §148 layering rule (docs/agents/
# 27_Owl_Ruby_code_architecture.md): the CLI layer must reach domains only
# through their public `Owl::<Domain>::Api` facades and never touch a domain's
# private `::Internal::*` service objects. The CLI's own `Cli::Internal::*`
# namespace is exempt (it is the CLI's private implementation, not cross-domain).
#
# The doc records this rule as enforced "by grep"; this spec turns that manual
# grep into a standing CI gate so the debt cannot silently regrow.
RSpec.describe 'CLI layering (architecture §148)' do
  cli_root = File.expand_path('../../../lib/owl/cli', __dir__)

  it 'has no cross-domain ::Internal:: references under lib/owl/cli/' do
    offenders = Dir.glob("#{cli_root}/**/*.rb").flat_map do |path|
      File.foreach(path).with_index(1).filter_map do |line, no|
        next unless line.include?('::Internal::')
        next if line.include?('Cli::Internal') # the CLI's own private namespace is allowed

        rel = path.sub("#{File.expand_path('../../..', __dir__)}/", '')
        "#{rel}:#{no}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      The CLI layer must call domains via their public `Api` facade, not their
      private `::Internal::*` objects (architecture §4/§148). Offending lines:
        #{offenders.join("\n  ")}
    MSG
  end
end
