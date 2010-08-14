use 5.010001;
use ExtUtils::MakeMaker;
use lib 'inc';

use ExtUtils::AutoInstall (
        -core           => [            # mandatory modules          # any version would suffice
	"Carp"   => '',
	"Dir::Self"   => '',
	"Config::Any"   => '',
	"Perl6::Say"   => '',
	"Switch"   => '',
	"threads::shared"   => '',
	"IO::Socket::INET"   => '',
	"IO::Select"   => '',
	"IO::Socket"   => '',
	"List::Util"   => '',
	"DBIx::Class::Schema"   => '',
	"URI::Split"   => '',
	"Data::Dumper"   => '',
	"Data::Serializer"   => '',
	"Readonly"   => '',
	"File::Path"   => '',
	"LWP::RobotUA"   => '',
	"URI::Escape"   => '',
	"Digest::MurmurHash"   => '',
	"HTML::LinkExtractor"   => '',
	"URI::Escape"   => '',
	"IO::Compress::Gzip"   => '',
	"Encode"   => '',
	"Date::Parse"   => '',
	"File::Path"   => '',
	"IPC::Run3"   => '',
	"Data::Page"   => '',
	"DBIx::Simple"   => '',
	"Net::Server::PreFork"   => ''
        ]
    );
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'MCrawler',
    VERSION_FROM      => 'lib/MCrawler.pm', # finds $VERSION
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/MCrawler.pm', # retrieve abstract from module
       AUTHOR         => 'aditya <aditya@>') : ()),
);
