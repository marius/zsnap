require 'test/unit'
require 'lib/zsnap'

include Zsnap

class RuleTest < Test::Unit::TestCase
  def test_rule
    r = Rule.new
    2.times do
      assert r.condition_met?(0)
      assert r.condition_met?(60)
      assert r.condition_met?(120)
      (1..59).each do |i|
       assert !r.condition_met?(i)
      end
      r = Rule.new 'at_multiple' => 60
    end
  end

  def test_rule_with_offset
    r = Rule.new 'at_multiple' => 60, 'offset' => 4
    assert r.condition_met?(4)
    assert r.condition_met?(64)
    assert r.condition_met?(124)
    (5..63).each do |i|
     assert !r.condition_met?(i)
    end
  end
end

class PreservationRuleTest < Test::Unit::TestCase
  def test_create
    p = PreservationRule.new
    assert p.applies?(239, 0)
    assert !p.applies?(240, 0)
    assert !p.applies?(241, 0)
  end

  def test_condition_met
    p = PreservationRule.new
    s = SnapshotInfo.new 'foo-2009-08-05_21.00', 'bar', 'foo-'
    assert p.condition_met_for_snapshot? 17, s

  end
end

class SnapshotInfoTest < Test::Unit::TestCase
  def test_create
    s = SnapshotInfo.new 'foo-2009-08-05_21.42', 'bar', 'foo-'
    assert_equal 20825022, s.creation_time_minutes
    assert_equal 'bar@foo-2009-08-05_21.42', s.canonical_name
  end

  def test_raises_error
    s = SnapshotInfo.new 'foo-2009-08-05_21.42', nil, 'foo-'
    assert_raise(RuntimeError) { s.canonical_name }
  end
end

class FSInfoTest < Test::Unit::TestCase
  def test_create
    rules = {
              'creation_rule' => {'at_multiple' => 60, 'offset' => 0 },
              'preservation_rules' => [
                { 'for_minutes' => 240, 'at_multiple' => 0, 'offset' => 0 }
              ]
            }
    f = FSInfo.new 'tank/foo', rules
    assert f.create?(60)
# Mock here
#    assert_equal 'ff', f.send(:get_mount_point, 'tank/foo')
  end
end
