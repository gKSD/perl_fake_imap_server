#!/usr/bin/perl -I/home/sofia/mailru/perl_fake_imap_server

=begin
use FakeImapServer;

our $fake_imap_server = FakeImapServer->new(conf_file => 'config.conf');

$fake_imap_server->run();
=cut

use fake_imap_server;


#our $fake_imap_server = fake_imap_server->new(config_file => 'config.conf', host => 'localhost', port => 8080);
#$fake_imap_server->run();

our $fake_imap_server = fake_imap_server->new(host => 'omnoomno', scenario => 'scenario.txt');
$fake_imap_server->run(config_file => 'config.conf', host => 'localhost', port => 8081);
1;
