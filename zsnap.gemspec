Gem::Specification.new do |s|
  s.name = "zsnap"
  s.version = "0.1.0"

  s.authors = ["Marcin Simonides", "Marius Nuennerich"]
  s.email = "marius@nuenneri.ch"
  s.homepage = "http://github.com/marius/zsnap"
  s.summary = "A script to automatically create and delete zfs snapshots from cron"

  s.files = ["INSTALL", "test/zsnap_test.rb", "lib/zsnap.rb",
    "conf/zfs-snapshot-mgmt.conf.sample", "bin/zfs-snapshot-mgmt", "doc/zfs-snapshot-mgmt.8"]
  s.executables = ["zfs-snapshot-mgmt"]
  s.test_files = ["test/zsnap_test.rb"]
end
