#!/usr/bin/perl -w

use strict;

use Test::More tests => 31;
use Test::Fatal qw( dies_ok );
use Test::HexString;
use Test::Refcount;

use Tangence::Constants;

use t::Conversation;

use Tangence::Meta::Type;
use constant TYPE_INT => Tangence::Meta::Type->new( "int" );
use constant TYPE_STR => Tangence::Meta::Type->new( "str" );

$Tangence::Message::SORT_HASH_KEYS = 1;

my $client = TestClient->new();

# Initialisation
{
   is_hexstr( $client->recv_message, $C2S{INIT}, 'client stream initially contains MSG_INIT' );

   $client->send_message( $S2C{INITED} );

   is_hexstr( $client->recv_message, $C2S{GETROOT} . $C2S{GETREGISTRY}, 'client stream contains MSG_GETROOT and MSG_GETREGISTRY' );

   $client->send_message( $S2C{GETROOT} );
   $client->send_message( $S2C{GETREGISTRY} );
}

my $objproxy = $client->rootobj;

my $bagproxy;

# Methods
{
   my $result;
   $objproxy->call_method(
      method => "method",
      args   => [ 10, "hello" ],
      on_result => sub { $result = shift },
   );

   is_hexstr( $client->recv_message, $C2S{CALL}, 'client stream contains MSG_CALL' );

   $client->send_message( $S2C{CALL} );

   is( $result, "10/hello", 'result of call_method()' );

   dies_ok( sub { $objproxy->call_method(
                    method => "no_such_method",
                    args   => [ 123 ],
                    on_result => sub {},
                  ); },
            'Calling no_such_method fails in proxy' );
}

# Events
{
   my $event_i;
   my $event_s;
   my $subbed;
   $objproxy->subscribe_event(
      event => "event",
      on_fire => sub {
         ( $event_i, $event_s ) = @_;
      },
      on_subscribed => sub { $subbed = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{SUBSCRIBE}, 'client stream contains MSG_SUBSCRIBE' );

   $client->send_message( $S2C{SUBSCRIBED} );

   is( $subbed, 1, '$subbed after MSG_SUBSCRIBED' );

   $client->send_message( $S2C{EVENT} );

   $client->recv_message; # MSG_OK

   is( $event_i, 20, '$event_i after subscribed event' );

   dies_ok( sub { $objproxy->subscribe_event(
                    event => "no_such_event",
                    on_fire => sub {},
                  ); },
            'Subscribing to no_such_event fails in proxy' );
}

# Properties get/set
{
   is( $objproxy->prop( "s_scalar" ), 456, 'Smashed property initially set in proxy' );

   my $value;
   $objproxy->get_property(
      property => "scalar",
      on_value => sub { $value = shift },
   );

   is_hexstr( $client->recv_message, $C2S{GETPROP}, 'client stream contains MSG_GETPROP' );

   $client->send_message( $S2C{GETPROP_123} );

   is( $value, 123, '$value after get_property' );

   my $didset = 0;
   $objproxy->set_property(
      property => "scalar",
      value    => 135,
      on_done  => sub { $didset = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{SETPROP}, 'client stream contains MSG_SETPROP' );

   $client->send_message( $MSG_OK );

   is( $didset, 1, '$didset after set_property' );
}

# Properties watch
{
   my $value;
   my $watched;
   $objproxy->watch_property(
      property => "scalar",
      on_set => sub { $value = shift },
      on_watched => sub { $watched = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{WATCH}, 'client stream contains MSG_WATCH' );

   $client->send_message( $S2C{WATCHING} );

   $client->send_message( $S2C{UPDATE_SCALAR_147} );

   is( $value, 147, '$value after watch_property/set_prop_scalar' );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

   my $valuechanged = 0;
   my $secondvalue;
   $objproxy->watch_property(
      property => "scalar",
      on_set => sub {
         $secondvalue = shift;
         $valuechanged = 1
      },
      want_initial => 1,
   );

   is_hexstr( $client->recv_message, $C2S{GETPROP}, 'client stream contains MSG_GETPROP' );

   $client->send_message( $S2C{GETPROP_147} );

   is( $secondvalue, 147, '$secondvalue after watch_property with want_initial' );

   $client->send_message( $S2C{UPDATE_SCALAR_159} );

   is( $value, 159, '$value after second MSG_UPDATE' );
   is( $valuechanged, 1, '$valuechanged is true after second MSG_UPDATE' );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

   dies_ok( sub { $objproxy->get_property(
                    property => "no_such_property",
                    on_value => sub {},
                  ); },
            'Getting no_such_property fails in proxy' );
}

# Smashed Properties
{
   my $value;
   my $watched;
   $objproxy->watch_property(
      property => "s_scalar",
      on_set => sub { $value = shift },
      on_watched => sub { $watched = 1 },
      want_initial => 1,
   );

   is( $watched, 1, 'watch_property on smashed prop is synchronous' );

   is( $value, 456, 'watch_property on smashed prop gives initial value' );

   undef $value;
   $client->send_message( $S2C{UPDATE_S_SCALAR_468} );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK after smashed prop UPDATE' );

   is( $value, 468, 'smashed prop update succeeds' );
}

# Test object destruction
{
   my $proxy_destroyed = 0;
   $objproxy->subscribe_event(
      event => "destroy",
      on_fire => sub { $proxy_destroyed = 1 },
   );

   $client->send_message( $S2C{DESTROY} );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK after MSG_DESTROY' );

   is( $proxy_destroyed, 1, 'proxy gets destroyed' );
}

is_oneref( $client, '$client has refcount 1 before shutdown' );
undef $client;

is_oneref( $objproxy, '$objproxy has refcount 1 before shutdown' );

package TestClient;

use strict;
use base qw( Tangence::Client );

sub new
{
   my $self = bless { written => "" }, shift;
   $self->identity( "testscript" );
   $self->on_error( sub { die "Test failed early - $_[0]" } );
   $self->tangence_connected( do_init => 1 );
   return $self;
}

sub tangence_write
{
   my $self = shift;
   $self->{written} .= $_[0];
}

sub send_message
{
   my $self = shift;
   my ( $message ) = @_;
   $self->tangence_readfrom( $message );
   length($message) == 0 or die "Client failed to read the whole message";
}

sub recv_message
{
   my $self = shift;
   my $message = $self->{written};
   $self->{written} = "";
   return $message;
}
