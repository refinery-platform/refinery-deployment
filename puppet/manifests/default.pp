$appuser = "vagrant"
$virtualenv = "/home/${appuser}/.virtualenvs/refinery-platform"
$venvpath = "${virtualenv}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/opt/vagrant_ruby/bin"
$refinery_platform = "/vagrant/refinery-platform"
$requirements = "${refinery_platform}/requirements.txt"
$project_root = "${refinery_platform}/refinery"
$ui_app_root = "${project_root}/ui"
$repo_url = "git@github.com:parklab/refinery-platform.git"

#TODO: peg packages to specific versions
class venvdeps {
  package { 'build-essential': }
  package { 'libncurses5-dev': }
  package { 'libldap2-dev': }
  package { 'libsasl2-dev': }
}
include venvdeps

package { 'java':
  name => 'openjdk-7-jre-headless',
}  # required by solr
package { 'curl': }  # required by rabbitmq installer

package { 'virtualenvwrapper': }
->
file_line {"virtualenvwrapper_config":
  path => "/home/${appuser}/.profile",
  line => "source /etc/bash_completion.d/virtualenvwrapper",
}

# temp workaround from https://github.com/puppetlabs/puppetlabs-postgresql/issues/348
class { 'concat::setup':
  before => Class['postgresql::server'],
}
class { 'postgresql::globals':
  version => '9.1',
  encoding => 'UTF8',
  locale => 'en_US.utf8',
}
class { 'postgresql::server':
}
class { 'postgresql::lib::devel':
}
postgresql::server::db { 'refinery':
  user => $appuser,
  password => '',
}

file { "/home/${appuser}/.ssh/config":
  ensure => file,
  source => "/vagrant/ssh-config",
  owner => $appuser,
  group => $appuser,  
}
->
vcsrepo { $refinery_platform:
  ensure => present,
  provider => git,
  source => $repo_url,
  user => $appuser,
  group => $appuser,
}

class { 'python':
  version => 'system',
  pip => true,
  dev => true,
  virtualenv => true,
}
~>
python::virtualenv { $virtualenv:
  ensure => present,
  requirements => $requirements,
  owner => $appuser,
  group => $appuser,
  require => [
               Class['venvdeps'],
               Class['postgresql::lib::devel'],
               Vcsrepo[$refinery_platform],
             ]
}
->
file { "venv_project_conf":
  # workaround for setvirtualenvproject command not found
  ensure => file,
  path => "${virtualenv}/.project",
  content => $project_root,
  owner => $appuser,
  group => $appuser,
}
->
exec { "supervisord":
  command => "${virtualenv}/bin/supervisord",
  cwd => $project_root,
  creates => "/tmp/supervisord.pid",
  user => $appuser,
  group => $appuser,
}

file { [
        "${refinery_platform}/media",
        "${refinery_platform}/static",
        "${refinery_platform}/isa-tab",
        ]:
  ensure => directory,
  owner => $appuser,
  group => $appuser,
  require => Vcsrepo[$refinery_platform],
}

exec { "syncdb":
  command => "python ${project_root}/manage.py syncdb --migrate --noinput",
  path => $venvpath,
  user => $appuser,
  group => $appuser,
  require => [
               File["${refinery_platform}/media"],
               Python::Virtualenv[$virtualenv],
               Postgresql::Server::Db["refinery"]
             ],
}
->
exec { "init_refinery":
  command => "python ${project_root}/manage.py init_refinery 'Refinery' '192.168.50.50:8000'",
  path => $venvpath,
  user => $appuser,
  group => $appuser,
}
->
exec {
  "build_core_schema":
    command => "python ${project_root}/manage.py build_solr_schema --using=core > solr/core/conf/schema.xml",
    cwd => $project_root,
    path => $venvpath,
    user => $appuser,
    group => $appuser;
  "build_data_set_manager_schema":
    command => "python ${project_root}/manage.py build_solr_schema --using=data_set_manager > solr/data_set_manager/conf/schema.xml",
    cwd => $project_root,
    path => $venvpath,
    user => $appuser,
    group => $appuser;
}

$solr_version = "4.4.0"
$solr_archive = "solr-${solr_version}.tgz"
$solr_url = "http://archive.apache.org/dist/lucene/solr/${solr_version}/${solr_archive}"
exec { "solr_wget":
  command => "wget ${solr_url} -O /usr/src/${solr_archive}",
  creates => "/usr/src/${solr_archive}",
  path => "/usr/bin:/bin",
  timeout => 600,
}
->
exec { "solr_unpack":
  command => "mkdir -p /opt && tar -xzf /usr/src/${solr_archive} -C /opt && chown -R ${appuser}:${appuser} /opt/solr-${solr_version}",
  creates => "/opt/solr-${solr_version}",
  path => "/usr/bin:/bin",
}
->
file { "/opt/solr":
  ensure => link,
  target => "solr-${solr_version}",
}

# configure rabbitmq
class { '::rabbitmq':
  package_ensure => installed,
  service_ensure => running,
  port => '5672',
  require => Package['curl'],
}
rabbitmq_user { 'guest':
  password => 'guest',
  require => Class['::rabbitmq'],
}
rabbitmq_vhost { 'localhost':
  ensure => present,
  require => Class['::rabbitmq'],
}
rabbitmq_user_permissions { 'guest@localhost':
  configure_permission => '.*',
  read_permission => '.*',
  write_permission => '.*',
  require => [ Rabbitmq_user['guest'], Rabbitmq_vhost['localhost'] ]
}

file { "${project_root}/supervisord.conf":
  ensure => file,
  source => "${project_root}/supervisord.conf.sample",
  owner => $appuser,
  group => $appuser,
  require => Vcsrepo[$refinery_platform],
}

include apt
# need a version of Node that's more recent than one included with Ubuntu 12.04
apt::ppa { 'ppa:chris-lea/node.js': }

package { 'nodejs':
  name => 'nodejs',
  require => Apt::Ppa['ppa:chris-lea/node.js'],
}
->
package {
  'bower': ensure => '1.3.8', provider => 'npm';
  'jshint': ensure => '2.4.4', provider => 'npm';
  'grunt-cli': ensure => '0.1.13', provider => 'npm';
}

package { 'libapache2-mod-wsgi': }
->
file { "/etc/apache2/sites-available/refinery":
  ensure => file,
  content => template("/vagrant/apache.conf"),
}
->
file { "/etc/apache2/sites-enabled/001-refinery":
  ensure => link,
  target => "../sites-available/refinery",
}
~>
service { 'apache2':
  ensure => running,
  hasrestart => true,
}
