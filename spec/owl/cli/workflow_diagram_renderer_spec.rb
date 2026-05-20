# frozen_string_literal: true

require 'owl/cli/internal/commands/workflow_diagram_renderer'

RSpec.describe Owl::Cli::Internal::Commands::WorkflowDiagramRenderer do
  describe '.render in live mode' do
    let(:base_steps) do
      [
        { id: 'brief',   status: 'pending', ready: false, current: false, optional: false, requires: [],
          creates: ['brief'] },
        { id: 'specify', status: 'pending', ready: false, current: false, optional: false, requires: ['brief'],
          creates: ['spec'] },
        { id: 'design',  status: 'pending', ready: false, current: false, optional: true,  requires: ['specify'],
          creates: ['design'] },
        { id: 'plan',    status: 'pending', ready: false, current: false, optional: false, requires: ['specify'],
          creates: ['tasks'] },
        { id: 'apply',   status: 'pending', ready: false, current: false, optional: false, requires: ['plan'],
          creates: [] },
        { id: 'verify',  status: 'pending', ready: false, current: false, optional: false, requires: ['apply'],
          creates: ['verification'] },
        { id: 'publish', status: 'pending', ready: false, current: false, optional: false, requires: ['verify'],
          creates: [] },
        { id: 'archive', status: 'pending', ready: false, current: false, optional: false, requires: ['publish'],
          creates: [] }
      ]
    end

    it 'renders all-pending with empty progress bar and current-less plan' do
      data = {
        mode: :live,
        task: { id: 'TASK-0042', title: 'Add dark mode toggle', workflow_key: 'feature' },
        steps: base_steps.dup.tap { |steps| steps[0][:ready] = true },
        progress: { done: 0, total: 8, pct: 0.0 },
        blockers: []
      }
      out = described_class.render(data)
      expect(out).to include('TASK-0042 "Add dark mode toggle"   workflow: feature   ·········· 0/8 (0%)')
      expect(out).to include('[ ] brief')
      expect(out).to include('[ ] archive')
      expect(out).to include('Blockers: none')
      expect(out).not_to include('← current')
    end

    it 'renders partial-done with one current step and downstream requires' do
      steps = base_steps.dup
      steps[0] = steps[0].merge(status: 'done')
      steps[1] = steps[1].merge(status: 'done')
      steps[3] = steps[3].merge(ready: true, current: true)
      data = {
        mode: :live,
        task: { id: 'TASK-0042', title: 'Add dark mode toggle', workflow_key: 'feature' },
        steps: steps,
        progress: { done: 2, total: 8, pct: 25.0 },
        blockers: []
      }
      out = described_class.render(data)
      expect(out).to include('━━━·······')
      expect(out).to include('2/8 (25%)')
      expect(out).to include('[✓] brief')
      expect(out).to include('[✓] specify')
      expect(out).to include('[▶] plan')
      expect(out).to include('← current')
      expect(out).to include('→ tasks')
      expect(out).to include('requires: plan')
    end

    it 'renders all-done with full progress bar' do
      steps = base_steps.map { |s| s.merge(status: 'done') }
      data = {
        mode: :live,
        task: { id: 'TASK-0042', title: 'Done feature', workflow_key: 'feature' },
        steps: steps,
        progress: { done: 8, total: 8, pct: 100.0 },
        blockers: []
      }
      out = described_class.render(data)
      expect(out).to include('━━━━━━━━━━ 8/8 (100%)')
      expect(out).not_to include('[ ]')
      expect(out).not_to include('[▶]')
      expect(out).to include('Blockers: none')
    end

    it 'marks optional steps with (optional) suffix' do
      steps = base_steps.dup
      data = {
        mode: :live,
        task: { id: 'TASK-1', title: 't', workflow_key: 'feature' },
        steps: steps,
        progress: { done: 0, total: 8, pct: 0.0 },
        blockers: []
      }
      out = described_class.render(data)
      expect(out).to match(/\[ \] design\s+→ design\s+\(optional\)/)
    end

    it 'lists blockers when failed/blocked steps exist' do
      steps = base_steps.dup
      steps[3] = steps[3].merge(status: 'failed')
      data = {
        mode: :live,
        task: { id: 'TASK-1', title: 't', workflow_key: 'feature' },
        steps: steps,
        progress: { done: 0, total: 8, pct: 0.0 },
        blockers: [{ id: 'plan', status: 'failed' }]
      }
      out = described_class.render(data)
      expect(out).to include('[!] plan')
      expect(out).to include('Blockers: plan')
    end
  end

  describe '.render in abstract mode' do
    it 'renders the workflow header and pending-only step list, no blockers/progress' do
      data = {
        mode: :abstract,
        workflow_key: 'feature',
        steps: [
          { id: 'brief',   status: 'pending', ready: false, current: false, optional: false, requires: [],
            creates: ['brief'] },
          { id: 'specify', status: 'pending', ready: false, current: false, optional: false, requires: ['brief'],
            creates: ['spec'] }
        ]
      }
      out = described_class.render(data)
      expect(out).to include('workflow: feature   (2 steps)')
      expect(out).to include('[ ] brief')
      expect(out).to include('[ ] specify')
      expect(out).not_to include('Blockers')
      expect(out).not_to include('━')
      expect(out).not_to include('·')
    end
  end

  describe '.render with unknown mode' do
    it 'raises ArgumentError' do
      expect { described_class.render(mode: :weird) }.to raise_error(ArgumentError)
    end
  end

  describe '.render with step variants' do
    let(:variant_step) do
      {
        id: 'brief', status: 'pending', ready: true, current: true, optional: false,
        requires: [], creates: ['brief'],
        variants: %w[feature root_cause problem_inventory],
        default_variant: 'feature',
        chosen_variant: 'root_cause'
      }
    end

    it 'prints a variants sub-line marking [default] and the chosen one' do
      data = {
        mode: :live,
        task: { id: 'TASK-0001', title: 't', workflow_key: 'feature' },
        steps: [variant_step],
        progress: { done: 0, total: 1, pct: 0.0 },
        blockers: []
      }
      out = described_class.render(data)
      expect(out).to include('variants: feature [default]  ·  root_cause ←  ·  problem_inventory')
    end

    it 'omits the chosen-variant marker in abstract mode' do
      step = variant_step.merge(chosen_variant: nil, current: false, ready: false)
      data = { mode: :abstract, workflow_key: 'feature', steps: [step] }
      out = described_class.render(data)
      expect(out).to include('variants: feature [default]  ·  root_cause  ·  problem_inventory')
      expect(out).not_to include('←')
    end

    it 'prints nothing extra for steps without variants' do
      step = { id: 'plain', status: 'pending', ready: false, current: false, optional: false,
               requires: [], creates: [] }
      data = { mode: :abstract, workflow_key: 'feature', steps: [step] }
      out = described_class.render(data)
      expect(out).not_to include('variants:')
    end
  end
end
