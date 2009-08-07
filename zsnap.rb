#!/usr/local/bin/ruby -w
# Copyright (c) 2008, Marcin Simonides
# Copyright (c) 2009, Marius Nuennerich
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'yaml'
require 'time'

module Zsnap

CONFIG_FILE_NAME = '/usr/local/etc/zfs-snapshot-mgmt.conf'
CONFIG_SIZE_MAX = 64 * 1024     # just a safety limit

class Rule
  def initialize(args = {})
    args = { 'offset' => 0, 'at_multiple' => 60 }.merge(args)
    @at_multiple = args['at_multiple'].to_i
    @offset = args['offset'].to_i
  end

  def condition_met?(time_minutes)
    divisor = @at_multiple
    (divisor == 0) or ((time_minutes - @offset) % divisor) == 0
  end
end

class PreservationRule < Rule
  def initialize(args = {})
    super(args)
    args = { 'for_minutes' => 240 }.merge(args)
    @for_minutes = args['for_minutes'].to_i
  end

  def applies?(now_minutes, creation_time_minutes)
    (now_minutes - creation_time_minutes) < @for_minutes
  end

  def condition_met_for_snapshot?(now_minutes, snapshot)
    creation_time_minutes = snapshot.creation_time_minutes
    applies?(now_minutes, creation_time_minutes) and
      condition_met?(creation_time_minutes)
  end
end

class SnapshotInfo
  def initialize(name, fs_name, snapshot_prefix)
    @name = name
    @fs_name = fs_name
    @creation_time = parse_timestamp(name[snapshot_prefix.length .. -1])
  end

  def self.new_snapshot(fs_name, snapshot_prefix)
    name = snapshot_prefix + Time.now.strftime('%Y-%m-%d_%H.%M')
    new(name, fs_name, snapshot_prefix)
  end

  def creation_time_minutes
    @creation_time.to_i / 60
  end

  # Returns canonical name of the snapshot and FS (as accepted by zfs command)
  # e.g.: /tank/usr@snapshot
  def canonical_name
    if @fs_name and @name
      @fs_name + '@' + @name
    else
      raise "SnapshotInfo doesn't contain name and/or fs_name"
    end
  end

  private

  def parse_timestamp(time_string)
    date, time = time_string.split('_')
    year, month, day = date.split('-')
    hour, minute = time.split('.')
    Time.mktime(year, month, day, hour, minute)
  end
end

class FSInfo
  def initialize(fs_name, values = {})
    @name = fs_name
    @mount_point = get_mount_point(fs_name)
    raise "Filesystem #{fs_name} has no creation rule" unless values['creation_rule']
    raise "Filesystem #{fs_name} has no preservation rules" unless values['preservation_rules']

    @creation_rule = Rule.new(values['creation_rule'])
    @preservation_rules = values['preservation_rules'].map do |value|
      PreservationRule.new(value)
    end
    @is_recursive = values['recursive'] ? true : false
  end

  def create?(now_minutes)
    @creation_rule.condition_met?(now_minutes)
  end

  def snapshots(prefix)
    path = File.join(@mount_point, '.zfs', 'snapshot')
    Dir.open(path).select do |name|
      name[0, prefix.length] == prefix
    end.map { |name| SnapshotInfo.new(name, @name, prefix) }
  end

  def snapshots_to_remove(now_minutes, prefix)
    snapshots(prefix).reject do |snapshot|
      @preservation_rules.any? do |rule|
        rule.condition_met_for_snapshot?(now_minutes, snapshot)
      end
    end
  end

  def remove_snapshots(now_minutes, prefix)
    snapshots_to_remove(now_minutes, prefix).each do |s|
      remove_snapshot(s)
    end
  end

  def create_snapshot(now_minutes, prefix)
    if create?(now_minutes)
      create_snapshot_from_info(SnapshotInfo.new_snapshot(name, prefix))
    end
  end

  def pool
    # More or less according to ZFS Component Naming Requirements
    # http://docs.sun.com/app/docs/doc/819-5461/gbcpt
    @name[/\A[a-zA-Z_:.-]+/]
  end

  private

  def remove_snapshot(snapshot_info)
    arguments = @is_recursive ? '-r ' : ''
    system 'zfs destroy ' + arguments + snapshot_info.canonical_name
  end

  def create_snapshot_from_info(snapshot_info)
    arguments = @is_recursive ? '-r ' : ''
    system 'zfs snapshot ' + arguments + snapshot_info.canonical_name
  end

  def get_mount_point(fs_name)
    `zfs mount`.collect { |line| line.split(' ') }.
      select { |item| item.first == fs_name }.collect { |item| item.last }.first
  end
end

class Config
  attr_reader :snapshot_prefix, :filesystems

  def initialize(value)
    @snapshot_prefix = value['snapshot_prefix']
    @filesystems = value['filesystems'].map { |key, val| FSInfo.new(key, val) }
    @pools = @filesystems.map { |fs| fs.pool }.uniq
  end

  def busy_pools
    @busy_pools ||= @pools.select do |pool|
      `zpool status #{pool}`.any? { |line| line =~ /(scrub|resilver) in progress/ }
    end
  end
end

end
